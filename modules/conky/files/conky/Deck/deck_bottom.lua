require 'cairo'
pcall(require, 'cairo_xlib')
-- Ops deck, bottom strip: Linear issues as a two-column queue.
-- Reads ~/.cache/conky/linear.tsv (conky-feeds.service runs fetch_issues.py).
local CONKY = os.getenv("HOME") .. "/.config/conky/"
local flat = dofile(CONKY .. "Common/flat.lua")
local deck = dofile(CONKY .. "Deck/deck.lua")
local theme = flat.theme

local linear = flat.snapshot("linear")
local COL_MIN_W = 380   -- columns follow the strip width (any resolution)
local ROW_H = 26
local GAP = 24

local PRIORITY = { Urgent = theme.red, High = theme.yellow }

-- started first, then todo; Linear's own order within each
local function issues()
    local started, rest = {}, {}
    for _, r in ipairs(linear.rows or {}) do
        if r[1] and r[1] ~= "" and r[1] ~= "EMPTY" then
            local it = { id = r[1], state = r[2], priority = r[4], title = r[7] or "" }
            table.insert(it.state == "started" and started or rest, it)
        end
    end
    for _, it in ipairs(rest) do started[#started + 1] = it end
    return started
end

local function row(cr, x, y, w, it)
    -- state pip: filled = in progress, ring = not started
    flat.set_color(cr, it.state == "started" and theme.accent or theme.dim)
    cairo_new_path(cr)   -- text leaves a current point; don't join it to the ring
    cairo_arc(cr, x + 4, y - 4, 3.5, 0, 2 * math.pi)
    if it.state == "started" then cairo_fill(cr) else cairo_set_line_width(cr, 1.2); cairo_stroke(cr) end

    flat.font(cr, "JetBrains Mono", 10, true)
    flat.text(cr, x + 14, y, it.id, PRIORITY[it.priority] or theme.faint)
    local idw = 76
    flat.font(cr, "Exo 2", 13)
    flat.text(cr, x + 14 + idw, y, flat.fit(cr, it.title, w - 14 - idw), theme.text)
end

local function draw(cr, w, h)
    deck.frame(cr, w, h, "bottom")
    local list = issues()
    local status = "setup . LINEAR_API_KEY in ~/.config/secrets/linear.env"
    local colour = theme.yellow
    if linear.last_success then
        local started = 0
        for _, it in ipairs(list) do if it.state == "started" then started = started + 1 end end
        status = string.format("%d active . %d in progress . %s", #list, started,
            flat.format_age(os.time() - linear.last_success))
        colour = theme.faint
    end
    flat.header(cr, w, "linear", status, colour, "check")

    local top = 66
    local per_col = math.max(1, math.floor((h - top + ROW_H - 8) / ROW_H))
    local cols = math.max(1, math.min(3, math.floor((w - 2 * flat.PAD + GAP) / (COL_MIN_W + GAP))))
    local cw = (w - 2 * flat.PAD - GAP * (cols - 1)) / cols
    if #list == 0 and linear.last_success then
        flat.font(cr, "Exo 2", 13)
        flat.text(cr, flat.PAD, top, "inbox zero. nothing assigned.", theme.dim)
        return
    end
    local shown = math.min(#list, per_col * cols)
    for i = 1, shown do
        local c, r = math.floor((i - 1) / per_col), (i - 1) % per_col
        row(cr, flat.PAD + c * (cw + GAP), top + r * ROW_H, cw, list[i])
    end
    if #list > shown then
        flat.font(cr, "JetBrains Mono", 10)
        flat.text_right(cr, w - flat.PAD, h - 8, string.format("+%d more", #list - shown), theme.faint)
    end
end

function conky_main()
    linear.update()
    flat.render("DeckBottom", draw)
end
