-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers: WidgetHost
--
-- Owns the vertical slot layout inside the drawer's display frame.
-- Listens to BazUI's DockableWidget registry and reflows whenever
-- widgets are added/removed/reordered.
--
-- Slot layout:
--   slot
--     ├── titleBar   (clickable, owns widget.label + optional status text
--     │               + collapse chevron; click toggles collapsed state)
--     └── content    (hosts the widget frame, scaled to fit)
--
-- Scaling model:
--   Each widget declares a native designWidth it was built for. The host
--   computes a uniform scale factor (usableWidth / designWidth) and
--   applies it to the widget frame via SetScale. The title bar is NOT
--   scaled - it owns the full slot width so it stays legible regardless
--   of drawer width.
--
-- Widget contract:
--   widget.id                 unique string
--   widget.label              display label
--   widget.designWidth        native width in pixels (default 200)
--   widget.designHeight       native height in pixels (default 60) - initial hint
--   widget.frame              the actual Frame to parent into a slot's content area
--   widget:GetDesiredHeight() optional - overrides designHeight each reflow
--   widget:GetStatusText()    optional - returns (text, r, g, b) for the title bar
--   widget:OnDock(host)       optional - called when parented
--   widget:OnUndock()         optional - called when removed

local addon = BazUI:GetModule("Drawers")

local WidgetHost = {}
addon.WidgetHost = WidgetHost

local SLOT_SPACING = 6
local WIDGET_SIDE_INSET = 4           -- breathing room on each side of the widget inside its slot
local TITLE_HEIGHT = 20
local TITLE_CONTENT_GAP = 2
local DEFAULT_DESIGN_WIDTH = 200
local DEFAULT_DESIGN_HEIGHT = 60
local DRAG_HOLD_TIME = 0.5              -- seconds to hold before drag activates

---------------------------------------------------------------------------
-- Compute the usable interior width of the host. GetWidth() can return 0
-- on the first reflow before anchors have settled, so fall back to the
-- drawer width minus the display-frame + host insets.
---------------------------------------------------------------------------

local DRAWER_DISPLAY_INSET = 8        -- must match Drawer.lua display anchor inset
local DRAWER_HOST_INSET = 4           -- must match Drawer.lua widget host anchor inset

local function ComputeHostWidth(parent)
    local w = parent and parent:GetWidth() or 0
    if w and w > 0 then return w end
    local drawerWidth = addon:GetSetting("width") or 222
    return drawerWidth - DRAWER_DISPLAY_INSET * 2 - DRAWER_HOST_INSET * 2
end

---------------------------------------------------------------------------
-- Initialize
---------------------------------------------------------------------------

function WidgetHost:Initialize(parent)
    self.parent = parent
    self.slots = {}  -- { [id] = slotFrame }

    -- Reflow whenever the widget registry changes.
    local LBW = BazUI.Widgets
    if LBW then
        LBW:RegisterCallback(function() self:Reflow() end)
    elseif BazUI.RegisterDockableWidgetCallback then
        BazUI:RegisterDockableWidgetCallback(function()
            self:Reflow()
        end)
    end

    -- Combat-deferral. Some widgets parent secure children (e.g. the
    -- Trinket Tracker uses SecureActionButtonTemplate buttons), so any
    -- structural change to their frame during combat lockdown - Hide,
    -- SetParent, SetPoint - is blocked by the taint system. We park
    -- pending structural work here and replay it when combat ends.
    self._combatWatcher = self._combatWatcher or CreateFrame("Frame")
    self._combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    self._combatWatcher:SetScript("OnEvent", function()
        if self._reflowPending then
            self._reflowPending = nil
            self:Reflow()
        end
        if self._pendingDisable then
            local list = self._pendingDisable
            self._pendingDisable = nil
            for _, w in ipairs(list) do self:DisableWidget(w) end
        end
        if self._pendingFloat then
            local list = self._pendingFloat
            self._pendingFloat = nil
            for _, entry in ipairs(list) do
                if entry.float then
                    self:FloatWidget(entry.widget)
                else
                    self:DockWidget(entry.widget)
                end
            end
        end
    end)

    self:Reflow()
