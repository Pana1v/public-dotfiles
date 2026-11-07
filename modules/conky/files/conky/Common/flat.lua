require 'cairo'
-- conky 1.20+ ships the X11 surface functions in their own module.
pcall(require, 'cairo_xlib')

-- =====================================================
--  Shared flat-panel helpers for the right-column widgets.
--  Same look as Linear/Elysium: greyscale, color only for state.
--  Load with: local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
-- =====================================================

-- One instance per conky process: a wing window embeds several widgets, and its
-- suppress_card/accent_icons settings must reach all of them.
if rawget(_G, "RICE_FLAT") then return RICE_FLAT end

local M = {}

M.theme = {
    bg     = "#0a0506",
    glass  = "#1a0b0d",   -- glass panel tint: a step above bg so it reads over a black sky
    bar_bg = "#2a1013",
    text   = "#ffe9eb",
    red    = "#ff3b1f",
    green  = "#52e5ff",
    yellow = "#ffc14d",
    dim    = "#b86a72",
    faint  = "#8a3a44",
}
-- Highlight colour for chrome (section icons, dividers, glow). switch-theme.sh
-- rewrites this line from the palette's @conky_accent (green for most palettes).
M.theme.accent = "#ff1f3d"

-- "personal" (default) or "professional". Set PROFILE=professional in
-- ~/.config/dotfiles/local.env (or CONKY_PROFILE in the environment); it is read
-- once per window, so restart the widgets after changing it. Personal things
-- (Google Tasks) stay off the screen in the professional profile.
function M.profile()
    local env = os.getenv("CONKY_PROFILE")
    if env and env ~= "" then return env end
    local f = io.open((os.getenv("HOME") or "") .. "/.config/dotfiles/local.env", "r")
    if not f then return "personal" end
    local value = "personal"
    for line in f:lines() do
        local v = line:match("^%s*PROFILE%s*=%s*[\"']?(%w+)[\"']?")
        if v then value = v end
    end
    f:close()
    return value
end

-- Set by the wing windows: their frame draws the glass, so embedded widgets
-- skip their own card, and section icons take the accent colour.
M.suppress_card = false
M.accent_icons = false

M.PAD = 16
M.RULE_Y = 38          -- header hairline; content starts below ~46
local CARD_ALPHA = 0.90   -- frosted glass, 90% opaque
local BRACKET = 10     -- corner bracket arm length
local BRACKET_W = 1.5
local TITLE_TRACK = 2  -- extra px between header letters
local STATUS_TRACK = 0.5
local TICK_W, TICK_GAP = 2, 2

local function rgb(colour, alpha)
    colour = tonumber((colour:gsub("#", "0x")))
    return ((colour / 0x10000) % 0x100) / 255.,
           ((colour / 0x100) % 0x100) / 255.,
           (colour % 0x100) / 255.,
           alpha
end

M.rgb = rgb

