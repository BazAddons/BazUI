-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: Constants & Shared Helpers
-- Layout dimensions, fonts, colors, backdrops, and utility functions
-- used across all Options modules.
---------------------------------------------------------------------------

BazUI._Options = BazUI._Options or {}
local O = BazUI._Options

---------------------------------------------------------------------------
-- Layout Dimensions
---------------------------------------------------------------------------

O.PAD            = 8
O.WIDGET_HEIGHT  = 28
O.HEADER_HEIGHT  = 24
O.SPACING        = 2
O.LIST_ITEM_HEIGHT = 28

-- The form language (WidgetFactories / LayoutEngine / ListDetail).
-- Sized for the Options panel's canvas: ~665 px wide at the default
-- window size, so one column with controls at fixed widths.
O.CONTENT_MAX    = 640   -- content never stretches wider than this
O.ROW_H          = 28    -- a control row
O.ROW_DESC_H     = 44    -- a control row with a description line
O.ROW_PAD        = 6     -- inset of label and control from the row edges
O.ROW_GAP        = 14    -- minimum gap between label and control
O.SECTION_GAP    = 10    -- extra air above a section header
O.CHECK_W        = 24
O.CTRL_W         = 180   -- dropdowns and sliders (slider includes its value box)
O.CTRL_MAX_W     = 240   -- a dropdown may widen to this for long values
O.INPUT_W        = 200
O.VALUE_W        = 44    -- slider value box
O.BUTTON_MIN_W   = 90
O.BUTTON_MAX_W   = 200
O.PICKER_H       = 34    -- the "pick an item" row above an item's form

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------

O.LABEL_FONT     = "GameFontHighlight"
O.DESC_FONT      = "GameFontHighlightSmall"
O.HEADER_FONT    = "GameFontNormal"
O.LIST_FONT      = "GameFontHighlight"
O.SMALL_FONT     = "GameFontHighlight"

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------

O.GOLD           = { 1, 0.82, 0 }
O.WHITE          = { 1, 1, 1 }
O.DIM            = { 0.6, 0.6, 0.6 }
O.TEXT_NORMAL    = { 0.9, 0.9, 0.9 }
O.TEXT_DESC      = { 0.62, 0.58, 0.50 }
O.TEXT_DISABLED  = { 0.42, 0.40, 0.36 }
O.PANEL_BG       = { 0.04, 0.04, 0.06, 0.7 }
O.PANEL_BORDER   = { 0.25, 0.25, 0.3, 0.6 }
O.LIST_BG        = { 0.03, 0.03, 0.05, 0.6 }
O.HEADER_LINE    = { 0.62, 0.48, 0.20, 0.55 }

-- Floating-dialog colors (Popup, CopyDialog, IconPicker). Brighter
-- and more opaque than the inline PANEL_* tones so a popup floating
-- over arbitrary game content (the world, a Blizzard frame, etc.)
-- stays clearly delineated. Inline panels keep PANEL_BG / PANEL_BORDER
-- since they sit on the already-textured Options window backdrop.
O.DIALOG_BG      = { 0.04, 0.04, 0.06, 0.95 }
O.DIALOG_BORDER  = { 0.4,  0.35, 0.2,  0.95 }

---------------------------------------------------------------------------
-- Backdrops
---------------------------------------------------------------------------



