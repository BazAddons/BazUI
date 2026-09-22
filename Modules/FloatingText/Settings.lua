-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Floating Text: the module's page
---------------------------------------------------------------------------

local addon = BazUI:GetModule("FloatingText")
if not addon then return end

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

BazUI:RegisterSettingsSpec("FloatingText", {
    sections = {
        general  = { label = "General", order = 1 },
        look     = { label = "The numbers", order = 2 },
        colors   = { label = "Colors", order = 3 },
        events   = { label = "What to show", order = 4 },
        merging  = { label = "Merging", order = 5 },
    },
    entries = {
        { key = "enabled", label = "Floating text", type = "toggle",
          section = "general", order = 1,
          desc = "Numbers rising off the fight: what you hit for, what hit you, what you healed."
              .. "\n\nOff by default, because it draws over the middle of the screen and a module that starts doing that unannounced is one people go hunting for the switch to.",
          get = Bool("enabled", false), set = Set("enabled") },

        { key = "hideBlizzard", label = "Turn off the game's own", type = "toggle",
          section = "general", order = 2,
          desc = "The game has floating combat text of its own, and two sets of numbers over one fight is unreadable."
              .. "\n\nThis is the game's setting rather than a frame we hide, so switching this module off puts theirs back exactly as it was.",
          get = Bool("hideBlizzard", true), set = Set("hideBlizzard"),
          disabled = function() return addon:GetSetting("enabled") ~= true end },

        { key = "hideBlizzardWorld", label = "Turn off the game's numbers over the mob", type = "toggle",
          section = "general", order = 2.5,
          desc = "The game also draws its own damage numbers over the mob itself. That is separate from its scrolling text, so turning that off leaves these running - this is the switch for them.",
          get = Bool("hideBlizzardWorld", false), set = Set("hideBlizzardWorld"),
          disabled = function() return addon:GetSetting("enabled") ~= true end },

        { key = "hideBlizzardXP", label = "Turn off the game's experience text", type = "toggle",
          section = "general", order = 2.7,
          desc = "The experience number that floats up when something dies. BazUI's Notifications module already tells you about experience, so this is usually saying it twice.",
          get = Bool("hideBlizzardXP", false), set = Set("hideBlizzardXP") },

        { key = "where", type = "note", section = "general", order = 3,
          text = "There are two areas - |cffffd700Incoming|r on the left and |cffffd700Outgoing|r on the right. Open |cffffd700BazUI Edit Mode|r and they show their bounds so you can drag them where you want; the rest of the time an area is just a space, and only the numbers are visible." },

        { key = "fontSize", label = "Size", type = "slider", section = "look", order = 1,
          min = 10, max = 48, step = 1,
          desc = "An ordinary hit. Crits are drawn larger than this, and a glancing blow smaller.",
          get = Get("fontSize"), set = Set("fontSize") },

        { key = "outline", label = "Outline", type = "select", section = "look", order = 2,
          values = { NONE = "None", OUTLINE = "Thin", THICKOUTLINE = "Thick" },
          desc = "Numbers are drawn over the world rather than over a panel, so an outline is usually what makes them readable against grass.",
          get = Get("outline"), set = Set("outline") },

        { key = "duration", label = "How long they last", type = "slider",
          section = "look", order = 3, min = 0.5, max = 5, step = 0.1,
          desc = "Seconds from appearing to gone. They stay fully solid for most of it and fade at the end - a number that starts fading immediately reads as already over.",
          get = Get("duration"), set = Set("duration") },

        { key = "travel", label = "How far they travel", type = "slider",
          section = "look", order = 4, min = 60, max = 400, step = 10,
          desc = "The height of the area, in pixels, and the distance a number climbs in its lifetime. The two are the same thing on purpose: what you drag in Edit Mode is the space the numbers actually use.",
          get = Get("travel"), set = Set("travel") },

        { key = "critScale", label = "Crit size", type = "slider",
          section = "look", order = 5, min = 1, max = 3, step = 0.1,
          desc = "How much bigger a critical or crushing hit is drawn than an ordinary one. At 1 they are the same size.",
          get = Get("critScale"), set = Set("critScale") },

        { key = "critPrefix", label = "Mark crits with stars", type = "toggle",
          section = "look", order = 6,
          desc = "Draws a crit as *1234* rather than 1234. Size alone tells you it was a crit only if there is an ordinary hit next to it to compare against.",
          get = Bool("critPrefix", true), set = Set("critPrefix") },

        { key = "colorNote", type = "note", section = "colors", order = 0,
          text = "Which way a hit went is the thing a screen full of white numbers cannot tell you, so it is a colour rather than a position. |cffffd700Color by damage school|r below overrides these where a spell has a school - physical does not count as one, so melee keeps the colour set here." },

        { key = "colorOutDamage", label = "Damage you deal", type = "select",
          section = "colors", order = 1,
          values = { white = "White", red = "Red", orange = "Orange", yellow = "Yellow", green = "Green", cyan = "Cyan", blue = "Blue", purple = "Purple", pink = "Pink", grey = "Grey" },
          desc = "Your hits. Yellow by default, so what you are doing reads apart from what is happening to you.",
          get = Get("colorOutDamage"), set = Set("colorOutDamage") },

        { key = "colorInDamage", label = "Damage you take", type = "select",
          section = "colors", order = 2,
          values = { white = "White", red = "Red", orange = "Orange", yellow = "Yellow", green = "Green", cyan = "Cyan", blue = "Blue", purple = "Purple", pink = "Pink", grey = "Grey" },
          desc = "Hits on you. Red by default, which is the one colour nobody has to learn.",
          get = Get("colorInDamage"), set = Set("colorInDamage") },

        { key = "colorOutHeal", label = "Healing you do", type = "select",
          section = "colors", order = 3,
          values = { white = "White", red = "Red", orange = "Orange", yellow = "Yellow", green = "Green", cyan = "Cyan", blue = "Blue", purple = "Purple", pink = "Pink", grey = "Grey" },
          get = Get("colorOutHeal"), set = Set("colorOutHeal") },

        { key = "colorInHeal", label = "Healing you receive", type = "select",
          section = "colors", order = 4,
          values = { white = "White", red = "Red", orange = "Orange", yellow = "Yellow", green = "Green", cyan = "Cyan", blue = "Blue", purple = "Purple", pink = "Pink", grey = "Grey" },
          get = Get("colorInHeal"), set = Set("colorInHeal") },

        { key = "colorEnergize", label = "Mana and energy", type = "select",
          section = "colors", order = 5,
          values = { white = "White", red = "Red", orange = "Orange", yellow = "Yellow", green = "Green", cyan = "Cyan", blue = "Blue", purple = "Purple", pink = "Pink", grey = "Grey" },
          get = Get("colorEnergize"), set = Set("colorEnergize") },

        { key = "colorMiss", label = "Misses and dodges", type = "select",
          section = "colors", order = 6,
          values = { white = "White", red = "Red", orange = "Orange", yellow = "Yellow", green = "Green", cyan = "Cyan", blue = "Blue", purple = "Purple", pink = "Pink", grey = "Grey" },
          get = Get("colorMiss"), set = Set("colorMiss") },

        { key = "scatter", label = "Spread them apart", type = "slider",
          section = "look", order = 8, min = 0, max = 100, step = 5,
          desc = "How far apart two numbers landing at the same instant are nudged, in pixels."
              .. "\n\nAt 0 they form one hard column, which is the tidiest and does mean a simultaneous pair overlaps. Too high and the numbers stop looking like they belong to anything.",
          get = Get("scatter"), set = Set("scatter") },

        { key = "schoolColors", label = "Color by damage school", type = "toggle",
          section = "colors", order = 7,
          desc = "Fire orange, frost blue, shadow purple, nature green, holy gold, arcane pink, physical white - the game's own school colors, the ones the combat log uses."
              .. "\n\nOff draws all damage white.",
          get = Bool("schoolColors", true), set = Set("schoolColors") },

        { key = "showDamage", label = "Damage", type = "toggle",
          section = "events", order = 1,
          get = Bool("showDamage", true), set = Set("showDamage") },

        { key = "showHeals", label = "Healing", type = "toggle",
          section = "events", order = 2,
          get = Bool("showHeals", true), set = Set("showHeals") },

        { key = "showMisses", label = "Misses, dodges and parries", type = "toggle",
          section = "events", order = 3,
          desc = "The words rather than the numbers: Miss, Dodge, Parry, Block, Resist, Immune, Evade. Drawn smaller than a hit, because none of them is the thing you were watching for.",
          get = Bool("showMisses", true), set = Set("showMisses") },

        { key = "showEnergize", label = "Mana and energy returned", type = "toggle",
          section = "events", order = 4,
          desc = "Off by default. On a class that regains something every few seconds this is a second stream of numbers saying what the power bar already says.",
          get = Bool("showEnergize", false), set = Set("showEnergize") },

        { key = "merge", label = "Add up rapid hits", type = "toggle",
          section = "merging", order = 1,
          desc = "A fight is mostly the same mob hitting you four times a second, and six numbers climbing the screen say nothing one number does not."
              .. "\n\nOff by default, because it is a friendly kind of lie: the total is true and the number of hits is gone."
              .. "\n\n|cffffd700Crits are never merged|r - the reason to want one on screen is that it was a crit, and folding it into a total throws away exactly that.",
          get = Bool("merge", false), set = Set("merge") },

        { key = "mergeWindow", label = "Add up over", type = "slider",
          section = "merging", order = 2, min = 0.1, max = 2, step = 0.1,
          desc = "Seconds. Everything landing inside the window is added up, and the total appears when the window closes rather than when it opens - so what you see is the whole of what happened.",
          get = Get("mergeWindow"), set = Set("mergeWindow"),
          disabled = function() return addon:GetSetting("merge") ~= true end },
    },
})

-- Registering the spec only stores it. Something has to turn it into a
-- page and hang that page in the tree, which is what this does - and
-- leaving it out is why the page appeared in the list and rendered
-- empty: the entry existed, the contents were never built.
BazUI:QueueForModule("FloatingText", function()
    BazUI:RegisterOptionsTable("FloatingText", function()
        return BazUI:BuildOptionsTableFromSpec("FloatingText",
            { name = "Floating Text" })
    end)
    BazUI:AddToSettings("FloatingText", "Floating Text")
end)