end

---------------------------------------------------------------------------
-- Slot construction
---------------------------------------------------------------------------

function WidgetHost:CreateSlot(widget)
    local slot = CreateFrame("Frame", nil, self.parent)
    slot._widget = widget

    -- Title bar (unscaled, slot-owned). Click anywhere on it to toggle
    -- the widget's collapsed state.
    local title = CreateFrame("Button", nil, slot)
    title:SetHeight(TITLE_HEIGHT)
    title:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, 0)

    title.bg = title:CreateTexture(nil, "BACKGROUND")
    title.bg:SetAllPoints()
    title.bg:SetColorTexture(0.08, 0.08, 0.12, 0.7)

    -- Slot content background - owned by the slot, drawn beneath the
    -- widget's content area. Widgets no longer draw their own background.
    slot.contentBg = slot:CreateTexture(nil, "BACKGROUND")
    slot.contentBg:SetColorTexture(0.05, 0.05, 0.08, 0.6)

    title.label = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title.label:SetPoint("LEFT", 6, 0)
    title.label:SetText(widget.label or widget.id or "")
    title.label:SetTextColor(1, 0.82, 0)

    title.chevron = title:CreateTexture(nil, "OVERLAY")
    title.chevron:SetSize(16, 16)
    title.chevron:SetPoint("RIGHT", -6, 0)
    BazUI.SetAtlasOrTexture(title.chevron, "ui-questtrackerbutton-secondary-collapse",
        "Interface\\Buttons\\UI-MinusButton-Up")

    title.status = title:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title.status:SetPoint("RIGHT", title.chevron, "LEFT", -6, 0)
    title.status:SetJustifyH("RIGHT")
    title.status:SetText("")

    -- Drag-to-reorder: hold the title bar for DRAG_HOLD_TIME seconds
    -- to activate drag mode (bar turns green). Then drag to reorder.
    -- Short clicks still toggle collapse. Only when unlocked.
    title:RegisterForDrag("LeftButton")
    title._widgetId = widget.id

    title:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if addon:GetSetting("locked") then return end

        -- Start a hold timer - if held long enough, activate drag mode
        self._holdPending = true
        self._holdTimer = C_Timer.NewTimer(DRAG_HOLD_TIME, function()
            if not self._holdPending then return end
            self._holdPending = nil
            self._dragReady = true
            -- Visual: turn green to indicate drag is active
            self.bg:SetColorTexture(0.1, 0.4, 0.1, 0.9)
            WidgetHost:StartDrag(self._widgetId)
        end)
    end)

    title:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end

        if self._holdTimer then
            self._holdTimer:Cancel()
            self._holdTimer = nil
        end

        if self._dragReady then
            -- Was dragging - stop and restore color
            self._dragReady = nil
            self.bg:SetColorTexture(0.15, 0.15, 0.22, 0.9)  -- hovered color (mouse is still over)
            WidgetHost:StopDrag()
        elseif self._holdPending then
            -- Short click - toggle collapse
            self._holdPending = nil
            local collapsed = addon:IsWidgetCollapsed(widget.id)
            addon:SetWidgetCollapsed(widget.id, not collapsed)
            WidgetHost:Reflow()
        end
    end)

    title:SetScript("OnDragStart", function() end)  -- consumed by hold system
    title:SetScript("OnDragStop", function() end)

    title:SetScript("OnEnter", function(self)
        if not self._dragReady then
            self.bg:SetColorTexture(0.15, 0.15, 0.22, 0.9)
        end
    end)
    title:SetScript("OnLeave", function(self)
        if self._holdTimer then
            self._holdTimer:Cancel()
            self._holdTimer = nil
            self._holdPending = nil
        end
        if not self._dragReady then
            self.bg:SetColorTexture(0.08, 0.08, 0.12, 0.7)
        end
    end)

    slot.titleBar = title

    -- Content area (hosts the widget). Sized by Reflow to fit the
    -- scaled widget height.
    local content = CreateFrame("Frame", nil, slot)
    content:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -TITLE_CONTENT_GAP)
    content:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -TITLE_CONTENT_GAP)
    content:SetFrameLevel(slot:GetFrameLevel() + 2)
    slot.content = content

    -- Slot background fills the content area (drawn behind content)
    slot.contentBg:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    slot.contentBg:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    -- Reparent the widget's frame into the slot's content area
    if widget.frame then
        widget.frame:SetParent(content)
        widget.frame:ClearAllPoints()
        widget.frame:Show()
    end

    if widget.OnDock then
        pcall(widget.OnDock, widget, self)
    end

    return slot
