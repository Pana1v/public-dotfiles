require 'cairo'
-- conky 1.20+ ships the X11 surface functions in their own module.
pcall(require, 'cairo_xlib')
local flat = dofile(os.getenv("HOME") .. "/.config/conky/Common/flat.lua")

-- =====================================================
--  Claude Code Usage — session (5h) and weekly (7d) rate
--  limit percentages, straight from Claude Code's own
--  statusline.sh cache (~/.claude/rate-cache.json), which
--  it refreshes on every status-line render. No subprocess
--  needed: this is a plain local file read (unlike a
--  spawned process, that's always safe from Lua).
-- =====================================================

local theme = {
    bg     = "#0a0506",
    bar_bg = "#2a1013",
    text   = "#ffe9eb",
    red    = "#ff3b1f",
    green  = "#52e5ff",
    orange = "#ffc14d",   -- warn state, clear yellow despite the name
    blue   = "#ffe9eb",   -- neutral, same as text
    dim    = "#b86a72",
    faint  = "#8a3a44",
}

local function rgb(colour, alpha)
    if type(colour) == "string" then
        colour = tonumber((colour:gsub("#", "0x")))
    end
    return ((colour / 0x10000) % 0x100) / 255.,
           ((colour / 0x100) % 0x100) / 255.,
           (colour % 0x100) / 255.,
           alpha
end

local function set_color(cr, colour, alpha)
    local r, g, b, a = rgb(colour, alpha)
    cairo_set_source_rgba(cr, r, g, b, a)
end

local function right_text(cr, text, right_x, y)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, text, ext)
    cairo_move_to(cr, right_x - ext.width, y)
    cairo_show_text(cr, text)
end

-- =====================================================
-- Fetch (throttled): plain file read, no subprocess at all
-- =====================================================
local RATE_CACHE = os.getenv("HOME") .. "/.claude/rate-cache.json"
local REFRESH_SECONDS = 2
local STALE_SECONDS = 600
local WEEK_SECONDS = 7 * 24 * 3600
local SESSION_SECONDS = 5 * 3600

-- Weekly limit resets Thursday 16:30 local time; only a fallback for
-- when the cache has no r7_resets_at.
local RESET_WDAY = 5          -- os.date wday: Sunday=1 .. Thursday=5
local RESET_HOUR, RESET_MIN = 16, 30

local have_fetched_once = false
local last_fetch = 0
local cache = { r5 = 0, r7 = 0, r5_reset = nil, r7_reset = nil, ts = nil }

local function read_rate_cache()
    local f = io.open(RATE_CACHE, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()

    local function field(name)
        return tonumber(content:match('"' .. name .. '"%s*:%s*"?(%d+)"?'))
    end

    local r5, r7 = field("r5"), field("r7")
    if not r5 or not r7 then return nil end
    return { r5 = r5, r7 = r7, r5_reset = field("r5_resets_at"),
             r7_reset = field("r7_resets_at"), ts = field("ts") }
end

local function update()
    local now = os.time()
    if now - last_fetch < REFRESH_SECONDS then return end
    last_fetch = now

    local fresh = read_rate_cache()
    if fresh then
        cache = fresh
        have_fetched_once = true
    end
end

-- A window whose reset time has passed is empty again, whatever the
-- last cached percentage says.
local function live_pct(pct, resets_at)
    if resets_at and resets_at <= os.time() then return 0 end
    return pct
end

local function next_weekly_reset()
    if cache.r7_reset and cache.r7_reset > os.time() then return cache.r7_reset end

    local now = os.time()
    local t = os.date("*t", now)
    t.hour, t.min, t.sec = RESET_HOUR, RESET_MIN, 0
    t.day = t.day + (RESET_WDAY - t.wday) % 7
    local reset = os.time(t)
    if reset <= now then reset = reset + WEEK_SECONDS end
    return reset
end

local function week_elapsed()
    local remaining = next_weekly_reset() - os.time()
    local pct = (1 - remaining / WEEK_SECONDS) * 100
    return math.max(0, math.min(100, pct)), remaining
end

-- Nil when no 5h window is open (never started, or already reset).
local function session_elapsed()
    if not cache.r5_reset then return nil end

    local remaining = cache.r5_reset - os.time()
    if remaining <= 0 then return nil end
    return math.max(0, math.min(100, (1 - remaining / SESSION_SECONDS) * 100)), remaining
end

local function format_remaining(seconds)
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    if d > 0 then return string.format("%dd %dh left", d, h) end
    return string.format("%dh %dm left", h, math.floor((seconds % 3600) / 60))
end

local function format_age(seconds)
    if seconds < 90 then return string.format("%ds ago", seconds) end
    if seconds < 5400 then return string.format("%dm ago", math.floor(seconds / 60)) end
    return string.format("%dh ago", math.floor(seconds / 3600))
end

-- =====================================================
-- Layout
-- =====================================================
local PAD = 16

local function pct_color(pct)
    if pct >= 80 then return theme.red end
    if pct >= 50 then return theme.orange end
    return theme.green
end

local function draw_limit_row(cr, w, y, label, pct, colour, value_text)
    colour = colour or pct_color(pct)
    value_text = value_text or string.format("%d%%", pct)

    set_color(cr, colour == theme.green and theme.text or colour, 1)
    flat.font(cr, "JetBrains Mono", 14)
    right_text(cr, value_text, w - PAD, y)
    local value_w = flat.width(cr, value_text)

    set_color(cr, theme.dim, 1)
    flat.font(cr, "Exo 2", 14)
    cairo_move_to(cr, PAD, y)
    cairo_show_text(cr, flat.fit(cr, label, w - 2 * PAD - value_w - 12))

    flat.ticks(cr, PAD, y + 8, w - PAD * 2, 5, pct / 100, colour)
end

local function draw(cr, w, h)
    flat.card(cr, w, h)

    if not have_fetched_once then
        return flat.header(cr, w, "claude", "no data - run Claude Code once", nil, "robot")
    end

    local age = cache.ts and math.max(0, os.time() - cache.ts) or nil
    local stale = age and age > STALE_SECONDS
    flat.header(cr, w, "claude", age and ((stale and "stale " or "updated ") .. format_age(age)),
        stale and theme.orange or theme.faint, "robot")

    -- four rows, 44 px apart in a full card; closer together when the card is short
    local pitch = math.min(44, (h - 58 - 14) / 3)
    draw_limit_row(cr, w, 58, "Session (5h)", live_pct(cache.r5, cache.r5_reset))

    local s_elapsed, s_remaining = session_elapsed()
    draw_limit_row(cr, w, 58 + pitch, "Session elapsed", s_elapsed or 0, theme.green,
        s_elapsed and string.format("%d%%  |  %s", math.floor(s_elapsed), format_remaining(s_remaining))
                   or "no active window")

    draw_limit_row(cr, w, 58 + 2 * pitch, "Weekly (7d)", live_pct(cache.r7, cache.r7_reset))

    local elapsed, remaining = week_elapsed()
    draw_limit_row(cr, w, 58 + 3 * pitch, "Week elapsed (resets Thu 16:30)", elapsed, theme.green,
        string.format("%d%%  |  %s", math.floor(elapsed), format_remaining(remaining)))
end

-- Loaded by a wing window: hand over update/draw instead of becoming conky_main.
if WING then
    return { update = update, draw = draw }
end

function conky_main()
    update()
    flat.render("ClaudeUsage", draw)
end
