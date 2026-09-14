-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Free Bag Slots
--
-- Always-on widget showing how many empty inventory slots you have left
-- across all your normal bags. Color shifts as you fill up.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_freebagslots"
local DESIGN_WIDTH = 200
local DESIGN_HEIGHT = 44
local PAD          = 8

local Bags = {}
addon.FreeBagSlotsWidget = Bags

---------------------------------------------------------------------------
-- Read free vs total slots across the player's normal bags (0..NUM_BAG_SLOTS)
---------------------------------------------------------------------------

local function GetSlotCounts()
    local free, total = 0, 0
    local first = (Enum and Enum.BagIndex and Enum.BagIndex.Backpack) or 0
    local last  = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS) or 4
    for bag = first, last do
        local numFree
        if C_Container and C_Container.GetContainerNumFreeSlots then
            numFree = C_Container.GetContainerNumFreeSlots(bag)
        end
        local numSlots
        if C_Container and C_Container.GetContainerNumSlots then
            numSlots = C_Container.GetContainerNumSlots(bag)
        end
        if numFree and numSlots then
            free = free + numFree
            total = total + numSlots
        end
    end
    return free, total
end

local function ColorForRatio(free, total)
    if total <= 0 then return 0.6, 0.6, 0.6 end
    local ratio = free / total
    if ratio < 0.10 then return 1.00, 0.30, 0.30 end   -- < 10% free > red
    if ratio < 0.25 then return 1.00, 0.85, 0.30 end   -- < 25% free > yellow
    return 0.50, 0.95, 0.50                             -- plenty > green
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local frame

function Bags:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- Bag icon
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(28, 28)
    f.icon:SetPoint("LEFT", PAD, 0)
    f.icon:SetTexture("Interface\\Icons\\inv_misc_bag_07")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Free count (large)
    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.count:SetPoint("LEFT", f.icon, "RIGHT", 8, 6)
    f.count:SetJustifyH("LEFT")

    -- Sub-label
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.label:SetPoint("LEFT", f.icon, "RIGHT", 8, -8)
    f.label:SetJustifyH("LEFT")
    f.label:SetTextColor(0.85, 0.85, 0.85)
    f.label:SetText("Free Slots")

    frame = f
    return f
end

function Bags:Refresh()
    if not frame then return end
    local free, total = GetSlotCounts()
    frame.count:SetText(string.format("%d|cff999999 / %d|r", free, total))
    frame.count:SetTextColor(ColorForRatio(free, total))

    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

function Bags:GetDesiredHeight() return DESIGN_HEIGHT end

function Bags:GetStatusText()
    local free, total = GetSlotCounts()
    return tostring(free), ColorForRatio(free, total)
end

function Bags:Init()
    local f = self:Build()

    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Free Bag Slots",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return Bags:GetDesiredHeight() end,
        GetStatusText    = function() return Bags:GetStatusText() end,
    })

    f:RegisterEvent("BAG_UPDATE")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:HookScript("OnEvent", function() Bags:Refresh() end)

    self:Refresh()
end

BazUI:QueueForLogin(function() Bags:Init() end)
