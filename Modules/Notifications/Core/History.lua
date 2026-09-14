-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BNC: History
-- Persistent notification history organized by date
---------------------------------------------------------------------------
local addon = BazUI.Notifications

-- History is stored in BazUIDB.notifications.history = { days = {}, dayIndex = {} }
-- Initialized after ADDON_LOADED in Database.lua

local function GetDateKey(timestamp)
    return date("%Y-%m-%d", timestamp)
end

local function GetHistory()
    local sv = BazUIDB and BazUIDB.notifications
    if not sv then return nil end
    if not sv.history then
        sv.history = { days = {}, dayIndex = {} }
    end
    return sv.history
end

local function RebuildDayIndex()
    local history = GetHistory()
    if not history then return end
    wipe(history.dayIndex)
    for dateKey in pairs(history.days) do
        table.insert(history.dayIndex, dateKey)
    end
    table.sort(history.dayIndex, function(a, b) return a > b end)
end

-- Called by Notifications.lua to persist new entries
function addon.History_AppendEntries(entries)
    if not entries or #entries == 0 then return end
    local history = GetHistory()
    if not history then return end

    for _, entry in ipairs(entries) do
        local dateKey = GetDateKey(entry.realTime or time())
        if not history.days[dateKey] then
            history.days[dateKey] = {}
        end
        table.insert(history.days[dateKey], 1, entry)
    end

    RebuildDayIndex()

    -- Trim on append so a long-running session doesn't grow unbounded
    local retention = addon.db and addon.db.historyRetentionDays or 7
    addon.History_Trim(retention)
end

function addon.History_GetDay(dateKey)
    local history = GetHistory()
    if not history then return {} end
    return history.days[dateKey] or {}
end

function addon.History_GetDayIndex()
    local history = GetHistory()
    if not history then return {} end
    if #history.dayIndex == 0 then
        RebuildDayIndex()
    end
    return history.dayIndex
end

function addon.History_GetRange(startDate, endDate)
    local results = {}
    local dayIndex = addon.History_GetDayIndex()
    local history = GetHistory()
    if not history then return results end

    for _, dateKey in ipairs(dayIndex) do
        if dateKey >= startDate and dateKey <= endDate then
            local dayEntries = history.days[dateKey] or {}
            for _, entry in ipairs(dayEntries) do
                table.insert(results, entry)
            end
        end
    end

    return results
end

function addon.History_Search(query, moduleFilter, startDate, endDate)
    local dayIndex = addon.History_GetDayIndex()
    local history = GetHistory()
    if not history then return {} end

    local results = {}
    local queryLower = query and query:lower() or nil

    for _, dateKey in ipairs(dayIndex) do
        if startDate and dateKey < startDate then break end
        if not endDate or dateKey <= endDate then
            local dayEntries = history.days[dateKey] or {}
            for _, entry in ipairs(dayEntries) do
                local passModule = not moduleFilter or entry.module == moduleFilter
                local passText = true
                if queryLower and queryLower ~= "" then
                    local title = (entry.title or ""):lower()
                    local message = (entry.message or ""):lower()
                    local module = (entry.module or ""):lower()
                    passText = title:find(queryLower, 1, true)
                        or message:find(queryLower, 1, true)
                        or module:find(queryLower, 1, true)
                end
                if passModule and passText then
                    table.insert(results, entry)
                end
            end
        end
    end

    return results
end

function addon.History_GetTotalCount()
    local history = GetHistory()
    if not history then return 0 end
    local count = 0
    for _, entries in pairs(history.days) do
        count = count + #entries
    end
    return count
end

function addon.History_PurgeAll()
    local history = GetHistory()
    if not history then return end
    wipe(history.days)
    wipe(history.dayIndex)
end

---------------------------------------------------------------------------
-- Retention
--
-- Deletes day buckets older than `days` days ago. Called at login and
-- after each append so memory usage stays bounded. Without this, the
-- history table grows forever and can reach many MB.
---------------------------------------------------------------------------

function addon.History_Trim(days)
    if not days or days <= 0 then return 0 end
    local history = GetHistory()
    if not history or not history.days then return 0 end

    local cutoff = date("%Y-%m-%d", time() - days * 86400)
    local removed = 0
    for dateKey in pairs(history.days) do
        if dateKey < cutoff then
            history.days[dateKey] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then
        RebuildDayIndex()
    end
    return removed
end

function addon.History_GetModules()
    local history = GetHistory()
    if not history then return {} end
    local modules = {}
    for _, entries in pairs(history.days) do
        for _, entry in ipairs(entries) do
            if entry.module and not modules[entry.module] then
                modules[entry.module] = true
            end
        end
    end
    return modules
end

-- Also set globals so the old API calls (BNC_History_*) still work
-- and the panel/notifications code doesn't need rewriting
BNC_History_AppendEntries = function(entries) addon.History_AppendEntries(entries) end
BNC_History_Search = function(...) return addon.History_Search(...) end
BNC_History_PurgeAll = function() addon.History_PurgeAll() end
BNC_History_GetDay = function(dateKey) return addon.History_GetDay(dateKey) end
BNC_History_GetDayIndex = function() return addon.History_GetDayIndex() end
BNC_History_GetRange = function(...) return addon.History_GetRange(...) end
BNC_History_GetTotalCount = function() return addon.History_GetTotalCount() end
BNC_History_GetModules = function() return addon.History_GetModules() end