---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Sort args table by order field, returns array
function O.SortedArgs(args)
    if not args then return {} end
    local sorted = {}
    for key, opt in pairs(args) do
        opt._key = key
        sorted[#sorted + 1] = opt
    end
    table.sort(sorted, function(a, b)
        return (a.order or 100) < (b.order or 100)
    end)
    return sorted
end

-- Check if an option is disabled (supports function or boolean)
function O.IsDisabled(opt)
    if type(opt.disabled) == "function" then return opt.disabled() end
    return opt.disabled or false
end

-- A row's state, applied now and whenever it is shown again.
--
-- Every widget factory reads its value and its disabled state in one
-- function and hung that function on OnShow. OnShow does not fire when
-- a frame is created into a parent that is already visible and shown in
-- the same breath, which is exactly what re-rendering a page does - so
-- a row rebuilt by a refresh kept whatever state it was built with, and
-- `disabled` did nothing at all until something else made the page
-- appear. A setting that greys out on one render and not the next is
-- worse than one that never greys out, because you cannot tell which
-- you are looking at.
--
-- So the sync runs once at creation too. It is the same function either
-- way, and running it twice only reads the same values twice.
function O.SyncRow(frame, fn)
    frame:SetScript("OnShow", fn)
    fn(frame)
end

function O.IsHidden(opt)
    if type(opt.hidden) == "function" then return opt.hidden() end
    return opt.hidden or false
end

---------------------------------------------------------------------------
-- Selection highlight (Blizzard-style gold gradient)
--
-- Returns a {textures...} group that the caller toggles via Show()/Hide()
-- when the row's selection state changes. Mirrors the highlight used by
-- Traveler's Log + Quest tracker dialogues - two horizontal bands
-- fading inward to a center crest, plus thin gold lines at top + bottom
-- that fade to transparent at each edge.
--
-- Used by both the User Manual tree (Options/UserGuide.lua) and the
-- list/detail panel (Options/ListDetail.lua) so selection visuals stay
-- cohesive across every page that uses one of those layouts.
---------------------------------------------------------------------------

function O.BuildSelectionHighlight(row, rowH)
    -- Two-anchor placement (corner + center) so each half always
    -- spans LEFT-edge-to-center or center-to-RIGHT-edge regardless of
    -- the row's current width. Earlier versions used SetSize(halfW)
    -- captured at construction time, which left a black gap in the
    -- middle when the row grew during a later layout pass.
    rowH = rowH or row:GetHeight() or 26

    local function MakeBand(layer, side, fadeFromCenter)
        local tex = row:CreateTexture(nil, layer)
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetHeight(rowH)
        if side == "LEFT" then
            tex:SetPoint("TOPLEFT",     row, "TOPLEFT",     0, 0)
            tex:SetPoint("BOTTOMRIGHT", row, "BOTTOM",      0, 0)
        else  -- RIGHT
            tex:SetPoint("TOPLEFT",     row, "TOP",         0, 0)
            tex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        end
        if fadeFromCenter then
            tex:SetGradient("HORIZONTAL",
                CreateColor(1, 0.82, 0, 0.45),
                CreateColor(1, 0.82, 0, 0))
        else
            tex:SetGradient("HORIZONTAL",
                CreateColor(1, 0.82, 0, 0),
                CreateColor(1, 0.82, 0, 0.45))
        end
        return tex
    end

    local function MakeRule(corner, fadeFromCenter)
        local tex = row:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetHeight(1)
        if corner == "TOPLEFT" then
            tex:SetPoint("TOPLEFT",     row, "TOPLEFT",   0, 0)
            tex:SetPoint("BOTTOMRIGHT", row, "TOP",       0, -1)
        elseif corner == "TOPRIGHT" then
            tex:SetPoint("TOPLEFT",     row, "TOP",       0, 0)
            tex:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT",  0, -1)
        elseif corner == "BOTTOMLEFT" then
            tex:SetPoint("TOPLEFT",     row, "BOTTOMLEFT", 0, 1)
            tex:SetPoint("BOTTOMRIGHT", row, "BOTTOM",     0, 0)
        else  -- BOTTOMRIGHT
            tex:SetPoint("TOPLEFT",     row, "BOTTOM",      0, 1)
            tex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        end
        if fadeFromCenter then
            tex:SetGradient("HORIZONTAL",
                CreateColor(1, 0.82, 0, 0.85),
                CreateColor(1, 0.82, 0, 0))
        else
            tex:SetGradient("HORIZONTAL",
                CreateColor(1, 0.82, 0, 0),
                CreateColor(1, 0.82, 0, 0.85))
        end
        return tex
    end

    local bandL = MakeBand("BACKGROUND", "LEFT",  false)
    local bandR = MakeBand("BACKGROUND", "RIGHT", true)
    local topL  = MakeRule("TOPLEFT",     false)
    local topR  = MakeRule("TOPRIGHT",    true)
    local botL  = MakeRule("BOTTOMLEFT",  false)
    local botR  = MakeRule("BOTTOMRIGHT", true)

    return { bandL, bandR, topL, topR, botL, botR }
end

function O.ShowHighlightGroup(group, show)
    for _, t in ipairs(group or {}) do
        if show then t:Show() else t:Hide() end
    end
end

---------------------------------------------------------------------------
-- Section header chrome - the chapter-divider look used by source-
-- grouped lists in the picker AND by expandable parent
-- rows in the User Manual tree. Keeping the styling here so both
-- renderers stay in lockstep when the look changes.
--
-- Adds three textures to a header button frame:
--   * Warm-toned dark backdrop fill (BACKGROUND layer)
--   * Thick gold accent bar on the left edge (ARTWORK layer)
--   * Thin gold rule along the bottom, full width (ARTWORK layer)
--
-- The gold rule is anchored at x=0 (no inset on either side) so it
-- meets the accent bar at the bottom-left corner cleanly and reaches
-- the right edge of the backdrop without leaving a gap.
---------------------------------------------------------------------------

function O.BuildSectionHeaderChrome(button)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.09, 0.04, 0.65)

    local accent = button:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetColorTexture(1.00, 0.82, 0.00, 0.95)

    local rule = button:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    rule:SetColorTexture(1.00, 0.82, 0.00, 0.55)

    return { bg = bg, accent = accent, rule = rule }
