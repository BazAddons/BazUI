-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Notifications (from BazNotificationCenter)
-- Toasts plus a browsable history for game events.
---------------------------------------------------------------------------
local addon = BazUI.Notifications
local BNC = addon.API


-- Internal state
addon.VERSION = BazUI.VERSION or "1"
addon.modules = {}
addon.notifications = {}
addon.notificationCounter = 0
addon.suppressedFrames = {}
addon.db = nil
addon.panel = nil
addon.name = "Notifications"

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------

local DEFAULTS = {
    -- Derived corner - recomputed automatically from the bell's actual
    -- screen position. Stored so the rest of the addon (toast growth,
    -- panel anchor side, header layout) can read a single value.
    -- Users no longer pick this directly; they drag the bell in
    -- Edit Mode and this updates to match.
    position = "TOPLEFT",
    -- User-saved bell position from Edit Mode dragging. nil = use the
    -- legacy corner default (TOPLEFT margin).
    bellAnchor = nil,
    toastDuration = 5,
    toastScale = 1,
    toastsEnabled = true,
    soundEnabled = true,
    tomtomEnabled = true,
    panelOpacity = 0.85,
    maxHistory = 999,
    historyRetentionDays = 7,
    scale = 1.0,
    dndEnabled = false,
    dndAutoCombat = false,
    dndAutoInstance = false,
    soundHigh = 8959,
    soundNormal = 3175,
    soundLow = 0,
    modules = {},
}

---------------------------------------------------------------------------
-- BazUI Registration
---------------------------------------------------------------------------

BazUI:RegisterModule("Notifications", {
    title = "Notifications",
    profiles = true,
    defaults = DEFAULTS,

    slash = { "/bnc", "/baznotify" },
    commands = {
        test = {
            desc = "Send a test notification",
            handler = function()
                BNC:Push({
                    module = "_test",
                    title = "Test Notification",
                    message = "BNC is working correctly!",
                    icon = "Interface\\Icons\\INV_Misc_Bell_01",
                    priority = "normal",
                })
            end,
        },
        testall = {
            desc = "Send test notifications from all modules",
            handler = function()
                print("|cff00aaff[BNC]|r Sending test notifications...")
                if addon.SendTestBurst then addon.SendTestBurst() end
            end,
        },
        history = {
            desc = "Open notification history",
            handler = function()
                if addon.ShowHistoryPanel then addon.ShowHistoryPanel() end
            end,
        },
        clear = {
            desc = "Clear all notifications",
            handler = function()
                BNC:DismissAll()
                print("|cff00aaff[BNC]|r All notifications cleared.")
            end,
        },
        dnd = {
            desc = "Toggle Do Not Disturb",
            handler = function()
                BNC:ToggleDND()
            end,
        },
        scaffold = {
            desc = "Print a module template: /bnc scaffold <name>",
            handler = function(args)
                if addon.ScaffoldModule then addon.ScaffoldModule(args) end
            end,
        },
    },
    defaultHandler = function()
        if addon.TogglePanel then addon.TogglePanel() end
    end,

    minimap = {
        label = "Notifications",
        icon = "Interface\\Icons\\INV_Misc_Bell_01",
        onClick = function()
            if addon.OpenOptions then addon.OpenOptions() end
        end,
    },

    onLoad = function(self)

        -- History is global (not per-profile): BazUIDB.notifications.history
        BazUIDB.notifications = BazUIDB.notifications or {}
        if not BazUIDB.notifications.history then
            BazUIDB.notifications.history = { days = {}, dayIndex = {} }
        end

        -- Flatten the db proxy: addon.db.X reads directly from active profile
        addon.db = self.db.profile
        addon.bncAddon = self

        -- Trim persistent history at load to bound memory usage
        if addon.History_Trim then
            local retention = addon.db.historyRetentionDays or 7
            addon.History_Trim(retention)
        end

        -- Register PLAYER_ENTERING_WORLD to bridge to internal PLAYER_READY
        self:On("PLAYER_ENTERING_WORLD", function(event, isLogin, isReload)
            addon.Events:Trigger("PLAYER_READY", isLogin, isReload)
        end)

        -- Fire CORE_LOADED so all internal listeners activate
        addon.Events:Trigger("CORE_LOADED")
    end,

    onReady = function(self)
        -- Asked for by name, like the other nine modules that draw
        -- something. FireProfileChanged has a fallback that looks for an
        -- ApplySettings, but it looks on the object RegisterModule hands
        -- back and this module keeps its on BazUI.Notifications - two
        -- different tables. The fallback has since been taught to look in
        -- both places; this does not depend on it having been.
        self:OnProfileChanged(function() addon:ApplySettings() end)
    end,
})

---------------------------------------------------------------------------
-- Reading the profile again
--
-- Called when the profile underneath changes, which is every one of these
-- at once. This module keeps its display settings on an event bus - each
-- one has a SETTING_CHANGED_<key> that whatever draws it listens for - so
-- the honest way to re-apply them is to say they all changed, rather than
-- to reach into the panel and the toasts from here and set them by hand.
--
-- The keys are the ones something actually listens for. A key nobody
-- listens for would fire into nothing, and one that is missed here shows
-- up as a part of the screen still wearing the old profile.
---------------------------------------------------------------------------

local PROFILE_KEYS = { "position", "scale", "toastScale", "panelOpacity" }

function addon:ApplySettings()
    if not addon.db then return end

    -- The bell first: its position is the anchor the panel and the toasts
    -- are placed from, so moving it after them would leave them behind.
    if addon.ApplyButtonPosition then addon.ApplyButtonPosition() end

    for _, key in ipairs(PROFILE_KEYS) do
        addon.Events:Trigger("SETTING_CHANGED_" .. key, addon.db[key])
    end
end

---------------------------------------------------------------------------
-- TomTom integration
---------------------------------------------------------------------------

function BNC:HasTomTom()
    return TomTom and TomTom.AddWaypoint and true or false
end

function BNC:SetWaypoint(waypointData)
    if not waypointData then return false end
    if addon.db and not addon.db.tomtomEnabled then return false end
    if not self:HasTomTom() then
        print("|cff00aaff[BNC]|r TomTom is not installed. Install TomTom to use waypoint features.")
        return false
    end

    local mapID = waypointData.mapID
    local x = waypointData.x
    local y = waypointData.y
    local title = waypointData.title or "BNC Waypoint"

    if not mapID or not x or not y then return false end

    if addon.lastWaypoint then
        pcall(function() TomTom:RemoveWaypoint(addon.lastWaypoint) end)
    end

    addon.lastWaypoint = TomTom:AddWaypoint(mapID, x, y, {
        title = title,
        persistent = false,
        minimap = true,
        world = true,
        from = "BNC",
    })

    return true
end
