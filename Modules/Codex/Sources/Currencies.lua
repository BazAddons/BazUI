-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: Currencies
--
-- Your purse, then every currency the client lists, grouped the way its
-- own currency pane groups them. One row per currency: its icon, its
-- name, how much you hold, and where it has a cap or a weekly limit,
-- how close you are to it - in words, because a cap is a number you
-- compare, not a picture you glance at.
--
-- The groups are the game's. A group collapsed in the game's pane is
-- collapsed here too, for the same reason the reputation page leaves
-- them be: expanding one redraws the codex, which would expand it again.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local Theme = BazUI.Skin.Theme

local TAB = "currencies"
local COMMON = {
    tab      = TAB,
    tabLabel = "Currencies",
    tabOrder = 28,
    tabIcon  = "Interface\\Icons\\INV_Misc_Coin_02",
}
local PREFIX = "cur."

---------------------------------------------------------------------------
-- Reading the list
---------------------------------------------------------------------------

local function ReadEntry(i)
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListInfo then
        return C_CurrencyInfo.GetCurrencyListInfo(i)
    end
    return nil
end

local function Scan()
    local groups, byName, collapsed = {}, {}, 0
    local count = (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize
        and C_CurrencyInfo.GetCurrencyListSize()) or 0

    local current
    local function Group(name)
        local g = byName[name]
        if not g then
            g = { header = name, entries = {} }
            byName[name] = g
            groups[#groups + 1] = g
        end
        return g
    end

    for i = 1, count do
        local c = ReadEntry(i)
        if c and c.name then
            if c.isHeader then
                current = Group(c.name)
                if not c.isHeaderExpanded then collapsed = collapsed + 1 end
            elseif not c.isTypeUnused then
                local g = current or Group("Other")
                g.entries[#g.entries + 1] = c
            end
        end
    end
    return groups, collapsed
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function Reading(c)
    local have = BazUI:FormatNumber(c.quantity or 0)
    local cap  = c.maxQuantity or 0
    if c.useTotalEarnedForMaxQty and cap > 0 then
        return ("%s   |   %s of %s earned"):format(have,
            BazUI:FormatNumber(c.totalEarned or 0), BazUI:FormatNumber(cap))
    end
    if cap > 0 then
        return ("%s / %s"):format(have, BazUI:FormatNumber(cap))
    end
    return have
end

-- A weekly limit is the thing you can act on this week, so it gets the
-- row's state: gold while there is room, green when it is filled.
local function WeeklyState(c)
    if not c.canEarnPerWeek then return nil, nil end
    local weeklyMax = c.maxWeeklyQuantity or 0
    if weeklyMax <= 0 then return nil, nil end
    local earned = c.quantityEarnedThisWeek or 0
    local tip = ("%s of %s earned this week"):format(
        BazUI:FormatNumber(earned), BazUI:FormatNumber(weeklyMax))
    return (earned >= weeklyMax) and "done" or "open", tip
end

local function Rows(group)
    local rows = {}
    for _, c in ipairs(group.entries) do
        local state, tip = WeeklyState(c)
        local cap = c.maxQuantity or 0
        local muted = (c.quantity or 0) == 0
        rows[#rows + 1] = {
            icon   = c.iconFileID,
            label  = c.name,
            detail = Reading(c),
            state  = state or ((cap > 0 and (c.quantity or 0) >= cap) and "done" or nil),
            muted  = muted,
            tip    = tip,
            link   = (c.currencyID and C_CurrencyInfo.GetCurrencyLink)
                and C_CurrencyInfo.GetCurrencyLink(c.currencyID) or nil,
        }
    end
    return rows
end

local function Summary(group)
    local held = 0
    for _, c in ipairs(group.entries) do
        if (c.quantity or 0) > 0 then held = held + 1 end
    end
    local n = #group.entries
    return { text = ("%d of %d held"):format(held, n) }
end

---------------------------------------------------------------------------
-- Blocks
---------------------------------------------------------------------------

local groupsNow, collapsedNow = {}, 0

local function Sync()
    groupsNow, collapsedNow = Scan()

    local blocks = {
        -- The purse first: the one currency everyone has.
        {
            key   = "_money",
            title = "Purse",
            GetRows = function()
                return { {
                    icon   = "Interface\\Icons\\INV_Misc_Coin_01",
                    label  = "Gold on this character",
                    detail = BazUI:FormatMoney(GetMoney and GetMoney() or 0),
                } }
            end,
            GetHighlight = function()
                return { value = BazUI:FormatMoney(GetMoney and GetMoney() or 0), label = "in your purse" }
            end,
        },
    }

    for _, g in ipairs(groupsNow) do
        blocks[#blocks + 1] = {
            key   = g.header,
            title = g.header,
            empty = "Nothing in this group yet.",
            GetRows = function() return Rows(g) end,
            GetBar  = function() return Summary(g) end,
        }
    end

    if collapsedNow > 0 then
        blocks[#blocks + 1] = {
            key   = "_collapsed",
            title = "Not shown",
            GetRows = function()
                return { {
                    label = ("%d group%s collapsed in the game's currency pane."):format(
                        collapsedNow, collapsedNow == 1 and "" or "s"),
                    detail = "expand them there to see them here",
                    muted = true,
                } }
            end,
        }
    end

    Codex:SyncGroupSections(PREFIX, COMMON, blocks)
end

---------------------------------------------------------------------------
-- Staying current
---------------------------------------------------------------------------

BazUI:QueueForModule("Codex", function()
    Sync()
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    watcher:RegisterEvent("PLAYER_MONEY")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", function()
        Sync()
        if Codex.IsShown and Codex:IsShown() then
            Codex.Panel:RebuildTabs()
            Codex.Panel:QueueRefresh()
        end
    end)
end)

-- Silence a linter that cannot see Theme is kept for the day a color
-- is wanted here.
local _ = Theme
