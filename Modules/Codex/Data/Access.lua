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
-- Checking the table against the client, and reading the player's state
--
-- Both go through Data/Gates.lua, which is the one place that knows how
-- to ask this client a question about a character. A goal and an
-- attunement are the same shape underneath.
---------------------------------------------------------------------------

local rejected = {}

function Access.Validate()
    rejected = Codex.Gates.Validate(Access.entries)
    return rejected
end

function Access.IsRejected(entry)
    return rejected[entry.id] ~= nil
end

function Access.Rejected()
    return rejected
end

-- Whether the instance's own lock is currently on you, which is the
-- difference between "you could go" and "you already went".
local function SavedTo(lockoutName)
    if not lockoutName then return false, nil end
    local count = GetNumSavedInstances and GetNumSavedInstances() or 0
    for i = 1, count do
        local name, _, reset, _, locked, extended = GetSavedInstanceInfo(i)
        if name and Codex.Gates.Same(name, lockoutName) and (locked or extended) then
            return true, reset
        end
    end
    return false, nil
end

-- The whole state of one door: its gates, plus the two things a gate
-- cannot express, your level and the lockout already on you.
function Access.Evaluate(entry)
    local state = Codex.Gates.Evaluate(entry)

    local level = UnitLevel("player") or 1
    local underLevelled = entry.level and level < entry.level
    local saved, reset = SavedTo(entry.lockout)

    state.ready = state.complete
    state.open  = state.complete and not saved and not underLevelled
    state.saved = saved
    state.reset = reset
    state.underLevelled = underLevelled
    return state
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
