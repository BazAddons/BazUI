-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex: quests worth finishing
--
-- The Today tab answers one question, and for most characters on most
-- days the answer is in the quest log. Not all of it though: twenty
-- quest titles is the log, not an answer. So this shows the two kinds
-- that are actually a plan.
--
--   Ready to hand in   nothing left to do but walk back.
--   Nearly there       the ones you are furthest through.
--
-- Everything else stays in the quest log where it belongs.
--
-- The reading comes from the quest tracker widget's own data layer
-- rather than a second walk of the quest log: one place understands
-- what a quest looks like on this client, and both readers use it.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local Theme = BazUI.Skin.Theme

local MAX_ROWS = 10

local function Tracker()
    local drawers = BazUI:GetModule("Drawers")
    return drawers and drawers.QT
end

---------------------------------------------------------------------------
-- Reading the log
---------------------------------------------------------------------------

local function QuestIDs()
    local ids = {}
    local total = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    for i = 1, total do
        local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
        if not isHeader and questID and questID > 0 then
            ids[#ids + 1] = questID
        end
    end
    return ids
end

-- How far through a quest's objectives you are. Counting finished
-- objectives works on every client here; the fulfilled/required numbers
-- are not always filled in on Era, so they are used only when present.
local function Progress(quest)
    local done, total = 0, 0
    for _, objective in ipairs(quest.objectives or {}) do
        total = total + 1
        if objective.finished then
            done = done + 1
        elseif objective.numRequired and objective.numRequired > 0
            and objective.numFulfilled then
            -- A part-finished objective counts for its own fraction, so
            -- eight of ten kobolds reads as most of the way rather than
            -- as nothing at all.
            done = done + (objective.numFulfilled / objective.numRequired)
        end
    end
    return done, total
end

local function Gather()
    local QT = Tracker()
    if not QT or not QT.GetQuestData then return {}, 0, 0 end

    local quests, ready, active = {}, 0, 0
    for _, questID in ipairs(QuestIDs()) do
        local ok, quest = pcall(QT.GetQuestData, questID)
        if ok and quest and quest.title ~= "" then
            local done, total = Progress(quest)
            local fraction = (total > 0) and (done / total) or 0

            if quest.isComplete then
                ready = ready + 1
            else
                active = active + 1
            end

            -- A quest with no objectives at all is a "go and speak to
            -- someone" step. It has nothing to show a bar for, but it is
            -- still something you can go and do.
            quests[#quests + 1] = {
                id       = questID,
                title    = quest.title,
                level    = quest.level,
                complete = quest.isComplete,
                done     = done,
                total    = total,
                fraction = quest.isComplete and 1 or fraction,
                objectives = quest.objectives,
            }
        end
    end

    table.sort(quests, function(a, b)
        if a.complete ~= b.complete then return a.complete end
        if a.fraction ~= b.fraction then return a.fraction > b.fraction end
        return (a.title or "") < (b.title or "")
    end)
    return quests, ready, active
end

---------------------------------------------------------------------------
-- The block
---------------------------------------------------------------------------

local function Tooltip(quest)
    local lines = { quest.title }
    if quest.level then
        lines[#lines + 1] = "Level " .. quest.level
    end
    if quest.complete then
        lines[#lines + 1] = "|cff73c773Ready to hand in.|r"
    end
    for _, objective in ipairs(quest.objectives or {}) do
        local text = objective.text
        if text and text ~= "" then
            lines[#lines + 1] = objective.finished
                and ("|cff73c773" .. text .. "|r")
                or  ("|cffd9c7a0" .. text .. "|r")
        end
    end
    return table.concat(lines, "|n")
end

Codex:RegisterSection({
    id     = "quests",
    tab    = "today",
    title  = "Quests",
    order  = 5,
    accent = Theme.colors.gold,
    empty  = "Nothing in the quest log.",
    events = {
        "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED",
        "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_ENTERING_WORLD",
    },

    GetHighlight = function()
        local _, ready = Gather()
        return {
            value = ready,
            label = ready == 1 and "quest ready to hand in" or "quests ready to hand in",
            color = ready > 0 and Theme.colors.success or nil,
        }
    end,

    -- The heading carries how much of the log is finished, which is the
    -- one number that says whether today is a hand-in day or a go-out
    -- and-kill-things day.
    GetBar = function()
        local _, ready, active = Gather()
        local total = ready + active
        if total == 0 then return nil end
        return {
            label = "Ready to hand in",
            value = ready, max = total,
            text  = string.format("%d of %d", ready, total),
            color = Theme.colors.success,
        }
    end,

    GetRows = function()
        local quests = Gather()
        local rows = {}
        for i = 1, math.min(#quests, MAX_ROWS) do
            local quest = quests[i]
            local detail
            if quest.complete then
                detail = "ready"
            elseif quest.total > 0 then
                detail = string.format("%d of %d", math.floor(quest.done + 0.5), quest.total)
            else
                detail = "in progress"
            end

            rows[#rows + 1] = {
                label  = quest.title,
                detail = detail,
                state  = quest.complete and "done" or "open",
                tip    = Tooltip(quest),
                progress = (quest.total > 0 or quest.complete) and {
                    value = quest.complete and 1 or quest.done,
                    max   = quest.complete and 1 or quest.total,
                    color = quest.complete and Theme.colors.success or Theme.colors.gold,
                } or nil,
            }
        end

        if #quests > MAX_ROWS then
            rows[#rows + 1] = {
                label = string.format("%d more in the log", #quests - MAX_ROWS),
                muted = true,
            }
        end
        return rows
    end,
})
