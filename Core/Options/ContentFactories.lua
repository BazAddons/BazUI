-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: Content Block Factories
--
-- Extends O.widgetFactories with rich content block types used by the
-- User Manual and any settings page that wants documentation-style
-- content. All blocks share the same factory contract:
--
--     factory(parent, opt, contentWidth) -> (frame, height)
--
-- Block types added here:
--   Text presets:  h1, h2, h3, h4, paragraph, lead, caption, quote
--   Lists:         list  (ordered/unordered, nestable, custom markers)
--   Layout:        collapsible, divider, spacer
--   Media:         image
--   Callouts:      note  (tip / info / warning)
--   Code:          code  (monospace box)
--   Tabular:       table (header row + data rows)
---------------------------------------------------------------------------

local O = BazUI._Options

---------------------------------------------------------------------------
-- Style constants for content blocks
---------------------------------------------------------------------------

O.NOTE_BG = {
    tip     = { 0.10, 0.30, 0.10, 0.55 },  -- soft green
    info    = { 0.10, 0.20, 0.35, 0.55 },  -- soft blue
    warning = { 0.40, 0.20, 0.05, 0.55 },  -- amber/orange
    danger  = { 0.40, 0.10, 0.10, 0.55 },  -- red
}
O.NOTE_BORDER = {
    tip     = { 0.40, 0.85, 0.40, 0.85 },
    info    = { 0.45, 0.65, 1.00, 0.85 },
    warning = { 1.00, 0.75, 0.20, 0.85 },
    danger  = { 1.00, 0.30, 0.30, 0.85 },
}
O.NOTE_LABEL = {
    tip     = "TIP",
    info    = "NOTE",
    warning = "WARNING",
    danger  = "DANGER",
}

O.CODE_BG     = { 0.04, 0.04, 0.06, 0.85 }
O.CODE_BORDER = { 0.20, 0.20, 0.25, 0.85 }
O.CODE_TEXT   = { 0.85, 1.00, 0.65 }      -- soft green-yellow

O.QUOTE_BAR     = { 1.00, 0.82, 0.00, 0.7 }
O.TABLE_HEADER_BG = { 0.10, 0.10, 0.14, 0.85 }
O.TABLE_ROW_ALT   = { 0.06, 0.06, 0.09, 0.45 }
O.DIVIDER_COLOR   = { 0.40, 0.35, 0.20, 0.6 }

---------------------------------------------------------------------------
-- Text preset registry
---------------------------------------------------------------------------

O.TEXT_PRESETS = {
    h1        = { font = "GameFontNormalLarge",     color = O.GOLD,     marginBot = 8,  accent = "underline" },
    h2        = { font = "GameFontHighlightMedium", color = O.GOLD,     marginBot = 4,  accent = "underline" },
    h3        = { font = "GameFontHighlight",       color = O.GOLD,     marginBot = 3 },
    h4        = { font = "GameFontHighlightSmall",  color = O.GOLD,     marginBot = 2 },
    paragraph = { font = "GameFontHighlight",       color = O.TEXT_NORMAL, marginBot = 4, wrap = true },
    lead      = { font = "GameFontHighlight",       color = O.WHITE,    marginBot = 6, wrap = true },
    caption   = { font = "GameFontHighlightSmall",  color = O.DIM,      marginBot = 4, wrap = true, justify = "CENTER" },
    quote     = { font = "GameFontHighlight",       color = O.DIM,      marginBot = 6, wrap = true, indent = 14, leftBar = true },
}

local function CreateTextWidget(presetName)
    return function(parent, opt, contentWidth)
        local preset = O.TEXT_PRESETS[presetName]
        local frame = CreateFrame("Frame", nil, parent)

        local indent = preset.indent or 0
        local fs = frame:CreateFontString(nil, "OVERLAY")
        fs:SetFontObject(preset.font)
        fs:SetPoint("TOPLEFT", indent, 0)
        fs:SetWidth(contentWidth - indent)
        fs:SetJustifyH(preset.justify or "LEFT")
        fs:SetText(opt.text or opt.name or "")
        fs:SetTextColor(unpack(preset.color))
        if preset.wrap then fs:SetWordWrap(true) end

        local textH = fs:GetStringHeight()
        local totalH = textH + (preset.marginBot or 0)

        -- Underline accent for h1/h2
        if preset.accent == "underline" then
            local line = frame:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
            line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -textH - 3)
            line:SetColorTexture(unpack(O.HEADER_LINE))
            totalH = totalH + 4
        end

        -- Left vertical bar accent (for quotes)
        if preset.leftBar then
            local bar = frame:CreateTexture(nil, "ARTWORK")
            bar:SetWidth(2)
            bar:SetPoint("TOPLEFT", 4, 0)
            bar:SetPoint("BOTTOMLEFT", 4, -textH)
            bar:SetColorTexture(unpack(O.QUOTE_BAR))
        end

        frame:SetSize(contentWidth, totalH)
        return frame, totalH
    end
