-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: the window
--
-- Flat chrome, the suite's face, the shared tab strip. Sections supply
-- rows and this draws them, so every tracker reads the same whether it
-- is counting lockouts or steps in a quest chain.
--
-- Rows are pooled: a codex redraws on every event that touches it, and
-- frames cannot be destroyed in this client.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local addon = BazUI:GetModule("Codex")
local Theme = BazUI.Skin.Theme

local Panel = {}
Codex.Panel = Panel

local WIDTH, HEIGHT   = 460, 520
local PAD             = 12
local HEADER_H        = 30
local TAB_H           = 24
local ROW_H           = 22
local SECTION_H       = 22
local INDENT          = 10

local frame, scroll, content
local rowPool, sectionPool = {}, {}
local refreshQueued = false

---------------------------------------------------------------------------
-- State colours
---------------------------------------------------------------------------

local STATE_COLOR = {
    open   = Theme.colors.gold,
    locked = Theme.colors.textMuted,
    done   = { 0.45, 0.75, 0.45, 1 },
}

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function AcquireRow()
    local row = table.remove(rowPool)
    if row then return row end

    row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)

    row.label = Theme.FontString(row, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", INDENT, 0)
    row.label:SetJustifyH("LEFT")

    row.detail = Theme.FontString(row, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetPoint("RIGHT", -INDENT, 0)
    row.detail:SetJustifyH("RIGHT")

    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(Theme.colors.bgHover[1], Theme.colors.bgHover[2],
        Theme.colors.bgHover[3], 0.5)
    row.hover:Hide()

    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        if self._tip or self._link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self._link then
                GameTooltip:SetHyperlink(self._link)
            else
                GameTooltip:SetText(self._tip, unpack(Theme.colors.text))
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        if self._onClick then self._onClick(self) end
    end)
    return row
end

local function AcquireSectionHeader()
    local header = table.remove(sectionPool)
    if header then return header end

    header = CreateFrame("Button", nil, content)
    header:SetHeight(SECTION_H)

    header.title = Theme.FontString(header, "OVERLAY", "GameFontNormal")
    header.title:SetPoint("LEFT", 0, 0)
    header.title:SetTextColor(unpack(Theme.colors.gold))

    header.rule = header:CreateTexture(nil, "ARTWORK")
    header.rule:SetHeight(1)
    header.rule:SetPoint("BOTTOMLEFT", 0, 2)
    header.rule:SetPoint("BOTTOMRIGHT", 0, 2)
    header.rule:SetColorTexture(Theme.colors.divider[1], Theme.colors.divider[2],
        Theme.colors.divider[3], Theme.colors.divider[4])

    header:SetScript("OnClick", function(self)
        Codex:SetCollapsed(self._sectionID, not Codex:IsCollapsed(self._sectionID))
        Panel:Refresh()
    end)
    return header
end

local function ReleaseAll()
    for _, row in ipairs(content._rows or {}) do
        row:Hide()
        rowPool[#rowPool + 1] = row
    end
    for _, header in ipairs(content._headers or {}) do
        header:Hide()
        sectionPool[#sectionPool + 1] = header
    end
    content._rows, content._headers = {}, {}
end

---------------------------------------------------------------------------
-- Drawing one tab
---------------------------------------------------------------------------

function Panel:Refresh()
    if not frame or not frame:IsShown() then return end
    ReleaseAll()

    local tab   = addon:GetSetting("activeTab") or "today"
    local width = WIDTH - PAD * 2 - 18
    local y     = 0

    -- A tab may own its whole page (item lookup does); otherwise it is
    -- a stack of sections.
    -- A tab that owns its page keeps its frames between visits, so the
    -- ones we are not showing have to be put away.
    for key, def in pairs(Codex.customTabs or {}) do
        if key ~= tab and def.Hide then def.Hide() end
    end

    local custom = Codex.customTabs and Codex.customTabs[tab]
    if custom then
        custom.Render(content, width)
        content:SetHeight(math.max(custom.height or 1, 1))
        return
    end

    for _, def in ipairs(Codex:GetSections(tab)) do
        local header = AcquireSectionHeader()
        header._sectionID = def.id
        header:SetWidth(width)
        header:SetPoint("TOPLEFT", 0, -y)
        local collapsed = Codex:IsCollapsed(def.id)
        header.title:SetText((collapsed and "> " or "v ") .. (def.title or def.id))
        header:Show()
        content._headers[#content._headers + 1] = header
        y = y + SECTION_H + 2

        if not collapsed then
            local rows = (def.GetRows and def.GetRows()) or {}
            if #rows == 0 then
                local row = AcquireRow()
                row:SetWidth(width)
                row:SetPoint("TOPLEFT", 0, -y)
                row.label:SetText(def.empty or "Nothing to show.")
                row.label:SetTextColor(unpack(Theme.colors.textMuted))
                row.detail:SetText("")
                row._tip, row._link, row._onClick = nil, nil, nil
                row:Show()
                content._rows[#content._rows + 1] = row
                y = y + ROW_H
            else
                for _, data in ipairs(rows) do
                    local row = AcquireRow()
                    row:SetWidth(width)
                    row:SetPoint("TOPLEFT", 0, -y)
                    row.label:SetText(data.label or "")
                    row.label:SetTextColor(unpack(Theme.colors.text))
                    row.detail:SetText(data.detail or "")
                    row.detail:SetTextColor(unpack(STATE_COLOR[data.state] or Theme.colors.textSoft))
                    row._tip     = data.tip
                    row._link    = data.link
                    row._onClick = data.onClick
                    row:Show()
                    content._rows[#content._rows + 1] = row
                    y = y + ROW_H
                end
            end
            y = y + 6
        end
    end

    content:SetHeight(math.max(y, 1))
end

function Panel:QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        Panel:Refresh()
    end)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Build()
    if frame then return frame end

    frame = CreateFrame("Frame", "BazUICodexFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        addon:SetSetting("position", { point = point, relPoint = relPoint, x = x, y = y })
    end)
    Theme.ApplyFlatPanel(frame)
    frame:Hide()
    Codex.frame = frame

    -- Escape closes it, like every other BazUI window.
    tinsert(UISpecialFrames, "BazUICodexFrame")

    local title = Theme.FontString(frame, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText("Codex")
    title:SetTextColor(unpack(Theme.colors.gold))

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() Codex:Hide() end)

    -- The suite's tab strip, in the look panels use.
    local tabRow = CreateFrame("Frame", nil, frame)
    tabRow:SetHeight(TAB_H)
    tabRow:SetPoint("TOPLEFT", PAD, -(PAD + HEADER_H))
    tabRow:SetPoint("TOPRIGHT", -PAD, -(PAD + HEADER_H))

    local strip = BazUI.CreateTabStrip(nil, tabRow, {
        style = "underline", tabHeight = TAB_H, spacing = 16,
        dividerParent = tabRow,
    })
    strip:SetPoint("BOTTOMLEFT")
    frame.tabStrip = strip
    Codex.tabKeys = {}

    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", PAD, -(PAD + HEADER_H + TAB_H + 8))
    scroll:SetPoint("BOTTOMRIGHT", -(PAD + 6), PAD)
    scroll:EnableMouseWheel(true)

    local bar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)

    content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(WIDTH - PAD * 2 - 18)
    content._rows, content._headers = {}, {}
    scroll:SetScrollChild(content)
    Codex.content = content

    return frame
end

-- Tabs are rebuilt whenever a section or a custom tab registers, so a
-- module loading late still gets one.
function Panel:RebuildTabs()
    if not frame then return end
    local strip = frame.tabStrip
    strip:ClearTabs()
    Codex.tabKeys = {}

    local seen, order = {}, {}
    local function Want(key, label, sort)
        if seen[key] then return end
        seen[key] = true
        order[#order + 1] = { key = key, label = label, sort = sort or 100 }
    end
    -- The two questions the codex exists to answer come first, always,
    -- even before anything has registered against them.
    Want("today",    "Today",    10)
    Want("achieved", "Achieved", 20)
    for _, def in pairs(Codex.sections) do
        Want(def.tab, def.tabLabel or def.tab:gsub("^%l", string.upper), def.tabOrder)
    end
    for key, def in pairs(Codex.customTabs or {}) do
        Want(key, def.label or key, def.order)
    end
    table.sort(order, function(a, b)
        if a.sort ~= b.sort then return a.sort < b.sort end
        return a.label < b.label
    end)

    local active = addon:GetSetting("activeTab") or "today"
    local activeID
    for _, entry in ipairs(order) do
        local id = strip:AddTab(entry.label)
        Codex.tabKeys[id] = entry.key
        if entry.key == active then activeID = id end
    end
    strip:SetTabSelectedCallback(function(tabID, isUserAction)
        local key = Codex.tabKeys[tabID]
        if not key then return end
        addon:SetSetting("activeTab", key)
        if isUserAction then Panel:Refresh() end
    end)
    strip:Layout()
    if activeID then
        strip:SetTabVisuallySelected(activeID)
        strip.selectedTabID = activeID
    end
end

function Panel:ApplySettings()
    if not frame then return end
    frame:SetScale(addon:GetSetting("scale") or 1)
    Theme.SetFlatPanelAlpha(frame, addon:GetSetting("opacity") or 0.95, 1)
    frame:ClearAllPoints()
    local pos = addon:GetSetting("position")
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function Codex:Show()
    Build()
    self.Panel:ApplySettings()
    self.Panel:RebuildTabs()
    frame:Show()
    self.Panel:Refresh()
end

function Codex:Hide()
    if frame then frame:Hide() end
end

function Codex:Toggle()
    if frame and frame:IsShown() then self:Hide() else self:Show() end
end

function Codex:IsShown()
    return frame and frame:IsShown() or false
end

function Codex:ApplySettings()
    if frame then self.Panel:ApplySettings() end
end

function Codex:Initialize()
    -- Sections ask to be redrawn through the events they declared.
    local wired = {}
    for _, def in pairs(self.sections) do
        for _, event in ipairs(def.events or {}) do
            if not wired[event] then
                wired[event] = true
                addon:On(event, function() Panel:QueueRefresh() end)
            end
        end
    end
    addon:OnProfileChanged(function()
        Panel:RebuildTabs()
        Panel:QueueRefresh()
    end)
end
