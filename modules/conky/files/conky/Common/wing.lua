-- Shared frame for the two instrument wings: one stepped glass shape per wing,
-- with frost, an accent glow along the inner edge, ruler ticks and
-- corner brackets. The widgets inside draw without cards of their own.
local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
local theme = flat.theme

local M = {}

M.MARGIN = 16                     -- room around the shape for the glow
-- The inner edge is cut at 45 degrees at the top and bottom, SLANT px each way.
local SLANT = 60
M.CORNER = SLANT                  -- content starts below the slanted corners

-- Edge status: the glow, ruler and corner brackets take their colour from live
-- machine state (same feed as the systems gauges), so a glance at the screen
-- edge says if something needs attention. Green ok, yellow warn, red critical.
local snap = flat.snapshot("sysmon")
local LEVEL = { theme.accent, theme.yellow, theme.red }   -- 1 ok, 2 warn, 3 crit
local TICK_WHITE = "#ffffff"   -- ruler ticks on the inner edge
local status = { load = 0, all = 1, cpu = 1, disk = 1, mem = 1, mem_pct = 0, batt = 1, batt_pct = 100, charging = false }
local last_read = 0

local function grade(v, warn, crit) return v >= crit and 3 or v >= warn and 2 or 1 end

local function read_status()
    local now = os.time()
    if now - last_read < 2 then return end
    last_read = now
    snap.update()
    if not snap.rows then return end
    local d = {}
    for _, r in ipairs(snap.rows) do d[r[1]] = r end
    local function num(row, i) return row and tonumber(row[i]) or 0 end

    status.mem_pct = num(d.mem, 2)
    status.mem = math.max(grade(status.mem_pct, 70, 90), grade(num(d.swap, 2), 30, 70))
    status.cpu = math.max(grade(num(d.cpu, 2), 70, 90), grade(num(d.cpu, 3), 75, 90))
    status.load = math.max(num(d.cpu, 2), status.mem_pct) / 100
    status.disk = grade(num(d.disk, 2), 80, 92)

    local b = d.batt
    status.batt_pct = num(b, 2)
    status.charging = b ~= nil and (b[3] == "charging" or b[3] == "full")
    status.batt = 1
    if b and not status.charging and b[3] ~= "not charging" then
        status.batt = status.batt_pct <= 15 and 3 or status.batt_pct <= 30 and 2 or 1
    end
    -- the glow shows the worst of everything
    status.all = math.max(status.mem, status.cpu, status.disk, status.batt)
end

-- Outline in window coordinates. "left" has its inner (slanted) edge on the
-- right; "right" is the mirror image.
local function outline(side, w, h)
    local m = M.MARGIN
    local ww = w - 2 * m
    local pts = {
        { m, m }, { m + ww - SLANT, m }, { m + ww, m + SLANT },
        { m + ww, h - m - SLANT }, { m + ww - SLANT, h - m }, { m, h - m },
    }
    if side == "right" then
        for _, p in ipairs(pts) do p[1] = w - p[1] end
    end
    return pts
end

local function path(cr, pts)
    cairo_move_to(cr, pts[1][1], pts[1][2])
    for i = 2, #pts do cairo_line_to(cr, pts[i][1], pts[i][2]) end
    cairo_close_path(cr)
end

-- Content rectangle (x, width) and the first/last usable y inside the wing.
function M.content(w, h)
    local m = M.MARGIN
    return m + 14, w - 2 * m - 28, m + M.CORNER + 10, h - m - M.CORNER - 10
end

