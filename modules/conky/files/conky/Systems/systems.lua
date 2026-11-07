local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
local theme, PAD = flat.theme, flat.PAD

local snap = flat.snapshot("sysmon")

local HISTORY = 60          -- samples kept for the graphs (one per feed run)
local WARN, HOT = 70, 90    -- percent where a gauge turns yellow / red

local data = {}
local cpu_hist, net_hist = {}, {}
local last_ts

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
    return theme.accent
end

local function bytes(n)
    if n >= 1048576 then return string.format("%.1fM", n / 1048576) end
    if n >= 1024 then return string.format("%.0fK", n / 1024) end
    return string.format("%dB", n)
end

local function gib(kib) return string.format("%.1f", kib / 1048576) end

-- 270 degree gauge with a tick bezel: sweeps from bottom left, clockwise over the top.
local function gauge(cr, cx, cy, r, pct, title, value, colour)
    local a0, a1 = 0.75 * math.pi, 2.25 * math.pi
    local frac = math.max(0, math.min(pct / 100, 1))
    local small = r < 34                    -- the secondary dials get a calmer bezel
    local n = small and 18 or 36
    for i = 0, n do
        local a = a0 + (a1 - a0) * i / n
        local lit = i / n <= frac and frac > 0
        local long = i % (small and 3 or 6) == 0
        flat.set_color(cr, lit and colour or theme.dim, lit and 0.9 or 0.35)
        cairo_set_line_width(cr, 1)
        cairo_move_to(cr, cx + math.cos(a) * (r + 9), cy + math.sin(a) * (r + 9))
        cairo_line_to(cr, cx + math.cos(a) * (r + (long and 16 or 13)), cy + math.sin(a) * (r + (long and 16 or 13)))
        cairo_stroke(cr)
    end
    cairo_set_line_width(cr, small and 5 or 7)
    flat.set_color(cr, theme.bar_bg)
    cairo_new_sub_path(cr)
    cairo_arc(cr, cx, cy, r, a0, a1)
    cairo_stroke(cr)
    flat.set_color(cr, colour)
    cairo_new_sub_path(cr)
    cairo_arc(cr, cx, cy, r, a0, a0 + (a1 - a0) * math.max(frac, 0.015))
    cairo_stroke(cr)
    flat.font(cr, "Exo 2", small and 14 or r * 0.5, true)
    flat.text(cr, cx - flat.width(cr, value) / 2, cy + (small and 5 or r * 0.18), value, theme.text)
    flat.font(cr, "Orbitron", small and 9 or 10, true)
    flat.text(cr, cx - flat.width(cr, title) / 2, cy + r + 14, title, theme.dim)
end

local function draw_gauges(cr, w, h)
    flat.card(cr, w, h)
    local host = (data.net and data.net[4] and data.net[4] ~= "-") and data.net[4] or "offline"
    flat.header(cr, w, "systems", host, nil, "chip")

    local cpu = tonumber(data.cpu and data.cpu[2]) or 0
    local gpu = tonumber(data.gpu and data.gpu[2]) or 0
    local mem = tonumber(data.mem and data.mem[2]) or 0
    local gpu_state = data.gpu and data.gpu[5] or "none"
    local r, cy = 42, 112
    gauge(cr, w * 1 / 6, cy, r, cpu, "CPU", cpu .. "%", load_colour(cpu))
    gauge(cr, w * 3 / 6, cy, r, gpu, gpu_state == "sleep" and "GPU . SLEEP" or "GPU", gpu .. "%", load_colour(gpu))
    gauge(cr, w * 5 / 6, cy, r, mem, "MEM", mem .. "%", load_colour(mem))

    -- Second row, smaller: integrated GPU and NPU, tucked between the main dials.
    local ig = tonumber(data.igpu and data.igpu[2]) or 0
    local npu = tonumber(data.npu and data.npu[2]) or 0
    local npu_state = data.npu and data.npu[3] or "none"
    local r2, cy2 = 26, 222
    gauge(cr, w * 2 / 6, cy2, r2, ig, "iGPU", ig .. "%", load_colour(ig))
    if npu_state == "none" then
        gauge(cr, w * 4 / 6, cy2, r2, 0, "NPU . N/A", "--", theme.dim)
    else
        gauge(cr, w * 4 / 6, cy2, r2, npu, npu_state == "suspended" and "NPU . SLEEP" or "NPU", npu .. "%", load_colour(npu))
    end

    local function temp(row) local t = row and row[3] or "-" return t == "-" and "--" or (t .. "°") end
    local m = data.mem
    local line = string.format("%s  .  %s  .  %s/%sG  .  SWAP %s%%", temp(data.cpu), temp(data.gpu),
        m and gib(tonumber(m[3]) or 0) or "--", m and gib(tonumber(m[4]) or 0) or "--", data.swap and data.swap[2] or "0")
    flat.font(cr, "JetBrains Mono", 10)
    flat.text(cr, (w - flat.width(cr, line)) / 2, h - 8, line, theme.faint)
end

-- Filled area sparkline with a faint grid, scaled to its own peak (floor keeps idle flat).
local function spark(cr, x, y, w, h, hist, floor, colour)
    for i = 0, 3 do flat.hline(cr, x, x + w, y + h * i / 3 - 0.5) end
    if #hist < 2 then return end
    local peak = floor
    for _, v in ipairs(hist) do peak = math.max(peak, v) end
    local function pt(i, v) return x + w * (i - 1) / (HISTORY - 1) + w * (HISTORY - #hist) / (HISTORY - 1), y + h * (1 - v / peak) end
    local x0 = pt(1, 0)
    cairo_move_to(cr, x0, y + h)
    for i, v in ipairs(hist) do cairo_line_to(cr, pt(i, v)) end
    cairo_line_to(cr, x + w, y + h)
    cairo_close_path(cr)
    flat.set_color(cr, colour, 0.14)
    cairo_fill(cr)
    for i, v in ipairs(hist) do
        local px, py = pt(i, v)
        if i == 1 then cairo_move_to(cr, px, py) else cairo_line_to(cr, px, py) end
    end
    flat.set_color(cr, colour, 0.9)
    cairo_set_line_width(cr, 1.5)
    cairo_stroke(cr)
end

-- CPU and network graphs side by side, a disk bar underneath. The graphs take
-- whatever height is left, so the section works from about 130 px upward.
local function draw_activity(cr, w, h)
    flat.card(cr, w, h)
    flat.header(cr, w, "activity", "last 2 min", nil, "chip")

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
    flat.text_right(cr, x2 + col, 66, string.format("v %s  ^ %s", bytes(down), bytes(up)), theme.text)
    spark(cr, x2, gy, col, gh, net_hist, 51200, theme.accent)

    local disk = data.disk
    flat.font(cr, "JetBrains Mono", 10)
    flat.text(cr, PAD, h - 8, "DISK", theme.dim)
    flat.ticks(cr, PAD + 40, h - 15, w - 2 * PAD - 160, 4, (tonumber(disk and disk[2]) or 0) / 100, theme.text)
    flat.text_right(cr, w - PAD, h - 8, disk and string.format("%s / %sG", disk[3], disk[4]) or "--", theme.text)
end

return { update = update, draw_gauges = draw_gauges, draw_activity = draw_activity }
