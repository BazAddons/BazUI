-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("XPBar")
local both = { options = true, editMode = true }
local function Get(key) return function() return addon:GetSetting(key) end end
local function Set(key) return function(_, value) addon:SetSetting(key, value); addon:ApplySettings() end end
BazUI:RegisterSettingsSpec("XPBar", {
    sections = { appearance = { label = "Experience Bar", order = 1 }, layout = { label = "Size and Position", order = 2 } },
    entries = {
        { key = "enabled", label = "Replace the stock XP bar", type = "toggle", section = "appearance", order = 1, get = Get("enabled"), set = Set("enabled") },
        { key = "text", label = "Progress text", type = "select", section = "appearance", order = 2, surfaces = both,
          values = { always = "Always", hover = "On Hover", never = "Never" }, get = Get("text"), set = Set("text") },
        { key = "rested", label = "Show rested XP ahead of progress", type = "toggle", section = "appearance", order = 3, surfaces = both, get = Get("rested"), set = Set("rested") },
        { key = "ticks", label = "Subtle 10% markers", type = "toggle", section = "appearance", order = 4, surfaces = both, get = Get("ticks"), set = Set("ticks") },
        { key = "hideAtMax", label = "Hide at maximum level", type = "toggle", section = "appearance", order = 5, get = Get("hideAtMax"), set = Set("hideAtMax") },
        { key = "width", label = "Width", type = "slider", section = "layout", order = 1, min = 240, max = 1800, step = 10, surfaces = both, get = Get("width"), set = Set("width") },
        { key = "height", label = "Height", type = "slider", section = "layout", order = 2, min = 12, max = 32, step = 1, surfaces = both, get = Get("height"), set = Set("height") },
        { key = "scale", label = "Scale", type = "slider", section = "layout", order = 3, min = 0.5, max = 2, step = 0.05, format = "percent", surfaces = both, get = Get("scale"), set = Set("scale") },
        { key = "unlock", label = "Unlock bar", type = "execute", section = "layout", order = 4, disabled = InCombatLockdown, func = function() addon:SetUnlocked(true) end },
        { key = "lock", label = "Lock bar", type = "execute", section = "layout", order = 5, func = function() addon:SetUnlocked(false) end },
        { key = "reset", label = "Reset size and position", type = "execute", section = "layout", order = 6, func = function() addon:ResetLayout() end },
        { key = "nudge", label = "Position", type = "nudge", section = "layout", surfaces = { editMode = true } },
        { key = "help", type = "note", section = "layout", order = 7, text = "Purple is normal XP; blue indicates rested XP. The muted blue extension previews the available rested bonus up to the end of this level. Hover for exact values, or right-click for options. Move the bar in Edit Mode or unlock it here. Layout changes during combat apply afterward." },
    },
})
BazUI:QueueForLogin(function()
    BazUI:RegisterOptionsTable("XPBar", function() return BazUI:BuildOptionsTableFromSpec("XPBar", { name = "XP Bar" }) end)
    BazUI:AddToSettings("XPBar", "XP Bar")
end)