end

---------------------------------------------------------------------------
-- List block (bulleted/numbered, nestable)
---------------------------------------------------------------------------

local DEFAULT_MARKERS = { "*", "-", ">" }

local function GetOrderedLabel(index, depth)
    -- depth 0: 1. 2. 3.    depth 1: a. b. c.    depth 2: i. ii. iii.
    if depth == 0 then
        return index .. "."
    elseif depth == 1 then
        local letter = string.char(string.byte("a") + ((index - 1) % 26))
        return letter .. "."
    else
        -- Crude roman numerals up to ~10
        local roman = { "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x" }
        return (roman[index] or tostring(index)) .. "."
    end
end

local function RenderListItems(parent, items, opts, depth, contentWidth, startY)
    depth = depth or 0
    local y = startY or 0
    local ordered = opts.ordered
    local marker = opts.marker
    local indentPerLevel = 18
    local indent = depth * indentPerLevel
    local markerWidth = 18
    local lineSpacing = 4

    for i, item in ipairs(items or {}) do
        local isNestedList = (type(item) == "table" and item.items)

        if isNestedList then
            -- Nested list: recurse with deeper depth
            local nestedOpts = {
                ordered = item.ordered ~= nil and item.ordered or ordered,
                marker  = item.marker  or marker,
            }
            y = RenderListItems(parent, item.items, nestedOpts, depth + 1, contentWidth, y)
        else
            local text = (type(item) == "table") and (item.text or "") or tostring(item)

            -- Marker label (text or atlas/texture)
            local markerStr
            if ordered then
                markerStr = GetOrderedLabel(i, depth)
            elseif type(marker) == "string" then
                markerStr = marker
            else
                markerStr = DEFAULT_MARKERS[(depth % #DEFAULT_MARKERS) + 1]
            end

            local row = CreateFrame("Frame", nil, parent)
            row:SetPoint("TOPLEFT", indent, y)
            row:SetWidth(contentWidth - indent)

            local markerFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            markerFs:SetPoint("TOPLEFT", 0, 0)
            markerFs:SetWidth(markerWidth)
            markerFs:SetJustifyH("LEFT")
            markerFs:SetText(markerStr)
            markerFs:SetTextColor(unpack(O.GOLD))

            local body = row:CreateFontString(nil, "OVERLAY")
            body:SetFontObject("GameFontHighlight")
            body:SetPoint("TOPLEFT", markerWidth + 4, 0)
            body:SetWidth(contentWidth - indent - markerWidth - 4)
            body:SetJustifyH("LEFT")
            body:SetText(text)
            body:SetTextColor(unpack(O.TEXT_NORMAL))
            body:SetWordWrap(true)

            local h = math.max(body:GetStringHeight(), markerFs:GetStringHeight())
            row:SetHeight(h)
            y = y - h - lineSpacing
        end
    end

    return y
end

local function CreateListWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    local endY = RenderListItems(frame, opt.items, opt, 0, contentWidth, 0)
    local h = math.abs(endY) + 2
    frame:SetSize(contentWidth, h)
    return frame, h
end

---------------------------------------------------------------------------
-- Image block
-- Supports: texture (file path), atlas (Blizzard atlas name), fileID (number)
---------------------------------------------------------------------------

local function CreateImageWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)

    local desiredW = opt.width or contentWidth
    if desiredW > contentWidth then desiredW = contentWidth end
    local desiredH = opt.height  -- may be nil

    local tex = frame:CreateTexture(nil, "ARTWORK")
    if opt.atlas then
        tex:SetAtlas(opt.atlas)
        if not desiredH then
            -- Atlas knows its own native size; query via GetAtlasInfo if available
            local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(opt.atlas)
            if info and info.width and info.height and info.width > 0 then
                desiredH = math.floor(desiredW * (info.height / info.width))
            else
                desiredH = math.floor(desiredW * 0.5)
            end
        end
    elseif opt.fileID then
        tex:SetTexture(opt.fileID)
        desiredH = desiredH or math.floor(desiredW * 0.5)
    elseif opt.texture then
        tex:SetTexture(opt.texture)
        desiredH = desiredH or math.floor(desiredW * 0.5)
    end

    tex:SetSize(desiredW, desiredH or 100)
    -- Alignment
    local align = opt.align or "center"
    if align == "left" then
        tex:SetPoint("TOPLEFT", 0, 0)
    elseif align == "right" then
        tex:SetPoint("TOPRIGHT", 0, 0)
    else
        tex:SetPoint("TOP", 0, 0)
    end

    local totalH = (desiredH or 100)

    if opt.caption and opt.caption ~= "" then
        local cap = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cap:SetPoint("TOP", tex, "BOTTOM", 0, -4)
        cap:SetWidth(contentWidth)
        cap:SetJustifyH("CENTER")
        cap:SetWordWrap(true)
        cap:SetText(opt.caption)
        cap:SetTextColor(unpack(O.DIM))
        -- Measure the UNWRAPPED string width via a separate hidden
        -- FontString with no width constraint. cap:GetStringWidth() on a
        -- wrapped FontString returns the longest *wrapped* line, not the
        -- full string, so dividing by contentWidth always yields 1 line.
        local measure = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        measure:Hide()
        measure:SetText(opt.caption)
        local unwrappedW = measure:GetStringWidth() or 0
        measure:SetText("")
        local _, fontH = cap:GetFont()
        fontH = fontH or 12
        local numLines = math.max(1, math.ceil(unwrappedW / contentWidth))
        local capH = math.max(cap:GetStringHeight() or 0, numLines * fontH * 1.2)
        totalH = totalH + capH + 16
    end

    frame:SetSize(contentWidth, totalH)
    return frame, totalH
end

---------------------------------------------------------------------------
-- ImageRow block - image on one side, content blocks on the other
--
-- Reserves a fixed-width column for the image (with optional caption
-- underneath, same shape as the standalone image block) and renders
-- arbitrary content blocks alongside in the remaining width. Total
-- row height is whichever column is taller.
--
-- Use when:
--   * the image and a short paragraph / list / heading naturally
--     belong together visually
--   * you want to break up a wall of full-width screenshots with
--     a tighter shoulder-to-shoulder layout
--
-- Don't use when:
--   * the descriptive text is so long the image would feel orphaned
--     at the top - a centered full-width image + caption + body
--     reads better in that case
--   * the image deserves a "wow factor" full-width showing
--
-- Options:
--   texture | atlas | fileID  - image source (same precedence as
--                               the image block: atlas > fileID > texture)
--   imageWidth, imageHeight   - size of the image column. A value
--                               > 1 is treated as absolute pixels;
--                               a value between 0 and 1 is treated
--                               as a fraction of contentWidth (so
--                               imageWidth = 0.5 gives a half-width
--                               image column without the caller
--                               having to know the panel's pixel
--                               width). imageHeight defaults to 16:9
--                               of the resolved imageWidth.
--   imageSide                 - "left" (default) or "right"
--   caption                   - optional caption rendered below the
--                               image, sized to imageWidth
--   blocks                    - array of standard content blocks for
--                               the text column; rendered via the
--                               same RenderBlockList that drives
--                               regular page rendering, so anything
--                               nests freely (lists, notes, code,
--                               other images, even another imageRow)
---------------------------------------------------------------------------

local function CreateImageRowWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)

    -- Resolve imageWidth: < 1 means "fraction of contentWidth", >= 1
    -- means absolute pixels. Same rule for imageHeight (against the
    -- resolved imageWidth-based 16:9 fallback if imageHeight is nil).
    local imageW = opt.imageWidth or 280
    if imageW > 0 and imageW < 1 then imageW = math.floor(contentWidth * imageW) end
    local imageH = opt.imageHeight or math.floor(imageW * 9 / 16)
    if imageH > 0 and imageH < 1 then imageH = math.floor(imageW * imageH) end
    local gap = O.PAD or 16
    local textW = contentWidth - imageW - gap
    if textW < 100 then
        -- Pathological case: content area too narrow to host both
        -- columns at the requested image size. Shrink image to leave
        -- the text at least 100 px so the renderer doesn't choke.
        imageW = math.max(80, contentWidth - 100 - gap)
        imageH = math.floor(imageW * (opt.imageHeight and (opt.imageHeight / (opt.imageWidth or imageW)) or (9 / 16)))
        textW = contentWidth - imageW - gap
    end
    local imageSide = opt.imageSide or "left"

    -- Image column container (image + optional caption stacked)
    local imageFrame = CreateFrame("Frame", nil, frame)
    imageFrame:SetSize(imageW, imageH)

    local tex = imageFrame:CreateTexture(nil, "ARTWORK")
    -- Fixed size + TOPLEFT anchor so the texture holds its aspect
    -- ratio when imageFrame grows to fit the caption underneath.
    -- (SetAllPoints would stretch the texture vertically with the
    -- frame, squishing the image and dragging the caption anchor
    -- below the row's bounds.)
    tex:SetSize(imageW, imageH)
    tex:SetPoint("TOPLEFT", imageFrame, "TOPLEFT", 0, 0)
    if opt.atlas then
        tex:SetAtlas(opt.atlas)
    elseif opt.fileID then
        tex:SetTexture(opt.fileID)
    elseif opt.texture then
        tex:SetTexture(opt.texture)
    end

    local imageColH = imageH
    if opt.caption and opt.caption ~= "" then
        local cap = imageFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cap:SetPoint("TOP", tex, "BOTTOM", 0, -4)
        cap:SetWidth(imageW)
        cap:SetJustifyH("CENTER")
        cap:SetWordWrap(true)
        cap:SetText(opt.caption)
        cap:SetTextColor(unpack(O.DIM))
        -- Measure unwrapped string width via a hidden, unconstrained
        -- FontString (cap:GetStringWidth() on a wrapped FontString
        -- returns the longest wrapped line, not the full unwrapped text).
        local measure = imageFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        measure:Hide()
        measure:SetText(opt.caption)
        local unwrappedW = measure:GetStringWidth() or 0
        measure:SetText("")
        local _, fontH = cap:GetFont()
        fontH = fontH or 12
        local numLines = math.max(1, math.ceil(unwrappedW / imageW))
        local capH = math.max(cap:GetStringHeight() or 0, numLines * fontH * 1.2)
        imageColH = imageH + capH + 16
    end
    imageFrame:SetHeight(imageColH)

    -- Text column - render arbitrary content blocks via RenderBlockList
    local textFrame = CreateFrame("Frame", nil, frame)
    textFrame:SetWidth(textW)

    local textBottom = O.RenderBlockList(textFrame, opt.blocks, textW, 0) or 0
    local textColH = -textBottom
    if textColH < 0 then textColH = 0 end
    -- RenderBlockList tacks an O.SPACING after the last block; trim
    -- it so the row's bottom edge sits flush with the last block.
    if textColH > (O.SPACING or 0) then
        textColH = textColH - (O.SPACING or 0)
    end
    textFrame:SetHeight(textColH > 0 and textColH or 1)

    -- Position columns
    if imageSide == "right" then
        textFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        imageFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", textW + gap, 0)
    else
        imageFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        textFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", imageW + gap, 0)
    end

    local totalH = math.max(imageColH, textColH)
    if totalH < 1 then totalH = imageColH end
    frame:SetSize(contentWidth, totalH)
    return frame, totalH
end

---------------------------------------------------------------------------
-- Note (callout) block
---------------------------------------------------------------------------

local function CreateNoteWidget(parent, opt, contentWidth)
    local style = opt.style or "info"
    local bgColor = O.NOTE_BG[style] or O.NOTE_BG.info
    local borderColor = O.NOTE_BORDER[style] or O.NOTE_BORDER.info
    local label = opt.label or O.NOTE_LABEL[style] or "NOTE"

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetWidth(contentWidth)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(unpack(bgColor))
    frame:SetBackdropBorderColor(unpack(borderColor))

    -- Left accent strip in border color
    local strip = frame:CreateTexture(nil, "ARTWORK")
    strip:SetWidth(3)
    strip:SetPoint("TOPLEFT", 4, -4)
    strip:SetPoint("BOTTOMLEFT", 4, 4)
    strip:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], 1)

    -- Label (e.g. "TIP", "WARNING")
    local labelFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFs:SetPoint("TOPLEFT", 14, -8)
    labelFs:SetText(label)
    labelFs:SetTextColor(borderColor[1], borderColor[2], borderColor[3], 1)

    -- Body text
    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", labelFs, "BOTTOMLEFT", 0, -2)
    body:SetWidth(contentWidth - 22)
    body:SetJustifyH("LEFT")
    body:SetText(opt.text or "")
    body:SetTextColor(unpack(O.TEXT_NORMAL))
    body:SetWordWrap(true)

    local h = labelFs:GetStringHeight() + body:GetStringHeight() + 18
    frame:SetHeight(h)
    return frame, h
