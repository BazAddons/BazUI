-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BNC: Internal CallbackRegistry
-- Custom event system for internal addon coordination
-- WoW events are handled by BazUI (addon.bncAddon:On())
---------------------------------------------------------------------------
local addon = BazUI.Notifications

local CallbackRegistry = {}
CallbackRegistry.__index = CallbackRegistry

function CallbackRegistry:New()
    return setmetatable({ callbacks = {} }, self)
end

function CallbackRegistry:Register(event, callback, owner)
    if not self.callbacks[event] then
        self.callbacks[event] = {}
    end
    table.insert(self.callbacks[event], { func = callback, owner = owner })
end

function CallbackRegistry:Unregister(event, callback)
    local list = self.callbacks[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].func == callback then
            table.remove(list, i)
            return
        end
    end
end

function CallbackRegistry:UnregisterAll(owner)
    for event, list in pairs(self.callbacks) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then
                table.remove(list, i)
            end
        end
    end
end

function CallbackRegistry:Trigger(event, ...)
    local list = self.callbacks[event]
    if not list then return end
    for i = 1, #list do
        local entry = list[i]
        addon.SafeCall(entry.func, ...)
    end
end

-- Create the global callback registry for internal BNC events
addon.Events = CallbackRegistry:New()
