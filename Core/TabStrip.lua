-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: TabStrip
--
-- A horizontal row of tabs with the same API surface as Blizzard's
-- TabSystemTemplate, which Classic-family clients ship in source but do
-- not load. Modules written against the TabSystem (Chat's tab strip)
-- work unchanged against this:
--
--   strip:AddTab(label) -> tabID          strip.tabs[tabID]
--   strip:SetTab(tabID, isUserAction)     strip.selectedTabID
--   strip:SetTabSelectedCallback(fn)      fn(tabID, isUserAction)
--   strip:SetTabVisuallySelected(tabID)   strip:MarkDirty()
--   strip.minTabWidth / strip.maxTabWidth
--   tab:Init(tabID, text)  tab:SetTabSelected(bool)  tab.isSelected
--   tab:GetTabID()         tab.layoutIndex  tab.ignoreInLayout
--
-- Layout follows HorizontalLayoutFrame rules: every shown child with a
-- layoutIndex is placed left to right in that order (so a drag
-- placeholder frame slots in like a tab), children flagged
-- ignoreInLayout are skipped, and the strip sizes itself to its content.
--
-- Tabs use Blizzard's MinimalTabTemplate (the flat gold tabs the Settings
-- panel uses) when the client has it, else the classic panel top tab.
---------------------------------------------------------------------------

local TAB_SPACING = 2
local TEXT_PAD    = 40   -- MinimalTab's own text-to-edge padding

local function HasTemplate(name)
    return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) ~= nil
end

---------------------------------------------------------------------------
-- Tab buttons
---------------------------------------------------------------------------

-- MinimalTab's own art is a faint translucent shape that all but
-- vanishes over the game world, so each tab gets a solid dark panel
-- behind it with a gold accent along the top of the selected tab.
local BG_SELECTED   = { 0.10, 0.09, 0.07, 0.95 }
local BG_UNSELECTED = { 0.04, 0.04, 0.05, 0.85 }
local EDGE_SELECTED   = { 1.00, 0.82, 0.00, 0.95 }
local EDGE_UNSELECTED = { 0.55, 0.45, 0.15, 0.60 }

local function AddBackdrop(tab)
    local bg = tab:CreateTexture(nil, "BACKGROUND", nil, -2)
    if tab.Left and tab.Right then
        bg:SetPoint("TOPLEFT",     tab.Left,  "TOPLEFT",     1, 0)
        bg:SetPoint("BOTTOMRIGHT", tab.Right, "BOTTOMRIGHT", -1, 0)
    else
        bg:SetPoint("TOPLEFT", 1, -6)
        bg:SetPoint("BOTTOMRIGHT", -1, 0)
    end
    local edge = tab:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetPoint("TOPLEFT",  bg, "TOPLEFT",  0, 0)
    edge:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0)
    edge:SetHeight(2)
    tab._bazBg, tab._bazEdge = bg, edge
end

local function UpdateBackdrop(tab, selected)
    if not tab._bazBg then return end
    local bg   = selected and BG_SELECTED   or BG_UNSELECTED
    local edge = selected and EDGE_SELECTED or EDGE_UNSELECTED
    tab._bazBg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    tab._bazEdge:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
end

local TabMixin = {}

function TabMixin:Init(tabID, text)
    self.tabID = tabID
    if self.Text then
        self.Text:SetText(text or "")
    else
        self:SetText(text or "")
    end
    local strip = self:GetParent()
    local minW = (strip and strip.minTabWidth) or 60
    local maxW = (strip and strip.maxTabWidth) or 120
    if self._bazMinimal then
        local w = (self.Text and self.Text:GetStringWidth() or 0) + TEXT_PAD
        self:SetWidth(math.max(minW, math.min(maxW, w)))
    else
        PanelTemplates_TabResize(self, 0, nil, minW, maxW)
    end
    if strip and strip.MarkDirty then strip:MarkDirty() end
end

function TabMixin:GetTabID()
    return self.tabID
end

