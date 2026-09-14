-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex data: goals
--
-- The long projects a character is working on. An attunement is a door
-- someone else put a lock on; a goal is something you decided to go and
-- get. Both are lists of gates, so both use Data/Gates.lua.
--
-- Two kinds live here. Some need nothing written down at all, because
-- the client already answers them: a savings target is your purse
-- against a number, a level is a level. Those are exact, they work for
-- every character, and they draw a real bar.
--
-- The rest are the famous ones, and those need an id written down. Each
-- carries the name it believes its id has and is checked against the
-- client before it is ever shown, the same as the attunements. A number
-- I got wrong hides its goal; `/codex verify` says which.
--
-- Goals are filtered by class and by level, so a character only sees
-- what is theirs to chase. The table is meant to grow.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
Codex.Goals = Codex.Goals or {}
local Goals = Codex.Goals

local GOLD = 10000   -- copper in a gold piece

---------------------------------------------------------------------------
-- The table
--
--   class    the class file name (WARLOCK, PRIEST...), or nil for anyone
--   level    the level below which the goal is not worth showing yet
--   steps    gates from Data/Gates.lua
---------------------------------------------------------------------------

Goals.entries = {
    ---------------------------------------------------------------
    -- Worked out entirely from the client
    ---------------------------------------------------------------
    {
        id = "mount60", name = "Your first mount", kind = "mount", level = 34,
        note = "Riding at 40 costs about 100 gold all in.",
        steps = {
            { kind = "level", level = 40, label = "Reach level 40" },
            { kind = "money", copper = 100 * GOLD, label = "Save 100 gold" },
        },
    },
    {
        id = "mount100", name = "Epic mount", kind = "mount", level = 54,
        note = "The fast one runs to about 1,000 gold at level 60.",
        steps = {
            { kind = "level", level = 60, label = "Reach level 60" },
            { kind = "money", copper = 1000 * GOLD, label = "Save 1,000 gold" },
        },
    },

    ---------------------------------------------------------------
    -- The famous ones, which need a number written down
    ---------------------------------------------------------------
    {
        id = "dreadsteed", name = "Dreadsteed", kind = "mount",
        class = "WARLOCK", level = 55,
        steps = {
            { kind = "mount", name = "Dreadsteed", label = "Win the Dreadsteed" },
        },
    },
    {
        id = "charger", name = "Charger", kind = "mount",
        class = "PALADIN", level = 55,
        steps = {
            { kind = "mount", name = "Charger", label = "Win the Charger" },
        },
    },
    {
        id = "benediction", name = "Benediction", kind = "weapon",
        class = "PRIEST", level = 58,
        steps = {
            { kind = "item", id = 18608, name = "Benediction", label = "Claim Benediction" },
        },
    },
    {
        id = "rhokdelar", name = "Rhok'delar", kind = "weapon",
        class = "HUNTER", level = 58,
        steps = {
            { kind = "item", id = 18713, name = "Rhok'delar, Longbow of the Ancient Keepers",
              label = "Claim Rhok'delar" },
        },
    },
    {
        id = "lokdelar", name = "Lok'delar", kind = "weapon",
        class = "HUNTER", level = 58,
        steps = {
            { kind = "item", id = 18714, name = "Lok'delar, Stave of the Ancient Keepers",
              label = "Claim Lok'delar" },
        },
    },
}

---------------------------------------------------------------------------
-- Reading them
---------------------------------------------------------------------------

local rejected = {}

function Goals.Validate()
    rejected = Codex.Gates.Validate(Goals.entries)
    return rejected
end

function Goals.Rejected()
    return rejected
end

-- Goals for this character: its class, at a level where the goal has
-- started to matter, and not one the client disagreed with.
function Goals.All()
    local _, classFile = UnitClass("player")
    local level = UnitLevel("player") or 1

    local out = {}
    for _, entry in ipairs(Goals.entries) do
        local mine = (not entry.class) or (entry.class == classFile)
        local ready = (not entry.level) or (level >= entry.level)
        if mine and ready and not rejected[entry.id] then
            out[#out + 1] = Codex.Gates.Evaluate(entry)
        end
    end

    table.sort(out, function(a, b)
        -- Finished ones drop to the bottom; of the rest, the nearest
        -- first, because that is the one worth an evening.
        if a.complete ~= b.complete then return b.complete end
        if a.fraction ~= b.fraction then return a.fraction > b.fraction end
        return a.entry.name < b.entry.name
    end)
    return out
end

BazUI:QueueForLogin(function()
    C_Timer.After(6, function()
        Goals.Validate()
        if Codex.Panel and Codex:IsShown() then Codex.Panel:QueueRefresh() end
    end)
end)
