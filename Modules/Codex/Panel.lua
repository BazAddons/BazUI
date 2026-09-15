-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: the window
--
-- Three bands and two columns. A title bar, a hero card carrying the
-- character the codex is answering for, and the tab strip; then a rail
-- of headline numbers beside the content, so the shape of the week
-- reads before any of the detail does.
--
-- Sections hand over rows and the panel draws them, which is what keeps
-- a lockout, a title and a reputation looking like three readings of
-- the same instrument. Each block is a card: a heading, an optional bar
-- for the one number that sums it up, then its rows.
--
-- Everything is pooled. A codex redraws on every event that touches it
-- and frames cannot be destroyed in this client.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local addon = BazUI:GetModule("Codex")
local Theme = BazUI.Skin.Theme

local Panel = {}
Codex.Panel = Panel

local WIDTH, HEIGHT = 900, 580
local PAD           = 14
local TITLE_H       = 26
local HERO_H        = 74
local TAB_H         = 26
local RAIL_W        = 176
local GAP           = 12
local SCROLLBAR_W   = 16

local ROW_H         = 24
local ROW_BAR_H     = 38   -- a row carrying its own progress bar
local CARD_HEAD     = 26
local CARD_PAD      = 8
local CARD_GAP      = 10
local TILE_H        = 46

local frame, scroll, content, hero, rail, headerHost
local rowPool, cardPool, tilePool = {}, {}, {}
local liveCards, liveTiles = {}, {}
local refreshQueued = false

---------------------------------------------------------------------------
-- What a state means, in color
---------------------------------------------------------------------------

local STATE_COLOR = {
    open   = Theme.colors.gold,
    locked = Theme.colors.caution,
    done   = Theme.colors.success,
}

Codex.STATE_COLOR = STATE_COLOR

local function ContentWidth()
    return WIDTH - PAD * 2 - RAIL_W - GAP - SCROLLBAR_W
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function AcquireRow(parent)
    local row = table.remove(rowPool)
    if row then
        row:SetParent(parent)
        return row
    end

    row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)

    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(Theme.colors.bgHover[1], Theme.colors.bgHover[2],
        Theme.colors.bgHover[3], 0.55)
    row.hover:Hide()

    -- A stripe down the left edge in the state's color: the one part of
    -- a row you can read without reading it.
    row.stripe = row:CreateTexture(nil, "ARTWORK")
    row.stripe:SetWidth(2)
    row.stripe:SetPoint("TOPLEFT", 0, -3)
    row.stripe:SetPoint("BOTTOMLEFT", 0, 3)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.label = Theme.FontString(row, "OVERLAY", "GameFontHighlight")
    row.label:SetJustifyH("LEFT")

    row.detail = Theme.FontString(row, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        if not (self._tip or self._link) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self._link then
            GameTooltip:SetHyperlink(self._link)
        else
            GameTooltip:SetText(self._tip, unpack(Theme.colors.text))
        end
        GameTooltip:Show()
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

-- A row with a reading of its own gets a hairline bar beneath the label.
local function RowBar(row)
    if not row.bar then
        row.bar = Theme.CreateStatBar(row, { height = 8 })
        row.bar:SetPoint("BOTTOMLEFT", 10, 4)
        row.bar:SetPoint("BOTTOMRIGHT", -10, 4)
    end
    return row.bar
end

local function DrawRow(row, data, y)
    -- Inset by the card's own edge so a row's hover fill and its state
    -- stripe sit inside the frame rather than on top of it.
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 1, -y)
    row:SetPoint("TOPRIGHT", -1, -y)

    local hasIcon = data.icon ~= nil
    row.icon:SetShown(hasIcon)
    if hasIcon then row.icon:SetTexture(data.icon) end

    local state = data.state
    row.stripe:SetShown(state ~= nil)
    if state then
        local c = STATE_COLOR[state] or Theme.colors.textMuted
        row.stripe:SetColorTexture(c[1], c[2], c[3], 0.9)
    end

    row.label:SetText(data.label or "")
    row.label:SetTextColor(unpack(data.muted and Theme.colors.textMuted or Theme.colors.text))

    row.detail:SetText(data.detail or "")
    row.detail:SetTextColor(unpack(STATE_COLOR[state] or Theme.colors.textSoft))

    local progress = data.progress
    local offset = progress and 5 or 0

    row.label:ClearAllPoints()
    row.detail:ClearAllPoints()
    row.detail:SetPoint("RIGHT", -8, offset)
    row.label:SetPoint("LEFT", hasIcon and 30 or 10, offset)
    row.label:SetPoint("RIGHT", row.detail, "LEFT", -8, 0)

    if progress then
        local bar = RowBar(row)
        bar:SetBarColor(progress.color or STATE_COLOR[state] or Theme.colors.gold)
        bar:SetValues(progress.value, progress.max)
        bar:Show()
        row:SetHeight(ROW_BAR_H)
    else
        if row.bar then row.bar:Hide() end
        row:SetHeight(ROW_H)
    end

    row._tip     = data.tip
    row._link    = data.link
    row._onClick = data.onClick
    row:Show()
    return progress and ROW_BAR_H or ROW_H
