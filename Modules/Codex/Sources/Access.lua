-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex: doors open to you, and doors you are working on
--
-- Two blocks over one table. "Open to you" is the answer to what can I
-- do today: instances you are attuned or keyed for, at level, and not
-- already saved to. "Working towards" is everything you have started
-- and not finished, with what is left to do.
--
-- Nothing here asks the client a question it cannot answer. The gates
-- are quests you have completed, keys in your bags, reputations and
-- your level; Data/Access.lua is where it is written down which of
-- those guard which door.
---------------------------------------------------------------------------

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
            -- Not started at all is not "working towards"; it is just
            -- the rest of the game, and listing it would bury the ones
            -- you are actually part way through.
            working[#working + 1] = state
        end
    end
    return open, working
end

local function Duration(seconds)
    return BazUI:FormatSpan(seconds)
end

---------------------------------------------------------------------------
-- Open to you
---------------------------------------------------------------------------

Codex:RegisterSection({
    id     = "open",
    tab    = "today",
    title  = "Open to you",
    order  = 8,
    accent = Theme.colors.success,
    empty  = "Nothing attuned or keyed yet that you are not already saved to.",
    events = {
        "PLAYER_ENTERING_WORLD", "UPDATE_INSTANCE_INFO", "BAG_UPDATE_DELAYED",
        "QUEST_TURNED_IN", "UPDATE_FACTION", "PLAYER_LEVEL_UP",
    },

    GetHighlight = function()
        local open = Split()
        local ready = 0
        for _, state in ipairs(open) do
            if state.open then ready = ready + 1 end
        end
        return {
            value = ready,
            label = ready == 1 and "instance open to you" or "instances open to you",
            color = ready > 0 and Theme.colors.success or nil,
        }
    end,

    GetRows = function()
        local open = Split()
        local rows = {}
        for _, state in ipairs(open) do
            local entry = state.entry

            local detail, rowState, tip
            if state.saved then
                detail   = "saved, " .. Duration(state.reset or 0)
                rowState = "locked"
                tip      = entry.name .. "|nYou are already saved to this one."
            elseif state.underLevelled then
                detail   = "level " .. entry.level
                rowState = "locked"
                tip      = entry.name .. "|nAttuned, but not yet the level for it."
            else
                detail   = "go"
                rowState = "done"
                tip      = entry.name .. "|nAttuned, at level, and not saved."
            end

            rows[#rows + 1] = {
                label  = entry.name,
                detail = detail,
                state  = rowState,
                tip    = tip,
            }
        end
        return rows
    end,
})

---------------------------------------------------------------------------
-- Working towards
---------------------------------------------------------------------------

Codex:RegisterSection({
    id     = "attunements",
    tab    = "today",
    title  = "Working towards",
    order  = 30,
    accent = Theme.colors.caution,
    empty  = "Nothing started. Attunements and keys show up here once you begin one.",
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
