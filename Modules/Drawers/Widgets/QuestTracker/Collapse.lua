-- SPDX-License-Identifier: GPL-2.0-or-later
-- QuestTracker: Group Collapse State
-- Per-group collapse tracking, persisted via widgetSettings.

local addon = BazUI:GetModule("Drawers")
if not addon then return end
local QT = addon.QT
local C  = QT.C

function QT.GetCollapsedMap()
    return addon:GetWidgetSetting(C.WIDGET_ID, "groupsCollapsed", nil) or {}
end

function QT.IsGroupCollapsed(label)
    local map = QT.GetCollapsedMap()
    return map[label] and true or false
end

function QT.SetGroupCollapsed(label, val)
    local map = QT.GetCollapsedMap()
    if val then
        map[label] = true
    else
        map[label] = nil
    end
    addon:SetWidgetSetting(C.WIDGET_ID, "groupsCollapsed", map)
end
