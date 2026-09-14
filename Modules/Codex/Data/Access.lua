-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex data: what is open to you
--
-- Classic has no attunement API. Retail hands an addon a list of what
-- you are eligible for; this client hands you nothing, because in 2004
-- the answer lived in the player's head. So the codex works it out from
-- the primitives the client does answer:
--
--   a quest you finished     C_QuestLog.IsQuestFlaggedCompleted
--   a key in your bags       C_Item.GetItemCount
--   a reputation standing    the faction list
--   your level               UnitLevel
--
-- Which means this file: the one place that says which of those gates
-- guard which door. It is deliberate, written-down knowledge, the kind
-- the Codex's own header allows, and it is the only file in the module
-- that knows anything the client did not tell it.
--
-- Every entry checks itself. A quest step carries the name we believe
-- its id has, and an item step the same; at load the client is asked
-- what that id really is, and an entry whose name comes back different
-- is dropped rather than shown. A wrong number here therefore shows
-- nothing, never something false. `/codex verify` lists what failed,
-- which is how a wrong number gets found and corrected.
--
-- Entries are welcome to be incomplete. A door nobody has written down
-- yet simply does not appear.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
Codex.Access = Codex.Access or {}
local Access = Codex.Access

---------------------------------------------------------------------------
-- The table
--
--   kind     "raid" or "dungeon", used for grouping and wording
--   level    the level the instance itself expects
--   lockout  the name GetSavedInstanceInfo reports, when it has one, so
--            a raid you are already saved to is not offered as open
--   steps    every gate, all of which must be met
---------------------------------------------------------------------------

Access.entries = {
    {
        id = "moltencore", name = "Molten Core", kind = "raid", level = 55,
        lockout = "Molten Core",
        steps = {
            { kind = "quest", id = 7848, name = "Attunement to the Core" },
        },
    },
    {
        id = "onyxia", name = "Onyxia's Lair", kind = "raid", level = 60,
        lockout = "Onyxia's Lair",
        steps = {
            { kind = "item", id = 16309, name = "Drakefire Amulet" },
        },
    },
    {
        id = "blackwing", name = "Blackwing Lair", kind = "raid", level = 60,
        lockout = "Blackwing Lair",
        steps = {
            { kind = "quest", id = 7761, name = "Blackhand's Command" },
        },
    },
    {
        id = "naxxramas", name = "Naxxramas", kind = "raid", level = 60,
        lockout = "Naxxramas",
        steps = {
            { kind = "reputation", faction = "Argent Dawn", standing = 6,
              name = "Honored with the Argent Dawn" },
        },
    },
    {
        id = "brd", name = "Blackrock Depths", kind = "dungeon", level = 52,
        steps = {
            { kind = "item", id = 11000, name = "Shadowforge Key" },
        },
    },
    {
        id = "ubrs", name = "Upper Blackrock Spire", kind = "dungeon", level = 58,
        steps = {
            { kind = "item", id = 12344, name = "Seal of Ascension" },
        },
    },
    {
        id = "scholomance", name = "Scholomance", kind = "dungeon", level = 58,
        steps = {
            { kind = "item", id = 13704, name = "Skeleton Key" },
        },
    },
    {
        id = "stratholme", name = "Stratholme", kind = "dungeon", level = 58,
        steps = {
            { kind = "item", id = 12382, name = "Key to the City" },
        },
    },
    {
        id = "diremaul", name = "Dire Maul", kind = "dungeon", level = 55,
        steps = {
            { kind = "item", id = 18249, name = "Crescent Key" },
        },
    },
    {
        id = "maraudon", name = "Maraudon", kind = "dungeon", level = 46,
        steps = {
            { kind = "item", id = 17191, name = "Scepter of Celebras" },
        },
    },
}

---------------------------------------------------------------------------
-- Checking the table against the client
---------------------------------------------------------------------------

local function Same(a, b)
    if not (a and b) then return false end
    return a:lower() == b:lower()
end

-- Returns true when the client agrees, false when it disagrees, and nil
-- when it has not heard of the id yet. Only a flat disagreement counts
-- against a step: item and quest data arrive late and a missing answer
-- is not evidence of a wrong number. The second return is what the
-- client actually calls the id, which is the whole of the fix when a
-- number here is wrong.
local function StepAgrees(step)
    if step.kind == "quest" then
        if not (C_QuestLog and C_QuestLog.GetQuestInfo) then return nil end
        local title = C_QuestLog.GetQuestInfo(step.id)
        if not title or title == "" then return nil end
        return Same(title, step.name), title
    end
    if step.kind == "item" then
        local itemName = C_Item.GetItemInfo(step.id)
        if not itemName then
            if C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(step.id)
            end
            return nil
        end
        return Same(itemName, step.name), itemName
    end
    return true   -- reputation and level steps carry no id to check
