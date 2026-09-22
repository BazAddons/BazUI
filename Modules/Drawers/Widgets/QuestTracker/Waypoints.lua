-- SPDX-License-Identifier: GPL-2.0-or-later
-- QuestTracker: Waypoint Integrations (TomTom + Zygor)
-- Sets a waypoint arrow to the super-tracked quest's next objective
-- via TomTom and/or Zygor when installed. Each integration is
-- independently toggleable via the Quest Tracker's Integrations
-- settings. Silent no-op when the addon isn't installed.

local addon = BazUI:GetModule("Drawers")
if not addon then return end
local QT = addon.QT
local C  = QT.C

local currentTomTomUID = nil

function QT.HasTomTom()
    return _G.TomTom and type(_G.TomTom.AddWaypoint) == "function"
end

---------------------------------------------------------------------------
-- TomTom's coordinate block
--
-- The little readout of where you are standing. Useful to some people and
-- permanently in the way for everybody else, and TomTom's own switch for
-- it is several clicks into a different addon's options.
--
-- Hidden through BazUI.SuppressFrame rather than by writing to TomTom's
-- settings. Reaching into another addon's saved variables to change its
-- mind is not ours to do - it would fight the next time TomTom wrote its
-- own config, and it would leave a change behind that survives BazUI
-- being uninstalled. Suppression hooks the frame's OnShow and puts it
-- back down; turn this off and TomTom's block returns exactly as TomTom
-- left it.
--
-- TomTomBlock is built the first time TomTom wants it rather than at
-- load, so a straight lookup at login finds nothing. Hence the retry: it
-- only runs while the setting is on and it gives up rather than waiting
-- forever on an addon that may simply not be installed.
---------------------------------------------------------------------------

local hideBlock = false

function QT.ApplyTomTomBlock(attempt)
    hideBlock = addon:GetWidgetSetting(C.WIDGET_ID, "tomtomHideBlock", false) == true

    local block = _G.TomTomBlock
    if not block then
        attempt = (attempt or 0) + 1
        if hideBlock and attempt <= 10 then
            C_Timer.After(1, function() QT.ApplyTomTomBlock(attempt) end)
        end
        return
    end

    BazUI.SuppressFrame(block, function() return hideBlock end)
end

-- Exported on QT so Zygor integration can reuse it
function QT.ResolveQuestWaypoint(questID)
    if not questID or questID == 0 then return nil end

    if C_QuestLog.GetNextWaypoint then
        local mapID, x, y = C_QuestLog.GetNextWaypoint(questID)
        if mapID and x and y then
            return mapID, x, y
        end
    end

    local uiMapID = GetQuestUiMapID and GetQuestUiMapID(questID)
    if uiMapID and uiMapID > 0 and C_QuestLog.GetQuestsOnMap then
        local quests = C_QuestLog.GetQuestsOnMap(uiMapID)
        if quests then
            for _, info in ipairs(quests) do
                if info.questID == questID and info.x and info.y then
                    return uiMapID, info.x, info.y
                end
            end
        end
    end

    return nil
end

function QT.RemoveActiveWaypoint()
    if currentTomTomUID and _G.TomTom and type(_G.TomTom.RemoveWaypoint) == "function" then
        pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, currentTomTomUID)
    end
    currentTomTomUID = nil
end

function QT.SetTomTomForQuest(questID)
    if not QT.HasTomTom() then return end
    if not addon:GetWidgetSetting(C.WIDGET_ID, "tomtomEnabled", true) then return end

    QT.RemoveActiveWaypoint()

    if not questID or questID == 0 then return end

    local mapID, x, y = QT.ResolveQuestWaypoint(questID)
    if not (mapID and x and y) then return end

    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID) or ""

    local ok, uid = pcall(_G.TomTom.AddWaypoint, _G.TomTom, mapID, x, y, {
        title       = title,
        from        = "BazUI",
        silent      = true,
        persistent  = false,
        minimap     = true,
        world       = true,
        crazy       = true,
    })
    if ok then currentTomTomUID = uid end
end

---------------------------------------------------------------------------
-- Zygor integration
--
-- Uses ZGV.Pointer:SetWaypoint(mapID, x, y, data, showArrow) to set
-- Zygor's navigation arrow to the super-tracked quest's next objective.
-- Same trigger as TomTom - fires on SUPER_TRACKING_CHANGED.
---------------------------------------------------------------------------

function QT.HasZygor()
    return _G.ZGV and _G.ZGV.Pointer and type(_G.ZGV.Pointer.SetWaypoint) == "function"
end

function QT.SetZygorForQuest(questID)
    if not QT.HasZygor() then return end
    if not addon:GetWidgetSetting(C.WIDGET_ID, "zygorEnabled", true) then return end

    if not questID or questID == 0 then return end

    local mapID, x, y = QT.ResolveQuestWaypoint(questID)
    if not (mapID and x and y) then return end

    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID) or ""

    pcall(_G.ZGV.Pointer.SetWaypoint, _G.ZGV.Pointer, mapID, x, y, {
        title    = title,
        arrow    = true,
        findpath = true,
        type     = "manual",
    }, true)
end

---------------------------------------------------------------------------
-- Super-track change handler (fires both TomTom + Zygor)
---------------------------------------------------------------------------

function QT.OnSuperTrackChanged()
    local qid = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
        and C_SuperTrack.GetSuperTrackedQuestID() or 0
    QT.SetTomTomForQuest(qid)
    QT.SetZygorForQuest(qid)
end
