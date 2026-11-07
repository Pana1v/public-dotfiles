-- =====================================================
--  Analog Clock Card (Elysium Official Standard)
-- =====================================================

local M = {}
local flat = dofile(os.getenv("HOME") .. "/.config/conky/Common/flat.lua")

-- =====================================================
-- Config
-- =====================================================
local CARD_W = 134
local CARD_H = 134

-- =====================================================
-- Convert hex color to RGBA (Official)
-- =====================================================
local function rgb_to_r_g_b(colour, alpha)
    if type(colour) == "string" then
        colour = tonumber((colour:gsub("#","0x")))
    end
    return ((colour / 0x10000) % 0x100) / 255.,
           ((colour / 0x100) % 0x100) / 255.,
           (colour % 0x100) / 255.,
           alpha or 1
end

-- =====================================================
-- Base Layer
-- =====================================================
function M.draw_rect(ctx)
    flat.card_at(ctx.cr, ctx.x, ctx.y, CARD_W, CARD_H)
end

-- =====================================================
-- Visual Layer (Clock)
-- =====================================================
local function tick(cr, cx, cy, angle, inner, outer)
    cairo_move_to(cr, cx + inner * math.sin(angle), cy - inner * math.cos(angle))
    cairo_line_to(cr, cx + outer * math.sin(angle), cy - outer * math.cos(angle))
end

local function hand(cr, cx, cy, angle, len)
    cairo_move_to(cr, cx, cy)
    cairo_line_to(cr, cx + len * math.sin(angle), cy - len * math.cos(angle))
    cairo_stroke(cr)
end

function M.draw_visual(ctx)

    local cr    = ctx.cr
    local s     = ctx.s
    local theme = ctx.theme

    local size   = s(CARD_W)
    local cx     = ctx.x + size/2
    local cy     = ctx.y + size/2
    local radius = s(60)

    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)

    -- Hairline face, no filled dial
    local r,g,b,a = rgb_to_r_g_b(theme.bar_bg, 1)
    cairo_set_source_rgba(cr, r,g,b,a)
    cairo_set_line_width(cr, 1)
    cairo_arc(cr, cx, cy, radius, 0, 2*math.pi)
    cairo_stroke(cr)

    -- Hour ticks (faint); quarters drawn separately, longer and dim
    r,g,b,a = rgb_to_r_g_b(theme.faint, 1)
    cairo_set_source_rgba(cr, r,g,b,a)
    cairo_set_line_width(cr, 1)
    for i=0,11 do
        if i % 3 ~= 0 then
            tick(cr, cx, cy, i * math.pi/6, radius - s(6), radius - s(2))
        end
    end
    cairo_stroke(cr)

    r,g,b,a = rgb_to_r_g_b(theme.dim, 1)
    cairo_set_source_rgba(cr, r,g,b,a)
    cairo_set_line_width(cr, s(1.5))
    for i=0,3 do
        tick(cr, cx, cy, i * math.pi/2, radius - s(10), radius - s(2))
    end
    cairo_stroke(cr)

    -- Time
    local hour   = tonumber(os.date("%I"))
    local minute = tonumber(os.date("%M"))
    local second = tonumber(os.date("%S"))

    local hour_angle   = (hour + minute/60) * math.pi/6
    local minute_angle = minute * math.pi/30
    local second_angle = second * math.pi/30

    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)

    local tr,tg,tb,ta = rgb_to_r_g_b(theme.text, 1)
    cairo_set_source_rgba(cr, tr,tg,tb,ta)

    cairo_set_line_width(cr, s(2))
    hand(cr, cx, cy, hour_angle, radius - s(26))

    cairo_set_line_width(cr, s(1.5))
    hand(cr, cx, cy, minute_angle, radius - s(14))

    r,g,b,a = rgb_to_r_g_b(theme.dim, 1)
    cairo_set_source_rgba(cr, r,g,b,a)
    cairo_set_line_width(cr, 1)
    hand(cr, cx, cy, second_angle, radius - s(10))

    -- Center dot
    cairo_set_source_rgba(cr, tr,tg,tb,ta)
    cairo_arc(cr, cx, cy, s(2), 0, 2*math.pi)
    cairo_fill(cr)
end

-- =====================================================
-- Main
-- =====================================================
function M.draw(ctx)
    M.draw_rect(ctx)
    M.draw_visual(ctx)
end

return M
