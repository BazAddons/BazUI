-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Stopwatch
--
-- Simple start/pause/reset stopwatch with large time display.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_stopwatch"
local DESIGN_WIDTH = 220
local DESIGN_HEIGHT = 76
local PAD          = 8

local StopwatchWidget = {}
local frame
local elapsed = 0
local running = false
local startTime = 0

local function FormatTime(seconds)
    seconds = math.floor(seconds * 10 + 0.5) / 10
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%d:%02d:%04.1f", h, m, s)
    end
    return string.format("%d:%04.1f", m, s)
end

function StopwatchWidget:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", "BazUIDrawerStopwatch", UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- Time display (large)
    f.time = f:CreateFontString(nil, "OVERLAY", "GameFont_Gigantic")
    f.time:SetPoint("TOP", 0, -PAD)
    f.time:SetTextColor(1, 0.82, 0)
    f.time:SetText("0:00.0")

    -- Buttons
    local btnW = (DESIGN_WIDTH - PAD * 2 - 8) / 3
    f.startBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.startBtn:SetSize(btnW, 22)
    f.startBtn:SetPoint("BOTTOMLEFT", PAD, PAD)
    f.startBtn:SetText("Start")
    f.startBtn:SetScript("OnClick", function() StopwatchWidget:ToggleRunning() end)
    local fs1 = f.startBtn:GetFontString(); if fs1 then fs1:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontHighlightSmall")) end

    f.lapBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.lapBtn:SetSize(btnW, 22)
    f.lapBtn:SetPoint("LEFT", f.startBtn, "RIGHT", 4, 0)
    f.lapBtn:SetText("Reset")
    f.lapBtn:SetScript("OnClick", function() StopwatchWidget:Reset() end)
    local fs2 = f.lapBtn:GetFontString(); if fs2 then fs2:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontHighlightSmall")) end

    f.closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.closeBtn:SetSize(btnW, 22)
    f.closeBtn:SetPoint("LEFT", f.lapBtn, "RIGHT", 4, 0)
    f.closeBtn:SetText("- 1m")
    f.closeBtn:SetScript("OnClick", function()
        elapsed = math.max(0, elapsed - 60)
        if not running then f.time:SetText(FormatTime(elapsed)) end
    end)
    local fs3 = f.closeBtn:GetFontString(); if fs3 then fs3:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontHighlightSmall")) end

    f:SetScript("OnUpdate", function(_, dt)
        if running then
            elapsed = GetTime() - startTime
            f.time:SetText(FormatTime(elapsed))
            if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
                addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
            end
        end
    end)

    frame = f
    return f
end

function StopwatchWidget:ToggleRunning()
    if running then
        running = false
        frame.startBtn:SetText("Start")
    else
        running = true
        startTime = GetTime() - elapsed
        frame.startBtn:SetText("Pause")
    end
end

function StopwatchWidget:Reset()
    running = false
    elapsed = 0
    if frame then
        frame.startBtn:SetText("Start")
        frame.time:SetText("0:00.0")
    end
end

function StopwatchWidget:GetStatusText()
    if running or elapsed > 0 then
        return FormatTime(elapsed), 1, 0.82, 0
    end
    return "", 0.6, 0.6, 0.6
end

function StopwatchWidget:GetDesiredHeight() return DESIGN_HEIGHT end

function StopwatchWidget:Init()
    local f = self:Build()
    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Stopwatch",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return StopwatchWidget:GetDesiredHeight() end,
        GetStatusText    = function() return StopwatchWidget:GetStatusText() end,
    })
end

BazUI:QueueForLogin(function() StopwatchWidget:Init() end)
