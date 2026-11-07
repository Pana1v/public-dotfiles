local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
local theme, PAD = flat.theme, flat.PAD

local tasks = flat.snapshot("tasks")

local HEADER_H = 46
local ROW_H = 28
local FOOTER_H = 22
local STALE_S = 600

-- Layout, 1x units:
--   TASKS                               3 OPEN
--   [ ] Renew passport                    fri
--   [ ] Reply to landlord
--   [x] Pay electricity bill

local function parse(rows)
    local status, message, list = "ok", "", {}
    for _, r in ipairs(rows) do
        if r[1] == "status" then
            status, message = r[2] or "ok", r[3] or ""
        elseif r[1] == "task" then
            list[#list + 1] = { due = tonumber(r[2]) or 0, done = r[3] == "1", list = r[4] or "", title = r[5] or "" }
        end
    end
    return status, message, list
end

local function midnight(t)
    local d = os.date("*t", t)
    return os.time({ year = d.year, month = d.month, day = d.day, hour = 0 })
end

-- Right-hand due tag: overdue red, today yellow, soon dim, later faint.
local function due_tag(due, today0)
    if due == 0 then return nil end
    local diff = math.floor((midnight(due) - today0) / 86400 + 0.5)
    if diff < 0 then return "overdue", theme.red end
    if diff == 0 then return "today", theme.yellow end
    if diff == 1 then return "tomorrow", theme.dim end
    if diff < 7 then return os.date("%a", due):lower(), theme.dim end
    return string.format("%d %s", tonumber(os.date("%d", due)), os.date("%b", due):lower()), theme.faint
end

local function box(cr, x, y, done)
    flat.set_color(cr, done and theme.green or theme.dim)
    cairo_set_line_width(cr, 1.3)
    cairo_rectangle(cr, x + 0.5, y + 0.5, 12, 12)
    cairo_stroke(cr)
    if done then flat.icon(cr, x - 1, y + 13, "check", 14, theme.green) end
end

local function notice(cr, w, h, icon, colour, title, detail)
    local cy = HEADER_H + (h - HEADER_H) / 2
    flat.icon(cr, w / 2 - 14, cy - 4, icon, 30, colour)
    flat.font(cr, "Exo 2", 13)
    flat.text(cr, (w - flat.width(cr, title)) / 2, cy + 22, title, theme.text)
    if detail then
        flat.font(cr, "Exo 2", 11)
        flat.text(cr, (w - flat.width(cr, detail)) / 2, cy + 40, detail, theme.dim)
    end
end

local function draw(cr, w, h)
    flat.card(cr, w, h)

    if not tasks.rows then
        flat.header(cr, w, "tasks", "", nil, "check")
        flat.font(cr, "Exo 2", 13)
        return flat.text(cr, PAD, HEADER_H + 20, "loading...", theme.dim)
    end

    local status, message, list = parse(tasks.rows)
    local open = 0
    for _, t in ipairs(list) do if not t.done then open = open + 1 end end
    local stale = os.time() - (tasks.last_success or 0) > STALE_S

    local label, label_colour = open .. " open", theme.faint
    if status == "setup" and #list == 0 then label, label_colour = "setup", theme.yellow end
    if status == "error" then label, label_colour = "error", theme.red end
    if stale then label, label_colour = "stale", theme.yellow end
    flat.header(cr, w, "tasks", label, label_colour, "check")

    if status == "error" and #list == 0 then
        return notice(cr, w, h, "alert", theme.red, "tasks unavailable", flat.fit(cr, message, w - 2 * PAD))
    end
    if status == "setup" and #list == 0 then
        return notice(cr, w, h, "check", theme.dim, "no task list connected",
            message:find("gir1.2", 1, true) and "sudo apt install gir1.2-ecal-2.0" or "Online Accounts > Google > Tasks")
    end
    if #list == 0 then return notice(cr, w, h, "check", theme.green, "all clear", nil) end

    local today0 = midnight(os.time())
    local fit_rows = math.max(1, math.floor((h - HEADER_H - FOOTER_H) / ROW_H))
    local shown = math.min(#list, fit_rows)
    for i = 1, shown do
        local t = list[i]
        local y = HEADER_H + 14 + (i - 1) * ROW_H
        box(cr, PAD, y, t.done)

        local right = w - PAD
        local tag, tag_colour = due_tag(t.due, today0)
        if tag and not t.done then
            flat.font(cr, "JetBrains Mono", 10)
            flat.text_right(cr, right, y + 11, tag, tag_colour)
            right = right - flat.width(cr, tag) - 10
        end
        flat.font(cr, "Exo 2", 13)
        flat.text(cr, PAD + 24, y + 11, flat.fit(cr, t.title, right - PAD - 24), t.done and theme.faint or theme.text)
    end
    if shown < #list then
        flat.font(cr, "JetBrains Mono", 10)
        flat.text_right(cr, w - PAD, h - 8, string.format("+%d more", #list - shown), theme.faint)
    end
end

if WING then
    return { update = function() tasks.update() end, draw = draw }
end

function conky_main()
    if flat.profile() == "professional" then return end
    tasks.update()
    flat.render("Tasks", draw)
end
