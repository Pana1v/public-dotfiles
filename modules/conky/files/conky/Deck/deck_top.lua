require 'cairo'
pcall(require, 'cairo_xlib')
-- Ops deck, top strip: the fleet as a grid of host chips.
-- Reads ~/.cache/conky/fleet.tsv (fleet-ping.service); no subprocess here.
local CONKY = os.getenv("HOME") .. "/.config/conky/"
local flat = dofile(CONKY .. "Common/flat.lua")
local theme = flat.theme

local fleet = flat.snapshot("fleet")
-- Numbered between the wings: left 01-06, deck 07-08, right 09 on.
flat.section = 7
local STALE_SECONDS = 45
local SLOW_MS = 1000
local CHIP_MIN_W = 190   -- columns follow the strip width (any resolution)
local CHIP_H = 38
local GAP = 8

local function hosts()
    local list = {}
    for _, r in ipairs(fleet.rows or {}) do
        if r[1] and r[1] ~= "" then
            list[#list + 1] = { label = r[1], addr = r[2] or "", up = r[3] == "up", ms = tonumber(r[4]) }
        end
    end
    return list
end

local function chip(cr, x, y, w, h, host)
    local state = not host.up and theme.red or (host.ms and host.ms > SLOW_MS and theme.yellow) or theme.green

    -- state pip, as in the Linear strip: filled = up, ring = down
    flat.set_color(cr, state)
    cairo_new_path(cr)
    cairo_arc(cr, x + 4, y + 12, 3.5, 0, 2 * math.pi)
    if host.up then cairo_fill(cr) else cairo_set_line_width(cr, 1.2); cairo_stroke(cr) end

    flat.font(cr, "Exo 2", 13, true)
    flat.text(cr, x + 14, y + 16, flat.fit(cr, host.label, w - 90), host.up and theme.text or theme.dim)
    flat.font(cr, "JetBrains Mono", 10)
    flat.text(cr, x + 14, y + 31, flat.fit(cr, host.addr, w - 28), theme.faint)

    flat.font(cr, "JetBrains Mono", 11, true)
    local tag = host.up and (host.ms and string.format("%.0fms", host.ms) or "up") or "off"
    flat.text_right(cr, x + w - 10, y + 16, tag:upper(), state)
end

local function draw(cr, w, h)
    flat.card(cr, w, h)
    local list = hosts()
    local up = 0
    for _, hst in ipairs(list) do if hst.up then up = up + 1 end end

    local status, colour = "no data . fleet-ping not running", theme.yellow
    if fleet.last_success then
        local age = os.time() - fleet.last_success
        status = string.format("%d/%d online . %s", up, #list, flat.format_age(age))
        colour = age > STALE_SECONDS and theme.yellow or (up == #list and theme.green or theme.faint)
    end
    flat.header(cr, w, "fleet", status, colour, "server")

    local top = 46
    local inner = w - 2 * flat.PAD
    local cols = math.max(1, math.min(#list, math.floor((inner + GAP) / (CHIP_MIN_W + GAP))))
    local fit_rows = math.max(1, math.floor((h - top - 12 + GAP) / (CHIP_H + GAP)))
    local shown = math.min(#list, cols * fit_rows)
    if shown < #list then cols = math.max(1, cols); shown = cols * fit_rows - 1 end
    local cw = (inner - (cols - 1) * GAP) / cols
    -- fewer rows than fit (wide screens): centre them between the rule and the bottom
    local used_rows = math.ceil(math.min(#list, shown + (shown < #list and 1 or 0)) / cols)
    top = top + math.max(0, ((h - 14 - top) - (used_rows * CHIP_H + (used_rows - 1) * GAP)) / 2 - 2)
    for i = 1, shown do
        local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
        chip(cr, flat.PAD + c * (cw + GAP), top + r * (CHIP_H + GAP), cw, CHIP_H, list[i])
    end
    if shown < #list then
        -- last slot: how many hosts did not fit, and how many of those are down
        local down = 0
        for i = shown + 1, #list do if not list[i].up then down = down + 1 end end
        local c, r = shown % cols, math.floor(shown / cols)
        local x, y = flat.PAD + c * (cw + GAP), top + r * (CHIP_H + GAP)
        flat.font(cr, "JetBrains Mono", 11, true)
        flat.text(cr, x + 14, y + 16, string.format("+%d HOSTS", #list - shown), theme.dim)
        flat.font(cr, "JetBrains Mono", 10)
        flat.text(cr, x + 14, y + 31, string.format("%d down", down), down > 0 and theme.red or theme.faint)
    end
end

function conky_main()
    fleet.update()
    flat.render("DeckTop", draw)
end
