-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Reset Timers
--
-- Always-on widget showing time until next daily and weekly resets.
-- Color shifts from green > yellow > red as the deadline approaches.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_resettimers"
local DESIGN_WIDTH = 220
local DESIGN_HEIGHT = 56
local PAD          = 8

-- Color thresholds (seconds remaining) > color
local function ColorFor(seconds, isWeekly)
    -- For daily: < 1h = red, < 4h = yellow, else green
    -- For weekly: < 6h = red, < 24h = yellow, else green
    if isWeekly then
        if seconds < 6 * 3600 then return 1.00, 0.30, 0.30 end
        if seconds < 24 * 3600 then return 1.00, 0.85, 0.30 end
        return 0.50, 0.95, 0.50
    else
        if seconds < 3600 then return 1.00, 0.30, 0.30 end
        if seconds < 4 * 3600 then return 1.00, 0.85, 0.30 end
        return 0.50, 0.95, 0.50
    end
end

local function FormatLong(seconds)
    seconds = math.max(0, math.floor(seconds))
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if d > 0 then
        return string.format("%dd %dh", d, h)
    elseif h > 0 then
        return string.format("%dh %dm", h, m)
    else
        local s = seconds % 60
        return string.format("%dm %ds", m, s)
    end
end

local Reset = {}
addon.ResetTimersWidget = Reset

local frame

function Reset:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- Daily column (left half)
    f.dailyLabel = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.dailyLabel:SetPoint("TOPLEFT", PAD, -PAD)
    f.dailyLabel:SetText("Daily Reset")
    f.dailyLabel:SetTextColor(0.85, 0.85, 0.85)

    f.dailyTime = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontNormalLarge")
    f.dailyTime:SetPoint("TOPLEFT", f.dailyLabel, "BOTTOMLEFT", 0, -2)

    -- Weekly column (right half)
    f.weeklyLabel = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.weeklyLabel:SetPoint("TOPRIGHT", -PAD, -PAD)
    f.weeklyLabel:SetText("Weekly Reset")
    f.weeklyLabel:SetTextColor(0.85, 0.85, 0.85)

    f.weeklyTime = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontNormalLarge")
    f.weeklyTime:SetPoint("TOPRIGHT", f.weeklyLabel, "BOTTOMRIGHT", 0, -2)

    -- Bottom separator
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", PAD, 4)
    sep:SetPoint("BOTTOMRIGHT", -PAD, 4)
    sep:SetColorTexture(0.30, 0.25, 0.15, 0.4)

    -- Tick once a second so the seconds column updates
    local accum = 0
    f:SetScript("OnUpdate", function(_, dt)
        accum = accum + dt
        if accum < 1 then return end
        accum = 0
        Reset:Refresh()
    end)

    frame = f
    return f
end

function Reset:Refresh()
    if not frame then return end

    local daily = (C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset
                   and C_DateAndTime.GetSecondsUntilDailyReset()) or 0
    local weekly = (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
                    and C_DateAndTime.GetSecondsUntilWeeklyReset()) or 0

    frame.dailyTime:SetText(FormatLong(daily))
    frame.dailyTime:SetTextColor(ColorFor(daily, false))

    frame.weeklyTime:SetText(FormatLong(weekly))
    frame.weeklyTime:SetTextColor(ColorFor(weekly, true))

    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

function Reset:GetDesiredHeight() return DESIGN_HEIGHT end

function Reset:GetStatusText()
    local daily = (C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset
                   and C_DateAndTime.GetSecondsUntilDailyReset()) or 0
    return FormatLong(daily), ColorFor(daily, false)
end

function Reset:Init()
    local f = self:Build()

    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Reset Timers",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return Reset:GetDesiredHeight() end,
        GetStatusText    = function() return Reset:GetStatusText() end,
    })

    self:Refresh()
end

BazUI:QueueForLogin(function() Reset:Init() end)