end

-- Section-header height is slightly taller than item rows so the
-- chapter-divider backdrop has room to breathe.
O.SECTION_HEADER_HEIGHT = (O.LIST_ITEM_HEIGHT or 28) + 4

---------------------------------------------------------------------------
-- O.RenderListRows — one shared row builder for every list/sidebar in
-- the suite. Pages converted their domain-specific data (tree nodes,
-- option-table groups, top-level sub-categories) into a flat array of
-- row specs and hand it off here, which means visuals + behavior stay
-- in lockstep across:
--   * The standalone window's left sidebar (Registration.lua)
--   * The User Manual tree (UserGuide.lua)
--   * The list/detail panel (ListDetail.lua)
--
-- Each row spec is a table:
--   {
--     key        = unique string,
--     label      = display text,
--     count      = optional number (rendered as "  (N)" suffix in gray),
--     isParent   = true for chapter-divider headers (BG + accent +
--                  bottom rule + +/- chevron). Default false.
--     expanded   = parent rows: true shows minus, false shows plus.
--                  Ignored for non-parent rows.
--     isSelected = true to draw the gold-gradient highlight + white
--                  text. Parent rows skip the gradient (chapter chrome
--                  is enough) but still get the white text color.
--     depth      = optional indentation level (0 = flush left).
--     indent     = optional extra pixels of indent on top of depth.
--     onClick    = function() called on left-click.
--     moveUp     = optional function() - when set, paints a small up
--                  arrow button at the right edge of the row. Pass nil
--                  on the topmost row so the arrow renders disabled.
--     moveDown   = optional function() - mirror of moveUp; nil on the
--                  bottommost row to render disabled.
--   }
--
-- opts:
--   width = list-content width in pixels (required).
--
-- Selection styling for parent rows is intentionally NOT optional.
-- Both lists feed the same renderer the same shape of data; if a
-- caller wants the parent to look "selected" it sets isSelected on
-- that row spec. Source headers in the list/detail panel use this
-- the same way User Manual tree parents do, so the two lists always
-- read as one cohesive widget.
---------------------------------------------------------------------------