-- Load ramp for glowing edges, same stops as the sysmon-flair panel extension:
-- the dim role at idle, accent when busy, yellow at 80%, red when pinned.
-- Returns a hex string so it drops into set_color like any theme colour.
function M.edge_color(t)
    t = math.max(0, math.min(1, t))
    local stops = { { 0, M.theme.faint }, { 0.55, M.theme.accent }, { 0.8, M.theme.yellow }, { 1, M.theme.red } }
    for i = 2, #stops do
        local p1, c1 = stops[i][1], stops[i][2]
        if t <= p1 then
            local p0, c0 = stops[i - 1][1], stops[i - 1][2]
            local f = (t - p0) / (p1 - p0)
            local out = "#"
            for k = 2, 6, 2 do
                local a, b = tonumber(c0:sub(k, k + 1), 16), tonumber(c1:sub(k, k + 1), 16)
                out = out .. string.format("%02x", math.floor(a + (b - a) * f + 0.5))
            end
            return out
        end
    end
    return stops[#stops][2]
end

function M.set_color(cr, colour, alpha)
    local r, g, b, a = rgb(colour, alpha or 1)
    cairo_set_source_rgba(cr, r, g, b, a)
end

function M.rounded_rect(cr, x, y, w, h, r)
    if r > h / 2 then r = h / 2 end
    if r > w / 2 then r = w / 2 end
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r, r, -math.pi / 2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
    cairo_arc(cr, x + r, y + h - r, r, math.pi / 2, math.pi)
    cairo_arc(cr, x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cairo_close_path(cr)
end

-- HUD card: translucent "frosted glass" panel with two slanted corners
-- (top right, bottom left) and brackets that follow the outline.
--       ┌─────────╲
--       │          ╲
--        ╲          │
--         ╲─────────┘
-- Real blur comes from Blur My Shell when the compositor allows it; the
-- sheen, hairline edge and low alpha carry the look when it does not.
local CUT = 16

local function card_path(cr, w, h, cut)
    cairo_move_to(cr, 0, 0)
    cairo_line_to(cr, w - cut, 0)
    cairo_line_to(cr, w, cut)
    cairo_line_to(cr, w, h)
    cairo_line_to(cr, cut, h)
    cairo_line_to(cr, 0, h - cut)
    cairo_close_path(cr)
end

function M.card(cr, w, h)
    if M.suppress_card then return end
    local cut = math.min(CUT, w / 4, h / 4)

    card_path(cr, w, h, cut)
    M.set_color(cr, M.theme.glass, CARD_ALPHA)
    cairo_fill_preserve(cr)

    -- Frost: light falls from the top left and fades across the panel.
    local sheen = cairo_pattern_create_linear(0, 0, w * 0.7, h)
    cairo_pattern_add_color_stop_rgba(sheen, 0, 1, 1, 1, 0.075)
    cairo_pattern_add_color_stop_rgba(sheen, 0.45, 1, 1, 1, 0.02)
    cairo_pattern_add_color_stop_rgba(sheen, 1, 1, 1, 1, 0.0)
    cairo_set_source(cr, sheen)
    cairo_fill(cr)
    cairo_pattern_destroy(sheen)

    -- Glass edge: a faint light hairline just inside the outline.
    local i = BRACKET_W / 2
    cairo_save(cr)
    cairo_translate(cr, i, i)
    card_path(cr, w - 2 * i, h - 2 * i, cut)
    cairo_restore(cr)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.07)
    cairo_set_line_width(cr, 1)
    cairo_stroke(cr)

    -- Brackets: plain L at the square corners, bent around the slanted ones.
    M.set_color(cr, M.theme.dim)
    cairo_set_line_width(cr, BRACKET_W)
    cairo_move_to(cr, i, i + BRACKET)
    cairo_line_to(cr, i, i)
    cairo_line_to(cr, i + BRACKET, i)
    cairo_move_to(cr, w - i, h - i - BRACKET)
    cairo_line_to(cr, w - i, h - i)
    cairo_line_to(cr, w - i - BRACKET, h - i)
    cairo_move_to(cr, w - cut - BRACKET, i)
    cairo_line_to(cr, w - cut, i)
    cairo_line_to(cr, w - i, cut)
    cairo_line_to(cr, w - i, cut + BRACKET)
    cairo_move_to(cr, i, h - cut - BRACKET)
    cairo_line_to(cr, i, h - cut)
    cairo_line_to(cr, cut, h - i)
    cairo_line_to(cr, cut + BRACKET, h - i)
    cairo_stroke(cr)
end

-- Elysium modules place cards with s() offsets instead of cairo_scale;
-- scale here so bracket length and line width match the panels.
function M.card_at(cr, x, y, w, h)
    cairo_save(cr)
    cairo_translate(cr, x, y)
    cairo_scale(cr, M.SCALE, M.SCALE)
    M.card(cr, w, h)
    cairo_restore(cr)
end

-- Same idea for ticks: Elysium passes device-pixel geometry.
function M.ticks_at(cr, x, y, w, h, frac, colour)
    cairo_save(cr)
    cairo_translate(cr, x, y)
    cairo_scale(cr, M.SCALE, M.SCALE)
    M.ticks(cr, 0, 0, w / M.SCALE, h / M.SCALE, frac, colour)
    cairo_restore(cr)
end

-- face: "Exo 2" body, "JetBrains Mono" numbers, "Orbitron" titles
function M.font(cr, face, size, bold)
    local weight = bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL
    cairo_select_font_face(cr, face, CAIRO_FONT_SLANT_NORMAL, weight)
    cairo_set_font_size(cr, size)
end

local ext = cairo_text_extents_t:create()

-- Material Design glyphs from Symbols Nerd Font (fonts-cursors module).
M.icons = {
    calendar = 0xF00ED, agenda = 0xF00F0, clock = 0xF0954, pin = 0xF034E,
    video = 0xF0567, repeat_ = 0xF0456,
    headset = 0xF02CB, mouse = 0xF037D, keyboard = 0xF030C, gamepad = 0xF0297,
    phone = 0xF011C, battery = 0xF0079, charging = 0xF0084, devices = 0xF00AF,
    speaker = 0xF04C3, mic = 0xF036C, mic_off = 0xF036D, muted = 0xF0581,
    music = 0xF075A, play = 0xF040A, pause = 0xF03E4,
    sun = 0xF0599, cloud = 0xF0590, rain = 0xF0597, snow = 0xF0598, storm = 0xF0593,
    thermo = 0xF050F, drop = 0xF058C, wind = 0xF059D,
    github = 0xF02A4, pr = 0xF062C, robot = 0xF06A9, chip = 0xF061A,
    server = 0xF048B, check = 0xF012C, alert = 0xF0026, issue = 0xF05D6,
}

-- Draw a glyph from M.icons (or a raw code point) at baseline (x, y).
-- Returns its advance so callers can lay text after it.
function M.icon(cr, x, y, name, size, colour)
    local cp = M.icons[name] or name
    cairo_select_font_face(cr, "Symbols Nerd Font Mono", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    local glyph = utf8.char(cp)
    M.set_color(cr, colour)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, glyph)
    cairo_text_extents(cr, glyph, ext)
    return ext.x_advance
end

function M.width(cr, s)
    cairo_text_extents(cr, s, ext)
    return ext.x_advance
end

function M.text(cr, x, y, s, colour)
    M.set_color(cr, colour)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, s)
