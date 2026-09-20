-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: the window
--
-- A window made of the game's own parts. The frame is the one the
-- talents and the character sheet come in - rock, gold border, a round
-- portrait in the corner. It is laid on the dark leather the Appearances
-- panel is laid on, and a column of picture tabs hangs off its right
-- edge, the way every Forever panel picks its pages. Nothing here is a
-- drawing of a WoW frame; it is the frame.
--
-- On the leather, three shapes, all borrowed:
--
--   a box    - the thin-bordered plate the game draws tooltips in. The
--              character sits in one, each block of a page is one, each
--              number on the rail is one.
--   a plate  - the carved heading the character sheet puts over
--              "General" and "Weapons". Every block wears one.
--   a band   - the soft stripe the character sheet lays under every
--              other stat line. Rows inside a block sit on those.
--
-- Sections hand over rows and the panel draws them, which is what keeps
-- a lockout, a title and a reputation looking like three readings of
-- the same instrument. Numbers are written, not drawn: a block says
-- "3 of 9" in words and a row says "ready" in its colour.
--
-- Everything is pooled. A codex redraws on every event that touches it
-- and frames cannot be destroyed in this client.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local addon = BazUI:GetModule("Codex")
local Theme = BazUI.Skin.Theme

local Panel = {}
Codex.Panel = Panel

-- The size and place of the Talents window on Forever (PlayerSpellsFrame's
-- talentsWidth / talentsHeight, hung from the top of the screen), so the
-- codex opens where the talents do and covers the same ground.
local WIDTH, HEIGHT = 1218, 708
local HOME_POINT, HOME_Y = "TOP", -41
local TOP           = 26   -- the window template's title bar
local EDGE_L        = 4    -- where an inset tucks under the frame border,
local EDGE_R        = 6    -- the offsets Blizzard's own button frames use
local EDGE_B        = 6
local INNER         = 16   -- inside the inset's border, clear of the filigree
local HERO_H        = 64
local RAIL_W        = 200
local GAP           = 12
local SCROLLBAR_W   = 16
local TABS_Y        = -30  -- where the character sheet hangs its tabs

local ROW_H         = 26   -- the character sheet's stat line, near enough
local PLATE_W       = 197  -- the heading plate's own size
local PLATE_H       = 40
local CARD_PAD      = 10
local CARD_GAP      = 12
local TILE_H        = 58
local TILE_GAP      = 8

local frame, inset, scroll, content, hero, rail, headerHost
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

-- The tab pictures. Blizzard's icons for now; when the codex has art of
-- its own, this is the one table to point at it.
local TAB_ICONS = {
    today    = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    achieved = "Interface\\Icons\\Achievement_General",
    items    = "Interface\\Icons\\inv_misc_bag_08",
    wishlist = "Interface\\Icons\\INV_Misc_Note_01",
}
local TAB_ICON_DEFAULT = "Interface\\Icons\\INV_Misc_Book_09"

local function ContentWidth()
    -- The scroll frame knows better than arithmetic does, once it has
    -- been laid out; before that, the arithmetic.
    local w = scroll and scroll:GetWidth()
    if w and w > 50 then return math.floor(w) end
    return WIDTH - EDGE_L - EDGE_R - INNER * 2 - RAIL_W - GAP - SCROLLBAR_W
end

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- How tall a page may be before it has to scroll. A page that lays
-- itself out to fit asks this rather than guessing at the window.
function Panel.ContentHeight()
    local h = scroll and scroll:GetHeight()
    if h and h > 50 then return math.floor(h) end
    return HEIGHT - TOP - EDGE_B - INNER * 2 - HERO_H - GAP
end

---------------------------------------------------------------------------
-- Boxes
--
-- The game's tooltip backdrop - the thin nine-slice border round a dark
-- plate - which both clients ship, so a box here is the same box the
-- game puts round every tooltip. The fill is thinned so the leather
-- shows through and a box reads as sitting on it rather than pasted on.
---------------------------------------------------------------------------

local BOX_TEMPLATE = "TooltipBackdropTemplate"
local BOX_FILL     = { 0.02, 0.02, 0.02, 0.62 }

Panel.BOX_FILL = BOX_FILL

local function HasBoxTemplate()
    return BazUI.Has and BazUI.Has.Template and BazUI.Has.Template(BOX_TEMPLATE)
end

function Panel.CreateBox(parent, frameType)
    local f
    if HasBoxTemplate() then
        f = CreateFrame(frameType or "Frame", nil, parent, BOX_TEMPLATE)
        f.bazBox = true
        f:SetBackdropColor(unpack(BOX_FILL))
    else
        f = CreateFrame(frameType or "Frame", nil, parent)
        Theme.ApplyFlatPanel(f, Theme.colors.bgRaised, Theme.colors.edge)
    end
    return f
