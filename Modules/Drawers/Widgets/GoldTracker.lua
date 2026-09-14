-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Gold Tracker
--
-- Shows current gold and session change with iconography.
-- Title bar shows compact gold via GetStatusText.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_goldtracker"
local DESIGN_WIDTH = 220
local DESIGN_HEIGHT = 64
local PAD          = 8

local GoldWidget = {}

local sessionStart = 0
local frame

-- Group an integer with thousands separators: 244340 -> "244,340"
local function WithCommas(n)
    local s = tostring(math.floor(n or 0))
    while true do
        local replaced
        s, replaced = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if replaced == 0 then break end
    end
    return s
end

-- Settings helpers
local function GetShowSilver()
    return addon:GetWidgetSetting(WIDGET_ID, "showSilver", true) ~= false
end
local function GetShowCopper()
    return addon:GetWidgetSetting(WIDGET_ID, "showCopper", true) ~= false
end

local function FormatGold(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local showSilver = GetShowSilver()
    local showCopper = GetShowCopper()

    if g > 0 then
        local out = string.format("%s|cffffd700g|r", WithCommas(g))
        if showSilver then out = out .. string.format(" %d|cffc7c7cfs|r", s) end
        if showCopper then out = out .. string.format(" %d|cffeda55fc|r", c) end
        return out
    elseif s > 0 and showSilver then
        local out = string.format("%d|cffc7c7cfs|r", s)
        if showCopper then out = out .. string.format(" %d|cffeda55fc|r", c) end
        return out
    end
    return string.format("%d|cffeda55fc|r", c)
end

local function FormatGoldShort(copper)
    local g = math.floor(copper / 10000)
    if g >= 1000000 then
        return string.format("%.1fM|cffffd700g|r", g / 1000000)
    elseif g >= 1000 then
        return string.format("%.1fk|cffffd700g|r", g / 1000)
    end
    return g .. "|cffffd700g|r"
end

function GoldWidget:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", "BazUIDrawerGoldTracker", UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- Coin icon (left) - use the high-res inv_misc_coin_01 icon texture.
    -- The bag UI's atlas (`coin-gold`) is designed for a tiny inline
    -- display and looks pixelated when scaled up to widget size; the
    -- Blizzard icon texture is 64x64 native and stays crisp.
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(28, 28)
    f.icon:SetPoint("LEFT", PAD, 4)
    f.icon:SetTexture("Interface\\Icons\\inv_misc_coin_17")
    -- Trim the icon's default border (Blizzard icons have a ~6% padded edge)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Current gold (large, top right of icon)
    f.current = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.current:SetPoint("LEFT", f.icon, "RIGHT", 6, 6)
    f.current:SetJustifyH("LEFT")

    -- Session change (smaller, below current)
    f.change = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.change:SetPoint("LEFT", f.icon, "RIGHT", 6, -8)
    f.change:SetJustifyH("LEFT")

    -- Subtle separator at the bottom
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", PAD, 4)
    sep:SetPoint("BOTTOMRIGHT", -PAD, 4)
    sep:SetColorTexture(0.3, 0.25, 0.15, 0.4)

    frame = f
    return f
end

-- Shrink a font string to fit the available width by reducing its
-- font size proportionally. Resets to the base font object first so
-- the next call starts from full size.
local function FitFontToWidth(fs, baseObject, maxWidth, minSize)
    fs:SetFontObject(baseObject)
    if not maxWidth or maxWidth <= 0 then return end
    local font, size, flags = fs:GetFont()
    if not font or not size then return end
    local width = fs:GetStringWidth()
    if width <= maxWidth then return end
    local newSize = math.max(minSize or 9, math.floor(size * maxWidth / width))
    fs:SetFont(font, newSize, flags or "")
end

function GoldWidget:Update()
    if not frame then return end
    local gold = GetMoney() or 0
    frame.current:SetText(FormatGold(gold))

    local diff = gold - sessionStart
    if diff > 0 then
        frame.change:SetText("|cff44dd44Session +|r " .. FormatGold(diff))
    elseif diff < 0 then
        frame.change:SetText("|cffdd4444Session -|r " .. FormatGold(-diff))
    else
        frame.change:SetText("|cff666666Session no change|r")
    end

    -- Dynamically shrink fonts so big numbers (like 244,340g) always fit.
    -- Available text width = frame width - left padding - icon width
    --                        - icon-to-text gap - right padding.
    local maxW = (frame:GetWidth() or DESIGN_WIDTH) - PAD - 28 - 6 - PAD
    FitFontToWidth(frame.current, "GameFontNormalLarge",  maxW, 10)
    FitFontToWidth(frame.change,  "GameFontHighlightSmall", maxW, 8)

    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

function GoldWidget:GetOptionsArgs()
    return {
        header = {
            order = 1,
            type = "header",
            name = "Display",
        },
        showSilver = {
            order = 2,
            type = "toggle",
            name = "Show silver",
            desc = "Display the silver portion of your gold total. Hide for a cleaner look at high gold values.",
            get = function() return GetShowSilver() end,
            set = function(_, val)
                addon:SetWidgetSetting(WIDGET_ID, "showSilver", val)
                GoldWidget:Update()
            end,
        },
        showCopper = {
            order = 3,
            type = "toggle",
            name = "Show copper",
            desc = "Display the copper portion of your gold total.",
            get = function() return GetShowCopper() end,
            set = function(_, val)
                addon:SetWidgetSetting(WIDGET_ID, "showCopper", val)
                GoldWidget:Update()
            end,
        },
    }
end

function GoldWidget:GetStatusText()
    return FormatGoldShort(GetMoney() or 0), 1, 0.82, 0
end

function GoldWidget:GetDesiredHeight() return DESIGN_HEIGHT end

function GoldWidget:Init()
    local f = self:Build()
    sessionStart = GetMoney() or 0

    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Gold Tracker",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return GoldWidget:GetDesiredHeight() end,
        GetStatusText    = function() return GoldWidget:GetStatusText() end,
        GetOptionsArgs   = function() return GoldWidget:GetOptionsArgs() end,
    })

    f:RegisterEvent("PLAYER_MONEY")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:HookScript("OnEvent", function() GoldWidget:Update() end)

    self:Update()
end

BazUI:QueueForLogin(function() GoldWidget:Init() end)