end

function M.text_right(cr, right_x, y, s, colour)
    M.text(cr, right_x - M.width(cr, s), y, s, colour)
end

-- Trim with "..." until s fits max_w in the current font.
-- Cuts on character boundaries: slicing through the middle of a multi-byte
-- letter (the E in MEXICO) hands cairo invalid UTF-8, which puts the whole
-- context into an error state and silently stops all later drawing.
function M.fit(cr, s, max_w)
    if M.width(cr, s) <= max_w then return s end
    while (utf8.len(s) or #s) > 1 and M.width(cr, s .. "...") > max_w do
        local last = utf8.len(s) and utf8.offset(s, -1) or #s
        s = s:sub(1, last - 1)
    end
    return s .. "..."
end

-- Cairo's toy text API has no letter spacing, so place glyphs one by one.
-- Sum the glyphs one by one, the same way spaced() draws them, so centring is exact.
function M.spaced_width(cr, s, track)
    local w, n = 0, 0
    for _, cp in utf8.codes(s) do
        w = w + M.width(cr, utf8.char(cp))
        n = n + 1
    end
    return w + track * math.max(n - 1, 0)
end

function M.spaced(cr, x, y, s, colour, track)
    M.set_color(cr, colour)
    for _, cp in utf8.codes(s) do
        local ch = utf8.char(cp)
        cairo_move_to(cr, x, y)
        cairo_show_text(cr, ch)
        x = x + M.width(cr, ch) + track
    end
end

-- Header row shared by every panel, all caps:
--   FLEET                2/7 ONLINE
--   ─────────────────────────────── RULE_Y
-- Status is trimmed to the space the title leaves. Leaves the mono font
-- selected, so callers must set their own font afterwards.
function M.header(cr, w, title, status, status_colour, icon)
    title = title:upper()
    local x0 = M.PAD
    if icon then x0 = x0 + M.icon(cr, M.PAD, 29, icon, 14, M.accent_icons and M.theme.accent or M.theme.dim) + 8 end
    M.font(cr, "Orbitron", 11, true)
    M.spaced(cr, x0, 28, title, M.theme.text, TITLE_TRACK)
    local title_w = M.spaced_width(cr, title, TITLE_TRACK) + (x0 - M.PAD)
    M.hline(cr, M.PAD, w - M.PAD, M.RULE_Y)
    if not status or status == "" then return end

    status = status:upper()
    M.font(cr, "JetBrains Mono", 10)
    local max_w = w - 2 * M.PAD - title_w - 16
    while utf8.len(status) > 1 and M.spaced_width(cr, status, STATUS_TRACK) > max_w do
        status = status:sub(1, utf8.offset(status, -1) - 1)
    end
    local x = w - M.PAD - M.spaced_width(cr, status, STATUS_TRACK)
    M.spaced(cr, x, 28, status, status_colour or M.theme.faint, STATUS_TRACK)
end

-- Segmented bar: whole ticks only, lit share = frac.
--   ||||||||::::::::::::
function M.ticks(cr, x, y, w, h, frac, colour)
    local n = math.floor((w + TICK_GAP) / (TICK_W + TICK_GAP))
    local lit = math.floor(n * math.max(0, math.min(frac, 1)) + 0.5)
    for i = 0, n - 1 do
        M.set_color(cr, i < lit and colour or M.theme.bar_bg)
        cairo_rectangle(cr, x + i * (TICK_W + TICK_GAP), y, TICK_W, h)
        cairo_fill(cr)
    end
end

function M.hline(cr, x1, x2, y)
    M.set_color(cr, M.theme.bar_bg)
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, x1, y + 0.5)
    cairo_line_to(cr, x2, y + 0.5)
    cairo_stroke(cr)
