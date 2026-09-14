-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex: what have I already accomplished
--
-- Collections and standing. Classic answers titles and companions
-- today; the mount and pet journals, transmog and the rest are declared
-- in this client's API but hold nothing until Forever fills them in, so
-- each section asks what the client actually knows and says so plainly
-- rather than showing a confident zero.
---------------------------------------------------------------------------

local Codex = BazUI.Codex

---------------------------------------------------------------------------
-- Titles
---------------------------------------------------------------------------

Codex:RegisterSection({
    id    = "titles",
    tab   = "achieved",
    title = "Titles",
    order = 10,
    empty = "No titles earned yet.",
    events = { "KNOWN_TITLES_UPDATE", "PLAYER_ENTERING_WORLD" },
    GetRows = function()
        if not (GetNumTitles and IsTitleKnown and GetTitleName) then return {} end
        local rows, known = {}, 0
        local total = GetNumTitles() or 0
        for i = 1, total do
            local ok, isKnown = pcall(IsTitleKnown, i)
            if ok and isKnown then
                local name = GetTitleName(i)
                if name and name:trim() ~= "" then
                    known = known + 1
                    rows[#rows + 1] = { label = name:trim(), state = "done" }
                end
            end
        end
        table.sort(rows, function(a, b) return a.label < b.label end)
        if #rows > 0 then
            table.insert(rows, 1, {
                label  = "Earned",
                detail = string.format("%d of %d", known, total),
                state  = "done",
            })
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
        local ok2, _, name = pcall(GetCompanionInfo, kind, i)
        if ok2 and name then
            rows[#rows + 1] = { label = name, state = "done" }
        end
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    table.insert(rows, 1, { label = "Collected", detail = tostring(count), state = "done" })
    return rows
end

Codex:RegisterSection({
    id    = "mounts",
    tab   = "achieved",
    title = "Mounts",
    order = 20,
    empty = "No mounts yet.",
    events = { "COMPANION_LEARNED", "COMPANION_UPDATE", "PLAYER_ENTERING_WORLD" },
    GetRows = function() return CompanionRows("MOUNT") end,
})

Codex:RegisterSection({
    id    = "pets",
    tab   = "achieved",
    title = "Pets",
    order = 30,
    empty = "No pets yet.",
    events = { "COMPANION_LEARNED", "COMPANION_UPDATE", "PLAYER_ENTERING_WORLD" },
    GetRows = function() return CompanionRows("CRITTER") end,
})

---------------------------------------------------------------------------
-- Reputation
--
-- Only the standings worth calling an accomplishment: revered and above.
---------------------------------------------------------------------------

local STANDING = {
    [5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted",
}

Codex:RegisterSection({
    id    = "reputation",
    tab   = "achieved",
    title = "Reputation",
    order = 40,
    empty = "Nothing at revered yet.",
    events = { "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" },
    GetRows = function()
        local rows = {}
        local numFactions = (C_Reputation and C_Reputation.GetNumFactions
            and C_Reputation.GetNumFactions()) or (GetNumFactions and GetNumFactions()) or 0
        for i = 1, numFactions do
            local name, standing, isHeader
            if C_Reputation and C_Reputation.GetFactionDataByIndex then
                local data = C_Reputation.GetFactionDataByIndex(i)
                if data then name, standing, isHeader = data.name, data.reaction, data.isHeader end
            else
                local n, _, s, _, _, _, _, _, header = GetFactionInfo(i)
                name, standing, isHeader = n, s, header
            end
            if name and not isHeader and standing and standing >= 7 then
                rows[#rows + 1] = {
                    label  = name,
                    detail = STANDING[standing] or tostring(standing),
                    state  = standing >= 8 and "done" or "open",
                }
            end
        end
        table.sort(rows, function(a, b) return a.label < b.label end)
        return rows
    end,
})
