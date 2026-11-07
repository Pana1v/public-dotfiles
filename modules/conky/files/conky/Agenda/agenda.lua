local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
local theme, PAD = flat.theme, flat.PAD

local events = flat.snapshot("events")

local HEADER_H = 46
local DAY_H = 26
local ROW_H = 38
local FOOTER_H = 24
local TIME_W = 56
local SOON_MIN = 30        -- yellow countdown inside this many minutes
local COUNTDOWN_MIN = 180  -- show "in 2h 10m" for events this close
local STALE_S = 600        -- feed runs every 2 minutes

-- Layout, 1x units:
--   AGENDA                                5 UPCOMING
--   TODAY ───────────────────────── FRI 31 OCT
--   14:30  │ Design review                  in 25m
--   15:30  │ 󰍹 Zoom                               (video or pin + place)
--   TOMORROW ────────────────────── SAT 1 NOV
--   ALL DAY│ Dad's birthday

local function parse(rows)
    local status, message, list = "ok", "", {}
    for _, r in ipairs(rows) do
        if r[1] == "status" then
            status, message = r[2] or "ok", r[3] or ""
        elseif r[1] == "ev" then
            list[#list + 1] = {
                start = tonumber(r[2]) or 0, stop = tonumber(r[3]) or 0, allday = r[4] == "1",
                cal = r[5] or "", video = r[6] == "1", title = r[7] or "", where = r[8] or "",
            }
        end
    end
    return status, message, list
end

local function midnight(t)
    local d = os.date("*t", t)
    return os.time({ year = d.year, month = d.month, day = d.day, hour = 0 })
end

-- "today", "tomorrow", else the weekday name.
local function day_label(day0, today0)
    local diff = math.floor((day0 - today0) / 86400 + 0.5)
    if diff <= 0 then return "today" end
    if diff == 1 then return "tomorrow" end
    return os.date("%A", day0):lower()
end

