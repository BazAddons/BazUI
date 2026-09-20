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
--              headline number in the strip is one.
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
local GAP           = 12
local COLUMNS       = 2
local TABS_Y        = -30  -- where the character sheet hangs its tabs

local ROW_H         = 26   -- the character sheet's stat line, near enough
local ROW_BAR_W     = 180  -- the bar column, where a row asks for one
local ROW_DETAIL_W  = 170  -- the reading beside it
local PLATE_W       = 197  -- the heading plate's own size
local PLATE_H       = 40
local CARD_PAD      = 10
local CARD_GAP      = 12
-- How much of the page a column may be short by and still stretch its
-- last block to the foot. Beyond this the page is simply not full, and
-- stretching would make a hollow box rather than a tidy one.
local SLACK_SHARE   = 0.28
local TILE_H        = 58
local TILE_GAP      = 8

local frame, inset, scroll, content, hero, headerHost
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

-- The tab pictures.
--
-- The codex has art of its own: one painting per page, named for the
-- page, under Textures/Codex. Asked for by name rather than listed, so
-- a new page's picture is a file dropped in beside the others - see
-- tools/gen-codex-icons.py, which brings them in from the source art
-- at the size a tab draws them.
--
-- Checked rather than assumed, so a page added before its painting
-- exists still draws something: what the page asked for, then
-- Blizzard's own, then the book.
local TAB_ART = "Interface\\AddOns\\BazUI\\Textures\\Codex\\"
local TAB_ICON_DEFAULT = "Interface\\Icons\\INV_Misc_Book_09"

local TAB_FALLBACK = {
    today      = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    progress   = "Interface\\Icons\\Achievement_General",
    reputation = "Interface\\Icons\\Achievement_Reputation_01",
    items      = "Interface\\Icons\\inv_misc_bag_08",
    wishlist   = "Interface\\Icons\\INV_Misc_Note_01",
}

local function TabIcon(key, named)
    local own = TAB_ART .. key:gsub("^%l", string.upper) .. ".png"
    if BazUI.Has.Texture(own) then return own end
    return named or TAB_FALLBACK[key] or TAB_ICON_DEFAULT
end

-- The arrow that says there is more below, and the wheel that gets you
-- there. Any scroll frame in the codex asks for these rather than
-- growing its own: the page, a card whose list outruns it, the stats
-- column on the equipment page.
--
-- hintParent is where the arrow hangs, for a scroll frame whose own
-- bottom edge is not where the eye looks for it.
function Panel.MakeScrollable(f, hintParent, step)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        local most = math.max(0, (self.bazContentH or 0) - (self:GetHeight() or 0))
        local to = math.max(0, math.min(most, (self:GetVerticalScroll() or 0) - delta * (step or 48)))
        self:SetVerticalScroll(to)
        Panel.UpdateScrollHint(self)
    end)
    f.hint = (hintParent or f):CreateTexture(nil, "OVERLAY")
    f.hint:SetPoint("BOTTOM", hintParent or f, "BOTTOM", 0, 4)
    BazUI.SetArrowTexture(f.hint, "DOWN", 20)
    f.hint:SetAlpha(0.45)
    f.hint:Hide()
    return f
end

-- Show the arrow while there is more below the fold, and keep the view
-- honest when the content shrinks under a scroll that has run past its
-- end. Called with nothing, it means the page.
function Panel.UpdateScrollHint(f)
    f = f or scroll
    if not (f and f.hint) then return end
    local most = math.max(0, (f.bazContentH or 0) - (f:GetHeight() or 0))
    if (f:GetVerticalScroll() or 0) > most then
        f:SetVerticalScroll(most)
    end
    f.hint:SetShown(most > 1 and (f:GetVerticalScroll() or 0) < most - 1)
end

