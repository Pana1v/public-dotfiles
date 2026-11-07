local HOME = os.getenv("HOME")
local flat = dofile(HOME .. "/.config/conky/Common/flat.lua")
local theme, PAD = flat.theme, flat.PAD

local prs = flat.snapshot("github_prs")

local HEADER_H = 46
local SECTION_H = 22
local ROW_H = 40
local FOOTER_H = 22

-- Right-hand tags, color only for state that needs action:
--   ci failed = red, changes requested / ci running = yellow, approved = green
local function tags(pr)
    local out = {}
    if pr.ci == "FAILURE" or pr.ci == "ERROR" then
        out[#out + 1] = { "ci failed", theme.red }
    elseif pr.ci == "PENDING" then
        out[#out + 1] = { "ci running", theme.yellow }
    end
    if pr.review == "CHANGES_REQUESTED" then
        out[#out + 1] = { "changes", theme.yellow }
    elseif pr.review == "APPROVED" then
        out[#out + 1] = { "approved", theme.green }
    end
    if pr.draft == "1" then
        out[#out + 1] = { "draft", theme.faint }
    end
    return out
end

local function split(rows)
    local mine, review = {}, {}
    for _, r in ipairs(rows) do
        local pr = { id = r[2], draft = r[3], review = r[4], ci = r[5], age = r[6], title = r[7] or "" }
        if r[1] == "R" then review[#review + 1] = pr end
        if r[1] == "M" then mine[#mine + 1] = pr end
    end
    return mine, review
end

local function draw_row(cr, w, y, pr)
    local iw = flat.icon(cr, PAD, y + 15, "pr", 13, theme.dim) + 4
    flat.font(cr, "Exo 2", 13)
    flat.text(cr, PAD + iw, y + 15, pr.id, theme.text)
    local x = PAD + iw + flat.width(cr, pr.id) + 10

    flat.font(cr, "Exo 2", 11)
    flat.text(cr, x, y + 15, pr.age, theme.faint)

    local right = w - PAD
    local row_tags = tags(pr)
    for i = #row_tags, 1, -1 do
        local t = row_tags[i]
        flat.text_right(cr, right, y + 15, t[1], t[2])
        right = right - flat.width(cr, t[1]) - 10
    end

    flat.font(cr, "Exo 2", 12)
    flat.text(cr, PAD, y + 32, flat.fit(cr, pr.title, w - 2 * PAD), theme.dim)
end

local function draw(cr, w, h)
    flat.card(cr, w, h)

    if not prs.rows then
        flat.header(cr, w, "github", "", nil, "github")
        flat.font(cr, "Exo 2", 13)
        flat.text(cr, PAD, HEADER_H + 20, "loading...", theme.dim)
        return
    end

    local mine, review = split(prs.rows)
    local status = string.format("%d mine  .  %d to review", #mine, #review)
    if prs.last_success then
        status = status .. "  .  " .. flat.format_age(os.time() - prs.last_success)
    end
    flat.header(cr, w, "github", status, nil, "github")

    local sections = {}
    if #review > 0 then sections[#sections + 1] = { "review requested", review } end
    if #mine > 0 then sections[#sections + 1] = { "my open prs", mine } end
    if #sections == 0 then
        flat.font(cr, "Exo 2", 13)
        flat.text(cr, PAD, HEADER_H + 20, "no open prs", theme.dim)
        return
    end

    local y = HEADER_H
    local hidden = 0
    for _, s in ipairs(sections) do
        local label, list = s[1], s[2]
        flat.font(cr, "Exo 2", 10)
        flat.text(cr, PAD, y + 12, label, theme.faint)
        y = y + SECTION_H

        for _, pr in ipairs(list) do
            if y + ROW_H > h - FOOTER_H then
                hidden = hidden + 1
            else
                draw_row(cr, w, y, pr)
                y = y + ROW_H
            end
        end
        y = y + 4
    end

    if hidden > 0 then
        flat.font(cr, "Exo 2", 11)
        flat.text(cr, PAD, h - 10, string.format("+%d more on GitHub", hidden), theme.faint)
    end
end

-- Loaded by a wing window: hand over update/draw instead of becoming conky_main.
if WING then
    return { update = function() prs.update() end, draw = draw }
end

function conky_main()
    prs.update()
    flat.render("GithubPRs", draw)
end
