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

local blizzTrackerSuppressed = false

function QT.ApplyBlizzardTrackerVisibility()
    -- Retail: ObjectiveTrackerFrame. Classic Era: QuestWatchFrame
    -- (Wrath-era clients call it WatchFrame).
    local tracker = ObjectiveTrackerFrame or QuestWatchFrame or WatchFrame
    if not tracker then return end
    local hide = addon:GetWidgetSetting(C.WIDGET_ID, "hideBlizzardTracker", true)
    blizzTrackerSuppressed = (hide ~= false)

    -- Through the shared suppressor, which hooks the frame's OnShow and
    -- never writes to the frame itself. This used to hooksecurefunc its
    -- Show, and on Forever - where the tracker is an Edit Mode managed,
    -- and so protected, frame - that left Blizzard's own self:Show()
    -- calling a nil.
    BazUI.SuppressFrame(tracker, function() return blizzTrackerSuppressed end)
    QT.RescueQuestTimer()
end

---------------------------------------------------------------------------
-- The quest timer
--
-- Blizzard_QuestTimer/Mainline/Blizzard_QuestTimer.xml:
--
--   <Frame name="QuestTimerFrame" ... parent="ObjectiveTrackerFrame">
--
-- The timer is a CHILD of the tracker, so hiding the tracker hides it, and
-- a timed quest counts down where nobody can see it. "Scalding Mornbrew
-- Delivery" gives you five minutes and no clock, which is the quest
-- failing rather than the interface being untidy.
--
-- Rescued rather than rebuilt. Their frame already knows how to count, how
-- to list several timers at once, and what to do when one runs out; a copy
-- of that in our tracker would be a second implementation to keep in step
-- with theirs for no gain. So it is moved to UIParent and left to get on
-- with it.
--
-- Safe on their side: Blizzard_QuestTimer.lua never re-parents this frame
-- and never anchors it - it only positions its own buttons inside itself
-- and shows or hides the whole thing. So the parent is ours to change and
-- nothing of theirs disagrees later.
---------------------------------------------------------------------------

local timerRescued = false

-- Where the timer sits until somebody moves it.
--
-- Measured rather than guessed: placed by hand on a 4K screen and read
-- back out of the saved position. Screen pixels from UIParent's centre,
-- the same units Edit Mode saves in, so the one scale division below
-- applies to this and to a saved value alike.
--
-- It used to default to "just above BazUI's quest tracker", which sounds
-- tidier than it looked - the tracker moves, can be docked into a drawer,
-- and can be turned off entirely, so the timer went wherever that left it.
-- A fixed spot is somewhere, and somewhere is draggable.
local DEFAULT_TIMER = { x = 432.36, y = 182.04 }

function QT.RescueQuestTimer()
    local timer = _G.QuestTimerFrame
    if not timer then
        -- Blizzard_QuestTimer is its own addon. It is enabled by default,
        -- but "loaded by the time our settings are applied" is not the
        -- same claim, and a nil here would mean the rescue silently never
        -- happened - which is indistinguishable from the bug it fixes.
        if not QT._timerWatch then
            QT._timerWatch = CreateFrame("Frame")
            QT._timerWatch:RegisterEvent("ADDON_LOADED")
            QT._timerWatch:SetScript("OnEvent", function(self, _, name)
                if name ~= "Blizzard_QuestTimer" then return end
                self:UnregisterAllEvents()
                QT._timerWatch = nil
                QT.RescueQuestTimer()
            end)
        end
        return
    end

    -- Reparenting is a protected operation in combat, and a timer arriving
    -- mid-fight is exactly when this would be attempted. Deferred rather
    -- than dropped.
    if InCombatLockdown() then
        if not QT._timerWaiting then
            QT._timerWaiting = CreateFrame("Frame")
            QT._timerWaiting:RegisterEvent("PLAYER_REGEN_ENABLED")
            QT._timerWaiting:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                QT._timerWaiting = nil
                QT.RescueQuestTimer()
            end)
        end
        return
    end

    if not blizzTrackerSuppressed then
        -- Their tracker is visible again, so the timer belongs back inside
        -- it where their layout expects it.
        if timerRescued then
            local tracker = _G.ObjectiveTrackerFrame
            if tracker then
                BazUI.SecureCall(timer, "SetParent", tracker)
                timer:ClearAllPoints()
                timer:SetPoint("TOP", tracker, "TOP", 0, -10)
            end
            timerRescued = false
        end
        return
    end

    if timerRescued then return end
    timerRescued = true

    BazUI.SecureCall(timer, "SetParent", UIParent)
    timer:SetFrameStrata("MEDIUM")
    timer:ClearAllPoints()
    timer:SetPoint("CENTER", QT.QuestTimerAnchor(), "CENTER", 0, 0)
