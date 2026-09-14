-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Hearthstone Cooldown
--
-- Dormant widget that auto-shows while your Hearthstone is on cooldown
-- and disappears once it's ready. Keep your screen clean when there's
-- nothing to track; surface a countdown when there is.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_hearthstonecd"
local DESIGN_WIDTH = 200
local DESIGN_HEIGHT = 44
local PAD          = 8
local HEARTH_ITEM  = 6948  -- standard Hearthstone

-- Colors
local CLR_LABEL = { 0.90, 0.90, 0.90 }
local CLR_TIME  = { 1.00, 0.85, 0.45 }

local Hearth = {}
addon.HearthstoneCDWidget = Hearth

---------------------------------------------------------------------------
-- Cooldown read
---------------------------------------------------------------------------

local function GetHearthCD()
    if not C_Container or not C_Container.GetItemCooldown then
        local start, duration = C_Item.GetItemCooldown(HEARTH_ITEM)
        if not start or not duration or duration == 0 then return 0 end
        local remaining = (start + duration) - GetTime()
        return math.max(0, remaining)
    end
    local start, duration = C_Container.GetItemCooldown(HEARTH_ITEM)
    if not start or not duration or duration == 0 then return 0 end
    local remaining = (start + duration) - GetTime()
    return math.max(0, remaining)
end

local function FormatCD(seconds)
    seconds = math.floor(seconds + 0.5)
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    if m > 0 then return string.format("%d:%02d", m, s) end
    return string.format("%ds", s)
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local frame

function Hearth:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- Hearthstone icon (left)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(28, 28)
    f.icon:SetPoint("LEFT", PAD, 0)
    f.icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(HEARTH_ITEM)
                       or "Interface\\Icons\\inv_misc_rune_01")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- "Hearthstone" label
    f.label = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlight")
    f.label:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -2)
    f.label:SetText("Hearthstone")
    f.label:SetTextColor(unpack(CLR_LABEL))

    -- Time remaining (large, gold)
    f.time = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontNormalLarge")
    f.time:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 8, 0)
    f.time:SetTextColor(unpack(CLR_TIME))

    -- Tick the display while on CD
    local accum = 0
    f:SetScript("OnUpdate", function(_, dt)
        accum = accum + dt
        if accum < 0.5 then return end
        accum = 0
        Hearth:Refresh()
    end)

    frame = f
    return f
end

function Hearth:Refresh()
    if not frame then return end
    local cd = GetHearthCD()
    if cd > 0 then
        frame.time:SetText(FormatCD(cd))
    else
        frame.time:SetText("Ready")
    end
    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

function Hearth:GetDesiredHeight() return DESIGN_HEIGHT end

function Hearth:GetStatusText()
    local cd = GetHearthCD()
    if cd > 0 then return FormatCD(cd), unpack(CLR_TIME) end
    return ""
end

---------------------------------------------------------------------------
-- Init - dormant: only register while CD > 0
---------------------------------------------------------------------------

function Hearth:Init()
    local f = self:Build()

    f:RegisterEvent("BAG_UPDATE_COOLDOWN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:HookScript("OnEvent", function() Hearth:Refresh() end)

    local widgetDef = {
        id           = WIDGET_ID,
        label        = "Hearthstone CD",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return Hearth:GetDesiredHeight() end,
        GetStatusText    = function() return Hearth:GetStatusText() end,
    }

    local LBW = BazUI.Widgets
    LBW:RegisterDormantWidget(widgetDef, {
        events = {
            "BAG_UPDATE_COOLDOWN",
            "PLAYER_ENTERING_WORLD",
            "HEARTHSTONE_BOUND",
        },
        condition = function() return GetHearthCD() > 0 end,
    })
end

BazUI:QueueForLogin(function() Hearth:Init() end)
