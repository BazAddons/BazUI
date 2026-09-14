-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("Tooltip")
local function Get(key) return function() return addon:GetSetting(key) end end
local function Set(key) return function(_, value) addon:SetSetting(key, value); addon:ApplySettings() end end
BazUI:RegisterSettingsSpec("Tooltip", {
    sections = { appearance = { label = "Appearance", order = 1 },
        anchor = { label = "Position", order = 2 }, behavior = { label = "Visibility", order = 3 } },
    entries = {
        { key = "unlock", label = "Unlock anchor", type = "toggle", section = "anchor", order = .1,
          desc = "Show the draggable anchor. Turn off to lock it, or right-click the marker.",
          disabled = function() return not addon:GetSetting("enabled") end,
          get = function() return addon:IsUnlocked() end,
          set = function(_, value) addon:SetUnlocked(value) end },
        { key = "enabled", label = "Enable Tooltip module", type = "toggle", section = "appearance", order = 1, get = Get("enabled"), set = Set("enabled") },
        { key = "skin", label = "Use BazUI tooltip frame", type = "toggle", section = "appearance", order = 2, get = Get("skin"), set = Set("skin") },
        { key = "scale", label = "Tooltip scale", type = "slider", section = "appearance", order = 3, min = .75, max = 1.5, step = .05, format = "percent", get = Get("scale"), set = Set("scale") },
        { key = "opacity", label = "Background opacity", type = "slider", section = "appearance", order = 4, min = .5, max = 1, step = .05, format = "percent", get = Get("opacity"), set = Set("opacity") },
        { key = "anchor", label = "Tooltip anchor", type = "select", section = "anchor", order = 1,
          values = { default = "Default / Drawer dock", cursor = "Follow cursor", fixed = "Fixed screen position" }, get = Get("anchor"), set = Set("anchor") },
        { key = "origin", label = "Tooltip origin", type = "select", section = "anchor", order = 1.5,
          values = { auto = "Original direction", TOPLEFT = "Top left (grows down and right)",
              TOP = "Top (grows down)", TOPRIGHT = "Top right (grows down and left)",
              LEFT = "Left (grows right)", CENTER = "Center", RIGHT = "Right (grows left)",
              BOTTOMLEFT = "Bottom left (grows up and right)", BOTTOM = "Bottom (grows up)",
              BOTTOMRIGHT = "Bottom right (grows up and left)" },
          disabled = function() return addon:GetSetting("anchor") == "default" end,
          get = Get("origin"), set = Set("origin") },
        { key = "point", label = "Anchor screen reference", type = "select", section = "anchor", order = 2,
          values = { BOTTOMRIGHT = "Bottom right", BOTTOMLEFT = "Bottom left", TOPRIGHT = "Top right", TOPLEFT = "Top left" },
          disabled = function() return addon:GetSetting("anchor") ~= "fixed" end, get = Get("point"), set = Set("point") },
        { key = "x", label = "Screen horizontal offset", type = "slider", section = "anchor", order = 3, min = -1000, max = 1000, step = 1,
          disabled = function() return addon:GetSetting("anchor") ~= "fixed" end, get = Get("x"), set = Set("x") },
        { key = "y", label = "Screen vertical offset", type = "slider", section = "anchor", order = 4, min = -700, max = 700, step = 1,
          disabled = function() return addon:GetSetting("anchor") ~= "fixed" end, get = Get("y"), set = Set("y") },
        { key = "cursorX", label = "Cursor horizontal offset", type = "slider", section = "anchor", order = 5, min = -100, max = 100, step = 1,
          disabled = function() return addon:GetSetting("anchor") ~= "cursor" end, get = Get("cursorX"), set = Set("cursorX") },
        { key = "cursorY", label = "Cursor vertical offset", type = "slider", section = "anchor", order = 6, min = -100, max = 100, step = 1,
          disabled = function() return addon:GetSetting("anchor") ~= "cursor" end, get = Get("cursorY"), set = Set("cursorY") },
        { key = "anchorHelp", type = "note", section = "anchor", order = 7,
          text = "Tooltip origin chooses which part of the tooltip meets the marker center (or cursor offset). Changing it leaves the marker in place. Default preserves existing anchors and the Drawers tooltip dock. Cursor and fixed modes override the main hover tooltip; item comparisons stay beside their item. A docked tooltip uses the drawer's fit scale." },
        { key = "hideHealth", label = "Hide unit tooltip health bar", type = "toggle", section = "behavior", order = 1, get = Get("hideHealth"), set = Set("hideHealth") },
        { key = "hideCombat", label = "Hide tooltips during combat", type = "toggle", section = "behavior", order = 2, get = Get("hideCombat"), set = Set("hideCombat") },
        { key = "preview", label = "Preview tooltip for 5 seconds", type = "execute", section = "behavior", order = 3,
          disabled = InCombatLockdown, func = function() addon:Preview() end },
    },
})
BazUI:QueueForLogin(function()
    BazUI:RegisterOptionsTable("Tooltip", function() return { name = "Tooltip", type = "group", args = {} } end)
    BazUI:AddToSettings("Tooltip", "Tooltip")
    BazUI:RegisterOptionsTable("Tooltip-Settings", function()
        return BazUI:BuildOptionsTableFromSpec("Tooltip", { name = "General Settings" })
    end)
    BazUI:AddToSettings("Tooltip-Settings", "General Settings", "Tooltip")
end)