end

---------------------------------------------------------------------------
-- Code block
---------------------------------------------------------------------------

local function CreateCodeWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetWidth(contentWidth)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(unpack(O.CODE_BG))
    frame:SetBackdropBorderColor(unpack(O.CODE_BORDER))

    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 10, -8)
    fs:SetWidth(contentWidth - 20)
    fs:SetJustifyH("LEFT")
    fs:SetText(opt.text or "")
    fs:SetTextColor(unpack(O.CODE_TEXT))
    fs:SetWordWrap(true)

    local h = fs:GetStringHeight() + 16
    frame:SetHeight(h)
    return frame, h
end

---------------------------------------------------------------------------
-- Divider block
---------------------------------------------------------------------------

local function CreateDividerWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    local h = (opt.height or 1) + 8
    frame:SetSize(contentWidth, h)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetHeight(opt.height or 1)
    line:SetPoint("LEFT", 0, 0)
    line:SetPoint("RIGHT", 0, 0)
    line:SetColorTexture(unpack(opt.color or O.DIVIDER_COLOR))
    return frame, h
end

---------------------------------------------------------------------------
-- Spacer block
---------------------------------------------------------------------------

local function CreateSpacerWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    local h = opt.height or 12
    frame:SetSize(contentWidth, h)
    return frame, h
