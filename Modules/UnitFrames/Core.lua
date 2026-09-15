-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Unit Frames
--
-- A unit is drawn as bars you make yourself: health, power, casting,
-- experience and reputation, each one floating or docked to an action
-- bar or to another bar. There is no portrait and no frame around it,
-- which is exactly what lets any of them dock to anything else.
--
-- Almost nothing is configured here as a result. What a bar reads, how
-- wide it is, where it sits and what its text says are properties of
-- that bar and are kept on it; this page holds only the few things that
-- are true of all of them.
--
-- See REDESIGN.md for how this replaced the artwork frames.
---------------------------------------------------------------------------

local addon
addon = BazUI:RegisterModule("UnitFrames", {
    title = "Unit Frames",
    icon = "Interface\\Icons\\INV_Misc_Head_Human_01",
    minimap = { label = "Unit Frames", icon = "Interface\\Icons\\INV_Misc_Head_Human_01" },
    profiles = true,
    defaults = {
        classColor   = false,
        unitTooltips = true,
        -- Fading someone you cannot reach, and how far to fade them.
        rangeFade    = true,
        rangeAlpha   = 0.45,
    },
    slash = { "/bazframes", "/bazplayer" },
    defaultHandler = function() BazUI:OpenOptionsPanel("UnitFrames") end,
    commands = {
        preview = {
            desc = "Show bars for units that are not there, to arrange them",
            handler = function()
                local UnitBars = addon.UnitBars
                if InCombatLockdown() then
                    addon:Print("Preview the bars after combat ends.")
                    return
                end
                UnitBars:SetPreviewWanted(not UnitBars:PreviewWanted())
                addon:Print(UnitBars:PreviewWanted()
                    and "Previewing bars for absent units."
                    or "Preview off.")
            end,
        },
    },
    onReady = function(self)
        self:InitializeBars()
        self:OnProfileChanged(function() self:ApplySettings() end)
    end,
})

-- Everything the module owns, applied again from what is saved. Named
-- ApplySettings because that is what the suite calls on a profile
-- change, and safe to call twice: every bar is laid out from its own
-- definition rather than from wherever it happens to be.
function addon:ApplySettings()
    local UnitBars = self.UnitBars
    if not UnitBars then return end
    UnitBars:ApplyAll()
    UnitBars:UpdateAll()
    UnitBars:SuppressStock()
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
    if InCombatLockdown() then
        self:On("PLAYER_REGEN_ENABLED", function() self:InitializeBars() end)
        return
    end

    local UnitBars = self.UnitBars
    UnitBars:RegisterCreator()
    UnitBars:RegisterCopyMenu()
    UnitBars:BuildAll()
    self:SeedBars()
    UnitBars:WatchAll()
    UnitBars:UpdateAll()
    -- Your bars replace the game's own, so the game's go away.
    UnitBars:SuppressStock()

    -- Edit Mode may open or close at any time, and the movers are the
    -- only thing it is ever allowed to move.
    self:On("BAZ_EDITMODE_ENTER", function()
        UnitBars:RefreshEditSettings()
        -- Bars for absent units turn up while arranging, so a party
        -- layout can be built without a party.
        UnitBars:RefreshPreview()
        UnitBars:ShowAllMovers()
    end)
    self:On("BAZ_EDITMODE_EXIT",  function()
        UnitBars:RefreshPreview()
        UnitBars:ShowAllMovers()
    end)
    self:On("PLAYER_REGEN_ENABLED", function()
        UnitBars:BuildAll()
        UnitBars:ApplyAll()
        -- Showing and hiding these is protected, so whatever the preview
        -- should have been while the fight ran, it is now.
        UnitBars:RefreshPreview()
        UnitBars:ShowAllMovers()
        -- Hiding Blizzard's frames is protected, so anything that
        -- changed mid-fight has been waiting for this.
        UnitBars:SuppressStock()
    end)
end
