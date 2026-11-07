-- =====================================================
--  System Card 1x1 (Elysium flat)
--  CPU history sparkline on top, then ram / bat / tmp bars.
-- =====================================================

local M = {}
local flat = dofile(os.getenv("HOME") .. "/.config/conky/Common/flat.lua")

-- =====================================================
-- Config
-- =====================================================
local CARD_W = 134
local CARD_H = 134

local PAD_X   = 12
local BAR_H   = 3
local BAR_GAP = 4

-- CPU row: label and value share a baseline, graph sits under it
local CPU_Y     = 23
local SPARK_Y   = 31
local SPARK_H   = 30
local HIST_N    = 48     -- one sample per tick, so ~48s of history

-- Lower rows: baseline of the label/value text
local rows = {
    { name = "memperc",         label = "ram", y = 82  },
    { name = "battery_percent", label = "bat", y = 101 },
    { name = "cpu_temp",        label = "tmp", y = 120 },
}

-- Samples live here between ticks (the module is loaded once)
local hist = {}
local last_push = 0

local function push_sample(v)
    local now = os.time()
    if now == last_push then return end   -- draw can run twice in a second
    last_push = now
    hist[#hist + 1] = v
    if #hist > HIST_N then table.remove(hist, 1) end
end

local function rgba(colour, alpha)
    colour = tonumber((colour:gsub("#", "0x")))
    return ((colour / 0x10000) % 0x100) / 255.,
           ((colour / 0x100) % 0x100) / 255.,
           (colour % 0x100) / 255.,
           alpha
end

-- Bar colour follows severity, not identity: a calm CPU should not be red
local function level_color(theme, name, value)
    if name == "cpu"             then return theme.level(value, 60, 85) end
    if name == "memperc"         then return theme.level(value, 70, 90) end
    if name == "battery_percent" then return theme.level(value, 40, 20, true) end
    return theme.level(value, 70, 85)
end

-- "5.21GiB" -> "5.2G"
local function short_size(str)
    local num, unit = (str or ""):match("([%d%.]+)%s*(%a)")
    if not num then return "?" end
    return string.format("%.1f%s", tonumber(num), unit)
end

local function value_of(rt, name)
    if name == "memperc"         then return (rt.ram and rt.ram.percent) or 0 end
    if name == "battery_percent" then return rt.battery_percent or 0 end
    return rt.cpu_temp or 0
end

local function value_text(rt, name)
    if name == "memperc" then
        local r = rt.ram or {}
        return short_size(r.used) .. "/" .. short_size(r.total)
    end
    if name == "battery_percent" then return string.format("%d%%", rt.battery_percent or 0) end
    return string.format("%d°", rt.cpu_temp or 0)
end

-- =====================================================
-- CPU sparkline: filled area under a line, dot on the newest sample
-- =====================================================
local function draw_spark(cr, x, y, w, h, colour, theme)
    -- baseline and a faint 50% guide
    flat.set_color(cr, theme.bar_bg)
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, x, math.floor(y + h) + 0.5)
    cairo_line_to(cr, x + w, math.floor(y + h) + 0.5)
    cairo_stroke(cr)
    flat.set_color(cr, theme.bar_bg, 0.5)
    cairo_move_to(cr, x, math.floor(y + h / 2) + 0.5)
    cairo_line_to(cr, x + w, math.floor(y + h / 2) + 0.5)
    cairo_stroke(cr)

    local n = #hist
    if n < 2 then return end

    -- newest sample pinned to the right edge, history scrolls left
    local step = w / (HIST_N - 1)
    local x0 = x + w - (n - 1) * step
    local function px(i) return x0 + (i - 1) * step end
    -- scale to the recent peak so an idle CPU still draws a readable line
    local ceil = 30
    for i = 1, n do ceil = math.max(ceil, hist[i]) end
    ceil = math.min(100, ceil * 1.15)
    local function py(v) return y + h - h * math.max(0, math.min(v / ceil, 1)) end

    local r, g, b = rgba(colour, 1)

    cairo_move_to(cr, px(1), y + h)
    for i = 1, n do cairo_line_to(cr, px(i), py(hist[i])) end
    cairo_line_to(cr, px(n), y + h)
    cairo_close_path(cr)
    local fill = cairo_pattern_create_linear(0, y, 0, y + h)
    cairo_pattern_add_color_stop_rgba(fill, 0, r, g, b, 0.38)
    cairo_pattern_add_color_stop_rgba(fill, 1, r, g, b, 0.02)
    cairo_set_source(cr, fill)
    cairo_fill(cr)
    cairo_pattern_destroy(fill)

    cairo_set_source_rgba(cr, r, g, b, 1)
    cairo_set_line_width(cr, math.max(1, h / 20))
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
    cairo_move_to(cr, px(1), py(hist[1]))
    for i = 2, n do cairo_line_to(cr, px(i), py(hist[i])) end
    cairo_stroke(cr)

    cairo_arc(cr, px(n), py(hist[n]), math.max(1.5, h / 14), 0, 2 * math.pi)
    cairo_fill(cr)
end

-- =====================================================
-- Draw
-- =====================================================
function M.draw(ctx)
    local cr, s, ox, oy, theme = ctx.cr, ctx.s, ctx.x, ctx.y, ctx.theme
    local rt = ctx.runtime or {}

    flat.card_at(cr, ox, oy, CARD_W, CARD_H)

    local left_x  = ox + s(PAD_X)
    local right_x = ox + s(CARD_W) - s(PAD_X)
    local inner_w = s(CARD_W) - 2 * s(PAD_X)

    -- CPU header: dim label, big coloured value
    local cpu = (rt.cpu and rt.cpu.percent) or 0
    push_sample(cpu)
    local cpu_col = level_color(theme, "cpu", cpu)

    flat.font(cr, "Exo 2", s(10))
    flat.text(cr, left_x, oy + s(CPU_Y), "cpu", theme.dim)
    flat.font(cr, "JetBrains Mono", s(13), true)
    flat.text_right(cr, right_x, oy + s(CPU_Y), string.format("%d%%", cpu), cpu_col)

    draw_spark(cr, left_x, oy + s(SPARK_Y), inner_w, s(SPARK_H), cpu_col, theme)

    -- ram / bat / tmp: label, value, tick bar
    local charging = (rt.battery_status or ""):lower():find("^charg") ~= nil
    for _, row in ipairs(rows) do
        local y = oy + s(row.y)
        local value = value_of(rt, row.name)
        local col = level_color(theme, row.name, value)

        flat.font(cr, "Exo 2", s(10))
        flat.text(cr, left_x, y, row.label, theme.dim)
        if row.name == "battery_percent" and charging then
            flat.text(cr, left_x + flat.width(cr, "bat "), y, "+", theme.green)
        end
        flat.text_right(cr, right_x, y, value_text(rt, row.name), theme.text)

        local max = 100
        if row.name == "cpu_temp" and (rt.cpu_unit or "°C") == "°F" then max = 212 end
        local pct = math.max(0, math.min(value / max, 1))
        flat.ticks_at(cr, left_x, y + s(BAR_GAP), inner_w, s(BAR_H), pct, col)
    end
end

return M