function M.frame(cr, side, w, h)
    local pts = outline(side, w, h)
    local m = M.MARGIN
    local x0, x1 = m, w - m

    -- Frosted glass: translucent fill, light falling from the top, soft sheen.
    path(cr, pts)
    flat.set_color(cr, theme.glass, 0.90)   -- 90% opaque, same as flat.lua cards
    cairo_fill_preserve(cr)
    local sheen = cairo_pattern_create_linear(x0, m, x1, h * 0.7)
    cairo_pattern_add_color_stop_rgba(sheen, 0, 1, 1, 1, 0.11)
    cairo_pattern_add_color_stop_rgba(sheen, 0.45, 1, 1, 1, 0.03)
    cairo_pattern_add_color_stop_rgba(sheen, 1, 1, 1, 1, 0.0)
    cairo_set_source(cr, sheen)
    cairo_fill_preserve(cr)
    cairo_pattern_destroy(sheen)
    local top_light = cairo_pattern_create_linear(0, m, 0, m + 140)
    cairo_pattern_add_color_stop_rgba(top_light, 0, 1, 1, 1, 0.07)
    cairo_pattern_add_color_stop_rgba(top_light, 1, 1, 1, 1, 0.0)
    cairo_set_source(cr, top_light)
    cairo_fill_preserve(cr)
    cairo_pattern_destroy(top_light)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.17)
    cairo_set_line_width(cr, 1.2)
    cairo_stroke(cr)

    -- Glow along the slanted inner edge: every point except the two outer corners.
    local line = {}
    for i = 2, #pts - 1 do line[#line + 1] = pts[i] end
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
    read_status()
    -- White, like the ruler ticks; a warning or critical state (disk, battery,
    -- temperature) still turns it yellow or red.
    local edge = status.all == 1 and TICK_WHITE or LEVEL[status.all]
    for _, g in ipairs({ { 11, 0.05 }, { 5, 0.11 }, { 1.6, 0.95 } }) do
        cairo_move_to(cr, line[1][1], line[1][2])
        for i = 2, #line do cairo_line_to(cr, line[i][1], line[i][2]) end
        flat.set_color(cr, edge, g[2])
        cairo_set_line_width(cr, g[1])
        cairo_stroke(cr)
    end

    -- Ruler ticks on the long vertical run of the inner edge, pointing inward.
    -- They double as a level meter filling from the bottom: memory on the left
    -- wing, battery on the right (green while charging).
    local inner_x = side == "left" and x1 or x0
    local dir = side == "left" and -1 or 1
    local y_from, y_to = m + M.CORNER + 16, h - m - M.CORNER - 16
    local pct = side == "left" and status.mem_pct or status.batt_pct
    local lvl = side == "left" and status.mem or (status.charging and 1 or status.batt)
    local total = math.floor((y_to - y_from) / 12) + 1
    local lit = math.floor(total * math.max(0, math.min(pct, 100)) / 100 + 0.5)
    local n = 0
    for y = y_from, y_to, 12 do
        local long = n % 5 == 0
        local on = (total - n) <= lit
        -- White meter; a warning or critical level still lights it yellow or red.
        if on then
            flat.set_color(cr, lvl == 1 and TICK_WHITE or LEVEL[lvl], 0.95)
        else
            flat.set_color(cr, TICK_WHITE, long and 0.45 or 0.25)
        end
        cairo_set_line_width(cr, on and 1.6 or 1)
        cairo_move_to(cr, inner_x + dir * 4, y + 0.5)
        cairo_line_to(cr, inner_x + dir * ((long or on) and 13 or 8), y + 0.5)
        cairo_stroke(cr)
        n = n + 1
    end

    -- Brackets on the two outer (screen side) corners.
    local ox = side == "left" and x0 or x1
    local sx = side == "left" and 1 or -1
    local b = 16
    cairo_set_line_width(cr, 1.6)
    for _, oy in ipairs({ m, h - m }) do
        local sy = oy == m and 1 or -1
        -- top bracket: CPU load and temperature; bottom: disk (left) or battery (right)
        local lv = oy == m and status.cpu or (side == "left" and status.disk or status.batt)
        flat.set_color(cr, LEVEL[lv], 0.9)
        cairo_move_to(cr, ox + sx * b, oy + sy * 3)
        cairo_line_to(cr, ox + sx * 3, oy + sy * 3)
        cairo_line_to(cr, ox + sx * 3, oy + sy * b)
        cairo_stroke(cr)
    end
