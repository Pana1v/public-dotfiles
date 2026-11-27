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
local docker   = dofile(CONKY .. "Docker/docker_card.lua")
-- Google Tasks are personal: the professional profile does not even load them.
local professional = flat.profile() == "professional"
local tasks = not professional and dofile(CONKY .. "Tasks/tasks.lua") or nil

local AGENDA_H = 150
local AGENDA_IDLE_H = 100   -- header plus the two-line "no calendar" notice

local agenda_card = { h = AGENDA_H, flex = true, update = agenda.update, draw = agenda.draw }
local github_card = { h = 176, update = github.update, draw = github.draw }
local sections = {
    { h = 222, update = weather.update,  draw = weather.draw },
    { h = 222, update = calendar.update, draw = calendar.draw },
    agenda_card,
    github_card,
    { update = docker.update, draw = docker.draw, size = docker.size },
}
if tasks then
    sections[#sections + 1] = { h = 130, update = tasks.update, draw = tasks.draw }
end

local function draw(cr, w, h)
    -- No calendar: agenda shrinks, GitHub soaks up the spare height instead.
    local idle = agenda.idle()
    agenda_card.h = idle and AGENDA_IDLE_H or AGENDA_H
    agenda_card.flex, github_card.flex = not idle, idle
    wing.layout(cr, w, h, sections, 9)
end

function conky_main()
    for _, s in ipairs(sections) do
        if s.update then s.update() end
    end
    flat.render("WingRight", draw)
end
