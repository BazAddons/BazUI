-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BNC: Do Not Disturb
-- Suppresses toasts and sounds when active.
-- Can be toggled manually or auto-enabled in combat / rated instances.
---------------------------------------------------------------------------
local addon = BazUI.Notifications
local BNC = addon.API

-- Runtime DND state (not saved - auto-DND resets on combat/instance end)
addon.dndActive = false

--- Check whether DND is currently in effect (manual toggle OR auto-triggered).
function addon.IsDND()
    if addon.db and addon.db.dndEnabled then return true end
    return addon.dndActive
end

--- Toggle manual DND on/off. Persists across sessions via saved variable.
function BNC:ToggleDND(state)
    if not addon.db then return end
    if state ~= nil then
        addon.db.dndEnabled = state
    else
        addon.db.dndEnabled = not addon.db.dndEnabled
    end
    addon.Events:Trigger("SETTING_CHANGED", "dndEnabled", addon.db.dndEnabled)
    addon.Events:Trigger("SETTING_CHANGED_dndEnabled", addon.db.dndEnabled)

    local status = addon.db.dndEnabled and "ON" or "OFF"
    print("|cff00aaff[BNC]|r Do Not Disturb: " .. status)
end

function BNC:IsDND()
    return addon.IsDND()
end

-- Auto-DND via BazUI events (registered after CORE_LOADED)
addon.Events:Register("CORE_LOADED", function()
    if not addon.bncAddon then return end

    addon.bncAddon:On({
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "ENCOUNTER_START", "ENCOUNTER_END",
    }, function(event)
        if event == "PLAYER_REGEN_DISABLED" then
            if addon.db and addon.db.dndAutoCombat then addon.dndActive = true end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if addon.db and addon.db.dndAutoCombat then addon.dndActive = false end
        elseif event == "ENCOUNTER_START" then
            if addon.db and addon.db.dndAutoInstance then addon.dndActive = true end
        elseif event == "ENCOUNTER_END" then
            if addon.db and addon.db.dndAutoInstance then addon.dndActive = false end
        end
    end)
end)
