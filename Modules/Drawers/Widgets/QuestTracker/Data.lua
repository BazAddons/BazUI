-- SPDX-License-Identifier: GPL-2.0-or-later
-- QuestTracker: Data Retrieval (Classic-family clients)
--
-- Classic Era has none of the systems the Retail data layer polls: no
-- C_QuestLog watch APIs, no super-tracking, scenarios, Challenge Mode,
-- world quests, bonus objectives, achievements or recipe tracking. BazUI
-- targets Classic-family clients only, so this is the tracker's only data
-- layer. It feeds the shared renderer the same
-- quest record shape from the legacy quest log API and stubs the rest so
-- Init.lua, Blocks.lua and Options.lua stay one codebase.
--
-- Legacy quest log API (all take a quest LOG INDEX, not a quest ID):
--   GetNumQuestWatches() / GetQuestIndexForWatch(i)   -- the watch list
--   GetQuestLogTitle(index) -> title, level, tag, isHeader, isCollapsed,
--                              isComplete (1 done / -1 failed / nil), ...,
--                              questID (8th)
--   GetNumQuestLeaderBoards(index) / GetQuestLogLeaderBoard(j, index)
--   GetQuestLogSpecialItemInfo(index), GetQuestLogCompletionText(index)
--   GetQuestLogIndexByID(questID)
-- C_QuestLog.GetQuestObjectives(questID) does exist on Era and returns the
-- same {text, type, finished, numFulfilled, numRequired} rows as Retail.

local addon = BazUI:GetModule("Drawers")
if not addon then return end
local QT = addon.QT

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function LogIndexFor(questID)
    if not questID then return nil end
    if GetQuestLogIndexByID then
        local idx = GetQuestLogIndexByID(questID)
        if idx and idx > 0 then return idx end
    end
    -- Fallback: scan the log. Cheap (a few dozen entries at most).
    local n = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    for i = 1, n do
        local _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
        if not isHeader and id == questID then return i end
    end
    return nil
end

local function ObjectivesFor(questID, logIndex)
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
        if ok and type(objs) == "table" then return objs end
    end
    -- Legacy leaderboard rows, shaped like C_QuestLog objectives.
    local out = {}
    if logIndex and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        for i = 1, (GetNumQuestLeaderBoards(logIndex) or 0) do
            local text, objType, finished = GetQuestLogLeaderBoard(i, logIndex)
            out[#out + 1] = {
                text     = text or "",
                type     = objType or "monster",
                finished = finished and true or false,
            }
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Tracked quest IDs
---------------------------------------------------------------------------

function QT.GetTrackedQuestIDs()
    local ids = {}
    local n = GetNumQuestWatches and GetNumQuestWatches() or 0
    for i = 1, n do
        local idx = GetQuestIndexForWatch and GetQuestIndexForWatch(i)
        if idx then
            local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(idx)
            if not isHeader and questID and questID > 0 then
                ids[#ids + 1] = questID
            end
        end
    end
    return ids
end

---------------------------------------------------------------------------
-- Classification: Classic has none, everything lands in "Quests".
---------------------------------------------------------------------------

function QT.GetQuestClassification()
    return nil
end

function QT.ClassificationGroup()
    return 5, "Quests"
end

---------------------------------------------------------------------------
-- Quest data builder - same record shape Data.lua produces on Retail.
---------------------------------------------------------------------------

function QT.GetQuestData(questID)
    local logIndex = LogIndexFor(questID)
    local title, level, isCompleteFlag, _
    if logIndex then
        title, level, _, _, _, isCompleteFlag = GetQuestLogTitle(logIndex)
    end
    title = title or ""

    local objectives = ObjectivesFor(questID, logIndex)

    -- GetQuestLogTitle reports 1 for complete and -1 for failed.
    local isComplete = (isCompleteFlag == 1)
    if not isComplete and IsQuestComplete then
        local ok, done = pcall(IsQuestComplete, questID)
        if ok and done then isComplete = true end
    end

    local specialItem, specialItemCharges
    if logIndex and GetQuestLogSpecialItemInfo then
        local ok, _, item, charges = pcall(GetQuestLogSpecialItemInfo, logIndex)
        if ok and item then
            specialItem        = item
            specialItemCharges = charges
        end
    end

    -- Auto-complete (turn in from anywhere) barely exists on Era, but the
    -- API is present on some Classic clients, so honour it when it is.
    local isAutoComplete = false
    if logIndex and GetQuestLogIsAutoComplete then
        local ok, auto = pcall(GetQuestLogIsAutoComplete, logIndex)
        if ok and auto then isAutoComplete = true end
    end

    local completionText
    if isComplete and not isAutoComplete and logIndex and GetQuestLogCompletionText then
        local ok, text = pcall(GetQuestLogCompletionText, logIndex)
        if ok and type(text) == "string" and text ~= "" then completionText = text end
    end

    return {
        kind               = "quest",
        id                 = questID,
        title              = title,
        level              = level,
        objectives         = objectives,
        isComplete         = isComplete,
        isAutoComplete     = isAutoComplete,
        completionText     = completionText,
        classification     = nil,
        progressBarPct     = nil,
        questLogIndex      = logIndex,
        specialItem        = specialItem,
        specialItemCharges = specialItemCharges,
    }
end

---------------------------------------------------------------------------
-- Retail-only feeds, stubbed so Init.lua and Options.lua stay shared.
-- (QT.GetWorldQuests / QT.GetTrackedRecipes are deliberately left nil;
-- Init.lua checks for their existence before calling them.)
---------------------------------------------------------------------------

function QT.GetBonusObjectives()        return {} end
function QT.GetTrackedAchievementIDs()  return {} end
function QT.GetAchievementData()        return { kind = "achievement", title = "" } end
function QT.IsChallengeModeActive()     return false end
function QT.ResetChallengeMode()        end
function QT.GetScenarioData()           return nil end
function QT.OnSuperTrackChanged()       end
function QT.RemoveActiveWaypoint()      end
function QT.HasTomTom()                 return false end
function QT.HasZygor()                  return false end
