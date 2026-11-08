-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("AGN")
local function Get(key) return function() return addon:GetSetting(key) end end
local function Set(key)
    return function(_, value) addon:SetSetting(key, value); addon:ApplySettings() end
end

BazUI:RegisterSettingsSpec("AGN", {
    sections = {
        appearance = { label = "Azeroth Navigation System", order = 1 },
        integrations = { label = "Navigation addons", order = 2 },
    },
    entries = {
        { key = "size", label = "Arrow size", type = "slider", section = "appearance", order = 1,
          min = 48, max = 192, step = 4, get = Get("size"), set = Set("size") },
        { key = "preview", label = "Show or hide preview", type = "execute", section = "appearance", order = 2,
          func = function() addon:TogglePreview() end },
        { key = "tomtom", label = "Use AGN for TomTom's arrow", type = "toggle", section = "integrations", order = 1,
          get = Get("tomtom"), set = Set("tomtom") },
        { key = "zygor", label = "Use AGN for Zygor's arrow", type = "toggle", section = "integrations", order = 2,
          get = Get("zygor"), set = Set("zygor") },
        { key = "help", type = "note", section = "integrations", order = 3,
          text = "AGN works on its own. Use /way [zone or #mapID] x y [name], /wayb, /cway or /ttpaste. Quest tracker circles select a quest destination. Optional TomTom and Zygor targets feed the same AGN arrow; their original arrow displays are suppressed. The display is click-through; hold Shift to drag it. Use /agn clear to clear navigation." },
    },
})

BazUI:QueueForModule("AGN", function()
    BazUI:RegisterOptionsTable("AGN", function() return { name = "AGN", type = "group", args = {} } end)
    BazUI:AddToSettings("AGN", "AGN")
    BazUI:RegisterOptionsTable("AGN-General", function()
        return BazUI:BuildOptionsTableFromSpec("AGN", { name = "General" })
    end)
    BazUI:AddToSettings("AGN-General", "General", "AGN")
end)
