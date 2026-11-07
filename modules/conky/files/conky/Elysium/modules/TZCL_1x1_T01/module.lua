-- =====================================================
--  Dual Timezone Clock Card (IST / CET)
-- =====================================================

local M = {}
local flat = dofile(os.getenv("HOME") .. "/.config/conky/Common/flat.lua")

local CARD_W = 276   -- spans two grid slots: 2 x 134 + 8
local CARD_H = 134

local function rgb_to_r_g_b(colour, alpha)
    if type(colour) == "string" then
        colour = tonumber((colour:gsub("#", "0x")))
    end
    return ((colour / 0x10000) % 0x100) / 255.,
           ((colour / 0x100) % 0x100) / 255.,
           (colour % 0x100) / 255.,
           alpha
end

local function center_text(cr, text, cx, y)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, text, ext)
    cairo_move_to(cr, cx - ext.width / 2, y)
    cairo_show_text(cr, text)
end

-- Cheap local `date` call, no caching needed: unlike a network fetch,
-- this is sub-millisecond and safe to run every tick via conky's own
-- ${exec} machinery (never io.popen from Lua — see the Linear widget's
-- history for why a raw io.popen call segfaults conky outright).
local function fetch_zone(tz)
    local out = conky_parse("${exec TZ='" .. tz .. "' date '+%H:%M %Z'}")
    if not out then return "--:--", "" end
    local time_str, zone = out:match("^(%d%d:%d%d)%s*(%S*)$")
    return time_str or "--:--", zone or ""
end

function M.draw_rect(ctx)
    flat.card_at(ctx.cr, ctx.x, ctx.y, CARD_W, CARD_H)
end

function M.draw_content(ctx)
    local cr, s, theme = ctx.cr, ctx.s, ctx.theme

    local text_r, text_g, text_b = rgb_to_r_g_b(theme.text, 1)
    local dim_r, dim_g, dim_b = rgb_to_r_g_b(theme.dim, 1)
    local line_r, line_g, line_b = rgb_to_r_g_b(theme.bar_bg, 1)

    local half_w = s(CARD_W) / 2
    local mid_x = ctx.x + half_w
    local mid_y = ctx.y + s(CARD_H) / 2

    -- Hairline divider; +0.5 keeps a 1px line on the pixel grid
    cairo_set_source_rgba(cr, line_r, line_g, line_b, 1)
    cairo_set_line_width(cr, 1)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)
    mid_x = math.floor(mid_x) + 0.5
    cairo_move_to(cr, mid_x, ctx.y + s(18))
    cairo_line_to(cr, mid_x, ctx.y + s(CARD_H) - s(14))
    cairo_stroke(cr)

    local ist_time, ist_zone = fetch_zone("Asia/Kolkata")
    local cet_time = fetch_zone("Europe/Berlin")

    local sides = {
        { cx = ctx.x + half_w * 0.5, zone = (ist_zone ~= "" and ist_zone) or "IST", time = ist_time },
        { cx = ctx.x + half_w * 1.5, zone = "CET", time = cet_time },
    }

    for _, side in ipairs(sides) do
        cairo_set_source_rgba(cr, dim_r, dim_g, dim_b, 1)
        cairo_select_font_face(cr, "Exo 2", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, s(9))
        center_text(cr, side.zone, side.cx, ctx.y + s(30))

        cairo_set_source_rgba(cr, text_r, text_g, text_b, 1)
        cairo_select_font_face(cr, "Exo 2", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, s(19))
        center_text(cr, side.time, side.cx, mid_y + s(10))
    end
end

function M.draw(ctx)
    M.draw_rect(ctx)
    M.draw_content(ctx)
end

return M