end

function Panel.SetBoxFill(f, color)
    color = color or BOX_FILL
    if f.bazBox then
        f:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
    else
        Theme.SetFlatPanelColor(f, color, color[4])
    end
end

-- nil puts the border back to the art's own colour.
function Panel.SetBoxBorder(f, color)
    if f.bazBox then
        if color then
            f:SetBackdropBorderColor(color[1], color[2], color[3], 0.9)
        else
            f:SetBackdropBorderColor(1, 1, 1, 1)
        end
    elseif f._bazFlatPanel then
        f._bazFlatPanel.edgeColor = color or Theme.colors.edge
        Theme.SetFlatPanelAlpha(f)
    end
end

---------------------------------------------------------------------------
-- Bands and plates
--
-- The character sheet's two pieces of furniture. The band is a soft
-- stripe that fades at both ends; drawn under every other row it makes
-- a list countable without ruling it. The plate is the carved heading.
-- Both are fixed-size art on the character sheet; the band is a
-- gradient and stretches without complaint (retail already stretches
-- it), the plate has carved ends and is kept at its own size.
---------------------------------------------------------------------------

local BAND_ATLAS  = "UI-Character-Info-Line-Bounce"
local PLATE_ATLAS = "UI-Character-Info-Title"
local BAND_ALPHA  = 0.55

-- A row that sits on a band: hover on top, band beneath. Pages that draw
-- their own rows ask for this so theirs match.
function Panel.CreateBandRow(parent)
    local row = CreateFrame("Button", nil, parent)

    row.band = row:CreateTexture(nil, "BACKGROUND", nil, -2)
    row.band:SetAllPoints()
    if HasAtlas(BAND_ATLAS) then
        row.band:SetAtlas(BAND_ATLAS, false)
        row.band:SetAlpha(BAND_ALPHA)
    else
        row.band:SetColorTexture(1, 1, 1, 0.05)
    end

    row.hover = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(Theme.colors.bgHover[1], Theme.colors.bgHover[2],
        Theme.colors.bgHover[3], 0.6)
    row.hover:Hide()

    return row
end

-- Every other row gets the band, counted from the top of its list.
function Panel.SetRowBand(row, index)
    row.band:SetShown(index % 2 == 1)
end

-- The heading plate, with its title on it. Falls back to a bare title
-- where the art is missing.
local function CreatePlate(parent)
    local plate = CreateFrame("Frame", nil, parent)
    plate:SetSize(PLATE_W, PLATE_H)
    if HasAtlas(PLATE_ATLAS) then
        plate.art = plate:CreateTexture(nil, "ARTWORK")
        plate.art:SetAtlas(PLATE_ATLAS, true)
        plate.art:SetPoint("CENTER")
    end
    plate.title = Theme.FontString(plate, "OVERLAY", "GameFontNormal")
    plate.title:SetPoint("CENTER", 0, 1)
    plate.title:SetWidth(PLATE_W - 30)
    plate.title:SetWordWrap(false)
    plate.title:SetTextColor(unpack(Theme.colors.gold))
    return plate
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

    row = Panel.CreateBandRow(parent)
    row:SetHeight(ROW_H)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.label = Theme.FontString(row, "OVERLAY", "GameFontHighlight")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

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

local function DrawRow(row, data, y, index)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", CARD_PAD, -y)
    row:SetPoint("TOPRIGHT", -CARD_PAD, -y)
    row:SetHeight(ROW_H)
    Panel.SetRowBand(row, index)

    local hasIcon = data.icon ~= nil
    row.icon:SetShown(hasIcon)
    if hasIcon then row.icon:SetTexture(data.icon) end

    local state = data.state
    local c = state and (STATE_COLOR[state] or Theme.colors.textMuted) or nil

    row.label:SetText(data.label or "")
    row.label:SetTextColor(unpack(data.muted and Theme.colors.textMuted or Theme.colors.text))

    -- A fraction with no words of its own is written as one.
    local detail = data.detail
    if (not detail or detail == "") and data.progress and data.progress.max then
        detail = string.format("%s of %s", tostring(data.progress.value or 0),
            tostring(data.progress.max))
    end
    row.detail:SetText(detail or "")
    row.detail:SetTextColor(unpack(c or Theme.colors.textSoft))

    row.label:ClearAllPoints()
    row.detail:ClearAllPoints()
    row.detail:SetPoint("RIGHT", -10, 0)
    row.label:SetPoint("LEFT", hasIcon and 36 or 11, 0)
    row.label:SetPoint("RIGHT", row.detail, "LEFT", -10, 0)

    row._tip     = data.tip
    row._link    = data.link
    row._onClick = data.onClick
    row:Show()
    return ROW_H
