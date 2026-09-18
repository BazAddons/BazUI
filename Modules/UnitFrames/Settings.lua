-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Unit Frames: the module's page
--
-- Short on purpose. Everything about a particular bar belongs to that
-- bar and is edited on the Bars page or by selecting it in Edit Mode;
-- what is left here is the handful of choices that are true of every
-- bar at once, and the switches for the game's own frames.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("UnitFrames")

local function Get(key) return function() return addon:GetSetting(key) end end

-- Nothing here changes a bar's shape, so re-reading each bar's values is
-- enough; Apply would rebuild layout that has not moved.
local function Set(key)
    return function(_, value)
        addon:SetSetting(key, value)
        local UnitBars = addon.UnitBars
        if UnitBars then UnitBars:UpdateAll() end
    end
end

---------------------------------------------------------------------------
-- The switches for Blizzard's own frames, built from the one list that
-- says which frames the module can put away. Adding a frame there adds
-- its switch here; there is no second list to keep in step.
---------------------------------------------------------------------------

local function StockEntries()
    local UnitBars = addon and addon.UnitBars
    local entries = {}
    for index, stock in ipairs(UnitBars and UnitBars.STOCK or {}) do
        entries[#entries + 1] = {
            key = stock.key, label = stock.label, type = "toggle",
            section = "blizzard", order = index,
            desc = stock.desc,
            get = function() return UnitBars:StockHidden(stock) end,
            -- Parking a frame is protected, so a switch thrown mid-fight
            -- is answered when the fight ends: the module already asks
            -- again on PLAYER_REGEN_ENABLED.
            set = function(_, value)
                addon:SetSetting(stock.key, value and true or false)
                UnitBars:SuppressStock()
            end,
        }
    end
    return entries
end

