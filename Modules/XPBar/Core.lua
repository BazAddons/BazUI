-- SPDX-License-Identifier: GPL-2.0-or-later
local addon
addon = BazUI:RegisterModule("XPBar", {
    title = "XP Bar", profiles = true,
    minimap = { label = "XP Bar", icon = "Interface\\Icons\\XP_Icon" },
    defaults = {
        enabled = true, width = 700, height = 18, scale = 1,
        text = "hover", rested = true, ticks = false, hideAtMax = true,
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 8 },
    },
    slash = { "/bazxp" },
    defaultHandler = function() BazUI:OpenOptionsPanel("XPBar") end,
    commands = {
        unlock = { desc = "Move the XP bar", handler = function() addon:SetUnlocked(true) end },
        lock = { desc = "Lock the XP bar", handler = function() addon:SetUnlocked(false) end },
        reset = { desc = "Reset XP bar layout", handler = function() addon:ResetLayout() end },
    },
    onReady = function(self)
        self:Initialize()
        self:OnProfileChanged(function() self:ApplySettings() end)
    end,
})

-- API access is kept here for the eventual Forever client transition.
function addon:ReadProgress()
    local level = UnitLevel("player") or 1
    local maximum = math.max(0, UnitXPMax("player") or 0)
    local current = math.max(0, math.min(maximum, UnitXP("player") or 0))
    local cap = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
    return { level = level, current = current, maximum = maximum,
        rested = math.max(0, GetXPExhaustion() or 0),
        capped = (cap and level >= cap) or maximum == 0,
        resting = IsResting() }
end

function addon:ResetLayout()
    self:SetSetting("width", 700); self:SetSetting("height", 18); self:SetSetting("scale", 1)
    self:SetSetting("position", { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 8 })
    self:ApplySettings()
end
