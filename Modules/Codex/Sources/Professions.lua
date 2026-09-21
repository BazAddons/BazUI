-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: Professions and skills
--
-- Every profession as a card of its own, wearing the profession book's
-- own furniture: the faded workshop behind it, the framed icon, and
-- the rank bar in that profession's colors. Then everything else the
-- character has learned - class skills, weapons, armor, languages -
-- grouped the way Forever's skills sheet groups them, one row per
-- skill with a bar where a rank is climbing to its cap.
--
-- Retail has no skills sheet, so there the page is the profession
-- cards alone, read from the profession list every client has.
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

-- The skills sheet's groups that are professions rather than skills.
-- Matched by the game's own header words so a localised client agrees.
local function IsProfessionGroup(header)
    return header == (TRADE_SKILLS or "Professions")
        or header == (SECONDARY_SKILLS or "Secondary Skills")
end

-- The profession's art name: the key of its Enum.Profession value, which
-- is how the profession book names its atlases.
local KITS = (Enum and Enum.Profession and tInvert) and tInvert(Enum.Profession) or {}

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

local function HasSkillSheet()
    return C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo
end

-- What the trade skill side knows about a skill line: its art kit and
-- its icon. Nil where the line is not a profession.
local function TradeInfo(skillLineID)
    if not (skillLineID and C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID) then
        return nil
    end
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
    if ok and info and (info.profession or info.professionName) then return info end
    return nil
end

-- The profession list's icons, by skill line, since the skills sheet
-- has no pictures of its own.
local function ProfessionIcons()
    local icons = {}
    if not (GetProfessions and GetProfessionInfo) then return icons end
    for _, index in pairs({ GetProfessions() }) do
        if type(index) == "number" then
            local _, texture, _, _, _, _, skillLine = GetProfessionInfo(index)
            if skillLine then icons[skillLine] = texture end
        end
    end
    return icons
end

