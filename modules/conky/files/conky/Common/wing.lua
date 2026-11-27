-- Shared layout for the two wings: a column of separate matte cards, one per
-- widget, numbered 01, 02 ... down the left wing, across the deck (07-08)
-- and on down the right one.
-- Nothing-style: no glass, no frame around the column, each card stands alone.
local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")

local M = {}

M.MARGIN = 18   -- room around the column for the card shadows
M.GAP = 14      -- space between cards

-- Content rectangle (x, width) and the first/last usable y inside the wing.
function M.content(w, h)
    local m = M.MARGIN
    return m, w - 2 * m, m - 4, h - m
end

-- Stack sections top to bottom. Each is { h, update, draw } with an optional
-- size() for a height that follows its content, and flex = true on the one
-- section that grows to soak up spare height. Each section draws its own card
-- (flat.card) and gets its number from `first` upward.
function M.layout(cr, w, h, sections, first)
    local x, cw, y_top, y_bottom = M.content(w, h)
    local GAP = M.GAP
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
    if fixed + (flex and heights[flex] or 0) + GAP * (#sections - 1) > avail then GAP = 10 end
    local gaps = GAP * (#sections - 1)
    if flex then
        heights[flex] = math.max(heights[flex], avail - fixed - gaps)
    elseif #sections > 1 then
        -- nothing soaks up the spare height: hand it to the cards evenly
        local used = gaps
        for _, v in ipairs(heights) do used = used + v end
        local extra = math.max(0, avail - used) / #sections
        for i = 1, #heights do heights[i] = heights[i] + extra end
    end
    local y = y_top
    for i, s in ipairs(sections) do
        flat.section = (first or 1) + i - 1
        cairo_save(cr)
        cairo_translate(cr, x, y)
        s.draw(cr, cw, heights[i])
        cairo_restore(cr)
        y = y + heights[i] + GAP
    end
    flat.section = nil
end

return M
