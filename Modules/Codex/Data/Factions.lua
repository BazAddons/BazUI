-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: the factions there are
--
-- The client lists only the factions this character has met. This is
-- the rest of them, written down so the Reputation page can show what
-- you have not met yet - greyed, with live standing read by id.
--
-- Ids, not names. The client supplies the name in your language, and
-- it confirms each entry at load: a faction it has no description for
-- is a creature faction or a leftover, not a reputation, and is left
-- out. So a wrong id here hides itself rather than lying.
--
-- The groups are the words the game's own pane uses as headers. Where
-- a faction already met sits under a header, its unmet neighbours join
-- it under that header, whatever the client calls it; the words here
-- are only the fallback when nothing in the group has been met yet.
--
-- Taken from a probe of Forever (build 1.60.1, September 2026) with
-- /codex factions, on an Alliance character - the client does not
-- answer for the other side's cities, so the Horde ids are from vanilla
-- and wait to be confirmed by a Horde character.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
Codex.Factions = Codex.Factions or {}
local Factions = Codex.Factions

Factions.entries = {
    -- Home cities
    { id = 72,   group = "Alliance", side = "Alliance" },   -- Stormwind
    { id = 47,   group = "Alliance", side = "Alliance" },   -- Ironforge
    { id = 69,   group = "Alliance", side = "Alliance" },   -- Darnassus
    { id = 54,   group = "Alliance", side = "Alliance" },   -- Gnomeregan Exiles
    { id = 76,   group = "Horde",    side = "Horde" },      -- Orgrimmar
    { id = 81,   group = "Horde",    side = "Horde" },      -- Thunder Bluff
    { id = 68,   group = "Horde",    side = "Horde" },      -- Undercity
    { id = 530,  group = "Horde",    side = "Horde" },      -- Darkspear Trolls

    -- Battlegrounds
    { id = 730,  group = "Alliance Forces", side = "Alliance" },   -- Stormpike Guard
    { id = 890,  group = "Alliance Forces", side = "Alliance" },   -- Silverwing Sentinels
    { id = 509,  group = "Alliance Forces", side = "Alliance" },   -- The League of Arathor
    { id = 729,  group = "Horde Forces",    side = "Horde" },      -- Frostwolf Clan
    { id = 889,  group = "Horde Forces",    side = "Horde" },      -- Warsong Outriders
    { id = 510,  group = "Horde Forces",    side = "Horde" },      -- The Defilers

    -- Goblins
    { id = 21,   group = "Steamwheedle Cartel" },   -- Booty Bay
    { id = 577,  group = "Steamwheedle Cartel" },   -- Everlook
    { id = 369,  group = "Steamwheedle Cartel" },   -- Gadgetzan
    { id = 470,  group = "Steamwheedle Cartel" },   -- Ratchet

    -- Everyone else vanilla had
    { id = 529,  group = "Other" },   -- Argent Dawn
    { id = 87,   group = "Other" },   -- Bloodsail Buccaneers
    { id = 609,  group = "Other" },   -- Cenarion Circle
    { id = 909,  group = "Other" },   -- Darkmoon Faire
    { id = 92,   group = "Other" },   -- Gelkis Clan Centaur
    { id = 93,   group = "Other" },   -- Magram Clan Centaur
    { id = 749,  group = "Other" },   -- Hydraxian Waterlords (not yet on Forever)
    { id = 349,  group = "Other" },   -- Ravenholdt
    { id = 809,  group = "Other" },   -- Shen'dralar
    { id = 59,   group = "Other" },   -- Thorium Brotherhood
    { id = 576,  group = "Other" },   -- Timbermaw Hold
    { id = 589,  group = "Other" },   -- Wintersaber Trainers
    { id = 70,   group = "Other" },   -- Syndicate
    { id = 270,  group = "Other" },   -- Zandalar Tribe (not yet on Forever)
    { id = 910,  group = "Other" },   -- Brood of Nozdormu (not yet on Forever)

    -- Forever's own
    { id = 2586, group = "Other" },   -- Azeroth Commerce Authority
    { id = 2634, group = "Other" },   -- Blood Moon
    { id = 2679, group = "Other" },   -- Order of the Silver Hand
    { id = 2719, group = "Other" },   -- Cenarion Scouts
    { id = 2740, group = "Other" },   -- Kirin Tor
    { id = 2747, group = "Other" },   -- Barkskin Burrow
    { id = 2765, group = "Other" },   -- Guardians of Hyjal
    { id = 2768, group = "Other" },   -- The Blackthorne Pact
    { id = 2769, group = "Other" },   -- Gelkis Outcasts
    { id = 2779, group = "Other" },   -- High Order
    { id = 2788, group = "Other" },   -- Ashen Reign
    { id = 2798, group = "Other" },   -- Darkspear Raiders
    { id = 2799, group = "Other" },   -- Theramore Expeditionary Force
    { id = 2819, group = "Other" },   -- The Watchers
    { id = 2826, group = "Other" },   -- Brotherhood of the Horse
    { id = 2827, group = "Other" },   -- Powderfuse
    { id = 629,  group = "Other" },   -- Shatterspear Trolls
    { id = 2757, group = "Other" },   -- Zephras Peacekeepers
    { id = 2758, group = "Other" },   -- Nightclaw Druids
    { id = 108,  group = "Other" },   -- Theramore
    { id = 61,   group = "Other" },   -- Dalaran
}

-- What the client says about a written-down faction, or nil where it is
-- not a reputation a player can hold: no such id, a header, the other
-- side's, or a creature faction (no description).
function Factions.Confirm(entry)
    if not (C_Reputation and C_Reputation.GetFactionDataByID) then return nil end
    if entry.side then
        local mine = UnitFactionGroup and UnitFactionGroup("player")
        if mine and mine ~= entry.side then return nil end
    end
    local ok, d = pcall(C_Reputation.GetFactionDataByID, entry.id)
    if not (ok and d and d.name and d.name ~= "") then return nil end
    if d.isHeader then return nil end
    if not d.description or d.description == "" then return nil end
    return d
end
