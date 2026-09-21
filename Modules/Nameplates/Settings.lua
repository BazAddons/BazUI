-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Nameplates: the module's page
---------------------------------------------------------------------------

local addon = BazUI:GetModule("Nameplates")

local function Get(key) return function() return addon:GetSetting(key) end end

local function Set(key)
    return function(_, value)
        addon:SetSetting(key, value)
        addon:ApplySettings()
    end
end

local function Bool(key, default)
    return function()
        local value = addon:GetSetting(key)
        if value == nil then return default end
        return value and true or false
    end
end

---------------------------------------------------------------------------
-- One group per kind of unit, built from the one list that says what the
-- kinds are. See Kinds.lua - adding a kind there adds its group here,
-- and there is no second list to keep in step.
--
-- Four switches each, and all four are offered on every kind even where
-- one of them cannot apply: class color means nothing on a mob and rank
-- means nothing on a player, so those gray out in place rather than
-- vanishing. A switch you can see is not for this kind beats hunting for
-- one that moved.
--
-- Each starts as whatever the General switch above says, and holds its
-- own answer from the moment you touch it. So the page still works the
-- old way until you want it not to.
---------------------------------------------------------------------------

local KIND_ROWS = {
    { key = "showPlate",  label = "Nameplate",
      desc = "Whether this kind of unit gets a plate from BazUI at all. Off means nothing at all over their heads - not ours and not the game's. This only ever takes plates away: if the game is not giving a unit one, there is nothing here to hide. It is worth having because the game cannot split this as finely as we can - Interface Options has one switch for all enemies, so hostile players and hostile NPCs go together there, and nothing at all for mobs somebody else has tapped." },
    { key = "showBar",    label = "Health bar",
      desc = "The bar itself. With it off the plate is the unit's name and nothing else, which is the usual way to keep a city full of guards readable." },
    { key = "showName",   label = "Name" },
    { key = "showLevel",  label = "Level" },
    { key = "showRank",   label = "Rare and elite mark" },
    { key = "classColor", label = "Class color" },
}

local function KindSections()
    local out = {}
    for index, kind in ipairs(addon.KINDS or {}) do
        out[kind.id] = { label = kind.label, order = 10 + index }
    end
    return out
end

local function KindEntries(entries)
    for _, kind in ipairs(addon.KINDS or {}) do
        entries[#entries + 1] = {
            key = kind.id .. "Note", type = "note", style = "info",
            section = kind.id, order = 0,
            text = kind.desc,
        }
        for order, row in ipairs(KIND_ROWS) do
            local kindId, key = kind.id, row.key
            entries[#entries + 1] = {
                key     = kindId .. "_" .. key,
                label   = row.label,
                desc    = row.desc,
                type    = "toggle",
                section = kindId,
                order   = order,
                disabled = function() return not addon:KindAppliesTo(kindId, key) end,
                get = function() return addon:KindValue(kindId, key) end,
                set = function(_, value)
                    addon:SetKindValue(kindId, key, value)
                    addon:ApplySettings()
                end,
            }
        end
    end
    return entries
end

-- A page of its own rather than six more groups under General. Six kinds
-- times five switches is thirty rows, and thirty rows below the ones that
-- were already there is a page you scroll rather than a page you read.
BazUI:RegisterSettingsSpec("Nameplates-Kinds", {
    intro = "Every plate is sorted into one of these, and each kind can "
        .. "answer for itself. The first one that matches wins, so a mob "
        .. "somebody else has tagged is tapped rather than hostile, and a "
        .. "player is a player rather than an NPC.|n|n"
        .. "A switch left alone follows the General page. Class color is "
        .. "grayed out where the unit has no class and the rare and elite "
        .. "mark where it has no rank.",
    sections = KindSections(),
    entries = KindEntries({}),
})

