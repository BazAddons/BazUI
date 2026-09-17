-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Gold Tracker
--
-- Shows current gold and session change with iconography.
-- Title bar shows compact gold via GetStatusText.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_goldtracker"
local DESIGN_WIDTH = 220
local DESIGN_HEIGHT = 46
local PAD          = 8

local GoldWidget = {}

local sessionStart = 0
local frame


-- Settings helpers
local function GetShowSilver()
    return addon:GetWidgetSetting(WIDGET_ID, "showSilver", true) ~= false
end
local function GetShowCopper()
    return addon:GetWidgetSetting(WIDGET_ID, "showCopper", true) ~= false
end

-- The coin art the rest of the game uses, rather than a letter after the
-- number. There is room for it here - this is a panel, not a line of
-- chat - and a coin is read without being read.
local function Coin(kind, amount)
    return string.format("|cff%s%s|r%s",
        kind == "gold" and "ffd700" or kind == "silver" and "c7c7cf" or "eda55f",
        amount, BazUI.CoinMarkup(kind))
end

local function FormatGold(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local showSilver = GetShowSilver()
    local showCopper = GetShowCopper()

    -- Leading denominations you do not have are left out: nobody wants
    -- to read 0g before the part of the number that means something.
    if g > 0 then
        local out = Coin("gold", BazUI:FormatNumber(g))
        if showSilver then out = out .. "  " .. Coin("silver", s) end
        if showCopper then out = out .. "  " .. Coin("copper", c) end
        return out
    elseif s > 0 and showSilver then
        local out = Coin("silver", s)
        if showCopper then out = out .. "  " .. Coin("copper", c) end
        return out
    end
    return Coin("copper", c)
end

local function FormatGoldShort(copper)
    return Coin("gold", BazUI:FormatShortNumber(math.floor(copper / 10000)))
end

function GoldWidget:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", "BazUIDrawerGoldTracker", UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- No coin icon and no rule underneath. The amount now carries the
    -- game's own coins on the end of it, so a second and larger coin
    -- beside them was saying the same thing twice and taking a third of
    -- the widget to do it. The rule was drawing a line between this
    -- widget and the next, which is the drawer's business rather than
    -- any one widget's.
    f.current = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontNormalLarge")
    f.current:SetPoint("TOPLEFT", PAD, -PAD)
    f.current:SetJustifyH("LEFT")

    f.change = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.change:SetPoint("TOPLEFT", f.current, "BOTTOMLEFT", 0, -2)
    f.change:SetJustifyH("LEFT")

    frame = f
    return f
end

-- Shrink a font string to fit the available width by reducing its
-- font size proportionally. Resets to the base font object first so
-- the next call starts from full size.
local function FitFontToWidth(fs, baseObject, maxWidth, minSize)
    -- Through the theme, or this hands the string back to Blizzard's own
    -- font object every time it runs - which is every update, so the
    -- widget was built in the addon's face and then quietly repainted in
    -- the game's a moment later.
    fs:SetFontObject(BazUI.Skin.Theme.FontObject(baseObject) or baseObject)
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

    -- Shrink the text if a big number would not fit. The whole width is
    -- the text's now that nothing sits beside it.
    local maxW = (frame:GetWidth() or DESIGN_WIDTH) - PAD * 2
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

BazUI:QueueForModule("Drawers", function() GoldWidget:Init() end)