local function ContentWidth()
    -- The scroll frame knows better than arithmetic does, once it has
    -- been laid out; before that, the arithmetic.
    local w = scroll and scroll:GetWidth()
    if w and w > 50 then return math.floor(w) end
    return WIDTH - EDGE_L - EDGE_R - INNER * 2
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
local CreatePlate
function Panel.CreatePlate(parent) return CreatePlate(parent) end
-- The plate, in three pieces.
--
-- A heading may be longer than the character sheet's plate was drawn
-- for, so the plate has to be able to grow. Stretching the whole
-- picture grows the carved scrolls at each end along with it, which
-- both looks wrong and eats the room the words need. So the ends are
-- drawn at their own size and only the middle is stretched, which is
-- how every piece of chrome in this game is built.
local PLATE_CAP  = 24   -- how much of each end is the carved scroll
local PLATE_TEXT = 22   -- and how far the words stay clear of it

CreatePlate = function(parent)
    local plate = CreateFrame("Frame", nil, parent)
    plate:SetSize(PLATE_W, PLATE_H)

    local info = HasAtlas(PLATE_ATLAS) and C_Texture.GetAtlasInfo(PLATE_ATLAS) or nil
    if info then
        local l, r = info.leftTexCoord, info.rightTexCoord
        local t, b = info.topTexCoord, info.bottomTexCoord
        local span = r - l
        local cap  = span * (PLATE_CAP / math.max(info.width, 1))

        local function Piece(x1, x2)
            local tex = plate:CreateTexture(nil, "ARTWORK")
            tex:SetTexture(info.file)
            tex:SetTexCoord(x1, x2, t, b)
            return tex
        end

        plate.artLeft = Piece(l, l + cap)
        plate.artLeft:SetWidth(PLATE_CAP)
        plate.artLeft:SetPoint("TOPLEFT")
        plate.artLeft:SetPoint("BOTTOMLEFT")

        plate.artRight = Piece(r - cap, r)
        plate.artRight:SetWidth(PLATE_CAP)
        plate.artRight:SetPoint("TOPRIGHT")
        plate.artRight:SetPoint("BOTTOMRIGHT")

        plate.artMid = Piece(l + cap, r - cap)
        plate.artMid:SetPoint("TOPLEFT", plate.artLeft, "TOPRIGHT")
        plate.artMid:SetPoint("BOTTOMRIGHT", plate.artRight, "BOTTOMLEFT")
    end

    plate.title = Theme.FontString(plate, "OVERLAY", "GameFontNormal")
    plate.title:SetPoint("CENTER", 0, 1)
    plate.title:SetWordWrap(false)
    plate.title:SetTextColor(unpack(Theme.colors.gold))
    return plate
end

-- The character sheet's own size until a heading needs more, and then
-- as much as it is given. A name cut to "Stranglethorn Fishing Ex..."
-- is a name nobody can read.
function Panel.FitPlate(plate, text, maxWidth)
    local room = PLATE_CAP * 2 + PLATE_TEXT * 2
    plate.title:SetWidth(0)
    Theme.SetText(plate.title, text or "")
    local wanted = (plate.title:GetStringWidth() or 0) + room
    local width = math.max(PLATE_W, math.min(maxWidth or PLATE_W, wanted))
    plate:SetWidth(width)
    plate.title:SetWidth(width - room)
end

---------------------------------------------------------------------------
-- The skill bar
--
-- The profession book's own rank bar: a stone trough, a fill in the
-- profession's colours, a carved frame, the reading lettered across it.
-- Blizzard animates the fill as a flipbook; here it is the first frame,
-- still. Built from the same atlases so it is the same bar, and hidden
-- where a client has not got them.
---------------------------------------------------------------------------

local SKILLBAR_W, SKILLBAR_H = 453, 18
local SKILLBAR_FILL_FRAME_H  = 34   -- one frame of the flipbook sheet

