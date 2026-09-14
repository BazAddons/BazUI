-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Coordinates
--
-- Shows player map coordinates with a compass icon and zone name.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_coords"
local DESIGN_WIDTH = 220
local DESIGN_HEIGHT = 56
local PAD          = 8
local UPDATE_INTERVAL = 0.25

local CoordsWidget = {}
local frame
local lastX, lastY = 0, 0

local function GetCoords()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return 0, 0 end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return 0, 0 end
    return pos.x * 100, pos.y * 100
end

function CoordsWidget:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", "BazUIDrawerCoordinates", UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- Compass/map icon
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(28, 28)
    f.icon:SetPoint("LEFT", PAD, 2)
    f.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Coords (large)
    f.coords = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.coords:SetPoint("LEFT", f.icon, "RIGHT", 8, 6)
    f.coords:SetTextColor(1, 0.82, 0)
    f.coords:SetJustifyH("LEFT")

    -- Zone name (smaller, dim)
    f.zone = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.zone:SetPoint("LEFT", f.icon, "RIGHT", 8, -8)
    f.zone:SetTextColor(0.7, 0.7, 0.7)
    f.zone:SetJustifyH("LEFT")
    f.zone:SetWidth(DESIGN_WIDTH - 28 - PAD * 2 - 8)
    f.zone:SetWordWrap(false)

    -- OnUpdate poller
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < UPDATE_INTERVAL then return end
        elapsed = 0
        CoordsWidget:Update()
    end)

    frame = f
    return f
end

function CoordsWidget:Update()
    if not frame then return end
    local x, y = GetCoords()
    if math.abs(x - lastX) >= 0.05 or math.abs(y - lastY) >= 0.05 then
        lastX, lastY = x, y
        if x == 0 and y == 0 then
            frame.coords:SetText("- -")
        else
            frame.coords:SetText(string.format("%.1f, %.1f", x, y))
        end
    end
    local zoneName = GetZoneText() or ""
    if zoneName ~= frame._lastZone then
        frame._lastZone = zoneName
        frame.zone:SetText(zoneName)
    end
    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

function CoordsWidget:GetStatusText()
    if lastX == 0 and lastY == 0 then return "- -", 0.6, 0.6, 0.6 end
    return string.format("%.1f, %.1f", lastX, lastY), 1, 0.82, 0
end

function CoordsWidget:GetDesiredHeight() return DESIGN_HEIGHT end

function CoordsWidget:Init()
    local f = self:Build()
    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Coordinates",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return CoordsWidget:GetDesiredHeight() end,
        GetStatusText    = function() return CoordsWidget:GetStatusText() end,
    })
    self:Update()
end

BazUI:QueueForLogin(function() CoordsWidget:Init() end)
