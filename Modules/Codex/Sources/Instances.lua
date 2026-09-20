-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: Instances
--
-- The whole picture of where you can go: every raid and dungeon the
-- codex has written down, with its gate and its lockout on one row.
-- Today shows the slice of this that matters this week; this is the
-- map it is cut from.
--
-- A row reads one of four ways, worst first: saved (with bosses down
-- and time to reset), not yet attuned (steps done of steps needed),
-- attuned but under level, or open. Anything you are saved to that the
-- codex has not written down is listed too, so a lockout is never
-- missing from the page just because the data has not caught up.
---------------------------------------------------------------------------

local Codex = BazUI.Codex

local TAB = "instances"
local COMMON = {
    tab      = TAB,
    tabLabel = "Instances",
    tabOrder = 26,
    tabIcon  = "Interface\\Icons\\INV_Misc_Key_03",
    empty    = "Nothing written down here yet.",
}
local PREFIX = "inst."

local KIND_TITLE = { raid = "Raids", dungeon = "Dungeons" }
local KIND_ORDER = { raid = 1, dungeon = 2 }

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

local function Duration(seconds)
    return BazUI:FormatSpan(seconds)
end

-- Every live lockout, by name, with what is known about it.
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

local function LockoutFor(locks, lockoutName)
    if not lockoutName then return nil end
    for _, lock in ipairs(locks) do
        if Codex.Gates.Same(lock.name, lockoutName) then return lock end
    end
    return nil
end

-- Bosses down and bosses up, where the client will say.
local function BossLines(lock)
    if not (GetSavedInstanceEncounterInfo and lock.encounters > 0) then return nil end
    local down, up = {}, {}
    for e = 1, lock.encounters do
        local ok, boss, _, killed = pcall(GetSavedInstanceEncounterInfo, lock.index, e)
        if ok and boss then
            if killed then down[#down + 1] = boss else up[#up + 1] = boss end
        end
    end
    local lines = {}
    if #down > 0 then lines[#lines + 1] = "|cff73c773Down:|r " .. table.concat(down, ", ") end
    if #up > 0 then lines[#lines + 1] = "|cffffd700Still up:|r " .. table.concat(up, ", ") end
    return #lines > 0 and table.concat(lines, "|n") or nil
end

-- The gate evaluator names what is missing; everything else is done.
local function StepLines(entry, state)
    local missing = {}
    for _, name in ipairs(state.missing or {}) do missing[name] = true end
    local lines = {}
    for _, step in ipairs(entry.steps or {}) do
        local name = step.label or step.name or step.kind or "?"
        local done = not missing[name]
        lines[#lines + 1] = (done and "|cff73c773+|r " or "|cff888888-|r ") .. name
    end
    return #lines > 0 and table.concat(lines, "|n") or nil
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function EntryRow(entry, locks)
    local A = Codex.Access
    local state = A.Evaluate(entry)
    local lock = LockoutFor(locks, entry.lockout)
    local steps = #(entry.steps or {})
    local done = state.done or 0
    local level = UnitLevel("player") or 1

    local row = { label = entry.name }
    local tip = entry.name
    if entry.level then tip = tip .. ("  |cff888888level %d|r"):format(entry.level) end

    if lock then
        row.state = "locked"
        if lock.encounters > 0 then
            row.detail = ("%d/%d down   |   resets in %s"):format(lock.defeated, lock.encounters, Duration(lock.reset))
        else
            row.detail = "saved   |   resets in " .. Duration(lock.reset)
        end
        local bosses = BossLines(lock)
        tip = tip .. "|nSaved to this one." .. (bosses and ("|n" .. bosses) or "")
    elseif steps > 0 and not state.complete then
        row.state = "open"
        row.detail = ("%d of %d step%s"):format(done, steps, steps == 1 and "" or "s")
        local lines = StepLines(entry, state)
        tip = tip .. "|nNot yet attuned." .. (lines and ("|n" .. lines) or "")
    elseif entry.level and level < entry.level then
        row.muted = true
        row.detail = ("level %d"):format(entry.level)
        tip = tip .. ("|nOpen to you at level %d."):format(entry.level)
    else
        row.state = "done"
        row.detail = "open"
        tip = tip .. "|nAttuned, at level, and not saved."
    end
    row.tip = tip
    return row, row.state
end

local function Blocks()
    local A = Codex.Access
    if not (A and A.entries) then return {} end
    local locks = Lockouts()

    local byKind, kinds = {}, {}
    for _, entry in ipairs(A.entries) do
        if not A.IsRejected(entry) then
            local kind = KIND_TITLE[entry.kind] and entry.kind or "dungeon"
            if not byKind[kind] then
                byKind[kind] = {}
                kinds[#kinds + 1] = kind
            end
            byKind[kind][#byKind[kind] + 1] = entry
        end
    end
    table.sort(kinds, function(a, b) return (KIND_ORDER[a] or 9) < (KIND_ORDER[b] or 9) end)

    local blocks = {}
    local known = {}
    for index, kind in ipairs(kinds) do
        local entries = byKind[kind]
        table.sort(entries, function(a, b)
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
            return a.name < b.name
        end)
        for _, e in ipairs(entries) do if e.lockout then known[#known + 1] = e.lockout end end
        blocks[#blocks + 1] = {
            key   = kind,
            title = KIND_TITLE[kind],
            GetRows = function()
                local rows = {}
                local liveLocks = Lockouts()
                for _, entry in ipairs(entries) do
                    rows[#rows + 1] = (EntryRow(entry, liveLocks))
                end
                return rows
            end,
            GetBar = function()
                local liveLocks = Lockouts()
                local open, saved = 0, 0
                for _, entry in ipairs(entries) do
                    local _, s = EntryRow(entry, liveLocks)
                    if s == "done" then open = open + 1 elseif s == "locked" then saved = saved + 1 end
                end
                local parts = {}
                if open > 0 then parts[#parts + 1] = ("%d open"):format(open) end
                if saved > 0 then parts[#parts + 1] = ("%d saved"):format(saved) end
                if #parts == 0 then return nil end
                return { text = table.concat(parts, "  |  ") }
            end,
            GetHighlight = index == 1 and function()
                local liveLocks = Lockouts()
                local open = 0
                for _, k in ipairs(kinds) do
                    for _, entry in ipairs(byKind[k]) do
                        local _, s = EntryRow(entry, liveLocks)
                        if s == "done" then open = open + 1 end
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

    -- Lockouts the data does not know about.
    local strays = {}
    for _, lock in ipairs(locks) do
        local found = false
        for _, name in ipairs(known) do
            if Codex.Gates.Same(lock.name, name) then found = true break end
        end
        if not found then strays[#strays + 1] = lock end
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
                        tip    = BossLines(lock),
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