local function countdown(mins)
    if mins < 60 then return string.format("in %dm", mins) end
    return string.format("in %dh %02dm", mins // 60, mins % 60)
end

-- Accent for the stripe and countdown: green while running, yellow when close.
local function accent(ev, now)
    if not ev.allday and ev.start <= now and ev.stop > now then return theme.green, "now" end
    local mins = math.ceil((ev.start - now) / 60)
    if not ev.allday and mins > 0 and mins <= SOON_MIN then return theme.yellow, countdown(mins) end
    if not ev.allday and mins > 0 and mins <= COUNTDOWN_MIN then return theme.dim, countdown(mins) end
    return theme.bar_bg, nil
end

local function draw_day(cr, w, y, label, day0)
    flat.font(cr, "Orbitron", 9, true)
    flat.spaced(cr, PAD, y + 16, label:upper(), theme.dim, 1.5)
    local lw = flat.spaced_width(cr, label:upper(), 1.5)
    flat.font(cr, "JetBrains Mono", 10)
    local date = string.format("%s %d %s", os.date("%a", day0), tonumber(os.date("%d", day0)), os.date("%b", day0)):upper()
    local dw = flat.width(cr, date)
    flat.text_right(cr, w - PAD, y + 16, date, theme.faint)
    flat.hline(cr, PAD + lw + 10, w - PAD - dw - 10, y + 12)
end

local function draw_event(cr, w, y, ev, now)
    local colour, when = accent(ev, now)
    local running = colour == theme.green

    -- Time column.
    if ev.allday then
        flat.font(cr, "JetBrains Mono", 9)
        flat.text(cr, PAD, y + 15, "ALL DAY", theme.faint)
    else
        flat.font(cr, "JetBrains Mono", 12)
        flat.text(cr, PAD, y + 15, os.date("%H:%M", ev.start), running and theme.text or theme.dim)
        flat.font(cr, "JetBrains Mono", 10)
        flat.text(cr, PAD, y + 29, os.date("%H:%M", ev.stop), theme.faint)
    end

    -- Stripe: lit while running or close, hairline otherwise.
    flat.set_color(cr, colour)
    cairo_rectangle(cr, PAD + TIME_W, y + 2, 2, ROW_H - 8)
    cairo_fill(cr)

    local x = PAD + TIME_W + 12
    local right = w - PAD
    if when then
        flat.font(cr, "JetBrains Mono", 10)
        flat.text_right(cr, right, y + 15, when, colour)
        right = right - flat.width(cr, when) - 10
    end

    flat.font(cr, "Exo 2", 13)
    flat.text(cr, x, y + 15, flat.fit(cr, ev.title, right - x), theme.text)

    -- Second line: where, with a camera for video calls and a pin otherwise.
    local sub, icon = ev.where, ev.video and "video" or "pin"
    if sub == "" and ev.video then sub = "video call" end
    if sub == "" and not ev.allday then
        local mins = math.floor((ev.stop - ev.start) / 60 + 0.5)
        sub, icon = (mins >= 60 and string.format("%dh%s", mins // 60, mins % 60 > 0 and string.format(" %dm", mins % 60) or "") or (mins .. "m")), "clock"
    end
    if sub ~= "" then
        local iw = flat.icon(cr, x, y + 31, icon, 11, theme.faint)
        flat.font(cr, "Exo 2", 11)
        flat.text(cr, x + iw + 5, y + 30, flat.fit(cr, sub, w - PAD - x - iw - 5), theme.dim)
    end
end

-- Centered message with a big icon, for setup/error/empty states.
local function notice(cr, w, h, icon, colour, title, detail)
    local cy = HEADER_H + (h - HEADER_H) / 2
    flat.icon(cr, w / 2 - 17, cy - 8, icon, 36, colour)
    flat.font(cr, "Exo 2", 14)
    flat.text(cr, (w - flat.width(cr, title)) / 2, cy + 22, title, theme.text)
    flat.font(cr, "Exo 2", 11)
    for i, line in ipairs(detail) do
        flat.text(cr, (w - flat.width(cr, line)) / 2, cy + 22 + 18 * i, line, theme.dim)
    end
end

local function draw(cr, w, h)
    flat.card(cr, w, h)

    if not events.rows then
        flat.header(cr, w, "agenda", "", nil, "agenda")
        flat.font(cr, "Exo 2", 13)
        return flat.text(cr, PAD, HEADER_H + 20, "loading...", theme.dim)
    end

    local status, message, list = parse(events.rows)
    local now = os.time()
    local stale = now - (events.last_success or 0) > STALE_S

    local label = #list .. " upcoming"
    local label_colour = theme.faint
    if status == "setup" and #list == 0 then label, label_colour = "setup", theme.yellow end
    if status == "error" then label, label_colour = "error", theme.red end
    if stale then label, label_colour = "stale", theme.yellow end
    flat.header(cr, w, "agenda", label, label_colour, "agenda")

    if status == "error" and #list == 0 then
        return notice(cr, w, h, "alert", theme.red, "calendar unavailable", { flat.fit(cr, message, w - 2 * PAD) })
    end
    if status == "setup" and #list == 0 then
        local lines = message:find("gir1.2", 1, true)
            and { "install the calendar library:", "sudo apt install gir1.2-ecal-2.0" }
            or { "Settings > Online Accounts > Google", "turn Calendar on" }
        return notice(cr, w, h, "calendar", theme.dim, "no calendar connected", lines)
    end
    if #list == 0 then
        return notice(cr, w, h, "check", theme.green, "nothing coming up", { "the next 3 days are clear" })
    end

    -- Group by day (events already running count as today), then draw while there is room.
    local today0 = midnight(now)
    local y, shown, current = HEADER_H + 4, 0, nil
    local limit = h - FOOTER_H
    for _, ev in ipairs(list) do
        local day0 = math.max(midnight(ev.start), today0)
        local need = ROW_H + (day0 ~= current and DAY_H or 0)
        if y + need > limit then break end
        if day0 ~= current then
            draw_day(cr, w, y, day_label(day0, today0), day0)
            y, current = y + DAY_H, day0
        end
        draw_event(cr, w, y, ev, now)
        y, shown = y + ROW_H, shown + 1
    end

    if shown < #list then
        local more = string.format("+%d more", #list - shown)
        flat.font(cr, "JetBrains Mono", 10)
        flat.text_right(cr, w - PAD, h - 9, more, theme.faint)
    end
end

-- Loaded by a wing window: hand over update/draw instead of becoming conky_main.
if WING then
    return { update = function() events.update() end, draw = draw }
end

function conky_main()
    events.update()
    flat.render("Agenda", draw)
end
