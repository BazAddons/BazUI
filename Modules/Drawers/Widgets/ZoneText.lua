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
local DESIGN_HEIGHT = 16   -- fallback min content height; the widget
                           -- auto-sizes to the text's real string height
local PAD           = 4    -- vertical padding above and below the text

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
    f.text:SetText(zone)
    f.text:SetTextColor(GetZoneColor())

    -- Auto-size to the text's actual rendered height plus minimal
    -- symmetric padding. The text is anchored CENTER so it stays
    -- vertically balanced regardless of the string height.
    local textH = f.text:GetStringHeight() or DESIGN_HEIGHT
    if textH < DESIGN_HEIGHT then textH = DESIGN_HEIGHT end
    self._desiredHeight = textH + PAD * 2
    f:SetHeight(self._desiredHeight)

    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

---------------------------------------------------------------------------
-- Widget interface
---------------------------------------------------------------------------

function ZoneWidget:GetDesiredHeight()
    return self._desiredHeight or (DESIGN_HEIGHT + PAD * 2)
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
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT + PAD * 2)
    self.frame = f

    -- Centered zone text FontString. Uses GameFontNormalMed3 for a
    -- slightly larger read than the default GameFontNormal. Anchored
    -- CENTER to the widget so the text is vertically balanced instead
    -- of TOP-anchored with dead space below it.
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalMed3")
    f.text:SetPoint("LEFT",  f, "LEFT",  PAD, 0)
    f.text:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    f.text:SetJustifyH("CENTER")
    f.text:SetJustifyV("MIDDLE")
    f.text:SetWordWrap(false)   -- keep zone name to one line; falls back to truncation
    f.text:SetTextColor(1.00, 0.82, 0.00)

    self._desiredHeight = DESIGN_HEIGHT + PAD * 2
    return f
end

function ZoneWidget:Init()
    local f = self:Build()

    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Zone",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT + PAD * 2,
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
