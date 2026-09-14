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
    accent = Theme.colors.success,
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
    accent = { 0.45, 0.68, 0.85, 1 },
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
    accent = { 0.72, 0.55, 0.85, 1 },
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
-- Only the standings worth calling an accomplishment: revered and above.
-- Each row carries how far through its standing you are, so the ones
-- within reach of exalted stand out from the ones that just arrived.
---------------------------------------------------------------------------

local STANDING = {
    [5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted",
}

local function Factions()
    local out = {}
    local numFactions = (C_Reputation and C_Reputation.GetNumFactions
        and C_Reputation.GetNumFactions()) or (GetNumFactions and GetNumFactions()) or 0

    for i = 1, numFactions do
        local name, standing, isHeader, barMin, barMax, barValue
        if C_Reputation and C_Reputation.GetFactionDataByIndex then
            local data = C_Reputation.GetFactionDataByIndex(i)
            if data then
                name, standing, isHeader = data.name, data.reaction, data.isHeader
                barMin, barMax, barValue = data.currentReactionThreshold,
                    data.nextReactionThreshold, data.currentStanding
            end
        else
            local n, _, s, low, high, value, _, _, header = GetFactionInfo(i)
            name, standing, isHeader = n, s, header
            barMin, barMax, barValue = low, high, value
        end

        if name and not isHeader and standing and standing >= 7 then
            out[#out + 1] = {
                name = name, standing = standing,
                min = barMin or 0, max = barMax or 0, value = barValue or 0,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.standing ~= b.standing then return a.standing > b.standing end
        return a.name < b.name
    end)
    return out
end

Codex:RegisterSection({
    id     = "reputation",
    tab    = "achieved",
    title  = "Reputation",
    order  = 40,
    accent = Theme.colors.caution,
    empty = "Nothing at revered yet.",
    events = { "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" },

    GetHighlight = function()
        local exalted = 0
        for _, f in ipairs(Factions()) do
            if f.standing >= 8 then exalted = exalted + 1 end
        end
        return { value = exalted, label = "exalted", color = exalted > 0 and DONE or nil }
    end,

    GetRows = function()
        local rows = {}
        for _, f in ipairs(Factions()) do
            local done = f.standing >= 8
            local span = math.max(0, (f.max or 0) - (f.min or 0))
            rows[#rows + 1] = {
                label  = f.name,
                detail = STANDING[f.standing] or tostring(f.standing),
                state  = done and "done" or "open",
                -- Exalted is the end of the track, so it reads full
                -- rather than as whatever fraction the client reports.
                progress = (done or span > 0)
                    and { value = done and 1 or (f.value - f.min),
                          max   = done and 1 or span,
                          color = done and Theme.colors.success or Theme.colors.caution }
                    or nil,
            }
        end
        return rows
    end,
})
