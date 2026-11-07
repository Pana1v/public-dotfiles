local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
local theme = flat.theme

local weather = flat.snapshot("weather")
local events = flat.snapshot("events")

-- Ring radii, 1x units, around the centre of the window.
local R_TICKS_IN, R_TICKS_OUT, R_TICKS_MAJOR = 268, 280, 290
local R_DAY = 244
local R_NUMERALS = 318

local function line(cr, x1, y1, x2, y2, colour, alpha, width)
    flat.set_color(cr, colour, alpha)
    cairo_set_line_width(cr, width)
    cairo_move_to(cr, x1, y1)
    cairo_line_to(cr, x2, y2)
    cairo_stroke(cr)
end

local function centred(cr, face, size, cx, y, s, colour, bold)
    flat.font(cr, face, size, bold)
    flat.text(cr, cx - flat.width(cr, s) / 2, y, s, colour)
end

local function spaced_centred(cr, face, size, cx, y, s, colour, track, bold)
    flat.font(cr, face, size, bold)
    flat.spaced(cr, cx - flat.spaced_width(cr, s, track) / 2, y, s, colour, track)
end

-- "21°  smoky haze" from the weather feed, or nil before the first fetch.
local function weather_line()
    for _, r in ipairs(weather.rows or {}) do
        if r[1] == "N" then return string.format("%s°  %s", r[2] or "--", (r[4] or ""):lower()) end
    end
end

local function place()
    for _, r in ipairs(weather.rows or {}) do
        if r[1] == "L" and r[2] then return (r[2]:match("^[^,]+") or r[2]):upper() end
    end
    return nil
end

-- Next calendar event: running or upcoming timed event first, else an all-day one.
local function next_event(now)
    local timed, allday
    for _, r in ipairs(events.rows or {}) do
        if r[1] == "ev" then
            local start, stop = tonumber(r[2]) or 0, tonumber(r[3]) or 0
            if stop > now then
                if r[4] == "1" then allday = allday or { title = r[7], allday = true }
                else timed = timed or { title = r[7], start = start, stop = stop } end
            end
        end
    end
    return timed or allday
end

