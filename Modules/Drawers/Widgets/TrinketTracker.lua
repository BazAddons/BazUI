-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Trinket Tracker
--
-- Always-on widget showing your two equipped trinkets with icons,
-- live cooldown sweep, and click-to-use (when out of combat).
-- Hidden if you have no trinkets equipped.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_trinkettracker"
local DESIGN_WIDTH = 200
local DESIGN_HEIGHT = 44
local PAD          = 8
local ICON_SIZE    = 32
local ICON_GAP     = 8

-- WoW slot IDs for trinkets
local SLOT_TRINKET_1 = 13
local SLOT_TRINKET_2 = 14

local Trinket = {}
addon.TrinketTrackerWidget = Trinket

---------------------------------------------------------------------------
-- One click-safe trinket button. SecureActionButtonTemplate lets the
-- "item" click type activate the trinket without taint.
---------------------------------------------------------------------------

local function BuildSlotButton(parent, slotID)
    local btn = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("type", "item")
    btn:SetAttribute("item", GetInventoryItemLink("player", slotID) or "")

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Empty-slot placeholder backdrop
    btn.empty = btn:CreateTexture(nil, "BACKGROUND")
    btn.empty:SetAllPoints()
    btn.empty:SetColorTexture(0.08, 0.08, 0.10, 0.8)
    btn.empty:Hide()

    -- Cooldown sweep
    btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cd:SetAllPoints()

    -- Thin border
    btn.border = btn:CreateTexture(nil, "OVERLAY")
    btn.border:SetAllPoints()
    btn.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    btn.border:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    btn.border:SetVertexColor(0.5, 0.4, 0.2, 1)

    -- Tooltip on hover
    btn:SetScript("OnEnter", function(self)
        local link = GetInventoryItemLink("player", slotID)
        if link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetInventoryItem("player", slotID)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn.slotID = slotID
    return btn
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local frame

function Trinket:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    f.slot1 = BuildSlotButton(f, SLOT_TRINKET_1)
    f.slot1:SetPoint("LEFT", PAD, 0)

    f.slot2 = BuildSlotButton(f, SLOT_TRINKET_2)
    f.slot2:SetPoint("LEFT", f.slot1, "RIGHT", ICON_GAP, 0)

    -- Status text to the right of the icons (shorter-CD remaining)
    f.status = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("LEFT", f.slot2, "RIGHT", 10, 0)
    f.status:SetTextColor(0.85, 0.85, 0.85)

    frame = f
    return f
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

-- Updating the secure "item" attribute is taint-blocked during combat.
-- We track the desired item link separately and only push it onto the
-- secure attribute out of combat; pending updates flush on
-- PLAYER_REGEN_ENABLED.
local function SetItemAttributeSafe(btn, link)
    btn._pendingItem = link
    if InCombatLockdown() then return end
    btn:SetAttribute("item", link or "")
    btn._pendingItem = nil
end

local function RefreshSlot(btn)
    local slotID = btn.slotID
    local link = GetInventoryItemLink("player", slotID)
    if link then
        local icon = GetInventoryItemTexture("player", slotID)
        btn.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        btn.icon:Show()
        btn.empty:Hide()
        SetItemAttributeSafe(btn, link)

        -- Cooldown sweep
        local start, duration = C_Container.GetItemCooldown and C_Container.GetItemCooldown(GetInventoryItemID("player", slotID) or 0)
        if not start then
            -- Fallback: use legacy inventory cooldown API
            start, duration = GetInventoryItemCooldown("player", slotID)
        end
        if start and duration and duration > 0 then
            btn.cd:SetCooldown(start, duration)
        else
            btn.cd:Clear()
        end
        return start, duration
    else
        btn.icon:Hide()
        btn.empty:Show()
        SetItemAttributeSafe(btn, "")
        btn.cd:Clear()
        return nil, nil
    end
end

-- Flush any pending item-attribute updates when combat ends.
local combatFlush = CreateFrame("Frame")
combatFlush:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFlush:SetScript("OnEvent", function()
    if not frame then return end
    for _, btn in ipairs({ frame.slot1, frame.slot2 }) do
        if btn and btn._pendingItem ~= nil then
            btn:SetAttribute("item", btn._pendingItem or "")
            btn._pendingItem = nil
        end
    end
end)

function Trinket:Refresh()
    if not frame then return end
    local s1, d1 = RefreshSlot(frame.slot1)
    local s2, d2 = RefreshSlot(frame.slot2)

    -- Status text: shortest active cooldown
    local function Remaining(start, duration)
        if not start or not duration or duration == 0 then return nil end
        return math.max(0, (start + duration) - GetTime())
    end
    local r1 = Remaining(s1, d1)
    local r2 = Remaining(s2, d2)
    local shortest
    if r1 and r1 > 0 and r2 and r2 > 0 then
        shortest = math.min(r1, r2)
    elseif r1 and r1 > 0 then shortest = r1
    elseif r2 and r2 > 0 then shortest = r2
    end

    if shortest then
        frame.status:SetText(string.format("|cffffd700%ds|r", math.ceil(shortest)))
    elseif (s1 or s2) then
        frame.status:SetText("|cff40ff40Ready|r")
    else
        frame.status:SetText("")
    end

    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

function Trinket:GetDesiredHeight() return DESIGN_HEIGHT end

function Trinket:GetStatusText()
    -- Reuse the status text logic (simpler to not compute twice)
    if not frame or not frame.status then return "" end
    return frame.status:GetText() or ""
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function Trinket:Init()
    local f = self:Build()

    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Trinket Tracker",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return Trinket:GetDesiredHeight() end,
        GetStatusText    = function() return Trinket:GetStatusText() end,
    })

    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterEvent("BAG_UPDATE_COOLDOWN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:HookScript("OnEvent", function() Trinket:Refresh() end)

    -- Also tick every half second for smooth CD-remaining text update
    local accum = 0
    f:SetScript("OnUpdate", function(_, dt)
        accum = accum + dt
        if accum < 0.5 then return end
        accum = 0
        Trinket:Refresh()
    end)

    self:Refresh()
end

BazUI:QueueForModule("Drawers", function() Trinket:Init() end)