end

---------------------------------------------------------------------------
-- Cards
--
-- One block of the codex: a plate with the heading on it, the sentence
-- that sums the block up, and the rows on their bands. Clicking the
-- heading folds the block away.
---------------------------------------------------------------------------

local function AcquireCard()
    local card = table.remove(cardPool)
    if card then
        card:SetParent(content)
        return card
    end

    card = Panel.CreateBox(content)

    card.head = CreateFrame("Button", nil, card)
    card.head:SetPoint("TOPLEFT", 4, -4)
    card.head:SetPoint("TOPRIGHT", -4, -4)

    card.plate = CreatePlate(card.head)
    card.plate:SetPoint("TOP", 0, -2)
    card.title = card.plate.title

    -- The one line that sums the block up, under the plate.
    card.summary = Theme.FontString(card.head, "OVERLAY", "GameFontHighlightSmall")
    card.summary:SetPoint("TOP", card.plate, "BOTTOM", 0, -1)
    card.summary:SetJustifyH("CENTER")
    card.summary:SetTextColor(unpack(Theme.colors.textSoft))

    -- The fold toggle is the same arrow the action bars use for a flyout,
    -- pointing down when the block is open and along when it is folded.
    card.arrow = card.head:CreateTexture(nil, "OVERLAY")
    card.arrow:SetPoint("TOPRIGHT", -(CARD_PAD - 2), -12)
    card.arrow:SetAlpha(0.6)

    card.count = Theme.FontString(card.head, "OVERLAY", "GameFontHighlightSmall")
    card.count:SetPoint("RIGHT", card.arrow, "LEFT", -8, 0)
    card.count:SetTextColor(unpack(Theme.colors.textMuted))

    card.head:SetScript("OnEnter", function(self)
        self:GetParent().arrow:SetAlpha(1)
    end)
    card.head:SetScript("OnLeave", function(self)
        self:GetParent().arrow:SetAlpha(0.6)
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

    tile = Panel.CreateBox(rail)
    tile:SetHeight(TILE_H)

    -- A band down the inside of the left edge in the reading's colour.
    tile.accent = tile:CreateTexture(nil, "ARTWORK")
    tile.accent:SetWidth(3)
    tile.accent:SetPoint("TOPLEFT", 6, -7)
    tile.accent:SetPoint("BOTTOMLEFT", 6, 7)

    tile.value = Theme.FontString(tile, "OVERLAY", "GameFontNormalLarge")
    tile.value:SetPoint("TOPLEFT", 18, -9)
    tile.value:SetPoint("TOPRIGHT", -10, -9)
    tile.value:SetJustifyH("LEFT")

    tile.label = Theme.FontString(tile, "OVERLAY", "GameFontHighlightSmall")
    tile.label:SetPoint("BOTTOMLEFT", 18, 10)
    tile.label:SetPoint("BOTTOMRIGHT", -10, 10)
    tile.label:SetJustifyH("LEFT")
    tile.label:SetWordWrap(false)
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
        y = y + TILE_H + TILE_GAP
    end
end

---------------------------------------------------------------------------
-- The header box
--
-- Whose codex it is, and which page this is, in words. The portrait in
-- the frame's corner is the character too, so the box need not repeat
-- it; it carries the name, because a picture is not a name.
---------------------------------------------------------------------------

local function UpdateHero()
    if not hero then return end

    local tab = addon:GetSetting("activeTab") or "today"
    hero.section:SetText(Codex.tabLabels and Codex.tabLabels[tab] or "")

    local name = UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName()
    Theme.SetText(hero.name, realm and (name .. " - " .. realm) or name)

    local class, classFile = UnitClass("player")
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then
        hero.name:SetTextColor(c.r, c.g, c.b)
    else
        hero.name:SetTextColor(unpack(Theme.colors.gold))
    end

    local parts = { string.format("Level %d  |  %s", UnitLevel("player") or 1, class or "") }
    local zone = GetRealZoneText and GetRealZoneText()
    if zone and zone ~= "" then parts[#parts + 1] = zone end
    parts[#parts + 1] = BazUI:FormatMoney(GetMoney and GetMoney() or 0)
    hero.sub:SetText(table.concat(parts, "  |  "))

    -- The frame's own portrait wears the character. A masked texture is
    -- fussy about what may be done to it, and a failure here must not
    -- take the rest of the window down with it.
    if frame and frame.bazPortrait and SetPortraitTexture then
        pcall(SetPortraitTexture, frame.bazPortrait, "player")
    end
end

---------------------------------------------------------------------------
-- Drawing one tab
---------------------------------------------------------------------------

-- What a block's summary says, in words. A bar used to draw this; the
-- sentence is the same reading without the picture.
local function Summary(barDef)
    if not barDef then return nil end
    local reading = barDef.text
    if (not reading or reading == "") and barDef.max then
        reading = string.format("%s of %s", tostring(barDef.value or 0), tostring(barDef.max))
    end
    if barDef.label and reading then
        return barDef.label .. "  |  " .. reading
    end
    return barDef.label or reading
end

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

        local collapsed = Codex:IsCollapsed(def.id)
        BazUI.SetArrowTexture(card.arrow, collapsed and "RIGHT" or "DOWN", 16)

        local barDef = (not collapsed) and def.GetBar and def.GetBar() or nil
        local summary = Summary(barDef)
        card.summary:SetText(summary or "")
        if barDef and barDef.color then
            card.summary:SetTextColor(barDef.color[1], barDef.color[2], barDef.color[3])
        else
            card.summary:SetTextColor(unpack(Theme.colors.textSoft))
        end

        -- The plate, then the sentence under it if there is one.
        local headH = 2 + PLATE_H + (summary and 18 or 4)
        card.head:SetHeight(headH)

        if collapsed then
            card.count:SetText(def.collapsedHint or "")
            card:SetHeight(headH + 8)
        else
            local inner = headH + 8

            local rows = (def.GetRows and def.GetRows()) or {}
            if #rows == 0 then
                local row = AcquireRow(card)
                inner = inner + DrawRow(row, {
                    label = def.empty or "Nothing to show.",
                    muted = true,
                }, inner, 1)
                card.rows[#card.rows + 1] = row
            else
                for i, data in ipairs(rows) do
                    local row = AcquireRow(card)
                    inner = inner + DrawRow(row, data, inner, i)
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
    hero = Panel.CreateBox(parent)
    hero:SetHeight(HERO_H)

    hero.name = Theme.FontString(hero, "OVERLAY", "GameFontNormalLarge")
    hero.name:SetPoint("TOPLEFT", 16, -13)
    hero.name:SetJustifyH("LEFT")

    hero.sub = Theme.FontString(hero, "OVERLAY", "GameFontHighlightSmall")
    hero.sub:SetPoint("TOPLEFT", hero.name, "BOTTOMLEFT", 0, -6)
    hero.sub:SetJustifyH("LEFT")
    hero.sub:SetTextColor(unpack(Theme.colors.textSoft))

    hero.section = Theme.FontString(hero, "OVERLAY", "GameFontNormalLarge")
    hero.section:SetPoint("RIGHT", -16, 0)
    hero.section:SetJustifyH("RIGHT")
    hero.section:SetTextColor(unpack(Theme.colors.gold))

    return hero
end

local function Build()
    if frame then return frame end

    frame = BazUI:CreatePortraitWindow("BazUICodexFrame", {
        title          = "Codex",
        textured       = true,
        width          = WIDTH,
        height         = HEIGHT,
        strata         = "HIGH",
        savedAddon     = addon,
        savedKey       = "position",
        uiSpecialFrame = true,
        dragTitleOnly  = true,
        portraitOnClick = function()
            if ToggleCharacter then ToggleCharacter("PaperDollFrame") end
        end,
        portraitTooltip = { title = "Open the character sheet", anchor = "ANCHOR_RIGHT" },
    })
    frame.bazPortrait = (frame.PortraitContainer and frame.PortraitContainer.portrait)
        or frame.portrait or (frame.GetPortrait and frame:GetPortrait())
    Codex.frame = frame

    -- The version, small, in the title bar where the eye does not rest.
    local version = Theme.FontString(frame, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("TOPRIGHT", -36, -8)
    version:SetText(BazUI.VERSION or "")
    version:SetTextColor(unpack(Theme.colors.textMuted))

    -- The leather the pages are laid on; marble where a client lacks it.
    inset = Theme.CreateInset(frame, { tint = 0.7, ground = "collections" })
    inset:SetPoint("TOPLEFT", EDGE_L, -TOP)
    inset:SetPoint("BOTTOMRIGHT", -EDGE_R, EDGE_B)
    frame.inset = inset

    BuildHero(inset)
    hero:SetPoint("TOPLEFT", INNER, -INNER)
    hero:SetPoint("TOPRIGHT", -INNER, -INNER)

    -- The pages, down the right edge, the way the character sheet
    -- carries its own.
    local tabs = BazUI.CreateSideTabs(nil, frame)
    tabs:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, TABS_Y)
    frame.sideTabs = tabs
    Codex.tabKeys = {}
    Codex.tabLabels = {}

    rail = CreateFrame("Frame", nil, inset)
    rail:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -GAP)
    rail:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", INNER, INNER)
    rail:SetWidth(RAIL_W)

    rail.empty = Theme.FontString(rail, "OVERLAY", "GameFontHighlightSmall")
    rail.empty:SetPoint("TOPLEFT", 4, -4)
    rail.empty:SetPoint("TOPRIGHT", -4, -4)
    rail.empty:SetJustifyH("LEFT")
    rail.empty:SetText("Nothing to count on this page.")
    rail.empty:SetTextColor(unpack(Theme.colors.textMuted))
    rail.empty:Hide()

    -- A page that takes typing puts its box and its filters up here,
    -- outside the scroll, so they stay put while the list moves.
    headerHost = CreateFrame("Frame", nil, inset)
    headerHost:SetPoint("TOPLEFT", rail, "TOPRIGHT", GAP, 0)
    headerHost:SetPoint("RIGHT", inset, "RIGHT", -(INNER + SCROLLBAR_W), 0)
    headerHost:SetHeight(1)

    scroll = CreateFrame("ScrollFrame", nil, inset)
    scroll:SetPoint("TOPLEFT", headerHost, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -(INNER + SCROLLBAR_W), INNER)
    scroll:EnableMouseWheel(true)

    local bar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
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
    local tabs = frame.sideTabs
    tabs:ClearTabs()
    Codex.tabKeys = {}
    Codex.tabLabels = {}

    local seen, order = {}, {}
    local function Want(key, label, sort, icon)
        if seen[key] then return end
        seen[key] = true
        order[#order + 1] = {
            key = key, label = label, sort = sort or 100,
            icon = icon or TAB_ICONS[key] or TAB_ICON_DEFAULT,
        }
    end
    -- The two questions the codex exists to answer come first, always,
    -- even before anything has registered against them.
    Want("today",    "Today",    10)
    Want("achieved", "Achieved", 20)
    for _, def in pairs(Codex.sections) do
        Want(def.tab, def.tabLabel or def.tab:gsub("^%l", string.upper), def.tabOrder, def.tabIcon)
    end
    for key, def in pairs(Codex.customTabs or {}) do
        Want(key, def.label or key, def.order, def.icon)
    end
    table.sort(order, function(a, b)
        if a.sort ~= b.sort then return a.sort < b.sort end
        return a.label < b.label
    end)

    local active = addon:GetSetting("activeTab") or "today"
    local activeID
    for _, entry in ipairs(order) do
        local id = tabs:AddTab(entry.label, entry.icon)
        Codex.tabKeys[id] = entry.key
        Codex.tabLabels[entry.key] = entry.label
        if entry.key == active then activeID = id end
    end
    tabs:SetTabSelectedCallback(function(tabID, isUserAction)
        local key = Codex.tabKeys[tabID]
        if not key then return end
        addon:SetSetting("activeTab", key)
        if isUserAction then Panel:Refresh() end
    end)
    tabs:Layout()
    if activeID then
        tabs:SetTabVisuallySelected(activeID)
        tabs.selectedTabID = activeID
    end
end

function Panel:ApplySettings()
    if not frame then return end
    frame:SetScale(addon:GetSetting("scale") or 1)

    -- Opacity thins the ground, not the border or the words: the rock
    -- behind everything and the leather the pages sit on.
    local opacity = addon:GetSetting("opacity") or 0.95
    if frame.Bg and frame.Bg.SetAlpha then frame.Bg:SetAlpha(opacity) end
    if inset then Theme.SetInsetAlpha(inset, opacity) end

    frame:ClearAllPoints()
    local pos = addon:GetSetting("position")
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint(HOME_POINT, UIParent, HOME_POINT, 0, HOME_Y)
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
    -- The header box and the portrait are about the player, so they
    -- follow the player.
    for _, event in ipairs({ "PLAYER_MONEY", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA",
                             "PORTRAITS_UPDATED" }) do
        addon:On(event, function() Panel:QueueRefresh() end)
    end
    addon:OnProfileChanged(function()
        Panel:RebuildTabs()
        Panel:QueueRefresh()
    end)
end