function Panel.CreateSkillBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(SKILLBAR_W, SKILLBAR_H)

    bar.bg = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.bg:SetPoint("TOPLEFT")
    BazUI.SetAtlasOrTexture(bar.bg, "Professions-skillbar-bg", nil, true)

    bar.fill = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.fill:SetSize(SKILLBAR_W - 12, SKILLBAR_H)
    bar.fill:SetPoint("TOPLEFT", 5, -3)

    bar.mask = bar:CreateMaskTexture()
    bar.mask:SetPoint("LEFT", bar.fill, "LEFT", 1, 0)
    if HasAtlas("Professions-skillbar-mask") then
        bar.mask:SetAtlas("Professions-skillbar-mask", true)
    else
        bar.mask:SetTexture("Interface\\Buttons\\WHITE8x8")
        bar.mask:SetHeight(SKILLBAR_H)
    end
    bar.fill:AddMaskTexture(bar.mask)

    bar.border = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    bar.border:SetPoint("TOPLEFT")
    BazUI.SetAtlasOrTexture(bar.border, "Professions-skillbar-frame", nil, true)

    bar.text = bar:CreateFontString(nil, "OVERLAY", "Number12FontOutline")
    bar.text:SetPoint("CENTER", 0, -3)

    bar.usable = HasAtlas("Professions-skillbar-bg") and HasAtlas("Professions-skillbar-frame")
    return bar
end

-- kit is the profession's art name (Alchemy, FirstAid, ...); the fill
-- falls back to the plain blue where there is no art for it.
function Panel.SetSkillBar(bar, kit, value, max, text)
    local name = kit and ("Skillbar_Fill_Flipbook_" .. kit)
    if not (name and HasAtlas(name)) then name = "Skillbar_Fill_Flipbook_DefaultBlue" end
    local info = C_Texture.GetAtlasInfo(name)
    if info then
        bar.fill:SetAtlas(name, false)
        -- One frame of the sheet: two columns across, height/34 rows down.
        local rows = math.max(1, math.floor(info.height / SKILLBAR_FILL_FRAME_H + 0.5))
        local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        bar.fill:SetTexCoord(l, l + (r - l) / 2, t, t + (b - t) / rows)
    end
    local progress = (max and max > 0) and math.min(1, math.max(0, (value or 0) / max)) or 0
    bar.mask:SetWidth(math.max(1, bar:GetWidth() * progress))
    bar.text:SetText(text or "")
end

-- A tooltip written as lines. The first is the title; the rest wrap,
-- because SetText alone never does and a list of twenty bosses came out
-- as one line across the whole screen.
-- A line of "  " on its own is a gap; a line of "key\tvalue" is a pair,
-- set out left and right the way the game sets out an item's stats.
function Panel.SetTooltipText(tooltip, text)
    local first = true
    -- Split on the literal "|n" only; a colour code has a bar in it too.
    for line in (tostring(text or "") .. "|n"):gmatch("(.-)|n") do
        if line == "" then
            -- A blank line between sections, which is the whole point of
            -- there being sections.
            if not first then tooltip:AddLine(" ") end
        elseif first then
            tooltip:SetText(line, unpack(Theme.colors.text))
            first = false
        else
            local left, right = line:match("^(.-)\t(.*)$")
            if left then
                tooltip:AddDoubleLine(left, right, 0.75, 0.72, 0.62, 1, 1, 1)
            else
                tooltip:AddLine(line, 0.9, 0.9, 0.9, true)
            end
        end
    end
    if first then tooltip:SetText(tostring(text or "")) end
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
    row.detail:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        if not (self._tip or self._link) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self._link then
            GameTooltip:SetHyperlink(self._link)
        else
            Panel.SetTooltipText(GameTooltip, self._tip)
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

    -- A row that asks for a bar gets one in a column of its own, the
    -- reading beside it, so a list of them lines up like a table. Made
    -- on the first row that asks, since most never will.
    local wantsBar = data.progress and data.progress.bar and data.progress.max
    if wantsBar and not row.bar then
        row.bar = Theme.CreateStatBar(row, { height = 10 })
    end

    row.label:ClearAllPoints()
    row.detail:ClearAllPoints()
    row.label:SetPoint("LEFT", hasIcon and 36 or 11, 0)
    if wantsBar then
        row.detail:SetPoint("RIGHT", -10, 0)
        row.detail:SetWidth(ROW_DETAIL_W)
        row.bar:ClearAllPoints()
        row.bar:SetPoint("RIGHT", row.detail, "LEFT", -10, 0)
        row.bar:SetWidth(ROW_BAR_W)
        row.bar:SetBarColor(data.progress.color or c or Theme.colors.gold)
        row.bar:SetValues(data.progress.value or 0, data.progress.max)
        row.bar:Show()
        row.label:SetPoint("RIGHT", row.bar, "LEFT", -10, 0)
    else
        if row.bar then row.bar:Hide() end
        row.detail:SetWidth(0)
        row.detail:SetPoint("RIGHT", -10, 0)
        row.label:SetPoint("RIGHT", row.detail, "LEFT", -10, 0)
    end

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

