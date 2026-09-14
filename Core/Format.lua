-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Format Module
-- Money, time, number, text formatting, and safe string utilities
---------------------------------------------------------------------------

local floor = math.floor

---------------------------------------------------------------------------
-- Money Formatting
-- Converts copper amount to colored gold/silver/copper string
---------------------------------------------------------------------------

function BazUI:FormatMoney(copper)
    if not copper or copper == 0 then
        return "|cffeda55f0|rc"
    end

    local negative = copper < 0
    copper = math.abs(copper)

    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local cop = copper % 100

    local parts = {}
    if gold > 0 then
        table.insert(parts, string.format("|cffffd700%s|rg", self:FormatNumber(gold)))
    end
    if silver > 0 then
        table.insert(parts, string.format("|cffc7c7cf%d|rs", silver))
    end
    if cop > 0 or #parts == 0 then
        table.insert(parts, string.format("|cffeda55f%d|rc", cop))
    end

    local result = table.concat(parts, " ")
    if negative then
        result = "-" .. result
    end
    return result
end

---------------------------------------------------------------------------
-- Time Formatting
-- Precise time display (H:MM:SS or M:SS)
---------------------------------------------------------------------------

function BazUI:FormatTime(seconds)
    if not seconds or seconds <= 0 then return "0:00" end
    seconds = floor(seconds)

    if seconds >= 3600 then
        return string.format(
            "%d:%02d:%02d",
            floor(seconds / 3600),
            floor((seconds % 3600) / 60),
            seconds % 60
        )
    end
    return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

---------------------------------------------------------------------------
-- Span Formatting
-- A stretch of time in the largest two units that matter: "3d 4h",
-- "5h 12m", "40m". For anything measured in days a clock reads wrong,
-- so lockout timers, reset clocks and "how long ago" use this instead
-- of FormatTime above.
---------------------------------------------------------------------------

function BazUI:FormatSpan(seconds)
    seconds = floor(tonumber(seconds) or 0)
    if seconds <= 0 then return "now" end

    local days = floor(seconds / 86400)
    local hours = floor((seconds % 86400) / 3600)
    local mins = floor((seconds % 3600) / 60)

    if days > 0 then return string.format("%dd %dh", days, hours) end
    if hours > 0 then return string.format("%dh %dm", hours, mins) end
    if mins > 0 then return string.format("%dm", mins) end
    return "under a minute"
end

---------------------------------------------------------------------------
-- Number Formatting
-- Adds thousand separators (1,234,567)
---------------------------------------------------------------------------

function BazUI:FormatNumber(num)
    if not num then return "0" end
    local formatted = tostring(floor(num))
    local k
    while true do
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

---------------------------------------------------------------------------
-- Short Number Formatting
-- Compact display (1.2k, 3.5M, 1.1B)
---------------------------------------------------------------------------

function BazUI:FormatShortNumber(num)
    if not num then return "0" end
    local abs = math.abs(num)
    local sign = num < 0 and "-" or ""

    if abs >= 1e9 then
        return string.format("%s%.1fB", sign, abs / 1e9)
    elseif abs >= 1e6 then
        return string.format("%s%.1fM", sign, abs / 1e6)
    elseif abs >= 1e3 then
        return string.format("%s%.1fk", sign, abs / 1e3)
    else
        return string.format("%s%d", sign, abs)
    end
end

---------------------------------------------------------------------------
-- Text Truncation
---------------------------------------------------------------------------

function BazUI:TruncateText(text, maxLen, suffix)
    if not text then return "" end
    maxLen = maxLen or 50
    suffix = suffix or "..."
    if #text <= maxLen then return text end
    return strsub(text, 1, maxLen - #suffix) .. suffix
end

---------------------------------------------------------------------------
-- Safe String Utilities
-- Midnight (12.0) marks some strings as "secret values" which can't be
-- indexed or matched directly. These helpers convert to plain strings first.
---------------------------------------------------------------------------

function BazUI:SafeString(str)
    if str == nil then return nil end
    -- string.format("%s", value) forces a fresh allocation, which strips
    -- a secret string's taint; tostring alone does not. The two
    -- fallbacks cover plainly tainted strings that are not secret.
    local ok, result = pcall(string.format, "%s", str)
    if ok and result then return result end
    if forceinsecure then forceinsecure() end
    ok, result = pcall(tostring, str)
    if ok and result then return result end
    ok, result = pcall(securecallfunction, tostring, str)
    if ok and result then return result end
    return nil
end

function BazUI:SafeMatch(str, pattern)
    local s = self:SafeString(str)
    if not s then return nil end
    return s:match(pattern)
end

function BazUI:SafeFind(str, pattern, init, plain)
    local s = self:SafeString(str)
    if not s then return nil end
    return s:find(pattern, init, plain)
end

---------------------------------------------------------------------------
-- Safe Number Utility
-- Midnight (12.0) returns "secret number" values from APIs like
-- GetUnitSpeed, certain aura/spell IDs, and protected combat values.
-- Direct arithmetic on these throws when execution is tainted by the
-- calling addon. Round-trip through "%d" formatting to launder.
---------------------------------------------------------------------------

function BazUI:SafeNumber(num)
    if num == nil then return nil end
    -- Integer round-trip: "%d" formats reliably even when num is a
    -- secret number; tonumber rebuilds a clean Lua number from the
    -- resulting string. pcall guards against rare cases where the
    -- value is a non-integer or otherwise rejects %d.
    local ok, str = pcall(string.format, "%d", num)
    if not ok then
        ok, str = pcall(string.format, "%f", num)
    end
    if not ok or not str then return nil end
    return tonumber(str)
end
