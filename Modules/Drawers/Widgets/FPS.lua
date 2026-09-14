-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: FPS
--
-- Compact FPS-only readout. Lighter complement to the Performance
-- widget (which combines FPS with home + world latency); this one is
-- a dedicated speedometer for users who want just the frame-rate
-- signal in their drawer / dock.
--
-- Big current FPS on the left, rolling 60-second min / max underneath
-- so a brief dip while flying through Stormwind doesn't look like a
-- catastrophe.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_fps"
local DESIGN_WIDTH = 140
local DESIGN_HEIGHT = 44
local PAD          = 8
local WINDOW_SIZE  = 60   -- seconds of samples we keep for min/max

local FPS = {}
addon.FPSWidget = FPS

---------------------------------------------------------------------------
-- Color thresholds (mirror Performance widget so the colours mean the
-- same thing whichever readout the user is looking at).
---------------------------------------------------------------------------

local function ColorForFPS(fps)
    if fps >= 100 then return 0.50, 0.95, 0.50 end   -- great
    if fps >= 60  then return 0.85, 0.95, 0.50 end   -- good
    if fps >= 30  then return 1.00, 0.85, 0.30 end   -- okay
    return 1.00, 0.40, 0.40                           -- bad
end

---------------------------------------------------------------------------
-- Rolling-window stats - simple ring buffer of integer FPS samples.
-- -1 sentinel means "no data yet" so the min/max ignores empty slots
-- during the first minute after login.
---------------------------------------------------------------------------

local samples    = {}
local sampleHead = 0
for i = 1, WINDOW_SIZE do samples[i] = -1 end

local function PushSample(fps)
    sampleHead = (sampleHead % WINDOW_SIZE) + 1
    samples[sampleHead] = fps
end

local function MinMax()
    local lo, hi
    for i = 1, WINDOW_SIZE do
        local v = samples[i]
        if v >= 0 then
            if not lo or v < lo then lo = v end
            if not hi or v > hi then hi = v end
        end
    end
    return lo or 0, hi or 0
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local frame

function FPS:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- Big number, "FPS" label sitting to its right at top alignment.
    f.fps = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontNormalHuge")
    f.fps:SetPoint("TOPLEFT", PAD, -4)
    f.fps:SetJustifyH("LEFT")

    f.unit = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.unit:SetPoint("BOTTOMLEFT", f.fps, "BOTTOMRIGHT", 4, 2)
    f.unit:SetText("FPS")
    f.unit:SetTextColor(0.75, 0.75, 0.75)

    -- Rolling min/max under the main number.
    f.minmax = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.minmax:SetPoint("BOTTOMLEFT", PAD, 4)
    f.minmax:SetTextColor(0.6, 0.6, 0.6)

    -- Hover tooltip with more detail.
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local fps = math.floor((GetFramerate and GetFramerate() or 0) + 0.5)
        local lo, hi = MinMax()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("FPS")
        GameTooltip:AddLine(string.format("Current: |cffffffff%d|r", fps), 1, 1, 1)
        GameTooltip:AddLine(string.format("Last 60s min: |cffffffff%d|r", lo), 1, 1, 1)
        GameTooltip:AddLine(string.format("Last 60s max: |cffffffff%d|r", hi), 1, 1, 1)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Tick once per second via OnUpdate accumulator. Cheap: just one
    -- GetFramerate call + a ring-buffer write per tick. The min/max
    -- scan iterates 60 ints, which is nothing.
    local accum = 0
    f:SetScript("OnUpdate", function(_, dt)
        accum = accum + dt
        if accum < 1 then return end
        accum = 0
        FPS:Refresh()
    end)

    frame = f
    return f
end

function FPS:Refresh()
    if not frame then return end

    local fps = math.floor((GetFramerate and GetFramerate() or 0) + 0.5)
    PushSample(fps)
    local lo, hi = MinMax()

    frame.fps:SetText(tostring(fps))
    frame.fps:SetTextColor(ColorForFPS(fps))
    frame.minmax:SetText(string.format("min %d / max %d", lo, hi))

    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

function FPS:GetDesiredHeight() return DESIGN_HEIGHT end

function FPS:GetStatusText()
    local fps = math.floor((GetFramerate and GetFramerate() or 0) + 0.5)
    return tostring(fps), ColorForFPS(fps)
end

function FPS:Init()
    local f = self:Build()

    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "FPS",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return FPS:GetDesiredHeight() end,
        GetStatusText    = function() return FPS:GetStatusText() end,
    })

    self:Refresh()
end

BazUI:QueueForLogin(function() FPS:Init() end)
