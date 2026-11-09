-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex: doors open to you, and doors you are working on
--
-- Two blocks over one table. "Open to you" is the answer to what can I
-- do today: instances you are attuned or keyed for, at level, and not
-- already saved to. "Working toward" is everything you have started
-- and not finished, with what is left to do.
--
-- Nothing here asks the client a question it cannot answer. The gates
-- are quests you have completed, keys in your bags, reputations and
-- your level; Data/Access.lua is where it is written down which of
-- those guard which door.
---------------------------------------------------------------------------

if BazUI.IsRetail then return end -- Forever only; see Modules/Codex/Core.lua

local Codex = BazUI.Codex
local Theme = BazUI.Skin.Theme

local function Access()
    return Codex.Access
end

local function Split()
    local A = Access()
    if not (A and A.All) then return {}, {} end
    local open, working = {}, {}
    for _, state in ipairs(A.All()) do
        if state.ready then
            open[#open + 1] = state
        elseif state.done > 0 then
            -- Not started at all is not "working toward"; it is just
            -- the rest of the game, and listing it would bury the ones
            -- you are actually part way through.
            working[#working + 1] = state
        end
    end
    return open, working
end

---------------------------------------------------------------------------
-- Open to you
---------------------------------------------------------------------------

Codex:RegisterSection({
    id     = "open",
    tab    = "today",
    title  = "Ready to run",
    about  = "Instances confirmed open by the Instances page's level, attunement"
        .. " and lockout checks. Outgrown dungeons are omitted.",
    order  = 8,
    empty  = function()
        return "No instances are currently confirmed open to you. Check Instances for level requirements and attunements."
    end,
    events = {
        "PLAYER_ENTERING_WORLD", "UPDATE_INSTANCE_INFO", "BAG_UPDATE_DELAYED",
        "QUEST_TURNED_IN", "UPDATE_FACTION", "PLAYER_LEVEL_UP",
    },

    GetHighlight = function()
        local ready = #Codex.Instances.OpenRows()
        return {
            value = ready,
            label = ready == 1 and "instance open to you" or "instances open to you",
            color = ready > 0 and Theme.colors.success or nil,
        }
    end,

    GetRows = function()
        return Codex.Instances.OpenRows()
    end,
})

---------------------------------------------------------------------------
-- Working toward
---------------------------------------------------------------------------

Codex:RegisterSection({
    id     = "attunements",
    tab    = "today",
    title  = "Attunements started",
    about  = "Raids and dungeons whose key or attunement you have begun but not"
        .. " finished. Each says how many of its steps are done; finish the last"
        .. " one and it moves up to Ready to run.",
    order  = 30,
    empty  = function()
        local A = Access()
        local level = UnitLevel("player") or 1
        local nearest, gap
        for _, entry in ipairs((A and A.entries) or {}) do
            local at = entry.level or 1
            if at > level and (not gap or at - level < gap) then nearest, gap = entry, at - level end
        end
        if not nearest then
            return "Nothing started. Take the first step of any attunement and it appears here."
        end
        return ("Nothing started. The first you can reach is %s at level %d."):format(
            nearest.name, nearest.level or level)
    end,
    events = {
        "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "QUEST_TURNED_IN",
        "UPDATE_FACTION", "PLAYER_LEVEL_UP",
    },

    GetRows = function()
        local _, working = Split()
        local rows = {}
        for _, state in ipairs(working) do
            local entry = state.entry
            local left = #state.missing

            local tip = entry.name .. "|nStill to do:"
            for _, missing in ipairs(state.missing) do
                tip = tip .. "|n|cffd9c7a0" .. missing .. "|r"
            end

            rows[#rows + 1] = {
                label  = entry.name,
                detail = string.format("%d of %d", state.done, state.total),
                state  = "open",
                tip    = tip,
                progress = {
                    value = state.done, max = state.total,
                    color = Theme.colors.caution,
                },
            }
            if left == 1 then
                rows[#rows].detail = "1 step left"
            end
        end
        return rows
    end,
})