end

---------------------------------------------------------------------------
-- Float / Dock transitions
--
-- A widget can live in one of two states:
--   1. Docked   - parented into a slot inside the drawer's widget host
--                 (sized/scaled by Reflow, title bar + collapse, etc.)
--   2. Floating - parented to UIParent with its own saved anchor and
--                 registered with BazUI Edit Mode for drag.
--
-- Transitions are reversible at any time.
---------------------------------------------------------------------------

-- Translate a widget's Ace-style GetOptionsArgs() into BazUI Edit Mode
-- `settings` + `actions` so clicking the floating widget in Edit Mode
-- opens a popup with its configuration. Toggle > checkbox, range > slider,
-- select > dropdown, execute > action button. Other types are skipped.
local function BuildEditModeConfig(widget)
    local settings, actions = {}, {}
    if not widget.GetOptionsArgs then return settings, actions end

    local ok, args = pcall(widget.GetOptionsArgs, widget)
    if not ok or type(args) ~= "table" then return settings, actions end

    -- Sort by order so the popup matches the settings page layout
    local sorted = {}
    for key, opt in pairs(args) do
        if type(opt) == "table" then
            table.insert(sorted, { key = key, opt = opt })
        end
    end
    table.sort(sorted, function(a, b)
        return (a.opt.order or 100) < (b.opt.order or 100)
    end)

    -- Always include nudge controls so every floating widget can be
    -- pixel-positioned via the Edit Mode popup
    table.insert(settings, { type = "nudge" })

    for _, entry in ipairs(sorted) do
        local key, opt = entry.key, entry.opt

        if opt.type == "toggle" then
            table.insert(settings, {
                type = "checkbox",
                key = key,
                label = opt.name or key,
                get = opt.get,
                set = function(v) if opt.set then opt.set(nil, v) end end,
            })
        elseif opt.type == "range" then
            table.insert(settings, {
                type = "slider",
                key = key,
                label = opt.name or key,
                min = opt.min or 0,
                max = opt.max or 100,
                step = opt.step or 1,
                format = opt.format,
                get = opt.get,
                set = function(v) if opt.set then opt.set(nil, v) end end,
            })
        elseif opt.type == "select" then
            -- Ace `values` is either a map { value = label } or a list of
            -- values; the popup dropdown wants an ordered { value, label }
            -- list. Sort the map form by label so the menu is stable.
            local options = {}
            local vals = opt.values
            if type(vals) == "function" then vals = vals() end
            if type(vals) == "table" then
                for k, v in pairs(vals) do
                    if type(k) == "number" and type(v) ~= "string" then
                        -- unusual list shape; skip
                    elseif type(k) == "number" then
                        table.insert(options, { value = v, label = tostring(v) })
                    else
                        table.insert(options, { value = k, label = tostring(v) })
                    end
                end
                table.sort(options, function(a, b) return a.label < b.label end)
            end
            if #options > 0 then
                table.insert(settings, {
                    type = "dropdown",
                    key = key,
                    label = opt.name or key,
                    options = options,
                    get = opt.get,
                    set = function(v) if opt.set then opt.set(nil, v) end end,
                    disabled = (type(opt.disabled) == "function") and opt.disabled or nil,
                })
            end
        elseif opt.type == "execute" then
            table.insert(actions, {
                label = opt.name or key,
                callback = opt.func,
            })
        end
    end

    return settings, actions
