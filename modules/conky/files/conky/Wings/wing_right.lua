-- Right wing: a column of separate cards, numbered on from the left wing.
local HOME = os.getenv("HOME")
local CONKY = HOME .. "/.config/conky/"
local flat = dofile(CONKY .. "Common/flat.lua")

-- The widgets below see WING and hand over update/draw instead of running
-- themselves; each draws its own card inside the column.
WING = true

local wing = dofile(CONKY .. "Common/wing.lua")
local weather  = dofile(CONKY .. "Weather/weather.lua")
local calendar = dofile(CONKY .. "Calendar/calendar.lua")
local agenda   = dofile(CONKY .. "Agenda/agenda.lua")
local github   = dofile(CONKY .. "GithubPRs/github_prs.lua")
-- Google Tasks are personal: the professional profile does not even load them.
local professional = flat.profile() == "professional"
local tasks = not professional and dofile(CONKY .. "Tasks/tasks.lua") or nil

local sections = {
    { h = 222, update = weather.update,  draw = weather.draw },
    { h = 222, update = calendar.update, draw = calendar.draw },
    { h = 150, flex = true, update = agenda.update, draw = agenda.draw },
    { h = 176, update = github.update,   draw = github.draw },
}
if tasks then
    sections[#sections + 1] = { h = 130, update = tasks.update, draw = tasks.draw }
end

local function draw(cr, w, h)
    wing.layout(cr, w, h, sections, 7)
end

function conky_main()
    for _, s in ipairs(sections) do
        if s.update then s.update() end
    end
    flat.render("WingRight", draw)
end