end

---------------------------------------------------------------------------
-- Table block
---------------------------------------------------------------------------

-- Cells wrap, and each row is as tall as its tallest cell, so long
-- descriptions read in full instead of being cut off with an ellipsis.
-- Column widths: opt.columnWidths as fractions of the content width;
-- otherwise a two-column table gives the first (label) column 38% and
-- wider tables split evenly.
local MIN_ROW_H = 22
local CELL_PAD  = 5

local function ColumnWidths(opt, nCols, contentWidth)
    local fractions = opt.columnWidths
    if not fractions then
        if nCols == 2 then
            fractions = { 0.38, 0.62 }
        else
            fractions = {}
            for i = 1, nCols do fractions[i] = 1 / nCols end
        end
    end
    local widths, x = {}, {}
    local left = 0
    for i = 1, nCols do
        x[i] = left
        widths[i] = math.floor(contentWidth * (fractions[i] or (1 / nCols)))
        left = left + widths[i]
    end
    return widths, x
end

local function CreateTableWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    local cols = opt.columns or {}
    local rows = opt.rows or {}
    local nCols = math.max(#cols, 1)
    for _, row in ipairs(rows) do
        if #row > nCols then nCols = #row end
    end
    local colW, colX = ColumnWidths(opt, nCols, contentWidth)
    local headerH = 24

    -- Header row
    if #cols > 0 then
        local hdrBg = frame:CreateTexture(nil, "BACKGROUND")
        hdrBg:SetHeight(headerH)
        hdrBg:SetPoint("TOPLEFT", 0, 0)
        hdrBg:SetPoint("TOPRIGHT", 0, 0)
        hdrBg:SetColorTexture(unpack(O.TABLE_HEADER_BG))

        for i, col in ipairs(cols) do
            local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("TOPLEFT", colX[i] + 8, -6)
            fs:SetWidth(colW[i] - 12)
            fs:SetJustifyH("LEFT")
            fs:SetText(col)
            fs:SetTextColor(unpack(O.GOLD))
        end
    end

    local y = #cols > 0 and -(headerH + 2) or 0
    for r, row in ipairs(rows) do
        local cells, rowH = {}, MIN_ROW_H
        for c, cell in ipairs(row) do
            local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            fs:SetPoint("TOPLEFT", colX[c] + 8, y - CELL_PAD)
            fs:SetWidth(colW[c] - 12)
            fs:SetJustifyH("LEFT")
            fs:SetJustifyV("TOP")
            fs:SetWordWrap(true)
            fs:SetNonSpaceWrap(true)
            fs:SetText(tostring(cell or ""))
            fs:SetTextColor(unpack(O.TEXT_NORMAL))
            cells[c] = fs
            rowH = math.max(rowH, math.ceil(fs:GetStringHeight() or 0) + CELL_PAD * 2)
        end
        for _, fs in ipairs(cells) do
            fs:SetHeight(rowH - CELL_PAD * 2)
        end
        if r % 2 == 0 then
            local bg = frame:CreateTexture(nil, "BACKGROUND")
            bg:SetHeight(rowH)
            bg:SetPoint("TOPLEFT", 0, y)
            bg:SetPoint("TOPRIGHT", 0, y)
            bg:SetColorTexture(unpack(O.TABLE_ROW_ALT))
        end
        y = y - rowH
    end

    local h = math.abs(y) + 4
    frame:SetSize(contentWidth, h)
    return frame, h
end

---------------------------------------------------------------------------
-- Collapsible block - animated expand/collapse with persistent state
---------------------------------------------------------------------------

-- Saved state lives in BazUIDB.collapsibles. The DB is created by
-- the BazUI loader; we lazy-init the sub-table on first use.
local function GetCollapsibleState(key, defaultCollapsed)
    if not key then return defaultCollapsed end
    BazUIDB = BazUIDB or {}
    BazUIDB.collapsibles = BazUIDB.collapsibles or {}
    if BazUIDB.collapsibles[key] == nil then
        return defaultCollapsed
    end
    return BazUIDB.collapsibles[key]
end

local function SaveCollapsibleState(key, collapsed)
    if not key then return end
    BazUIDB = BazUIDB or {}
    BazUIDB.collapsibles = BazUIDB.collapsibles or {}
    BazUIDB.collapsibles[key] = collapsed
end

-- Smooth height + alpha animation using OnUpdate
local function AnimateCollapse(frame, fromH, toH, fromA, toA, duration, onComplete)
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / duration, 1)
        -- Ease out cubic for natural feel
        local eased = 1 - (1 - t) * (1 - t) * (1 - t)
        local h = fromH + (toH - fromH) * eased
        local a = fromA + (toA - fromA) * eased
        self:SetHeight(math.max(h, 0.001))
        self:SetAlpha(a)
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
            if onComplete then onComplete() end
        end
    end)
