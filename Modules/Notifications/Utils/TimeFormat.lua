-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications

-- Relative time from GetTime() (session-based)
function addon.FormatRelativeTime(timestamp)
    local elapsed = GetTime() - timestamp
    if elapsed < 10 then
        return "just now"
    elseif elapsed < 60 then
        return string.format("%ds ago", math.floor(elapsed))
    elseif elapsed < 3600 then
        return string.format("%dm ago", math.floor(elapsed / 60))
    elseif elapsed < 86400 then
        return string.format("%dh ago", math.floor(elapsed / 3600))
    else
        return string.format("%dd ago", math.floor(elapsed / 86400))
    end
end

-- Format a real timestamp (from time()) as a short time string for panel cards
function addon.FormatCardTimestamp(realTime)
    if not realTime then return "" end
    return date("%H:%M", realTime)
end
