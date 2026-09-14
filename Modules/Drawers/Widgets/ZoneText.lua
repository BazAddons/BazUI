-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Zone Text
--
-- Single-line widget that displays the current minimap zone text,
-- centered, so long zone names get their own row without fighting for
-- space with clock/calendar/tracking icons in the Info Bar.
--
-- The zone name is colored by PVP status (red contested, green friendly,
-- orange hostile, yellow sanctuary) to match the default Blizzard zone
-- text colors. Updates on ZONE_CHANGED events.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID     = "bazdrawer_zonetext"
local DESIGN_WIDTH  = 220
local DESIGN_HEIGHT = 28   -- includes the gold frame around the text

local ZoneWidget = {}
addon.ZoneWidget = ZoneWidget

---------------------------------------------------------------------------
-- Zone color lookup. Matches Blizzard's MinimapZoneText behavior: each
-- zone's PVP/faction status produces a different tint.
---------------------------------------------------------------------------

local function GetZoneColor()
    local pvpType = C_PvP.GetZonePVPInfo()
    if pvpType == "sanctuary" then
        return 0.41, 0.80, 0.94   -- light blue - sanctuary
    elseif pvpType == "arena" then
        return 1.00, 0.10, 0.10   -- bright red - arena
    elseif pvpType == "friendly" then
        return 0.10, 1.00, 0.10   -- bright green - friendly territory
    elseif pvpType == "hostile" then
        return 1.00, 0.10, 0.10   -- bright red - hostile territory
    elseif pvpType == "contested" then
        return 1.00, 0.70, 0.00   -- orange - contested
    elseif pvpType == "combat" then
        return 1.00, 0.10, 0.10   -- bright red - active combat zone
    end
    return 1.00, 0.82, 0.00       -- default gold
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function ZoneWidget:Refresh()
    local f = self.frame; if not f then return end
    local zone = GetMinimapZoneText() or GetZoneText() or ""
    f.updateNameplate(zone, f:GetWidth())
    f.text:SetTextColor(GetZoneColor())

    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

---------------------------------------------------------------------------
-- Widget interface
---------------------------------------------------------------------------

function ZoneWidget:GetDesiredHeight()
    return self._desiredHeight or DESIGN_HEIGHT
end

function ZoneWidget:GetStatusText()
    -- No title bar status - the zone text IS the whole widget
    return "", 0.85, 0.85, 0.85
end

function ZoneWidget:GetOptionsArgs()
    return {
        appearanceHeader = {
            order = 10,
            type = "header",
            name = "Appearance",
        },
        appearanceNote = {
            order = 11,
            type = "note",
            style = "info",
            text = "The zone name is colored automatically based on the area's PVP status (gold in neutral zones, green in friendly, red in hostile, orange in contested, light blue in sanctuary).",
        },
    }
end

---------------------------------------------------------------------------
-- Build + Init
---------------------------------------------------------------------------

function ZoneWidget:Build()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "BazUIDrawerZoneTextWidget", UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)
    self.frame = f

    local layout = {
        namePlate = { x = 0, y = 0, w = 110, h = DESIGN_HEIGHT },
        name = { x = 0, y = 4, w = 110, h = 20 },
    }
    f.text, f.updateNameplate = BazUI.Skin.Theme.CreateNameplate(f, f, layout, 1, 14, .84)
    -- Docking and drawer resizing can change the available width without a zone event.
    f:HookScript("OnSizeChanged", function(_, width)
        if f.lastWidth ~= width then
            f.lastWidth = width
            f.updateNameplate(GetMinimapZoneText() or GetZoneText() or "", width)
        end
    end)

    self._desiredHeight = DESIGN_HEIGHT
    return f
end

function ZoneWidget:Init()
    local f = self:Build()

    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Zone",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return ZoneWidget:GetDesiredHeight() end,
        GetStatusText    = function() return ZoneWidget:GetStatusText() end,
        GetOptionsArgs   = function() return ZoneWidget:GetOptionsArgs() end,
    })

    -- Event-driven refresh. The three ZONE_CHANGED* events cover every
    -- possible zone transition (outdoor, indoor, new area), and
    -- PLAYER_ENTERING_WORLD catches the initial login / zone-in state.
    f:RegisterEvent("ZONE_CHANGED")
    f:RegisterEvent("ZONE_CHANGED_INDOORS")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:HookScript("OnEvent", function() ZoneWidget:Refresh() end)

    C_Timer.After(0.2, function() ZoneWidget:Refresh() end)
end

BazUI:QueueForLogin(function() ZoneWidget:Init() end)