function TabMixin:SetTabSelected(selected)
    selected = selected and true or false
    self.isSelected = selected
    if self._bazMinimal then
        if self.SetSelected then
            self:SetSelected(selected)
        elseif self.OnSelected then
            self:OnSelected(selected)
        end
        UpdateBackdrop(self, selected)
    else
        if selected then PanelTemplates_SelectTab(self) else PanelTemplates_DeselectTab(self) end
    end
end

local function CreateTab(strip)
    local tab
    if HasTemplate("MinimalTabTemplate") then
        tab = CreateFrame("Button", nil, strip, "MinimalTabTemplate")
        tab._bazMinimal = true
        AddBackdrop(tab)
    else
        tab = CreateFrame("Button", nil, strip, "PanelTopTabButtonTemplate")
    end
    Mixin(tab, TabMixin)
    -- Left click selects. Right click is left to OnMouseUp hooks (Chat
    -- opens its tab menu there), so it must not change the selection.
    tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tab:SetScript("OnClick", function(self, button)
        if button == "RightButton" then return end
        local s = self:GetParent()
        if s and s.SetTab then s:SetTab(self.tabID, true) end
    end)
    return tab
end

---------------------------------------------------------------------------
-- Strip
---------------------------------------------------------------------------

local StripMixin = {}

function StripMixin:SetTabSelectedCallback(fn)
    self.tabSelectedCallback = fn
end

function StripMixin:AddTab(label)
    local tabID = #self.tabs + 1
    local tab = CreateTab(self)
    self.tabs[tabID] = tab
    tab.layoutIndex = tabID
    tab:Init(tabID, label)
    tab:SetTabSelected(false)
    tab:Show()
    self:MarkDirty()
    return tabID
end

function StripMixin:SetTabVisuallySelected(tabID)
    for id, tab in ipairs(self.tabs) do
        tab:SetTabSelected(id == tabID)
    end
end

function StripMixin:SetTab(tabID, isUserAction)
    if not self.tabs[tabID] then return end
    self.selectedTabID = tabID
    self:SetTabVisuallySelected(tabID)
    if self.tabSelectedCallback then
        self.tabSelectedCallback(tabID, isUserAction and true or false)
    end
    if isUserAction and self.tabSelectSound then
        PlaySound(self.tabSelectSound)
    end
end

function StripMixin:GetTab(tabID)
    return self.tabs[tabID]
end

function StripMixin:MarkDirty()
    self._dirty = true
end

function StripMixin:Layout()
    self._dirty = false
    local items = {}
    for _, child in ipairs({ self:GetChildren() }) do
        if child.layoutIndex and not child.ignoreInLayout and child:IsShown() then
            items[#items + 1] = child
        end
    end
    table.sort(items, function(a, b)
        if a.layoutIndex == b.layoutIndex then
            return tostring(a) < tostring(b)
        end
        return a.layoutIndex < b.layoutIndex
    end)

    local x, maxH = 0, 0
    for i, child in ipairs(items) do
        child:ClearAllPoints()
        child:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 0)
        x = x + (child:GetWidth() or 0) + (i < #items and TAB_SPACING or 0)
        maxH = math.max(maxH, child:GetHeight() or 0)
    end
    self:SetSize(math.max(x, 1), math.max(maxH, 1))
end

---------------------------------------------------------------------------
-- Factory
---------------------------------------------------------------------------

-- BazUI.CreateTabStrip(name, parent, opts)
--   opts.minTabWidth / opts.maxTabWidth  clamp tab widths (default 60 / 120)
--   opts.tabSelectSound                  SOUNDKIT id played on user clicks
function BazUI.CreateTabStrip(name, parent, opts)
    opts = opts or {}
    local strip = CreateFrame("Frame", name, parent or UIParent)
    Mixin(strip, StripMixin)
    strip.tabs           = {}
    strip.minTabWidth    = opts.minTabWidth or 60
    strip.maxTabWidth    = opts.maxTabWidth or 120
    strip.tabSelectSound = opts.tabSelectSound
    strip:SetSize(1, 1)
    strip:SetScript("OnUpdate", function(self)
        if self._dirty then self:Layout() end
    end)
    return strip
end

-- True when the client loads Blizzard's own TabSystem, in which case
-- callers may prefer it.
function BazUI.HasBlizzardTabSystem()
    return HasTemplate("TabSystemTemplate")
end
