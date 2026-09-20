-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: Reputation
--
-- Everyone you have standing with, grouped the way the game's own pane
-- groups them - Alliance, Steamwheedle Cartel, Other - one block per
-- group, one row per faction, and a bar on every row. This is the one
-- page where a bar earns its place: a standing is a fraction of the way
-- to the next standing, and that is what a bar is for.
--
-- The groups are the game's, so the blocks are made from what the
-- client lists rather than written down here. A group collapsed in the
-- game's pane is collapsed here too - expanding one fires UPDATE_FACTION,
-- which is what redraws this, so expanding them ourselves to read them
-- would redraw the codex, which would expand them again.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local Theme = BazUI.Skin.Theme

local TAB      = "reputation"
local TAB_ICON = "Interface\\Icons\\Achievement_Reputation_01"
local PREFIX   = "rep."
local EXALTED  = 8
local COMMON   = { tab = TAB, tabLabel = "Reputation", tabOrder = 27, tabIcon = TAB_ICON }

---------------------------------------------------------------------------
-- Words and colours
---------------------------------------------------------------------------

-- The client's own word for a standing: localised, and gendered in the
-- languages that need it. The game's own reputation pane asks the same
-- way.
local function StandingName(standing)
    local token = "FACTION_STANDING_LABEL" .. standing
    local label = GetText and GetText(token, UnitSex("player")) or _G[token]
    return label or tostring(standing)
end

-- Our palette rather than the game's FACTION_BAR_COLORS, so a reputation
-- reads like every other reading in the suite: green is finished, gold
-- is in progress, red is a problem.
local function StandingColor(standing)
    if standing >= EXALTED then return Theme.colors.success end
    if standing >= 5 then return Theme.colors.gold end
    if standing == 4 then return Theme.colors.textMuted end
    return Theme.colors.danger
end

---------------------------------------------------------------------------
-- Reading the list
---------------------------------------------------------------------------

local function ReadFaction(i)
    if C_Reputation and C_Reputation.GetFactionDataByIndex then
        local d = C_Reputation.GetFactionDataByIndex(i)
        if not d then return nil end
        return {
            name = d.name, standing = d.reaction, isHeader = d.isHeader,
            hasRep = d.isHeaderWithRep, collapsed = d.isCollapsed,
            min = d.currentReactionThreshold, max = d.nextReactionThreshold,
            value = d.currentStanding, factionID = d.factionID,
        }
    end
    if GetFactionInfo then
        local name, _, standing, low, high, value, _, _, isHeader, isCollapsed, hasRep,
              _, _, factionID = GetFactionInfo(i)
        if not name then return nil end
        return {
            name = name, standing = standing, isHeader = isHeader, hasRep = hasRep,
            collapsed = isCollapsed, min = low, max = high, value = value,
            factionID = factionID,
        }
    end
    return nil
end

-- Groups in the game's order, each with its factions in the game's
-- order. The count of collapsed groups comes back so a block can say
-- where its missing rows went.
local function Scan()
    local groups, byName, collapsed = {}, {}, 0
    local count = (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetNumFactions())
        or (GetNumFactions and GetNumFactions()) or 0

    local current
    local function Group(name)
        local g = byName[name]
        if not g then
            g = { header = name, factions = {} }
            byName[name] = g
            groups[#groups + 1] = g
        end
        return g
    end

    for i = 1, count do
        local f = ReadFaction(i)
        if f and f.name then
            if f.isHeader then
                current = Group(f.name)
                if f.collapsed then collapsed = collapsed + 1 end
            end
            if f.standing and (not f.isHeader or f.hasRep) then
                local g = current or Group("Other")
                local min, max = f.min or 0, f.max or 0
                local span = math.max(0, max - min)
                g.factions[#g.factions + 1] = {
                    name = f.name, standing = f.standing, factionID = f.factionID,
                    into = math.max(0, (f.value or 0) - min), span = span,
                    fraction = f.standing >= EXALTED and 1
                        or (span > 0 and math.max(0, (f.value or 0) - min) / span or 0),
                }
            end
        end
    end
    return groups, collapsed
end

---------------------------------------------------------------------------
-- Blocks
--
-- One section per group, registered from what was just read. Ids are
-- the group's name so a block you folded stays folded across sessions
-- and reloads.
---------------------------------------------------------------------------

local groupsNow, collapsedNow = {}, 0

local function Rows(group)
    local rows = {}
    for _, f in ipairs(group.factions) do
        local done = f.standing >= EXALTED
        rows[#rows + 1] = {
            label  = f.name,
            detail = done and StandingName(f.standing)
                or ("%s   %s / %s"):format(StandingName(f.standing),
                    BazUI:FormatNumber(f.into), BazUI:FormatNumber(f.span)),
            state  = done and "done" or "open",
            progress = {
                bar   = true,
                value = done and 1 or f.into,
                max   = done and 1 or math.max(f.span, 1),
                color = StandingColor(f.standing),
            },
        }
    end
    return rows
end

local function Summary(group)
    local exalted, top = 0, nil
    for _, f in ipairs(group.factions) do
        if f.standing >= EXALTED then exalted = exalted + 1 end
        if not top or f.standing > top.standing
            or (f.standing == top.standing and f.fraction > top.fraction) then
            top = f
        end
    end
    local n = #group.factions
    local text = ("%d faction%s"):format(n, n == 1 and "" or "s")
    if exalted > 0 then
        text = text .. ("  |  %d exalted"):format(exalted)
    elseif top then
        text = text .. ("  |  furthest with %s"):format(top.name)
    end
    return { text = text }
end

-- The rail counts the whole page once.
local function Highlight()
    local exalted, total = 0, 0
    for _, g in ipairs(groupsNow) do
        for _, f in ipairs(g.factions) do
            total = total + 1
            if f.standing >= EXALTED then exalted = exalted + 1 end
        end
    end
    return {
        value = exalted,
        label = ("exalted of %d"):format(total),
        color = exalted > 0 and Codex.STATE_COLOR.done or nil,
    }
end

local function Sync()
    groupsNow, collapsedNow = Scan()

    local blocks = {}
    for index, g in ipairs(groupsNow) do
        blocks[#blocks + 1] = {
            key   = g.header,
            title = g.header,
            empty = "Nothing here yet.",
            GetRows = function() return Rows(g) end,
            GetBar  = function() return Summary(g) end,
            GetHighlight = index == 1 and Highlight or nil,
        }
    end

    if #blocks == 0 then
        blocks[1] = {
            key = "_none", title = "Reputation",
            empty = "No standing with anyone yet.",
            GetRows = function() return {} end,
        }
    end

    if collapsedNow > 0 then
        blocks[#blocks + 1] = {
            key   = "_collapsed",
            title = "Not shown",
            GetRows = function()
                return { {
                    label = ("%d group%s collapsed in the game's reputation pane."):format(
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
    watcher:RegisterEvent("UPDATE_FACTION")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", function()
        Sync()
        if Codex.IsShown and Codex:IsShown() then
            Codex.Panel:RebuildTabs()
            Codex.Panel:QueueRefresh()
        end
    end)
end)
