-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: SideTabs
--
-- The column of picture tabs hung off the right edge of a window: the
-- ones the character sheet, the collections and the legacy panel wear
-- on Forever, and the quest log wears on retail. Blizzard ships them as
-- LargeSideTabButtonTemplate on both clients, each in that client's own
-- art, so a window that uses this gets the tabs the rest of the client
-- has rather than a drawing of them.
--
-- The same API as the TabStrip, so a window can hang its pages off
-- either and the code that fills them need not know which:
--
--   column:AddTab(label, icon) -> tabID    column.tabs[tabID]
--   column:SetTab(tabID, isUserAction)     column.selectedTabID
--   column:SetTabSelectedCallback(fn)      fn(tabID, isUserAction)
--   column:SetTabVisuallySelected(tabID)   column:ClearTabs()
--   column:GetTab(tabID)                   column:Layout()
--
-- A tab has no words on it, so the label is its tooltip. icon is a
-- texture path, or a function(texture) that paints one - a portrait has
-- to be painted rather than named.
--
-- A rail can also be rearranged by the player, the same way a drawer's
-- widgets are: hold a tab, it washes green, drag it past its neighbour.
-- Off unless the owner asks for it:
--
--   column:AddTab(label, icon, key)        -- key names the page
--   column:SetReorderHandler(fn)           -- fn(key, otherKey)
--
-- The handler swaps those two in whatever the owner saves its order in
-- and rebuilds the rail. The column does not keep the order itself -
-- it is torn down and refilled on every rebuild, so it has nowhere to
-- keep one - and the drag follows the key through the rebuild rather
-- than the tab ID, which is only a position and changes underneath it.
---------------------------------------------------------------------------

local TEMPLATE  = "LargeSideTabButtonTemplate"
local ICON_CROP = 0.03125          -- the trim Blizzard gives a tab's icon
local FALLBACK_W, FALLBACK_H = 43, 55
local DEFAULT_SPACING = 2

-- The same half second the drawer's title bars use before a hold turns
-- into a drag, so the two gestures are one gesture.
local DRAG_HOLD_TIME = 0.5

-- Green, on the tab's own art rather than over the top of it. The
-- template carries a TabGlow layer for this: the selected-tab atlas
-- again, drawn additively at zero alpha, so it is already the shape of
-- a tab and already in the right place.
local DRAG_TINT  = { 0.30, 1.00, 0.40 }
local DRAG_GLOW  = 0.55

-- The icon goes green as well, but not as far. A tint is a multiply, so
-- the tab art - one flat color - takes a strong one and still reads,
-- while an icon is a picture and the same multiply turns the dark half
-- of it to black. Lighter, and the whole tab is one color without the
-- picture on it dissolving.
local DRAG_ICON  = { 0.55, 1.00, 0.62 }

local function HasTemplate()
    return BazUI.Has and BazUI.Has.Template and BazUI.Has.Template(TEMPLATE)
end

local function Crop(tex)
    tex:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
end

---------------------------------------------------------------------------
-- One tab
--
-- The two clients' copies of the template disagree on three things, and
-- they are settled here so nothing else has to know. Forever sizes the
-- tab from its atlas as it loads and offers SetFillToInterior to size
-- the icon; retail sizes the tab in XML and leaves the icon unsized.
-- Retail's SetChecked assumes the icon is an atlas and errors on a
-- file, so selection is drawn here, on both.
---------------------------------------------------------------------------

local TabMixin = {}

function TabMixin:Init(tabID, label, icon)
    self.tabID = tabID
    self.tooltipText = label
    if type(icon) == "function" then
        icon(self.Icon)
    else
        self.Icon:SetTexture(icon or nil)
    end
    -- Painting a portrait resets the trim, so it is set after, every time.
    Crop(self.Icon)
end

function TabMixin:GetTabID()
    return self.tabID
end

function TabMixin:SetTabSelected(selected)
    selected = selected and true or false
    self.isSelected = selected
    if self.SelectedTexture then self.SelectedTexture:SetShown(selected) end
end

-- Green means this one is loose and will change places if you move.
--
-- The tab's own art, tinted, and the glow layer lit in the same green.
-- A colored square laid over the top was the first attempt and it looked
-- like a colored square laid over the top: side tab art is a shape with
-- a bevel and a curved outer edge, and a rectangle covering its bounding
-- box is wrong everywhere the tab is not a rectangle, which is most of
-- it.
--
function TabMixin:SetDragArmed(armed)
    armed = armed and true or false
    self.dragArmed = armed

    if self.Background then
        if armed then
            self.Background:SetVertexColor(unpack(DRAG_TINT))
        else
            self.Background:SetVertexColor(1, 1, 1)
        end
    end

    if self.Icon then
        if armed then
            self.Icon:SetVertexColor(unpack(DRAG_ICON))
        else
            self.Icon:SetVertexColor(1, 1, 1)
        end
    end

    if self.TabGlow then
        self.TabGlow:SetVertexColor(unpack(DRAG_TINT))
        self.TabGlow:SetAlpha(armed and DRAG_GLOW or 0)
    end
