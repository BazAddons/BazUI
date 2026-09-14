-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- SafeString: Taint-safe string operations for BNC modules.
-- WoW's taint system prevents addon code from operating on strings
-- received from hardware events (CHAT_MSG_*, RAID_BOSS_EMOTE, etc).
-- We use pcall to catch taint errors and forceinsecure to bypass them.
-- ==========================================================================

-- ---------------------------------------------------------------------------
-- Detaint helper: copies a potentially tainted string into an untainted one.
-- forceinsecure() suppresses taint propagation for the current execution.
-- If that fails, we fall back to pcall which swallows the taint error.
-- ---------------------------------------------------------------------------

-- BazUI:SafeString does the laundering for the whole suite; these stay
-- as BNC.* because thirty call sites across the sources use that name,
-- and the sub/len/lower/gsub wrappers below have no core counterpart.
local function Detaint(str)
    return BazUI:SafeString(str)
end

-- ---------------------------------------------------------------------------
-- Core string wrappers (called as BNC.SafeMatch, not BNC:SafeMatch)
-- ---------------------------------------------------------------------------

function BNC.SafeMatch(str, pattern)
    local clean = Detaint(str)
    if not clean then return nil end
    return string.match(clean, pattern)
end

function BNC.SafeFind(str, pattern, init, plain)
    local clean = Detaint(str)
    if not clean then return nil end
    return string.find(clean, pattern, init, plain)
end

function BNC.SafeGsub(str, pattern, repl)
    local clean = Detaint(str)
    if not clean then return str end
    return string.gsub(clean, pattern, repl)
end

function BNC.SafeLower(str)
    local clean = Detaint(str)
    if not clean then return nil end
    return string.lower(clean)
end

function BNC.SafeSub(str, i, j)
    local clean = Detaint(str)
    if not clean then return nil end
    return string.sub(clean, i, j)
end

function BNC.SafeLen(str)
    local clean = Detaint(str)
    if not clean then return nil end
    return string.len(clean)
end

--- Strip WoW escape sequences (color codes, reset, textures) from a string.
--- Returns cleaned string, or "" if input is nil.
function BNC.StripEscapes(str)
    if not str then return "" end
    str = BNC.SafeGsub(str, "|c%x%x%x%x%x%x%x%x", "") or str
    str = BNC.SafeGsub(str, "|r", "") or str
    str = BNC.SafeGsub(str, "|T.-|t", "") or str
    return str
end

-- ---------------------------------------------------------------------------
-- Deduplicator: throttle duplicate events within a time window.
--
-- Usage:
--   local dedup = BNC:CreateDeduplicator(2)  -- 2-second window
--   if dedup:IsDuplicate(someKey) then return end
-- ---------------------------------------------------------------------------

function BNC:CreateDeduplicator(windowSeconds)
    local seen = {}
    local window = windowSeconds or 2

    local dedup = {}

    --- Returns true if key was seen within the window (i.e. is a duplicate).
    --- Records the key either way.
    function dedup:IsDuplicate(key)
        local now = GetTime()
        if seen[key] and (now - seen[key]) < window then
            return true
        end
        seen[key] = now
        return false
    end

    function dedup:Wipe()
        wipe(seen)
    end

    -- Periodic cleanup to prevent unbounded table growth
    C_Timer.NewTicker(60, function()
        local now = GetTime()
        for k, t in pairs(seen) do
            if (now - t) > window then
                seen[k] = nil
            end
        end
    end)

    return dedup
end

-- ---------------------------------------------------------------------------
-- Accumulator: batch rapid-fire numeric values and flush after a delay.
--
-- Usage:
--   local acc = BNC:CreateAccumulator(1.5, function(data)
--       for key, amount in pairs(data) do ... end
--   end)
--   acc:Add("Faction Name", 50)  -- resets flush timer each call
-- ---------------------------------------------------------------------------

function BNC:CreateAccumulator(flushDelay, onFlush)
    local accumulated = {}
    local timer = nil

    local acc = {}

    --- Add a numeric value to the given key. Resets the flush timer.
    function acc:Add(key, value)
        accumulated[key] = (accumulated[key] or 0) + value
        if timer then timer:Cancel() end
        timer = C_Timer.NewTimer(flushDelay, function()
            if onFlush then onFlush(accumulated) end
            wipe(accumulated)
            timer = nil
        end)
    end

    --- Cancel any pending flush and discard accumulated data.
    function acc:Cancel()
        if timer then timer:Cancel() end
        timer = nil
        wipe(accumulated)
    end

    return acc
end
