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
--
-- Every button either client has, including the ones this one does not.
-- A switch for a button that is not here greys out rather than
-- disappearing, so the list is the same shape wherever you read it and
-- nobody goes looking for a row that moved.
--
-- Greyed on whether this client uses the button, not on whether the frame
-- exists. Both clients define every button either of them has, so the
-- second question answers yes for things that are nowhere on screen - a
-- switch offering to show Achievements on Forever, which has none.
for i, def in ipairs(addon.DEFS) do
    entries[#entries + 1] = {
        key = "btn_" .. def.key, label = def.label, type = "toggle", section = "buttons", order = i,
        desc = "Whether this button is on the bar.",
        disabled = function()
            for _, listed in ipairs(addon:Buttons()) do
                if listed.def.key == def.key then return false end
            end
            return true
        end,
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
        general = { label = "",           order = 1 },
        layout  = { label = "Layout",     order = 2 },
        buttons = { label = "Buttons",    order = 3 },
    },
    entries = entries,
})

BazUI:QueueForModule("MicroMenu", function()
    -- The module entry itself never renders: its pages are tabs.
    BazUI:RegisterOptionsTable(MODULE_NAME, function()
        return { name = "Micro Menu", type = "group", args = {} }
    end)
    BazUI:AddToSettings(MODULE_NAME, "Micro Menu")

    BazUI:RegisterOptionsTable(MODULE_NAME .. "-Settings", function()
        return BazUI:BuildOptionsTableFromSpec(MODULE_NAME, { name = "General" })
    end)
    BazUI:AddToSettings(MODULE_NAME .. "-Settings", "General", MODULE_NAME)
end)