-- A picture behind a card: the profession book's faded workshop, say.
-- Drawn at its own size against the right edge and clipped to the
-- card, because stretching an illustration to a card's width is how
-- you get a wide cauldron.
local function CardArt(card)
    if card.artFrame then return card.artFrame end
    local clip = CreateFrame("Frame", nil, card)
    clip:SetPoint("TOPLEFT", 4, -4)
    clip:SetPoint("BOTTOMRIGHT", -4, 4)
    clip:SetFrameLevel(card:GetFrameLevel() + 1)
    clip:SetClipsChildren(true)
    local inner = CreateFrame("Frame", nil, clip)
    inner:SetAllPoints()
    clip.tex = inner:CreateTexture(nil, "BACKGROUND")
    clip.tex:SetPoint("RIGHT", 0, 0)
    card.artFrame = clip
    return clip
end

-- A framed icon on the heading's left, in the profession book's own
-- square frame where the client has it.
local function CardIcon(card)
    if card.iconTex then return card.iconTex end
    card.iconTex = card.head:CreateTexture(nil, "ARTWORK")
    card.iconTex:SetSize(40, 40)
    card.iconTex:SetPoint("TOPLEFT", CARD_PAD, -4)
    card.iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    card.iconRing = card.head:CreateTexture(nil, "OVERLAY")
    card.iconRing:SetPoint("CENTER", card.iconTex, "CENTER")
    if HasAtlas("Profession-square-frame") then
        card.iconRing:SetAtlas("Profession-square-frame", true)
    else
        card.iconRing:Hide()
    end
    return card.iconTex
end

-- A block long enough to run past the foot of the page keeps its list
-- inside itself and scrolls there, rather than pushing the page down
-- and taking the block beside it out of sight with it. Made on the
-- first card that needs one.
local CARD_SCROLL_MIN = 150   -- below this there is no room worth scrolling

local function CardScroll(card)
    if card.scroll then return card.scroll end
    local f = CreateFrame("ScrollFrame", nil, card)
    local body = CreateFrame("Frame", nil, f)
    body:SetSize(1, 1)
    f:SetScrollChild(body)
    f.body = body
    Panel.MakeScrollable(f, nil, ROW_H * 2)
    card.scroll = f
    return f
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
-- The strip
--
-- One tile per block that can put a single number on itself, in a row
-- across the top of the page. This is the part you read from across
-- the room. A page with nothing to count has no strip.
---------------------------------------------------------------------------

local function AcquireTile()
    local tile = table.remove(tilePool)
    if tile then
        tile:SetParent(content)
        return tile
    end

    tile = Panel.CreateBox(content)
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