end

---------------------------------------------------------------------------
-- Somewhere to put it
--
-- A frame of ours that the timer sits on, rather than registering their
-- frame with Edit Mode directly.
--
-- Edit Mode writes to what it manages - an overlay, a mover, a handful of
-- fields - and those go on ours. Blizzard reads none of them, so this is
-- belt and braces rather than a known break; but the timer is a frame
-- whose mixin runs an OnUpdate every frame, and a frame we have written
-- to is a frame whose scripts run as ours. The cheap version of that
-- argument is that there is no reason to find out.
--
-- It also gives the thing a size while it is empty. QuestTimerFrame is
-- hidden whenever no quest is timed, so without an anchor of its own
-- there would be nothing to grab in Edit Mode until you happened to be on
-- a timed quest - which is the one moment you do not want to be arranging
-- your interface.
---------------------------------------------------------------------------

function QT.QuestTimerAnchor()
    if QT._timerAnchor then return QT._timerAnchor end

    local anchor = CreateFrame("Frame", "BazUIQuestTimerAnchor", UIParent)
    anchor:SetSize(158, 72)          -- QuestTimerFrame's own size
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetClampedToScreen(true)
    QT._timerAnchor = anchor

    -- Placed once the settings are real, not now.
    --
    -- This widget is set up from the tracker's own init, which runs before
    -- Persist has adopted the saved tables - on this client BazUIDB at that
    -- moment is Seed.lua's copy and is about to be replaced wholesale. A
    -- position read here comes back nil every time, the fallback is used,
    -- and the frame appears to "move on reload" while in fact it has never
    -- once been restored. See Core/Core.lua's ReadyVariables.
    --
    -- QueueForVariables runs straight away if they are already ready, so
    -- this is not a delay, it is an ordering.
    BazUI:QueueForVariables(function() QT.PlaceQuestTimerAnchor() end)

    if BazUI.RegisterEditModeFrame then
        BazUI:RegisterEditModeFrame(anchor, {
            label = "Quest Timer",
            addonName = "Drawers",
            positionKey = "questTimerPosition",
            actions = {
                {
                    label = "Reset position",
                    callback = function()
                        if addon.SetSetting then
                            addon:SetSetting("questTimerPosition", nil)
                        end
                        QT.PlaceQuestTimerAnchor()
                    end,
                },
            },
        })
    end

    return anchor
end

-- Where it was left, or above our tracker, or where Blizzard's would have
-- been.
--
-- The saved figures are screen pixels: Edit Mode's SavePosition works out
-- the frame's centre against UIParent's and multiplies both by their
-- effective scale. SetPoint does not take screen pixels - its offsets are
-- in the frame's own coordinate space - so putting the saved number
-- straight back in is only right when that scale happens to be 1.
--
-- On a 4K display with UI Scale off it is well under 1, and the frame came
-- back nearer the middle of the screen than it was left: down and to the
-- left of a spot above and right of centre. Dividing undoes the multiply,
-- and matches what NudgeFrame does in Core/EditMode.lua.
function QT.PlaceQuestTimerAnchor()
    local anchor = QT._timerAnchor
    if not anchor then return end

    local saved = addon.GetSetting and addon:GetSetting("questTimerPosition")
    if not (saved and saved.x and saved.y) then saved = DEFAULT_TIMER end

    local scale = anchor:GetEffectiveScale()
    if not scale or scale == 0 then scale = 1 end

    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", saved.x / scale, saved.y / scale)
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
        tomtomHideBlock = {
            order = 31.5,
            type = "toggle",
            name = "Hide TomTom's coordinates",
            desc = "Puts away the little block showing where you are "
                .. "standing. TomTom's own setting is left alone - this "
                .. "only holds the frame down, so turning it off gives you "
                .. "the block back exactly as TomTom had it.",
            get = function()
                return addon:GetWidgetSetting(C.WIDGET_ID, "tomtomHideBlock", false) == true
            end,
            set = function(_, val)
                addon:SetWidgetSetting(C.WIDGET_ID, "tomtomHideBlock", val and true or false)
                QT.ApplyTomTomBlock()
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