end

-- Split exec output into rows of tab-separated fields.
function M.rows(out)
    local rows = {}
    for line in out:gmatch("[^\n]+") do
        local fields = {}
        for f in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = f end
        rows[#rows + 1] = fields
    end
    return rows
end

function M.format_age(seconds)
    if seconds < 90 then return string.format("%ds ago", seconds) end
    return string.format("%dm ago", math.floor(seconds / 60))
end

-- Snapshot written by Common/feeds.py (conky-feeds.service). Reading a
-- file is the only safe I/O here: io.popen segfaults conky, and ${exec}
-- from Lua returns empty on most ticks.
--   rows = nil until the first snapshot exists
--   last_success = epoch of the last successful fetch ("ts" line)
local CACHE = os.getenv("CONKY_CACHE") or (os.getenv("HOME") .. "/.cache/conky/")

function M.snapshot(name)
    local s = { rows = nil, last_success = nil }

    function s.update()
        local f = io.open(CACHE .. name .. ".tsv", "r")
        if not f then return end
        local out = f:read("a")
        f:close()

        local rows = M.rows(out)
        if not rows[1] or rows[1][1] ~= "ts" then return end
        s.last_success = tonumber(rows[1][2])
        table.remove(rows, 1)
        s.rows = rows
    end

    return s
end

-- Set by Common/start-widget.sh from the target monitor's height.
-- Panels draw in 1x units; cairo_scale maps them to the window.
local SCALE = tonumber(os.getenv("CONKY_SCALE")) or 1.0
M.SCALE = SCALE

-- Cairo setup/teardown around a draw(cr, w, h) function.
-- w, h are in 1x units (window size / SCALE).
--
-- Preview (no X window needed): CONKY_PREVIEW="<w>x<h>:<out.png>" draws one
-- frame on a dark mock desktop and writes it to a PNG. See Common/preview.sh.
local PREVIEW = os.getenv("CONKY_PREVIEW")

local function render_preview(tag, draw)
    local w, h, path = PREVIEW:match("^(%d+)x(%d+):(.+)$")
    if not w then return end
    w, h = tonumber(w), tonumber(h)
    local pad = 24
    local cs = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w + 2 * pad, h + 2 * pad)
    local cr = cairo_create(cs)
    M.set_color(cr, "#101114")
    cairo_paint(cr)
    cairo_translate(cr, pad, pad)
    local ok, err = pcall(draw, cr, w, h)
    if not ok then io.stderr:write("[" .. tag .. "] draw error: " .. tostring(err) .. "\n") end
    cairo_surface_write_to_png(cs, path)
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

function M.render(tag, draw)
    if not conky_window then
        if PREVIEW then render_preview(tag, draw) end
        return
    end

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
        io.stderr:write("[" .. tag .. "] draw error: " .. tostring(err) .. "\n")
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

RICE_FLAT = M
return M
