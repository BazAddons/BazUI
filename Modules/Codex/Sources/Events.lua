-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: Events
--
-- What is on: today, the rest of this week, and the holidays running
-- now. Read from the game's own calendar, which has to be asked to
-- open before it will answer - so the page asks once, quietly, and
-- again whenever the client says the calendar changed.
--
-- Every row opens the real calendar on the day it belongs to, and so
-- does the button in the header, because the calendar has no home in
-- this interface otherwise. Opening it is Blizzard's own toggle run as
-- Blizzard, since it puts up a panel of theirs.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local Theme = BazUI.Skin.Theme

local TAB = "events"
local COMMON = {
    tab      = TAB,
    tabLabel = "Events",
    tabOrder = 24,
    tabIcon  = "Interface\\Icons\\INV_Misc_PocketWatch_01",
}
local PREFIX = "evt."

local DAYS_AHEAD = 7

---------------------------------------------------------------------------
-- Opening the real thing
---------------------------------------------------------------------------

local function HasCalendar()
    return C_Calendar and C_Calendar.GetMonthInfo and C_Calendar.GetNumDayEvents
end

-- The calendar is a Blizzard panel, so their toggle runs as theirs: on
-- Forever a panel opened by us compares secret values on the way up and
-- throws for its trouble. See BazUI.OpenCharacterSheet, same reason.
local function OpenCalendar(monthOffset, day)
    if not _G.ToggleCalendar then
        BazUI:Print("This client has no calendar.")
        return
    end
    if not (Calendar_Show or CalendarFrame) then
        pcall(C_AddOns.LoadAddOn, "Blizzard_Calendar")
    end
    if monthOffset and day and C_Calendar and C_Calendar.SetAbsMonth then
        local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime
            and C_DateAndTime.GetCurrentCalendarTime()
        if now then
            local month = now.month + monthOffset
            local year  = now.year + math.floor((month - 1) / 12)
            month = ((month - 1) % 12) + 1
            pcall(C_Calendar.SetAbsMonth, month, year)
        end
    end
    if securecallfunction then
        securecallfunction(_G.ToggleCalendar)
    else
        _G.ToggleCalendar()
    end
end

Codex.OpenCalendar = OpenCalendar

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

local opened = false

local function Today()
    if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
        local ok, now = pcall(C_DateAndTime.GetCurrentCalendarTime)
        if ok and now then return now end
    end
    return nil
end

-- Ask the calendar to load its month. It answers nothing until it has,
-- and it fires CALENDAR_UPDATE_EVENT_LIST when it does.
local function Prime()
    if opened or not HasCalendar() then return end
    opened = true
    if C_Calendar.OpenCalendar then pcall(C_Calendar.OpenCalendar) end
end

