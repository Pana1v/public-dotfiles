require 'cairo'
-- conky 1.20+ ships the X11 surface functions in their own module.
pcall(require, 'cairo_xlib')

-- ============================================================
-- Elysium Widget Orchestrator
-- Drives all 5 Closebox73 module cards via Cairo/Lua
-- ============================================================

local BASE = os.getenv("HOME") .. "/.config/conky/Elysium/modules/"

-- ---- Theme (flat greyscale; color = state only) ----------
local theme = {
    bg     = "#0a0506",  -- flat panel fill
    bar_bg = "#2a1013",  -- tracks, hairlines, empty graph area
    text   = "#ffe9eb",  -- primary text, values, bar fills, hands
    dim    = "#b86a72",  -- labels, headers, units
    faint  = "#8a3a44",  -- tertiary: other-month days, ticks
    red    = "#ff3b1f",  -- bad state
    green  = "#52e5ff",  -- highlight: bar fills, today, live states
    blue   = "#ffe9eb",  -- same as text so legacy blue usages go greyscale
    orange = "#ffc14d",  -- warn state (yellow despite key name)
}
-- CALD module calls theme.get_color("name") as a function
theme.get_color = function(name) return theme[name] end

-- Colour a gauge by how worrying its value is. Higher is worse by default;
-- pass lower_is_worse for things like battery charge.
theme.level = function(value, warn, bad, lower_is_worse)
    if lower_is_worse then
        if value <= bad then return theme.red end
        if value <= warn then return theme.orange end
        return theme.green
    end
    if value >= bad then return theme.red end
    if value >= warn then return theme.orange end
    return theme.green
end

theme.card_alpha = 0.90   -- shared by every widget; wallpaper shows through

-- ---- Scale (set by Common/start-widget.sh per monitor) ---
local SCALE = tonumber(os.getenv("CONKY_SCALE")) or 1.0
local function s(v) return math.floor(v * SCALE + 0.5) end

-- ---- Card dimensions and grid gap --------------------------
local CARD = 134   -- px per card (defined by all modules)
local GAP  = 8     -- px between cards

-- ---- Widget layout: {module_dir, col, row} -----------------
-- Col 0 = left column, Col 1 = right column
-- Layout (3 x 134 + 2 x 8 = 418, the panel width):
--   [CLCK] [SYST] [DISK]
--   [NETW] [ TZCL 2 wide ]
local layout = {
    { dir = "CLCK_1x1_C01", col = 0, row = 0 },  -- analog clock
    { dir = "SYST_1x1_S01", col = 1, row = 0 },  -- CPU/RAM/batt/temp bars
    { dir = "DISK_1x1_D01", col = 2, row = 0 },  -- disk usage bars
    { dir = "NETW_1x1_N01", col = 0, row = 1 },  -- network rates
    { dir = "TZCL_1x1_T01", col = 1, row = 1 },  -- IST / CET dual clock
}

-- ---- Load module Lua files once at startup -----------------
local loaded = {}
for _, entry in ipairs(layout) do
    local path = BASE .. entry.dir .. "/module.lua"
    local ok, mod = pcall(dofile, path)
    if ok and type(mod) == "table" then
        loaded[#loaded + 1] = { mod = mod, col = entry.col, row = entry.row }
    else
        io.stderr:write("[Elysium] failed to load: " .. path
            .. "\n  " .. tostring(mod) .. "\n")
    end
end

-- ---- Collect live data each tick ---------------------------
local function get_runtime()
    -- Highest reading across all kernel thermal zones (÷1000 → °C).
    -- thermal_zone0 is not reliably the CPU package sensor -- its index
    -- is assignment order from the kernel/firmware, which varies by
    -- board, so a hardcoded zone0 can silently report a cool peripheral
    -- sensor instead of the hottest one. Taking the max across every
    -- zone is robust to that and still surfaces the number a user
    -- actually cares about: how hot is anything in this machine.
    local temp_raw = tonumber(conky_parse(
        "${exec cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -rn | head -1}")) or 0

    -- Active network interface from default route
    local iface_raw = conky_parse(
        "${exec ip route show default 2>/dev/null | awk '/default/{print $5; exit}'}")
    local iface = (iface_raw or ""):match("^%s*(.-)%s*$")
    if not iface or iface == "" then iface = "wlp0s20f3" end

    local net_type = "none"
    if     iface:match("^wl")  then net_type = "wifi"
    elseif iface:match("^e")   then net_type = "lan"
    elseif iface:match("^usb") then net_type = "usb"
    end

    -- Disk used in KB (for format_size in DISK module)
    local root_kb = tonumber(conky_parse(
        "${exec df / | awk 'NR==2{print $3}'}")) or 0
    local home_kb = tonumber(conky_parse(
        "${exec df /home | awk 'NR==2{print $3}'}")) or 0

    -- Whether / and /home are the same filesystem (common when there's
    -- no separate /home partition). The DISK module uses this to avoid
    -- showing two identical bars for what is really one disk.
    local root_dev = conky_parse("${exec df --output=source / 2>/dev/null | tail -1}")
    local home_dev = conky_parse("${exec df --output=source /home 2>/dev/null | tail -1}")
    local same_fs = (root_dev or ""):match("^%s*(.-)%s*$") == (home_dev or ""):match("^%s*(.-)%s*$")

    return {
        cpu             = { percent = tonumber(conky_parse("${cpu cpu0}")) or 0 },
        ram             = { percent = tonumber(conky_parse("${memperc}")) or 0,
                            used    = conky_parse("${mem}"),
                            total   = conky_parse("${memmax}") },
        battery_percent = tonumber(conky_parse("${battery_percent BAT0}")) or 0,
        battery_status  = conky_parse("${battery_status BAT0}"),
        -- round to a whole degree: some thermal zones report sub-degree
        -- precision, and the SYST module formats this with %d, which
        -- requires an exact integer in Lua 5.3+
        cpu_temp        = math.floor(temp_raw / 1000 + 0.5),
        cpu_unit        = "°C",
        net_iface       = iface,
        net_type        = net_type,
        disk = {
            root    = { percent = tonumber(conky_parse("${fs_used_perc /}")) or 0,
                        used    = root_kb },
            home    = { percent = tonumber(conky_parse("${fs_used_perc /home}")) or 0,
                        used    = home_kb },
            same_fs = same_fs,
            extra   = {},
        },
    }
end

-- ---- Draw hook (called by Conky each update_interval) ------
function conky_main()
    if not conky_window then return end

    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height)

    local cr = cairo_create(cs)

    -- Gray AA: subpixel AA leaves color fringes on ARGB windows
    local fo = cairo_font_options_create()
    cairo_font_options_set_antialias(fo, CAIRO_ANTIALIAS_GRAY)
    cairo_font_options_set_hint_style(fo, CAIRO_HINT_STYLE_SLIGHT)
    cairo_set_font_options(cr, fo)
    cairo_font_options_destroy(fo)

    -- Clear canvas to fully transparent before redraw
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER)

    local rt = get_runtime()

    for _, m in ipairs(loaded) do
        local ctx = {
            cr      = cr,
            s       = s,
            theme   = theme,
            runtime = rt,
            x       = m.col * s(CARD + GAP),
            y       = m.row * s(CARD + GAP),
        }

        -- Some modules buffer history (e.g. NETW speed graph)
        if m.mod.update then pcall(m.mod.update, ctx) end

        local ok, err = pcall(m.mod.draw, ctx)
        if not ok then
            io.stderr:write("[Elysium] draw error: " .. tostring(err) .. "\n")
        end
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
