-- =====================================================
--  Storage Usage Card (Elysium Official Standard)
-- =====================================================

local M = {}
local flat = dofile(os.getenv("HOME") .. "/.config/conky/Common/flat.lua")

-- =====================================================
-- Config
-- =====================================================
local CARD_W = 134
local CARD_H = 134

-- =====================================================
-- Convert hex color to RGBA
-- =====================================================
local function rgb_to_r_g_b(colour, alpha)
    if type(colour) == "string" then
        colour = tonumber((colour:gsub("#","0x")))
    end
    return ((colour / 0x10000) % 0x100) / 255.,
           ((colour / 0x100) % 0x100) / 255.,
           (colour % 0x100) / 255.,
           alpha
end

-- =====================================================
-- Get bar color
-- =====================================================
local function read_bar_colors()
    local home = os.getenv("HOME") or ""
    local path = home ..
        "/.config/conky/Elysium/modules/DISK_1x1_D01/bar-color.conf"

    local colors = {}

    local f = io.open(path)
    if not f then return colors end

    for line in f:lines() do
        local k,v = line:match("^(%w+)%s*=%s*(%w+)")
        if k and v then
            colors[k:lower()] = v:lower()
        end
    end

    f:close()
    return colors
end

local bar = read_bar_colors()

-- =====================================================
-- State
-- =====================================================
local function format_size(kb)
    if not kb or kb <= 0 then return "0 KB" end

    local mb = kb / 1024
    local gb = mb / 1024

    if gb >= 1 then
        return string.format("%.1f GB", gb)
    elseif mb >= 1 then
        return string.format("%.0f MB", mb)
    else
        return string.format("%d KB", kb)
    end
end

-- =====================================================
-- Base Layer
-- =====================================================
function M.draw_rect(ctx)
    flat.card_at(ctx.cr, ctx.x, ctx.y, CARD_W, CARD_H)
end

-- =====================================================
-- Bar + text helpers
-- =====================================================
local PAD_X = 12
local BAR_H = 4


local function right_text(cr, text, rx, y)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, text, ext)
    cairo_move_to(cr, math.floor(rx - ext.width - ext.x_bearing), math.floor(y))
    cairo_show_text(cr, text)
end

local function set_color(cr, hex)
    local r,g,b,a = rgb_to_r_g_b(hex, 1)
    cairo_set_source_rgba(cr, r,g,b,a)
end

-- =====================================================
-- Visual + Numbers Layer (thin bars)
-- =====================================================
-- draw_visual owns both the bar geometry and the numbers tied to it,
-- so the two never drift out of sync with each other.
function M.draw_visual(ctx)

    local cr    = ctx.cr
    local s     = ctx.s
    local theme = ctx.theme
    local ox    = ctx.x
    local oy    = ctx.y

    local disk = ctx.runtime.disk or {}
    local root = disk.root or {}
    local home = disk.home or {}

    local left_x  = ox + s(PAD_X)
    local right_x = ox + s(CARD_W) - s(PAD_X)
    local bar_w   = right_x - left_x

    if disk.same_fs then
        -- / and /home are the same partition: one big number, one bar
        local pct = math.max(0, math.min((root.percent or 0) / 100, 1))

        cairo_select_font_face(cr, "Exo 2",
            CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, s(34))
        set_color(cr, theme.text)
        cairo_move_to(cr, left_x, oy + s(80))
        cairo_show_text(cr, string.format("%d%%", root.percent or 0))

        cairo_select_font_face(cr, "Exo 2",
            CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, s(9))
        set_color(cr, theme.dim)
        cairo_move_to(cr, left_x, oy + s(100))
        cairo_show_text(cr, "used")
        right_text(cr, format_size(root.used or 0), right_x, oy + s(100))

        flat.ticks_at(cr, left_x, oy + s(110), bar_w, s(BAR_H), pct,
            theme.level(root.percent or 0, 75, 90))
        return
    end

    -- Real separate /home partition: two labeled rows
    local rows = {
        { d = root, y = 62,  label = "root" },
        { d = home, y = 104, label = "home" },
    }

    for _, row in ipairs(rows) do
        local pct = math.max(0, math.min((row.d.percent or 0) / 100, 1))
        local y   = oy + s(row.y)

        cairo_select_font_face(cr, "Exo 2",
            CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, s(9))
        set_color(cr, theme.dim)
        cairo_move_to(cr, left_x, math.floor(y))
        cairo_show_text(cr, row.label .. "  " .. format_size(row.d.used or 0))

        cairo_select_font_face(cr, "Exo 2",
            CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, s(16))
        set_color(cr, theme.text)
        right_text(cr, string.format("%d%%", row.d.percent or 0), right_x, y)

        flat.ticks_at(cr, left_x, y + s(6), bar_w, s(BAR_H), pct,
            theme.level(row.d.percent or 0, 75, 90))
    end
end

-- =====================================================
-- Text Layer (header)
-- =====================================================
function M.draw_text(ctx)

    local cr    = ctx.cr
    local s     = ctx.s
    local theme = ctx.theme
    local ox    = ctx.x
    local oy    = ctx.y

    local disk  = (ctx.runtime and ctx.runtime.disk) or {}
    local extra = disk.extra or {}

    flat.font(cr, "Orbitron", s(9), true)
    flat.spaced(cr, ox + s(PAD_X), oy + s(20), "STORAGE", theme.text, s(1.5))

    if #extra == 0 then return end

    set_color(cr, theme.faint)
    right_text(cr, "+" .. #extra, ox + s(CARD_W) - s(PAD_X), oy + s(20))
end

-- =====================================================
-- Main (Compact Standard)
-- =====================================================
function M.draw(ctx)
    M.draw_rect(ctx)
    M.draw_visual(ctx)
    M.draw_text(ctx)
end

return M
