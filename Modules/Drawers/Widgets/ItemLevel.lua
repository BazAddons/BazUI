-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Item Level
--
-- Headline equipped iLevel with the overall (best-available) iLevel as a
-- sub-label. When the two diverge, the headline tints yellow as a
-- gentle nudge that better gear is sitting in your bags.
--
-- Optional: overlay each item's iLevel onto its character-pane slot,
-- coloured by item quality (toggleable via the widget's settings).

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID     = "bazdrawer_itemlevel"
local DESIGN_WIDTH  = 200
local DESIGN_HEIGHT = 44
local PAD           = 8

local ItemLevel = {}
addon.ItemLevelWidget = ItemLevel

---------------------------------------------------------------------------
-- iLevel readers
---------------------------------------------------------------------------

local function GetLevels()
    local overall, equipped = 0, 0
    if GetAverageItemLevel then
        overall, equipped = GetAverageItemLevel()
    end
    return tonumber(overall) or 0, tonumber(equipped) or 0
end

local function FormatLevel(level)
    if level <= 0 then return "-" end
    return string.format("%.1f", level)
end

local function ColorForDelta(overall, equipped)
    if math.abs(overall - equipped) < 0.5 then
        return 1.00, 0.82, 0.00
    end
    return 1.00, 0.95, 0.40
end

---------------------------------------------------------------------------
-- Headline frame
---------------------------------------------------------------------------

local frame

function ItemLevel:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(28, 28)
    f.icon:SetPoint("LEFT", PAD, 0)
    f.icon:SetTexture("Interface\\Icons\\inv_chest_plate10")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.equipped = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontNormalLarge")
    f.equipped:SetPoint("LEFT", f.icon, "RIGHT", 8, 6)
    f.equipped:SetJustifyH("LEFT")

    f.sub = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("LEFT", f.icon, "RIGHT", 8, -8)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetTextColor(0.85, 0.85, 0.85)

    frame = f
    return f
end

function ItemLevel:Refresh()
    if not frame then return end
    local overall, equipped = GetLevels()

    frame.equipped:SetText(FormatLevel(equipped))
    frame.equipped:SetTextColor(ColorForDelta(overall, equipped))

    if math.abs(overall - equipped) < 0.5 then
        frame.sub:SetText("Item Level")
    else
        frame.sub:SetText(string.format("Item Level  |cff999999(avg %s)|r",
            FormatLevel(overall)))
    end

    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

function ItemLevel:GetDesiredHeight() return DESIGN_HEIGHT end

function ItemLevel:GetStatusText()
    local overall, equipped = GetLevels()
    return FormatLevel(equipped), ColorForDelta(overall, equipped)
end

---------------------------------------------------------------------------
-- Paper-doll overlay
--
-- For each equipped slot on the Character pane, drop a small text label
-- in the top-right corner showing the item's iLevel coloured by quality
-- (purple for epic, blue for rare, etc.). Toggleable per-widget so users
-- who already use Pawn / ItemLevelDisplay can leave it off.
---------------------------------------------------------------------------

local PAPER_DOLL_SLOT_NAMES = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
    "CharacterShirtSlot", "CharacterChestSlot", "CharacterWaistSlot",
    "CharacterLegsSlot", "CharacterFeetSlot", "CharacterWristSlot",
    "CharacterHandsSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
    "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterBackSlot",
    "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterTabardSlot",
}

local function PaperDollEnabled()
    return addon:GetWidgetSetting(WIDGET_ID, "showOnPaperDoll", false) and true or false
end

local function GetOrCreateOverlay(slot)
    if slot._bazILvl then return slot._bazILvl end
    local fs = slot:CreateFontString(nil, "OVERLAY")
    fs:SetFont(BazUI.Skin.Theme.FontFile(), 13, "OUTLINE")
    fs:SetPoint("TOPRIGHT", -2, -2)
    fs:SetJustifyH("RIGHT")
    fs:SetDrawLayer("OVERLAY", 7)  -- above the icon and any default Blizzard borders
    slot._bazILvl = fs
    return fs
