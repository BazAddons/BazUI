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
    tab    = "progress",
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

-- The mount journal knows every mount there is, not only the ones you
-- have, so where it exists the block can say how far through the
-- collection you are. Clients without it fall back to the companion
-- list, which only knows what you own.
local function JournalMounts()
    if not (C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountInfoByID) then
        return nil
    end
    local ok, ids = pcall(C_MountJournal.GetMountIDs)
    if not ok or type(ids) ~= "table" then return nil end
    local owned, total = {}, 0
    for _, id in ipairs(ids) do
        local ok2, name, _, icon, _, _, _, _, _, _, hidden, collected = pcall(C_MountJournal.GetMountInfoByID, id)
        if ok2 and name and not hidden then
            total = total + 1
            if collected then owned[#owned + 1] = { label = name, icon = icon, state = "done" } end
        end
    end
    table.sort(owned, function(a, b) return a.label < b.label end)
    return owned, total
end

Codex:RegisterSection({
    id     = "mounts",
    tab    = "progress",
    title  = "Mounts",
    order  = 20,
    empty = "No mounts yet.",
    events = { "COMPANION_LEARNED", "COMPANION_UPDATE", "NEW_MOUNT_ADDED",
               "MOUNT_JOURNAL_USABILITY_CHANGED", "PLAYER_ENTERING_WORLD" },
    GetHighlight = function()
        local owned, total = JournalMounts()
        local n = owned and #owned or CompanionCount("MOUNT")
        return {
            value = n,
            label = total and ("mounts of %d"):format(total) or (n == 1 and "mount" or "mounts"),
        }
    end,
    GetBar = function()
        local owned, total = JournalMounts()
        if not owned or not total or total == 0 then return nil end
        return { text = ("%d of %d collected"):format(#owned, total), color = DONE }
    end,
    GetRows = function()
        local owned = JournalMounts()
        return owned or CompanionRows("MOUNT")
    end,
})

Codex:RegisterSection({
    id     = "pets",
    tab    = "progress",
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