end

function WidgetHost:FloatWidget(widget)
    if not widget or not widget.frame then return end

    -- SetParent / SetPoint on protected frames is blocked in combat.
    if InCombatLockdown() then
        self._pendingFloat = self._pendingFloat or {}
        table.insert(self._pendingFloat, { widget = widget, float = true })
        return
    end

    local id = widget.id

    -- Release any existing slot for this widget
    local slot = self.slots[id]
    if slot then
        slot:Hide()
        self.slots[id] = nil
    end

    local f = widget.frame
    f:SetParent(UIParent)
    f:SetScale(1.0)
    f:SetSize(widget.designWidth or 200, widget.designHeight or 60)
    f:ClearAllPoints()

    local pos = addon:GetWidgetPosition(id)
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    f:Show()

    -- Register with BazUI Edit Mode so the user can drag + configure it.
    -- The popup that opens on click is built from the widget's own
    -- GetOptionsArgs so the settings that appear match what's in the
    -- Widgets subcategory of the options panel.
    if BazUI.RegisterEditModeFrame and not widget._editModeRegistered then
        local settings, actions = BuildEditModeConfig(widget)

        -- Always append an "Open Full Settings" action so the user has a
        -- one-click path to the complete options page.
        table.insert(actions, {
            label = "Open Full Settings",
            callback = function()
                if BazUI.OpenOptionsPanel then
                    BazUI:OpenOptionsPanel("Drawers")
                end
            end,
        })

        BazUI:RegisterEditModeFrame(f, {
            label = widget.label or id,
            addonName = "Drawers",
            positionKey = false,
            onPositionChanged = function()
                local point, _, relPoint, x, y = f:GetPoint()
                if point then
                    addon:SetWidgetPosition(id, {
                        point = point, relPoint = relPoint, x = x, y = y,
                    })
                end
            end,
            settings = settings,
            actions  = actions,
        })
        widget._editModeRegistered = true
    end

    widget._floating = true
end

function WidgetHost:DockWidget(widget)
    if not widget or not widget.frame then return end

    -- Reparenting back into a slot during combat is blocked when the
    -- widget owns secure children. Defer the dock and re-run on
    -- PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then
        self._pendingFloat = self._pendingFloat or {}
        table.insert(self._pendingFloat, { widget = widget, float = false })
        return
    end

    -- Unregister from BazUI Edit Mode
    if widget._editModeRegistered and BazUI.UnregisterEditModeFrame then
        BazUI:UnregisterEditModeFrame(widget.frame)
        widget._editModeRegistered = nil
    end

    widget._floating = nil
    -- The next Reflow will re-create a slot and reparent the frame
    self:Reflow()
end

-- Disable the widget entirely: release its slot, unregister it from
-- Edit Mode, and hide its frame. The widget table stays in the
-- registry so it can be re-enabled later.
function WidgetHost:DisableWidget(widget)
    if not widget or not widget.frame then return end

    -- Protected children make Hide a taint risk during combat.
    if InCombatLockdown() then
        self._pendingDisable = self._pendingDisable or {}
        table.insert(self._pendingDisable, widget)
        return
    end

    local id = widget.id

    local slot = self.slots[id]
    if slot then
        slot:Hide()
        self.slots[id] = nil
    end

    if widget._editModeRegistered and BazUI.UnregisterEditModeFrame then
        BazUI:UnregisterEditModeFrame(widget.frame)
        widget._editModeRegistered = nil
    end

    widget.frame:Hide()
    widget._floating = nil
end

