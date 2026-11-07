require 'cairo'
-- conky 1.20+ ships the X11 surface functions in their own module.
pcall(require, 'cairo_xlib')
local flat = dofile(os.getenv("HOME") .. "/.config/conky/Common/flat.lua")

-- =====================================================
--  Fleet Status — ping sweep panel
--  Reads the TSV snapshot that ping_hosts.py (fleet-ping.service)
--  rewrites every sweep. Plain file read only: no subprocess.
-- =====================================================

local theme = {
    bg     = "#0a0506",
    bar_bg = "#2a1013",
    text   = "#ffe9eb",
    red    = "#ff3b1f",
    green  = "#52e5ff",
    yellow = "#ffc14d",
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
-- Data: plain file read, throttled
-- =====================================================
local SNAPSHOT = os.getenv("HOME") .. "/.cache/conky/fleet.tsv"
local READ_SECONDS = 2
local STALE_SECONDS = 45
local LATENCY_SLOW_MS = 1000

local hosts = {}
local snapshot_ts = nil
local last_read = 0

local function read_snapshot()
    local f = io.open(SNAPSHOT, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()

    local ts = content:match("^ts\t(%d+)")
    if not ts then return nil end

    local parsed = {}
    for line in content:gmatch("[^\n]+") do
        local label, addr, status, latency = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        if label then
            parsed[#parsed + 1] = { label = label, addr = addr, up = status == "up", latency = tonumber(latency) }
        end
    end
    return tonumber(ts), parsed
end

local function update()
    local now = os.time()
    if now - last_read < READ_SECONDS then return end
    last_read = now

    local ts, parsed = read_snapshot()
    if ts then
        snapshot_ts = ts
        hosts = parsed
    end
end

-- =====================================================
-- Layout
-- =====================================================
local PAD = 16
local HEADER_H = 46
local ROW_H = 33

local function set_font(cr, face, size, bold)
    cairo_select_font_face(cr, face, CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
end

local function text_width(cr, text)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, text, ext)
    return ext.width
end

local function right_text(cr, text, right_x, y)
    cairo_move_to(cr, right_x - text_width(cr, text), y)
    cairo_show_text(cr, text)
end

local function latency_color(ms)
    if ms and ms > LATENCY_SLOW_MS then return theme.orange end
    return theme.green
end

local function count_up()
    local n = 0
    for _, host in ipairs(hosts) do
        if host.up then n = n + 1 end
    end
    return n
end

local function draw_header(cr, w)
    if not snapshot_ts then return flat.header(cr, w, "fleet", nil, nil, "server") end

    -- Count stays quiet unless something is down.
    local up, total = count_up(), #hosts
    flat.header(cr, w, "fleet", string.format("%d/%d online", up, total),
        (up < total) and theme.red or theme.faint, "server")
end

local function draw_host(cr, w, host, row_top)
    local dot_color = host.up and latency_color(host.latency) or theme.red
    set_color(cr, dot_color, 1)
    cairo_arc(cr, PAD + 4, row_top + 11, 4.5, 0, 2 * math.pi)
    cairo_fill(cr)

    set_color(cr, theme.text, host.up and 1 or 0.55)
    set_font(cr, "Exo 2", 14, false)
    cairo_move_to(cr, PAD + 18, row_top + 15)
    cairo_show_text(cr, host.label)

    set_color(cr, theme.faint, host.up and 1 or 0.6)
    set_font(cr, "Exo 2", 12, false)
    cairo_move_to(cr, PAD + 124, row_top + 15)
    cairo_show_text(cr, host.addr)

    set_font(cr, "JetBrains Mono", 12, false)
    if host.up then
        set_color(cr, latency_color(host.latency), 1)
        right_text(cr, host.latency and string.format("%.0f ms", host.latency) or "up", w - PAD, row_top + 15)
    else
        set_color(cr, theme.red, 1)
        right_text(cr, "OFFLINE", w - PAD, row_top + 15)
    end
end

local function draw_footer(cr, w, h)
    set_font(cr, "Exo 2", 10, false)

    if not snapshot_ts then
        set_color(cr, theme.orange, 1)
        cairo_move_to(cr, PAD, h - 12)
        cairo_show_text(cr, "no data - is fleet-ping.service running?")
        return
    end

    local age = math.max(0, os.time() - snapshot_ts)
    local stale = age > STALE_SECONDS
    set_color(cr, stale and theme.orange or theme.faint, 1)
    right_text(cr, string.format(stale and "STALE - updated %ds ago" or "updated %ds ago", age), w - PAD, h - 12)
end

local function draw(cr, w, h)
    flat.card(cr, w, h)

    draw_header(cr, w)

    local y = HEADER_H
    for _, host in ipairs(hosts) do
        draw_host(cr, w, host, y)
        y = y + ROW_H
    end

    draw_footer(cr, w, h)
end

-- Set by Common/start-widget.sh from the monitor's height; draw in 1x units.
local SCALE = tonumber(os.getenv("CONKY_SCALE")) or 1.0

function conky_main()
    if not conky_window then return end

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
    local ok, err = pcall(function()
        update()
        draw(cr, conky_window.width / SCALE, conky_window.height / SCALE)
    end)
    if not ok then
        io.stderr:write("[FleetStatus] error: " .. tostring(err) .. "\n")
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
