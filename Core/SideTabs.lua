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
---------------------------------------------------------------------------

local TEMPLATE  = "LargeSideTabButtonTemplate"
local ICON_CROP = 0.03125          -- the trim Blizzard gives a tab's icon
local FALLBACK_W, FALLBACK_H = 43, 55
local DEFAULT_SPACING = 2

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
        if upInside == false then return end
        local c = self:GetParent()
        if c and c.SetTab then c:SetTab(self.tabID, true) end
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

function ColumnMixin:AddTab(label, icon)
    local tabID = #self.tabs + 1
    local tab = table.remove(self._pool) or CreateTab(self)
    self.tabs[tabID] = tab
    tab:Init(tabID, label, icon)
    tab:SetTabSelected(false)
    tab:Show()
    self:MarkDirty()
    return tabID
end

-- Empty the column, keeping the frames for the next build.
function ColumnMixin:ClearTabs()
    for _, tab in ipairs(self.tabs) do
        tab:Hide()
        tab.isSelected = false
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
function ColumnMixin:Layout()
    self._dirty = false
    local y, widest = 0, 1
    for _, tab in ipairs(self.tabs) do
        if tab:IsShown() then
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
            y = y + (tab:GetHeight() or FALLBACK_H) + self.tabSpacing
            widest = math.max(widest, tab:GetWidth() or FALLBACK_W)
        end
    end
    self:SetSize(widest, math.max(y - self.tabSpacing, 1))
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
    end)
    return column
end

-- True when the client has Blizzard's own side tab art to draw with.
function BazUI.HasBlizzardSideTabs()
    return HasTemplate() and true or false
end