local function ScanSkills()
    local groups, collapsed = {}, 0
    local count = C_SkillInfo.GetNumSkillLines() or 0
    local current
    for i = 1, count do
        local s = C_SkillInfo.GetSkillLineInfo(i)
        if s and s.name then
            if s.isHeader then
                current = { header = s.name, skills = {}, seen = {} }
                groups[#groups + 1] = current
                if s.isCollapsed then collapsed = collapsed + 1 end
            elseif current and not current.seen[s.name] then
                -- The sheet lists some skills twice, once per rank line;
                -- one row per name is the reading that means something.
                current.seen[s.name] = true
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
    local out = {}
    for _, g in ipairs(groups) do
        if #g.skills > 0 then out[#out + 1] = g end
    end
    return out, collapsed
end

local function ScanProfessions()
    if not (GetProfessions and GetProfessionInfo) then return {} end
    local skills = {}
    for _, index in pairs({ GetProfessions() }) do
        if type(index) == "number" then
            local name, icon, rank, maxRank, _, _, skillLine, modifier = GetProfessionInfo(index)
            if name then
                skills[#skills + 1] = {
                    name = name, icon = icon, rank = rank or 0, maxRank = maxRank or 0,
                    modifier = modifier or 0, skillID = skillLine,
                }
            end
        end
    end
    table.sort(skills, function(a, b) return a.name < b.name end)
    return skills
end

---------------------------------------------------------------------------
-- Talent points
--
-- A class skill line - Arcane, Fire, Frost - is a talent tree, and the
-- skills sheet only ever says "known" about it. The Talents window puts
-- the points spent on each tree's header; this reads the same numbers,
-- from the same place: the active config's tree, its groups, and each
-- group's currency.
--
-- Asked once per draw and cached for a moment, because a page has three
-- of these on it and the answer cannot change between them.
---------------------------------------------------------------------------

local pointsByTree, pointsAt = nil, 0

local function ReadTalentPoints()
    local now = GetTime and GetTime() or 0
    if pointsByTree and (now - pointsAt) < 1 then return pointsByTree end
    pointsByTree, pointsAt = {}, now

    if not (C_Traits and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo
        and C_ClassTalents and C_ClassTalents.GetActiveConfigID) then
        return pointsByTree
    end

    local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if not (ok and configID) then return pointsByTree end

    local info
    ok, info = pcall(C_Traits.GetConfigInfo, configID)
    if not (ok and info and info.treeIDs) then return pointsByTree end

    for _, treeID in ipairs(info.treeIDs) do
        local okD, displays = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
        if okD and displays then
            local ids = {}
            for _, d in ipairs(displays) do ids[#ids + 1] = d.groupID end
            local okC, groups = pcall(C_Traits.GetGroupCurrencyInfo, configID, ids)
            local spentByGroup = {}
            if okC and groups then
                for _, g in ipairs(groups) do
                    local currency = g.currencyInfos and g.currencyInfos[1]
                    spentByGroup[g.traitNodeGroupID] = currency and currency.spent or 0
                end
            end
            for _, d in ipairs(displays) do
                if d.displayName then
                    pointsByTree[d.displayName] = spentByGroup[d.groupID] or 0
                end
            end
        end
    end
    return pointsByTree
end

-- How many talent points are in this line, or nil where it is not a
-- talent tree at all.
local function TalentPoints(name)
    local points = ReadTalentPoints()
    return points[name]
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function Row(skill)
    local rank, maxRank = skill.rank, skill.maxRank
    local capped = maxRank > 1 and rank >= maxRank
    local known  = maxRank <= 1
    local detail
    local points = known and TalentPoints(skill.name) or nil
    if points then
        detail = points == 1 and "1 point" or (points .. " points")
    elseif known then
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
        state  = capped and "done" or (points and points > 0 and "open")
            or (known and nil or "open"),
        muted  = known and not (points and points > 0) or nil,
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
    local capped, climbing, points, trees = 0, 0, 0, 0
    for _, s in ipairs(skills) do
        if s.maxRank > 1 then
            if s.rank >= s.maxRank then capped = capped + 1 else climbing = climbing + 1 end
        else
            local spent = TalentPoints(s.name)
            if spent then
                trees = trees + 1
                points = points + spent
            end
        end
    end
    -- A block of talent trees says the one number that matters: how many
    -- points are in it.
    if trees > 0 and capped + climbing == 0 then
        return { text = points == 1 and "1 point spent" or (points .. " points spent") }
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

local professionsNow, groupsNow, collapsedNow = {}, {}, 0

-- The points spent across every tree, for the strip.
local function TalentHighlight()
    local points, any = 0, false
    for _, g in ipairs(groupsNow) do
        for _, s in ipairs(g.skills) do
            local spent = TalentPoints(s.name)
            if spent then
                any = true
                points = points + spent
            end
        end
    end
    if not any then return nil end
    return { value = points, label = points == 1 and "talent point spent" or "talent points spent" }
end

local function Highlight()
    local capped, total = 0, 0
    for _, p in ipairs(professionsNow) do
        if p.maxRank > 1 then
            total = total + 1
            if p.rank >= p.maxRank then capped = capped + 1 end
        end
    end
    if total == 0 then return nil end
    return {
        value = capped,
        label = ("professions at cap of %d"):format(total),
        color = capped > 0 and Codex.STATE_COLOR.done or nil,
    }
end

-- One card per profession, in the profession book's clothes.
local function ProfessionBlock(p, index, icons)
    local trade = TradeInfo(p.skillID)
    local kit = trade and trade.profession and KITS[trade.profession] or nil
    local icon = p.icon or icons[p.skillID]
    if not icon and p.skillID and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture then
        local ok, tex = pcall(C_TradeSkillUI.GetTradeSkillTexture, p.skillID)
        if ok then icon = tex end
    end
    local text = ("%s %d/%d"):format(p.name, p.rank, p.maxRank)
    if p.modifier and p.modifier > 0 then
        text = ("%s %d/%d  (+%d)"):format(p.name, p.rank, p.maxRank, p.modifier)
    end
    return {
        key     = "prof." .. p.name,
        title   = p.name,
        order   = index,
        icon    = icon,
        art     = "Profession-overview-Card-" .. p.name,
        artFallback = "Profession-overview-Card",
        artAlpha = 0.9,
        rowless = true,
        GetRows = function() return {} end,
        GetBar  = function()
            return { kit = kit or "DefaultBlue", value = p.rank, max = p.maxRank, text = text }
        end,
        GetHighlight = index == 1 and Highlight or nil,
    }
end

local function Sync()
    local blocks = {}
    professionsNow, groupsNow, collapsedNow = {}, {}, 0

    if HasSkillSheet() then
        local groups, collapsed = ScanSkills()
        collapsedNow = collapsed
        for _, g in ipairs(groups) do
            if IsProfessionGroup(g.header) then
                for _, s in ipairs(g.skills) do professionsNow[#professionsNow + 1] = s end
            else
                groupsNow[#groupsNow + 1] = g
            end
        end
    else
        professionsNow = ScanProfessions()
    end

    local icons = ProfessionIcons()
    for index, p in ipairs(professionsNow) do
        blocks[#blocks + 1] = ProfessionBlock(p, index, icons)
    end

    local talentBlock = nil
    for index, g in ipairs(groupsNow) do
        local hasTrees = false
        for _, s in ipairs(g.skills) do
            if TalentPoints(s.name) then hasTrees = true break end
        end
        if hasTrees and not talentBlock then talentBlock = g.header end
        blocks[#blocks + 1] = {
            key   = g.header,
            title = g.header,
            order = 100 + index,
            empty = "Nothing learned here yet.",
            GetRows = function() return Rows(g.skills) end,
            GetBar  = function() return Summary(g.skills) end,
            GetHighlight = (hasTrees and talentBlock == g.header) and TalentHighlight or nil,
        }
    end

    if #blocks == 0 then
        blocks[1] = {
            key = "_none", title = "Professions",
            empty = "No professions learned yet. A trainer in any capital will teach you two.",
            GetRows = function() return {} end,
        }
    end

    if collapsedNow > 0 then
        blocks[#blocks + 1] = {
            key   = "_collapsed",
            title = "Not shown",
            order = 1000,
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
    for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
                             "CHARACTER_POINTS_CHANGED" }) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    -- Some clients have this event and some do not; asking is harmless.
    pcall(watcher.RegisterEvent, watcher, "TRADE_SKILL_LIST_UPDATE")
    watcher:SetScript("OnEvent", function()
        pointsByTree = nil
        Sync()
        if Codex.IsShown and Codex:IsShown() then
            Codex.Panel:RebuildTabs()
            Codex.Panel:QueueRefresh()
        end
    end)
end)
