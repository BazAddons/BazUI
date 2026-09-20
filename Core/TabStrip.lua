-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: TabStrip
--
-- Every row of tabs in the addon. One API, the same one Blizzard's
-- TabSystemTemplate exposes, which Classic-family clients ship in source
-- but do not load; code written against either works against this:
--
--   strip:AddTab(label) -> tabID          strip.tabs[tabID]
--   strip:SetTab(tabID, isUserAction)     strip.selectedTabID
--   strip:SetTabSelectedCallback(fn)      fn(tabID, isUserAction)
--   strip:SetTabVisuallySelected(tabID)   strip:MarkDirty()
--   strip:ClearTabs()                     strip:GetTab(tabID)
--   strip.minTabWidth / strip.maxTabWidth
--   tab:Init(tabID, text)  tab:SetTabSelected(bool)  tab.isSelected
--   tab:GetTabID()         tab.layoutIndex  tab.ignoreInLayout
--
-- Layout follows HorizontalLayoutFrame rules: every shown child with a
-- layoutIndex is placed in that order (so a drag placeholder frame slots
-- in like a tab), children flagged ignoreInLayout are skipped, and the
-- strip sizes itself to its content.
--
-- Two looks, chosen with opts.style:
--
--   "panel"      A square plate with a gold accent along its top
--                along the top of the selected tab. Tabs that sit above
--                a page: the options canvas, the chat dock.
--   "underline"  Text alone, the selected one bright over a gold rule.
--                Tabs inside a panel: the notification center.
--
-- Colors come from the shared theme, so a tab reads like everything
-- else in the suite.
---------------------------------------------------------------------------

local Theme = BazUI.Skin.Theme

local DEFAULT_SPACING = 2
local UNDERLINE_PAD   = 16
local UNDERLINE_H     = 2

local function HasTemplate(name)
    return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) ~= nil
end

local function SetTexColor(tex, c)
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

---------------------------------------------------------------------------
-- The "panel" look
--
-- A square plate with the accent line capping it. Blizzard's own tab
-- art is rounded at the top corners, so a straight line across it left
-- a notch at each end; drawing the plate ourselves means the line meets
-- the corners and the tab matches the flat chrome everywhere else.
-- The plate also gives a hit target that reads over the game world,
-- which is why the chat dock uses this rather than the underline.
---------------------------------------------------------------------------

local PANEL_TEXT_PAD = 24
local PANEL_ACCENT_H = 2

local Panel = {}

function Panel.Create(strip)
    local tab = CreateFrame("Button", nil, strip)
    tab:SetHeight(strip.tabHeight or 26)

    tab.bg = tab:CreateTexture(nil, "BACKGROUND", nil, -2)
    tab.bg:SetAllPoints()

    tab.accent = tab:CreateTexture(nil, "BACKGROUND", nil, -1)
    tab.accent:SetHeight(PANEL_ACCENT_H)
    tab.accent:SetPoint("TOPLEFT")
    tab.accent:SetPoint("TOPRIGHT")

    tab.Text = Theme.FontString(tab, "OVERLAY", strip.tabFont or "GameFontNormal")
    tab.Text:SetPoint("CENTER", 0, -1)

    tab:HookScript("OnEnter", function(self)
        if not self.isSelected then self.Text:SetTextColor(unpack(Theme.colors.gold)) end
    end)
    tab:HookScript("OnLeave", function(self)
        Panel.SetSelected(self, self.isSelected)
    end)
    return tab
end

function Panel.Init(tab, text, strip)
    tab.Text:SetText(text or "")
    local w = (tab.Text:GetStringWidth() or 0) + (strip.textPad or PANEL_TEXT_PAD)
    tab:SetWidth(math.max(strip.minTabWidth or 60, math.min(strip.maxTabWidth or 120, w)))
    tab:SetHeight(strip.tabHeight or 26)
end

function Panel.SetSelected(tab, selected)
    SetTexColor(tab.bg, selected and Theme.colors.bgRaised or Theme.colors.bg)
    SetTexColor(tab.accent, selected and Theme.colors.gold or Theme.colors.divider)
    tab.Text:SetTextColor(unpack(selected and Theme.colors.text or Theme.colors.textMuted))
end

---------------------------------------------------------------------------
-- The "underline" look
---------------------------------------------------------------------------

local Underline = {}

