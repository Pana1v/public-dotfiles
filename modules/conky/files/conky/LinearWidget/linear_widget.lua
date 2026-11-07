require 'cairo'
-- conky 1.20+ ships the X11 surface functions in their own module.
pcall(require, 'cairo_xlib')
local flat = dofile(os.getenv("HOME") .. "/.config/conky/Common/flat.lua")

-- =====================================================
--  Linear Active Issues — standalone large panel
--  (see fetch_issues.py for the data side)
-- =====================================================

local theme = {
    bg     = "#0a0506",
    bar_bg = "#2a1013",
    text   = "#ffe9eb",
    red    = "#ff3b1f",
    green  = "#52e5ff",
    blue   = "#ffe9eb",   -- neutral, same as text
    orange = "#ffc14d",   -- warn state, clear yellow despite the name
    dim    = "#b86a72",
    faint  = "#8a3a44",
}

local function rgb(colour, alpha)
    if type(colour) == "string" then
        colour = tonumber((colour:gsub("#", "0x")))
    end
    return ((colour / 0x10000) % 0x100) / 255.,
           ((colour / 0x100) % 0x100) / 255.,
           (colour % 0x100) / 255.,
           alpha
end

local function set_color(cr, colour, alpha)
    local r, g, b, a = rgb(colour, alpha)
    cairo_set_source_rgba(cr, r, g, b, a)
end

-- =====================================================
-- Fetch (throttled, via conky's own ${exec} — never io.popen
-- from Lua: that fights conky's SIGCHLD handling and segfaults
-- the whole process with no catchable Lua error)
-- =====================================================
local FETCH_SCRIPT = os.getenv("HOME") .. "/.config/conky/LinearWidget/fetch_issues.py"
local REFRESH_SECONDS = 300  -- 5 minutes
local WARMUP_ATTEMPTS = 4    -- conky's ${exec} needs a few ticks to warm up

local cached_issues = {}
local have_fetched_once = false
local last_fetch = 0
local last_success = nil
local attempts = 0

local function fetch_issues()
    local out = conky_parse("${exec python3 " .. FETCH_SCRIPT .. " 2>/dev/null}")
    if not out or out == "" then return nil end

    local issues = {}
    for line in out:gmatch("[^\n]+") do
        local identifier, state_type, state_name, priority_label, project, rel_time, title =
            line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
        if identifier then
            issues[#issues + 1] = {
                identifier     = identifier,
                state_type     = state_type,
                state_name     = state_name,
                priority_label = priority_label,
                project        = project,
                rel_time       = rel_time,
                title          = title,
            }
        end
    end
    return issues
end

local function update()
    local now = os.time()
    local interval = (attempts < WARMUP_ATTEMPTS) and 5 or REFRESH_SECONDS
    if now - last_fetch < interval then return end
    last_fetch = now
    attempts = attempts + 1

    local issues = fetch_issues()
    if issues and #issues > 0 then
        cached_issues = issues
        have_fetched_once = true
        last_success = now
    elseif attempts >= WARMUP_ATTEMPTS then
        cached_issues = issues or cached_issues
        have_fetched_once = true
    end
end

