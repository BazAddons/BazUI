-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications
local BNC = addon.API

local suppressedFrames = addon.suppressedFrames

function BNC:SuppressBlizzardFrame(frameName)
    if suppressedFrames[frameName] then return end

    local frame = _G[frameName]
    if not frame then return end

    local ok = pcall(function()
        local state = {
            wasShown = frame:IsShown(),
            onShow = frame:GetScript("OnShow"),
        }
        suppressedFrames[frameName] = state

        frame:Hide()
        frame:SetScript("OnShow", function(self)
            self:Hide()
        end)
    end)

    if not ok then
        suppressedFrames[frameName] = nil
    end
end

function BNC:RestoreBlizzardFrame(frameName)
    local state = suppressedFrames[frameName]
    if not state then return end

    local frame = _G[frameName]
    if not frame then return end

    pcall(function()
        frame:SetScript("OnShow", state.onShow)
        if state.wasShown then
            frame:Show()
        end
    end)

    suppressedFrames[frameName] = nil
end

function addon.RestoreAllBlizzardFrames()
    for frameName in pairs(suppressedFrames) do
        BNC:RestoreBlizzardFrame(frameName)
    end
end

-- ---------------------------------------------------------------------------
-- Alert system hooking: suppress Blizzard popup alert frames (loot, achievements, etc).
-- shouldSuppressFunc() should return true when alerts should be hidden.
-- ---------------------------------------------------------------------------

local hookedAlertSystems = {}

function BNC:HookAlertSystem(system, shouldSuppressFunc)
    if not system or not system.AddAlert then return end
    if hookedAlertSystems[system] then return end
    hookedAlertSystems[system] = true

    hooksecurefunc(system, "AddAlert", function(self, frame)
        if shouldSuppressFunc() and type(frame) == "table" and frame.Hide then
            frame:Hide()
        end
    end)
end
