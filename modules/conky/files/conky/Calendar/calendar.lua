local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
local theme, PAD = flat.theme, flat.PAD

local HEADER_H = 46
local ROW_H = 24
local WEEKDAYS = { "mo", "tu", "we", "th", "fr", "sa", "su" }
local SATURDAY = 6

-- Centre s on x in the current font.
local function centred(cr, x, y, s, colour)
    flat.text(cr, x - flat.width(cr, s) / 2, y, s, colour)
end

local function draw(cr, w, h)
    flat.card(cr, w, h)

    local now = os.date("*t")
    flat.header(cr, w, "calendar", string.lower(os.date("%B %Y")), nil, "calendar")

    -- Monday-first grid: Lua wday is 1 = Sunday, so shift by 5.
    local first = os.date("*t", os.time({ year = now.year, month = now.month, day = 1 }))
    local offset = (first.wday + 5) % 7
    -- Day 0 of next month normalises to the last day of this one.
    local days = os.date("*t", os.time({ year = now.year, month = now.month + 1, day = 0 })).day

    local col_w = (w - 2 * PAD) / 7
    local function col_x(col) return PAD + col_w * (col + 0.5) end

    flat.font(cr, "Exo 2", 11)
    for i, name in ipairs(WEEKDAYS) do
        centred(cr, col_x(i - 1), HEADER_H + 12, name, theme.faint)
    end

    flat.font(cr, "Exo 2", 13)
    for day = 1, days do
        local cell = offset + day - 1
        local col, row = cell % 7, cell // 7
        local x = col_x(col)
        local y = HEADER_H + 22 + ROW_H * (row + 1)

        -- Today: green disc with the number knocked out in card colour.
        if day == now.day then
            flat.set_color(cr, theme.green)
            cairo_arc(cr, x, y - 5, 12, 0, 2 * math.pi)
            cairo_fill(cr)
            centred(cr, x, y, tostring(day), theme.bg)
            goto continue
        end

        centred(cr, x, y, tostring(day), (col + 1 >= SATURDAY) and theme.faint or theme.dim)
        ::continue::
    end
end

-- Loaded by a wing window: hand over update/draw instead of becoming conky_main.
if WING then
    return { update = function()  end, draw = draw }
end

function conky_main()
    flat.render("Calendar", draw)
end
