-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BNC: Database Helpers
-- SV lifecycle managed by BazUI:RegisterModule() in Init.lua
---------------------------------------------------------------------------
local addon = BazUI.Notifications

-- Public getter/setter that triggers change events
function addon.SetDBValue(key, value)
    if addon.db then
        addon.db[key] = value
        addon.Events:Trigger("SETTING_CHANGED", key, value)
        addon.Events:Trigger("SETTING_CHANGED_" .. key, value)
    end
end

function addon.GetDBValue(key)
    if addon.db then
        return addon.db[key]
    end
end