end

---------------------------------------------------------------------------
-- Cards
--
-- One block of the codex: a heading you can fold away, the number that
-- sums the block up, and the rows.
---------------------------------------------------------------------------

local function AcquireCard()
    local card = table.remove(cardPool)
    if card then
        card:SetParent(content)
        return card
    end

    card = CreateFrame("Frame", nil, content)
    Theme.ApplyFlatPanel(card, Theme.colors.bgRaised, Theme.colors.edge)

    card.head = CreateFrame("Button", nil, card)
    card.head:SetHeight(CARD_HEAD)
    card.head:SetPoint("TOPLEFT", 1, -1)
    card.head:SetPoint("TOPRIGHT", -1, -1)

    card.head.bg = card.head:CreateTexture(nil, "BACKGROUND")
    card.head.bg:SetAllPoints()
    card.head.bg:SetColorTexture(0, 0, 0, 0.25)

    -- A band of the section's own color down the left of the card, and
    -- a wash of it behind the heading. This is what stops six cards of
    -- identical chrome reading as one long list.
    card.accent = card:CreateTexture(nil, "ARTWORK")
    card.accent:SetWidth(3)
    card.accent:SetPoint("TOPLEFT", 1, -1)
    card.accent:SetPoint("BOTTOMLEFT", 1, 1)

    card.chevron = Theme.FontString(card.head, "OVERLAY", "GameFontNormalSmall")
    card.chevron:SetPoint("LEFT", 12, 0)
    card.chevron:SetTextColor(unpack(Theme.colors.goldDim))

    card.title = Theme.FontString(card.head, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("LEFT", 27, 0)
    card.title:SetTextColor(unpack(Theme.colors.gold))

    card.count = Theme.FontString(card.head, "OVERLAY", "GameFontHighlightSmall")
    card.count:SetPoint("RIGHT", -9, 0)
    card.count:SetTextColor(unpack(Theme.colors.textMuted))

    -- The same gold rule the tab strip draws, so a card reads as part of
    -- the same object rather than a box sitting on top of it.
    card.rule = card.head:CreateTexture(nil, "OVERLAY")
    card.rule:SetHeight(1)
    card.rule:SetPoint("BOTTOMLEFT")
    card.rule:SetPoint("BOTTOMRIGHT")
    card.rule:SetColorTexture(Theme.colors.divider[1], Theme.colors.divider[2],
        Theme.colors.divider[3], Theme.colors.divider[4])

    card.bar = Theme.CreateStatBar(card, { height = 11, labels = true })
    card.bar:SetPoint("TOPLEFT", CARD_PAD + 1, -(CARD_HEAD + CARD_PAD))
    card.bar:SetPoint("TOPRIGHT", -(CARD_PAD + 1), -(CARD_HEAD + CARD_PAD))

    card.head:SetScript("OnEnter", function(self)
        local a = self:GetParent()._accent or Theme.colors.gold
        self.bg:SetColorTexture(a[1] * 0.55, a[2] * 0.55, a[3] * 0.55, 0.55)
    end)
    card.head:SetScript("OnLeave", function(self)
        local a = self:GetParent()._accent or Theme.colors.gold
        self.bg:SetColorTexture(a[1] * 0.35, a[2] * 0.35, a[3] * 0.35, 0.40)
    end)
    card.head:SetScript("OnClick", function(self)
        local id = self:GetParent()._sectionID
        Codex:SetCollapsed(id, not Codex:IsCollapsed(id))
        Panel:Refresh()
    end)

    card.rows = {}
    return card
end

local function ReleaseAll()
    for _, card in ipairs(liveCards) do
        for _, row in ipairs(card.rows) do
            row:Hide()
            rowPool[#rowPool + 1] = row
        end
        card.rows = {}
        card:Hide()
        cardPool[#cardPool + 1] = card
    end
    liveCards = {}

    for _, tile in ipairs(liveTiles) do
        tile:Hide()
        tilePool[#tilePool + 1] = tile
    end
    liveTiles = {}
end

---------------------------------------------------------------------------
-- The rail
--
-- One tile per block that can put a single number on itself. This is
-- the half of the window you read from across the room.
---------------------------------------------------------------------------

local function AcquireTile()
    local tile = table.remove(tilePool)
    if tile then
        tile:SetParent(rail)
        return tile
    end

    tile = CreateFrame("Frame", nil, rail)
    tile:SetHeight(TILE_H)
    Theme.ApplyFlatPanel(tile, Theme.colors.bgRaised, Theme.colors.edge)

    tile.accent = tile:CreateTexture(nil, "ARTWORK")
    tile.accent:SetWidth(3)
    tile.accent:SetPoint("TOPLEFT", 1, -1)
    tile.accent:SetPoint("BOTTOMLEFT", 1, 1)

    tile.value = Theme.FontString(tile, "OVERLAY", "GameFontNormalLarge")
    tile.value:SetPoint("TOPLEFT", 10, -6)
    tile.value:SetPoint("TOPRIGHT", -8, -6)
    tile.value:SetJustifyH("LEFT")

    tile.label = Theme.FontString(tile, "OVERLAY", "GameFontHighlightSmall")
    tile.label:SetPoint("BOTTOMLEFT", 10, 7)
    tile.label:SetPoint("BOTTOMRIGHT", -8, 7)
    tile.label:SetJustifyH("LEFT")
    tile.label:SetTextColor(unpack(Theme.colors.textMuted))

    return tile
end

local function DrawRail(tab)
    local highlights = {}

    for _, def in ipairs(Codex:GetSections(tab)) do
        if def.GetHighlight then
            local h = def.GetHighlight()
            if h and h.value then highlights[#highlights + 1] = h end
        end
    end
    local custom = Codex.customTabs and Codex.customTabs[tab]
    if custom and custom.GetHighlights then
        for _, h in ipairs(custom.GetHighlights() or {}) do
            if h and h.value then highlights[#highlights + 1] = h end
        end
    end

    rail.empty:SetShown(#highlights == 0)

    local y = 0
    for _, h in ipairs(highlights) do
        local tile = AcquireTile()
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", 0, -y)
        tile:SetPoint("TOPRIGHT", 0, -y)
        tile.value:SetText(tostring(h.value))
        tile.value:SetTextColor(unpack(h.color or Theme.colors.gold))
        tile.accent:SetColorTexture(unpack(h.color or Theme.colors.goldDim))
        tile.label:SetText(h.label or "")
        tile:Show()
        liveTiles[#liveTiles + 1] = tile
        y = y + TILE_H + 6
    end
end

---------------------------------------------------------------------------
-- The hero card
---------------------------------------------------------------------------

local function UpdateHero()
    if not hero then return end

    local name = UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName()
    hero.name:SetText(realm and (name .. " - " .. realm) or name)

    local class, classFile = UnitClass("player")
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then
        hero.name:SetTextColor(c.r, c.g, c.b)
    else
        hero.name:SetTextColor(unpack(Theme.colors.gold))
    end

    local parts = { string.format("Level %d %s", UnitLevel("player") or 1, class or "") }
    local zone = GetRealZoneText and GetRealZoneText()
    if zone and zone ~= "" then parts[#parts + 1] = zone end
    hero.sub:SetText(table.concat(parts, "   |   "))

    hero.money:SetText(BazUI:FormatMoney(GetMoney and GetMoney() or 0))

    -- The portrait wears the round-button mask, and a masked texture is
    -- fussy about what may be done to it; a failure here must not take
    -- the rest of the card down with it.
    if SetPortraitTexture then
        pcall(SetPortraitTexture, hero.portraitTexture, "player")
    end
end

---------------------------------------------------------------------------
-- Drawing one tab
---------------------------------------------------------------------------

function Panel:Refresh()
    if not frame or not frame:IsShown() then return end
    ReleaseAll()
    UpdateHero()

    local tab   = addon:GetSetting("activeTab") or "today"
    local width = ContentWidth()

    DrawRail(tab)

    -- A tab that owns its page keeps its frames between visits, so the
    -- ones we are not showing have to be put away.
    for key, def in pairs(Codex.customTabs or {}) do
        if key ~= tab and def.Hide then def.Hide() end
    end

    local custom = Codex.customTabs and Codex.customTabs[tab]
    local headerHeight = 1
    if custom and custom.RenderHeader then
        headerHeight = math.max(custom.RenderHeader(headerHost, width) or 1, 1)
    end
    headerHost:SetHeight(headerHeight)

    if custom then
        custom.Render(content, width)
        content:SetHeight(math.max(custom.height or 1, 1))
        return
    end

    local y = 0
    for _, def in ipairs(Codex:GetSections(tab)) do
        local card = AcquireCard()
        card._sectionID = def.id
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 0, -y)
        card:SetWidth(width)
        card.title:SetText(def.title or def.id)

        local accent = def.accent or Theme.colors.gold
        card._accent = accent
        card.accent:SetColorTexture(accent[1], accent[2], accent[3], 0.85)
        card.head.bg:SetColorTexture(accent[1] * 0.35, accent[2] * 0.35,
            accent[3] * 0.35, 0.40)
        card.title:SetTextColor(unpack(accent))
        card.rule:SetColorTexture(accent[1], accent[2], accent[3], 0.45)

        local collapsed = Codex:IsCollapsed(def.id)
        card.chevron:SetText(collapsed and "+" or "-")

        if collapsed then
            card.bar:Hide()
            card.count:SetText(def.collapsedHint or "")
            card:SetHeight(CARD_HEAD + 2)
        else
            local inner = CARD_HEAD

            -- The bar under a heading is the whole block in one reading.
            local barDef = def.GetBar and def.GetBar() or nil
            if barDef then
                card.bar:SetLabel(barDef.label)
                card.bar:SetBarColor(barDef.color)
                card.bar:SetValues(barDef.value, barDef.max, barDef.text)
                card.bar:SetBreakpoints(barDef.breakpoints, barDef.max)
                card.bar:Show()
                inner = inner + CARD_PAD + 24
            else
                card.bar:Hide()
            end

            inner = inner + CARD_PAD

            local rows = (def.GetRows and def.GetRows()) or {}
            if #rows == 0 then
                local row = AcquireRow(card)
                inner = inner + DrawRow(row, {
                    label = def.empty or "Nothing to show.",
                    muted = true,
                }, inner)
                card.rows[#card.rows + 1] = row
            else
                for _, data in ipairs(rows) do
                    local row = AcquireRow(card)
                    inner = inner + DrawRow(row, data, inner)
                    card.rows[#card.rows + 1] = row
                end
            end

            card.count:SetText(#rows > 0 and tostring(#rows) or "")
            card:SetHeight(inner + CARD_PAD)
        end

        card:Show()
        liveCards[#liveCards + 1] = card
        y = y + card:GetHeight() + CARD_GAP
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

local function BuildHero(parent)
    hero = CreateFrame("Frame", nil, parent)
    hero:SetHeight(HERO_H)
    Theme.ApplyFlatPanel(hero, Theme.colors.bgRaised, Theme.colors.edge)

    -- A band of the addon's own frame art down the right of the card,
    -- faded almost away: enough that the hero is not a flat rectangle.
    local art = hero:CreateTexture(nil, "ARTWORK")
    art:SetTexture(BazUI.Skin.MINIMAP_RING)
    art:SetPoint("TOPRIGHT", -1, -1)
    art:SetPoint("BOTTOMRIGHT", -1, 1)
    art:SetWidth(280)
    art:SetAlpha(0.09)
    art:SetTexCoord(0.5, 1, 0.08, 0.62)

    local portrait = CreateFrame("Button", nil, hero)
    portrait:SetSize(52, 52)
    portrait:SetPoint("LEFT", 14, 0)
    local tex = portrait:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("CENTER")
    hero.portraitTexture = tex
    Theme.ApplyRoundButton(portrait, tex, { size = 52 })
    portrait:SetScript("OnClick", function()
        if ToggleCharacter then ToggleCharacter("PaperDollFrame") end
    end)
    portrait:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Open the character sheet", unpack(Theme.colors.text))
        GameTooltip:Show()
    end)
    portrait:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hero.portrait = portrait

    hero.name = Theme.FontString(hero, "OVERLAY", "GameFontNormalLarge")
    hero.name:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 14, -6)
    hero.name:SetJustifyH("LEFT")

    hero.sub = Theme.FontString(hero, "OVERLAY", "GameFontHighlightSmall")
    hero.sub:SetPoint("TOPLEFT", hero.name, "BOTTOMLEFT", 1, -6)
    hero.sub:SetJustifyH("LEFT")
    hero.sub:SetTextColor(unpack(Theme.colors.textSoft))

    hero.moneyLabel = Theme.FontString(hero, "OVERLAY", "GameFontHighlightSmall")
    hero.moneyLabel:SetPoint("TOPRIGHT", -14, -14)
    hero.moneyLabel:SetText("Purse")
    hero.moneyLabel:SetTextColor(unpack(Theme.colors.textMuted))

    hero.money = Theme.FontString(hero, "OVERLAY", "GameFontNormal")
    hero.money:SetPoint("TOPRIGHT", hero.moneyLabel, "BOTTOMRIGHT", 0, -5)
    hero.money:SetJustifyH("RIGHT")

    return hero
end

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

    local title = Theme.FontString(frame, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD, -9)
    title:SetText("CODEX")
    title:SetTextColor(unpack(Theme.colors.gold))

    local version = Theme.FontString(frame, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("TOPRIGHT", -32, -12)
    version:SetText(BazUI.VERSION or "")
    version:SetTextColor(unpack(Theme.colors.textMuted))

    local titleRule = frame:CreateTexture(nil, "ARTWORK")
    titleRule:SetHeight(1)
    titleRule:SetPoint("TOPLEFT", PAD, -TITLE_H)
    titleRule:SetPoint("TOPRIGHT", -PAD, -TITLE_H)
    titleRule:SetColorTexture(Theme.colors.divider[1], Theme.colors.divider[2],
        Theme.colors.divider[3], Theme.colors.divider[4])

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() Codex:Hide() end)

    BuildHero(frame)
    hero:SetPoint("TOPLEFT", PAD, -(TITLE_H + 10))
    hero:SetPoint("TOPRIGHT", -PAD, -(TITLE_H + 10))

    -- The suite's tab strip, in the look the panels wear.
    local tabTop = TITLE_H + 10 + HERO_H + 8
    local tabRow = CreateFrame("Frame", nil, frame)
    tabRow:SetHeight(TAB_H)
    tabRow:SetPoint("TOPLEFT", PAD, -tabTop)
    tabRow:SetPoint("TOPRIGHT", -PAD, -tabTop)

    local strip = BazUI.CreateTabStrip(nil, tabRow, {
        style = "underline", tabHeight = TAB_H, spacing = 18,
        dividerParent = tabRow,
    })
    strip:SetPoint("BOTTOMLEFT")
    frame.tabStrip = strip
    Codex.tabKeys = {}

    local bodyTop = tabTop + TAB_H + 10

    rail = CreateFrame("Frame", nil, frame)
    rail:SetPoint("TOPLEFT", PAD, -bodyTop)
    rail:SetPoint("BOTTOMLEFT", PAD, PAD)
    rail:SetWidth(RAIL_W)

    rail.empty = Theme.FontString(rail, "OVERLAY", "GameFontHighlightSmall")
    rail.empty:SetPoint("TOPLEFT", 2, -2)
    rail.empty:SetPoint("TOPRIGHT", -2, -2)
    rail.empty:SetJustifyH("LEFT")
    rail.empty:SetText("Nothing to count on this page.")
    rail.empty:SetTextColor(unpack(Theme.colors.textMuted))
    rail.empty:Hide()

    -- A page that takes typing puts its box and its filters up here,
    -- outside the scroll, so they stay put while the list moves.
    headerHost = CreateFrame("Frame", nil, frame)
    headerHost:SetPoint("TOPLEFT", rail, "TOPRIGHT", GAP, 0)
    headerHost:SetPoint("RIGHT", frame, "RIGHT", -(PAD + SCROLLBAR_W), 0)
    headerHost:SetHeight(1)

    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", headerHost, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -(PAD + SCROLLBAR_W), PAD)
    scroll:EnableMouseWheel(true)

    local bar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 5, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 5, 0)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
    Theme.AutoFadeScrollBar(bar, scroll)

    content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(ContentWidth())
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
    -- The hero card is about the player, so it follows the player.
    for _, event in ipairs({ "PLAYER_MONEY", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA" }) do
        addon:On(event, function() Panel:QueueRefresh() end)
    end
    addon:OnProfileChanged(function()
        Panel:RebuildTabs()
        Panel:QueueRefresh()
    end)
end