-- Public toggle used by the Modules subcategory
function WidgetHost:SetWidgetEnabled(widgetId, enabled)
    -- Record the user's preference first, regardless of whether the
    -- widget is currently live (dockable) or dormant (registered with
    -- the registry but waiting on a condition like "in dungeon queue").
    -- Dormant widgets aren't in the dockable registry yet, so guarding
    -- the saved-variable write behind GetDockableWidget caused the
    -- toggle to silently no-op for them - the user enables a dormant
    -- widget on the Widgets page, navigates to Drawers, and the widget
    -- still appears disabled because IsWidgetEnabled was never updated.
    addon:SetWidgetEnabled(widgetId, enabled)

    -- Live-side mutations only apply when the widget is currently
    -- registered as dockable. Dormant widgets will pick up the new
    -- enable state when their condition triggers a registration.
    local widget = BazUI.GetDockableWidget and BazUI:GetDockableWidget(widgetId)
    if widget then
        if enabled then
            -- Restore: let Reflow pick it back up based on its floating state
            if widget.frame then widget.frame:Show() end
            self:Reflow()
        else
            self:DisableWidget(widget)
        end
    end

    -- Let widgets react to their own enable/disable transition. This is
    -- how the Repair widget re-applies DurabilityFrame suppression after
    -- the user toggles it from the Modules page, for example.
    if addon.RepairWidget and widgetId == "bazdrawer_repair"
       and addon.RepairWidget.ApplyVisibility then
        addon.RepairWidget:ApplyVisibility()
    end

    if addon.Drawer and addon.Drawer.EvaluateFade then
        addon.Drawer:EvaluateFade(true)
    end
end

-- Public toggle used by the settings page
function WidgetHost:SetWidgetFloating(widgetId, shouldFloat)
    local widget = BazUI.GetDockableWidget and BazUI:GetDockableWidget(widgetId)
    if not widget then return end

    addon:SetWidgetFloating(widgetId, shouldFloat)

    if shouldFloat then
        self:FloatWidget(widget)
    else
        self:DockWidget(widget)
    end

    -- Re-evaluate fade state since the slot set changed
    if addon.Drawer and addon.Drawer.EvaluateFade then
        addon.Drawer:EvaluateFade(true)
    end
end

---------------------------------------------------------------------------
-- Apply a fade alpha to each slot's title bar and content bg based on
-- the widget's fadeTitleBar / fadeBackground settings (with global
-- overrides resolved by addon:GetWidgetEffectiveSetting). Called by the
-- Drawer's fade controller whenever the chrome target alpha changes.
---------------------------------------------------------------------------

function WidgetHost:ApplyFadeTargets(chromeAlpha, fullAlpha)
    if not self.slots then return end
    for id, slot in pairs(self.slots) do
        local fadeTitle = addon:GetWidgetEffectiveSetting(id, "fadeTitleBar", true) ~= false
        local fadeBg    = addon:GetWidgetEffectiveSetting(id, "fadeBackground", true) ~= false

        if slot.titleBar then
            slot.titleBar:SetAlpha(fadeTitle and chromeAlpha or fullAlpha)
        end
        if slot.contentBg then
            slot.contentBg:SetAlpha(fadeBg and chromeAlpha or fullAlpha)
        end
    end
end

---------------------------------------------------------------------------
-- Refresh the status text on a slot's title bar without a full reflow.
-- Widgets call this after computing new status so the title bar updates
-- live without causing layout churn.
---------------------------------------------------------------------------

function WidgetHost:UpdateWidgetStatus(widgetId)
    local slot = self.slots and self.slots[widgetId]
    if not slot or not slot.titleBar then return end
    local widget = slot._widget
    if widget and widget.GetStatusText then
        local ok, text, r, g, b = pcall(widget.GetStatusText, widget)
        if ok then
            slot.titleBar.status:SetText(text or "")
            if r and g and b then
                slot.titleBar.status:SetTextColor(r, g, b)
            else
                slot.titleBar.status:SetTextColor(0.8, 0.8, 0.8)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Drag-to-reorder
