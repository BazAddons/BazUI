-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Timers Module
-- Managed timers, throttle, debounce with per-addon cleanup
---------------------------------------------------------------------------

local addonTimers = {} -- [addonName] = { ticker1, ticker2, ... }

---------------------------------------------------------------------------
-- Managed Timers (per-addon, auto-tracked for cleanup)
---------------------------------------------------------------------------

local AddonMixin = BazUI.AddonMixin

-- One-shot timer
function AddonMixin:After(delay, fn)
    local timers = addonTimers[self.name]
    if not timers then
        timers = {}
        addonTimers[self.name] = timers
    end

    -- Declared first so the callback captures the local rather than a
    -- nil global (a local's scope starts after its own statement).
    local timer
    timer = C_Timer.NewTimer(delay, function()
        -- Remove from tracking
        for i, t in ipairs(timers) do
            if t == timer then
                table.remove(timers, i)
                break
            end
        end
        fn()
    end)
    table.insert(timers, timer)
    return timer
end

-- Repeating ticker
function AddonMixin:Every(interval, fn)
    local timers = addonTimers[self.name]
    if not timers then
        timers = {}
        addonTimers[self.name] = timers
    end

    local ticker = C_Timer.NewTicker(interval, fn)
    table.insert(timers, ticker)
    return ticker
end

-- Cancel all timers for this addon
function AddonMixin:CancelAllTimers()
    local timers = addonTimers[self.name]
    if not timers then return end
    for _, timer in ipairs(timers) do
        timer:Cancel()
    end
    wipe(timers)
end

---------------------------------------------------------------------------
-- Static timer helpers (not addon-bound)
---------------------------------------------------------------------------

function BazUI:After(delay, fn)
    return C_Timer.NewTimer(delay, fn)
end

function BazUI:Every(interval, fn)
    return C_Timer.NewTicker(interval, fn)
end

---------------------------------------------------------------------------
-- Throttle
-- Returns a function that executes at most once per interval.
-- Calls during the cooldown are silently dropped.
---------------------------------------------------------------------------

function BazUI:Throttle(interval, fn)
    local lastCall = 0
    return function(...)
        local now = GetTime()
        if now - lastCall >= interval then
            lastCall = now
            return fn(...)
        end
    end
end

---------------------------------------------------------------------------
-- Debounce
-- Returns a function that delays execution until no calls have been
-- made for the specified delay. Each call resets the timer.
---------------------------------------------------------------------------

function BazUI:Debounce(delay, fn)
    local timer = nil
    return function(...)
        local args = { ... }
        if timer then
            timer:Cancel()
        end
        timer = C_Timer.NewTimer(delay, function()
            timer = nil
            fn(unpack(args))
        end)
    end
end

---------------------------------------------------------------------------
-- Cooldown
-- Like throttle, but queues the last call to execute when
-- the cooldown expires (ensures the final state is always applied).
---------------------------------------------------------------------------

function BazUI:Cooldown(interval, fn)
    local lastCall = 0
    local pending = nil
    local pendingTimer = nil

    return function(...)
        local now = GetTime()
        local remaining = interval - (now - lastCall)

        if remaining <= 0 then
            lastCall = now
            pending = nil
            if pendingTimer then
                pendingTimer:Cancel()
                pendingTimer = nil
            end
            return fn(...)
        else
            -- Queue latest args for when cooldown expires
            pending = { ... }
            if not pendingTimer then
                pendingTimer = C_Timer.NewTimer(remaining, function()
                    pendingTimer = nil
                    if pending then
                        lastCall = GetTime()
                        local args = pending
                        pending = nil
                        fn(unpack(args))
                    end
                end)
            end
        end
    end
end