function Underline.Create(strip)
    local tab = CreateFrame("Button", nil, strip)
    tab:SetHeight(strip.tabHeight or 24)

    tab.Text = Theme.FontString(tab, "OVERLAY", strip.tabFont or "GameFontNormal")
    tab.Text:SetAllPoints()
    -- A label too long even for the cap is cut short rather than folded.
    -- A tab strip is one row of words; a label that wraps does not just
    -- look wrong, it doubles the strip's height and pushes everything
    -- below it down.
    tab.Text:SetWordWrap(false)

    tab.underline = tab:CreateTexture(nil, "ARTWORK")
    tab.underline:SetHeight(UNDERLINE_H)
    tab.underline:SetPoint("BOTTOMLEFT")
    tab.underline:SetPoint("BOTTOMRIGHT")
    SetTexColor(tab.underline, Theme.colors.gold)
    tab.underline:Hide()

    -- Hover previews the selected color without moving the rule.
    tab:HookScript("OnEnter", function(self)
        if not self.isSelected then self.Text:SetTextColor(unpack(Theme.colors.gold)) end
    end)
    tab:HookScript("OnLeave", function(self)
        Underline.SetSelected(self, self.isSelected)
    end)
    return tab
end

function Underline.Init(tab, text, strip)
    tab.Text:SetText(text or "")
    local w = (tab.Text:GetStringWidth() or 0) + (strip.textPad or UNDERLINE_PAD)
    tab:SetWidth(math.max(strip.minTabWidth or 1, math.min(strip.maxTabWidth or 400, w)))
    tab:SetHeight(strip.tabHeight or 24)
end

function Underline.SetSelected(tab, selected)
    tab.Text:SetTextColor(unpack(selected and Theme.colors.text or Theme.colors.textMuted))
    tab.underline:SetShown(selected and true or false)
end

local STYLES = { panel = Panel, underline = Underline }

-- How wide a tab of each style may be before it is clamped.
--
-- Only the ceiling differs. A plate tab is one of a row of matching
-- plates, and a cap keeps a long word from making one plate twice its
-- neighbours; an underline tab is a word with a rule under it, where the
-- cap has nothing to protect and only wraps the word. The floor is the
-- same for both, because a tab too narrow to click is no better looking
-- than a wide one.
local STYLE_WIDTHS = {
    panel     = { min = 60, max = 120 },
    underline = { min = 60, max = 400 },
}

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local TabMixin = {}

function TabMixin:Init(tabID, text)
    self.tabID = tabID
    local strip = self:GetParent()
    self._bazStyle.Init(self, text, strip)
    if strip and strip.MarkDirty then strip:MarkDirty() end
end

function TabMixin:GetTabID()
    return self.tabID
end

function TabMixin:SetTabSelected(selected)
    selected = selected and true or false
    self.isSelected = selected
    self._bazStyle.SetSelected(self, selected)
end

local function CreateTab(strip)
    local style = STYLES[strip.tabStyle] or Panel
    local tab = style.Create(strip)
    tab._bazStyle = style
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
    local tab = table.remove(self._pool) or CreateTab(self)
    self.tabs[tabID] = tab
    tab.layoutIndex = tabID
    tab:Init(tabID, label)
    tab:SetTabSelected(false)
    tab:Show()
    self:MarkDirty()
    return tabID
end