function O.RenderListRows(listContent, rows, opts)
    opts = opts or {}
    local width = opts.width
    if not width then return end

    local frames = {}
    local y = 0

    for i, spec in ipairs(rows) do
        local isParent   = spec.isParent and true or false
        local rowH       = isParent and O.SECTION_HEADER_HEIGHT or O.LIST_ITEM_HEIGHT
        local isSelected = spec.isSelected and true or false

        local row = CreateFrame("Button", nil, listContent)
        row:SetSize(width, rowH)
        row:SetPoint("TOPLEFT", 0, -y)
        row:RegisterForClicks("LeftButtonUp")

        if isParent then
            O.BuildSectionHeaderChrome(row)
        end

        -- Subtle hover background (only when not selected).
        local hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        hover:SetAllPoints()
        if isParent then
            hover:SetColorTexture(1, 0.82, 0, 0.10)
        else
            hover:SetColorTexture(1, 1, 1, 0.05)
        end
        hover:Hide()
        row.hover = hover

        -- Gold-gradient selection highlight. Skipped on parent rows
        -- because the chapter chrome already gives them their visual
        -- identity; layering the gradient + top/bottom rules would
        -- double-paint the accent + bottom rule.
        local hlGroup
        if not isParent then
            hlGroup = O.BuildSelectionHighlight(row, rowH)
            O.ShowHighlightGroup(hlGroup, isSelected)
        end
        row.hlGroup = hlGroup

        local depth   = spec.depth or 0
        local indent  = 8 + depth * 16 + (spec.indent or 0)

        -- Plus/minus chevron for parent rows. Positioned a hair left
        -- of the text so it doesn't visually float away from the row.
        if isParent then
            local arrow = row:CreateTexture(nil, "OVERLAY")
            arrow:SetSize(14, 14)
            arrow:SetPoint("LEFT", indent - 2, 0)
            arrow:SetTexture(spec.expanded
                and "Interface\\Buttons\\UI-MinusButton-Up"
                or  "Interface\\Buttons\\UI-PlusButton-Up")
            indent = indent + 16
        end

        -- Move-up / move-down arrows on the right edge. Rendered as
        -- child Buttons so clicking an arrow doesn't trigger the row's
        -- OnClick. A nil callback on either side draws the arrow
        -- disabled (grayed out, non-clickable) so the user still sees
        -- the affordance but understands they're at a list boundary.
        -- Only emitted when the spec sets either callback - rows
        -- without ordering (User Manual tree, source headers) skip
        -- the arrows entirely so the right edge stays clean.
        --
        -- Style: the same arrow every other arrow in BazUI uses, through
        -- BazUI.SetArrowTexture. These rows used to draw a set of custom
        -- PNGs under Textures/Sort_Arrows/ that were never made, so the
        -- reorder buttons on every list - bag categories, drawer widgets,
        -- minimap buttons - were invisible while still being clickable.
        -- One arrow for the whole addon also means a skin that changes it
        -- changes it everywhere rather than in three places out of four.
        local rightInset = 4
        if spec.moveUp ~= nil or spec.moveDown ~= nil then
            local function MakeArrow(direction, callback, anchorRight)
                local btn = CreateFrame("Button", nil, row)
                btn:SetSize(22, 22)
                btn:SetPoint("RIGHT", -anchorRight, 0)

                local tex = btn:CreateTexture(nil, "ARTWORK")
                tex:SetPoint("CENTER")
                BazUI.SetArrowTexture(tex, direction, 14)
                btn.tex = tex

                if callback then
                    btn:RegisterForClicks("LeftButtonUp")
                    btn:SetScript("OnClick", function() callback() end)
                    btn:SetScript("OnEnter", function(self)
                        self.tex:SetVertexColor(unpack(O.GOLD))
                    end)
                    btn:SetScript("OnLeave", function(self)
                        self.tex:SetVertexColor(1, 1, 1)
                        self.tex:SetPoint("CENTER", 0, 0)
                    end)
                    btn:SetScript("OnMouseDown", function(self)
                        self.tex:SetPoint("CENTER", 0, -1)
                    end)
                    btn:SetScript("OnMouseUp", function(self)
                        self.tex:SetPoint("CENTER", 0, 0)
                    end)
                else
                    -- At the end of the list: still drawn, so the row
                    -- keeps its shape, and plainly not for pressing.
                    btn:EnableMouse(false)
                    tex:SetVertexColor(0.4, 0.4, 0.4, 0.55)
                end
                return btn
            end
            -- Down arrow flush to the right; up arrow to its left.
            MakeArrow("Down", spec.moveDown, 6)
            MakeArrow("Up",   spec.moveUp,   32)
            rightInset = 60  -- reserve room so label doesn't overlap arrows
        end

        local labelText = spec.label or ""
        if spec.count then
            labelText = labelText .. "  |cff888888(" .. spec.count .. ")|r"
        end
        local text = row:CreateFontString(nil, "OVERLAY", O.LIST_FONT)
        text:SetPoint("LEFT", indent, 0)
        text:SetPoint("RIGHT", -rightInset, 0)
        text:SetJustifyH("LEFT")
        text:SetText(labelText)
        if isSelected then
            text:SetTextColor(1, 1, 1)
            text:SetAlpha(1.0)
        else
            text:SetTextColor(unpack(O.GOLD))
            text:SetAlpha(0.75)
        end
        row.text = text

        local capturedClick = spec.onClick
        row:SetScript("OnClick", function()
            if capturedClick then capturedClick() end
        end)
        row:SetScript("OnEnter", function(self)
            if not isSelected then
                self.hover:Show()
                self.text:SetAlpha(1.0)
            end
        end)
        row:SetScript("OnLeave", function(self)
            if not isSelected then
                self.hover:Hide()
                self.text:SetAlpha(0.75)
            end
        end)

        frames[i] = row
        y = y + rowH
    end

    return frames, y
