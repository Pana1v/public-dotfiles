local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
local theme, PAD = flat.theme, flat.PAD

local snap = flat.snapshot("docker")

local HEADER_H = 46
local ROW_H = 24
local MAX_ROWS = 4
local FOOTER_H = 30
local NAME_W = 150
local IMAGE_W = 100
local STALE_SECONDS = 60   -- feeder runs every 10s; older means it stalled

-- Rows by kind: S = summary, C = container (see fetch_docker.py).
local function parse(rows)
    local info = { containers = {} }
    for _, r in ipairs(rows) do
        if r[1] == "E" then info.err = r[2] end
        if r[1] == "S" then
            info.running, info.total = tonumber(r[2]), tonumber(r[3])
            info.domain, info.rmw = r[4], r[5]
        end
        if r[1] == "C" then
            info.containers[#info.containers + 1] = { name = r[2], image = r[3], up = r[4], cpu = r[5], mem = r[6] }
        end
    end
    return info
end

local function note(cr, y, s)
    flat.font(cr, "Exo 2", 13)
    flat.text(cr, PAD, y, s, theme.dim)
end

local function draw_row(cr, w, y, c)
    flat.font(cr, "Exo 2", 12)
    flat.text(cr, PAD, y, flat.fit(cr, c.name, NAME_W), theme.text)
    flat.font(cr, "Exo 2", 11)
    flat.text(cr, PAD + NAME_W + 8, y, flat.fit(cr, c.image, IMAGE_W), theme.faint)
    local right = w - PAD
    for _, col in ipairs({ { c.mem, 64 }, { c.cpu, 56 }, { c.up, 36 } }) do
        flat.text_right(cr, right, y, col[1], theme.dim)
        right = right - col[2]
    end
end

local function draw(cr, w, h)
    flat.card(cr, w, h)

    if not snap.rows then
        flat.header(cr, w, "docker", "", nil, "robot")
        note(cr, HEADER_H + 20, "loading...")
        return
    end

    local info = parse(snap.rows)
    local stale = snap.last_success and os.time() - snap.last_success > STALE_SECONDS
    if info.err or stale then
        flat.header(cr, w, "docker", "offline", theme.yellow, "robot")
        note(cr, HEADER_H + 20, info.err or "feeder stalled")
        return
    end

    flat.header(cr, w, "docker", string.format("%d / %d running", info.running, info.total), nil, "robot")
    flat.ticks(cr, PAD, HEADER_H - 6, w - 2 * PAD, 6, info.total > 0 and info.running / info.total or 0, theme.accent)

    local y = HEADER_H + 22
    if #info.containers == 0 then
        note(cr, y, "no containers running")
    end
    for i, c in ipairs(info.containers) do
        if i > MAX_ROWS then
            flat.font(cr, "Exo 2", 11)
            flat.text(cr, PAD, y, string.format("+%d more", #info.containers - MAX_ROWS), theme.faint)
            break
        end
        draw_row(cr, w, y, c)
        y = y + ROW_H
    end

    flat.font(cr, "Exo 2", 11)
    flat.text(cr, PAD, h - 12, flat.fit(cr, "ros domain " .. info.domain .. "  .  " .. info.rmw, w - 2 * PAD), theme.faint)
end

local function size()
    return HEADER_H + 22 + MAX_ROWS * ROW_H + FOOTER_H
end

-- Loaded by a wing window: hand over update/draw instead of becoming conky_main.
if WING then
    return { update = function() snap.update() end, draw = draw, size = size }
end

function conky_main()
    snap.update()
    flat.render("DockerCard", draw)
end
