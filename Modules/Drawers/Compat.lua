-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers: Compatibility shims
--
-- Defensive patches for taint propagation and third-party addon conflicts
-- caused by BazUI Drawers modifying Blizzard frames (ObjectiveTrackerFrame,
-- DurabilityFrame, UIParentRightManagedFrameContainer, Minimap, etc.)
-- from insecure code. Each shim wraps a specific Blizzard function in
-- pcall so taint errors are caught silently rather than breaking the UI.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

---------------------------------------------------------------------------
-- Zygor Guides Viewer compatibility.
--
-- Zygor's NotificationCenter.lua line 434 reads
--     ZygorGuidesViewerMapIcon:GetLeft() > (NC.SingleNotif:GetWidth() + 10)
-- during its threaded 'NC2 startup' phase. When BazUI Drawers' Minimap
-- widget has already reparented the Blizzard Minimap into our drawer
-- wrapper, the minimap's child frames (including Zygor's map icon)
-- are in an anchor chain whose positions haven't been resolved yet by
-- a render pass - so GetLeft() returns nil and Zygor's numeric
-- comparison throws "attempt to compare number with nil".
--
-- Zygor's own bug is missing a nil-guard on that line. We can't fix
-- their source, but we CAN pre-hook their UpdatePosition function to
-- bail and retry when the icon isn't positioned yet. We cap retries
-- at a few seconds so a truly broken icon doesn't loop forever.
---------------------------------------------------------------------------

local zygorPatched = false
local zygorRetries = 0
local ZYGOR_MAX_RETRIES = 20   -- ~4 seconds at 0.2s intervals

local function InstallZygorNCFix()
    if zygorPatched then return true end
    if not _G.ZGV or not _G.ZGV.NotificationCenter
       or not _G.ZGV.NotificationCenter.UpdatePosition then
        return false
    end

    local NC = _G.ZGV.NotificationCenter
    local origUpdatePosition = NC.UpdatePosition

    NC.UpdatePosition = function(self, ...)
        local icon = _G.ZygorGuidesViewerMapIcon

        -- Defer until the icon's anchor chain has resolved. During
        -- BazUI Drawers' startup the Minimap gets reparented into a
        -- not-yet-rendered widget wrapper, so the Zygor icon's
        -- GetLeft() can return nil for a frame or two.
        if icon and icon.GetLeft and not icon:GetLeft() then
            zygorRetries = zygorRetries + 1
            if zygorRetries < ZYGOR_MAX_RETRIES then
                C_Timer.After(0.2, function()
                    pcall(NC.UpdatePosition, NC)
                end)
            end
            return
        end

        -- Reset retry counter on successful call
        zygorRetries = 0

        -- Call the original. Wrap in pcall so any other race-condition
        -- nils from the Zygor init phase don't propagate back out to
        -- their error handler and show the user a huge stack trace.
        local ok = pcall(origUpdatePosition, self, ...)
        if not ok then
            C_Timer.After(0.5, function()
                pcall(NC.UpdatePosition, NC)
            end)
        end
    end

    zygorPatched = true
    return true
end

---------------------------------------------------------------------------
-- Install compat shims on ADDON_LOADED so we catch third-party addons
-- regardless of load order. If Zygor is already loaded when we reach
-- here (unlikely but possible), InstallZygorNCFix short-circuits.
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, _, name)
    if name == "ZygorGuidesViewer" then
        -- Zygor's NotificationCenter.lua runs before PLAYER_LOGIN, so
        -- by the time ADDON_LOADED fires for their addon, ZGV and
        -- ZGV.NotificationCenter should already exist. Install the
        -- shim immediately.
        InstallZygorNCFix()
    end
end)

-- In case Zygor was already loaded before we registered the event
-- (same-session reload after BazUI Drawers was installed), try once now.
if _G.ZGV and _G.ZGV.NotificationCenter then
    InstallZygorNCFix()
end
