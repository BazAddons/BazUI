-- SPDX-License-Identifier: GPL-2.0-or-later
-- ==========================================================================
-- ModuleHelpers: Convenience APIs for module developers.
-- Provides BNC:Listen(), BNC:OnChatMessage(), and the notification builder.
-- ==========================================================================
local addon = BazUI.Notifications
local BNC = addon.API

-- ---------------------------------------------------------------------------
-- BNC:Listen(events, handler)
-- Registers WoW events without manual CreateFrame/RegisterEvent boilerplate.
-- Accepts a single event string or an array of events.
-- Returns a control table with :Unregister() and :UnregisterAll().
--
-- Usage:
--   local listener = BNC:Listen("QUEST_ACCEPTED", function(event, questID) ... end)
--   local listener = BNC:Listen({"ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA"}, handler)
--   listener:Unregister("ZONE_CHANGED")  -- stop one event
--   listener:UnregisterAll()              -- stop all
-- ---------------------------------------------------------------------------

-- Shared event frame for all BNC:Listen() calls (one frame, many handlers)
local listenerFrame = CreateFrame("Frame")
local listenerHandlers = {}  -- [event] = { handler1, handler2, ... }

listenerFrame:SetScript("OnEvent", function(self, event, ...)
    local handlers = listenerHandlers[event]
    if not handlers then return end
    for i = 1, #handlers do
        addon.SafeCall(handlers[i], event, ...)
    end
end)

function BNC:Listen(events, handler)
    if not handler then return end

    -- Normalize to array
    if type(events) == "string" then
        events = { events }
    end

    local registered = {}

    for _, event in ipairs(events) do
        -- pcall in case event doesn't exist in this WoW version
        local ok = pcall(function() listenerFrame:RegisterEvent(event) end)
        if ok then
            if not listenerHandlers[event] then
                listenerHandlers[event] = {}
            end
            table.insert(listenerHandlers[event], handler)
            registered[event] = true
        end
    end

    -- Return control object
    local control = {}

    function control:Unregister(event)
        local handlers = listenerHandlers[event]
        if not handlers then return end
        for i = #handlers, 1, -1 do
            if handlers[i] == handler then
                table.remove(handlers, i)
            end
        end
        if #handlers == 0 then
            listenerHandlers[event] = nil
            pcall(function() listenerFrame:UnregisterEvent(event) end)
        end
        registered[event] = nil
    end

    function control:UnregisterAll()
        for event in pairs(registered) do
            self:Unregister(event)
        end
    end

    return control
end

-- ---------------------------------------------------------------------------
-- BNC:OnChatMessage(event, pattern, handler)
-- Registers a chat event listener that automatically SafeMatches the message
-- against the pattern and passes the captures to the handler.
-- Eliminates taint-handling boilerplate in modules.
--
-- Usage:
--   BNC:OnChatMessage("CHAT_MSG_LOOT", "You receive loot: (.+)", function(event, msg, itemLink)
--       -- itemLink is the first capture from the pattern
--   end)
--
--   -- Multiple patterns:
--   BNC:OnChatMessage("CHAT_MSG_SYSTEM", {
--       { pattern = "A buyer has been found for your auction of (.+)", handler = OnSold },
--       { pattern = "Your auction of (.+) has expired",               handler = OnExpired },
--   })
-- ---------------------------------------------------------------------------

function BNC:OnChatMessage(event, patternOrList, handler)
    if type(patternOrList) == "string" then
        -- Single pattern + handler
        return BNC:Listen(event, function(evt, msg, ...)
            if not msg then return end
            local c1, c2, c3, c4, c5 = BNC.SafeMatch(msg, patternOrList)
            if c1 then
                handler(evt, msg, c1, c2, c3, c4, c5)
            end
        end)
    elseif type(patternOrList) == "table" then
        -- Array of { pattern, handler } entries - tries each in order
        return BNC:Listen(event, function(evt, msg, ...)
            if not msg then return end
            for _, entry in ipairs(patternOrList) do
                local c1, c2, c3, c4, c5 = BNC.SafeMatch(msg, entry.pattern)
                if c1 then
                    entry.handler(evt, msg, c1, c2, c3, c4, c5)
                    return  -- first match wins
                end
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- BNC:NewNotification(moduleId)
-- Chainable builder for constructing notifications with validation.
-- Provides a cleaner API than raw table construction.
--
-- Usage:
--   BNC:NewNotification("loot")
--       :title("|cff0070ddBlade of Valor|r")
--       :icon("Interface\\Icons\\INV_Sword_39")
--       :priority("high")
--       :itemLink(link)
--       :duration(5)
--       :send()
-- ---------------------------------------------------------------------------

local NotificationBuilder = {}
NotificationBuilder.__index = NotificationBuilder

function NotificationBuilder:title(text)
    self._data.title = text
    return self
end

function NotificationBuilder:message(text)
    self._data.message = text
    return self
end

function NotificationBuilder:icon(path)
    self._data.icon = path
    return self
end

function NotificationBuilder:priority(level)
    self._data.priority = level
    return self
end

function NotificationBuilder:duration(seconds)
    self._data.duration = seconds
    return self
end

function NotificationBuilder:silent(flag)
    self._data.silent = flag ~= false
    return self
end

function NotificationBuilder:itemLink(link)
    self._data.itemLink = link
    return self
end

function NotificationBuilder:waypoint(mapID, x, y, wpTitle)
    self._data.waypoint = {
        mapID = mapID,
        x = x,
        y = y,
        title = wpTitle,
    }
    return self
end

function NotificationBuilder:onClick(callback)
    self._data.onClick = callback
    return self
end

function NotificationBuilder:send()
    -- Validate required fields
    if not self._data.module then
        error("BNC notification builder: module is required")
        return nil
    end
    if not self._data.title or self._data.title == "" then
        error("BNC notification builder: title is required")
        return nil
    end

    -- Validate priority
    local validPriorities = { low = true, normal = true, high = true }
    if self._data.priority and not validPriorities[self._data.priority] then
        print("|cffff4444[BNC]|r Warning: invalid priority '" .. tostring(self._data.priority) .. "', using 'normal'")
        self._data.priority = "normal"
    end

    -- Validate duration
    if self._data.duration and (type(self._data.duration) ~= "number" or self._data.duration <= 0) then
        print("|cffff4444[BNC]|r Warning: invalid duration, using default")
        self._data.duration = nil
    end

    return BNC:Push(self._data)
end

function BNC:NewNotification(moduleId)
    local builder = setmetatable({}, NotificationBuilder)
    builder._data = { module = moduleId }
    return builder
end
