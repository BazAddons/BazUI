-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Speed Monitor
--
-- Shows current movement speed % with a colored progress bar below.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_speed"
local DESIGN_WIDTH = 220
local DESIGN_HEIGHT = 50
local PAD          = 8
local UPDATE_INTERVAL = 0.15
local BASE_RUN_SPEED = 7

local SpeedWidget = {}
local frame
local lastSpeed = -1

local function GetSpeed()
    -- GetUnitSpeed returns a "secret number" in Midnight 12.0 - direct
    -- arithmetic throws when the calling context is tainted (which is
    -- the case any time the OnUpdate loop reads it). Launder via
    -- BazUI:SafeNumber to a plain Lua number first.
    local raw = GetUnitSpeed and GetUnitSpeed("player") or 0
    local current = BazUI.SafeNumber and BazUI:SafeNumber(raw) or 0
    if not current then return 0 end
    return math.floor((current / BASE_RUN_SPEED) * 100 + 0.5)
end

local function GetSpeedColor(speed)
    if speed > 100 then return 0.4, 1, 0.4
    elseif speed < 100 and speed > 0 then return 1, 0.4, 0.4
    else return 0.9, 0.9, 0.9 end
end

function SpeedWidget:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", "BazUIDrawerSpeedMonitor", UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- Top row: icon + label
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(20, 20)
    f.icon:SetPoint("TOPLEFT", PAD, -PAD)
    f.icon:SetTexture("Interface\\Icons\\Ability_Rogue_Sprint")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.label = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontNormalLarge")
    f.label:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)

    -- Bottom row: full-width progress bar
    f.barBg = f:CreateTexture(nil, "ARTWORK")
    f.barBg:SetPoint("BOTTOMLEFT", PAD, PAD)
    f.barBg:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    f.barBg:SetHeight(6)
    f.barBg:SetColorTexture(0.12, 0.12, 0.15, 0.8)

    f.barFill = f:CreateTexture(nil, "OVERLAY")
    f.barFill:SetPoint("LEFT", f.barBg, "LEFT", 0, 0)
    f.barFill:SetPoint("BOTTOM", f.barBg, "BOTTOM", 0, 0)
    f.barFill:SetPoint("TOP", f.barBg, "TOP", 0, 0)

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < UPDATE_INTERVAL then return end
        elapsed = 0
        SpeedWidget:Update()
    end)

    frame = f
    return f
end

function SpeedWidget:Update()
    if not frame then return end
    local speed = GetSpeed()
    if speed == lastSpeed then return end
    lastSpeed = speed
    frame.label:SetText(speed .. "%")

    local r, g, b = GetSpeedColor(speed)
    frame.label:SetTextColor(r, g, b)
    frame.barFill:SetColorTexture(r, g, b, 0.85)

    -- Bar fill: 100% speed = full bar, scale linearly, cap at 200%
    local barMax = frame.barBg:GetWidth()
    local fill = math.min(speed / 100, 2) / 2
    frame.barFill:SetWidth(math.max(2, barMax * fill))

    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

function SpeedWidget:GetStatusText()
    if lastSpeed < 0 then return "", 0.7, 0.7, 0.7 end
    local r, g, b = GetSpeedColor(lastSpeed)
    return lastSpeed .. "%", r, g, b
end

function SpeedWidget:GetDesiredHeight() return DESIGN_HEIGHT end

function SpeedWidget:Init()
    local f = self:Build()
    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Speed",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return SpeedWidget:GetDesiredHeight() end,
        GetStatusText    = function() return SpeedWidget:GetStatusText() end,
    })
    self:Update()
end

BazUI:QueueForModule("Drawers", function() SpeedWidget:Init() end)
