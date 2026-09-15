-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex: what can I do today
--
-- Raid and dungeon lockouts, and the reset clocks. Every answer comes
-- from the client; nothing here is shipped knowledge.
---------------------------------------------------------------------------

local Codex = BazUI.Codex

local DAY  = 86400
local WEEK = 604800

-- Lockouts and resets are measured in days, which a clock reads badly;
-- the suite's own span format is what everything here shows.
local function Duration(seconds)
    return BazUI:FormatSpan(seconds)
end

---------------------------------------------------------------------------
-- Saved instances
---------------------------------------------------------------------------

local function Lockouts()
    local out = {}
    local count = GetNumSavedInstances and GetNumSavedInstances() or 0
    for i = 1, count do
        local name, _, reset, _, locked, extended, _, isRaid, maxPlayers,
              difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
        -- An expired lockout stays in the list until the server drops
        -- it; showing it would be a lie.
        if name and (locked or extended) then
            out[#out + 1] = {
                name = name, reset = reset or 0, isRaid = isRaid,
                maxPlayers = maxPlayers, difficultyName = difficultyName,
                encounters = numEncounters or 0, defeated = encounterProgress or 0,
            }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

Codex:RegisterSection({
    id     = "lockouts",
    tab    = "today",
    title  = "Saved instances",
    order  = 10,
    accent = BazUI.Skin.Theme.colors.caution,
    empty = "Nothing saved. Every raid is open to you.",
    events = { "UPDATE_INSTANCE_INFO", "PLAYER_ENTERING_WORLD", "BOSS_KILL" },

    GetHighlight = function()
        local locks = Lockouts()
        return {
            value = #locks,
            label = #locks == 1 and "instance saved" or "instances saved",
            color = #locks > 0 and Codex.STATE_COLOR.locked or nil,
        }
    end,

    GetRows = function()
        local rows = {}
        for _, lock in ipairs(Lockouts()) do
            local tip = lock.name
            if lock.encounters > 0 then
                tip = string.format("%s|n%d of %d defeated", lock.name, lock.defeated, lock.encounters)
            end
            if lock.difficultyName and lock.difficultyName ~= "" then
                tip = tip .. "|n" .. lock.difficultyName
            elseif lock.isRaid and lock.maxPlayers then
                tip = tip .. "|n" .. lock.maxPlayers .. " player raid"
            end

            rows[#rows + 1] = {
                label  = lock.name,
                detail = lock.encounters > 0
                    and string.format("%d/%d   %s", lock.defeated, lock.encounters, Duration(lock.reset))
                    or Duration(lock.reset),
                state  = "locked",
                tip    = tip .. "|nResets in " .. Duration(lock.reset),
                -- How much of the instance is already spent, which is
                -- the part you actually weigh before going back in.
                -- Green for what is already down: this is progress
                -- through the instance, not time running out.
                progress = lock.encounters > 0
                    and { value = lock.defeated, max = lock.encounters,
                          color = BazUI.Skin.Theme.colors.success } or nil,
            }
        end
        return rows
    end,
})

---------------------------------------------------------------------------
-- The clocks
--
-- Shown as how much of the period has run rather than a bare countdown:
-- a bar most of the way along says "this week is nearly gone" at a
-- glance, which a string of hours does not.
---------------------------------------------------------------------------

local function SecondsUntil(fn)
    local dt = C_DateAndTime
    if not (dt and dt[fn]) then return nil end
    local ok, secs = pcall(dt[fn])
    if ok and secs and secs > 0 then return secs end
    return nil
end

-- One reset clock. The bar fills as the window runs out and warms from
-- gold towards amber as it does, so a glance says how much of the day or
-- the week is already spent without reading the number.
local function ResetRow(label, remaining, period, tip)
    local Theme = BazUI.Skin.Theme
    local spent = (period - remaining) / period
    return {
        label    = label,
        detail   = Duration(remaining) .. " left",
        state    = "open",
        tip      = tip,
        progress = {
            value = period - remaining,
            max   = period,
            color = Theme.Blend(Theme.colors.gold, Theme.colors.warn, spent),
        },
    }
end

Codex:RegisterSection({
    id     = "resets",
    tab    = "today",
    title  = "Resets",
    order  = 20,
    accent = BazUI.Skin.Theme.colors.gold,
    empty = "This client reports no reset timers.",
    events = { "PLAYER_ENTERING_WORLD" },

    GetHighlight = function()
        local weekly = SecondsUntil("GetSecondsUntilWeeklyReset")
        if not weekly then return nil end
        return { value = Duration(weekly), label = "until the weekly reset" }
    end,

    GetRows = function()
        local rows = {}
        local daily = SecondsUntil("GetSecondsUntilDailyReset")
        if daily then
            rows[#rows + 1] = ResetRow("Daily", daily, DAY,
                "The daily rollover, when quests flagged daily come back.")
        end
        local weekly = SecondsUntil("GetSecondsUntilWeeklyReset")
        if weekly then
            rows[#rows + 1] = ResetRow("Weekly", weekly, WEEK,
                "The weekly rollover, when raid lockouts clear.")
        end
        return rows
    end,
})

-- The server only sends lockout data when asked. Ask on login, and the
-- codex asks again whenever it opens.
BazUI:QueueForModule("Codex", function()
    if RequestRaidInfo then pcall(RequestRaidInfo) end
end)
