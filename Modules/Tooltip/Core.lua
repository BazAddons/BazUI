-- SPDX-License-Identifier: GPL-2.0-or-later
local addon
addon = BazUI:RegisterModule("Tooltip", {
    title = "Tooltip", profiles = true,
    minimap = { label = "Tooltip", icon = "Interface\\Icons\\INV_Misc_Note_01" },
    defaults = { enabled = true, skin = true, scale = 1, opacity = .96,
        hideHealth = false, hideCombat = false, anchor = "default", origin = "auto",
        point = "BOTTOMRIGHT", x = -24, y = 100, cursorX = 18, cursorY = 18 },
    slash = { "/baztooltip" },
    defaultHandler = function() BazUI:OpenOptionsPanel("Tooltip") end,
    commands = {
        unlock = { desc = "Drag the tooltip anchor", handler = function() addon:SetUnlocked(true) end },
        lock = { desc = "Lock the tooltip anchor", handler = function() addon:SetUnlocked(false) end },
    },
    onReady = function(self)
        self:Initialize()
        self:OnProfileChanged(function() self:ApplySettings() end)
    end,
})

function addon:OverridesAnchor()
    return self:GetSetting("enabled") and self:GetSetting("anchor") ~= "default"
end
