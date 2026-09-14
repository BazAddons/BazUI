-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Calendar: Calendar event summaries, holiday alerts, invites, and weekly reset timer.
-- Events: CALENDAR_UPDATE_INVITE_LIST, CALENDAR_NEW_EVENT, CALENDAR_UPDATE_EVENT_LIST
-- ==========================================================================

local MODULE_ID = "calendar"
local MODULE_NAME = "Calendar"
local MODULE_ICON = "Interface\\Icons\\INV_Misc_Note_01"

local ICON_EVENT = "Interface\\Icons\\INV_Misc_Note_01"
local ICON_HOLIDAY = "Interface\\Icons\\INV_Misc_Tournaments_banner_Orc"
local ICON_INVITE = "Interface\\Icons\\INV_Letter_15"
local ICON_RESET = "Interface\\Icons\\Spell_Nature_TimeStop"

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local function CheckPendingInvites()
    if GetSetting("showInvites") == false then return end

    local numInvites = C_Calendar.GetNumPendingInvites()
    if numInvites and numInvites > 0 then
        BNC:Push({
            module = MODULE_ID,
            title = "Calendar Invites",
            message = numInvites .. " pending invite" .. (numInvites ~= 1 and "s" or ""),
            icon = ICON_INVITE,
            priority = "normal",
            duration = GetSetting("toastDuration") or 5,
            silent = GetSetting("inviteToasts") == false,
        })
    end
end

-- Show non-holiday player events for today
local function CheckTodayEvents()
    if GetSetting("showTodayEvents") == false then return end

    local currentDate = C_DateAndTime.GetCurrentCalendarTime()
    if not currentDate then return end

    local numEvents = C_Calendar.GetNumDayEvents(0, currentDate.monthDay)

    local upcomingEvents = {}
    for i = 1, numEvents do
        local event = C_Calendar.GetDayEvent(0, currentDate.monthDay, i)
        if event and event.calendarType ~= "HOLIDAY" and event.calendarType ~= "SYSTEM" then
            table.insert(upcomingEvents, event.title or "Event")
        end
    end

    if #upcomingEvents > 0 then
        local message
        if #upcomingEvents <= 2 then
            message = table.concat(upcomingEvents, ", ")
        else
            message = upcomingEvents[1] .. " + " .. (#upcomingEvents - 1) .. " more"
        end

        BNC:Push({
            module = MODULE_ID,
            title = "Today's Events",
            message = message,
            icon = ICON_EVENT,
            priority = "normal",
            duration = GetSetting("toastDuration") or 6,
            silent = GetSetting("eventToasts") == false,
        })
    end
end

-- Notify about active in-game holidays
local function CheckHolidays()
    if GetSetting("showHolidays") == false then return end

    local currentDate = C_DateAndTime.GetCurrentCalendarTime()
    if not currentDate then return end

    local numEvents = C_Calendar.GetNumDayEvents(0, currentDate.monthDay)

    for i = 1, numEvents do
        local event = C_Calendar.GetDayEvent(0, currentDate.monthDay, i)
        if event and (event.calendarType == "HOLIDAY" or event.calendarType == "SYSTEM") then
            local title = event.title
            if title and title ~= "" then
                BNC:Push({
                    module = MODULE_ID,
                    title = "Holiday Active",
                    message = title,
                    icon = event.iconTexture and tostring(event.iconTexture) or ICON_HOLIDAY,
                    priority = "low",
                    duration = GetSetting("toastDuration") or 5,
                    silent = GetSetting("holidayToasts") == false,
                })
            end
        end
    end
end

-- Show time remaining until weekly reset
local function ShowResetInfo()
    if GetSetting("showReset") == false then return end

    local resetTime = C_DateAndTime.GetSecondsUntilWeeklyReset()
    if not resetTime then return end

    local days = math.floor(resetTime / 86400)
    local hours = math.floor((resetTime % 86400) / 3600)

    local message
    if days > 0 then
        message = days .. "d " .. hours .. "h until weekly reset"
    else
        message = hours .. "h until weekly reset"
    end

    BNC:Push({
        module = MODULE_ID,
        title = "Weekly Reset",
        message = message,
        icon = ICON_RESET,
        priority = days <= 1 and "high" or "low",
        duration = GetSetting("toastDuration") or 5,
        silent = GetSetting("resetToasts") == false,
    })
end

local function OnCalendarInviteAdded()
    if GetSetting("showInvites") == false then return end

    BNC:Push({
        module = MODULE_ID,
        title = "New Calendar Invite",
        message = "You have a new calendar invitation",
        icon = ICON_INVITE,
        priority = "normal",
        duration = GetSetting("toastDuration") or 5,
        silent = GetSetting("inviteToasts") == false,
    })
end

-- Event frame
local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CALENDAR_UPDATE_INVITE_LIST")

pcall(function() eventFrame:RegisterEvent("CALENDAR_NEW_EVENT") end)
pcall(function() eventFrame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST") end)

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local isLogin = ...
        if isLogin then
            -- Calendar data must be opened before querying
            C_Calendar.OpenCalendar()
            C_Timer.After(3, function()
                CheckPendingInvites()
                CheckTodayEvents()
                CheckHolidays()
                ShowResetInfo()
            end)
        end
    elseif event == "CALENDAR_UPDATE_INVITE_LIST" then
        C_Timer.After(0.5, OnCalendarInviteAdded)
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { type = "event", key = "events",   label = "Today's events at login", show = "showTodayEvents", toast = "eventToasts" },
    { type = "event", key = "holidays", label = "Holidays at login",       show = "showHolidays",    toast = "holidayToasts" },
    { type = "event", key = "invites",  label = "Calendar invites",        show = "showInvites",     toast = "inviteToasts" },
    { type = "event", key = "reset",    label = "Weekly reset timer",      show = "showReset",       toast = "resetToasts" },
    { key = "toastDuration",    label = "Toast duration", type = "slider", default = 5, min = 1, max = 15, step = 1 },
})