-- =====================================================
-- Word wrap: greedy fill up to max_lines, "..." on overflow
-- =====================================================
local function wrap_text(cr, text, max_w, max_lines)
    local words = {}
    for w in text:gmatch("%S+") do words[#words + 1] = w end

    local lines = {}
    local cur = ""
    local idx = 1
    local ext = cairo_text_extents_t:create()

    while idx <= #words and #lines < max_lines do
        local w = words[idx]
        local trial = (cur == "") and w or (cur .. " " .. w)
        cairo_text_extents(cr, trial, ext)
        if ext.width <= max_w or cur == "" then
            cur = trial
            idx = idx + 1
        else
            lines[#lines + 1] = cur
            cur = ""
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end

    if idx <= #words and #lines > 0 then
        local last = lines[#lines]
        cairo_text_extents(cr, last .. "...", ext)
        while ext.width > max_w and #last > 1 do
            last = last:sub(1, #last - 1)
            cairo_text_extents(cr, last .. "...", ext)
        end
        lines[#lines] = last .. "..."
    end
    return lines
end

-- =====================================================
-- Layout
-- =====================================================
local PAD = 16
local HEADER_H = 46
local ROW_H = 76
local ROW_GAP = 4
local FOOTER_H = 26

-- Only the issue actually being worked on stands out.
local function state_color(state_name)
    if state_name == "In Progress" then return theme.text end
    return theme.dim
end

local function format_age(seconds)
    if seconds < 90 then return string.format("%ds ago", seconds) end
    return string.format("%dm ago", math.floor(seconds / 60))
end

local function priority_color(label)
    if label == "Urgent" then return theme.red end
    if label == "High" then return theme.dim end
    return theme.faint
end

local function draw(cr, w, h)
    flat.card(cr, w, h)

    local count_str = string.format("%d active", #cached_issues)
    if last_success then
        count_str = count_str .. "  .  updated " .. format_age(os.time() - last_success)
    end
    flat.header(cr, w, "linear", count_str, nil, "check")

    if not have_fetched_once then
        set_color(cr, theme.dim, 1)
        cairo_select_font_face(cr, "Exo 2", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, 13)
        cairo_move_to(cr, PAD, HEADER_H + 20)
        cairo_show_text(cr, "loading...")
        return
    end
    if #cached_issues == 0 then
        set_color(cr, theme.dim, 1)
        cairo_select_font_face(cr, "Exo 2", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, 13)
        cairo_move_to(cr, PAD, HEADER_H + 20)
        cairo_show_text(cr, "no active issues")
        return
    end

    local y = HEADER_H
    local max_title_w = w - PAD * 2 - 14
    local id_ext = cairo_text_extents_t:create()
    local p_ext = cairo_text_extents_t:create()

    local pitch = ROW_H + ROW_GAP
    local visible = math.min(#cached_issues, math.floor((h - HEADER_H - FOOTER_H) / pitch))

    for i = 1, visible do
        local issue = cached_issues[i]
        local row_top = y

        if issue.priority_label == "Urgent" then
            set_color(cr, priority_color(issue.priority_label), 1)
            flat.rounded_rect(cr, 6, row_top + 2, 3, ROW_H - 4, 1.5)
            cairo_fill(cr)
        end

        set_color(cr, state_color(issue.state_name), 1)
        cairo_arc(cr, PAD + 3, row_top + 14, 4, 0, 2 * math.pi)
        cairo_fill(cr)

        set_color(cr, theme.text, 1)
        cairo_select_font_face(cr, "Exo 2", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, 13)
        cairo_move_to(cr, PAD + 14, row_top + 18)
        cairo_show_text(cr, issue.identifier)
        -- measure while the identifier's own face/size is still selected;
        -- measuring after switching to state_name's smaller face understated
        -- the width and made state_name overlap the identifier's tail
        cairo_text_extents(cr, issue.identifier, id_ext)

        set_color(cr, theme.dim, 1)
        cairo_select_font_face(cr, "Exo 2", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, 11)
        cairo_move_to(cr, PAD + 14 + id_ext.width + 10, row_top + 18)
        cairo_show_text(cr, issue.state_name)

        if issue.priority_label ~= "" then
            set_color(cr, priority_color(issue.priority_label), 1)
            cairo_select_font_face(cr, "Exo 2", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
            cairo_set_font_size(cr, 11)
            cairo_text_extents(cr, issue.priority_label, p_ext)
            cairo_move_to(cr, w - PAD - p_ext.width, row_top + 18)
            cairo_show_text(cr, issue.priority_label)
        end

        set_color(cr, theme.text, 1)
        cairo_select_font_face(cr, "Exo 2", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, 12)
        local lines = wrap_text(cr, issue.title, max_title_w, 2)
        local title_y = row_top + 36
        for _, line in ipairs(lines) do
            cairo_move_to(cr, PAD + 14, title_y)
            cairo_show_text(cr, line)
            title_y = title_y + 15
        end

        set_color(cr, theme.faint, 1)
        cairo_select_font_face(cr, "Exo 2", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, 10)
        local meta = issue.rel_time
        if issue.project ~= "" then meta = issue.project .. "  .  " .. meta end
        cairo_move_to(cr, PAD + 14, row_top + ROW_H - 8)
        cairo_show_text(cr, meta)

        if i < visible then
            set_color(cr, theme.bar_bg, 1)
            cairo_set_line_width(cr, 1)
            cairo_move_to(cr, PAD, row_top + ROW_H + ROW_GAP / 2)
            cairo_line_to(cr, w - PAD, row_top + ROW_H + ROW_GAP / 2)
            cairo_stroke(cr)
        end

        y = y + ROW_H + ROW_GAP
    end

    local hidden = #cached_issues - visible
    if hidden > 0 then
        set_color(cr, theme.faint, 1)
        cairo_select_font_face(cr, "Exo 2", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, 11)
        cairo_move_to(cr, PAD, h - 12)
        cairo_show_text(cr, string.format("+%d more in Linear", hidden))
    end
end

-- Set by Common/start-widget.sh from the monitor's height; draw in 1x units.
local SCALE = tonumber(os.getenv("CONKY_SCALE")) or 1.0

function conky_main()
    if not conky_window then return end
    update()

    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height)
    local cr = cairo_create(cs)

    -- Gray AA: subpixel AA fringes color on ARGB windows.
    local fo = cairo_font_options_create()
    cairo_font_options_set_antialias(fo, CAIRO_ANTIALIAS_GRAY)
    cairo_font_options_set_hint_style(fo, CAIRO_HINT_STYLE_SLIGHT)
    cairo_set_font_options(cr, fo)
    cairo_font_options_destroy(fo)

    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER)

    cairo_scale(cr, SCALE, SCALE)
    local ok, err = pcall(draw, cr, conky_window.width / SCALE, conky_window.height / SCALE)
    if not ok then
        io.stderr:write("[LinearWidget] draw error: " .. tostring(err) .. "\n")
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
