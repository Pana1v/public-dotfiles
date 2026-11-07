local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
local theme, PAD = flat.theme, flat.PAD

local RAIN_WARN = 60   -- % chance; the only weather value that earns color

local weather = flat.snapshot("weather")

local function rain_color(pct)
    if (tonumber(pct) or 0) >= RAIN_WARN then return theme.yellow end
    return theme.dim
end

-- Group rows by record tag: L, N, S single; H, D lists.
local function parse(rows)
    local d = { H = {}, D = {} }
    for _, r in ipairs(rows) do
        local tag = r[1]
        if tag == "H" or tag == "D" then
            d[tag][#d[tag] + 1] = r
        else
            d[tag] = r
        end
    end
    return d
end

local function weather_icon(desc)
    local d = desc:lower()
    if d:find("thunder") or d:find("storm") then return "storm" end
    if d:find("snow") or d:find("sleet") or d:find("ice") or d:find("blizzard") then return "snow" end
    if d:find("rain") or d:find("drizzle") or d:find("shower") then return "rain" end
    if d:find("sun") or d:find("clear") then return "sun" end
    return "cloud"
end

local function draw(cr, w, h)
    flat.card(cr, w, h)

    local status = ""
    if weather.last_success then
        status = flat.format_age(os.time() - weather.last_success)
    end

    if not weather.rows then
        flat.header(cr, w, "weather", status, nil, "cloud")
        flat.font(cr, "Exo 2", 13)
        flat.text(cr, PAD, 66, "loading...", theme.dim)
        return
    end
    local d = parse(weather.rows)
    if not d.N then
        flat.header(cr, w, "weather", status, nil, "cloud")
        flat.font(cr, "Exo 2", 13)
        flat.text(cr, PAD, 66, "wttr.in unreachable", theme.dim)
        return
    end

    local place = d.L and d.L[2] or ""
    local icon = weather_icon(d.N[4] or "")
    flat.header(cr, w, "weather", place .. "  .  " .. status, nil, icon)
    flat.icon(cr, w - PAD - 34, 92, icon, 34, theme.dim)

    -- Now: big temperature, description and details to its right
    local _, temp, feels, desc, humidity, wind, rain = table.unpack(d.N)
    flat.font(cr, "Exo 2", 40)
    local temp_s = temp .. "°"
    flat.text(cr, PAD, 90, temp_s, theme.text)
    local x = PAD + flat.width(cr, temp_s) + 14

    flat.font(cr, "Exo 2", 14)
    flat.text(cr, x, 66, flat.fit(cr, desc, w - x - PAD - 44), theme.text)
    flat.font(cr, "Exo 2", 12)
    flat.text(cr, x, 86, string.format("feels %s°  .  %s%%  .  %s km/h", feels, humidity, wind), theme.dim)

    flat.font(cr, "Exo 2", 11)
    local rain_s = "rain " .. rain .. "%"
    local drop_w = flat.icon(cr, PAD, 115, "drop", 12, rain_color(rain))
    flat.font(cr, "Exo 2", 11)
    flat.text(cr, PAD + drop_w + 4, 114, rain_s, rain_color(rain))
    if d.S then
        local sun_s = d.S[2] .. " - " .. d.S[3]
        local sw = flat.width(cr, sun_s)
        flat.text_right(cr, w - PAD, 114, sun_s, theme.faint)
        flat.icon(cr, w - PAD - sw - 17, 115, "sun", 12, theme.faint)
    end

    -- Next hours: evenly spaced columns
    local col_w = (w - 2 * PAD) / math.max(#d.H, 1)
    for i, r in ipairs(d.H) do
        local cx = PAD + (i - 1) * col_w
        flat.font(cr, "Exo 2", 11)
        flat.text(cr, cx, 140, r[2], theme.faint)
        flat.font(cr, "Exo 2", 13)
        flat.text(cr, cx, 158, r[3] .. "°", theme.text)
        flat.font(cr, "Exo 2", 11)
        flat.text(cr, cx + 34, 158, r[4] .. "%", rain_color(r[4]))
    end

    flat.hline(cr, PAD, w - PAD, 172)

    -- Days: weekday, min / max, rain, description
    local y = 192
    for _, r in ipairs(d.D) do
        if y > h - 6 then break end
        local _, day, min_c, max_c, day_rain, day_desc = table.unpack(r)
        flat.font(cr, "Exo 2", 12)
        flat.text(cr, PAD, y, day, theme.text)
        flat.font(cr, "Exo 2", 12)
        flat.text(cr, PAD + 40, y, min_c .. "° / " .. max_c .. "°", theme.dim)
        flat.text(cr, PAD + 112, y, day_rain .. "%", rain_color(day_rain))
        flat.text(cr, PAD + 156, y, flat.fit(cr, day_desc, w - PAD * 2 - 156), theme.faint)
        y = y + 18
    end
end

-- Loaded by a wing window: hand over update/draw instead of becoming conky_main.
if WING then
    return { update = function() weather.update() end, draw = draw }
end

function conky_main()
    weather.update()
    flat.render("Weather", draw)
end