local function DayEvents(day, monthOffset)
    local out = {}
    local ok, count = pcall(C_Calendar.GetNumDayEvents, monthOffset or 0, day)
    if not (ok and type(count) == "number") then return out end
    for i = 1, count do
        local ok2, e = pcall(C_Calendar.GetDayEvent, monthOffset or 0, day, i)
        if ok2 and e and e.title then
            out[#out + 1] = e
        end
    end
    return out
end

-- Is this one of the game's own holidays, rather than somebody's raid
-- night?
--
-- Worked out from the enum's own key names rather than from numbers:
-- the values differ between clients, and a guessed number is how every
-- holiday ended up filed as an ordinary event. A client that answers
-- with a string ("HOLIDAY", "HOLIDAY_WEEKLY") is read the same way.
local holidaySet
local function HolidaySet()
    if holidaySet then return holidaySet end
    holidaySet = {}
    if Enum and Enum.CalendarType then
        for key, value in pairs(Enum.CalendarType) do
            if type(key) == "string" and key:lower():find("holiday") then
                holidaySet[value] = true
            end
        end
    end
    return holidaySet
end

local function IsHoliday(e)
    local kind = e.calendarType
    if type(kind) == "string" then return kind:upper():find("HOLIDAY") ~= nil end
    return HolidaySet()[kind] or false
end

-- An event's own words for when it is: "started", "ends today", or the
-- day it falls on.
local function When(e, offsetDays)
    if e.sequenceType == "ONGOING" then return "running now" end
    if e.sequenceType == "START" and offsetDays == 0 then return "starts today" end
    if e.sequenceType == "END" and offsetDays == 0 then return "ends today" end
    if offsetDays == 0 then return "today" end
    if offsetDays == 1 then return "tomorrow" end
    return ("in %d days"):format(offsetDays)
end

---------------------------------------------------------------------------
-- Blocks
---------------------------------------------------------------------------

local function Gather()
    local now = Today()
    if not (now and HasCalendar()) then return nil end

    local info
    local ok, month = pcall(C_Calendar.GetMonthInfo, 0)
    if ok then info = month end
    local numDays = (info and info.numDays) or 31

    -- An event that runs for days is listed once, on the first day it
    -- appears - otherwise a week-long festival fills the page with
    -- seven identical rows saying "running now".
    local today, soon, holidays = {}, {}, {}
    local seen = {}
    for offset = 0, DAYS_AHEAD do
        local day = now.monthDay + offset
        local monthOffset = 0
        if day > numDays then
            day = day - numDays
            monthOffset = 1
        end
        for _, e in ipairs(DayEvents(day, monthOffset)) do
            local key = (e.title or "?") .. "|" .. tostring(e.eventType or "")
            if not seen[key] then
                seen[key] = true
                local row = { event = e, offset = offset, day = day, monthOffset = monthOffset }
                if IsHoliday(e) then
                    holidays[#holidays + 1] = row
                elseif offset == 0 then
                    today[#today + 1] = row
                else
                    soon[#soon + 1] = row
                end
            end
        end
    end
    return { today = today, soon = soon, holidays = holidays, now = now }
end

local function Row(entry)
    local e = entry.event
    return {
        icon   = e.iconTexture,
        label  = e.title,
        detail = When(e, entry.offset),
        state  = entry.offset == 0 and "open" or nil,
        muted  = entry.offset > 2 or nil,
        tip    = e.title .. (e.difficultyName and e.difficultyName ~= ""
            and ("|nDifficulty\t" .. e.difficultyName) or "")
            .. "|n|nClick to open the calendar on this day.",
        onClick = function() OpenCalendar(entry.monthOffset, entry.day) end,
    }
end

local function Rows(list)
    local rows = {}
    for _, entry in ipairs(list) do rows[#rows + 1] = Row(entry) end
    return rows
end

local function Blocks()
    local data = Gather()

    if not data then
        return { {
            key   = "_none",
            title = "Events",
            GetRows = function()
                return { {
                    label  = HasCalendar() and "The calendar has not answered yet."
                        or "This client has no calendar.",
                    detail = "open it",
                    muted  = true,
                    onClick = function() OpenCalendar() end,
                    tip    = "Click to open the game's calendar.",
                } }
            end,
        } }
    end

    return {
        {
            key   = "today",
            title = "Today",
            column = 1,
            empty = "Nothing on today.",
            GetRows = function()
                local d = Gather()
                return d and Rows(d.today) or {}
            end,
            GetHighlight = function()
                local d = Gather()
                local n = d and (#d.today + #d.holidays) or 0
                return {
                    value = n,
                    label = n == 1 and "event on today" or "events on today",
                    color = n > 0 and Theme.colors.gold or nil,
                }
            end,
        },
        {
            key    = "holidays",
            title  = "Holidays",
            column = 1,
            empty  = "No holiday running.",
            GetRows = function()
                local d = Gather()
                return d and Rows(d.holidays) or {}
            end,
        },
        {
            key    = "soon",
            title  = "This week",
            column = 2,
            empty  = "Nothing else in the next seven days.",
            GetRows = function()
                local d = Gather()
                return d and Rows(d.soon) or {}
            end,
        },
    }
end

local function Sync()
    Codex:SyncGroupSections(PREFIX, COMMON, Blocks())
end

---------------------------------------------------------------------------
-- The button, and staying current
---------------------------------------------------------------------------

BazUI:QueueForModule("Codex", function()
    Prime()
    Sync()

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    for _, event in ipairs({ "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_UPDATE_EVENT",
                             "CALENDAR_OPEN_EVENT" }) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    watcher:SetScript("OnEvent", function()
        Prime()
        Sync()
        if Codex.IsShown and Codex:IsShown() then
            Codex.Panel:RebuildTabs()
            Codex.Panel:QueueRefresh()
        end
    end)
end)