end

-- Recursively render a list of blocks into a parent, returning total height.
-- Each block anchors to the previous block's BOTTOMLEFT so height changes
-- propagate naturally. Returns the bottom Y offset (negative).
local function RenderBlockList(parent, blocks, contentWidth, startY)
    local y = startY or 0
    local prev = nil
    for i, block in ipairs(blocks or {}) do
        local factory = O.widgetFactories[block.type]
        if factory then
            local widget, h = factory(parent, block, contentWidth)
            if prev then
                widget:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
            else
                widget:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
            end
            widget:Show()
            y = y - h - O.SPACING
            prev = widget
        end
    end
    return y
end

O.RenderBlockList = RenderBlockList

local function CreateCollapsibleWidget(parent, opt, contentWidth)
    local titleStyle = opt.style or "h3"
    local preset = O.TEXT_PRESETS[titleStyle] or O.TEXT_PRESETS.h3

    -- Auto-derive a key if none provided so persistent state still works
    local key = opt.key or ("auto:" .. tostring(opt.title or "?"))
    local startCollapsed = opt.collapsed
    if startCollapsed == nil then startCollapsed = true end
    local isCollapsed = GetCollapsibleState(key, startCollapsed)

    local outer = CreateFrame("Frame", nil, parent)
    outer:SetWidth(contentWidth)

    -- Header row (clickable)
    local header = CreateFrame("Button", nil, outer)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(26)
    header:RegisterForClicks("LeftButtonUp")

    -- Hover background
    local hoverBg = header:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(1, 1, 1, 0.04)
    hoverBg:Hide()

    -- [+]/[-] icon
    local icon = header:CreateTexture(nil, "OVERLAY")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 2, 0)
    if isCollapsed then
        icon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
    else
        icon:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
    end

    -- Title text
    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(preset.font)
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetPoint("RIGHT", -4, 0)
    title:SetJustifyH("LEFT")
    title:SetText(opt.title or "")
    title:SetTextColor(unpack(preset.color))

    -- Optional underline accent below header (for h2/h1 styles)
    if preset.accent == "underline" then
        local line = header:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", title, "BOTTOMLEFT", 0, -2)
        line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -4, 1)
        line:SetColorTexture(unpack(O.HEADER_LINE))
    end

    -- Children container (rendered once, shown/hidden + height-animated)
    local body = CreateFrame("Frame", nil, outer)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -4)
    body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
    body:SetClipsChildren(true)

    local innerWidth = contentWidth - 12
    local bottomY = O.RenderBlockList(body, opt.blocks, innerWidth, 0)
    local bodyContentH = math.abs(bottomY)
    body:SetHeight(bodyContentH)

    if isCollapsed then
        body:SetHeight(0.001)
        body:SetAlpha(0)
    else
        body:SetAlpha(1)
    end

    local function UpdateOuterHeight()
        local h = header:GetHeight() + 4 + body:GetHeight()
        outer:SetHeight(h)
        -- If the outer frame is in a chain of relative-anchored siblings,
        -- height changes propagate automatically. If it lives in a parent
        -- using absolute positioning, we fire a callback so the parent
        -- can re-flow if it cares.
        if outer._onHeightChanged then outer._onHeightChanged() end
    end

    UpdateOuterHeight()

    header:SetScript("OnEnter", function() hoverBg:Show() end)
    header:SetScript("OnLeave", function() hoverBg:Hide() end)
    header:SetScript("OnClick", function()
        isCollapsed = not isCollapsed
        SaveCollapsibleState(key, isCollapsed)
        if isCollapsed then
            icon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
            AnimateCollapse(body, body:GetHeight(), 0.001, body:GetAlpha(), 0, 0.18, function()
                UpdateOuterHeight()
            end)
            -- Also update outer height progressively during the animation
            local tickElapsed = 0
            outer:SetScript("OnUpdate", function(self, dt)
                tickElapsed = tickElapsed + dt
                UpdateOuterHeight()
                if tickElapsed > 0.3 then self:SetScript("OnUpdate", nil) end
            end)
        else
            icon:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
            AnimateCollapse(body, body:GetHeight(), bodyContentH, body:GetAlpha(), 1, 0.20, function()
                UpdateOuterHeight()
            end)
            local tickElapsed = 0
            outer:SetScript("OnUpdate", function(self, dt)
                tickElapsed = tickElapsed + dt
                UpdateOuterHeight()
                if tickElapsed > 0.3 then self:SetScript("OnUpdate", nil) end
            end)
        end
    end)

    return outer, outer:GetHeight()
end

---------------------------------------------------------------------------
-- Register all factories
---------------------------------------------------------------------------

O.widgetFactories.h1          = CreateTextWidget("h1")
O.widgetFactories.h2          = CreateTextWidget("h2")
O.widgetFactories.h3          = CreateTextWidget("h3")
O.widgetFactories.h4          = CreateTextWidget("h4")
O.widgetFactories.paragraph   = CreateTextWidget("paragraph")
O.widgetFactories.lead        = CreateTextWidget("lead")
O.widgetFactories.caption     = CreateTextWidget("caption")
O.widgetFactories.quote       = CreateTextWidget("quote")
O.widgetFactories.list        = CreateListWidget
O.widgetFactories.image       = CreateImageWidget
O.widgetFactories.imageRow    = CreateImageRowWidget
O.widgetFactories.note        = CreateNoteWidget
O.widgetFactories.code        = CreateCodeWidget
O.widgetFactories.divider     = CreateDividerWidget
O.widgetFactories.spacer      = CreateSpacerWidget
O.widgetFactories.table       = CreateTableWidget
O.widgetFactories.collapsible = CreateCollapsibleWidget
