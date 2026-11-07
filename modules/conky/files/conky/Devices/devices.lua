local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
local theme, PAD = flat.theme, flat.PAD

local devices = flat.snapshot("devices")
local buds = flat.snapshot("cmf_buds")

local LOW_PCT = 15
local MID_PCT = 30
local BUDS_STALE_S = 120   -- buds feed polls every 30 s

-- Layout, 1x units, one row per device (MAX_ROWS fit the card):
--   DEVICES                    3 LINKED
--   HEAD   CMF Buds 2      L80 R75 C40
--          ||||||||||||||||||::::::::::
--   MOUSE  MX Master 3S             70%
--          ||||||||||||||||||||::::::::
local LABEL_W = 52
local FIRST_Y = 62
local ROW_H = 34
local MAX_ROWS = 4
local KIND_ICON = {
    headset = "headset", headphones = "headset", mouse = "mouse", keyboard = "keyboard",
    ["gaming-input"] = "gamepad", phone = "phone",
}

local function battery_colour(pct, charging)
    if charging then return theme.green end
    if pct <= LOW_PCT then return theme.red end
    if pct <= MID_PCT then return theme.yellow end
    return theme.text
end

local function parse_devices(rows)
    local list = {}
    for _, r in ipairs(rows) do
        if r[1] == "dev" then
            list[#list + 1] = {
                kind = r[2], name = r[3], pct = tonumber(r[4]) or 0,
                charging = r[5] == "charging", full = r[5] == "full",
            }
        end
    end
    -- Lowest battery first: the one that needs a charger leads.
    table.sort(list, function(a, b) return a.pct < b.pct end)
    return list
end

-- CMF Buds report each bud and the case through their own feed, not UPower.
local function buds_device()
    if not buds.rows or os.time() - (buds.last_success or 0) > BUDS_STALE_S then return nil end
    local state, batt = nil, {}
    for _, r in ipairs(buds.rows) do
        if r[1] == "state" then state = r[2] end
        if r[1] == "battery" then batt[r[2]] = { pct = tonumber(r[3]) or 0, charging = r[4] == "1" } end
    end
    if state ~= "connected" or not (batt.left or batt.right) then return nil end

    local parts, low, charging = {}, 100, false
    for _, slot in ipairs({ { "left", "L" }, { "right", "R" }, { "case", "C" } }) do
        local b = batt[slot[1]]
        if b then
            parts[#parts + 1] = slot[2] .. b.pct .. (b.charging and "+" or "")
            if slot[1] ~= "case" then
                low = math.min(low, b.pct)
                charging = charging or b.charging
            end
        end
    end
    return { kind = "headset", name = "CMF Buds 2", pct = low, charging = charging, value = table.concat(parts, " ") }
end

local function draw_row(cr, w, y, d)
    flat.icon(cr, PAD, y + 3, KIND_ICON[d.kind] or "battery", 20, d.charging and theme.green or theme.dim)

    local colour = battery_colour(d.pct, d.charging)
    local value = d.value or string.format("%d%%%s", d.pct, d.charging and "+" or "")
    flat.font(cr, "JetBrains Mono", 12)
    flat.text_right(cr, w - PAD, y, value, colour)
    local value_w = flat.width(cr, value)

    local x = PAD + LABEL_W
    flat.font(cr, "Exo 2", 12)
    flat.text(cr, x, y, flat.fit(cr, d.name, w - PAD - x - value_w - 12), theme.text)
    flat.ticks(cr, x, y + 7, w - PAD - x, 4, d.pct / 100, d.charging and theme.green or colour)
end

local last_count = 0

local function draw(cr, w, h)
    flat.card(cr, w, h)

    local list = devices.rows and parse_devices(devices.rows) or {}
    local b = buds_device()
    if b then table.insert(list, 1, b) end
    last_count = math.min(#list, MAX_ROWS)

    flat.header(cr, w, "devices", #list > 0 and (#list .. " linked") or "", nil, "devices")

    if not devices.rows and not b then
        flat.font(cr, "Exo 2", 13)
        return flat.text(cr, PAD, FIRST_Y, "loading...", theme.dim)
    end
    if #list == 0 then
        flat.font(cr, "Exo 2", 13)
        return flat.text(cr, PAD, FIRST_Y, "no headphones, mice or keyboards", theme.faint)
    end

    for i = 1, math.min(#list, MAX_ROWS) do
        draw_row(cr, w, FIRST_Y + (i - 1) * ROW_H, list[i])
    end
end

-- Loaded by a wing window: hand over update/draw instead of becoming conky_main.
if WING then
    return {
        update = function() devices.update() buds.update() end,
        draw = draw,
        -- header + one row per device; a short message when nothing is connected
        size = function() return last_count == 0 and 92 or (FIRST_Y + ROW_H * (last_count - 1) + 30) end,
    }
end

function conky_main()
    devices.update()
    buds.update()
    flat.render("Devices", draw)
end
