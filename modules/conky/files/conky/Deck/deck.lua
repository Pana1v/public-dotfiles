-- Glass frame for the two ops-deck strips between the wings.
-- Same frost as the wings; the edge facing the clock carries a notch that
-- points at 12 (top strip) or 6 (bottom strip), with the accent glow on it.
local flat = dofile(os.getenv("HOME") .. "/.config/conky/Common/flat.lua")
local theme = flat.theme
local M = {}

local CUT = 22      -- chamfer on the outer corners
local NOTCH = 14    -- depth of the notch toward the clock
local NOTCH_W = 70  -- half width of the notch

-- side "top": notch on the bottom edge; "bottom": notch on the top edge.
local function outline(w, h, side)
    local pts = {
        { CUT, 0 }, { w - CUT, 0 }, { w, CUT },
        { w, h - CUT }, { w - CUT, h }, { CUT, h }, { 0, h - CUT }, { 0, CUT },
    }
    local c = w / 2
    if side == "top" then
        -- bottom edge, walking right to left: in at the notch, back out
        table.insert(pts, 6, { c + NOTCH_W, h })
        table.insert(pts, 7, { c + NOTCH_W - NOTCH, h - NOTCH })
        table.insert(pts, 8, { c - NOTCH_W + NOTCH, h - NOTCH })
        table.insert(pts, 9, { c - NOTCH_W, h })
    else
        table.insert(pts, 2, { c - NOTCH_W, 0 })
        table.insert(pts, 3, { c - NOTCH_W + NOTCH, NOTCH })
        table.insert(pts, 4, { c + NOTCH_W - NOTCH, NOTCH })
        table.insert(pts, 5, { c + NOTCH_W, 0 })
    end
    return pts
end

local function path(cr, pts)
    cairo_move_to(cr, pts[1][1], pts[1][2])
    for i = 2, #pts do cairo_line_to(cr, pts[i][1], pts[i][2]) end
    cairo_close_path(cr)
end

function M.frame(cr, w, h, side)
    local pts = outline(w, h, side)

    path(cr, pts)
    flat.set_color(cr, theme.glass, 0.90)
    cairo_fill_preserve(cr)
    local sheen = cairo_pattern_create_linear(0, 0, w * 0.6, h)
    cairo_pattern_add_color_stop_rgba(sheen, 0, 1, 1, 1, 0.09)
    cairo_pattern_add_color_stop_rgba(sheen, 0.5, 1, 1, 1, 0.02)
    cairo_pattern_add_color_stop_rgba(sheen, 1, 1, 1, 1, 0.0)
    cairo_set_source(cr, sheen)
    cairo_fill_preserve(cr)
    cairo_pattern_destroy(sheen)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.17)
    cairo_set_line_width(cr, 1.2)
    cairo_stroke(cr)

    -- accent glow on the notch, the part that faces the clock
    local c = w / 2
    local y_edge = side == "top" and h or 0
    local y_in = side == "top" and h - NOTCH or NOTCH
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
    for _, g in ipairs({ { 9, 0.06 }, { 4, 0.14 }, { 1.6, 0.95 } }) do
        cairo_move_to(cr, c - NOTCH_W - 40, y_edge)
        cairo_line_to(cr, c - NOTCH_W, y_edge)
        cairo_line_to(cr, c - NOTCH_W + NOTCH, y_in)
        cairo_line_to(cr, c + NOTCH_W - NOTCH, y_in)
        cairo_line_to(cr, c + NOTCH_W, y_edge)
        cairo_line_to(cr, c + NOTCH_W + 40, y_edge)
        flat.set_color(cr, theme.accent, g[2])
        cairo_set_line_width(cr, g[1])
        cairo_stroke(cr)
    end

    -- corner brackets, like the cards
    flat.set_color(cr, theme.dim)
    cairo_set_line_width(cr, 2)
    local b = 14
    for _, s in ipairs({ { 0, 1 }, { w, -1 } }) do
        local x, d = s[1], s[2]
        local ye = side == "top" and 0 or h          -- outer edge (away from the clock)
        local yd = side == "top" and 1 or -1
        cairo_move_to(cr, x + d * (CUT + b), ye + yd)
        cairo_line_to(cr, x + d * CUT, ye + yd)
        cairo_line_to(cr, x + d, ye + yd * CUT)
        cairo_line_to(cr, x + d, ye + yd * (CUT + b))
        cairo_stroke(cr)
    end
end

return M
