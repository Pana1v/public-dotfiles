local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
local theme, PAD = flat.theme, flat.PAD

local snap = flat.snapshot("sysmon")

local HISTORY = 60          -- samples kept for the graphs (one per feed run)
local WARN, HOT = 70, 90    -- percent where a gauge turns yellow / red

local data = {}
local cpu_hist, net_hist = {}, {}
local last_ts

-- Previews render one frame, so give the charts a minute of made-up history.
if os.getenv("CONKY_PREVIEW") then
    for i = 1, HISTORY do
        cpu_hist[i] = 12 + 10 * math.sin(i / 4) + (i * 7 % 11)
        net_hist[i] = 30000 + 40000 * math.abs(math.sin(i / 6)) + (i * 3731 % 20000)
    end
end

local function push(hist, v)
    hist[#hist + 1] = v
    if #hist > HISTORY then table.remove(hist, 1) end
end

local function update()
    snap.update()
    if not snap.rows or snap.last_success == last_ts then return end
    last_ts = snap.last_success
    data = {}
    for _, r in ipairs(snap.rows) do data[r[1]] = r end
    push(cpu_hist, tonumber(data.cpu and data.cpu[2]) or 0)
    push(net_hist, tonumber(data.net and data.net[2]) or 0)
end

local function load_colour(pct)
    if pct >= HOT then return theme.red end
    if pct >= WARN then return theme.yellow end
    return theme.text
end

local function bytes(n)
    if n >= 1048576 then return string.format("%.1fM", n / 1048576) end
    if n >= 1024 then return string.format("%.0fK", n / 1024) end
    return string.format("%dB", n)
end

local function gib(kib) return string.format("%.1f", kib / 1048576) end

-- 270 degree dot ring, Nothing style: dots sweep from bottom left clockwise
-- over the top, lit ones white, the leading dot in the accent. The value sits
-- in the middle in dot-matrix type.
local function gauge(cr, cx, cy, r, pct, title, value, colour)
    local a0, a1 = 0.75 * math.pi, 2.25 * math.pi
    local frac = math.max(0, math.min(pct / 100, 1))
    local small = r < 34
    local n = small and 22 or 34
    local lit = math.floor(n * frac + 0.5)
    local dr = small and 1.7 or 2.1
    for i = 0, n - 1 do
        local a = a0 + (a1 - a0) * i / (n - 1)
        local on = i < lit
        if on and i == lit - 1 then
            flat.set_color(cr, theme.text)          -- white cursor dot at the tip
        elseif on then
            flat.set_color(cr, colour == theme.text and theme.accent or colour)
        else
            flat.set_color(cr, theme.bar_bg)
        end
        flat.dot(cr, cx + math.cos(a) * r, cy + math.sin(a) * r, on and dr or dr * 0.75)
        cairo_fill(cr)
    end
    -- faint inner ring of fine dots for depth
    if not small then
        flat.set_color(cr, theme.grid)
        for i = 0, 47 do
            local a = 2 * math.pi * i / 48
            flat.dot(cr, cx + math.cos(a) * (r - 9), cy + math.sin(a) * (r - 9), 0.8)
        end
        cairo_fill(cr)
    end
    if small then value = value:gsub("%%", "") end
    local vh = small and 14 or 21
    flat.dm(cr, cx - flat.dm_width(value, vh) / 2, cy + vh / 2, value, vh, theme.text)
    flat.font(cr, "Space Mono", small and 9.5 or 11)
    flat.text(cr, cx - flat.width(cr, title) / 2, cy + r + (small and 13 or 16), title, theme.dim)
end

local function draw_gauges(cr, w, h)
    flat.card(cr, w, h)
    local host = (data.net and data.net[4] and data.net[4] ~= "-") and data.net[4] or "offline"
    flat.header(cr, w, "systems", host, nil, "chip")

    local cpu = tonumber(data.cpu and data.cpu[2]) or 0
    local gpu = tonumber(data.gpu and data.gpu[2]) or 0
    local mem = tonumber(data.mem and data.mem[2]) or 0
    local gpu_state = data.gpu and data.gpu[5] or "none"
    local r, cy = 44, 112
    gauge(cr, w * 1 / 6, cy, r, cpu, "CPU", cpu .. "%", load_colour(cpu))
    gauge(cr, w * 3 / 6, cy, r, gpu, gpu_state == "sleep" and "GPU . SLEEP" or "GPU", gpu .. "%", load_colour(gpu))
    gauge(cr, w * 5 / 6, cy, r, mem, "MEM", mem .. "%", load_colour(mem))

    -- Second row, smaller: integrated GPU and NPU, tucked between the main dials.
    local ig = tonumber(data.igpu and data.igpu[2]) or 0
    local npu = tonumber(data.npu and data.npu[2]) or 0
    local npu_state = data.npu and data.npu[3] or "none"
    local r2, cy2 = 28, 214
    gauge(cr, w * 2 / 6, cy2, r2, ig, "iGPU", ig .. "%", load_colour(ig))
    if npu_state == "none" then
        gauge(cr, w * 4 / 6, cy2, r2, 0, "NPU . N/A", "--", theme.dim)
    else
        gauge(cr, w * 4 / 6, cy2, r2, npu, npu_state == "suspended" and "NPU . SLEEP" or "NPU", npu .. "%", load_colour(npu))
    end

    local function temp(row) local t = row and row[3] or "-" return t == "-" and "--" or (t .. "°") end
    local m = data.mem
    local line = string.format("%s  /  %s  /  %s/%sG  /  SWAP %s%%", temp(data.cpu), temp(data.gpu),
        m and gib(tonumber(m[3]) or 0) or "--", m and gib(tonumber(m[4]) or 0) or "--", data.swap and data.swap[2] or "0")
    flat.font(cr, "Space Mono", 10.5)
    flat.text(cr, (w - flat.width(cr, line)) / 2, h - 10, line, theme.faint)
end

-- Dot-matrix column chart: one column per sample, newest on the right,
-- scaled to its own peak (floor keeps idle flat). The newest few columns
-- light in the accent, the rest white, the empty grid in faint dots.
local PITCH = 6
local function spark(cr, x, y, w, h, hist, floor, colour)
    local cols = math.floor(w / PITCH)
    local rows = math.floor(h / PITCH)
    local peak = floor
    for _, v in ipairs(hist) do peak = math.max(peak, v) end
    flat.set_color(cr, theme.grid)
    for c = 0, cols - 1 do
        for r = 0, rows - 1 do flat.dot(cr, x + c * PITCH + 2.5, y + r * PITCH + 2.5, 0.9) end
    end
    cairo_fill(cr)
    for c = 0, cols - 1 do
        local v = hist[#hist - (cols - 1 - c)]
        if v then
            local lit = math.max(v > 0 and 1 or 0, math.floor(rows * v / peak + 0.5))
            flat.set_color(cr, (cols - 1 - c) < 10 and theme.accent or colour)
            for r = 0, lit - 2 do flat.dot(cr, x + c * PITCH + 2.5, y + (rows - 1 - r) * PITCH + 2.5, 1.6) end
            cairo_fill(cr)
            -- every column's peak dot in the accent
            if lit > 0 then
                flat.set_color(cr, theme.accent)
                flat.dot(cr, x + c * PITCH + 2.5, y + (rows - lit) * PITCH + 2.5, 1.8)
                cairo_fill(cr)
            end
        end
    end
end

-- CPU and network graphs side by side, a disk bar underneath. The graphs take
-- whatever height is left, so the section works from about 130 px upward.
local function draw_activity(cr, w, h)
    flat.card(cr, w, h)
    flat.header(cr, w, "activity", "last 60 s", nil, "chip")

    local gap = 16
    local col = (w - 2 * PAD - gap) / 2
    local x1, x2 = PAD, PAD + col + gap
    local gy = 76
    local gh = math.max(h - gy - 32, 20)

    local cpu = tonumber(data.cpu and data.cpu[2]) or 0
    flat.font(cr, "JetBrains Mono", 10)
    flat.text(cr, x1, 66, "CPU", theme.dim)
    flat.text_right(cr, x1 + col, 66, cpu .. "%", theme.text)
    spark(cr, x1, gy, col, gh, cpu_hist, 20, theme.text)

    local down, up = tonumber(data.net and data.net[2]) or 0, tonumber(data.net and data.net[3]) or 0
    flat.font(cr, "JetBrains Mono", 10)
    flat.text(cr, x2, 66, "NET", theme.dim)
    flat.text_right(cr, x2 + col, 66, string.format("%s / %s", bytes(down), bytes(up)), theme.text)
    spark(cr, x2, gy, col, gh, net_hist, 51200, theme.text)

    local disk = data.disk
    flat.font(cr, "JetBrains Mono", 10)
    flat.text(cr, PAD, h - 8, "DISK", theme.dim)
    flat.ticks(cr, PAD + 40, h - 15, w - 2 * PAD - 160, 4, (tonumber(disk and disk[2]) or 0) / 100, theme.text)
    flat.text_right(cr, w - PAD, h - 8, disk and string.format("%s / %sG", disk[3], disk[4]) or "--", theme.text)
end

return { update = update, draw_gauges = draw_gauges, draw_activity = draw_activity }
