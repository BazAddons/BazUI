-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications
local BNC = addon.API

local suppressedFrames = addon.suppressedFrames

-- Blizzard's own popups, kept down.
--
-- This used to replace the frame's OnShow with one that hides it, and to
-- hooksecurefunc AddAlert on each alert system. Both are writes to a frame
-- we do not own: on Forever the write does not survive, and Blizzard's own
-- code then finds the script or the method missing - which is how the
-- objective tracker, the tooltip and the nameplates each broke in turn.
--
-- BazUI.SuppressFrame does the same job by appending an OnShow handler and
-- keeping the answer on our side. Which frames are meant to be down lives
-- in `suppressedFrames`, so asking again is just a table read.
function BNC:SuppressBlizzardFrame(frameName)
    local frame = _G[frameName]
    if not frame then return end
    suppressedFrames[frameName] = true
    BazUI.SuppressFrame(frame, function()
        return suppressedFrames[frameName] and true or false
    end)
end

function BNC:RestoreBlizzardFrame(frameName)
    local frame = _G[frameName]
    if not frame then return end
    suppressedFrames[frameName] = nil
    BazUI.SuppressFrame(frame, function() return false end)
end

function addon.RestoreAllBlizzardFrames()
    for frameName in pairs(suppressedFrames) do
        BNC:RestoreBlizzardFrame(frameName)
    end
end

-- ---------------------------------------------------------------------------
-- The game's popup alerts - loot, achievements and the rest.
--
-- Modern alert frames come out of a pool and have no names, so there is
-- nothing to suppress one by one. The container they all pass through is
-- the thing to put down, which takes the lot in one and needs no hook at
-- all: AddAlert and AddAlertFrame are left exactly as Blizzard wrote them.
-- ---------------------------------------------------------------------------

function BNC:HookAlertSystem(system, shouldSuppressFunc)
    if not (system and system.HookScript and shouldSuppressFunc) then return end
    BazUI.SuppressFrame(system, shouldSuppressFunc)
end