BazUI:RegisterSettingsSpec("Nameplates", {
    sections = {
        general = { label = "General", order = 1 },
        size    = { label = "Size and Text", order = 2 },
    },
    entries = {
        { key = "showPlate", label = "Nameplates", type = "toggle",
          section = "general", order = 0.4,
          desc = "Whether BazUI draws plates at all. Each kind of unit below can answer this for itself. Which units the game offers a plate for in the first place is its own setting, in Interface Options under Nameplates.",
          get = Bool("showPlate", true), set = Set("showPlate") },
        { key = "showBar", label = "Health bar", type = "toggle",
          section = "general", order = 0.5,
          desc = "Whether a plate has a bar on it at all. With it off a plate is the unit's name and nothing else. Each kind of unit below can answer this for itself.",
          get = Bool("showBar", true), set = Set("showBar") },
        { key = "showName", label = "Name", type = "toggle",
          section = "general", order = 0.6,
          desc = "The unit's name above the bar.",
          get = Bool("showName", true), set = Set("showName") },
        { key = "classColor", label = "Class color on players", type = "toggle",
          section = "general", order = 1,
          desc = "A player's plate takes their class color. Everything else is colored by whether it will attack you: red for hostile, amber for neutral, green for friendly.",
          get = Bool("classColor", true), set = Set("classColor") },
        { key = "showFriendly", label = "Replace friendly plates", type = "toggle",
          section = "general", order = 2,
          desc = "Friendly units get a BazUI plate too. Turn it off to leave them with the game's own. Whether a friendly unit has a plate at all is the game's setting, in Interface Options, not this one.",
          get = Bool("showFriendly", true), set = Set("showFriendly") },
        { key = "targetMark", label = "Mark your target", type = "toggle",
          section = "general", order = 3,
          desc = "A gold border on the plate of whatever you have targeted.",
          get = Bool("targetMark", true), set = Set("targetMark") },

        { key = "width", label = "Width", type = "slider",
          section = "size", order = 1, min = 60, max = 220, step = 2,
          get = Get("width"), set = Set("width") },
        { key = "height", label = "Height", type = "slider",
          section = "size", order = 2, min = 4, max = 24, step = 1,
          get = Get("height"), set = Set("height") },
        { key = "showLevel", label = "Show level", type = "toggle",
          section = "size", order = 3,
          desc = "The unit's level, on the right of the bar. Two question marks mean it is far enough above you that the number stopped being the point.",
          get = Bool("showLevel", true), set = Set("showLevel") },
        { key = "showRank", label = "Mark rares and elites", type = "toggle",
          section = "size", order = 3.5,
          desc = "The unit's rank beside its level: Elite reads 62+, a rare elite 62 Rare+, a world boss ?? Boss. Ordinary mobs are left unmarked. With the level switched off the rank is spelled out on its own.",
          get = Bool("showRank", true), set = Set("showRank") },
        { key = "nameSize", label = "Name size", type = "slider",
          section = "size", order = 4, min = 6, max = 18, step = 1,
          get = Get("nameSize"), set = Set("nameSize") },

        { key = "help", type = "note", section = "size", order = 9, style = "info",
          text = "How many plates you see, how far away, and whether "
              .. "friendly units get one at all are the game's own "
              .. "settings rather than this module's. They live in "
              .. "Interface Options under Names." },
        { key = "kindsHelp", type = "note", section = "general", order = 9, style = "info",
          text = "These are the answer for any kind of unit that has not "
              .. "been given its own. The Unit Kinds page beside this one "
              .. "has a group per kind - friendly players, friendly NPCs, "
              .. "hostile NPCs and the rest - and each can override them, "
              .. "so you can have a health bar on other players and "
              .. "nothing but a name on the city guards. Level and the "
              .. "rare and elite mark are on that page too." },
    },
})

BazUI:QueueForModule("Nameplates", function()
    BazUI:RegisterOptionsTable("Nameplates", function()
        return { name = "Nameplates", type = "group", args = {} }
    end)
    BazUI:AddToSettings("Nameplates", "Nameplates")

    BazUI:RegisterOptionsTable("Nameplates-Settings", function()
        return BazUI:BuildOptionsTableFromSpec("Nameplates", { name = "Nameplates" })
    end)
    BazUI:AddToSettings("Nameplates-Settings", "General Settings", "Nameplates", 10)

    BazUI:RegisterOptionsTable("Nameplates-Kinds", function()
        return BazUI:BuildOptionsTableFromSpec("Nameplates-Kinds", { name = "Unit Kinds" })
    end)
    BazUI:AddToSettings("Nameplates-Kinds", "Unit Kinds", "Nameplates", 20)
end)
