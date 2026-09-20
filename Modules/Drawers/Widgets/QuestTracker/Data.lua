-- SPDX-License-Identifier: GPL-2.0-or-later
-- QuestTracker: Data Retrieval
--
-- Read-only API polling. No frame creation and no visual work: this builds
-- the records Blocks.lua renders, and nothing else.
--
-- Forever is not Classic here. It ships retail's whole ObjectiveTracker and
-- retail's C_QuestLog, and the legacy quest log globals this file used to
-- call - GetQuestLogTitle, GetNumQuestWatches, GetQuestIndexForWatch -
-- exist only inside Blizzard's Classic, Vanilla and Cata folders, which
-- this client's game type never loads. They were nil, so the watch list
-- came back empty and the tracker drew nothing while looking healthy.
--
-- What the client really has, checked against its own
-- Blizzard_APIDocumentationGenerated and against which Blizzard files
-- actually load on this game type:
--
--   C_QuestLog.GetNumQuestWatches / GetQuestIDForQuestWatchIndex
--   C_QuestLog.GetLogIndexForQuestID / GetTitleForQuestID / IsComplete
--   C_QuestLog.GetInfo / GetQuestObjectives / GetNumWorldQuestWatches
--   C_QuestInfoSystem.GetQuestClassification, C_TaskQuest, C_ContentTracking
--   GetNumQuestLeaderBoards, GetQuestLogLeaderBoard, GetTasksTable,
--   GetTaskInfo, GetQuestProgressBarPercent, GetQuestLogSpecialItemInfo,
--   GetQuestLogCompletionText, the GetAchievement* family
--
-- Only C_QuestLog.GetAllQuestWatches is missing, and the older pair below
-- does the same job.

local addon = BazUI:GetModule("Drawers")
if not addon then return end
local QT = addon.QT

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function LogIndexFor(questID)
    if not questID then return nil end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local idx = C_QuestLog.GetLogIndexForQuestID(questID)
        if idx and idx > 0 then return idx end
    end
    -- Present on this client too, and harmless where it is not.
    if GetQuestLogIndexByID then
        local idx = GetQuestLogIndexByID(questID)
        if idx and idx > 0 then return idx end
    end
    return nil
end

-- Two ways to ask, and the order matters. C_QuestLog.GetQuestObjectives is
-- documented on this client, but Blizzard's own tracker never calls it - it
-- reads the leaderboard rows instead - so a documented-but-empty answer is
-- a real possibility. Take whichever actually returns lines rather than
-- trusting either one.
local function ObjectivesFor(questID, logIndex)
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
        if ok and type(objs) == "table" and #objs > 0 then return objs end
    end

    local out = {}
    if logIndex and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        for i = 1, (GetNumQuestLeaderBoards(logIndex) or 0) do
            -- The third argument keeps a percentage out of the text of a
            -- progress-bar objective, which we draw as a bar instead.
            local text, objType, finished = GetQuestLogLeaderBoard(i, logIndex, true)
            out[#out + 1] = {
                text     = text or "",
                type     = objType or "monster",
                finished = finished and true or false,
            }
        end
    end
    return out
end

local function ProgressBarPercent(questID, objectives)
    for _, obj in ipairs(objectives) do
        if obj and obj.type == "progressbar" then
            if GetQuestProgressBarPercent then
                local ok, pct = pcall(GetQuestProgressBarPercent, questID)
                if ok then return pct end
            end
            if C_TaskQuest and C_TaskQuest.GetQuestProgressBarInfo then
                local ok, pct = pcall(C_TaskQuest.GetQuestProgressBarInfo, questID)
                if ok then return pct end
            end
            return nil
        end
    end
    return nil
end

local function IsQuestComplete(questID, logIndex)
    if C_QuestLog and C_QuestLog.IsComplete then
        local ok, done = pcall(C_QuestLog.IsComplete, questID)
        if ok and done then return true end
    end
    -- Era: the log row carries it, as 1 for done and -1 for failed.
    if logIndex and GetQuestLogTitle then
        local _, _, _, _, _, isCompleteFlag = GetQuestLogTitle(logIndex)
        if isCompleteFlag == 1 then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Tracked quest IDs
