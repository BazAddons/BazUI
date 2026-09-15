-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Unit Frames: the module's page
--
-- Short on purpose. Everything about a particular bar belongs to that
-- bar and is edited on the Bars page or by selecting it in Edit Mode;
-- what is left here is the handful of choices that are true of every
-- bar at once.
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

BazUI:RegisterSettingsSpec("UnitFrames", {
    sections = { bars = { label = "Bars", order = 1 } },
    entries = {
        { key = "unitTooltips", label = "Tooltip on hover", type = "toggle",
          section = "bars", order = 1,
          desc = "Hovering a health or power bar shows that unit's tooltip.",
          get = Get("unitTooltips"), set = Set("unitTooltips") },
        { key = "classColor", label = "Class color on player health", type = "toggle",
          section = "bars", order = 2,
          desc = "Health bars for players take the class colour instead of green.",
          get = Get("classColor"), set = Set("classColor") },
        { key = "rangeFade", label = "Fade units out of range", type = "toggle",
          section = "bars", order = 3,
          desc = "A party member you cannot reach fades, so you know before you start casting. The game only answers this for people in your group, so nothing else is affected.",
          get = function() return addon:GetSetting("rangeFade") ~= false end,
          set = function(_, value)
              addon:SetSetting("rangeFade", value and true or false)
              addon.UnitBars:CheckRange()
          end },
        { key = "rangeAlpha", label = "Faded opacity", type = "slider",
          section = "bars", order = 4,
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
        { key = "preview", label = "Preview bars for absent units", type = "execute",
          section = "bars", order = 5,
          desc = "Party and target bars are hidden when there is nobody in them. This shows them as placeholders so they can be moved and docked while you are alone. Also /bazframes preview.",
          hidden = function()
              local bars = addon.UnitBars
              return not bars or bars:PreviewWanted()
          end,
          disabled = InCombatLockdown,
          func = function() addon.UnitBars:SetPreviewWanted(true) end },
        { key = "previewOff", label = "Stop previewing", type = "execute",
          section = "bars", order = 5,
          desc = "Hide the placeholder bars again.",
          hidden = function()
              local bars = addon.UnitBars
              return not bars or not bars:PreviewWanted()
          end,
          disabled = InCombatLockdown,
          func = function() addon.UnitBars:SetPreviewWanted(false) end },
        { key = "help", type = "note", section = "bars", order = 6, style = "info",
          text = "Bars are made and arranged on the Bars page, or in Edit Mode: "
              .. "drag one near the edge of an action bar or another bar to dock "
              .. "it there. Whatever you make a bar for replaces the game's own "
              .. "version of it, so deleting your last player health bar brings "
              .. "the stock player frame back." },
    },
})

BazUI:QueueForLogin(function()
    BazUI:RegisterOptionsTable("UnitFrames", function()
        return BazUI:BuildOptionsTableFromSpec("UnitFrames", { name = "Unit Frames" })
    end)
    BazUI:AddToSettings("UnitFrames", "Unit Frames")

    -- The bars you have made, each with its own form. A page rather than
    -- a section, because the list can be any length.
    BazUI:RegisterOptionsTable("UnitFrames-Bars", function()
        return addon.BarOptions:Build()
    end)
    BazUI:AddToSettings("UnitFrames-Bars", "Bars", "UnitFrames")
end)
