-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Micro Menu: settings
--
-- One spec feeds both the Options panel (Options > AddOns > BazUI >
-- Micro Menu) and the BazUI Edit Mode popup for the bar.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("MicroMenu")
local MODULE_NAME = addon.MODULE_NAME
local both = { options = true, editMode = true }

local function Get(key)
    return function() return addon:GetSetting(key) end
end

local function Set(key)
    return function(_, value)
        addon:SetSetting(key, value)
        addon:ApplySettings()
    end
end

local function GetBool(key)
    return function() return addon:GetSetting(key) ~= false end
end

local function SetBool(key)
    return function(_, value)
        addon:SetSetting(key, value and true or false)
        addon:ApplySettings()
    end
end

local entries = {
    { key = "intro", type = "note", section = "general", order = 0, style = "info",
      text = "Blizzard's micro buttons on a movable BazUI bar, drawn as round ring-framed icons. They are still Blizzard's buttons, so tooltips, the talent reminder and keybinds work as before. Move the bar in BazUI Edit Mode." },
    { key = "enabled", label = "Show the BazUI micro menu", type = "toggle", section = "general", order = 1,
      get = GetBool("enabled"), set = SetBool("enabled") },
    { key = "hideBlizzard", label = "Hide Blizzard's micro menu", type = "toggle", section = "general", order = 2,
      desc = "Park the stock micro menu container in the bottom right. Its buttons live on the BazUI bar either way.",
      get = GetBool("hideBlizzard"), set = SetBool("hideBlizzard") },

    { key = "orientation", label = "Orientation", type = "select", section = "layout", order = 1, surfaces = both,
      values = { horizontal = "Horizontal", vertical = "Vertical" }, get = Get("orientation"), set = Set("orientation") },
    { key = "buttonSize", label = "Button size", type = "slider", section = "layout", order = 2, surfaces = both,
      min = 22, max = 44, step = 1, get = Get("buttonSize"), set = Set("buttonSize") },
    { key = "spacing", label = "Spacing", type = "slider", section = "layout", order = 3, surfaces = both,
      min = 0, max = 16, step = 1, get = Get("spacing"), set = Set("spacing") },
    { key = "mouseoverFade", label = "Show only on mouseover", type = "toggle", section = "layout", order = 4, surfaces = both,
      desc = "Fade the bar out until the cursor is over it. The bar stays visible while Edit Mode is open.",
      get = function() return addon:GetSetting("mouseoverFade") and true or false end, set = SetBool("mouseoverFade") },
    { key = "fadeAlpha", label = "Faded opacity", type = "slider", section = "layout", order = 5, surfaces = both,
      desc = "How visible the bar stays when faded, in percent. 0 hides it completely; hover the spot to bring it back.",
      min = 0, max = 90, step = 5, get = function() return addon:GetSetting("fadeAlpha") or 0 end, set = Set("fadeAlpha") },
    { key = "resetPosition", label = "Reset position", type = "execute", section = "layout", order = 6,
      func = function() addon:ResetPosition() end },
}

-- One toggle per button, in bar order.
for i, def in ipairs(addon.DEFS) do
    entries[#entries + 1] = {
        key = "btn_" .. def.key, label = def.label, type = "toggle", section = "buttons", order = i,
        get = function()
            local prefs = addon:GetSetting("buttons")
            return not prefs or prefs[def.key] ~= false
        end,
        set = function(_, value)
            local prefs = addon:GetSetting("buttons") or {}
            prefs[def.key] = value and true or false
            addon:SetSetting("buttons", prefs)
            addon:ApplySettings()
        end,
    }
end

BazUI:RegisterSettingsSpec(MODULE_NAME, {
    sections = {
        general = { label = "Micro Menu", order = 1 },
        layout  = { label = "Layout",     order = 2 },
        buttons = { label = "Buttons",    order = 3 },
    },
    entries = entries,
})

local function GetLandingPage()
    return BazUI:CreateLandingPage(MODULE_NAME, {
        subtitle    = "Blizzard's micro buttons, BazUI style",
        description = "The Character, Spellbook, Talents, Quest Log, Social, Guild, World Map, Game Menu and Help " ..
            "buttons on a movable bar, drawn as round ring-framed icons that match the rest of BazUI.",
        features = "Still Blizzard's own buttons, so tooltips, keybinds and the talent reminder keep working. " ..
            "Horizontal or vertical. Show or hide each button. Player portrait on the Character button.",
        guide = {
            { "/bazmicro",       "Open these settings" },
            { "BazUI Edit Mode", "Drag the bar; size and spacing are in its popup too" },
            { "/bazmicro reset", "Move the bar back to the top centre" },
        },
    })
end

BazUI:QueueForLogin(function()
    BazUI:RegisterOptionsTable(MODULE_NAME, GetLandingPage)
    BazUI:AddToSettings(MODULE_NAME, "Micro Menu")

    BazUI:RegisterOptionsTable(MODULE_NAME .. "-Settings", function()
        return BazUI:BuildOptionsTableFromSpec(MODULE_NAME, { name = "General Settings" })
    end)
    BazUI:AddToSettings(MODULE_NAME .. "-Settings", "General Settings", MODULE_NAME)
end)
