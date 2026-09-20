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
    -- A world event, not a clock: Today already wears the pocket watch.
    tabIcon  = "Interface\\Icons\\Achievement_WorldEvent_Lunar",
}
local PREFIX = "evt."


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

-- One of the game's own holidays, rather than somebody's raid night?
-- Worked out from the enum's own key names rather than from numbers,
-- which differ between clients. It is only used to mark a row: on this
-- calendar nearly everything is a holiday, so filing by it would put
-- every event in one pile and leave the rest empty.
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

---------------------------------------------------------------------------
-- What a holiday is, in its own words
--
-- The calendar keeps a description for every holiday it runs, and
-- hands it over for the day and index the event sits at. Its banner is
-- not taken: those pictures are the decorative border of a day cell
-- rather than a scene, and a border behind a paragraph is a mess. The
-- event's own icon is the picture worth having.
---------------------------------------------------------------------------

local function HolidayInfo(entry)
    if not (C_Calendar and C_Calendar.GetHolidayInfo) then return nil end
    local ok, info = pcall(C_Calendar.GetHolidayInfo,
        entry.monthOffset, entry.day, entry.index)
    if not (ok and info) then return nil end
    return info
end

-- A date the way the game writes one.
local function ShortDate(t)
    if not (t and t.monthDay and t.month) then return nil end
    if FormatShortDate then
        local ok, text = pcall(FormatShortDate, t.monthDay, t.month)
        if ok and text then return text end
    end
    return ("%d/%d"):format(t.month, t.monthDay)
end

-- An event's own words for when it is.
local function When(e, offsetDays)
    if offsetDays == 0 then
        if e.sequenceType == "START" then return "starts today" end
        if e.sequenceType == "END" then return "ends today" end
        if e.sequenceType == "ONGOING" then return "running now" end
        return "today"
    end
    if offsetDays == 1 then return "tomorrow" end
    return ("in %d days"):format(offsetDays)
end

---------------------------------------------------------------------------
-- Gathering
--
-- From today to the end of the month, and never less than a fortnight,
-- so the page does not empty out on the 29th. A run of days is one
-- event, not one per day: the calendar numbers the days of a run, and
-- anything past the first is the same thing still going.
---------------------------------------------------------------------------

local MIN_DAYS = 14

local function Gather()
    local now = Today()
    if not (now and HasCalendar()) then return nil end

    local numDays = 31
    local ok, month = pcall(C_Calendar.GetMonthInfo, 0)
    if ok and month and month.numDays then numDays = month.numDays end

    local toMonthEnd = numDays - now.monthDay
    local span = math.max(toMonthEnd, MIN_DAYS)
    local spills = span > toMonthEnd

    local today, soon = {}, {}
    local started = {}
    for offset = 0, span do
        local day, monthOffset = now.monthDay + offset, 0
        if day > numDays then
            day = day - numDays
            monthOffset = 1
        end
        for i, e in ipairs(DayEvents(day, monthOffset)) do
            -- Day two of a run is the same event still going.
            local later = e.sequenceIndex and e.sequenceIndex > 1
            local key = (e.title or "?") .. "|" .. tostring(e.eventType or "")
            if not later and not started[key] then
                started[key] = true
                local row = {
                    event = e, offset = offset, day = day, monthOffset = monthOffset,
                    index = i, holiday = IsHoliday(e),
                }
                if offset == 0 then today[#today + 1] = row else soon[#soon + 1] = row end
            end
        end
    end
    return { today = today, soon = soon, now = now, spills = spills }
end

local function Row(entry)
    local e = entry.event
    local lines = { e.title }
    local info = entry.holiday and HolidayInfo(entry) or nil

    if info and info.startTime and info.endTime then
        local from, to = ShortDate(info.startTime), ShortDate(info.endTime)
        if from and to then lines[#lines + 1] = "Runs\t" .. from .. " to " .. to end
    end
    if e.difficultyName and e.difficultyName ~= "" then
        lines[#lines + 1] = "Difficulty\t" .. e.difficultyName
    end
    if info and info.description and info.description ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = info.description
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Click to open the calendar on this day."
    return {
        icon   = e.iconTexture,
        label  = e.title,
        detail = When(e, entry.offset),
        state  = entry.offset == 0 and "open" or nil,
        muted  = entry.offset > 7 or nil,
        tip    = table.concat(lines, "|n"),
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

    -- The holiday that is on, or the next one, told properly: its
    -- banner behind it, its own words under the heading, and when it
    -- ends. The rest of the page counts; this one says.
    local featured
    for _, entry in ipairs(data.today) do
        if entry.holiday then featured = entry break end
    end
    if not featured then
        for _, entry in ipairs(data.soon) do
            if entry.holiday then featured = entry break end
        end
    end

    local blocks = {}

    if featured then
        local info = HolidayInfo(featured)
        local name = (info and info.name) or featured.event.title
        local when = When(featured.event, featured.offset)
        local runs
        if info and info.startTime and info.endTime then
            local from, to = ShortDate(info.startTime), ShortDate(info.endTime)
            if from and to then runs = from .. " to " .. to end
        end
        blocks[#blocks + 1] = {
            key     = "featured",
            title   = name,
            column  = 1,
            -- The event's own picture, blown up and faded against the
            -- right edge. The calendar's banners are the decorative
            -- border of a day cell rather than a scene, which is not
            -- something to put behind text.
            art       = featured.event.iconTexture,
            artSquare = true,
            artAlpha  = 0.25,
            blurb   = (info and info.description ~= "" and info.description) or nil,
            GetRows = function()
                local rows = {}
                rows[#rows + 1] = {
                    icon   = featured.event.iconTexture,
                    label  = featured.offset == 0 and "On now" or "Starts",
                    detail = when,
                    state  = featured.offset == 0 and "open" or nil,
                }
                if runs then
                    rows[#rows + 1] = { label = "Runs", detail = runs, muted = true }
                end
                rows[#rows + 1] = {
                    label   = "Open the calendar",
                    detail  = "go",
                    muted   = true,
                    onClick = function() OpenCalendar(featured.monthOffset, featured.day) end,
                    tip     = "Click to open the game's calendar on this day.",
                }
                return rows
            end,
        }
    end

    blocks[#blocks + 1] = {
            key    = "today",
            title  = "Today",
            column = 1,
            empty  = "Nothing on today.",
            GetRows = function()
                local d = Gather()
                return d and Rows(d.today) or {}
            end,
            GetHighlight = function()
                local d = Gather()
                local n = d and #d.today or 0
                return {
                    value = n,
                    label = n == 1 and "event on today" or "events on today",
                    color = n > 0 and Theme.colors.gold or nil,
                }
            end,
        }

    blocks[#blocks + 1] = {
            -- Named for what it actually covers: the rest of this month,
            -- or "coming up" once that is a short enough stretch that the
            -- page reaches into the next one.
            key    = "soon",
            title  = data.spills and "Coming up" or "This month",
            column = 2,
            empty  = "Nothing else coming up.",
            GetRows = function()
                local d = Gather()
                return d and Rows(d.soon) or {}
            end,
            GetBar = function()
                local d = Gather()
                local n = d and #d.soon or 0
                if n == 0 then return nil end
                local holidays = 0
                for _, entry in ipairs(d.soon) do
                    if entry.holiday then holidays = holidays + 1 end
                end
                local text = ("%d coming"):format(n)
                if holidays > 0 then text = text .. ("  |  %d holiday%s"):format(
                    holidays, holidays == 1 and "" or "s") end
                return { text = text }
            end,
        }

    return blocks
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