-- Returns the height the strip took, so the blocks start below it.
local function DrawStrip(tab, width)
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

    if #highlights == 0 then return 0 end

    -- The strip fills the page, however many tiles there are: the last
    -- one ends where the page ends. Pixels left over by the division go
    -- to the last tile rather than leaving a gap.
    local n = #highlights
    local tileW = math.floor((width - TILE_GAP * (n - 1)) / n)
    local x = 0
    for i, h in ipairs(highlights) do
        local tile = AcquireTile()
        local w = (i == n) and (width - x) or tileW
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", x, 0)
        tile:SetSize(w, TILE_H)
        tile.value:SetText(tostring(h.value))
        tile.value:SetTextColor(unpack(h.color or Theme.colors.gold))
        tile.accent:SetColorTexture(unpack(h.color or Theme.colors.goldDim))
        tile.label:SetText(h.label or "")
        tile:Show()
        liveTiles[#liveTiles + 1] = tile
        x = x + w + TILE_GAP
    end
    return TILE_H + CARD_GAP
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
        -- Render is what sets height, so it is read after.
        custom.Render(content, width)
        local used = math.max(custom.height or 1, 1)
        content:SetHeight(used)
        scroll.bazContentH = used
        Panel.UpdateScrollHint()
        return
    end

    local top = DrawStrip(tab, width)
    local viewport = scroll:GetHeight() or 0

    -- Two columns; each block goes to whichever is shorter.
    local colW = math.floor((width - CARD_GAP * (COLUMNS - 1)) / COLUMNS)
    local colY, colLast = {}, {}
    for c = 1, COLUMNS do colY[c] = top end

    for _, def in ipairs(Codex:GetSections(tab)) do
        -- A block that named its column goes there; the rest fall into
        -- whichever column is shorter.
        local col = def.column
        if not (col and col >= 1 and col <= COLUMNS) then
            col = 1
            for c = 2, COLUMNS do
                if colY[c] < colY[col] then col = c end
            end
        end
        local y = colY[col]

        local card = AcquireCard()
        card._sectionID = def.id
        card._x = (col - 1) * (colW + CARD_GAP)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", card._x, -y)
        card:SetWidth(colW)
        Panel.FitPlate(card.plate, def.title or def.id, colW - CARD_PAD * 4)

        local collapsed = Codex:IsCollapsed(def.id)
        BazUI.SetArrowTexture(card.arrow, collapsed and "RIGHT" or "DOWN", 16)

        local barDef = (not collapsed) and def.GetBar and def.GetBar() or nil
        local rows = (not collapsed) and ((def.GetRows and def.GetRows()) or {}) or {}

        -- A block may ask for the profession book's bar instead of a
        -- sentence; it gets the sentence where the client lacks the art.
        local skinned = barDef and barDef.kit ~= nil
        if skinned then
            card.skill = card.skill or Panel.CreateSkillBar(card.head)
            if card.skill.usable then
                Panel.SetSkillBar(card.skill, barDef.kit, barDef.value, barDef.max, barDef.text)
                card.skill:ClearAllPoints()
                card.skill:SetPoint("TOP", card.plate, "BOTTOM", 0, -6)
                card.skill:Show()
            else
                skinned = false
            end
        end
        if card.skill and not skinned then card.skill:Hide() end

        -- A summary over one row says what the row says. "1 at cap"
        -- above "Language: Common  300 / 300" is the same reading
        -- twice, and the line it costs is a line the page has to find
        -- somewhere - which is how a page ends up scrolling by an inch.
        local summary = (not skinned) and #rows > 1 and Summary(barDef) or nil
        card.summary:SetText(summary or "")
        if barDef and barDef.color then
            card.summary:SetTextColor(barDef.color[1], barDef.color[2], barDef.color[3])
        else
            card.summary:SetTextColor(unpack(Theme.colors.textSoft))
        end

        -- The picture behind, if the block brought one the client has.
        -- Either an atlas or a texture path; a path is drawn to the
        -- card's own height rather than the atlas's natural size,
        -- because a banner has no size of its own to keep.
        local function Usable(name)
            if type(name) ~= "string" then return nil end
            if name:find("\\") then
                return BazUI.Has.Texture(name) and "file" or nil
            end
            return HasAtlas(name) and "atlas" or nil
        end
        local artName, artKind = def.art, Usable(def.art)
        if not artKind and def.artFallback then
            artName, artKind = def.artFallback, Usable(def.artFallback)
        end
        if artKind then
            local art = CardArt(card)
            art.tex:ClearAllPoints()
            if artKind == "atlas" then
                art.tex:SetTexCoord(0, 1, 0, 1)
                art.tex:SetAtlas(artName, true)
                art.tex:SetPoint("RIGHT", 0, 0)
            elseif def.artSquare then
                -- An icon is square and small; blown up to the card's
                -- height against the right edge it reads as a mark on
                -- the page rather than a stretched photograph. Sized
                -- below, once the card's own height is settled - a
                -- pooled card is still whatever height it was last
                -- time until then.
                art.tex:SetTexture(artName)
                art.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                art.tex:ClearAllPoints()
                art.tex:SetPoint("RIGHT", -6, 0)
                card._artSquare = true
            else
                art.tex:SetTexture(artName)
                art.tex:SetTexCoord(0, 1, 0, 1)
                art.tex:SetPoint("TOPLEFT")
                art.tex:SetPoint("BOTTOMRIGHT")
            end
            art.tex:SetAlpha(def.artAlpha or 1)
            art:Show()
        elseif card.artFrame then
            card.artFrame:Hide()
        end

        -- And the icon on the left, if it brought one.
        if def.icon then
            local icon = CardIcon(card)
            icon:SetTexture(def.icon)
            icon:Show()
            if card.iconRing then card.iconRing:SetShown(HasAtlas("Profession-square-frame")) end
        elseif card.iconTex then
            card.iconTex:Hide()
            if card.iconRing then card.iconRing:Hide() end
        end

        -- The plate, then what sits under it: the bar, the sentence, or
        -- nothing.
        local headH = 2 + PLATE_H + (skinned and (SKILLBAR_H + 18) or (summary and 18 or 4))
        card.head:SetHeight(headH)

        -- And a paragraph beneath the head, where the block brought one.
        local blurb = (not collapsed) and def.blurb or nil
        if blurb then
            if not card.blurb then
                card.blurb = Theme.FontString(card, "OVERLAY", "GameFontHighlightSmall")
                card.blurb:SetJustifyH("LEFT")
                card.blurb:SetJustifyV("TOP")
                card.blurb:SetWordWrap(true)
                card.blurb:SetTextColor(unpack(Theme.colors.textSoft))
            end
            card.blurb:ClearAllPoints()
            card.blurb:SetPoint("TOPLEFT", CARD_PAD + 2, -(headH + 8))
            card.blurb:SetPoint("TOPRIGHT", -(CARD_PAD + 2), -(headH + 8))
            Theme.SetText(card.blurb, blurb)
            card.blurb:Show()
            headH = headH + 8 + math.ceil((card.blurb:GetStringHeight() or 12) + 2)
        elseif card.blurb then
            card.blurb:Hide()
        end

        if collapsed then
            card.count:SetText((not def.hideCount) and (def.collapsedHint or "") or "")
            card:SetHeight(headH + 8)
        else
            local inner = headH + 8
            local shown = #rows > 0 and rows or nil

            -- Would the whole block fit between here and the foot of the
            -- page? If not, and there is room worth scrolling in, the
            -- list goes inside the card and scrolls there.
            local listH = ((shown and #shown or 1) * ROW_H) + CARD_PAD
            local room  = math.floor(math.max(0, viewport - y) - inner - CARD_PAD)
            local owns  = (listH > room) and (room >= CARD_SCROLL_MIN)

            local body, bodyY = card, inner
            if owns then
                local sf = CardScroll(card)
                sf:ClearAllPoints()
                sf:SetPoint("TOPLEFT", 0, -inner)
                sf:SetPoint("TOPRIGHT", 0, -inner)
                sf:SetHeight(room)
                sf.body:SetSize(colW, listH)
                sf.bazContentH = listH
                sf:Show()
                body, bodyY = sf.body, 0
            elseif card.scroll then
                card.scroll:Hide()
            end

            local used = bodyY
            if not shown and def.rowless then
                used = used - 4
            elseif not shown then
                local row = AcquireRow(body)
                used = used + DrawRow(row, {
                    label = def.empty or "Nothing to show.",
                    muted = true,
                }, used, 1)
                card.rows[#card.rows + 1] = row
            else
                for i, data in ipairs(shown) do
                    local row = AcquireRow(body)
                    used = used + DrawRow(row, data, used, i)
                    card.rows[#card.rows + 1] = row
                end
            end

            card.count:SetText((not def.hideCount) and #rows > 0 and tostring(#rows) or "")
            if owns then
                card:SetHeight(inner + room + CARD_PAD)
                Panel.UpdateScrollHint(card.scroll)
            else
                card:SetHeight(used + CARD_PAD)
            end
        end

        -- Now that the card knows how tall it is, the square mark can
        -- take its height.
        if card._artSquare and card.artFrame then
            local side = math.max((card:GetHeight() or 0) - 8, 48)
            card.artFrame.tex:SetSize(side, side)
            card._artSquare = nil
        end

        card:Show()
        liveCards[#liveCards + 1] = card
        colLast[col] = card
        colY[col] = y + card:GetHeight() + CARD_GAP
    end

    -- Each column's height carries the gap it would put under a next
    -- card; the page does not need it, and counting it made the page
    -- scroll by exactly that much.
    local tallest = 1
    for c = 1, COLUMNS do tallest = math.max(tallest, colY[c] - CARD_GAP) end
    tallest = math.max(tallest, 1)

    -- A column that stops a little short of the foot of the page has
    -- its last block take up the slack, so the two columns end level
    -- with each other and with the window. Only a little short: a page
    -- that is half empty would rather have two ordinary blocks than
    -- two tall hollow ones.
    --
    -- The block is anchored to the foot rather than given a computed
    -- height. A height has to come out exact against a viewport nobody
    -- measured in whole pixels, and when it did not, the block simply
    -- stayed where it was; an anchor cannot miss.
    if tallest <= viewport + 1 then
        tallest = viewport
        content:SetHeight(viewport)
        local slack = viewport * SLACK_SHARE
        for c = 1, COLUMNS do
            local card = colLast[c]
            local gap = viewport - (colY[c] - CARD_GAP)
            if card and gap > 1 and gap <= slack then
                card:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", card._x, 0)
                if card.scroll and card.scroll:IsShown() then
                    card.scroll:SetHeight((card.scroll:GetHeight() or 0) + gap)
                    Panel.UpdateScrollHint(card.scroll)
                end
            end
        end
    end

    content:SetHeight(tallest)
    scroll.bazContentH = tallest
    Panel.UpdateScrollHint()
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

    -- The game's calendar has no home in this interface, so the codex
    -- gives it one: a button on the header, beside the page's name.
    local cal = CreateFrame("Button", nil, hero)
    cal:SetSize(26, 26)
    cal:SetPoint("RIGHT", hero.section, "LEFT", -14, 0)
    cal.icon = cal:CreateTexture(nil, "ARTWORK")
    cal.icon:SetAllPoints()
    -- The Events page's own painting is a calendar, which is what this
    -- button opens. It wore the pocket watch before, which is Today's.
    cal.icon:SetTexture(TabIcon("events"))
    cal.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    cal.icon:SetAlpha(0.7)
    cal:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Calendar", unpack(Theme.colors.text))
        GameTooltip:AddLine("Open the game's calendar.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    cal:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.7)
        GameTooltip:Hide()
    end)
    cal:SetScript("OnClick", function()
        if Codex.OpenCalendar then Codex.OpenCalendar() end
    end)
    cal:SetShown(_G.ToggleCalendar ~= nil)
    hero.calendar = cal

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
            BazUI.OpenCharacterSheet("PaperDollFrame")
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

    -- A page that takes typing puts its box and its filters up here,
    -- outside the scroll, so they stay put while the list moves.
    headerHost = CreateFrame("Frame", nil, inset)
    headerHost:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -GAP)
    headerHost:SetPoint("RIGHT", inset, "RIGHT", -INNER, 0)
    headerHost:SetHeight(1)

    -- No scroll bar. A bar has to be given room whether the page needs
    -- it or not, and a page that keeps its columns a bar's width short
    -- of the header above them looks like a mistake on every page that
    -- fits. The wheel scrolls, and the arrow below says when there is
    -- more.
    scroll = CreateFrame("ScrollFrame", nil, inset)
    scroll:SetPoint("TOPLEFT", headerHost, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -INNER, INNER)
    Panel.MakeScrollable(scroll, inset)

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
            icon = TabIcon(key, icon),
        }
    end
    -- The two questions the codex exists to answer come first, always,
    -- even before anything has registered against them.
    Want("today",    "Today",    10)
    Want("progress", "Progress", 20)
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
    local activeID, todayID
    for _, entry in ipairs(order) do
        local id = tabs:AddTab(entry.label, entry.icon)
        Codex.tabKeys[id] = entry.key
        Codex.tabLabels[entry.key] = entry.label
        if entry.key == active then activeID = id end
        if entry.key == "today" then todayID = id end
    end
    -- A remembered page that no longer exists (renamed, or its module
    -- off) falls back to Today rather than to a blank window.
    if not activeID and todayID then
        activeID = todayID
        addon:SetSetting("activeTab", "today")
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
