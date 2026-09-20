-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: Instances
--
-- The whole map of where you can go: every dungeon, raid and world boss
-- the game knows about (Data/Instances.lua, written from the game's own
-- tables), with what stands between you and each: its level, a gate
-- you have not passed (Data/Access.lua), or a lockout you already hold.
-- Today shows the slice of this that matters now; this is the map it
-- is cut from.
--
-- A row reads one of five ways, worst first: saved (bosses down, time
-- to reset), too low for it, not yet attuned, outgrown, or open - with
-- "for your level" on the ones tuned for where you are. Any lockout
-- the catalogue does not know is listed on its own, so a lockout is
-- never missing from the page just because the data has not caught up.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local Theme = BazUI.Skin.Theme

local TAB = "instances"
local COMMON = {
    tab      = TAB,
    tabLabel = "Instances",
    tabOrder = 26,
    tabIcon  = "Interface\\Icons\\INV_Misc_Key_03",
    empty    = "Nothing written down here yet.",
}
local PREFIX = "inst."

local KIND_TITLE = { dungeon = "Dungeons", raid = "Raids", world = "World bosses" }
local KIND_ORDER = { dungeon = 1, raid = 2, world = 3 }

-- How far either side of a place's level it still counts as yours.
local BAND_BELOW, BAND_ABOVE = 2, 5

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

local function Duration(seconds)
    return BazUI:FormatSpan(seconds)
end

local function Catalogue()
    return (Codex.Instances and Codex.Instances.entries) or {}
end

-- Every live lockout, with what is known about it.
local function Lockouts()
    local out = {}
    local count = GetNumSavedInstances and GetNumSavedInstances() or 0
    for i = 1, count do
        local name, _, reset, _, locked, extended, _, isRaid, maxPlayers,
              difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
        if name and (locked or extended) then
            out[#out + 1] = {
                index = i, name = name, reset = reset or 0, isRaid = isRaid,
                maxPlayers = maxPlayers, difficulty = difficultyName,
                encounters = numEncounters or 0, defeated = encounterProgress or 0,
            }
        end
    end
    return out
end

local function LockoutFor(locks, entry)
    for _, lock in ipairs(locks) do
        if Codex.Gates.Same(lock.name, entry.name) then return lock end
        for _, alias in ipairs(entry.aliases or {}) do
            if Codex.Gates.Same(lock.name, alias) then return lock end
        end
    end
    return nil
end

-- The gate written down for a place, if any.
local function AccessFor(entry)
    local A = Codex.Access
    if not (A and A.entries) then return nil end
    for _, a in ipairs(A.entries) do
        if not A.IsRejected(a) then
            if Codex.Gates.Same(a.name, entry.name) or (a.lockout and Codex.Gates.Same(a.lockout, entry.name)) then
                return a
            end
            for _, alias in ipairs(entry.aliases or {}) do
                if Codex.Gates.Same(a.name, alias) or (a.lockout and Codex.Gates.Same(a.lockout, alias)) then
                    return a
                end
            end
        end
    end
    return nil
end