end

---------------------------------------------------------------------------
-- BuildTitleBar - shared header used by both the User Manual page and
-- the standard list/detail page. Includes the addon icon (if available),
-- gold title text, optional version line, and a horizontal rule
-- underneath. Returns (frame, height) so the caller can advance its
-- y-cursor past it.
--
-- opts = {
--   title         = string,         -- displayed as gold large text
--   addonName     = string,          -- used to look up icon + version
--   version       = string,          -- optional override; otherwise
--                                    -- read from the addon's .toc
--   contentWidth  = number,          -- frame width to set
-- }
---------------------------------------------------------------------------

function O.BuildTitleBar(parent, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    local headerHeight = 44
    local titleXOffset = O.PAD

    local addonConfig = opts.addonName and BazUI.addons
        and BazUI.addons[opts.addonName] or nil
    local iconTex = addonConfig and (addonConfig.icon or (addonConfig.minimap and addonConfig.minimap.icon))
    if not iconTex and opts.addonName and C_AddOns and C_AddOns.GetAddOnMetadata then
        iconTex = C_AddOns.GetAddOnMetadata(opts.addonName, "IconTexture")
    end
    if iconTex then
        local addonIcon = frame:CreateTexture(nil, "ARTWORK")
        addonIcon:SetSize(32, 32)
        addonIcon:SetPoint("TOPLEFT", O.PAD, -6)
        addonIcon:SetTexture(iconTex)
        titleXOffset = O.PAD + 40
    end

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", titleXOffset, -6)
    titleText:SetText(opts.title or opts.addonName or "")
    titleText:SetTextColor(unpack(O.GOLD))

    -- Version, license and copyright on one dim line under the title.
    -- All three are read from the addon's own .toc, so what the panel
    -- shows is the notice that shipped rather than a second copy of it
    -- written out here and left to drift. An addon whose .toc says
    -- nothing simply gets a shorter line.
    local function Meta(field)
        if not (opts.addonName and C_AddOns and C_AddOns.GetAddOnMetadata) then return nil end
        local value = C_AddOns.GetAddOnMetadata(opts.addonName, field)
        if value == "" then return nil end
        return value
    end

    local addonVersion = opts.version
        or (addonConfig and addonConfig.version)
        or Meta("Version")

    local credits = {}
    if addonVersion then credits[#credits + 1] = "v" .. addonVersion end
    local license = Meta("X-License")
    if license then credits[#credits + 1] = license end
    local copyright = Meta("X-Copyright")
    if copyright then credits[#credits + 1] = copyright end

    if #credits > 0 then
        local versionText = frame:CreateFontString(nil, "OVERLAY", O.SMALL_FONT)
        versionText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
        versionText:SetText(table.concat(credits, "  -  "))
        versionText:SetTextColor(unpack(O.DIM))
        headerHeight = headerHeight + 6
    end

    local titleLine = frame:CreateTexture(nil, "ARTWORK")
    titleLine:SetHeight(1)
    titleLine:SetPoint("BOTTOMLEFT", O.PAD, 0)
    titleLine:SetPoint("BOTTOMRIGHT", -O.PAD, 0)
    titleLine:SetColorTexture(unpack(O.HEADER_LINE))

    if opts.contentWidth then
        frame:SetSize(opts.contentWidth, headerHeight)
    else
        frame:SetHeight(headerHeight)
    end
    return frame, headerHeight
end

-- Remove all children from a frame (for re-rendering)
function O.ClearChildren(parent)
    for _, child in ipairs({ parent:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
    for _, region in ipairs({ parent:GetRegions() }) do
        region:Hide()
        region:SetParent(nil)
    end
end

---------------------------------------------------------------------------
-- List/detail layout dimensions - shared so the User Manual tree and
-- the standard list/detail panel resolve to the same widths regardless
-- of the container size. ListDetail used to clamp at 22 % / 180-320 px;
-- the User Manual at 28 % / 200-320. Settling on the User Manual's
-- numbers (it's the reference for visual style across the suite).
---------------------------------------------------------------------------

O.PAGE_LIST_PCT = 0.28
O.PAGE_LIST_MIN = 200
O.PAGE_LIST_MAX = 320
O.PAGE_LIST_GAP = 14

function O.ResolveListWidth(containerWidth)
    local w = math.floor((containerWidth or 600) * O.PAGE_LIST_PCT)
    if w < O.PAGE_LIST_MIN then w = O.PAGE_LIST_MIN end
    if w > O.PAGE_LIST_MAX then w = O.PAGE_LIST_MAX end
    return w
end


-- Auto-hide a scroll bar when the content fits without scrolling.
-- Tracks size changes on both the scroll frame *and* its scroll child:
-- the child height changes whenever a page re-renders (User Guide
-- navigation, dynamic option pages, etc.), and the frame's
-- OnSizeChanged alone can't catch that — leaving the bar stuck on its
-- previous show/hide state from when the panel was first laid out.
function O.AutoHideScrollbar(scrollFrame, scrollBar)
    if not scrollFrame or not scrollBar then return end

    local function Update()
        local child = scrollFrame:GetScrollChild()
        if not child then
            scrollBar:Hide()
            return
        end
        local contentH = child:GetHeight() or 0
        local frameH = scrollFrame:GetHeight() or 0
        if contentH > frameH + 1 then
            scrollBar:Show()
        else
            scrollBar:Hide()
        end
    end

    scrollFrame:HookScript("OnSizeChanged", Update)

    -- The scroll child may not exist yet when we're called, and may also
    -- be replaced later via SetScrollChild — so re-attach an
    -- OnSizeChanged hook each time we see a new child.
    local hookedChild = nil
    local function HookChild()
        local child = scrollFrame:GetScrollChild()
        if child and child ~= hookedChild then
            child:HookScript("OnSizeChanged", Update)
            hookedChild = child
            Update()
        end
    end
    if scrollFrame.SetScrollChild then
        hooksecurefunc(scrollFrame, "SetScrollChild", HookChild)
    end

    -- Poll briefly after creation so content has settled, and pick up
    -- the initial scroll child if it's already been assigned.
    C_Timer.After(0, function() HookChild() Update() end)
    C_Timer.After(0.1, function() HookChild() Update() end)
end