--
-- Title bars act as drag handles when the drawer is unlocked. During a
-- drag, an OnUpdate handler tracks the cursor Y and swaps widget order
-- when the cursor crosses into a different slot's territory. Reflow is
-- called on each swap so the layout updates in real-time.
---------------------------------------------------------------------------

function WidgetHost:StartDrag(widgetId)
    if self._dragging then return end

    local slot = self.slots and self.slots[widgetId]
    if not slot then return end

    self._dragging = widgetId

    -- OnUpdate handler: check cursor position and swap if needed
    if not self._dragFrame then
        self._dragFrame = CreateFrame("Frame")
    end
    self._dragFrame:SetScript("OnUpdate", function()
        self:DragUpdate()
    end)
end

function WidgetHost:StopDrag()
    if not self._dragging then return end

    self._dragging = nil

    -- Stop the OnUpdate
    if self._dragFrame then
        self._dragFrame:SetScript("OnUpdate", nil)
    end

    -- Persist the current order
    local sorted = addon:GetSortedWidgets()
    for i, w in ipairs(sorted) do
        addon:SetWidgetOrder(w.id, i)
    end

    -- Refresh the settings panel widget list if it's open
    BazUI:RefreshOptions("BazUIDrawer-Widgets")
end

function WidgetHost:DragUpdate()
    if not self._dragging or not self.parent then return end

    -- Detect mouse release globally - OnMouseUp on the originating
    -- title bar won't fire if the cursor moved to a different frame.
    if not IsMouseButtonDown("LeftButton") then
        -- Find the originating title bar and restore its color
        local slot = self.slots and self.slots[self._dragging]
        if slot and slot.titleBar then
            slot.titleBar._dragReady = nil
            slot.titleBar.bg:SetColorTexture(0.08, 0.08, 0.12, 0.7)
        end
        self:StopDrag()
        return
    end

    -- Swap cooldown: don't swap more than ~6 times per second. Without
    -- this, mouse jitter at slot boundaries produces rapid back-and-forth
    -- swaps that feel janky.
    local now = GetTime()
    if self._lastSwapTime and (now - self._lastSwapTime) < 0.15 then
        return
    end

    local _, cursorY = GetCursorPosition()
    local scale = self.parent:GetEffectiveScale()
    cursorY = cursorY / scale

    -- Find the slot whose CENTER the cursor has crossed past (not just
    -- "any slot the cursor is inside"). This gives a natural hysteresis
    -- - a small mouse jitter at a slot boundary can't flip the swap
    -- back-and-forth because the cursor has to physically move past
    -- the target's midline.
    local targetId = self:GetSlotPastMidpoint(cursorY)
    if not targetId or targetId == self._dragging then return end

    self._lastSwapTime = now
    self:SwapWidgetOrder(self._dragging, targetId)
end

-- Returns the slot whose midpoint the cursor has passed toward (relative
-- to the currently-dragged slot). The cursor must be on the side of the
-- target's midpoint that's "away from" the dragged slot before we call
-- it a crossing. Works for both upward and downward drags.
function WidgetHost:GetSlotPastMidpoint(cursorY)
    if not self.slots then return nil end

    local draggedSlot = self.slots[self._dragging]
    if not draggedSlot then return nil end
    local draggedMid
    local dTop, dBot = draggedSlot:GetTop(), draggedSlot:GetBottom()
    if dTop and dBot then draggedMid = (dTop + dBot) * 0.5 end
    if not draggedMid then return nil end

    -- Drag-reorder is scoped to the same stack as the dragged widget:
    -- you can't drag a top-stack widget into the bottom stack (or vice
    -- versa) because they grow from opposite ends - a swap would be
    -- visually nonsense. Switch stacks via the per-widget setting.
    local draggedToBottom = addon:IsWidgetDockedToBottom(self._dragging)

    for id, slot in pairs(self.slots) do
        if id ~= self._dragging and slot:IsShown()
           and addon:IsWidgetDockedToBottom(id) == draggedToBottom then
            local top, bottom = slot:GetTop(), slot:GetBottom()
            if top and bottom then
                local mid = (top + bottom) * 0.5
                -- Dragging DOWN into a lower slot - cursor must be
                -- below that slot's midpoint
                if mid < draggedMid and cursorY <= mid then
                    return id
                end
                -- Dragging UP into a higher slot - cursor must be
                -- above that slot's midpoint
                if mid > draggedMid and cursorY >= mid then
                    return id
                end
            end
        end
    end
    return nil
