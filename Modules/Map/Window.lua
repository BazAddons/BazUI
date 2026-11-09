-- SPDX-License-Identifier: GPL-2.0-or-later
-- Expand only the native maximized map; its normal window keeps Blizzard's size.
local addon = BazUI:GetModule("Map")
local map, watcher

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function Defer()
    if watcher then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
end

local function ApplyWidth()
    if not map:IsMaximized() then return end
    if InCombat() then Defer(); return end
    if addon:GetSetting("widescreen") == false then return end
    local parent = map:GetParent()
    local width = math.floor(parent:GetWidth() * parent:GetEffectiveScale() / map:GetEffectiveScale() - 30)
    if width > 0 and math.abs(map:GetWidth() - width) > 0.5 then
        map:SetWidth(width)
        map:OnFrameSizeChanged()
    end
end

function addon:ApplyWindowSettings()
    if not map or not map:IsMaximized() then return end
    if InCombat() then Defer(); return end
    -- Recompute Blizzard's size first so disabling the option restores it.
    -- The secure post-hook expands that result only when widescreen is enabled.
    map:UpdateMaximizedSize()
end

function addon:InitializeWindow()
    EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
        if map then return end
        map = WorldMapFrame
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            addon:ApplyWindowSettings()
        end)
        hooksecurefunc(map, "UpdateMaximizedSize", ApplyWidth)
        map:HookScript("OnShow", function() addon:ApplyWindowSettings() end)
        addon:ApplyWindowSettings()
    end)
end
