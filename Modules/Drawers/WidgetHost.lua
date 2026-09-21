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

local DEFAULT_SLOT_SPACING = 6        -- vertical gap between docked widgets; the widgetSpacing setting overrides it
local WIDGET_SIDE_INSET = 4           -- breathing room on each side of the widget inside its slot
-- Long edge of the reorder arrows on a title bar. The art is twice as
-- wide as it is deep, so this is a 16 by 8 arrow in a 16 square button.
local ARROW_SIZE = 16
local ARROW_ALPHA_IDLE, ARROW_ALPHA_OFF = 0.75, 0.25

-- The game's own red cross, which the bag already marks junk with.
local REMOVE_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local REMOVE_SIZE = 12
local TITLE_HEIGHT = 20
local TITLE_CONTENT_GAP = 2
local DEFAULT_DESIGN_WIDTH = 200
local DEFAULT_DESIGN_HEIGHT = 60
local DRAG_HOLD_TIME = 0.5              -- seconds to hold before drag activates

-- What a title bar looks like: sitting there, under the mouse, and armed
-- for a drag. Written out at each of the places that set one, which is
-- how the drag color and the hover color came to disagree about which
-- gray they were.
local TITLE_BG_IDLE  = { 0.08, 0.08, 0.12, 0.7 }
local TITLE_BG_HOVER = { 0.15, 0.15, 0.22, 0.9 }
local TITLE_BG_DRAG  = { 0.10, 0.40, 0.10, 0.9 }

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
        -- A fight can have refused a placement outright; everything
        -- that is floating gets its spot confirmed now either way.
        self:PlaceAllFloating()
    end)

    self:Reflow()

    -- And once the interface has finished coming up. Widgets register
    -- across several frames of the login, and a few of them anchor
    -- their own frame as they do, so the last word has to be ours.
    C_Timer.After(0, function() self:PlaceAllFloating() end)
    C_Timer.After(1, function() self:PlaceAllFloating() end)
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
    title.bg:SetColorTexture(unpack(TITLE_BG_IDLE))

    -- Slot content background - owned by the slot, drawn beneath the
    -- widget's content area. Widgets no longer draw their own background.
    slot.contentBg = slot:CreateTexture(nil, "BACKGROUND")
    slot.contentBg:SetColorTexture(0.05, 0.05, 0.08, 0.6)

    title.label = BazUI.Skin.Theme.FontString(title, "OVERLAY", "GameFontNormalSmall")
    title.label:SetPoint("LEFT", 6, 0)
    title.label:SetText(widget.label or widget.id or "")
    title.label:SetTextColor(1, 0.82, 0)

    -- Shown with the buttons rather than always: a widget that is
    -- collapsed already looks collapsed, so this mark was repeating what
    -- the empty space under it had already said.
    title.chevron = title:CreateTexture(nil, "OVERLAY")
    title.chevron:SetSize(16, 16)
    title.chevron:Hide()
    BazUI.SetAtlasOrTexture(title.chevron, "ui-questtrackerbutton-secondary-collapse",
        "Interface\\Buttons\\UI-MinusButton-Up")

    title.status = BazUI.Skin.Theme.FontString(title, "OVERLAY", "GameFontHighlightSmall")
    -- Against the bar's own edge, because what used to hold it in from
    -- there - the chevron - is not there most of the time now.
    title.status:SetPoint("RIGHT", title, "RIGHT", -6, 0)
    title.status:SetJustifyH("RIGHT")
    title.status:SetText("")

    -- Two arrows, in the space the status text was using.
    --
    -- Hold-then-drag works, but nothing about a title bar says it can be
    -- held, and a gesture that needs to be known about before it can be
    -- found is not a way to reorder anything. A pair of arrows under the
    -- cursor is.
    --
    -- They take the status text's place rather than sitting beside it:
    -- pointing at a title bar is wanting to do something to the widget,
    -- not wanting to read how many quests it is tracking, and reserving
    -- room for both would cost every widget the width of two buttons it
    -- only needs while the mouse is on it.
    title.controls = {}

    -- Everything shared by the buttons that appear on hover: the size,
    -- the icon, and knowing to put the whole set away when the cursor
    -- leaves. Each one adds what it does and when it can do it.
    local function MakeControl()
        local btn = CreateFrame("Button", nil, title)
        btn:SetSize(ARROW_SIZE, ARROW_SIZE)
        btn:Hide()

        btn.icon = btn:CreateTexture(nil, "OVERLAY")
        btn.icon:SetPoint("CENTER")

        btn:SetScript("OnLeave", function(self)
            if self:IsEnabled() then self.icon:SetAlpha(ARROW_ALPHA_IDLE) end
            GameTooltip:Hide()
            title:HideControls()
        end)

        title.controls[#title.controls + 1] = btn
        return btn
    end

    -- Alpha rather than a tint, for the arrows at least: the art is gray
    -- and a vertex color multiplies, so it can only ever be made darker.
    local function Lit(self)
        if self:IsEnabled() then self.icon:SetAlpha(1) end
    end

    local function MakeArrow(direction, delta)
        local btn = MakeControl()
        BazUI.SetArrowTexture(btn.icon, direction, ARROW_SIZE)
        btn.Available = function()
            return WidgetHost:MoveInStack(title._widgetId, delta, true)
        end
        btn:SetScript("OnClick", function()
            WidgetHost:MoveInStack(title._widgetId, delta)
        end)
        btn:SetScript("OnEnter", Lit)
        return btn
    end

    -- Taking a widget off the drawer, which is not the same as switching
    -- it off: it stays enabled and keeps its settings, and it is still on
    -- any other drawer it was put on. Reversible from the options, which
    -- the tooltip says, because a cross usually means something is gone
    -- for good and this one does not.
    local function MakeRemove()
        local btn = MakeControl()
        btn.icon:SetTexture(REMOVE_TEXTURE)
        btn.icon:SetSize(REMOVE_SIZE, REMOVE_SIZE)
        btn.Available = function() return not InCombatLockdown() end
        btn:SetScript("OnClick", function()
            addon:RemoveWidgetFromDrawer(addon:GetActiveDrawerId(), title._widgetId)
        end)
        btn:SetScript("OnEnter", function(self)
            Lit(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Take this off the drawer", 1, 1, 1)
            GameTooltip:AddLine("It keeps its settings. Settings, Drawers puts it back.",
                0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        return btn
    end

    title.moveUp   = MakeArrow("UP", -1)
    title.moveDown = MakeArrow("DOWN", 1)
    title.remove   = MakeRemove()

    -- Right to left: the cross, the collapse mark, then the two arrows.
    -- Closing sits furthest out, where a window's close button lives.
    title.remove:SetPoint("RIGHT", title, "RIGHT", -6, 0)
    title.chevron:SetPoint("RIGHT", title.remove, "LEFT", -6, 0)
    title.moveDown:SetPoint("RIGHT", title.chevron, "LEFT", -6, 0)
    title.moveUp:SetPoint("RIGHT", title.moveDown, "LEFT", -2, 0)

    -- Shown together, each grayed unless it has something to do. An
    -- arrow at the end of the stack is drawn faint and does nothing,
    -- which reads better than one that vanishes and leaves the other
    -- somewhere else.
    function title:ShowControls()
        if addon:GetSetting("locked") then return end
        for _, btn in ipairs(self.controls) do
            local can = btn.Available and btn.Available() and true or false
            btn:SetEnabled(can)
            btn.icon:SetAlpha(can and ARROW_ALPHA_IDLE or ARROW_ALPHA_OFF)
            btn:Show()
        end
        self.chevron:Show()
        self.status:Hide()
    end

    -- The cursor moving onto one of the buttons takes it off the title
    -- bar, so none of them can decide this alone.
    function title:HideControls()
        if self:IsMouseOver() then return end
        for _, btn in ipairs(self.controls) do
            if btn:IsMouseOver() then return end
        end
        for _, btn in ipairs(self.controls) do btn:Hide() end
        self.chevron:Hide()
        self.status:Show()
    end

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
            self.bg:SetColorTexture(unpack(TITLE_BG_DRAG))
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
            self.bg:SetColorTexture(unpack(TITLE_BG_HOVER))
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
            self.bg:SetColorTexture(unpack(TITLE_BG_HOVER))
        end
        self:ShowControls()
    end)
    title:SetScript("OnLeave", function(self)
        if self._holdTimer then
            self._holdTimer:Cancel()
            self._holdTimer = nil
            self._holdPending = nil
        end
        if not self._dragReady then
            self.bg:SetColorTexture(unpack(TITLE_BG_IDLE))
        end
        self:HideControls()
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

    -- And how big it draws, for the same reason: floating, nothing else
    -- decides. A widget that scales its own contents is skipped here and
    -- brings its own control through GetOptionsArgs below, so there is
    -- exactly one scale on this panel either way and the two can never
    -- disagree.
    if not widget.ownsScale then
        local id = widget.id
        table.insert(settings, {
            type = "slider",
            key = "bazScale",
            label = "Scale",
            min = 0.5, max = 2.0, step = 0.05,
            format = function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end,
            get = function() return addon:GetWidgetScale(id) end,
            set = function(v)
                if addon.WidgetHost then addon.WidgetHost:SetWidgetScale(id, v) end
            end,
        })
    end

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

-- Where a floating widget sits, written down so that scale cannot move it.
--
-- A position is the frame's center as a screen-pixel offset from the
-- middle of the screen, which is the shape every other BazUI frame is
-- saved in. The old shape was whatever GetPoint happened to return - a
-- point, a point on the screen to hang off, and an offset in the
-- frame's own units. Those units are scaled, so scaling the widget
-- multiplied the offset and the widget slid: down and left as it
-- shrank, up and right as it grew, along the line back to whatever
-- corner it was anchored from.
--
-- Screen pixels do not scale, so this one stays where it is put and
-- grows about its own center.
function WidgetHost:SaveFloatingPosition(widget)
    if not (widget and widget.frame) then return end
    local f = widget.frame
    local cx, cy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return end
    local es, ues = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    addon:SetWidgetPosition(widget.id, {
        x = cx * es - ux * ues,
        y = cy * es - uy * ues,
    })
end

-- Where a floating widget goes, and the only code that decides it.
function WidgetHost:PlaceFloating(widget)
    if not (widget and widget.frame) then return false end
    if InCombatLockdown() and widget.frame:IsProtected() then return false end

    local pos = addon:GetWidgetPosition(widget.id)
    local f = widget.frame
    f:ClearAllPoints()

    if pos and pos.point then
        -- Saved the old way, in the frame's own units. Place it where it
        -- says, then write it down again in screen pixels so it is only
        -- ever read like this once.
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point,
            pos.x or 0, pos.y or 0)
        self:SaveFloatingPosition(widget)
    elseif pos and pos.x and pos.y then
        local es = f:GetEffectiveScale()
        f:SetPoint("CENTER", UIParent, "CENTER", pos.x / es, pos.y / es)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    return true
end

-- Put every floating widget back where it belongs.
--
-- Logging in used to leave them stacked in the middle of the screen. The
-- placement itself was right; what was wrong is that it happened once,
-- at whatever point in the boot order the widget registered, and
-- anything that anchored the frame afterwards won - a widget that
-- anchors itself at Init so it has a resolved position before the dock
-- arrives, which several of them do for good reasons of their own.
--
-- So we place them again once the interface has settled, and again when
-- a fight that refused it ends. Placing a frame that is already in the
-- right spot costs nothing.
function WidgetHost:PlaceAllFloating()
    for _, widget in ipairs(BazUI.GetDockableWidgets and BazUI:GetDockableWidgets() or {}) do
        if widget._floating then
            self:PlaceFloating(widget)
        end
    end
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
    -- Docked, Reflow scales the widget to fill the drawer. Floating,
    -- there is nothing to fill, so it draws at whatever size the player
    -- asked for - and 1 for a widget that scales its own insides.
    f:SetScale(widget.ownsScale and 1 or addon:GetWidgetScale(id))
    f:SetSize(widget.designWidth or 200, widget.designHeight or 60)
    widget._floating = true
    self:PlaceFloating(widget)
    f:Show()

    -- Tell the widget it is on its own, the way releasing a slot does.
    --
    -- A widget's contract is OnDock when it is parented into a slot and
    -- OnUndock when it is taken out of one, and floating used to satisfy
    -- that only by accident: you docked first, then floated, so the slot
    -- release fired OnUndock on the way past. With no drawer a widget
    -- floats from login and is never in a slot at all, so neither hook
    -- ran - and the minimap does its reattach in OnUndock, so the map
    -- came up parented to nothing that had been told to hold it, with
    -- the wrapper still at the alpha it was born with.
    if widget.OnUndock then pcall(widget.OnUndock, widget) end

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
                WidgetHost:SaveFloatingPosition(widget)
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

-- Live scale change for a floating widget.
--
-- The frame is placed again afterwards: a position saved as an offset
-- from the middle of the screen is divided by the frame's effective
-- scale to land, so changing the scale without re-placing walks the
-- widget across the screen.
function WidgetHost:SetWidgetScale(widgetId, value)
    addon:SetWidgetScale(widgetId, value)

    local widget = BazUI.GetDockableWidget and BazUI:GetDockableWidget(widgetId)
    if not (widget and widget.frame) then return end
    if widget.ownsScale then return end

    if addon:IsWidgetFloating(widgetId) then
        widget.frame:SetScale(addon:GetWidgetScale(widgetId))
        self:PlaceFloating(widget)
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
    -- Kept so a slot built later can be brought to the same state. The
    -- drawer only calls this when its fade changes, and a slot that did
    -- not exist at the time would otherwise never hear about it.
    self._chromeAlpha, self._fullAlpha = chromeAlpha, fullAlpha

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
-- Dragging a widget to reorder it
--
-- Holding a title bar arms the drag - the bar turns green to say so - and
-- from then until the mouse comes up the widget changes places whenever
-- the cursor passes the middle of a neighbour.
--
-- The middle, rather than the edge, is what stops it flickering: swapping
-- the moment the cursor touched a neighbour would put the widget where
-- the cursor already is, which is immediately a reason to swap back. Past
-- the halfway point, the swap leaves the cursor inside the widget's own
-- new place and nothing more happens until it moves further.
--
-- One step at a time, too. Only the neighbour above and the neighbour
-- below are considered, so a long drag walks the widget through the
-- stack rather than teleporting it and leaving the rest to work out where
-- they went.
---------------------------------------------------------------------------

local function SlotMidY(slot)
    local top, bottom = slot:GetTop(), slot:GetBottom()
    if not (top and bottom) then return nil end
    return (top + bottom) / 2
end

-- The docked widgets sharing a stack with this one, in drawn order. The
-- drawer has two - the ordinary one and whatever is pinned to the bottom
-- - and a widget can only be reordered within its own.
function WidgetHost:StackOrder(widgetId)
    local wantBottom = addon:IsWidgetDockedToBottom(widgetId) and true or false
    local out = {}
    for _, w in ipairs(addon:GetSortedWidgets() or {}) do
        local bottom = addon:IsWidgetDockedToBottom(w.id) and true or false
        if bottom == wantBottom
            and addon:IsWidgetEnabled(w.id)
            and not addon:IsWidgetFloating(w.id) then
            out[#out + 1] = w.id
        end
    end
    return out
end

function WidgetHost:StartDrag(widgetId)
    if not widgetId then return end
    -- Reordering reflows, and reflowing is not something that can happen
    -- mid-fight: it reparents frames the taint system will not let us
    -- touch. Better to not start than to arm a drag that does nothing.
    if InCombatLockdown() then return end

    self._dragId = widgetId

    local watcher = self._dragWatcher
    if not watcher then
        watcher = CreateFrame("Frame")
        self._dragWatcher = watcher
    end
    watcher:SetScript("OnUpdate", function() WidgetHost:DragStep() end)
    watcher:Show()
end

function WidgetHost:DragStep()
    local id = self._dragId
    if not id then return end

    -- The title bar only hears the mouse come up while the cursor is
    -- still on it, and a drag that ends anywhere else would otherwise
    -- run forever. Whether the button is down is the honest question.
    if not IsMouseButtonDown("LeftButton") then
        self:StopDrag()
        return
    end
    if InCombatLockdown() then
        self:StopDrag()
        return
    end

    local slot = self.slots[id]
    if not (slot and slot:IsShown()) then return end

    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / (UIParent:GetEffectiveScale() or 1)

    local order = self:StackOrder(id)
    local index
    for i, other in ipairs(order) do
        if other == id then index = i break end
    end
    if not index then return end

    -- Screen coordinates count upward, so the neighbour drawn above is
    -- the one earlier in the order and the one with the larger Y.
    local above, below = order[index - 1], order[index + 1]

    if above and self.slots[above] then
        local mid = SlotMidY(self.slots[above])
        if mid and cursorY > mid then
            self:SwapWidgetOrder(id, above)
            return
        end
    end

    if below and self.slots[below] then
        local mid = SlotMidY(self.slots[below])
        if mid and cursorY < mid then
            self:SwapWidgetOrder(id, below)
            return
        end
    end
end

function WidgetHost:StopDrag()
    local id = self._dragId
    self._dragId = nil

    if self._dragWatcher then
        self._dragWatcher:SetScript("OnUpdate", nil)
        self._dragWatcher:Hide()
    end

    -- Put the bar back to how it looks when it is not being dragged. The
    -- title bar does this itself when the mouse comes up on it; this is
    -- for every other way a drag can end.
    local slot = id and self.slots[id]
    local title = slot and slot.titleBar
    if title and title._dragReady then
        title._dragReady = nil
        if title:IsMouseOver() then
            title.bg:SetColorTexture(unpack(TITLE_BG_HOVER))
        else
            title.bg:SetColorTexture(unpack(TITLE_BG_IDLE))
        end
    end
end

-- Put two widgets in each other's places.
--
-- Worked out from the whole drawer's order rather than by trading the
-- two numbers, which is what this did and why dragging appeared to do
-- nothing: a widget nobody has ever reordered has no number, both sides
-- read as the same stand-in value, and swapping one for itself leaves
-- the list exactly as it was. The bar turned green, the drag ran, and
-- every frame it swapped nothing.
--
-- The positions come from the sorted list of everything, not from the
-- stack the drag walks: a widget that is floating or switched off still
-- sits between two that are not, and the order being saved is the order
-- of the lot.
function WidgetHost:SwapWidgetOrder(idA, idB)
    local sorted = addon:GetSortedWidgets() or {}
    local ia, ib
    for i, w in ipairs(sorted) do
        if w.id == idA then ia = i end
        if w.id == idB then ib = i end
    end
    if not (ia and ib) then return end

    sorted[ia], sorted[ib] = sorted[ib], sorted[ia]
    addon:ApplyWidgetOrder(sorted)
end

-- Move a widget one place up or down its own stack.
--
-- What the arrows on a title bar do, and the same neighbour the drag
-- would have found. Answers whether it could, so a button at the end of
-- the stack can gray itself out rather than be a control that does
-- nothing when pressed.
function WidgetHost:MoveInStack(widgetId, delta, testOnly)
    if not widgetId then return false end
    if InCombatLockdown() then return false end

    local order = self:StackOrder(widgetId)
    local index
    for i, id in ipairs(order) do
        if id == widgetId then index = i break end
    end
    if not index then return false end

    local other = order[index + delta]
    if not other then return false end
    if testOnly then return true end

    self:SwapWidgetOrder(widgetId, other)
    return true
end

---------------------------------------------------------------------------
-- Reflow - rebuild the vertical slot stack from the current registry
---------------------------------------------------------------------------

-- A reflow can ask for another one before it has finished.
--
-- A widget is told it has docked or undocked in the middle of a pass,
-- and the honest answer to that is often "I am a different size now" -
-- the minimap says exactly that, because the map it holds is sized
-- against the drawer when it is in one and against nothing when it is
-- not. Saying so calls Reflow from inside Reflow, and the inner pass
-- then lays out frames the outer pass is still walking over.
--
-- So a reflow asked for while one is running is remembered and run
-- afterwards, once, however many times it was asked for.
local MAX_REFLOW_PASSES = 3

function WidgetHost:Reflow()
    if self._reflowing then
        self._reflowAgain = true
        return
    end

    -- A loop, not a call back into Reflow. Recursing here ran until the
    -- stack gave out: a widget that re-measures itself on being docked
    -- asks for a reflow from inside every pass, so every pass asked for
    -- another one. That was seconds of churn ending in an error, and
    -- the error abandoned the pass half done - which is why the map
    -- stopped moving as well as why the game hitched.
    --
    -- Bounded too. Two passes settle anything that re-measures once;
    -- a third is the benefit of the doubt. Past that something is
    -- arguing with itself and running it again will not settle it.
    self._reflowing = true
    local ok, err = true, nil
    for _ = 1, MAX_REFLOW_PASSES do
        self._reflowAgain = nil
        ok, err = pcall(self.DoReflow, self)
        if not ok or not self._reflowAgain then break end
    end
    self._reflowAgain = nil
    self._reflowing = false
    if not ok then error(err, 0) end
end

function WidgetHost:DoReflow()
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
    local slotSpacing     = tonumber(addon:GetSetting("widgetSpacing")) or DEFAULT_SLOT_SPACING

    local allWidgets = addon.GetSortedWidgets and addon:GetSortedWidgets()
        or (BazUI.GetDockableWidgets and BazUI:GetDockableWidgets())
        or {}

    -- No drawers: every enabled widget floats and no slot is built. The
    -- loop below already does this, because IsWidgetFloating answers
    -- true for everything while the drawer is off - but a widget that
    -- was in no drawer at all would never have been in this list, so it
    -- is gathered from the registry instead of from drawer membership.
    if not addon:UsingDrawers() then
        allWidgets = BazUI.GetDockableWidgets and BazUI:GetDockableWidgets() or {}
    end

    -- Split: disabled widgets are hidden entirely, floating widgets are
    -- handled by FloatWidget (reparented to UIParent, Edit Mode
    -- registered) and NOT included in the slot stack. Docked + enabled
    -- widgets get normal slot treatment.
    -- Everything registered, not only what this drawer holds.
    --
    -- A widget that is switched on but is in no drawer used to fall
    -- through every branch below, because the list only ever held the
    -- active drawer's members - so it was never docked, never floated
    -- and never hidden, and simply stayed wherever it last was. On
    -- screen, in the middle of nothing, ignoring the drawer entirely.
    local member = {}
    for _, w in ipairs(allWidgets) do member[w.id] = true end
    for _, w in ipairs(BazUI.GetDockableWidgets and BazUI:GetDockableWidgets() or {}) do
        if not member[w.id]
            and addon:IsWidgetEnabled(w.id)
            and not addon:IsWidgetFloating(w.id)
        then
            -- Switched on, not floating, and nowhere to be. There is no
            -- honest place to draw it.
            self:DisableWidget(w)
        end
    end

    local widgets = {}
    for _, w in ipairs(allWidgets) do
        if not addon:IsWidgetEnabled(w.id) then
            self:DisableWidget(w)
        elseif addon:IsWidgetFloating(w.id) then
            self:FloatWidget(w)
        else
            -- Coming home. A widget that was floating still carries its
            -- own Edit Mode handle and still counts as floating to
            -- anything that asks, so it would keep a handle of its own
            -- on top of the drawer's and get dragged back out to screen
            -- coordinates by the next placement pass.
            if w._floating then
                if w._editModeRegistered and BazUI.UnregisterEditModeFrame then
                    BazUI:UnregisterEditModeFrame(w.frame)
                    w._editModeRegistered = nil
                end
                w._floating = nil
            end
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
        yOffset = yOffset - slotHeight - slotSpacing
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
        bottomY = bottomY + slotHeight + slotSpacing
    end

    if addon.Drawer and addon.Drawer.SetWidgetCount then
        addon.Drawer:SetWidgetCount(#widgets)
    end

    -- A title bar is created at full alpha, and the drawer only fades the
    -- ones it can see at the moment its fade changes. A slot built or
    -- rebuilt after that - a widget switched on, or one that reflows on
    -- its own, which the minimap does whenever its style changes - was
    -- left sitting there opaque over a drawer that had faded away.
    if self._chromeAlpha then
        self:ApplyFadeTargets(self._chromeAlpha, self._fullAlpha)
    end
end