end

local function CreateTab(column)
    local tab
    if HasTemplate() then
        tab = CreateFrame("Frame", nil, column, TEMPLATE)
    else
        tab = CreateFrame("Frame", nil, column)
        tab:SetSize(FALLBACK_W, FALLBACK_H)
        tab.Background = tab:CreateTexture(nil, "BACKGROUND")
        tab.Background:SetAllPoints()
        tab.Background:SetColorTexture(0.10, 0.09, 0.07, 0.9)
        tab.Icon = tab:CreateTexture(nil, "ARTWORK")
        tab.Icon:SetPoint("CENTER", -2, 0)
        tab.SelectedTexture = tab:CreateTexture(nil, "OVERLAY")
        tab.SelectedTexture:SetAllPoints()
        tab.SelectedTexture:SetColorTexture(1, 0.82, 0, 0.25)
        -- Stands in for the template's TabGlow so the armed look is one
        -- piece of code rather than two. Additive, so it lights the tab
        -- rather than painting over it.
        tab.TabGlow = tab:CreateTexture(nil, "OVERLAY", nil, 7)
        tab.TabGlow:SetAllPoints()
        tab.TabGlow:SetColorTexture(1, 1, 1, 1)
        tab.TabGlow:SetBlendMode("ADD")
        tab.TabGlow:SetAlpha(0)
        local hi = tab:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.15)
        tab:SetScript("OnEnter", function(self)
            if not self.tooltipText then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipText)
            GameTooltip:Show()
        end)
        tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    tab:EnableMouse(true)
    Mixin(tab, TabMixin)

    local size = column.iconSize or (tab.SetFillToInterior and 50 or 30)
    if tab.SetFillToInterior then
        tab:SetFillToInterior(true, size)
    else
        tab.Icon:SetSize(size, size)
        Crop(tab.Icon)
    end

    -- Letting go over the tab selects it. The template's own mouse
    -- handling (the icon nudging down while pressed, the click sound)
    -- stays; this hangs off the hook it leaves for exactly this.
    local function OnUp(self, button, upInside)
        if button ~= "LeftButton" then return end
        local c = self:GetParent()

        -- A hold that never became a drag is still a click.
        --
        -- Letting go after the tab had gone green but before it had
        -- moved anywhere used to do nothing at all, which reads as the
        -- window ignoring you for having pressed too slowly.
        local moved = c and c:StopReorder() or false
        if c then c:CancelHold() end

        if moved then return end
        if upInside == false then return end
        if c and c.SetTab then c:SetTab(self.tabID, true) end
    end

    local function OnDown(self, button)
        if button ~= "LeftButton" then return end
        local c = self:GetParent()
        if c and c.BeginHold then c:BeginHold(self.key) end
    end
    if tab:GetScript("OnMouseDown") then
        tab:HookScript("OnMouseDown", OnDown)
    else
        tab:SetScript("OnMouseDown", OnDown)
    end
    if tab.SetCustomOnMouseUpHandler then
        tab:SetCustomOnMouseUpHandler(OnUp)
    else
        tab:SetScript("OnMouseUp", function(self, button)
            OnUp(self, button, self:IsMouseOver())
        end)
    end
    return tab
end

---------------------------------------------------------------------------
-- The column
---------------------------------------------------------------------------

local ColumnMixin = {}

function ColumnMixin:SetTabSelectedCallback(fn)
    self.tabSelectedCallback = fn
end

function ColumnMixin:AddTab(label, icon, key)
    local tabID = #self.tabs + 1
    local tab = table.remove(self._pool) or CreateTab(self)
    self.tabs[tabID] = tab
    tab:Init(tabID, label, icon)
    tab.key = key
    tab:SetTabSelected(false)
    tab:SetDragArmed(false)
    tab:Show()
    self:MarkDirty()
    return tabID
end

function ColumnMixin:TabByKey(key)
    if key == nil then return nil end
    for _, tab in ipairs(self.tabs) do
        if tab.key == key then return tab end
    end
end

