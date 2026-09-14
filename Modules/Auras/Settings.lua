-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Auras: settings page
--
-- One spec feeds the Options panel (Options > AddOns > BazUI > Auras).
-- Every change re-applies live; anything that touches the secure
-- headers waits for combat to end.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("Auras")
local MODULE_NAME = addon.MODULE_NAME

local function Get(key)
    return function() return addon:GetSetting(key) end
end

local function Set(key)
    return function(_, value)
        addon:SetSetting(key, value)
        addon:ApplySettings()
    end
end

-- Toggles default to true, so nil reads as on.
local function GetBool(key)
    return function() return addon:GetSetting(key) ~= false end
end

local function SetBool(key)
    return function(_, value)
        addon:SetSetting(key, value and true or false)
        addon:ApplySettings()
    end
end

BazUI:RegisterSettingsSpec(MODULE_NAME, {
    sections = {
        general = { label = "Auras",   order = 1 },
        layout  = { label = "Layout",  order = 2 },
        icons   = { label = "Icons",   order = 3 },
        sorting = { label = "Sorting", order = 4 },
    },
    entries = {
        { key = "intro", type = "note", section = "general", order = 0, style = "info",
          text = "Your buffs sit above the health bar of the BazUI player frame and your debuffs above the power bar, eight to a row, with more rows stacking upward as needed. Right-click an icon to cancel that buff. Changes apply live; layout changes made in combat apply when it ends." },
        { key = "enabled", label = "Show BazUI auras", type = "toggle", section = "general", order = 1,
          desc = "Draw your buffs and debuffs on the player frame.",
          get = GetBool("enabled"), set = SetBool("enabled") },
        { key = "hideBlizzard", label = "Hide Blizzard's buff and debuff frames", type = "toggle", section = "general", order = 2,
          desc = "Park the stock frames by the minimap while BazUI auras are shown. Turn off to keep both.",
          get = GetBool("hideBlizzard"), set = SetBool("hideBlizzard") },

        { key = "perRow", label = "Icons per row", type = "slider", section = "layout", order = 1,
          min = 4, max = 16, step = 1, get = Get("perRow"), set = Set("perRow") },
        { key = "iconSize", label = "Icon size", type = "slider", section = "layout", order = 2,
          min = 16, max = 40, step = 1, get = Get("iconSize"), set = Set("iconSize") },
        { key = "spacing", label = "Spacing", type = "slider", section = "layout", order = 3,
          desc = "Pixels between icons, and between rows.",
          min = 0, max = 10, step = 1, get = Get("spacing"), set = Set("spacing") },
        { key = "gap", label = "Distance above the bars", type = "slider", section = "layout", order = 4,
          min = 0, max = 40, step = 1, get = Get("gap"), set = Set("gap") },
        { key = "growth", label = "Fill direction", type = "select", section = "layout", order = 5,
          desc = "Where the first icon goes on each side. Later icons continue away from it, and new rows stack upward.",
          values = { portrait = "From the portrait outward", edge = "From the outer end inward" },
          get = Get("growth"), set = Set("growth") },
        { key = "reset", label = "Reset layout", type = "execute", section = "layout", order = 6,
          func = function() addon:ResetLayout() end },

        { key = "showDuration", label = "Time remaining on icons", type = "toggle", section = "icons", order = 1,
          get = GetBool("showDuration"), set = SetBool("showDuration") },
        { key = "showCount", label = "Stack counts", type = "toggle", section = "icons", order = 2,
          get = GetBool("showCount"), set = SetBool("showCount") },
        { key = "debuffBorders", label = "Colour debuff rims by type", type = "toggle", section = "icons", order = 3,
          desc = "Blue for Magic, purple for Curse, brown for Disease, green for Poison, red for everything else. Off keeps every debuff rim red.",
          get = GetBool("debuffBorders"), set = SetBool("debuffBorders") },
        { key = "showWeapons", label = "Weapon enchants with the buffs", type = "toggle", section = "icons", order = 4,
          desc = "Show poisons, sharpening stones and other temporary weapon enchants as buff icons. Right-click removes them.",
          get = GetBool("showWeapons"), set = SetBool("showWeapons") },

        { key = "sortMethod", label = "Sort by", type = "select", section = "sorting", order = 1,
          values = { INDEX = "Order applied", TIME = "Time remaining", NAME = "Name" },
          get = Get("sortMethod"), set = Set("sortMethod") },
        { key = "sortDirection", label = "Direction", type = "select", section = "sorting", order = 2,
          values = { ["+"] = "Ascending", ["-"] = "Descending" },
          get = Get("sortDirection"), set = Set("sortDirection") },
    },
})

BazUI:QueueForLogin(function()
    BazUI:RegisterOptionsTable(MODULE_NAME, function()
        return BazUI:BuildOptionsTableFromSpec(MODULE_NAME, { name = "Auras" })
    end)
    BazUI:AddToSettings(MODULE_NAME, "Auras")
end)
