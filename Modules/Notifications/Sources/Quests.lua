-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Quests: Quest accepted, completed, objective progress, and UI text suppression.
-- Events: QUEST_ACCEPTED, QUEST_TURNED_IN, QUEST_REMOVED, QUEST_LOG_UPDATE
-- ==========================================================================

local MODULE_ID = "quests"
local MODULE_NAME = "Quests"
local MODULE_ICON = "Interface\\Icons\\INV_Misc_Book_09"

local ICON_QUEST_COMPLETE = "Interface\\Icons\\Achievement_Quests_Completed_08"
local ICON_QUEST_ACCEPTED = "Interface\\Icons\\INV_Misc_Book_09"
local ICON_QUEST_PROGRESS = "Interface\\Icons\\INV_Scroll_02"

local objectiveCache = {}

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local function GetObjectiveKey(questID, objectiveIndex)
    return questID .. "_" .. objectiveIndex
end

local function CacheQuestObjectives(questID)
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if not objectives then return end

    for i, obj in ipairs(objectives) do
        local key = GetObjectiveKey(questID, i)
        objectiveCache[key] = {
            text = obj.text,
            numFulfilled = obj.numFulfilled,
            numRequired = obj.numRequired,
            finished = obj.finished,
        }
    end
end

-- Quest log access that works on Classic (GetQuestLogTitle and friends)
-- and Retail (C_QuestLog) alike.
local function NumLogEntries()
    if C_QuestLog.GetNumQuestLogEntries then return C_QuestLog.GetNumQuestLogEntries() end
    return GetNumQuestLogEntries()
end

local function LogIndexFor(questID)
    if C_QuestLog.GetLogIndexForQuestID then return C_QuestLog.GetLogIndexForQuestID(questID) end
    local index = GetQuestLogIndexByID and GetQuestLogIndexByID(questID)
    if index and index > 0 then return index end
    return nil
end

local function LogInfo(index)
    if C_QuestLog.GetInfo then return C_QuestLog.GetInfo(index) end
    local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
    if not title then return nil end
    return { title = title, isHeader = isHeader, questID = questID }
end

local function TitleFor(questID)
    if C_QuestLog.GetTitleForQuestID then return C_QuestLog.GetTitleForQuestID(questID) end
    if C_QuestLog.GetQuestInfo then return C_QuestLog.GetQuestInfo(questID) end
    return nil
end

local function CheckObjectiveProgress(questID)
    if GetSetting("showProgress") == false then return end

    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if not objectives then return end

    local logIndex = LogIndexFor(questID)
    local questInfo = logIndex and LogInfo(logIndex)
    local questTitle = questInfo and questInfo.title or "Quest"

    for i, obj in ipairs(objectives) do
        local key = GetObjectiveKey(questID, i)
        local cached = objectiveCache[key]

        if cached then
            local progressChanged = obj.numFulfilled ~= cached.numFulfilled
            local justCompleted = obj.finished and not cached.finished

            if justCompleted then
                if GetSetting("showObjectiveComplete") ~= false then
                    BNC:Push({
                        event = "progress",
                        module = MODULE_ID,
                        title = questTitle,
                        message = obj.text .. " (Complete!)",
                        icon = ICON_QUEST_COMPLETE,
                        priority = "normal",
                        duration = GetSetting("toastDuration") or 3,
                        silent = GetSetting("progressToasts") == false,
                    })
                end
            elseif progressChanged and obj.numRequired and obj.numRequired > 0 then
                BNC:Push({
                    event = "progress",
                    module = MODULE_ID,
                    title = questTitle,
                    message = obj.text,
                    icon = ICON_QUEST_PROGRESS,
                    priority = "low",
                    duration = GetSetting("toastDuration") or 3,
                    silent = GetSetting("progressToasts") == false,
                })
            end
        end

        objectiveCache[key] = {
            text = obj.text,
            numFulfilled = obj.numFulfilled,
            numRequired = obj.numRequired,
            finished = obj.finished,
        }
    end
end

