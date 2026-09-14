-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazBars Button Module
-- Creates action buttons, dispatches cursor/drag/click events to action
-- handlers (Actions/*.lua), and updates visuals (texture, cooldown, range,
-- usability, charge count, glow, tooltip).
--
-- All button state lives in btn.action = { type = "...", data = {...} }.
-- Every behavior delegates to the handler for that type via the registry.

local BazBars = BazUI.Bars   -- module namespace (was the BazBars global)
local addon = BazUI:GetModule("Bars")
local Button = {}
addon.Button = Button

-- Localized globals for perf
local pairs = pairs
local InCombatLockdown = InCombatLockdown
local ClearCursor = ClearCursor
local IsEquippedItem = C_Item.IsEquippedItem
local GameTooltip = GameTooltip

-- Textures
local EMPTY_SLOT = 136511 -- Interface\PaperDoll\UI-Backpack-EmptySlot
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Pristine Cooldown instance used to call SetCooldown/Clear through its
-- unmodified metatable. Going through `btn.cooldown:SetCooldown(...)`
-- dispatches via the individual frame's (potentially tainted) method
-- table - in combat that taint path can make SetCooldown silently
-- no-op, which is why our cooldown animations were missing during
-- combat. Using the prototype's method directly bypasses that.
-- Same pattern as Blizzard's ActionButton (Blizzard_ActionBar/Shared/
-- ActionButton.lua:890).
local CooldownPrototype = CreateFrame("Cooldown")

---------------------------------------------------------------------------
-- Handler helper
---------------------------------------------------------------------------

-- Returns (handler, data) for the button's current action, or nil if empty.
local function GetHandler(btn)
    if not btn.action then return nil end
    local handler = BazBars.Actions:Get(btn.action.type)
    if not handler then return nil end
    return handler, btn.action.data
end

---------------------------------------------------------------------------
-- Visuals
---------------------------------------------------------------------------

function Button:UpdateTexture(btn)
    local icon = btn.icon

    if not btn.action then
        icon:Hide()
        CooldownPrototype.Clear(btn.cooldown)
        if btn.bbShowEmpty then
            btn:SetNormalTexture(EMPTY_SLOT)
        else
            btn:SetNormalTexture("")
        end
        return
    end

    local tex = Button:GetTexture(btn)
    if tex then
        icon:SetTexture(tex)
    else
        icon:SetTexture(QUESTION_MARK)
    end
    icon:Show()
end

function Button:GetTexture(btn)
    local handler, data = GetHandler(btn)
    if handler and handler.getIcon then
        return handler.getIcon(data)
    end
end

function Button:UpdateCooldown(btn)
    local handler, data = GetHandler(btn)
    if not handler then
        CooldownPrototype.Clear(btn.cooldown)
        btn.cooldown:Hide()
        return
    end

    -- Preferred path: handler applies the cooldown directly via Midnight's
    -- SetCooldownFromDurationObject (the only path that survives combat
    -- taint). Each handler owns its own cooldown update because the
    -- underlying API differs per type (spells use GetSpellCooldownDuration,
    -- items use GetItemCooldown numbers, etc.).
    if handler.applyCooldown then
        handler.applyCooldown(data, btn.cooldown)
        return
    end

    -- Legacy fallback: handler returns raw (start, duration) numbers.
    -- Used by Item and Toy handlers which don't have a duration-object
    -- API. Still routes through CooldownPrototype to avoid taint on the
    -- method dispatch itself.
    if handler.getCooldown then
        local start, duration = handler.getCooldown(data)
        if start and duration and duration > 0 then
            btn.cooldown:Show()
            CooldownPrototype.SetCooldown(btn.cooldown, start, duration)
        else
            CooldownPrototype.Clear(btn.cooldown)
            btn.cooldown:Hide()
        end
        return
    end

    CooldownPrototype.Clear(btn.cooldown)
    btn.cooldown:Hide()
end

function Button:UpdateUsable(btn)
    if not btn.action then return end

    local outOfRange = btn._outOfRange and true or false
    -- "Tint the whole button when out of range" off leaves the icon and
    -- frame alone and reddens only the keybind text, so the usable
    -- colours below still have to run in that case.
    local tintAll = outOfRange and addon.db.profile.fullRangeColor ~= false

    if tintAll then
        btn.icon:SetVertexColor(0.8, 0.1, 0.1)
        if btn.NormalTexture then btn.NormalTexture:SetVertexColor(0.8, 0.1, 0.1) end
        if btn.Name then btn.Name:SetVertexColor(0.8, 0.1, 0.1) end
        if btn.HotKey then btn.HotKey:SetVertexColor(0.8, 0.1, 0.1) end
        return
    end

    local handler, data = GetHandler(btn)
    if handler and handler.isUsable then
        local isUsable, insufficientPower = handler.isUsable(data)
        if isUsable then
            btn.icon:SetVertexColor(1.0, 1.0, 1.0)
        elseif insufficientPower then
            btn.icon:SetVertexColor(0.5, 0.5, 1.0)
        else
            btn.icon:SetVertexColor(0.4, 0.4, 0.4)
        end
    else
        btn.icon:SetVertexColor(1.0, 1.0, 1.0)
    end

    if btn.NormalTexture then btn.NormalTexture:SetVertexColor(1.0, 1.0, 1.0) end
    if btn.Name then btn.Name:SetVertexColor(1.0, 1.0, 1.0) end
    if btn.HotKey then
        if outOfRange then
            btn.HotKey:SetVertexColor(0.8, 0.1, 0.1)
        else
            btn.HotKey:SetVertexColor(0.6, 0.6, 0.6)
        end
    end
end

function Button:UpdateRange(btn)
    if not btn.action then return end

    local outOfRange = false
    if UnitExists("target") then
        local handler, data = GetHandler(btn)
        if handler and handler.isInRange then
            local inRange = handler.isInRange(data, "target")
            if inRange == false then outOfRange = true end
        end
    end

    if outOfRange == btn._outOfRange then return end
    btn._outOfRange = outOfRange
    Button:UpdateUsable(btn)
end

function Button:UpdateCount(btn)
    local handler, data = GetHandler(btn)
    if handler and handler.getCount then
        btn.Count:SetText(handler.getCount(data) or "")
    else
        btn.Count:SetText("")
    end
end

function Button:ShowTooltip(btn)
    if not btn.action then return end
    if addon.db.profile.showTooltips == false then return end

    local handler, data = GetHandler(btn)
    if not handler or not handler.showTooltip then return end

    if addon.db.profile.tooltipAnchor == "button" then
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    else
        GameTooltip_SetDefaultAnchor(GameTooltip, btn)
    end
    handler.showTooltip(data)
    GameTooltip:Show()
end

-- Blizzard's checked state: lit while the action is current.
function Button:UpdateChecked(btn)
    if not btn.Checked then return end
    local handler, data = GetHandler(btn)
    local on = handler and handler.isCurrent and handler.isCurrent(data)
    btn.Checked:SetShown(on and true or false)
end

function Button:UpdateGlow(btn)
    local handler, data = GetHandler(btn)
    if handler and handler.hasProcGlow and handler.hasProcGlow(data) then
        BazUI:ShowGlow(btn)
    else
        BazUI:HideGlow(btn)
    end
end

function Button:UpdateEquipped(btn)
    -- Only the Item handler has an item id that can be "equipped"
    if btn.action and btn.action.type == "item"
        and btn.action.data and btn.action.data.id
        and IsEquippedItem(btn.action.data.id)
    then
        if not btn.bbEquipBorder then
            btn.bbEquipBorder = btn:CreateTexture(nil, "OVERLAY")
            BazUI.SetAtlasOrTexture(btn.bbEquipBorder, "UI-HUD-ActionBar-IconFrame-Border", nil)
            btn.bbEquipBorder:SetAllPoints()
        end
        btn.bbEquipBorder:SetVertexColor(0, 1.0, 0, 0.5)
        btn.bbEquipBorder:Show()
    else
        if btn.bbEquipBorder then
            btn.bbEquipBorder:Hide()
        end
    end
end

function Button:UpdateMacroName(btn)
    if not btn.Name then return end
    if addon.db.profile.showMacroNames == false then
        btn.Name:SetText("")
        btn.Name:Hide()
        return
    end

    if btn.action and btn.action.type == "macro" and btn.action.data and btn.action.data.name then
        btn.Name:SetText(btn.action.data.name)
        btn.Name:Show()
    else
        btn.Name:SetText("")
    end
end

---------------------------------------------------------------------------
-- Full button update (called on events)
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Flyout arrow
--
-- The small arrow marking a slot that opens into more, pointing the way
-- the popup will open. Blizzard's own flyout art ships on this client
-- even though the client has no flyouts of its own, so the arrow
-- matches the one players know from the spellbook.
---------------------------------------------------------------------------

-- Blizzard's flyout arrow is a wide, short strip, and rotating one of
-- those a quarter turn stretches it: the rotation is applied in the
-- texture's own space, so it only comes out true on a square. This art
-- is square and points right, which means all four directions are the
-- same texture at four rotations, with nothing distorted.
local FLYOUT_ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

local FLYOUT_ARROW_LOOK = {
    RIGHT = { point = "RIGHT",  x =  7, y =  0, rotation = 0 },
    UP    = { point = "TOP",    x =  0, y =  7, rotation = math.pi / 2 },
    LEFT  = { point = "LEFT",   x = -7, y =  0, rotation = math.pi },
    DOWN  = { point = "BOTTOM", x =  0, y = -7, rotation = -math.pi / 2 },
}

-- The offset above keeps pace with the size: the arrow sits just off
-- the button's edge rather than growing further over the icon.
local FLYOUT_ARROW_SIZE = 20

function Button:UpdateFlyoutArrow(btn)
    local isFlyout = btn.action and btn.action.type == "flyout"
    if not isFlyout then
        if btn.bbFlyoutArrow then btn.bbFlyoutArrow:Hide() end
        return
    end

    local look = FLYOUT_ARROW_LOOK[btn.action.data and btn.action.data.direction or "UP"]
        or FLYOUT_ARROW_LOOK.UP

    local arrow = btn.bbFlyoutArrow
    if not arrow then
        arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture(FLYOUT_ARROW)
        btn.bbFlyoutArrow = arrow
    end
    -- Size and colour are set on every update rather than at creation,
    -- so changing either takes effect without rebuilding the bars.
    arrow:SetSize(FLYOUT_ARROW_SIZE, FLYOUT_ARROW_SIZE)
    -- The full accent gold, not the soft one: this is a marker that has
    -- to catch the eye against a bright spell icon.
    arrow:SetVertexColor(unpack(BazUI.Skin.Theme.colors.gold))
    arrow:SetRotation(look.rotation)
    arrow:ClearAllPoints()
    arrow:SetPoint(look.point, btn, look.point, look.x, look.y)
    arrow:Show()
end

function Button:UpdateButton(btn)
    Button:UpdateTexture(btn)
    Button:UpdateCooldown(btn)
    Button:UpdateUsable(btn)
    Button:UpdateCount(btn)
    Button:UpdateGlow(btn)
    Button:UpdateChecked(btn)
    Button:UpdateEquipped(btn)
    Button:UpdateMacroName(btn)
    Button:UpdateFlyoutArrow(btn)
end

---------------------------------------------------------------------------
-- Drag and drop
---------------------------------------------------------------------------

function Button:ReceiveDrag(btn)
    if InCombatLockdown() then
        ClearCursor()
        return
    end

    local handler, newData = BazBars.Actions:FromCursor()
    if not handler then return end

    ClearCursor()

    -- Swap: put current contents back on the cursor so the user can chain
    Button:PickUpCurrent(btn)

    Button:SetActionFromHandler(btn, handler, newData)
end

function Button:StartDrag(btn)
    if InCombatLockdown() then return end

    -- Locked bars don't allow dragging.
    if btn.bbBarData and btn.bbBarData.locked then return end

    -- With the General setting on, only a Shift-drag picks a button up;
    -- a plain drag does nothing and the click still casts on release.
    if addon.db.profile.dragRequiresShift and not IsShiftKeyDown() then return end

    if not btn.action then return end

    local handler = BazBars.Actions:Get(btn.action.type)
    if handler and handler.pickup then
        handler.pickup(btn.action.data)
    end
    Button:ClearAction(btn)
end

-- Put whatever's currently on the button onto the cursor (for swaps).
-- Returns true if something was picked up.
function Button:PickUpCurrent(btn)
    if not btn.action then return false end
    local handler = BazBars.Actions:Get(btn.action.type)
    if not handler or not handler.pickup then return false end
    handler.pickup(btn.action.data)
    return true
end

-- Apply a handler-based action to a button.
function Button:SetActionFromHandler(btn, handler, data)
    -- Leaving a flyout behind: take its popup wiring off the slot before
    -- the new action sets its own attributes.
    if btn.action and btn.action.type == "flyout" and handler.type ~= "flyout"
        and addon.FlyoutPopup then
        addon.FlyoutPopup:DetachFrom(btn)
    end

    btn.action = { type = handler.type, data = data }

    local selfCast = btn.bbBarData and btn.bbBarData.rightClickSelfCast
    BazBars.Actions:Apply(btn, btn.action, selfCast)

    Button:UpdateButton(btn)
    Button:SaveButton(btn)
end

function Button:ClearAction(btn)
    if addon.FlyoutPopup then addon.FlyoutPopup:DetachFrom(btn) end
    btn.action = nil
    BazBars.Actions:ClearButtonAttributes(btn)
    Button:UpdateButton(btn)
    Button:SaveButton(btn)
end

---------------------------------------------------------------------------
-- Self-cast on right-click
---------------------------------------------------------------------------

function Button:ApplySelfCast(barFrame)
    local enabled = barFrame.barData.rightClickSelfCast
    for _, row in pairs(barFrame.buttons) do
        for _, btn in pairs(row) do
            -- Clear existing self-cast attrs
            btn:SetAttribute("type2", nil)
            btn:SetAttribute("spell2", nil)
            btn:SetAttribute("item2", nil)
            btn:SetAttribute("unit2", nil)

            if enabled and btn.action then
                local handler = BazBars.Actions:Get(btn.action.type)
                if handler and handler.applySelfCast then
                    handler.applySelfCast(btn, btn.action.data)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Save / load
---------------------------------------------------------------------------

function Button:SaveButton(btn)
    -- Sanity: bar must still exist in the profile (structure check).
    -- The actual payload lands in the per-character bucket via
    -- addon:SetButtonPayload, NOT in profile.bars[id].buttons.
    if not addon.db.profile.bars[btn.bbBarID] then return end
    local key = btn.bbRow .. ":" .. btn.bbCol

    if btn.action then
        addon:SetButtonPayload(btn.bbBarID, key,
            BazBars.Actions:Serialize(btn.action))
    else
        addon:SetButtonPayload(btn.bbBarID, key, nil)
    end
end

function Button:LoadButton(btn)
    if not addon.db.profile.bars[btn.bbBarID] then return end

    local key = btn.bbRow .. ":" .. btn.bbCol
    local saved = addon:GetButtonPayload(btn.bbBarID, key)
    if not saved then return end

    -- New format: { type = "...", data = {...} }
    if saved.type and saved.data then
        local action = BazBars.Actions:Deserialize(saved)
        if action then
            local handler = BazBars.Actions:Get(action.type)
            if handler then
                Button:SetActionFromHandler(btn, handler, action.data)
            end
        end
        return
    end

    -- Legacy format: { command, value, subValue, id, macrotext }
    -- Try to migrate via a registered handler's migrate() method.
    if saved.command then
        local action = BazBars.Actions:MigrateLegacy(saved)
        if action then
            local handler = BazBars.Actions:Get(action.type)
            if handler then
                Button:SetActionFromHandler(btn, handler, action.data)
            end
        end
    end
end

---------------------------------------------------------------------------
-- XML script handlers (wired by Bars.xml)
---------------------------------------------------------------------------

function BazBars.OnButtonEnter(self)
    Button:ShowTooltip(self)
end

function BazBars.OnButtonReceiveDrag(self)
    Button:ReceiveDrag(self)
end

function BazBars.OnButtonDragStart(self)
    Button:StartDrag(self)
end

---------------------------------------------------------------------------
-- bar-slot context menu section
--
-- Registered against the shared "bar-slot" scope so other modules can
-- append entries. Filled slots offer "Clear button"; empty slots have
-- nothing to offer.
---------------------------------------------------------------------------

-- The shape of a flyout is small enough to live in the menu, which
-- saves a dialog and means every way of changing a slot is in the one
-- place you already right-click.
local DIRECTION_LABELS = { UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right" }
local DIRECTION_ORDER  = { "UP", "DOWN", "LEFT", "RIGHT" }

local function FlyoutShapeItems(btn, data)
    local Flyout = addon.FlyoutHandler
    if not Flyout then return {} end

    local directions = {}
    for _, key in ipairs(DIRECTION_ORDER) do
        directions[#directions + 1] = {
            label = DIRECTION_LABELS[key] .. ((data.direction or "UP") == key and "  *" or ""),
            onClick = function() Flyout:SetShape(btn, "direction", key) end,
        }
    end

    local function CountItems(key, upTo, current)
        local items = {}
        for n = 1, upTo do
            items[#items + 1] = {
                label = tostring(n) .. (current == n and "  *" or ""),
                onClick = function() Flyout:SetShape(btn, key, n) end,
            }
        end
        return items
    end

    return {
        { label = "Opens towards", submenu = directions },
        { label = "Rows",    submenu = CountItems("rows", 4, data.rows or 1) },
        { label = "Columns", submenu = CountItems("cols", 8, data.cols or 3) },
        {
            label = (data.mode == "specific")
                and "Button casts: the pinned action"
                or  "Button casts: whatever you used last",
            onClick = function()
                if InCombatLockdown() then return end
                Flyout:SetShape(btn, "mode",
                    data.mode == "specific" and "lastUsed" or "specific")
            end,
        },
    }
end

local function GetBarSlotSection(ctx)
    if not ctx or not ctx.button then return end
    local btn = ctx.button
    local Flyout = addon.FlyoutHandler

    -- An empty slot has one useful thing to offer.
    if not ctx.action then
        if not Flyout then return end
        return {
            {
                label = "Create a flyout here",
                onClick = function()
                    if InCombatLockdown() then return end
                    local handler = BazBars.Actions:Get("flyout")
                    if not handler then return end
                    Button:SetActionFromHandler(btn, handler, Flyout.MakeDefault())
                    -- Open it straight away: an empty flyout is the one
                    -- thing you always want to fill in immediately.
                    local popup = btn._bazFlyoutPopup
                    if popup then popup:Show() end
                end,
            },
        }
    end

    local items = {}
    if ctx.action.type == "flyout" and Flyout then
        for _, item in ipairs(FlyoutShapeItems(btn, ctx.action.data)) do
            items[#items + 1] = item
        end
        items[#items + 1] = { divider = true }
    end

    items[#items + 1] = {
        label = "Clear button",
        onClick = function()
            if InCombatLockdown() then return end
            Button:ClearAction(btn)
        end,
    }
    return items
end

if BazUI.RegisterContextMenuSection then
    BazUI:RegisterContextMenuSection("bar-slot", "Bars", GetBarSlotSection)
end

function BazBars.OnButtonPostClick(self, button)
    if InCombatLockdown() then return end

    -- Shift+Right-Click opens a context menu. BazBars's own actions
    -- (spawn flyout / configure flyout / clear button) live as
    -- entries in that menu, sharing the popup with any other addon
    -- that registers under the "bar-slot" scope (BazTooltipEditor's
    -- "Inspect this tooltip" being the first such consumer).
    if button == "RightButton" and IsShiftKeyDown() then
        if BazUI.OpenContextMenu then
            -- No title intentionally - the slot's icon is already
            -- visible right next to the menu, so a title would just
            -- echo what the user can see. Bag-stack menus need the
            -- item link as a title to disambiguate stack vs single,
            -- but bar slots don't have that ambiguity.
            BazUI:OpenContextMenu("bar-slot", self, {
                button = self,
                action = self.action,
            })
        end
        return
    end

    Button:UpdateButton(self)
end