local function countdown(ev, now)
    if ev.allday then return "today", theme.dim end
    if ev.start <= now then return "now", theme.accent end
    local mins = math.ceil((ev.start - now) / 60)
    local colour = mins <= 30 and theme.yellow or theme.dim
    if mins < 60 then return string.format("in %dm", mins), colour end
    if mins < 24 * 60 then return string.format("in %dh %02dm", mins // 60, mins % 60), colour end
    return os.date("%a %H:%M", ev.start):lower(), colour
end

-- Central European time (CET / CEST) without touching TZ: EU summer time runs from
-- the last Sunday of March to the last Sunday of October, both at 01:00 UTC.
-- Returns the zone name, HH:MM and the offset in seconds.
local function local_offset() return os.time() - os.time(os.date("!*t")) end

local function cet(now)
    local y = tonumber(os.date("!%Y", now))
    local function last_sunday(month)
        -- os.time reads the table as local time, so add the local offset to land on UTC
        local t = os.time({ year = y, month = month, day = 31, hour = 1 }) + local_offset()
        return t - tonumber(os.date("!%w", t)) * 86400
    end
    local summer = now >= last_sunday(3) and now < last_sunday(10)
    local off = summer and 7200 or 3600
    return summer and "CEST" or "CET", os.date("!%H:%M", now + off), off
end

-- "+4:30" style gap between local time and CET.
local function gap_label(cet_off)
    local d = local_offset() - cet_off
    local sign = d < 0 and "-" or "+"
    d = math.abs(d)
    return string.format("%s%d:%02d", sign, d // 3600, d % 3600 // 60)
end

local function draw(cr, w, h)
    local cx, cy = w / 2, h / 2
    local now = os.time()
    local t = os.date("*t", now)
    local sec = t.sec

    -- Dark disc behind the dial so text stays readable over busy wallpapers.
    -- Solid to the tick ring, then fades out past the numerals.
    local br, bg, bb = flat.rgb(theme.bg, 1)
    local pat = cairo_pattern_create_radial(cx, cy, R_TICKS_IN - 20, cx, cy, R_NUMERALS + 40)
    cairo_pattern_add_color_stop_rgba(pat, 0, br, bg, bb, 0.86)
    cairo_pattern_add_color_stop_rgba(pat, 1, br, bg, bb, 0)
    cairo_set_source(cr, pat)
    cairo_arc(cr, cx, cy, R_NUMERALS + 40, 0, 2 * math.pi)
    cairo_fill(cr)
    cairo_pattern_destroy(pat)

    -- Seconds ring: 120 ticks, lit up to the current second, marker on the leading edge.
    for i = 0, 119 do
        local a = 2 * math.pi * i / 120 - math.pi / 2
        local major = i % 10 == 0
        local lit = i / 2 <= sec
        line(cr, cx + math.cos(a) * R_TICKS_IN, cy + math.sin(a) * R_TICKS_IN,
            cx + math.cos(a) * (major and R_TICKS_MAJOR or R_TICKS_OUT), cy + math.sin(a) * (major and R_TICKS_MAJOR or R_TICKS_OUT),
            lit and theme.text or theme.dim, lit and 0.85 or 0.3, major and 2 or 1)
    end
    local a = 2 * math.pi * sec / 60 - math.pi / 2
    flat.set_color(cr, theme.accent)
    cairo_new_sub_path(cr)
    cairo_arc(cr, cx + math.cos(a) * (R_TICKS_IN - 6), cy + math.sin(a) * (R_TICKS_IN - 6), 4, 0, 2 * math.pi)
    cairo_fill(cr)
    for i, n in ipairs({ "12", "3", "6", "9" }) do
        local ang = (i - 1) * math.pi / 2 - math.pi / 2
        centred(cr, "Orbitron", 12, cx + math.cos(ang) * R_NUMERALS, cy + math.sin(ang) * R_NUMERALS + 4, n, theme.text, true)
    end

    -- Day progress: a thick white band that fills as the day runs out,
    -- over a faint white track. Butt caps keep the ends square.
    local day = (t.hour * 3600 + t.min * 60 + t.sec) / 86400
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)
    cairo_set_line_width(cr, 12)
    flat.set_color(cr, "#ffffff", 0.12)
    cairo_new_sub_path(cr)
    cairo_arc(cr, cx, cy, R_DAY, 0, 2 * math.pi)
    cairo_stroke(cr)
    flat.set_color(cr, "#ffffff", 0.92)
    cairo_new_sub_path(cr)
    cairo_arc(cr, cx, cy, R_DAY, -math.pi / 2, -math.pi / 2 + 2 * math.pi * day)
    cairo_stroke(cr)

    -- Everything below is one block; lift it so the block, not the time, sits on the dial centre.
    cairo_save(cr)
    cairo_translate(cr, 0, -44)

    -- Time and seconds
    local zone, cet_time, cet_off = cet(now)
    local hhmm = os.date("%H:%M", now)
    centred(cr, "JetBrains Mono", 11, cx, cy - 110, string.format("%s AHEAD OF %s", gap_label(cet_off), zone), theme.yellow)
    -- HH:MM centred on the dial; seconds hang off its right edge, small enough
    -- to stay inside the day ring
    local ss = string.format("%02d", sec)
    flat.font(cr, "Orbitron", 104, true)
    local tw = flat.width(cr, hhmm)
    local tx = cx - tw / 2
    flat.text(cr, tx, cy - 14, hhmm, theme.text)
    flat.font(cr, "JetBrains Mono", 24)
    flat.text(cr, tx + tw + 6, cy - 14, ss, theme.dim)
    spaced_centred(cr, "JetBrains Mono", 11, cx, cy + 14,
        os.date("%Z") .. "  .  " .. (place() or "LOCAL"), theme.dim, 3)

    -- Date on one line
    spaced_centred(cr, "Exo 2", 17, cx, cy + 44,
        string.format("%s  %d %s", os.date("%a", now):upper(), tonumber(os.date("%d", now)), os.date("%b", now):upper()), theme.text, 5, true)
    flat.hline(cr, cx - 130, cx + 130, cy + 58)

    -- Other zones
    for i, z in ipairs({ { cet_time, zone .. "  .  BERLIN", theme.text }, { os.date("!%H:%M", now), "UTC", theme.dim } }) do
        local zx = cx + (i == 1 and -66 or 66)
        centred(cr, "Orbitron", 26, zx, cy + 92, z[1], z[3], true)
        spaced_centred(cr, "JetBrains Mono", 10, zx, cy + 112, z[2], theme.dim, 2)
    end

    -- Weather and what is next: each row (icon + text) is centred on the dial.
    local function icon_width(name, size)
        cairo_select_font_face(cr, "Symbols Nerd Font Mono", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, size)
        return flat.width(cr, utf8.char(flat.icons[name] or name))
    end
    local GAP = 10
    local wl = weather_line()
    flat.font(cr, "Exo 2", 17)
    local wtext = flat.fit(cr, wl or "weather loading...", 190)
    -- measure the text in its own font, before icon_width switches to the icon font
    local wtw = flat.width(cr, wtext)
    local wiw = icon_width("cloud", 24)
    local wx = cx - (wiw + GAP + wtw) / 2
    flat.icon(cr, wx, cy + 146, "cloud", 24, theme.dim)
    flat.font(cr, "Exo 2", 17)
    flat.text(cr, wx + wiw + GAP, cy + 144, wtext, wl and theme.text or theme.faint)

    local ev = next_event(now)
    local eiw = icon_width("agenda", 19)
    local etitle, when, colour, tw2, ww = nil, nil, nil, 0, 0
    if ev then
        when, colour = countdown(ev, now)
        flat.font(cr, "JetBrains Mono", 12)
        ww = flat.width(cr, when)
        flat.font(cr, "Exo 2", 15)
        etitle = flat.fit(cr, ev.title, 200 - ww - GAP)
    else
        flat.font(cr, "Exo 2", 15)
        etitle = events.rows and "nothing planned" or "calendar loading..."
    end
    tw2 = flat.width(cr, etitle)
    local total = eiw + GAP + tw2 + (ev and (GAP + ww) or 0)
    local ex = cx - total / 2
    flat.icon(cr, ex, cy + 174, "agenda", 19, theme.dim)
    flat.font(cr, "Exo 2", 15)
    flat.text(cr, ex + eiw + GAP, cy + 172, etitle, ev and theme.text or theme.faint)
    if ev then
        flat.font(cr, "JetBrains Mono", 12)
        flat.text(cr, ex + eiw + GAP + tw2 + GAP, cy + 172, when, colour)
    end

    centred(cr, "JetBrains Mono", 10, cx, cy + 204,
        string.format("WEEK %s  .  DAY %d  .  %d%% GONE", os.date("%V", now), t.yday, math.floor(day * 100)), theme.dim)
    cairo_restore(cr)
end

function conky_main()
    weather.update()
    events.update()
    flat.render("Clock", draw)
end
