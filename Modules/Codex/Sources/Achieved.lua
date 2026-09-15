-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex: what have I already accomplished
--
-- Collections and standing. Classic answers titles and companions
-- today; the mount and pet journals, transmog and the rest are declared
-- in this client's API but hold nothing until Forever fills them in, so
-- each block asks what the client actually knows and says so plainly
-- rather than showing a confident zero.
---------------------------------------------------------------------------

local Codex = BazUI.Codex

local Theme = BazUI.Skin.Theme

local DONE = Theme.colors.success

---------------------------------------------------------------------------
-- Titles
---------------------------------------------------------------------------

local function KnownTitles()
    if not (GetNumTitles and IsTitleKnown and GetTitleName) then return {}, 0 end
    local names = {}
    local total = GetNumTitles() or 0
    for i = 1, total do
        local ok, isKnown = pcall(IsTitleKnown, i)
        if ok and isKnown then
            local name = GetTitleName(i)
            if name and name:trim() ~= "" then names[#names + 1] = name:trim() end
        end
    end
    table.sort(names)
    return names, total
end

Codex:RegisterSection({
    id     = "titles",
    tab    = "achieved",
    title  = "Titles",
    order  = 10,
    empty = "No titles earned yet.",
    events = { "KNOWN_TITLES_UPDATE", "PLAYER_ENTERING_WORLD" },

    GetHighlight = function()
        local names = KnownTitles()
        return { value = #names, label = #names == 1 and "title earned" or "titles earned" }
    end,

    -- The one number that sums the block up sits under the heading, so
    -- the list below it is detail rather than arithmetic.
    GetBar = function()
        local names, total = KnownTitles()
        if total == 0 then return nil end
        return {
            label = "Earned",
            value = #names, max = total,
            text  = string.format("%d of %d", #names, total),
            color = DONE,
        }
    end,

    GetRows = function()
        local rows = {}
        for _, name in ipairs((KnownTitles())) do
            rows[#rows + 1] = { label = name, state = "done" }
        end
        return rows
    end,
})

---------------------------------------------------------------------------
-- Companions
--
-- Vanilla keeps mounts and critters in the companion list rather than a
-- journal. GetNumCompanions is the call that answers on this client.
---------------------------------------------------------------------------

local function CompanionRows(kind)
    if not (GetNumCompanions and GetCompanionInfo) then return {} end
    local ok, count = pcall(GetNumCompanions, kind)
    if not ok or not count or count == 0 then return {} end
    local rows = {}
    for i = 1, count do
        local ok2, _, name, _, icon = pcall(GetCompanionInfo, kind, i)
        if ok2 and name then
            rows[#rows + 1] = { label = name, state = "done", icon = icon }
        end
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    return rows
end

local function CompanionCount(kind)
    if not GetNumCompanions then return 0 end
    local ok, count = pcall(GetNumCompanions, kind)
    return (ok and count) or 0
end

Codex:RegisterSection({
    id     = "mounts",
    tab    = "achieved",
    title  = "Mounts",
    order  = 20,
    empty = "No mounts yet.",
    events = { "COMPANION_LEARNED", "COMPANION_UPDATE", "PLAYER_ENTERING_WORLD" },
    GetHighlight = function()
        local n = CompanionCount("MOUNT")
        return { value = n, label = n == 1 and "mount" or "mounts" }
    end,
    GetRows = function() return CompanionRows("MOUNT") end,
})

Codex:RegisterSection({
    id     = "pets",
    tab    = "achieved",
    title  = "Pets",
    order  = 30,
    empty = "No pets yet.",
    events = { "COMPANION_LEARNED", "COMPANION_UPDATE", "PLAYER_ENTERING_WORLD" },
    GetHighlight = function()
        local n = CompanionCount("CRITTER")
        return { value = n, label = n == 1 and "pet" or "pets" }
    end,
    GetRows = function() return CompanionRows("CRITTER") end,
})

---------------------------------------------------------------------------
-- Reputation
--
-- Everyone you have standing with, each with a bar showing how far
-- through that standing you are. It used to list revered and above only,
-- on the grounds that those are the ones worth calling an achievement,
-- which meant the card read "nothing at revered yet" for the first fifty
-- levels of the game and told you nothing you could act on.
--
-- Sorted by standing and then by how far into it you are, so whoever you
-- are about to advance with sits at the top of their group and the
-- factions you have never spoken to fall to the bottom.
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
-- reads like every other reading in the suite: green is finished, gold is
-- in progress, red is a problem. Nothing is lost by it - the game paints
-- friendly through exalted the same green anyway - and exalted getting a
-- colour of its own is one more thing than the game tells you.
local function StandingColor(standing)
    if standing >= 8 then return Theme.colors.success end
    if standing >= 5 then return Theme.colors.gold end
    if standing == 4 then return Theme.colors.textMuted end
    return Theme.colors.danger
end

-- Everything the client is willing to list, which is everything visible
-- in the game's own reputation pane. A group collapsed there is collapsed
-- here too: expanding one fires UPDATE_FACTION, and this runs on
-- UPDATE_FACTION, so expanding them ourselves to read them would refresh
-- the codex, which would expand them again. The count comes back instead,
-- so the card can say where the missing ones went.
local function Factions()
    local out, collapsed = {}, 0
    local numFactions = (C_Reputation and C_Reputation.GetNumFactions
        and C_Reputation.GetNumFactions()) or (GetNumFactions and GetNumFactions()) or 0

    for i = 1, numFactions do
        local name, standing, isHeader, hasRep, barMin, barMax, barValue
        if C_Reputation and C_Reputation.GetFactionDataByIndex then
            local data = C_Reputation.GetFactionDataByIndex(i)
            if data then
                name, standing, isHeader = data.name, data.reaction, data.isHeader
                hasRep = data.isHeaderWithRep
                if data.isCollapsed then collapsed = collapsed + 1 end
                barMin, barMax, barValue = data.currentReactionThreshold,
                    data.nextReactionThreshold, data.currentStanding
            end
        else
            local n, _, s, low, high, value, _, _, header, isCollapsed, rep = GetFactionInfo(i)
            name, standing, isHeader, hasRep = n, s, header, rep
            if isCollapsed then collapsed = collapsed + 1 end
            barMin, barMax, barValue = low, high, value
        end

        -- A header is a grouping and not a reputation, unless the game
        -- says it carries one of its own.
        if name and standing and (not isHeader or hasRep) then
            local min, max = barMin or 0, barMax or 0
            local span = math.max(0, max - min)
            out[#out + 1] = {
                name = name, standing = standing,
                into = math.max(0, (barValue or 0) - min),
                span = span,
                -- Exalted has no next standing to be partway to, so it
                -- reads full rather than as whatever the client reports
                -- for a track that has ended.
                fraction = standing >= 8 and 1
                    or (span > 0 and math.max(0, (barValue or 0) - min) / span or 0),
            }
        end
    end

    table.sort(out, function(a, b)
        if a.standing ~= b.standing then return a.standing > b.standing end
        if a.fraction ~= b.fraction then return a.fraction > b.fraction end
        return a.name < b.name
    end)
    return out, collapsed
end

Codex:RegisterSection({
    id     = "reputation",
    tab    = "achieved",
    title  = "Reputation",
    order  = 40,
    empty  = "No standing with anyone yet.",
    events = { "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" },

    GetHighlight = function()
        local exalted = 0
        for _, f in ipairs(Factions()) do
            if f.standing >= 8 then exalted = exalted + 1 end
        end
        return { value = exalted, label = "exalted", color = exalted > 0 and DONE or nil }
    end,

    GetRows = function()
        local factions, collapsed = Factions()
        local rows = {}
        for _, f in ipairs(factions) do
            local done = f.standing >= 8
            rows[#rows + 1] = {
                label  = f.name,
                detail = done and StandingName(f.standing)
                    or ("%s   %s / %s"):format(StandingName(f.standing),
                        BazUI:FormatNumber(f.into), BazUI:FormatNumber(f.span)),
                state  = done and "done" or "open",
                progress = {
                    value = done and 1 or f.into,
                    max   = done and 1 or math.max(f.span, 1),
                    color = StandingColor(f.standing),
                },
            }
        end

        if collapsed > 0 then
            rows[#rows + 1] = {
                label = ("%d group%s collapsed in the game's reputation pane."):format(
                    collapsed, collapsed == 1 and "" or "s"),
                detail = "expand them there to see them here",
                muted = true,
            }
        end
        return rows
    end,
})