local function OnQuestAccepted(event, questID)
    if GetSetting("showAccepted") == false then return end
    if not questID then return end

    local logIndex = LogIndexFor(questID)
    local questInfo = logIndex and LogInfo(logIndex)
    local questTitle = questInfo and questInfo.title

    if not questTitle then
        questTitle = TitleFor(questID) or "New Quest"
    end

    CacheQuestObjectives(questID)

    BNC:Push({
        event = "accepted",
        module = MODULE_ID,
        title = "Quest Accepted",
        message = questTitle,
        icon = ICON_QUEST_ACCEPTED,
        priority = "normal",
        duration = GetSetting("toastDuration") or 4,
        silent = GetSetting("acceptedToasts") == false,
    })
end

local function OnQuestTurnedIn(event, questID)
    if GetSetting("showCompleted") == false then return end
    if not questID then return end

    local questTitle = TitleFor(questID) or "Quest"

    -- Clean up objective cache for this quest
    for key in pairs(objectiveCache) do
        if BNC.SafeMatch(key, "^" .. questID .. "_") then
            objectiveCache[key] = nil
        end
    end

    BNC:Push({
        event = "completed",
        module = MODULE_ID,
        title = "Quest Completed",
        message = questTitle,
        icon = ICON_QUEST_COMPLETE,
        priority = "high",
        duration = GetSetting("toastDuration") or 5,
        silent = GetSetting("completedToasts") == false,
    })
end

local function OnQuestRemoved(event, questID, wasReplayQuest)
    for key in pairs(objectiveCache) do
        if BNC.SafeMatch(key, "^" .. questID .. "_") then
            objectiveCache[key] = nil
        end
    end
end

local function OnQuestObjectiveUpdate(event)
    for i = 1, NumLogEntries() do
        local info = LogInfo(i)
        if info and not info.isHeader and info.questID then
            CheckObjectiveProgress(info.questID)
        end
    end
end

local function InitializeCache()
    wipe(objectiveCache)
    for i = 1, NumLogEntries() do
        local info = LogInfo(i)
        if info and not info.isHeader and info.questID then
            CacheQuestObjectives(info.questID)
        end
    end
end

-- Suppress default quest progress text from UIErrorsFrame
-- Only hook if BNC-System is NOT installed (it handles all UIErrorsFrame messages)
local uiErrorsHooked = false

local function SetupQuestTextSuppression()
    if GetSetting("hideDefaultText") == false then return end
    if uiErrorsHooked then return end
    if BNC:IsModuleEnabled("system") then return end

    uiErrorsHooked = true

    local origAddMessage = UIErrorsFrame.AddMessage
    UIErrorsFrame.AddMessage = function(self, msg, r, g, b, ...)
        if GetSetting("hideDefaultText") ~= false and msg then
            -- Suppress quest objective progress patterns like "Something: 1/3"
            if BNC.SafeMatch(msg, "%d+/%d+") or BNC.SafeMatch(msg, ": %d+/%d+") then
                return
            end
        end
        return origAddMessage(self, msg, r, g, b, ...)
    end
end

-- Event frame
local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_REMOVED")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, InitializeCache)
        SetupQuestTextSuppression()
    elseif event == "QUEST_ACCEPTED" then
        OnQuestAccepted(event, ...)
        local questID = ...
        if questID then
            C_Timer.After(0.5, function() CacheQuestObjectives(questID) end)
        end
    elseif event == "QUEST_TURNED_IN" then
        OnQuestTurnedIn(event, ...)
    elseif event == "QUEST_REMOVED" then
        OnQuestRemoved(event, ...)
    elseif event == "QUEST_LOG_UPDATE" then
        OnQuestObjectiveUpdate(event)
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { type = "event", key = "accepted",  label = "Quest accepted",     show = "showAccepted",  toast = "acceptedToasts" },
    { type = "event", key = "completed", label = "Quest completed",    show = "showCompleted", toast = "completedToasts" },
    { type = "event", key = "progress",  label = "Objective progress", show = { "showProgress", "showObjectiveComplete" }, toast = "progressToasts" },
    { key = "toastDuration",    label = "Toast duration", type = "slider", default = 4, min = 1, max = 15, step = 1 },
    { key = "hideDefaultText", label = "Hide Blizzard's progress text", type = "toggle", default = true, section = "blizzard" },
})