local SPEC = {
    sections = {
        general  = { label = "General", order = 1 },
        blizzard = { label = "Blizzard's Frames", order = 2 },
    },
    entries = {
        { key = "preview", label = "Preview units that are not there", type = "toggle",
          section = "general", order = 1,
          desc = "Party and target bars are hidden when there is nobody in them. This shows them as placeholders, so a party layout can be built and docked while you are standing alone. Edit Mode does it on its own; this is for the rest of the time. It lasts until you reload. Also /bazframes preview.",
          disabled = InCombatLockdown,
          get = function()
              local bars = addon.UnitBars
              return bars and bars:PreviewWanted() or false
          end,
          set = function(_, value)
              addon.UnitBars:SetPreviewWanted(value and true or false)
          end },
        { key = "unitTooltips", label = "Tooltip on hover", type = "toggle",
          section = "general", order = 2,
          desc = "Hovering a health or power bar shows that unit's tooltip.",
          get = Get("unitTooltips"), set = Set("unitTooltips") },
        { key = "classColor", label = "Class color on player health", type = "toggle",
          section = "general", order = 3,
          desc = "Health bars for players take the class color instead of green.",
          get = Get("classColor"), set = Set("classColor") },
        { key = "rankNote", type = "note", section = "general", order = 3.05,
          style = "info",
          text = "The game ranks its NPCs and puts a dragon around the "
              .. "portrait to say which is which. These bars have no "
              .. "portrait, so the rank is marked on the bar itself - three "
              .. "ways, any or all of them. Ordinary mobs are never marked, "
              .. "which is what makes a marked one worth a second look." },
        { key = "rankGlow", label = "Glow around rares and elites", type = "toggle",
          section = "general", order = 3.1,
          desc = "A halo around the health bar colored by rank: blue for rare, gold for elite, purple for rare elite, red for a world boss. The colors are yours to change on the Skin page, under Unit ranks.",
          get = function() return addon:GetSetting("rankGlow") ~= false end,
          set = function(_, value)
              addon:SetSetting("rankGlow", value and true or false)
              addon.UnitBars:UpdateAll()
          end },
        { key = "rankIcon", label = "Icon in front of the name", type = "toggle",
          section = "general", order = 3.2,
          desc = "A small mark before the unit's name. Drawn in the bar's own text, so it grows and shrinks with the text rather than needing a size of its own.",
          get = function() return addon:GetSetting("rankIcon") ~= false end,
          set = function(_, value)
              addon:SetSetting("rankIcon", value and true or false)
              addon.UnitBars:UpdateAll()
          end },
        { key = "restIcon", label = "Resting mark", type = "toggle",
          section = "general", order = 3.4,
          desc = "The game's animated zZ, on your own health bar, while you are somewhere that rests you. The mark is the game's own art; where the client has no such art, the setting does nothing.",
          get = function() return addon:GetSetting("restIcon") ~= false end,
          set = function(_, value)
              addon:SetSetting("restIcon", value and true or false)
              addon.UnitBars:UpdateAll()
          end },
        { key = "rankWord", label = "Rank written beside the name", type = "toggle",
          section = "general", order = 3.3,
          desc = "Rare, Elite, Rare Elite or Boss, spelled out after the name. The plainest of the three, and the one that costs the name the most room.",
          get = function() return addon:GetSetting("rankWord") == true end,
          set = function(_, value)
              addon:SetSetting("rankWord", value and true or false)
              addon.UnitBars:UpdateAll()
          end },
        { key = "showLevel", label = "Show the unit's level", type = "toggle",
          section = "general", order = 3.4,
          desc = "The level beside the name. With the rank written out too it joins on: a rare elite reads 62 Rare+ rather than Rare Elite. Two question marks mean the game will not put a number on it, which is its way of saying it is far enough above you that the number stopped being the point.",
          get = function() return addon:GetSetting("showLevel") == true end,
          set = function(_, value)
              addon:SetSetting("showLevel", value and true or false)
              addon.UnitBars:UpdateAll()
          end },
        { key = "barClicks", label = "Clicking a bar opens what it shows", type = "toggle",
          section = "general", order = 3.5,
          desc = "The reputation bar opens the reputation panel, and the experience bar opens the character panel. Bars with nothing to open ignore the mouse entirely, so they stay click-through - turn this off and these two do as well.",
          get = function() return addon:GetSetting("barClicks") ~= false end,
          set = function(_, value)
              addon:SetSetting("barClicks", value and true or false)
              addon.UnitBars:ApplyAll()
          end },
        { key = "rangeFade", label = "Fade units out of range", type = "toggle",
          section = "general", order = 4,
          desc = "A party member you cannot reach fades, so you know before you start casting. The game only answers this for people in your group, so nothing else is affected.",
          get = function() return addon:GetSetting("rangeFade") ~= false end,
          set = function(_, value)
              addon:SetSetting("rangeFade", value and true or false)
              addon.UnitBars:CheckRange()
          end },
        { key = "rangeAlpha", label = "Faded opacity", type = "slider",
          section = "general", order = 5,
          min = 0.1, max = 1, step = 0.05, format = "percent",
          hidden = function() return addon:GetSetting("rangeFade") == false end,
          get = function() return addon:GetSetting("rangeAlpha") or 0.45 end,
          set = function(_, value)
              addon:SetSetting("rangeAlpha", value)
              -- Every faded bar has to be told again; nothing about the
              -- unit changed, only what faded means.
              for _, bar in pairs(addon.UnitBars.bars) do bar._outOfRange = nil end
              addon.UnitBars:CheckRange()
          end },
        { key = "help", type = "note", section = "general", order = 6, style = "info",
          text = "Bars are made and arranged on the Bars page, or in Edit Mode: "
              .. "drag one near the edge of an action bar or another bar to dock "
              .. "it there." },
        { key = "stockHelp", type = "note", section = "blizzard", order = 90, style = "info",
          text = "Nothing replaces these but the bars you make. Turning one off "
              .. "hides the game's frame whether or not you have made a bar to "
              .. "take its place, so party frames are best turned off once your "
              .. "party bars exist." },
    },
}

for _, entry in ipairs(StockEntries()) do
    SPEC.entries[#SPEC.entries + 1] = entry
end

BazUI:RegisterSettingsSpec("UnitFrames", SPEC)

BazUI:QueueForModule("UnitFrames", function()
    -- The module's node holds nothing itself; its pages are its tabs.
    -- Putting the settings on the node instead leaves one child page, and
    -- one page is no tab strip at all: the strip hides and that single
    -- child takes the whole canvas, which is how the settings ended up
    -- unreachable behind the bar editor.
    BazUI:RegisterOptionsTable("UnitFrames", function()
        return { name = "Unit Frames", type = "group", args = {} }
    end)
    BazUI:AddToSettings("UnitFrames", "Unit Frames")

    BazUI:RegisterOptionsTable("UnitFrames-Settings", function()
        return BazUI:BuildOptionsTableFromSpec("UnitFrames", { name = "Unit Frames" })
    end)
    BazUI:AddToSettings("UnitFrames-Settings", "General Settings", "UnitFrames")

    -- The bars you have made, each with its own form. A page rather than
    -- a section, because the list can be any length.
    BazUI:RegisterOptionsTable("UnitFrames-Bars", function()
        return addon.BarOptions:Build()
    end)
    BazUI:AddToSettings("UnitFrames-Bars", "Bars", "UnitFrames")
end)
