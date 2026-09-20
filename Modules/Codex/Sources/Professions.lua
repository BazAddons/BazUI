-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: Professions and skills
--
-- Everything the character has learned to do, grouped the way Forever's
-- skills sheet groups it: class skills, professions, secondary skills,
-- weapons, armour, languages. One row per skill with its rank, and a
-- bar where a rank is climbing towards a cap - a skill is a fraction of
-- the way to its next tier, which is what a bar is for.
--
-- Retail has no skills sheet, so there the page is the professions
-- alone, read from the profession list every client has.
--
-- Cooldowns are not here yet. Which recipes have one is a thing that
-- has to be written down, since the client will not say until the
-- trade window is open; when that list exists it belongs on Today.
---------------------------------------------------------------------------

local Codex = BazUI.Codex

local TAB = "professions"
local COMMON = {
    tab      = TAB,
    tabLabel = "Professions",
    tabOrder = 29,
    tabIcon  = "Interface\\Icons\\Trade_Engineering",
}
local PREFIX = "skl."

---------------------------------------------------------------------------
-- Reading the skills sheet (Forever)
---------------------------------------------------------------------------

local function HasSkillSheet()
    return C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo
end

local function ScanSkills()
    local groups, collapsed = {}, 0
    local count = C_SkillInfo.GetNumSkillLines() or 0
    local current
    for i = 1, count do
        local s = C_SkillInfo.GetSkillLineInfo(i)
        if s and s.name then
            if s.isHeader then
                current = { header = s.name, skills = {} }
                groups[#groups + 1] = current
                if s.isCollapsed then collapsed = collapsed + 1 end
            elseif current then
                current.skills[#current.skills + 1] = {
                    name     = s.name,
                    rank     = s.rank or 0,
                    maxRank  = s.maxRank or 0,
                    modifier = s.modifier or 0,
                    skillID  = s.skillID,
                }
            end
        end
    end
    -- A header with nothing under it is a group the game has collapsed
    -- or one this character has nothing in; either way not a block.
    local out = {}
    for _, g in ipairs(groups) do
        if #g.skills > 0 then out[#out + 1] = g end
    end
    return out, collapsed
end

---------------------------------------------------------------------------
-- Reading the profession list (both clients)
---------------------------------------------------------------------------

local function ScanProfessions()
    if not (GetProfessions and GetProfessionInfo) then return {} end
    local skills = {}
    local indices = { GetProfessions() }
    for _, index in pairs(indices) do
        if type(index) == "number" then
            local name, icon, rank, maxRank = GetProfessionInfo(index)
            if name then
                skills[#skills + 1] = {
                    name = name, icon = icon, rank = rank or 0, maxRank = maxRank or 0, modifier = 0,
                }
            end
        end
    end
    table.sort(skills, function(a, b) return a.name < b.name end)
    return skills
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function Row(skill)
    local rank, maxRank = skill.rank, skill.maxRank
    local capped = maxRank > 1 and rank >= maxRank
    local known  = maxRank <= 1
    local detail
    if known then
        detail = "known"
    else
        detail = ("%d / %d"):format(rank, maxRank)
        if skill.modifier and skill.modifier > 0 then
            detail = ("%d (+%d) / %d"):format(rank, skill.modifier, maxRank)
        end
    end
    return {
        icon   = skill.icon,
        label  = skill.name,
        detail = detail,
        state  = capped and "done" or (known and nil or "open"),
        muted  = known,
        progress = (not known) and {
            bar   = true,
            value = capped and 1 or rank,
            max   = capped and 1 or math.max(maxRank, 1),
            color = capped and Codex.STATE_COLOR.done or nil,
        } or nil,
    }
end

local function Rows(skills)
    local rows = {}
    for _, s in ipairs(skills) do rows[#rows + 1] = Row(s) end
    return rows
end

local function Summary(skills)
    local capped, climbing = 0, 0
    for _, s in ipairs(skills) do
        if s.maxRank > 1 then
            if s.rank >= s.maxRank then capped = capped + 1 else climbing = climbing + 1 end
        end
    end
    if capped + climbing == 0 then return nil end
    local parts = {}
    if climbing > 0 then parts[#parts + 1] = ("%d climbing"):format(climbing) end
    if capped > 0 then parts[#parts + 1] = ("%d at cap"):format(capped) end
    return { text = table.concat(parts, "  |  ") }
end

---------------------------------------------------------------------------
-- Blocks
---------------------------------------------------------------------------

local groupsNow, collapsedNow = {}, 0

local function Highlight()
    local capped, total = 0, 0
    for _, g in ipairs(groupsNow) do
        for _, s in ipairs(g.skills) do
            if s.maxRank > 1 then
                total = total + 1
                if s.rank >= s.maxRank then capped = capped + 1 end
            end
        end
    end
    if total == 0 then return nil end
    return {
        value = capped,
        label = ("skills at cap of %d"):format(total),
        color = capped > 0 and Codex.STATE_COLOR.done or nil,
    }
end

local function Sync()
    if HasSkillSheet() then
        groupsNow, collapsedNow = ScanSkills()
    else
        groupsNow, collapsedNow = { { header = "Professions", skills = ScanProfessions() } }, 0
    end

    local blocks = {}
    for index, g in ipairs(groupsNow) do
        blocks[#blocks + 1] = {
            key   = g.header,
            title = g.header,
            empty = "Nothing learned here yet.",
            GetRows = function() return Rows(g.skills) end,
            GetBar  = function() return Summary(g.skills) end,
            GetHighlight = index == 1 and Highlight or nil,
        }
    end

    if #blocks == 0 then
        blocks[1] = {
            key = "_none", title = "Professions",
            empty = "No professions learned yet.",
            GetRows = function() return {} end,
        }
    end

    if collapsedNow > 0 then
        blocks[#blocks + 1] = {
            key   = "_collapsed",
            title = "Not shown",
            GetRows = function()
                return { {
                    label = ("%d group%s collapsed in the game's skills sheet."):format(
                        collapsedNow, collapsedNow == 1 and "" or "s"),
                    detail = "expand them there to see them here",
                    muted = true,
                } }
            end,
        }
    end

    Codex:SyncGroupSections(PREFIX, COMMON, blocks)
end

---------------------------------------------------------------------------
-- Staying current
---------------------------------------------------------------------------

BazUI:QueueForModule("Codex", function()
    Sync()
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("SKILL_LINES_CHANGED")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Some clients have this event and some do not; asking is harmless.
    pcall(watcher.RegisterEvent, watcher, "TRADE_SKILL_LIST_UPDATE")
    watcher:SetScript("OnEvent", function()
        Sync()
        if Codex.IsShown and Codex:IsShown() then
            Codex.Panel:RebuildTabs()
            Codex.Panel:QueueRefresh()
        end
    end)
end)