end

local rejected = {}

function Access.Validate()
    wipe(rejected)
    for _, entry in ipairs(Access.entries) do
        for _, step in ipairs(entry.steps) do
            local agrees, actual = StepAgrees(step)
            if agrees == false then
                rejected[entry.id] = string.format(
                    "%s: %s %d should be \"%s\" but the client calls it \"%s\"",
                    entry.name, step.kind, step.id, step.name or "?", actual or "?")
                break
            end
        end
    end
    return rejected
end

function Access.IsRejected(entry)
    return rejected[entry.id] ~= nil
end

function Access.Rejected()
    return rejected
end

---------------------------------------------------------------------------
-- Reading the player's state
---------------------------------------------------------------------------

local function StandingWith(factionName)
    local count = (C_Reputation and C_Reputation.GetNumFactions
        and C_Reputation.GetNumFactions()) or (GetNumFactions and GetNumFactions()) or 0
    for i = 1, count do
        local name, standing, isHeader
        if C_Reputation and C_Reputation.GetFactionDataByIndex then
            local data = C_Reputation.GetFactionDataByIndex(i)
            if data then name, standing, isHeader = data.name, data.reaction, data.isHeader end
        else
            local n, _, s, _, _, _, _, _, header = GetFactionInfo(i)
            name, standing, isHeader = n, s, header
        end
        if name and not isHeader and Same(name, factionName) then return standing or 0 end
    end
    return nil
end

local function StepMet(step)
    if step.kind == "quest" then
        if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return false end
        return C_QuestLog.IsQuestFlaggedCompleted(step.id) and true or false
    end
    if step.kind == "item" then
        return (C_Item.GetItemCount(step.id, true) or 0) > 0
    end
    if step.kind == "reputation" then
        local standing = StandingWith(step.faction)
        return (standing or 0) >= (step.standing or 8)
    end
    return false
end

-- Whether the instance's own lock is currently on you, which is the
-- difference between "you could go" and "you already went".
local function SavedTo(lockoutName)
    if not lockoutName then return false, nil end
    local count = GetNumSavedInstances and GetNumSavedInstances() or 0
    for i = 1, count do
        local name, _, reset, _, locked, extended = GetSavedInstanceInfo(i)
        if name and Same(name, lockoutName) and (locked or extended) then
            return true, reset
        end
    end
    return false, nil
end

-- The whole state of one door.
function Access.Evaluate(entry)
    local done, missing = 0, {}
    for _, step in ipairs(entry.steps) do
        if StepMet(step) then
            done = done + 1
        else
            missing[#missing + 1] = step.name or step.kind
        end
    end

    local level = UnitLevel("player") or 1
    local underLevelled = entry.level and level < entry.level
    local saved, reset = SavedTo(entry.lockout)

    return {
        entry    = entry,
        done     = done,
        total    = #entry.steps,
        missing  = missing,
        ready    = (done == #entry.steps),
        open     = (done == #entry.steps) and not saved and not underLevelled,
        saved    = saved,
        reset    = reset,
        underLevelled = underLevelled,
    }
end

-- Every door, minus the ones the client disagreed with, and minus the
-- ones far enough above this character that offering them would be
-- noise rather than a plan.
function Access.All()
    local out = {}
    local level = UnitLevel("player") or 1
    for _, entry in ipairs(Access.entries) do
        if not Access.IsRejected(entry) then
            if not entry.level or level >= (entry.level - 5) then
                out[#out + 1] = Access.Evaluate(entry)
            end
        end
    end
    table.sort(out, function(a, b)
        if a.open ~= b.open then return a.open end
        if a.entry.kind ~= b.entry.kind then return a.entry.kind == "raid" end
        return a.entry.name < b.entry.name
    end)
    return out
end

BazUI:QueueForLogin(function()
    -- Item and quest names arrive over the wire, so the first pass runs
    -- once the client has had a moment to answer.
    C_Timer.After(6, function()
        Access.Validate()
        if Codex.Panel and Codex:IsShown() then Codex.Panel:QueueRefresh() end
    end)
end)