end

-- Legacy helper kept for back-compat (unused by the new drag logic)
function WidgetHost:GetSlotAtY(cursorY)
    if not self.slots then return nil end
    for id, slot in pairs(self.slots) do
        if slot:IsShown() then
            local top = slot:GetTop()
            local bottom = slot:GetBottom()
            if top and bottom and cursorY <= top and cursorY >= bottom then
                return id
            end
        end
    end
    return nil
end

function WidgetHost:SwapWidgetOrder(idA, idB)
    local orderA = addon:GetWidgetOrder(idA) or 10000
    local orderB = addon:GetWidgetOrder(idB) or 10000
    addon:SetWidgetOrder(idA, orderB)
    addon:SetWidgetOrder(idB, orderA)
    self:Reflow()
end

---------------------------------------------------------------------------
-- Reflow - rebuild the vertical slot stack from the current registry
---------------------------------------------------------------------------

function WidgetHost:Reflow()
    if not self.parent then return end

    -- Defer the entire reflow if we're in combat. Reflow can call
    -- DisableWidget / FloatWidget / slot:Hide on frames that parent
    -- protected children, which the taint system blocks. Run again
    -- on PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then
        self._reflowPending = true
        return
    end

    -- Locked drawers collapse their widget title-bar space so faded-out
    -- title bars don't leave awkward gaps between widgets. When unlocked
    -- the normal TITLE_HEIGHT is used so the title bars stack like usual.
    local locked = addon:GetSetting("locked") and true or false
    local effectiveTitleH = locked and 0 or TITLE_HEIGHT
    local effectiveGap    = locked and 0 or TITLE_CONTENT_GAP

    local allWidgets = addon.GetSortedWidgets and addon:GetSortedWidgets()
        or (BazUI.GetDockableWidgets and BazUI:GetDockableWidgets())
        or {}

    -- Split: disabled widgets are hidden entirely, floating widgets are
    -- handled by FloatWidget (reparented to UIParent, Edit Mode
    -- registered) and NOT included in the slot stack. Docked + enabled
    -- widgets get normal slot treatment.
    local widgets = {}
    for _, w in ipairs(allWidgets) do
        if not addon:IsWidgetEnabled(w.id) then
            self:DisableWidget(w)
        elseif addon:IsWidgetFloating(w.id) then
            self:FloatWidget(w)
        else
            table.insert(widgets, w)
        end
    end

    -- Hide slots whose widgets are no longer docked (either unregistered
    -- or transitioned to floating).
    local seen = {}
    for _, w in ipairs(widgets) do seen[w.id] = true end
    for id, slot in pairs(self.slots) do
        if not seen[id] then
            slot:Hide()
            local w = slot._widget
            if w and w.OnUndock then pcall(w.OnUndock, w) end
            self.slots[id] = nil
        end
    end

    local hostWidth = ComputeHostWidth(self.parent)
    local usableWidth = math.max(hostWidth - WIDGET_SIDE_INSET * 2, 20)

    -- Partition widgets into top and bottom stacks based on each
    -- widget's dockedToBottom setting. Order within each stack
    -- preserves the global widget order so the user reading the
    -- saved order list top-to-bottom matches what they see.
    local topList, bottomList = {}, {}
    for _, w in ipairs(widgets) do
        if addon:IsWidgetDockedToBottom(w.id) then
            bottomList[#bottomList + 1] = w
        else
            topList[#topList + 1] = w
        end
    end

    -- Configure one slot. Returns the computed slot height so the
    -- caller can advance its layout cursor without duplicating the
    -- widget-render math twice (once for each stack).
    local function ConfigureSlot(widget)
        local slot = self.slots[widget.id]
        if not slot then
            slot = self:CreateSlot(widget)
            self.slots[widget.id] = slot
        end

        -- Label can change if widget re-registers; keep it in sync
        slot.titleBar.label:SetText(widget.label or widget.id or "")

        -- Status text + chevron update
        self:UpdateWidgetStatus(widget.id)
        local isCollapsed = addon:IsWidgetCollapsed(widget.id)
        BazUI.SetAtlasOrTexture(slot.titleBar.chevron,
            isCollapsed and "ui-questtrackerbutton-secondary-expand" or "ui-questtrackerbutton-secondary-collapse",
            isCollapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")

        -- Apply the effective title-bar height. When locked, the title
        -- bar collapses to 0 and becomes non-interactive so the widget
        -- content hangs directly below any preceding slot's content.
        slot.titleBar:SetHeight(math.max(effectiveTitleH, 0.001))
        slot.titleBar:SetShown(not locked)
        slot.content:ClearAllPoints()
        slot.content:SetPoint("TOPLEFT",  slot.titleBar, "BOTTOMLEFT",  0, -effectiveGap)
        slot.content:SetPoint("TOPRIGHT", slot.titleBar, "BOTTOMRIGHT", 0, -effectiveGap)

        local designWidth = widget.designWidth or DEFAULT_DESIGN_WIDTH
        local designHeight = widget.designHeight or DEFAULT_DESIGN_HEIGHT
        if widget.GetDesiredHeight then
            local ok, h = pcall(widget.GetDesiredHeight, widget)
            if ok and type(h) == "number" and h > 0 then
                designHeight = h
            end
        end
        local scale = usableWidth / designWidth
        if scale <= 0 then scale = 1 end

        if widget.frame then
            widget.frame:SetSize(designWidth, designHeight)
            widget.frame:SetScale(scale)
            widget.frame:ClearAllPoints()
            widget.frame:SetPoint("TOP", slot.content, "TOP", 0, 0)
        end

        local renderedContentHeight = designHeight * scale

        if isCollapsed then
            slot.content:Hide()
            if slot.contentBg then slot.contentBg:Hide() end
        else
            slot.content:Show()
            slot.content:SetHeight(renderedContentHeight)
            if slot.contentBg then slot.contentBg:Show() end
        end

        local slotHeight = effectiveTitleH
            + (isCollapsed and 0 or (effectiveGap + renderedContentHeight))
        return slot, slotHeight
    end

    -- Top stack: anchor each slot's TOP to the drawer top, marching
    -- downward (yOffset becomes more negative).
    local yOffset = 0
    for _, widget in ipairs(topList) do
        local slot, slotHeight = ConfigureSlot(widget)
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT",  self.parent, "TOPLEFT",  0, yOffset)
        slot:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", 0, yOffset)
        slot:SetHeight(slotHeight)
        slot:Show()
        yOffset = yOffset - slotHeight - SLOT_SPACING
    end

    -- Bottom stack: walk in reverse so the LAST widget in saved order
    -- ends up flush with the drawer bottom and the FIRST sits at the
    -- top of the bottom stack. Each subsequent slot anchors above the
    -- previous one's height + gap.
    local bottomY = 0
    for i = #bottomList, 1, -1 do
        local widget = bottomList[i]
        local slot, slotHeight = ConfigureSlot(widget)
        slot:ClearAllPoints()
        slot:SetPoint("BOTTOMLEFT",  self.parent, "BOTTOMLEFT",  0, bottomY)
        slot:SetPoint("BOTTOMRIGHT", self.parent, "BOTTOMRIGHT", 0, bottomY)
        slot:SetHeight(slotHeight)
        slot:Show()
        bottomY = bottomY + slotHeight + SLOT_SPACING
    end

    if addon.Drawer and addon.Drawer.SetWidgetCount then
        addon.Drawer:SetWidgetCount(#widgets)
    end
end