-- Bosses down and bosses up, where the client will say; the catalogue's
-- list otherwise.
-- The bosses, one per line, marked off where the client will say which
-- are down. A list of fifteen names run together is not a list anyone
-- reads.
local function BossLines(entry, lock)
    local killed = nil
    if lock and GetSavedInstanceEncounterInfo and lock.encounters > 0 then
        killed = {}
        for e = 1, lock.encounters do
            local ok, boss, _, down = pcall(GetSavedInstanceEncounterInfo, lock.index, e)
            if ok and boss then killed[boss] = down and true or false end
        end
    end

    local names = entry and entry.bosses or nil
    if not names and killed then
        names = {}
        for boss in pairs(killed) do names[#names + 1] = boss end
        table.sort(names)
    end
    if not names or #names == 0 then return nil end

    local lines = { "", "|cffffd700Bosses|r" }
    for _, boss in ipairs(names) do
        local state = killed and killed[boss]
        if state == true then
            lines[#lines + 1] = "|cff73c773+|r  |cff888888" .. boss .. "|r"
        elseif state == false then
            lines[#lines + 1] = "|cffffd700-|r  " .. boss
        else
            lines[#lines + 1] = "   " .. boss
        end
    end
    return table.concat(lines, "|n")
end

local function StepLines(access, state)
    local missing = {}
    for _, name in ipairs(state.missing or {}) do missing[name] = true end
    local lines = {}
    for _, step in ipairs(access.steps or {}) do
        local name = step.label or step.name or step.kind or "?"
        local done = not missing[name]
        lines[#lines + 1] = (done and "|cff73c773+|r  |cff888888" or "|cffffd700-|r  ")
            .. name .. (done and "|r" or "")
    end
    return #lines > 0 and table.concat(lines, "|n") or nil
end

---------------------------------------------------------------------------
-- One place, read
---------------------------------------------------------------------------

-- What to say about a place: the row, and a word for what it is
-- ("saved", "low", "gated", "outgrown", "open", "yours").
local function Read(entry, locks)
    local level = UnitLevel("player") or 1
    local lock = LockoutFor(locks, entry)
    local access = AccessFor(entry)
    local state = access and Codex.Access.Evaluate(access) or nil
    local steps = access and #(access.steps or {}) or 0
    local tuned = entry.level

    -- Title, then the facts as pairs, then a section per thing worth
    -- saying. Tabs make a pair; an empty line makes a gap.
    local row = { label = entry.name }
    local lines = { entry.name }
    local function Pair(key, value) lines[#lines + 1] = key .. "\t" .. value end
    local function Gap() lines[#lines + 1] = "" end

    if tuned then Pair("Level", tostring(tuned)) end
    if entry.players and entry.players > 0 then Pair("Party", ("%d players"):format(entry.players)) end
    if entry.wings and #entry.wings > 0 then Pair("Wings", table.concat(entry.wings, ", ")) end

    local word, verdict
    if lock then
        word = "saved"
        row.state = "locked"
        if lock.encounters > 0 then
            row.detail = ("%d/%d down   |   resets in %s"):format(lock.defeated, lock.encounters, Duration(lock.reset))
        else
            row.detail = "saved   |   resets in " .. Duration(lock.reset)
        end
        Pair("Resets in", Duration(lock.reset))
        verdict = "|cffffd700You are saved to this one.|r"
    elseif tuned and level < tuned - BAND_BELOW then
        word = "low"
        row.muted = true
        row.detail = ("level %d"):format(tuned)
        verdict = ("|cff888888For level %d - come back later.|r"):format(tuned)
    elseif steps > 0 and state and not state.complete then
        word = "gated"
        row.state = "open"
        row.detail = ("%d of %d step%s"):format(state.done or 0, steps, steps == 1 and "" or "s")
        verdict = "|cffffd700Not yet attuned.|r"
    elseif tuned and entry.kind == "dungeon" and level > tuned + BAND_ABOVE then
        word = "outgrown"
        row.muted = true
        row.detail = ("level %d"):format(tuned)
        verdict = "|cff888888Below your level now.|r"
    elseif tuned and entry.kind == "dungeon" and level >= tuned - BAND_BELOW and level <= tuned + BAND_ABOVE then
        word = "yours"
        row.state = "done"
        row.detail = "for your level"
        verdict = "|cff73c773Tuned for where you are.|r"
    else
        word = "open"
        row.state = "done"
        row.detail = "open"
        verdict = "|cff73c773Open to you.|r"
    end

    if verdict then
        Gap()
        lines[#lines + 1] = verdict
    end

    -- The attunement, wherever it stands, under its own heading.
    if steps > 0 and state then
        Gap()
        lines[#lines + 1] = ("|cffffd700Attunement|r  |cff888888%d of %d|r"):format(
            state.done or 0, steps)
        local stepLines = StepLines(access, state)
        if stepLines then lines[#lines + 1] = stepLines end
    end

    local bosses = BossLines(entry, lock)
    if bosses then lines[#lines + 1] = bosses end

    row.tip = table.concat(lines, "|n")
    return row, word
end

---------------------------------------------------------------------------
-- Blocks
---------------------------------------------------------------------------

local function ByKind()
    local byKind, kinds = {}, {}
    for _, entry in ipairs(Catalogue()) do
        local kind = KIND_TITLE[entry.kind] and entry.kind or "dungeon"
        if not byKind[kind] then
            byKind[kind] = {}
            kinds[#kinds + 1] = kind
        end
        byKind[kind][#byKind[kind] + 1] = entry
    end
    table.sort(kinds, function(a, b) return (KIND_ORDER[a] or 9) < (KIND_ORDER[b] or 9) end)
    for _, list in pairs(byKind) do
        table.sort(list, function(a, b)
            if (a.level or 999) ~= (b.level or 999) then return (a.level or 999) < (b.level or 999) end
            return a.name < b.name
        end)
    end
    return byKind, kinds
end

local function Blocks()
    local byKind, kinds = ByKind()
    local blocks = {}

    for index, kind in ipairs(kinds) do
        local entries = byKind[kind]
        blocks[#blocks + 1] = {
            key   = kind,
            title = KIND_TITLE[kind],
            GetRows = function()
                local rows, locks = {}, Lockouts()
                for _, entry in ipairs(entries) do rows[#rows + 1] = (Read(entry, locks)) end
                return rows
            end,
            GetBar = function()
                local locks = Lockouts()
                local counts = {}
                for _, entry in ipairs(entries) do
                    local _, word = Read(entry, locks)
                    counts[word] = (counts[word] or 0) + 1
                end
                local parts = {}
                if counts.yours then parts[#parts + 1] = ("%d for your level"):format(counts.yours) end
                if counts.open then parts[#parts + 1] = ("%d open"):format(counts.open) end
                if counts.saved then parts[#parts + 1] = ("%d saved"):format(counts.saved) end
                if counts.gated then parts[#parts + 1] = ("%d gated"):format(counts.gated) end
                if #parts == 0 then return nil end
                return { text = table.concat(parts, "  |  ") }
            end,
            GetHighlight = index == 1 and function()
                local locks = Lockouts()
                local open = 0
                for _, k in ipairs(kinds) do
                    for _, entry in ipairs(byKind[k]) do
                        local _, word = Read(entry, locks)
                        if word == "open" or word == "yours" then open = open + 1 end
                    end
                end
                return {
                    value = open,
                    label = open == 1 and "instance open to you" or "instances open to you",
                    color = open > 0 and Codex.STATE_COLOR.done or nil,
                }
            end or nil,
        }
    end

    -- Lockouts the catalogue does not know.
    local strays = {}
    for _, lock in ipairs(Lockouts()) do
        local known = false
        for _, entry in ipairs(Catalogue()) do
            if LockoutFor({ lock }, entry) then known = true break end
        end
        if not known then strays[#strays + 1] = lock end
    end
    if #strays > 0 then
        blocks[#blocks + 1] = {
            key   = "_other",
            title = "Also saved to",
            GetRows = function()
                local rows = {}
                for _, lock in ipairs(strays) do
                    rows[#rows + 1] = {
                        label  = lock.name .. (lock.difficulty and lock.difficulty ~= "" and ("  " .. lock.difficulty) or ""),
                        detail = lock.encounters > 0
                            and ("%d/%d down   |   resets in %s"):format(lock.defeated, lock.encounters, Duration(lock.reset))
                            or ("resets in " .. Duration(lock.reset)),
                        state  = "locked",
                        tip    = lock.name .. "|nSaved to this one."
                            .. (BossLines(nil, lock) or ""),
                    }
                end
                return rows
            end,
        }
    end

    return blocks
end

local function Sync()
    Codex:SyncGroupSections(PREFIX, COMMON, Blocks())
end

---------------------------------------------------------------------------
-- Today: the places tuned for where you are
---------------------------------------------------------------------------

Codex:RegisterSection({
    id     = "forYourLevel",
    tab    = "today",
    title  = "For your level",
    about  = "Dungeons tuned for where you are now, give or take a couple of"
        .. " levels. The full map of them is on the Instances page.",
    order  = 7,
    empty  = function()
        local level = UnitLevel("player") or 1
        local byKind = ByKind()
        local nearest, gap
        for _, entry in ipairs(byKind.dungeon or {}) do
            local at = entry.level
            if at and at > level and (not gap or at - level < gap) then nearest, gap = entry, at - level end
        end
        if not nearest then
            return "No dungeon is tuned for your level. You have outgrown every one written down."
        end
        return ("No dungeon is tuned for level %d. %s opens at %d, %d level%s away."):format(
            level, nearest.name, nearest.level, gap, gap == 1 and "" or "s")
    end,
    events = { "PLAYER_LEVEL_UP", "UPDATE_INSTANCE_INFO", "PLAYER_ENTERING_WORLD" },
    GetRows = function()
        local rows, locks = {}, Lockouts()
        local byKind = ByKind()
        for _, entry in ipairs(byKind.dungeon or {}) do
            local row, word = Read(entry, locks)
            if word == "yours" or word == "saved" then
                row.detail = ("level %d   |   %d players"):format(entry.level or 0, entry.players or 5)
                    .. (word == "saved" and "   |   saved" or "")
                rows[#rows + 1] = row
            end
        end
        return rows
    end,
    GetHighlight = function()
        local locks = Lockouts()
        local byKind = ByKind()
        local n = 0
        for _, entry in ipairs(byKind.dungeon or {}) do
            local _, word = Read(entry, locks)
            if word == "yours" then n = n + 1 end
        end
        return {
            value = n,
            label = n == 1 and "dungeon for your level" or "dungeons for your level",
            color = n > 0 and Theme.colors.gold or nil,
        }
    end,
})

---------------------------------------------------------------------------
-- Staying current
---------------------------------------------------------------------------

BazUI:QueueForModule("Codex", function()
    Sync()
    local watcher = CreateFrame("Frame")
    for _, event in ipairs({ "UPDATE_INSTANCE_INFO", "BOSS_KILL", "PLAYER_ENTERING_WORLD",
                             "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP" }) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    watcher:SetScript("OnEvent", function()
        Sync()
        if Codex.IsShown and Codex:IsShown() then
            Codex.Panel:RebuildTabs()
            Codex.Panel:QueueRefresh()
        end
    end)
    if RequestRaidInfo then pcall(RequestRaidInfo) end
end)
