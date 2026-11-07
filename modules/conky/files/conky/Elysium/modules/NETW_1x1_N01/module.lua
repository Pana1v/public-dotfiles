-- =====================================================
--  Network rates card (down/up readouts with tick bars)
-- =====================================================

local M = {}
local flat = dofile(os.getenv("HOME") .. "/.config/conky/Common/flat.lua")

-- =====================================================
-- Config
-- =====================================================
local CARD_W = 134
local CARD_H = 134

local HISTORY_SIZE = 60
local MIN_SCALE_KB = 10

-- =====================================================
-- Color Config
-- =====================================================
local HOME = os.getenv("HOME") or ""
local COLOR_CONF = HOME .. "/.config/conky/Elysium/modules/NETW_1x1_A01/color.conf"

local color_map = {
    up   = "red",
    down = "blue"
}

local function load_color_conf()
    local f = io.open(COLOR_CONF, "r")
    if not f then return end

    for line in f:lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")

        if line ~= "" and not line:match("^#") and not line:match("^%-%-") then
            local k,v = line:match("(%w+)%s*=%s*(%w+)")
            if k and v then
                color_map[k] = v
            end
        end
    end

    f:close()
end

load_color_conf()

-- =====================================================
-- Buffers
-- =====================================================
local down_hist = {}
local up_hist   = {}

-- =====================================================
-- Resolve Interface
-- =====================================================
local function resolve_iface(ctx)
    return ctx and ctx.runtime and ctx.runtime.net_iface
end

-- =====================================================
-- Connection Detail
-- =====================================================
local function get_connection_detail(ctx)

    local iface = ctx.runtime.net_iface
    local ntype = ctx.runtime.net_type or "none"

    if not iface then
        return "Network Unavailable"
    end

    if ntype == "wifi" then
        local ssid = conky_parse("${exec iwgetid -r 2>/dev/null}")
        return (ssid ~= "" and ("Wi-Fi : " .. ssid)) or "Wi-Fi"
    end

    if ntype == "lan" then
        return "Wired Connection"
    end

    if ntype == "usb" then
        return "USB Tethering"
    end

    return "Network Unavailable"
end

-- =====================================================
-- Container
-- =====================================================
function M.draw_rect(ctx)
    flat.card_at(ctx.cr, ctx.x, ctx.y, CARD_W, CARD_H)
end

-- =====================================================
-- Update (FIXED - ALWAYS RUN)
-- =====================================================
function M.update(ctx)

    if not conky_window then return end

    local iface = resolve_iface(ctx)

    local down, up = 0, 0

    if iface then
        down = tonumber(conky_parse('${downspeedf ' .. iface .. '}')) or 0
        up   = tonumber(conky_parse('${upspeedf ' .. iface .. '}')) or 0
    end

    table.insert(down_hist, 1, down)
    table.insert(up_hist,   1, up)

    if #down_hist > HISTORY_SIZE then table.remove(down_hist) end
    if #up_hist   > HISTORY_SIZE then table.remove(up_hist)   end
end

-- =====================================================
-- Rates: mono readouts over tick bars, one shared scale
-- =====================================================
--   WI-FI          home-5g
--   DN            1.2 MB/s
--   ||||||||||::::::::::::
--   UP            158 KB/s
--   ||::::::::::::::::::::
--   192.168.1.23   pk 4.1M
local PAD_X = 12
local INNER_W = CARD_W - 2 * PAD_X

-- Long connection names don't fit the spaced title.
local TITLES = {
    ["Wired Connection"] = "LAN",
    ["USB Tethering"] = "USB",
    ["Network Unavailable"] = "OFFLINE",
}

local function peak(hist)
    local max = MIN_SCALE_KB
    for _, v in ipairs(hist) do
        if v > max then max = v end
    end
    return max
end

local function format_rate(kb)
    if kb >= 1024 then return string.format("%.1f MB/s", kb / 1024) end
    return string.format("%.0f KB/s", kb)
end

local function format_short(kb)
    if kb >= 1024 then return string.format("%.1fM", kb / 1024) end
    return string.format("%.0fK", kb)
end

function M.draw_text(ctx)
    local cr, s, theme = ctx.cr, ctx.s, ctx.theme
    local left_x = ctx.x + s(PAD_X)
    local right_x = left_x + s(INNER_W)

    local text_str = get_connection_detail(ctx)
    local kind, ssid = text_str:match("^(.-) : (.*)$")
    kind = kind or text_str

    flat.font(cr, "Orbitron", s(9), true)
    flat.spaced(cr, left_x, ctx.y + s(20), TITLES[kind] or kind:upper(), theme.text, s(1.5))
    if ssid and ssid ~= "" then
        flat.font(cr, "Exo 2", s(9))
        flat.text_right(cr, right_x, ctx.y + s(20), flat.fit(cr, ssid, s(50)), theme.faint)
    end

    -- Shared scale so the two bar lengths compare directly.
    local scale = math.max(peak(down_hist), peak(up_hist))
    local rows = {
        { "DN", down_hist[1] or 0, theme.green, 46 },
        { "UP", up_hist[1] or 0, theme.dim, 78 },
    }
    for _, row in ipairs(rows) do
        local label, kb, colour, y = table.unpack(row)
        flat.font(cr, "JetBrains Mono", s(9))
        flat.text(cr, left_x, ctx.y + s(y), label, theme.dim)
        flat.font(cr, "JetBrains Mono", s(11))
        flat.text_right(cr, right_x, ctx.y + s(y), format_rate(kb), theme.text)
        flat.ticks_at(cr, left_x, ctx.y + s(y + 7), s(INNER_W), s(5), kb / scale, colour)
    end

    local iface = resolve_iface(ctx)
    flat.font(cr, "JetBrains Mono", s(8))
    if iface then
        flat.text(cr, left_x, ctx.y + s(120), conky_parse("${addr " .. iface .. "}"), theme.dim)
    end
    flat.text_right(cr, right_x, ctx.y + s(120), "pk " .. format_short(scale), theme.dim)
end

-- =====================================================
-- Main
-- =====================================================
function M.draw(ctx)
    M.draw_rect(ctx)
    M.draw_text(ctx)
end

return M