end

local function UpdateSlot(slot)
    local fs = GetOrCreateOverlay(slot)

    if not PaperDollEnabled() then
        fs:Hide()
        return
    end

    local slotID = slot:GetID()
    if not slotID or slotID < 1 then
        fs:Hide()
        return
    end

    local link = GetInventoryItemLink("player", slotID)
    if not link then
        fs:Hide()
        return
    end

    -- GetDetailedItemLevelInfo returns (effectiveLevel, isPreview, baseLevel).
    -- effectiveLevel is what Blizzard's character pane shows, including any
    -- upgrades, sockets, or scaling.
    local level
    if GetDetailedItemLevelInfo then
        level = GetDetailedItemLevelInfo(link)
    end
    if not level or level < 1 then
        fs:Hide()
        return
    end

    -- Quality color via ITEM_QUALITY_COLORS. Quality is the 3rd return of
    -- GetItemInfo. Some items might not be cached yet - fall back to
    -- white text rather than skipping.
    local _, _, quality = C_Item.GetItemInfo(link)
    local color = quality and ITEM_QUALITY_COLORS[quality] or nil
    if color then
        fs:SetTextColor(color.r, color.g, color.b)
    else
        fs:SetTextColor(1, 1, 1)
    end

    fs:SetText(tostring(level))
    fs:Show()
end

function ItemLevel:UpdatePaperDollOverlays()
    for _, name in ipairs(PAPER_DOLL_SLOT_NAMES) do
        local slot = _G[name]
        if slot then UpdateSlot(slot) end
    end
end

local paperDollHooked = false
local function HookPaperDollFrame()
    if paperDollHooked then return end
    if not PaperDollFrame then return end
    paperDollHooked = true

    -- Refresh whenever the pane is shown (some events fire while the
    -- pane is hidden and the slot frames don't exist as visible yet).
    PaperDollFrame:HookScript("OnShow", function()
        ItemLevel:UpdatePaperDollOverlays()
    end)
end

---------------------------------------------------------------------------
-- Per-widget settings (paper-doll toggle)
---------------------------------------------------------------------------

function ItemLevel:GetOptionsArgs()
    return {
        paperDollHeader = {
            order = 1,
            type  = "header",
            name  = "Character Pane",
        },
        showOnPaperDoll = {
            order = 2,
            type  = "toggle",
            name  = "Show iLevel on Item Slots",
            desc  = "Overlay each equipped item's level number in the top-right corner of its slot on the character pane, colored by item quality.",
            get   = function()
                return addon:GetWidgetSetting(WIDGET_ID, "showOnPaperDoll", false) and true or false
            end,
            set   = function(_, val)
                addon:SetWidgetSetting(WIDGET_ID, "showOnPaperDoll", val and true or false)
                ItemLevel:UpdatePaperDollOverlays()
            end,
        },
        paperDollNote = {
            order = 3,
            type  = "note",
            style = "info",
            text  = "Numbers refresh on equipment changes and whenever you open the character pane. Disabling hides every overlay; the slot icons themselves are not modified.",
        },
    }
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function ItemLevel:Init()
    local f = self:Build()

    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Item Level",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return ItemLevel:GetDesiredHeight() end,
        GetStatusText    = function() return ItemLevel:GetStatusText() end,
        GetOptionsArgs   = function() return ItemLevel:GetOptionsArgs() end,
    })

    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("UNIT_INVENTORY_CHANGED")
    f:HookScript("OnEvent", function(_, event, unit)
        if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
        ItemLevel:Refresh()
        -- Refresh paper-doll overlays too - equipping new gear should
        -- update both the headline and the slot labels.
        ItemLevel:UpdatePaperDollOverlays()
    end)

    HookPaperDollFrame()

    self:Refresh()
end

BazUI:QueueForLogin(function()
    C_Timer.After(0.5, function() ItemLevel:Init() end)
end)
