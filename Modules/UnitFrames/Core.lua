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

-- The set a new profile starts with: the readings almost everyone wants,
-- arranged the way they were before any of this was configurable. Making
-- none would leave a blank screen and no clue where to begin.
local STARTER_BARS = {
    { kind = "health", unit = "player", y = -140 },
    { kind = "power",  unit = "player", y = -164, dockPrevious = true },
    { kind = "cast",   unit = "player", y = -188, dockPrevious = true },
    { kind = "health", unit = "target", y = -140, x = 300 },
    { kind = "power",  unit = "target", y = -164, x = 300, dockPrevious = true },
}

function addon:SeedBars()
    local UnitBars = self.UnitBars
    if #UnitBars:Defs() > 0 then return end

    local previous
    for _, seed in ipairs(STARTER_BARS) do
        local def = UnitBars:Add(seed.kind, seed.unit)
        if def then
            if seed.dockPrevious and previous then
                def.dock = { host = UnitBars:HostID(previous.id), edge = "BOTTOM" }
            else
                def.position = { point = "CENTER", relPoint = "CENTER",
                    x = seed.x or -300, y = seed.y or -140 }
                previous = def
            end
            if not seed.dockPrevious then previous = def end
        end
    end
    UnitBars:Save()
    UnitBars:ApplyAll()
end

function addon:InitializeBars()
    if not self:BarMode() then return end
    if InCombatLockdown() then
        self:On("PLAYER_REGEN_ENABLED", function() self:InitializeBars() end)
        return
    end

    local UnitBars = self.UnitBars
    UnitBars:BuildAll()
    self:SeedBars()
    UnitBars:WatchAll()
    UnitBars:UpdateAll()

    -- Edit Mode may open or close at any time, and the movers are the
    -- only thing it is ever allowed to move.
    self:On("BAZ_EDITMODE_ENTER", function() UnitBars:ShowAllMovers() end)
    self:On("BAZ_EDITMODE_EXIT",  function() UnitBars:ShowAllMovers() end)
    self:On("PLAYER_REGEN_ENABLED", function()
        UnitBars:BuildAll()
        UnitBars:ApplyAll()
        UnitBars:ShowAllMovers()
    end)
end
