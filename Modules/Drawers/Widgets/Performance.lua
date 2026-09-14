-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Performance
--
-- Always-on widget showing FPS and latency (home + world). Color-coded
-- so you can tell at a glance whether your client is healthy.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_performance"
local DESIGN_WIDTH = 220
local DESIGN_HEIGHT = 44
local PAD          = 8

local Perf = {}
addon.PerformanceWidget = Perf

---------------------------------------------------------------------------
-- Color thresholds
---------------------------------------------------------------------------

local function ColorForFPS(fps)
    if fps >= 100 then return 0.50, 0.95, 0.50 end   -- great
    if fps >= 60  then return 0.85, 0.95, 0.50 end   -- good
    if fps >= 30  then return 1.00, 0.85, 0.30 end   -- okay
    return 1.00, 0.40, 0.40                           -- bad
end

local function ColorForLatency(ms)
    if ms <= 50  then return 0.50, 0.95, 0.50 end
    if ms <= 100 then return 0.85, 0.95, 0.50 end
    if ms <= 250 then return 1.00, 0.85, 0.30 end
    return 1.00, 0.40, 0.40
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local frame

function Perf:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- FPS (left)
    f.fpsLabel = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.fpsLabel:SetPoint("TOPLEFT", PAD, -4)
    f.fpsLabel:SetText("FPS")
    f.fpsLabel:SetTextColor(0.75, 0.75, 0.75)

    f.fps = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontNormalLarge")
    f.fps:SetPoint("TOPLEFT", f.fpsLabel, "BOTTOMLEFT", 0, -1)

    -- Home latency (middle)
    f.homeLabel = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.homeLabel:SetPoint("TOP", f, "TOP", 0, -4)
    f.homeLabel:SetText("Home")
    f.homeLabel:SetTextColor(0.75, 0.75, 0.75)

    f.home = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontNormalLarge")
    f.home:SetPoint("TOP", f.homeLabel, "BOTTOM", 0, -1)

    -- World latency (right)
    f.worldLabel = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.worldLabel:SetPoint("TOPRIGHT", -PAD, -4)
    f.worldLabel:SetText("World")
    f.worldLabel:SetTextColor(0.75, 0.75, 0.75)

    f.world = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontNormalLarge")
    f.world:SetPoint("TOPRIGHT", f.worldLabel, "BOTTOMRIGHT", 0, -1)

    -- Tick once per second
    local accum = 0
    f:SetScript("OnUpdate", function(_, dt)
        accum = accum + dt
        if accum < 1 then return end
        accum = 0
        Perf:Refresh()
    end)

    frame = f
    return f
end

function Perf:Refresh()
    if not frame then return end

    local fps = GetFramerate and GetFramerate() or 0

    -- GetNetStats() returns (bandwidthIn, bandwidthOut, homeLatency,
    -- worldLatency). The previous one-liner attempted a nil-guarded
    -- destructure with `(GetNetStats and GetNetStats()) or 0, 0, 0, 0`
    -- - that parses as (firstReturnOnly or 0), 0, 0, 0 and `or` only
    -- propagates the first return value of GetNetStats, so homeMs /
    -- worldMs always landed on the literal trailing 0s and rendered
    -- as "0 ms" forever. Explicit if-guard fixes it.
    local homeMs, worldMs = 0, 0
    if GetNetStats then
        local _, _, h, w = GetNetStats()
        homeMs  = h or 0
        worldMs = w or 0
    end

    frame.fps:SetText(string.format("%d", math.floor(fps + 0.5)))
    frame.fps:SetTextColor(ColorForFPS(fps))

    frame.home:SetText(string.format("%d|cff999999ms|r", homeMs))
    frame.home:SetTextColor(ColorForLatency(homeMs))

    frame.world:SetText(string.format("%d|cff999999ms|r", worldMs))
    frame.world:SetTextColor(ColorForLatency(worldMs))

    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

function Perf:GetDesiredHeight() return DESIGN_HEIGHT end

function Perf:GetStatusText()
    local fps = GetFramerate and GetFramerate() or 0
    return string.format("%d", math.floor(fps + 0.5)), ColorForFPS(fps)
end

function Perf:Init()
    local f = self:Build()

    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Performance",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return Perf:GetDesiredHeight() end,
        GetStatusText    = function() return Perf:GetStatusText() end,
    })

    self:Refresh()
end

BazUI:QueueForLogin(function() Perf:Init() end)
