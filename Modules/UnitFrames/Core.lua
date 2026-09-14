-- SPDX-License-Identifier: GPL-2.0-or-later
local addon
addon = BazUI:RegisterModule("UnitFrames", {
    title = "Unit Frames",
    icon = "Interface\\Icons\\INV_Misc_Head_Human_01",
    minimap = { label = "Unit Frames", icon = "Interface\\Icons\\INV_Misc_Head_Human_01" },
    profiles = true,
    defaults = {
        enabled = true,
        scale = 1,
        -- The bar redesign. On means the unit is drawn as bars
        -- that dock; off falls back to the artwork frames until
        -- those are retired.
        barMode = true,
        barWidth = 240,
        barHeight = 20,
        barText = "always",
        healthText = "namePercent",
        powerText = "current",
        unitTooltips = true,
        playerBarPos = { point = "CENTER", relPoint = "CENTER", x = -260, y = -160 },
        targetBarPos = { point = "CENTER", relPoint = "CENTER", x = 260, y = -160 },
        portraitStyle = "3d",
        modelLayer = "above",
        modelScale = 1,
        modelX = 0,
        modelY = 0,
        modelDistance = 0.7,
        showValues = true,
        classColor = false,
        castEnabled = true,
        castOpacity = 0.55,
        castSwirl = 0.75,
        castColor = "gold",
        castText = true,
        position = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 170 },
        targetEnabled = true,
        targetScale = 1,
        targetPortraitStyle = "3d",
        targetModelLayer = "below",
        targetModelScale = 1,
        targetModelX = 0,
        targetModelY = -5,
        targetModelDistance = 0.98,
        targetShowValues = true,
        targetClassColor = false,
        targetPosition = { point = "TOP", relPoint = "TOP", x = 0, y = -30 },
    },
    slash = { "/bazplayer", "/bazframes" },
    defaultHandler = function() BazUI:OpenOptionsPanel("UnitFrames") end,
    commands = {
        portraitinfo = { desc = "Print player portrait placement", handler = function() addon:PrintPortraitPlacement() end },
        targetportraitinfo = { desc = "Print target portrait placement", handler = function() addon.Target:PrintPortraitPlacement() end },
        reset = { desc = "Reset player frame position and scale", handler = function() addon:ResetLayout() end },
        unlock = { desc = "Drag the player frame outside combat", handler = function() addon:SetUnlocked(true) end },
        lock = { desc = "Finish moving the player frame", handler = function() addon:SetUnlocked(false) end },
        targetunlock = { desc = "Move the target frame", handler = function() addon.Target:SetUnlocked(true) end },
        targetlock = { desc = "Lock the target frame", handler = function() addon.Target:SetUnlocked(false) end },
        targetreset = { desc = "Reset the target frame", handler = function() addon.Target:ResetLayout() end },
    },
    onReady = function(self)
        self:Initialize()
        self.Target:Initialize()
        self:InitializeBars()
        self:OnProfileChanged(function() self:ApplySettings(); self.Target:ApplySettings() end)
    end,
})

addon.ASSETS = "Interface\\AddOns\\BazUI\\Modules\\UnitFrames\\Assets\\"

function addon:ResetLayout()
    self:SetSetting("scale", 1)
    self:SetSetting("position", { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 170 })
    self:ApplySettings()
end

---------------------------------------------------------------------------
-- The bar redesign
--
-- Builds the player's readings as docked bars. The artwork frames stand
-- down while this is on; they are still here only until step six of
-- REDESIGN.md retires them.
---------------------------------------------------------------------------

function addon:BarMode()
    return self:GetSetting("barMode") ~= false
end

function addon:InitializeBars()
    if not self:BarMode() then return end
    if InCombatLockdown() then
        self:On("PLAYER_REGEN_ENABLED", function() self:InitializeBars() end)
        return
    end

    local UnitBars = self.UnitBars
    local set = UnitBars:Create("player")
    if not set then return end
    UnitBars:Watch("player")

    -- Floating for now: the dock's other hosts, the action bars, get
    -- their handles in the next step.
    UnitBars:CreateMover("player")
    UnitBars:ApplySettings("player")
    UnitBars:SyncCast("player")

    -- Edit Mode may open or close at any time, and the mover is the only
    -- thing it is ever allowed to move.
    self:On("BAZ_EDITMODE_ENTER", function() UnitBars:ShowMover("player") end)
    self:On("BAZ_EDITMODE_EXIT",  function() UnitBars:ShowMover("player") end)
    self:On("PLAYER_REGEN_ENABLED", function()
        UnitBars:ApplySettings("player")
        UnitBars:ShowMover("player")
    end)
end