-- Empty the column, keeping the frames for the next build.
function ColumnMixin:ClearTabs()
    for _, tab in ipairs(self.tabs) do
        tab:Hide()
        tab.isSelected = false
        tab:SetDragArmed(false)
        tab.key = nil
        self._pool[#self._pool + 1] = tab
    end
    self.tabs = {}
    self.selectedTabID = nil
    self:MarkDirty()
end

function ColumnMixin:SetTabVisuallySelected(tabID)
    for id, tab in ipairs(self.tabs) do
        tab:SetTabSelected(id == tabID)
    end
end

function ColumnMixin:SetTab(tabID, isUserAction)
    if not self.tabs[tabID] then return end
    self.selectedTabID = tabID
    self:SetTabVisuallySelected(tabID)
    if self.tabSelectedCallback then
        self.tabSelectedCallback(tabID, isUserAction and true or false)
    end
end

function ColumnMixin:GetTab(tabID)
    return self.tabs[tabID]
end

function ColumnMixin:MarkDirty()
    self._dirty = true
end

-- Top to bottom, in the order they were added. The column takes the
-- size of its tabs so whoever anchors it can anchor to it.
--
-- A tab being dragged is not laid out. It is following the cursor, so
-- it is left where the drag put it and an empty slot is opened at the
-- place it would land - which is what the other tabs sliding up and
-- down is: them being laid out around a gap that keeps moving.
function ColumnMixin:Layout()
    self._dirty = false

    local carried = self:TabByKey(self._reorderKey)

    local list = {}
    for _, tab in ipairs(self.tabs) do
        if tab:IsShown() and tab ~= carried then list[#list + 1] = tab end
    end

    local gap, drop = 0, nil
    if carried then
        gap  = (carried:GetHeight() or FALLBACK_H) + self.tabSpacing
        drop = math.min(math.max(self._dropIndex or 1, 1), #list + 1)
    end

    local y, widest = 0, 1
    if carried then widest = math.max(widest, carried:GetWidth() or FALLBACK_W) end

    for i = 1, #list + 1 do
        if drop and i == drop then y = y + gap end
        local tab = list[i]
        if tab then
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
            y = y + (tab:GetHeight() or FALLBACK_H) + self.tabSpacing
            widest = math.max(widest, tab:GetWidth() or FALLBACK_W)
        end
    end

    self:SetSize(widest, math.max(y - self.tabSpacing, 1))
end

---------------------------------------------------------------------------
-- Dragging a tab to another place in the rail
--
-- The drawer's gesture, on a column of pictures instead of a stack of
-- title bars: hold for half a second, the tab lights green, and from
-- then until the mouse comes up it is carried by the cursor.
--
-- Carried, not swapped. The first version traded places with a neighbour
-- whenever the cursor passed its middle and rebuilt the whole rail to
-- show it, which meant the tab could only ever be in one of twelve
-- places and jumped between them - correct, and nothing like dragging.
-- Here the tab leaves the layout altogether and follows the cursor, the
-- rest are laid out around a gap, and the gap is what moves in steps.
--
-- The order is not written down until the mouse comes up. Nothing is
-- saved and nothing is rebuilt during the drag, so there is no way for
-- a tab ID to change underneath the thing holding it.
---------------------------------------------------------------------------

-- fn(keys) - the pages in their new order, once, when the drag ends.
function ColumnMixin:SetReorderHandler(fn)
    self.reorderHandler = fn
end

function ColumnMixin:CursorY()
    local scale = self:GetEffectiveScale()
    if not scale or scale == 0 then scale = 1 end
    local _, y = GetCursorPosition()
    -- Divided by this rail's own scale, not UIParent's: the codex window
    -- carries a scale of its own, and GetTop answers in the frame's
    -- coordinate space while the cursor answers in screen pixels.
    return y / scale
end

-- Mouse went down on a tab. Nothing happens yet.
function ColumnMixin:BeginHold(key)
    if not (self.reorderHandler and key ~= nil) then return end
    self:CancelHold()
    self._holdKey = key
    self._holdTimer = C_Timer.NewTimer(DRAG_HOLD_TIME, function()
        if self._holdKey ~= key then return end
        self._holdTimer = nil
        self:StartReorder(key)
    end)
end

function ColumnMixin:CancelHold()
    if self._holdTimer then
        self._holdTimer:Cancel()
        self._holdTimer = nil
    end
    self._holdKey = nil
end

function ColumnMixin:StartReorder(key)
    -- Let go off the tab and it never hears the mouse up, so the hold
    -- timer runs on and fires into a drag nobody is holding. It would be
    -- caught on the next frame either way; this is so the tab does not
    -- flash green on its way there.
    if not IsMouseButtonDown("LeftButton") then
        self:CancelHold()
        return
    end

    local tab = self:TabByKey(key)
    if not tab then return end

    local index
    for i, other in ipairs(self.tabs) do
        if other == tab then index = i break end
    end
    if not index then return end

    -- Where in the tab it was picked up, so it does not jump so that its
    -- top is under the cursor the moment the hold completes.
    self._grabOffset  = (tab:GetTop() or self:CursorY()) - self:CursorY()
    self._reorderKey  = key
    self._fromIndex   = index
    self._dropIndex   = index

    -- Over its neighbours on the way past them.
    self._dragLevel = tab:GetFrameLevel()
    tab:SetFrameLevel((self:GetFrameLevel() or 1) + 10)

    tab:SetDragArmed(true)
    self:Layout()
end

-- Ends the drag and says whether it actually moved anything, which is
-- what tells a mouse-up apart from a click.
function ColumnMixin:StopReorder()
    local key = self._reorderKey
    if key == nil then return false end

    local tab  = self:TabByKey(key)
    local drop = self._dropIndex
    local from = self._fromIndex

    self._reorderKey = nil
    self._dropIndex  = nil
    self._fromIndex  = nil
    self._grabOffset = nil

    if tab then
        tab:SetDragArmed(false)
        if self._dragLevel then tab:SetFrameLevel(self._dragLevel) end
    end
    self._dragLevel = nil

    -- Back into the rail. If it did move, the owner is about to rebuild
    -- over the top of this; if it did not, this is the tab dropping back
    -- into the place it came from.
    self:Layout()

    if not (drop and from and drop ~= from) then return false end

    if self.reorderHandler then
        local keys = {}
        for _, other in ipairs(self.tabs) do
            if other.key ~= nil and other.key ~= key then
                keys[#keys + 1] = other.key
            end
        end
        table.insert(keys, math.min(drop, #keys + 1), key)
        self.reorderHandler(keys)
    end
    return true
end

function ColumnMixin:ReorderStep()
    local key = self._reorderKey
    if key == nil then return end

    -- The tab only hears the mouse come up while the cursor is still on
    -- it, and a drag let go anywhere else would otherwise run forever.
    -- Whether the button is down is the honest question.
    if not IsMouseButtonDown("LeftButton") then
        self:StopReorder()
        return
    end

    local tab = self:TabByKey(key)
    local top = self:GetTop()
    if not (tab and top) then return end

    local height = tab:GetHeight() or FALLBACK_H
    local step   = height + self.tabSpacing
    local count  = 0
    for _, other in ipairs(self.tabs) do
        if other:IsShown() then count = count + 1 end
    end
    if count < 2 or step <= 0 then return end

    -- How far the tab's top edge sits below the top of the rail, held
    -- inside it at both ends so it cannot be carried off the column.
    local offset = (top - self:CursorY()) - (self._grabOffset or 0)
    offset = math.min(math.max(offset, 0), (count - 1) * step)

    tab:ClearAllPoints()
    tab:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -offset)

    -- Which slot the tab's middle is over. The middle rather than its
    -- top edge, so the gap opens where the tab looks like it is, and a
    -- tab dragged halfway onto a slot has claimed it.
    local drop = math.floor((offset + height / 2) / step) + 1
    drop = math.min(math.max(drop, 1), count)
    if drop ~= self._dropIndex then
        self._dropIndex = drop
        self:Layout()
    end
end

---------------------------------------------------------------------------
-- Factory
---------------------------------------------------------------------------

-- BazUI.CreateSideTabs(name, parent, opts)
--   opts.iconSize   the icon inside the tab (default: what the client's
--                   tab art was drawn for)
--   opts.spacing    gap between tabs (default 2)
function BazUI.CreateSideTabs(name, parent, opts)
    opts = opts or {}
    local column = CreateFrame("Frame", name, parent or UIParent)
    Mixin(column, ColumnMixin)
    column.tabs       = {}
    column._pool      = {}
    column.iconSize   = opts.iconSize
    column.tabSpacing = opts.spacing or DEFAULT_SPACING
    column:SetSize(1, 1)
    column:SetScript("OnUpdate", function(self)
        if self._dirty then self:Layout() end
        if self._reorderKey ~= nil then self:ReorderStep() end
    end)
    -- A rail put away mid-drag would otherwise come back still green and
    -- still listening for a mouse button that was let go long ago.
    column:HookScript("OnHide", function(self)
        self:CancelHold()
        self:StopReorder()
    end)
    return column
end

-- True when the client has Blizzard's own side tab art to draw with.
function BazUI.HasBlizzardSideTabs()
    return HasTemplate() and true or false
end
