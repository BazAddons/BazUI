-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Locale Module
-- Simple localization system with passthrough fallback
---------------------------------------------------------------------------

local locales = {} -- [addonName] = { [locale] = { [key] = translation } }

---------------------------------------------------------------------------
-- Locale Definition
---------------------------------------------------------------------------

function BazUI:SetLocale(addonName, locale, strings)
    if not locales[addonName] then
        locales[addonName] = {}
    end
    locales[addonName][locale] = strings
end

---------------------------------------------------------------------------
-- Locale Retrieval
-- Returns a table with __index that falls back through:
-- 1. Current locale strings
-- 2. enUS strings (base language)
-- 3. The key itself (passthrough)
---------------------------------------------------------------------------

function BazUI:GetLocale(addonName)
    local currentLocale = GetLocale() -- "enUS", "deDE", "frFR", etc.

    return setmetatable({}, {
        __index = function(_, key)
            local addonLocales = locales[addonName]
            if not addonLocales then return key end

            -- Try current locale first
            local current = addonLocales[currentLocale]
            if current and current[key] then
                return current[key]
            end

            -- Fall back to enUS
            local english = addonLocales["enUS"]
            if english and english[key] then
                return english[key]
            end

            -- Passthrough: return the key itself
            return key
        end,

        __newindex = function()
            -- Locale tables are read-only at runtime
        end,
    })
end

---------------------------------------------------------------------------
-- Formatted Locale String
-- Like GetLocale but supports string.format placeholders
---------------------------------------------------------------------------

function BazUI:LocaleFormat(addonName, key, ...)
    local L = self:GetLocale(addonName)
    local template = L[key]
    if select("#", ...) > 0 then
        return string.format(template, ...)
    end
    return template
end

---------------------------------------------------------------------------
-- Bulk Locale Helpers
---------------------------------------------------------------------------

-- Check if a specific locale has been defined
function BazUI:HasLocale(addonName, locale)
    return locales[addonName] and locales[addonName][locale] ~= nil
end

-- Get list of defined locales for an addon
function BazUI:GetDefinedLocales(addonName)
    local result = {}
    if locales[addonName] then
        for locale in pairs(locales[addonName]) do
            table.insert(result, locale)
        end
        table.sort(result)
    end
    return result
end
