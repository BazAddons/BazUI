-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Events Module
-- Unified WoW event + custom event system
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}  -- [eventName] = { [addonName] = handler }

---------------------------------------------------------------------------
-- Event Frame Dispatch
---------------------------------------------------------------------------

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, handler in pairs(list) do
        handler(event, ...)
    end
end)

---------------------------------------------------------------------------
-- Internal Registration
---------------------------------------------------------------------------

local function RegisterHandler(owner, event, handler)
    if not handlers[event] then
        handlers[event] = {}
        -- Attempt to register as WoW event; silently fails for custom events
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    handlers[event][owner] = handler
end

local function UnregisterHandler(owner, event)
    local list = handlers[event]
    if not list then return end
    list[owner] = nil
    -- If no handlers remain, unregister from frame
    if not next(list) then
        pcall(eventFrame.UnregisterEvent, eventFrame, event)
        handlers[event] = nil
    end
end

local function UnregisterAll(owner)
    -- Collect events to clean up first, then modify (safe iteration)
    local toRemove = {}
    for event, list in pairs(handlers) do
        if list[owner] then
            list[owner] = nil
            if not next(list) then
                toRemove[#toRemove + 1] = event
            end
        end
    end
    for _, event in ipairs(toRemove) do
        pcall(eventFrame.UnregisterEvent, eventFrame, event)
        handlers[event] = nil
    end
end

---------------------------------------------------------------------------
-- BazUI-level API
---------------------------------------------------------------------------

-- Listen for an event globally (not tied to an addon)
function BazUI:On(event, handler)
    if type(event) == "table" then
        for _, e in ipairs(event) do
            RegisterHandler("BazUI", e, handler)
        end
    else
        RegisterHandler("BazUI", event, handler)
    end
end

function BazUI:Off(event)
    if type(event) == "table" then
        for _, e in ipairs(event) do
            UnregisterHandler("BazUI", e)
        end
    else
        UnregisterHandler("BazUI", event)
    end
end

-- Fire a custom event to all listeners
function BazUI:Fire(event, ...)
    local list = handlers[event]
    if not list then return end
    for _, handler in pairs(list) do
        handler(event, ...)
    end
end

---------------------------------------------------------------------------
-- AddonMixin: per-addon event methods
---------------------------------------------------------------------------

local AddonMixin = BazUI.AddonMixin

function AddonMixin:On(event, handler)
    if type(event) == "table" then
        for _, e in ipairs(event) do
            self:On(e, handler)
        end
        return
    end

    -- Support string method names: addon:On("EVENT", "MethodName")
    -- Resolves to self[methodName] at call time (late binding)
    if type(handler) == "string" then
        local methodName = handler
        local addonObj = self
        handler = function(evt, ...)
            local fn = addonObj[methodName]
            if fn then fn(addonObj, evt, ...) end
        end
    end

    RegisterHandler(self.name, event, handler)
end

function AddonMixin:Off(event)
    if type(event) == "table" then
        for _, e in ipairs(event) do
            UnregisterHandler(self.name, e)
        end
    else
        UnregisterHandler(self.name, event)
    end
end

-- Unregister all events for this addon
function AddonMixin:OffAll()
    UnregisterAll(self.name)
end
