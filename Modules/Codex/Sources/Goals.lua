-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex: goals
--
-- The long projects: the mount you are saving for, the weapon at the
-- end of your class chain. Unfinished ones sit on Today, because the
-- next step is something you could go and do; finished ones move to
-- Achieved, because by then they are something you did.
--
-- One table, read twice. Nothing is listed for a class it does not
-- belong to or a level it does not matter at yet.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local Theme = BazUI.Skin.Theme

local function Split()
    local Goals = Codex.Goals
    if not (Goals and Goals.All) then return {}, {} end
    local open, done = {}, {}
    for _, state in ipairs(Goals.All()) do
        if state.complete then
            done[#done + 1] = state
        else
            open[#open + 1] = state
        end
    end
    return open, done
end

local EVENTS = {
    "PLAYER_MONEY", "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED",
    "COMPANION_LEARNED", "QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD",
}

-- Money gates are the one kind worth spelling out on the row: "half way
-- there" means more with the number beside it.
local function Detail(state)
    local entry = state.entry
    for _, gate in ipairs(entry.steps or {}) do
        if gate.kind == "money" then
            local met = Codex.Gates.Met(gate)
            if not met then
                local short = (gate.copper or 0) - (GetMoney and GetMoney() or 0)
                return BazUI:FormatMoney(short) .. " to go"
            end
        end
    end
    if state.total > 1 then
        return string.format("%d of %d", state.done, state.total)
    end
    return state.complete and "done" or "not yet"
end

local function Tooltip(state)
    local lines = { state.entry.name }
    if state.entry.note then
        lines[#lines + 1] = "|cffd9c7a0" .. state.entry.note .. "|r"
    end
    if #state.missing > 0 then
        lines[#lines + 1] = "Still to do:"
        for _, missing in ipairs(state.missing) do
            lines[#lines + 1] = "|cffd9c7a0" .. missing .. "|r"
        end
    else
        lines[#lines + 1] = "|cff73c773Done.|r"
    end
    return table.concat(lines, "|n")
end

---------------------------------------------------------------------------
-- What you are chasing
---------------------------------------------------------------------------

Codex:RegisterSection({
    id     = "goals",
    tab    = "today",
    title  = "Goals",
    order  = 20,
    accent = { 0.72, 0.55, 0.85, 1 },
    empty  = "Nothing on the go. Goals appear as your character grows into them.",
    events = EVENTS,

    GetHighlight = function()
        local open = Split()
        if #open == 0 then return nil end
        -- The nearest one is the useful number: it is the thing an
        -- evening could actually finish.
        local nearest = open[1]
        return {
            value = string.format("%d%%", math.floor(nearest.fraction * 100 + 0.5)),
            label = "through " .. nearest.entry.name,
            color = { 0.72, 0.55, 0.85, 1 },
        }
    end,

    GetRows = function()
        local open = Split()
        local rows = {}
        for _, state in ipairs(open) do
            rows[#rows + 1] = {
                label  = state.entry.name,
                detail = Detail(state),
                state  = "open",
                tip    = Tooltip(state),
                progress = {
                    value = state.fraction, max = 1,
                    color = { 0.72, 0.55, 0.85, 1 },
                },
            }
        end
        return rows
    end,
})

---------------------------------------------------------------------------
-- What you finished
---------------------------------------------------------------------------

Codex:RegisterSection({
    id     = "goalsDone",
    tab    = "achieved",
    title  = "Goals",
    order  = 5,
    accent = { 0.72, 0.55, 0.85, 1 },
    empty  = "Nothing finished yet.",
    events = EVENTS,

    GetHighlight = function()
        local _, done = Split()
        return {
            value = #done,
            label = #done == 1 and "goal finished" or "goals finished",
            color = #done > 0 and Theme.colors.success or nil,
        }
    end,

    GetRows = function()
        local _, done = Split()
        local rows = {}
        for _, state in ipairs(done) do
            rows[#rows + 1] = {
                label  = state.entry.name,
                detail = "done",
                state  = "done",
                tip    = Tooltip(state),
            }
        end
        return rows
    end,
})