---------------------------------------------------------------------------

function QT.GetTrackedQuestIDs()
    local ids = {}
    if not C_QuestLog then return ids end

    if C_QuestLog.GetAllQuestWatches then
        local all = C_QuestLog.GetAllQuestWatches()
        if all then
            for _, info in ipairs(all) do
                if type(info) == "table" then
                    if info.questID then ids[#ids + 1] = info.questID end
                else
                    ids[#ids + 1] = info
                end
            end
            return ids
        end
    end

    -- The pair this client actually has.
    local n = C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches() or 0
    for i = 1, n do
        local qid = C_QuestLog.GetQuestIDForQuestWatchIndex
            and C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if qid then ids[#ids + 1] = qid end
    end
    if #ids > 0 then return ids end

    -- Classic Era, which BazUI also deploys to, has none of the above and
    -- the legacy globals instead - the exact mirror of Forever, where these
    -- three are the ones that do not exist. Asking for both keeps one file
    -- serving both clients rather than letting the two drift apart.
    if GetNumQuestWatches and GetQuestIndexForWatch and GetQuestLogTitle then
        for i = 1, (GetNumQuestWatches() or 0) do
            local idx = GetQuestIndexForWatch(i)
            if idx then
                local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(idx)
                if not isHeader and questID and questID > 0 then
                    ids[#ids + 1] = questID
                end
            end
        end
    end
    return ids
end

---------------------------------------------------------------------------
-- The whole log
---------------------------------------------------------------------------

-- Every quest in the log: no headers, and none of the game's own hidden
-- bookkeeping quests.
--
-- The tracker itself only ever wants what is being watched, so this is
-- here for the Codex rather than for the widget. It lives here anyway
-- because this is the file that knows how to ask each client - and the
-- Codex walking the log for itself is exactly how it came to report an
-- empty quest log to a character carrying a dozen. It called
-- GetNumQuestLogEntries and GetQuestLogTitle, which read like the obvious
-- way to walk a quest log and do not exist on this game type at all, so
-- the walk finished before it started. The same trap as the one at the
-- top of this file, one floor down.
function QT.GetAllQuestIDs()
    local ids = {}

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for index = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
            local ok, info = pcall(C_QuestLog.GetInfo, index)
            if ok and info and not info.isHeader and not info.isHidden
                and info.questID and info.questID > 0 then
                ids[#ids + 1] = info.questID
            end
        end
        if #ids > 0 then return ids end
    end

    -- Classic Era, where that pair is missing and these two are not - the
    -- mirror of Forever, which is why both get asked.
    if GetNumQuestLogEntries and GetQuestLogTitle then
        for index = 1, (GetNumQuestLogEntries() or 0) do
            local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
            if not isHeader and questID and questID > 0 then
                ids[#ids + 1] = questID
            end
        end
    end
    return ids
end

---------------------------------------------------------------------------
-- Quest classification
---------------------------------------------------------------------------

function QT.GetQuestClassification(questID)
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
        local ok, cls = pcall(C_QuestInfoSystem.GetQuestClassification, questID)
        if ok then return cls end
    end
    return nil
end

function QT.ClassificationGroup(cls)
    if cls == 2 then return 1, "Campaign"   end  -- Enum.QuestClassification.Campaign
    if cls == 6 then return 2, "Questlines" end  -- Questline
    if cls == 1 then return 3, "Legendary"  end  -- Legendary
    if cls == 3 then return 4, "Callings"   end  -- Calling
    return 5, "Quests"
end

---------------------------------------------------------------------------
-- Quest data builder
---------------------------------------------------------------------------

function QT.GetQuestData(questID)
    local logIndex = LogIndexFor(questID)

    local title = ""
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        title = C_QuestLog.GetTitleForQuestID(questID) or ""
    end
    -- Era again: no GetTitleForQuestID, and the name comes off the log row.
    if title == "" and logIndex and GetQuestLogTitle then
        title = GetQuestLogTitle(logIndex) or ""
    end

    local objectives = ObjectivesFor(questID, logIndex)
    local isComplete = IsQuestComplete(questID, logIndex)

    local specialItem, specialItemCharges
    if logIndex and GetQuestLogSpecialItemInfo then
        local ok, _, item, charges = pcall(GetQuestLogSpecialItemInfo, logIndex)
        if ok and item then
            specialItem        = item
            specialItemCharges = charges
        end
    end

    -- Turn-in-from-anywhere quests. When one of these is complete the block
    -- says "Click to complete quest" instead of listing objectives.
    local isAutoComplete, level = false, nil
    if logIndex and C_QuestLog and C_QuestLog.GetInfo then
        local ok, info = pcall(C_QuestLog.GetInfo, logIndex)
        if ok and info then
            isAutoComplete = info.isAutoComplete and true or false
            level = info.level
        end
    end
    -- Era keeps it on the log row instead.
    if not level and logIndex and GetQuestLogTitle then
        local _, rowLevel = GetQuestLogTitle(logIndex)
        level = rowLevel
    end

    -- "Return to so-and-so", shown in place of objectives once done.
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
        classification     = QT.GetQuestClassification(questID),
        progressBarPct     = ProgressBarPercent(questID, objectives),
        questLogIndex      = logIndex,
        specialItem        = specialItem,
        specialItemCharges = specialItemCharges,
    }
end

---------------------------------------------------------------------------
-- Bonus objectives: area tasks that track themselves
---------------------------------------------------------------------------

function QT.GetBonusObjectives()
    local results = {}
    if not GetTasksTable or not GetTaskInfo then return results end

    for _, questID in ipairs(GetTasksTable()) do
        -- World quests and watched quests have their own sections; a bonus
        -- objective is what is left over.
        local isWorldQuest = QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(questID)
        local isWatched    = QuestUtils_IsQuestWatched and QuestUtils_IsQuestWatched(questID)

        if not isWorldQuest and not isWatched then
            local isInArea, _, numObjectives, taskName = GetTaskInfo(questID)
            if isInArea and numObjectives and numObjectives > 0 then
                results[#results + 1] = {
                    kind       = "quest",
                    id         = questID,
                    title      = taskName or "",
                    objectives = ObjectivesFor(questID, LogIndexFor(questID)),
                    isComplete = IsQuestComplete(questID, LogIndexFor(questID)),
                }
            end
        end
    end
    return results
end

---------------------------------------------------------------------------
-- World quests
--
-- Both the ones that track themselves while you stand in the zone and the
-- ones pinned from the map.
---------------------------------------------------------------------------

local function WorldQuestTitle(questID)
    if C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
        local title = C_TaskQuest.GetQuestInfoByQuestID(questID)
        if title and title ~= "" then return title end
    end
    if QuestUtils_GetQuestName then
        local title = QuestUtils_GetQuestName(questID)
        if title and title ~= "" then return title end
    end
    return ""
end

local function BuildWorldQuestEntry(questID)
    local title = WorldQuestTitle(questID)
    if title == "" then return nil end

    local raw = ObjectivesFor(questID, LogIndexFor(questID))
    local objectives = {}
    for _, obj in ipairs(raw) do
        objectives[#objectives + 1] = {
            text     = obj.text or "",
            finished = obj.finished and true or false,
            type     = obj.type,
        }
    end
    local progressBarPct = ProgressBarPercent(questID, raw)

    -- Say how long is left only when it is worth saying.
    local timeLeftMinutes
    if C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes then
        local ok, mins = pcall(C_TaskQuest.GetQuestTimeLeftMinutes, questID)
        if ok then timeLeftMinutes = mins end
    end
    local critical = _G.WORLD_QUESTS_TIME_CRITICAL_MINUTES or 60
    if timeLeftMinutes and timeLeftMinutes > 0 and timeLeftMinutes <= critical then
        local timeText
        if timeLeftMinutes < 60 then
            timeText = string.format("%d min remaining", timeLeftMinutes)
        else
            timeText = string.format("%dh %dm remaining",
                math.floor(timeLeftMinutes / 60), timeLeftMinutes % 60)
        end
        objectives[#objectives + 1] = { text = timeText, finished = false, isTimer = true }
    end

    return {
        kind            = "worldquest",
        id              = questID,
        title           = title,
        objectives      = objectives,
        isComplete      = IsQuestComplete(questID, LogIndexFor(questID)),
        progressBarPct  = progressBarPct,
        timeLeftMinutes = timeLeftMinutes,
    }
end

local function SortWorldQuests(a, b)
    -- Blizzard's own order: in the area first, then on the map, then by id.
    if not GetTaskInfo then return a.id < b.id end
    local inArea1, onMap1 = GetTaskInfo(a.id)
    local inArea2, onMap2 = GetTaskInfo(b.id)
    if inArea1 ~= inArea2 then return inArea1 and true or false end
    if onMap1  ~= onMap2  then return onMap1  and true or false end
    return a.id < b.id
end

function QT.GetWorldQuests()
    local results, seen = {}, {}

    -- Nearby ones, filtered on isInArea so a quest from the zone behind you
    -- stops showing the moment you leave - which is what Blizzard's tracker
    -- does, because GetTasksTable keeps answering for a while after.
    if GetTasksTable and GetTaskInfo then
        for _, questID in ipairs(GetTasksTable()) do
            if QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(questID)
               and not seen[questID] and GetTaskInfo(questID) then
                local entry = BuildWorldQuestEntry(questID)
                if entry then
                    results[#results + 1] = entry
                    seen[questID] = true
                end
            end
        end
    end

    -- Pinned from the map.
    if C_QuestLog and C_QuestLog.GetNumWorldQuestWatches
       and C_QuestLog.GetQuestIDForWorldQuestWatchIndex then
        for i = 1, C_QuestLog.GetNumWorldQuestWatches() do
            local questID = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
            if questID and not seen[questID] then
                local entry = BuildWorldQuestEntry(questID)
                if entry then
                    results[#results + 1] = entry
                    seen[questID] = true
                end
            end
        end
    end

    table.sort(results, SortWorldQuests)
    return results
end

---------------------------------------------------------------------------
-- Achievements
---------------------------------------------------------------------------

function QT.GetTrackedAchievementIDs()
    local ids = {}
    if C_ContentTracking and C_ContentTracking.GetTrackedIDs
       and Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement then
        local ok, list = pcall(C_ContentTracking.GetTrackedIDs, Enum.ContentTrackingType.Achievement)
        if ok and type(list) == "table" then
            for _, id in ipairs(list) do ids[#ids + 1] = id end
        end
    elseif GetNumTrackedAchievements and GetTrackedAchievements then
        -- The older shape, kept for any client that still answers this way.
        local n = GetNumTrackedAchievements() or 0
        if n > 0 then
            local tracked = { GetTrackedAchievements() }
            for i = 1, n do
                if tracked[i] then ids[#ids + 1] = tracked[i] end
            end
        end
    end
    return ids
end

function QT.GetAchievementData(achievementID)
    local title, completed = "", false
    if GetAchievementInfo then
        local ok, _, name, _, c = pcall(GetAchievementInfo, achievementID)
        if ok then
            title = name or ""
            completed = c and true or false
        end
    end

    -- Only the criteria still outstanding. Somebody tracking an achievement
    -- wants to know what is left, and the finished half is the part they
    -- already know. Blizzard's own tracker lists all of it with green
    -- ticks; this deliberately does not.
    local objectives = {}
    local numCriteria = (GetAchievementNumCriteria and GetAchievementNumCriteria(achievementID)) or 0
    for i = 1, numCriteria do
        if GetAchievementCriteriaInfo then
            local ok, critString, _, critCompleted, quantity, reqQuantity =
                pcall(GetAchievementCriteriaInfo, achievementID, i)
            if ok and critString and critString ~= "" and not critCompleted then
                local text = critString
                if reqQuantity and reqQuantity > 1 and quantity then
                    text = text .. " (" .. quantity .. "/" .. reqQuantity .. ")"
                end
                objectives[#objectives + 1] = { text = text, finished = false }
            end
        end
    end

    return {
        kind       = "achievement",
        id         = achievementID,
        title      = title,
        objectives = objectives,
        isComplete = completed,
    }
end

---------------------------------------------------------------------------
-- Tracked recipes
--
-- Two pools in C_TradeSkillUI, regular and recraft. Each required reagent
-- becomes an objective line, counted the way Blizzard's own recipe tracker
-- counts them.
---------------------------------------------------------------------------

function QT.BuildRecipeEntry(recipeID, isRecraft)
    local PU = _G.ProfessionsUtil
    if not PU or not PU.GetRecipeSchematic then return nil end

    local ok, schematic = pcall(PU.GetRecipeSchematic, recipeID, isRecraft)
    if not ok or not schematic then return nil end

    local title = schematic.name or ""
    if isRecraft and _G.PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER then
        local fmtOk, fmt = pcall(string.format,
            _G.PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER, schematic.name or "")
        if fmtOk then title = fmt end
    end

    local objectives = {}
    local allMet = true

    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        if PU.IsReagentSlotRequired and PU.IsReagentSlotRequired(slot) then
            local reagent = slot.reagents and slot.reagents[1]
            local name

            if PU.IsReagentSlotBasicRequired and PU.IsReagentSlotBasicRequired(slot) then
                if reagent and reagent.itemID and _G.Item and _G.Item.CreateFromItemID then
                    local item = _G.Item:CreateFromItemID(reagent.itemID)
                    if item and item.GetItemName then
                        local nm = item:GetItemName()
                        if nm and nm ~= "" then name = nm end
                    end
                elseif reagent and reagent.currencyID and _G.C_CurrencyInfo
                       and _G.C_CurrencyInfo.GetCurrencyInfo then
                    local info = _G.C_CurrencyInfo.GetCurrencyInfo(reagent.currencyID)
                    if info and info.name then name = info.name end
                end
            elseif PU.IsReagentSlotModifyingRequired and PU.IsReagentSlotModifyingRequired(slot) then
                if slot.slotInfo and slot.slotInfo.slotText then
                    name = slot.slotInfo.slotText
                end
            end

            if name and name ~= "" then
                local quantityRequired = 1
                if slot.GetQuantityRequired then
                    local qrOk, qr = pcall(slot.GetQuantityRequired, slot, reagent)
                    if qrOk and qr then quantityRequired = qr end
                elseif reagent and reagent.quantityRequired then
                    quantityRequired = reagent.quantityRequired
                end

                local quantity = 0
                if PU.AccumulateReagentsInPossession then
                    local qOk, q = pcall(PU.AccumulateReagentsInPossession, slot.reagents)
                    if qOk and q then quantity = q end
                end

                local met = quantity >= quantityRequired
                if not met then allMet = false end

                objectives[#objectives + 1] = {
                    text     = string.format("%d/%d %s", quantity, quantityRequired, name),
                    finished = met,
                }
            end
        end
    end

    return {
        kind       = "recipe",
        id         = recipeID,
        isRecraft  = isRecraft,
        title      = title,
        objectives = objectives,
        isComplete = allMet,
    }
end

function QT.GetTrackedRecipes()
    local out = {}
    if not _G.C_TradeSkillUI or not _G.C_TradeSkillUI.GetRecipesTracked then return out end

    for _, isRecraft in ipairs({ false, true }) do
        local ok, list = pcall(_G.C_TradeSkillUI.GetRecipesTracked, isRecraft)
        if ok and type(list) == "table" then
            for _, recipeID in ipairs(list) do
                local entry = QT.BuildRecipeEntry(recipeID, isRecraft)
                if entry and entry.title ~= "" then out[#out + 1] = entry end
            end
        end
    end
    return out
end
