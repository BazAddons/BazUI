-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Nameplates: what sort of thing this is
--
-- A plate over a city guard and a plate over something trying to kill you
-- are not the same object wearing the same clothes, and until now they
-- were. One list of kinds here, and everything else - the settings page,
-- the plate itself - reads from it. Adding a kind is adding an entry.
--
-- Each kind can be switched off entirely, and that is worth explaining
-- because it looks at first like a second answer to a question the game
-- already answers.
--
-- It is not, because we can split finer than the game can. Its
-- nameplateShow* console settings have one switch for all enemies -
-- hostile players and hostile NPCs together - and nothing whatever for
-- mobs somebody else has tapped. Turning off hostile players while
-- keeping hostile NPCs is not something Interface Options can express.
--
-- Where the two do overlap the game still wins: if its setting says a
-- unit gets no plate then there is nothing here for us to hide. Ours
-- only ever takes away, never adds. So a missing plate is still
-- explained by one page or the other, and with everything on here the
-- game is exactly as much in charge as it was before.
--
-- Two things are deliberately not in this list, because the game already
-- answers them and two answers would only disagree:
--
--   Pets, guardians, totems and minions. The game keeps them as a
--   visibility category and colors them by whose side they are on, and
--   so do we: a hostile warlock's felhunter is a hostile NPC. A kind of
--   its own would have to outrank friendly and hostile both, and a pet
--   that ignored whether it was going to hit you would read wrong.
--
--   Whether this is your target. That is a state a plate passes through,
--   not what the unit is - a hostile NPC is one whether you are looking
--   at it or not. The target mark stays its own switch.
--
-- ORDER MATTERS. The first kind that matches wins, so they run from most
-- specific to least: tapped before hostile, players before NPCs. Move an
-- entry and you change what a unit is.
--
-- Every matcher here is on the plain side of Forever's secret values -
-- checked against the client's own API documentation, none of
-- UnitIsPlayer, UnitReaction, UnitIsTapDenied or UnitPlayerControlled
-- carries a SecretReturns predicate. See Core/Compat.lua.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("Nameplates")

local function Reaction(unit)
    return (UnitReaction and UnitReaction("player", unit)) or 0
end

local function IsPlayer(unit)
    return UnitIsPlayer and UnitIsPlayer(unit) and true or false
end

addon.KINDS = {
    {
        id    = "tapped",
        label = "Tapped by someone else",
        desc  = "A mob somebody else got to first, which you can hit but cannot loot or take credit for. Turn its plate down or off here; the color is left as the reaction color.",
        -- Above the hostile kinds on purpose: a tapped mob is still
        -- hostile, and knowing it is not yours is the more useful of the
        -- two facts.
        match = function(unit)
            return not IsPlayer(unit)
                and UnitIsTapDenied and UnitIsTapDenied(unit) and true or false
        end,
    },
    {
        id    = "friendlyPlayer",
        label = "Friendly players",
        desc  = "Other players on your side.",
        match = function(unit)
            return IsPlayer(unit) and Reaction(unit) > 4
        end,
    },
    {
        id    = "hostilePlayer",
        label = "Hostile players",
        desc  = "Players you can attack.",
        match = function(unit)
            return IsPlayer(unit) and Reaction(unit) <= 4
        end,
    },
    {
        id    = "friendlyNpc",
        label = "Friendly NPCs",
        desc  = "Guards, vendors, quest givers - anything that will not fight you.",
        match = function(unit) return Reaction(unit) > 4 end,
    },
    {
        id    = "neutralNpc",
        label = "Neutral NPCs",
        desc  = "Mobs that leave you alone until you start something.",
        match = function(unit) return Reaction(unit) == 4 end,
    },
    {
        id    = "hostileNpc",
        label = "Hostile NPCs",
        desc  = "Anything that will attack you on sight.",
        -- The last entry, and it matches everything left. A unit the
        -- other tests could not place is treated as something that might
        -- hit you, which is the safer way round to be wrong.
        match = function() return true end,
    },
}

---------------------------------------------------------------------------
-- Which one a unit is
---------------------------------------------------------------------------

-- Worked out fresh each time rather than kept on the plate. A plate is
-- recycled onto whoever stands there next, and a mob changes hands the
-- moment somebody else tags it, so a remembered answer goes stale in
-- ordinary play.
function addon:KindFor(unit)
    if not (unit and UnitExists and UnitExists(unit)) then return self.KINDS[#self.KINDS] end
    for _, kind in ipairs(self.KINDS) do
        local ok, matched = pcall(kind.match, unit)
        if ok and matched then return kind end
    end
    return self.KINDS[#self.KINDS]
end

---------------------------------------------------------------------------
-- What a kind is allowed to say for itself
--
-- Each of these is the module's switch until the kind has been given its
-- own answer, and the kind's from then on. Checked against nil rather
-- than leaned on: `or module` would turn a kind you deliberately switched
-- off back on, and the whole point of the list is that friendly NPCs can
-- be quiet while friendly players are not.
--
-- Saved as one table per kind under "kinds" rather than as thirty loose
-- settings, so a profile carries the shape rather than a flat list of
-- names nobody can read.
---------------------------------------------------------------------------

-- rank and class color are each only about half the kinds, and rather
-- than leave a switch that silently does nothing, the page grays them
-- out. Named here so the page and the plate agree about which.
local PLAYER_ONLY = { friendlyPlayer = true, hostilePlayer = true }
local NPC_ONLY    = { friendlyNpc = true, neutralNpc = true, hostileNpc = true, tapped = true }

function addon:KindAppliesTo(kindId, key)
    if key == "classColor" then return PLAYER_ONLY[kindId] and true or false end
    if key == "showRank"   then return NPC_ONLY[kindId] and true or false end
    return true
end

function addon:KindValue(kindId, key)
    local kinds = self:GetSetting("kinds")
    local saved = kinds and kinds[kindId] and kinds[kindId][key]
    if saved ~= nil then return saved and true or false end
    return self:GetSetting(key) ~= false
end

function addon:SetKindValue(kindId, key, value)
    local kinds = self:GetSetting("kinds") or {}
    kinds[kindId] = kinds[kindId] or {}
    kinds[kindId][key] = value and true or false
    self:SetSetting("kinds", kinds)
end

-- The answer for the unit standing there, which is what the plate wants.
function addon:UnitWants(unit, key)
    local kind = self:KindFor(unit)
    if not self:KindAppliesTo(kind.id, key) then return false end
    return self:KindValue(kind.id, key)
end