-- Empty the strip, keeping the tab frames for the next build. Frames
-- can't be destroyed, so a strip that rebuilds often (the options
-- canvas, once per module) reuses them instead of leaking one set per
-- rebuild.
function StripMixin:ClearTabs()
    for _, tab in ipairs(self.tabs) do
        tab:Hide()
        tab.layoutIndex = nil
        tab.isSelected = false
        self._pool[#self._pool + 1] = tab
    end
    self.tabs = {}
    self.selectedTabID = nil
    self:MarkDirty()
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

    local inset = self.tabInset or 0

    -- Wrapping strips fill left to right and drop to a new row when the
    -- next tab would run past the width they were given. A strip with
    -- tabs the user can add to (bag categories, say) has no fixed count,
    -- so the row has to be able to become two rather than run off the
    -- edge of the panel. These lay out downward from the top, since the
    -- strip's height is what changes.
    if self.wrapWidth and self.wrapWidth > 0 then
        local x, y, rowHeight, widest = inset, 0, 0, 0
        for _, child in ipairs(items) do
            local w = child:GetWidth() or 0
            if x > inset and (x + w) > self.wrapWidth then
                y = y + rowHeight + (self.rowSpacing or 4)
                x, rowHeight = inset, 0
            end
            child:ClearAllPoints()
            child:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
            x = x + w + self.tabSpacing
            rowHeight = math.max(rowHeight, child:GetHeight() or 0)
            widest = math.max(widest, x - self.tabSpacing)
        end
        self:SetSize(math.max(math.min(widest, self.wrapWidth), 1),
            math.max(y + rowHeight, 1))
        return
    end

    -- One row. Reversed, it fills from the other end: the first tab sits
    -- against the right edge and the rest run leftward from it, which is
    -- what a strip hung off the right-hand side of a window wants. The
    -- strip's own size is the same either way - only which end the tabs
    -- are measured from changes.
    local reverse = self.reverseFlow
    local x, maxH = inset, 0
    for i, child in ipairs(items) do
        child:ClearAllPoints()
        if reverse then
            child:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -x, 0)
        else
            child:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 0)
        end
        x = x + (child:GetWidth() or 0) + (i < #items and self.tabSpacing or 0)
        maxH = math.max(maxH, child:GetHeight() or 0)
    end
    self:SetSize(math.max(x, 1), math.max(maxH, 1))
end

-- Which way the tabs run. Nothing else about the strip changes: whoever
-- owns it decides which edge it hangs from and where the add button
-- goes, because only they know what it is sitting next to.
function StripMixin:SetReverseFlow(on)
    on = on and true or false
    if self.reverseFlow == on then return end
    self.reverseFlow = on
    self:MarkDirty()
end

function StripMixin:IsReverseFlow()
    return self.reverseFlow and true or false
end

-- Give a strip a width to wrap inside. Pass nothing to go back to one
-- row that grows as wide as it likes.
function StripMixin:SetWrapWidth(width)
    self.wrapWidth = width
    self:MarkDirty()
end

---------------------------------------------------------------------------
-- Factory
---------------------------------------------------------------------------

-- BazUI.CreateTabStrip(name, parent, opts)
--   opts.style           "panel" (default) or "underline"
--   opts.minTabWidth     clamp tab widths (default 60 / 120)
--   opts.maxTabWidth
--   opts.tabHeight       height of each tab (default 26 panel / 24 underline)
--   opts.tabFont         font object name for the label (default GameFontNormal)
--   opts.textPad         padding either side of the label
--   opts.reverseFlow     lay the tabs out from the right instead
--   opts.spacing         gap between tabs (default 2)
--   opts.inset           gap before the first tab (default 0)
--   opts.wrapWidth       wrap onto more rows inside this width; also
--                        settable later with strip:SetWrapWidth(w)
--   opts.rowSpacing      gap between wrapped rows (default 4)
--   opts.dividerParent   frame to span with a rule under the tabs; the
--                        strip only spans its own tabs, so a full-width
--                        rule has to hang off the container
--   opts.tabSelectSound  SOUNDKIT id played on user clicks
function BazUI.CreateTabStrip(name, parent, opts)
    opts = opts or {}
    local strip = CreateFrame("Frame", name, parent or UIParent)
    Mixin(strip, StripMixin)
    strip.tabs           = {}
    strip._pool          = {}
    strip.tabStyle       = opts.style or "panel"
    -- Per style: see STYLE_WIDTHS. One pair of numbers served both until
    -- now, which capped every underline tab at the plate width, so
    -- "Draggable Windows" was clamped to 120 pixels, wrapped onto a
    -- second line and stood the whole strip up to two rows.
    local limits = STYLE_WIDTHS[strip.tabStyle] or STYLE_WIDTHS.panel
    strip.minTabWidth    = opts.minTabWidth or limits.min
    strip.maxTabWidth    = opts.maxTabWidth or limits.max
    strip.tabHeight      = opts.tabHeight
    -- A tab shrinks in three ways and all three have to move together:
    -- the plate's height, the face it is lettered in, and the padding
    -- either side of the word. Setting only the height leaves the text
    -- the size it was, filling the smaller plate.
    strip.tabFont        = opts.tabFont
    strip.textPad        = opts.textPad
    strip.reverseFlow    = opts.reverseFlow and true or false
    strip.tabSpacing     = opts.spacing or DEFAULT_SPACING
    strip.tabInset       = opts.inset or 0
    strip.wrapWidth      = opts.wrapWidth
    strip.rowSpacing     = opts.rowSpacing or 4
    strip.tabSelectSound = opts.tabSelectSound
    strip:SetSize(1, 1)

    -- A rule along the bottom of the row, which the underline look sits
    -- on. Anchored to the container rather than the strip, which is only
    -- as wide as its tabs.
    if opts.dividerParent then
        local rule = opts.dividerParent:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rule:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
        rule:SetPoint("BOTTOMRIGHT", opts.dividerParent, "BOTTOMRIGHT", 0, 0)
        SetTexColor(rule, Theme.colors.divider)
        strip.divider = rule
        -- It lives on the container, so it has to follow the strip by hand.
        strip:HookScript("OnShow", function(self) self.divider:Show() end)
        strip:HookScript("OnHide", function(self) self.divider:Hide() end)
        rule:SetShown(strip:IsShown())
    end
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
