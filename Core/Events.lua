-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Events Module
-- Unified WoW event + custom event system
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

-- [eventName] = { { owner = addonName, fn = handler }, ... }
--
-- A list rather than a map keyed by owner. It used to be the map, which
-- silently allowed one handler per owner per event - and every global
-- listener registers under the owner "BazUI", so the second thing in the
-- addon to care about a given event threw the first one away without a
-- word. Edit Mode's layout dropdown and the skin both want to hear about
-- a profile change; under the old shape, whichever loaded last won.
local handlers = {}

---------------------------------------------------------------------------
-- Event Frame Dispatch
---------------------------------------------------------------------------

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, entry in ipairs(list) do
        entry.fn(event, ...)
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
    handlers[event][#handlers[event] + 1] = { owner = owner, fn = handler }
end

local function UnregisterAll(owner)
    -- Collect events to clean up first, then modify (safe iteration)
    local toRemove = {}
    for event, list in pairs(handlers) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then table.remove(list, i) end
        end
        if #list == 0 then
            toRemove[#toRemove + 1] = event
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


-- Fire a custom event to all listeners
function BazUI:Fire(event, ...)
    local list = handlers[event]
    if not list then return end
    for _, entry in ipairs(list) do
        entry.fn(event, ...)
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


-- Unregister all events for this addon
function AddonMixin:OffAll()
    UnregisterAll(self.name)
end
