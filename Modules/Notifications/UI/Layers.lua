-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications
local layers = {}
local frames = {}
local initialized = false

local function FullscreenMapShown()
    local map = WorldMapFrame
    return map and map:IsShown() and map:IsMaximized()
end

local function UpdateLayers()
    local covered = FullscreenMapShown()
    for _, frame in ipairs(frames) do
        -- The native fullscreen blackout is LOW; go beneath it as well
        -- as the map so notifications cannot show through the side margins.
        frame:SetFrameStrata(covered and "BACKGROUND" or layers[frame])
    end
    if covered and GameTooltip then
        local owner = GameTooltip:GetOwner()
        while owner do
            if layers[owner] then GameTooltip:Hide(); break end
            owner = owner:GetParent()
        end
    end
end

function addon.RegisterNotificationLayer(frame)
    if not layers[frame] then
        layers[frame] = frame:GetFrameStrata()
        frames[#frames + 1] = frame
    end
    if not initialized then
        initialized = true
        EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
            local map = WorldMapFrame
            map:HookScript("OnShow", UpdateLayers)
            map:HookScript("OnHide", UpdateLayers)
            hooksecurefunc(map, "Maximize", UpdateLayers)
            hooksecurefunc(map, "Minimize", UpdateLayers)
            UpdateLayers()
        end)
    end
    UpdateLayers()
end
