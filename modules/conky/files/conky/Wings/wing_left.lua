-- Left wing: a column of separate cards, numbered 01 down.
local HOME = os.getenv("HOME")
local CONKY = HOME .. "/.config/conky/"
local flat = dofile(CONKY .. "Common/flat.lua")

-- The widgets below see WING and hand over update/draw instead of running
-- themselves; each draws its own card inside the column.
WING = true

local wing = dofile(CONKY .. "Common/wing.lua")
local sys     = dofile(CONKY .. "Systems/systems.lua")
local devices = dofile(CONKY .. "Devices/devices.lua")
local audio   = dofile(CONKY .. "CmfBuds/cmf_buds.lua")
local player  = dofile(CONKY .. "NowPlaying/now_playing.lua")
local claude  = dofile(CONKY .. "ClaudeUsage/claude_usage.lua")

-- The activity graphs are optional: they take the height left over and are left out
-- when many devices are connected and the wing has no room for them.
local sections = {
    { h = 290, update = sys.update,     draw = sys.draw_gauges },
    { h = 188, update = devices.update, draw = devices.draw, size = devices.size },
    { h = 112, update = audio.update,   draw = audio.draw },
    { h = 110, update = player.update,  draw = player.draw, size = player.size },
    { h = 172, update = claude.update,  draw = claude.draw },
    { h = 130, flex = true, optional = true, draw = sys.draw_activity },
}

local function draw(cr, w, h)
    wing.layout(cr, w, h, sections, 1)
end

function conky_main()
    for _, s in ipairs(sections) do
        if s.update then s.update() end
    end
    flat.render("WingLeft", draw)
end
