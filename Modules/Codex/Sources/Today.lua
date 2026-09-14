-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex: what can I do today
--
-- Raid and dungeon lockouts, and the reset clocks. Every answer comes
-- from the client; nothing here is shipped knowledge.
---------------------------------------------------------------------------

local Codex = BazUI.Codex

-- Lockouts and resets are measured in days, which a clock reads badly;
-- the suite's own span format is what everything here shows.
local function Duration(seconds)
    return BazUI:FormatSpan(seconds)
end

---------------------------------------------------------------------------
-- Saved instances
---------------------------------------------------------------------------

Codex:RegisterSection({
    id    = "lockouts",
    tab   = "today",
    title = "Saved instances",
    order = 10,
    empty = "Nothing saved. Every raid is open to you.",
    events = { "UPDATE_INSTANCE_INFO", "PLAYER_ENTERING_WORLD", "BOSS_KILL" },
    GetRows = function()
        local rows = {}
        local count = GetNumSavedInstances and GetNumSavedInstances() or 0
        for i = 1, count do
            local name, _, reset, _, locked, extended, _, isRaid, maxPlayers,
                  difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
            -- An expired lockout stays in the list until the server drops
            -- it; showing it would be a lie.
            if name and (locked or extended) then
                local detail = Duration(reset)
                local tip = name
                if numEncounters and numEncounters > 0 then
                    tip = string.format("%s%s%d of %d defeated", name, "|n",
                        encounterProgress or 0, numEncounters)
                end
                if difficultyName and difficultyName ~= "" then
                    tip = tip .. "|n" .. difficultyName
                elseif isRaid and maxPlayers then
                    tip = tip .. "|n" .. maxPlayers .. " player raid"
                end
                rows[#rows + 1] = {
                    label  = name,
                    detail = (numEncounters and numEncounters > 0)
                        and string.format("%d/%d  %s", encounterProgress or 0, numEncounters, detail)
                        or detail,
                    state  = "locked",
                    tip    = tip .. "|nResets in " .. Duration(reset),
                }
            end
        end
        table.sort(rows, function(a, b) return a.label < b.label end)
        return rows
    end,
})

---------------------------------------------------------------------------
-- The clocks
---------------------------------------------------------------------------

Codex:RegisterSection({
    id    = "resets",
    tab   = "today",
    title = "Resets",
    order = 20,
    empty = "This client reports no reset timers.",
    GetRows = function()
        local rows = {}
        local dt = C_DateAndTime
        if dt and dt.GetSecondsUntilDailyReset then
            local ok, secs = pcall(dt.GetSecondsUntilDailyReset)
            if ok and secs then
                rows[#rows + 1] = { label = "Daily", detail = Duration(secs), state = "open" }
            end
        end
        if dt and dt.GetSecondsUntilWeeklyReset then
            local ok, secs = pcall(dt.GetSecondsUntilWeeklyReset)
            if ok and secs then
                rows[#rows + 1] = { label = "Weekly", detail = Duration(secs), state = "open" }
            end
        end
        return rows
    end,
})

-- The server only sends lockout data when asked. Ask on login and
-- whenever the codex opens.
BazUI:QueueForLogin(function()
    if RequestRaidInfo then pcall(RequestRaidInfo) end
end)
