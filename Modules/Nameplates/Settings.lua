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

BazUI:RegisterSettingsSpec("Nameplates", {
    sections = {
        general = { label = "General", order = 1 },
        size    = { label = "Size and Text", order = 2 },
    },
    entries = {
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
        { key = "nameSize", label = "Name size", type = "slider",
          section = "size", order = 4, min = 6, max = 18, step = 1,
          get = Get("nameSize"), set = Set("nameSize") },

        { key = "help", type = "note", section = "size", order = 9, style = "info",
          text = "How many plates you see, how far away, and whether "
              .. "friendly units get one at all are the game's own "
              .. "settings rather than this module's. They live in "
              .. "Interface Options under Names." },
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
    BazUI:AddToSettings("Nameplates-Settings", "General Settings", "Nameplates")
end)
