local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
local theme, PAD = flat.theme, flat.PAD

local audio = flat.snapshot("audio")
local buds = flat.snapshot("cmf_buds")

local BUDS_STALE_S = 120   -- buds feed polls every 30 s
local MAX_VOLUME = 1.5     -- wpctl allows boosting past 100%

-- Layout, 1x units:
--   AUDIO                      BLUETOOTH
--   OUT  Lenovo Headset             118%
--        ||||||||||||||||||||||:::::::::
--   IN   Digital Microphone          94%
--        ||||||||||||||||||:::::::::::::
-- Batteries (headsets, mice, buds) live in the devices widget.
local LABEL_W = 36
local DEVICE_Y = { out = 62, ["in"] = 94 }
local API_LABEL = { bluez5 = "bluetooth", alsa = "wired" }

local function parse_buds(rows)
    local d = { battery = {} }
    for _, r in ipairs(rows) do
        if r[1] == "battery" then
            d.battery[r[2]] = { pct = tonumber(r[3]) or 0, charging = r[4] == "1" }
        else
            d[r[1]] = r
        end
    end
    return d
end

local function parse_audio(rows)
    local d = {}
    for _, r in ipairs(rows) do
        if DEVICE_Y[r[1]] then
            d[r[1]] = { name = r[2], volume = tonumber(r[3]) or 0, muted = r[4] == "1", api = r[5] }
        end
    end
    return d
end

-- Volume ticks: green normally, yellow when boosted past 100%, dim when muted.
local function draw_device(cr, w, kind, dev)
    local y = DEVICE_Y[kind]
    local x = PAD + LABEL_W
    local icon = kind == "out" and (dev and dev.muted and "muted" or "speaker") or (dev and dev.muted and "mic_off" or "mic")
    flat.icon(cr, PAD, y + 2, icon, 17, (dev and dev.muted) and theme.faint or theme.dim)

    if not dev then
        flat.font(cr, "Exo 2", 12)
        flat.text(cr, x, y, "no device", theme.faint)
        return
    end

    local value = dev.muted and "MUTED" or string.format("%d%%", math.floor(dev.volume * 100 + 0.5))
    flat.font(cr, "JetBrains Mono", 12)
    flat.text_right(cr, w - PAD, y, value, dev.muted and theme.faint or theme.text)
    local value_w = flat.width(cr, value)

    flat.font(cr, "Exo 2", 12)
    flat.text(cr, x, y, flat.fit(cr, dev.name, w - PAD - x - value_w - 12), theme.text)

    local colour = dev.muted and theme.dim or (dev.volume > 1 and theme.yellow or theme.green)
    flat.ticks(cr, x, y + 7, w - PAD - x, 4, dev.volume / MAX_VOLUME, colour)
end

local function draw(cr, w, h)
    flat.card(cr, w, h)

    local devices = audio.rows and parse_audio(audio.rows) or {}
    local bd = buds.rows and parse_buds(buds.rows)
    local buds_on = bd and bd.state and bd.state[2] == "connected"
        and os.time() - (buds.last_success or 0) <= BUDS_STALE_S

    local status = ""
    if buds_on then
        status = "cmf buds 2  .  " .. (bd.anc and bd.anc[2] or "")
    elseif devices.out then
        status = API_LABEL[devices.out.api] or devices.out.api or ""
    end
    flat.header(cr, w, "audio", status, nil, "speaker")

    if not audio.rows then
        flat.font(cr, "Exo 2", 13)
        flat.text(cr, PAD, DEVICE_Y.out, "loading...", theme.dim)
        return
    end

    draw_device(cr, w, "out", devices.out)
    draw_device(cr, w, "in", devices["in"])
end

-- Loaded by a wing window: hand over update/draw instead of becoming conky_main.
if WING then
    return { update = function() audio.update() buds.update() end, draw = draw }
end

function conky_main()
    audio.update()
    buds.update()
    flat.render("CmfBuds", draw)
end
