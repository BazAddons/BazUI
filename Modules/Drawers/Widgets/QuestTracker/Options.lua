-- SPDX-License-Identifier: GPL-2.0-or-later
-- QuestTracker: Options & Blizzard Tracker Visibility
-- Per-widget settings exposed in BazUI Drawers > Widgets > Quest Tracker.

local addon = BazUI:GetModule("Drawers")
if not addon then return end
local QT = addon.QT
local C  = QT.C

---------------------------------------------------------------------------
-- Blizzard tracker visibility
---------------------------------------------------------------------------

local blizzTrackerHooked = false
local blizzTrackerSuppressed = false

function QT.ApplyBlizzardTrackerVisibility()
    -- Retail: ObjectiveTrackerFrame. Classic Era: QuestWatchFrame
    -- (Wrath-era clients call it WatchFrame).
    local tracker = ObjectiveTrackerFrame or QuestWatchFrame or WatchFrame
    if not tracker then return end
    local hide = addon:GetWidgetSetting(C.WIDGET_ID, "hideBlizzardTracker", true)
    blizzTrackerSuppressed = (hide ~= false)

    if blizzTrackerSuppressed then
        tracker:Hide()
    else
        tracker:Show()
    end

    -- Hook Show once (hooksecurefunc preserves the original secure
    -- method so it doesn't taint the frame's method table - unlike
    -- the old approach of replacing Show with Hide which tainted
    -- everything downstream including UnitFrame health bars).
    if not blizzTrackerHooked then
        hooksecurefunc(tracker, "Show", function(self)
            if blizzTrackerSuppressed then
                self:Hide()
            end
        end)
        blizzTrackerHooked = true
    end
end

---------------------------------------------------------------------------
-- Options table
---------------------------------------------------------------------------

function QT.GetOptionsArgs()
    return {
        layoutHeader = {
            order = 10,
            type = "header",
            name = "Layout",
        },
        maxHeight = {
            order = 11,
            type = "range",
            name = "Max Height",
            desc = "Cap the widget's height in pixels. Quests beyond this height scroll via the mouse wheel.",
            min = 120, max = 900, step = 20,
            get = function()
                return addon:GetWidgetSetting(C.WIDGET_ID, "maxHeight", C.MAX_HEIGHT_DEFAULT)
            end,
            set = function(_, val)
                addon:SetWidgetSetting(C.WIDGET_ID, "maxHeight", val)
                QT.Refresh()
            end,
        },
        behaviorHeader = {
            order = 20,
            type = "header",
            name = "Behavior",
        },
        hideBlizzardTracker = {
            order = 21,
            type = "toggle",
            name = "Hide Default Tracker",
            desc = "Hide Blizzard's own Objective Tracker so only this widget is visible. Disable to show both trackers side by side.",
            get = function()
                return addon:GetWidgetSetting(C.WIDGET_ID, "hideBlizzardTracker", true) ~= false
            end,
            set = function(_, val)
                addon:SetWidgetSetting(C.WIDGET_ID, "hideBlizzardTracker", val)
                QT.ApplyBlizzardTrackerVisibility()
            end,
        },

        integrationHeader = {
            order = 30,
            type = "header",
            name = "Integrations",
        },
        tomtomEnabled = {
            order = 31,
            type = "toggle",
            name = "TomTom Waypoint",
            desc = "When TomTom is installed, set the TomTom arrow to the super-tracked quest's next objective. Turn off to leave TomTom alone.",
            get = function()
                return addon:GetWidgetSetting(C.WIDGET_ID, "tomtomEnabled", true) ~= false
            end,
            set = function(_, val)
                addon:SetWidgetSetting(C.WIDGET_ID, "tomtomEnabled", val)
                if val then
                    QT.OnSuperTrackChanged()
                else
                    QT.RemoveActiveWaypoint()
                end
            end,
            disabled = function() return not QT.HasTomTom() end,
        },
        zygorEnabled = {
            order = 32,
            type = "toggle",
            name = "Zygor Waypoint",
            desc = "When Zygor Guides is installed, set Zygor's navigation arrow to the super-tracked quest's next objective. Turn off to leave Zygor alone.",
            get = function()
                return addon:GetWidgetSetting(C.WIDGET_ID, "zygorEnabled", true) ~= false
            end,
            set = function(_, val)
                addon:SetWidgetSetting(C.WIDGET_ID, "zygorEnabled", val)
                if val then
                    QT.OnSuperTrackChanged()
                end
            end,
            disabled = function() return not QT.HasZygor() end,
        },
    }
end
