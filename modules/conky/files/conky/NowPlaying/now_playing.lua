local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
local theme, PAD = flat.theme, flat.PAD

local US_PER_S = 1e6

local player = flat.snapshot("now_playing")

local function mmss(us)
    local s = math.floor((tonumber(us) or 0) / US_PER_S)
    return string.format("%d:%02d", s // 60, s % 60)
end

-- Prefer a playing player; otherwise the first paused one.
local function pick(rows)
    local first
    for _, r in ipairs(rows) do
        if r[1] == "Playing" then return r end
        first = first or (r[1] == "Paused" and r)
    end
    return first
end

-- Concentric dot rings with an accent centre, the "speaker" motif. Rings
-- light outward with the track position while something plays.
local function rings(cr, cx, cy, frac, on)
    for k = 1, 4 do
        local r = 6 + k * 6
        local n = 8 + k * 6
        local lit = on and (k / 4 <= frac + 0.25)
        flat.set_color(cr, lit and theme.accent or theme.bar_bg)
        for i = 0, n - 1 do
            local a = 2 * math.pi * i / n
            flat.dot(cr, cx + math.cos(a) * r, cy + math.sin(a) * r, 1.1)
        end
        cairo_fill(cr)
    end
    flat.set_color(cr, theme.accent)
    flat.dot(cr, cx, cy, 3.2)
    cairo_fill(cr)
end

local function message(cr, w, s)
    flat.header(cr, w, "now playing", "", nil, "music")
    flat.font(cr, "Exo 2", 13)
    flat.text(cr, PAD, 66, s, theme.dim)
    rings(cr, w - PAD - 30, 44, 0, false)
end

local playing = false

local function draw(cr, w, h)
    flat.card(cr, w, h)
    playing = false

    local rows = player.rows
    if not rows then return message(cr, w, "loading...") end
    if rows[1] and rows[1][1] == "MISSING" then return message(cr, w, "playerctl not installed") end

    local p = rows[1] and rows[1][1] ~= "NONE" and pick(rows)
    if not p then return message(cr, w, "nothing playing") end

    playing = true
    local status, name, artist, title, pos, len = table.unpack(p)
    flat.header(cr, w, "now playing", string.lower(status) .. "  .  " .. name, nil, status == "Playing" and "play" or "pause")

    local text_colour = (status == "Playing") and theme.text or theme.dim
    local len_f = tonumber(len) or 0
    rings(cr, w - PAD - 30, 62, len_f > 0 and math.min((tonumber(pos) or 0) / len_f, 1) or 1, status == "Playing")
    flat.font(cr, "Exo 2", 15)
    flat.text(cr, PAD, 62, flat.fit(cr, title ~= "" and title or "unknown", w - 2 * PAD - 70), text_colour)
    flat.font(cr, "Exo 2", 12)
    flat.text(cr, PAD, 80, flat.fit(cr, artist, w - 2 * PAD - 70), theme.dim)

    -- Progress bar; streams report no length, so skip it there.
    local len_n = tonumber(len) or 0
    if len_n <= 0 then return end
    local bar_w = w - 2 * PAD - 180
    local frac = math.min((tonumber(pos) or 0) / len_n, 1)
    flat.ticks(cr, PAD, 92, bar_w, 4, frac, theme.green)

    flat.font(cr, "Exo 2", 11)
    flat.text(cr, PAD + bar_w + 10, 98, mmss(pos) .. " / " .. mmss(len), theme.faint)
end

-- Loaded by a wing window: hand over update/draw instead of becoming conky_main.
if WING then
    return { update = function() player.update() end, draw = draw, size = function() return playing and 110 or 84 end }
end

function conky_main()
    player.update()
    flat.render("NowPlaying", draw)
end