end

-- Section divider: faint accent hairline with a bright lead-in.
function M.divider(cr, x1, x2, y)
    flat.set_color(cr, theme.accent, 0.28)
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, x1, y + 0.5)
    cairo_line_to(cr, x2, y + 0.5)
    cairo_stroke(cr)
    flat.set_color(cr, theme.accent, 0.95)
    cairo_set_line_width(cr, 1.6)
    cairo_move_to(cr, x1, y + 0.5)
    cairo_line_to(cr, x1 + 34, y + 0.5)
    cairo_stroke(cr)
    -- slashes at the far end, leaning like the wing's edges
    cairo_set_line_width(cr, 1.3)
    for k = 0, 2 do
        flat.set_color(cr, theme.accent, 0.75 - k * 0.2)
        cairo_move_to(cr, x2 - 4 - k * 7, y + 5)
        cairo_line_to(cr, x2 + 2 - k * 7, y - 4)
        cairo_stroke(cr)
    end
end

-- Small label in each slanted corner, in the empty strip above and below the content.
function M.captions(cr, side, w, h, top_text, bottom_text)
    local m = M.MARGIN
    -- the strip is narrower on the inner side: start past the slant on the right wing
    local x = side == "left" and (m + 16) or (m + 56)
    for _, c in ipairs({ { top_text, m + 24 }, { bottom_text, h - m - 18 } }) do
        flat.font(cr, "Orbitron", 9, true)
        flat.spaced(cr, x + 14, c[2], c[1]:upper(), theme.dim, 2.5)
        flat.set_color(cr, theme.accent)
        cairo_rectangle(cr, x, c[2] - 7, 8, 8)
        cairo_fill(cr)
    end
end

-- Stack sections top to bottom inside the wing. Each is { h, update, draw } with
-- an optional size() for a height that follows its content, and flex = true on
-- the one section that grows to soak up spare height. Gaps get a divider each.
function M.layout(cr, w, h, sections)
    local x, cw, y_top, y_bottom = M.content(w, h)
    local GAP = 16
    local function measure(list)
        local heights, fixed, flex = {}, 0, nil
        for i, s in ipairs(list) do
            heights[i] = s.size and s.size() or s.h
            if s.flex then flex = i else fixed = fixed + heights[i] end
        end
        return heights, fixed, flex
    end
    local heights, fixed, flex = measure(sections)
    -- An optional section that does not fit even with tight gaps is left out
    -- (e.g. the activity graphs while many devices are connected).
    local last = sections[#sections]
    if last and last.optional and fixed + heights[#sections] + 10 * (#sections - 1) > y_bottom - y_top then
        sections = { table.unpack(sections, 1, #sections - 1) }
        heights, fixed, flex = measure(sections)
    end
    local avail = y_bottom - y_top
    if fixed + heights[flex or 1] * (flex and 1 or 0) + GAP * (#sections - 1) > avail then GAP = 10 end
    local gaps = GAP * (#sections - 1)
    if flex then
        heights[flex] = math.max(heights[flex], y_bottom - y_top - fixed - gaps)
    end
    local used = gaps
    for _, v in ipairs(heights) do used = used + v end
    if not flex and #sections > 1 then
        -- nothing soaks up the spare height, so spread it over the gaps (not too wide)
        GAP = math.min(GAP + (y_bottom - y_top - used) / (#sections - 1), 40)
        used = GAP * (#sections - 1)
        for _, v in ipairs(heights) do used = used + v end
    end
    local y = y_top + math.max((y_bottom - y_top - used) / 2, 0)   -- centre what is left
    for i, s in ipairs(sections) do
        cairo_save(cr)
        cairo_translate(cr, x, y)
        s.draw(cr, cw, heights[i])
        cairo_restore(cr)
        y = y + heights[i]
        if i < #sections then
            M.divider(cr, x, x + cw, y + GAP / 2)
            y = y + GAP
        end
    end
end

return M
