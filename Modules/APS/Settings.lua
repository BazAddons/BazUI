-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("APS")
local function Get(key) return function() return addon:GetSetting(key) end end
local function Set(key)
    return function(_, value) addon:SetSetting(key, value); addon:ApplySettings() end
end

BazUI:RegisterSettingsSpec("APS", {
    sections = {
        appearance = { label = "Azeroth Positioning System", order = 1 },
        integrations = { label = "Navigation addons", order = 2 },
    },
    entries = {
        { key = "size", label = "Arrow size", type = "slider", section = "appearance", order = 1,
          min = 48, max = 192, step = 4, get = Get("size"), set = Set("size") },
        { key = "preview", label = "Show or hide preview", type = "execute", section = "appearance", order = 2,
          func = function() addon:TogglePreview() end },
        { key = "tomtom", label = "Use APS for TomTom's arrow", type = "toggle", section = "integrations", order = 1,
          get = Get("tomtom"), set = Set("tomtom") },
        { key = "zygor", label = "Use APS for Zygor's arrow", type = "toggle", section = "integrations", order = 2,
          get = Get("zygor"), set = Set("zygor") },
        { key = "help", type = "note", section = "integrations", order = 3,
          text = "APS works on its own. Use /way [zone or #mapID] x y [name], /wayb, /cway or /ttpaste. Quest tracker circles select a quest destination. Optional TomTom and Zygor targets feed the same APS arrow; their original arrow displays are suppressed. The display is click-through; hold Shift to drag it. Use /aps clear to clear navigation." },
    },
})

BazUI:QueueForModule("APS", function()
    BazUI:RegisterOptionsTable("APS", function() return { name = "APS", type = "group", args = {} } end)
    BazUI:AddToSettings("APS", "APS")
    BazUI:RegisterOptionsTable("APS-General", function()
        return BazUI:BuildOptionsTableFromSpec("APS", { name = "General" })
    end)
    BazUI:AddToSettings("APS-General", "General", "APS")
end)
