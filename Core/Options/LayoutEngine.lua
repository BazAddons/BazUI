-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: Layout Engine
-- Renders widgets in single-column or two-column bordered panel layout.
---------------------------------------------------------------------------

local O = BazUI._Options

-- Block types that always span the full content width in two-column
-- mode (never get paired side-by-side). The defaults cover legacy
-- header/description plus the rich content blocks from
-- ContentFactories. Custom blocks added later (e.g. dashboard widgets)
-- can opt in via O.RegisterFullWidthBlockType.
local FULL_WIDTH_TYPES = {
    header = true, description = true,
    h1 = true, h2 = true, h3 = true, h4 = true,
    paragraph = true, lead = true, caption = true, quote = true,
    list = true, image = true, note = true, code = true,
    divider = true, spacer = true, table = true,
    collapsible = true,
}

function O.RegisterFullWidthBlockType(blockType)
    if type(blockType) == "string" then
        FULL_WIDTH_TYPES[blockType] = true
    end
end

---------------------------------------------------------------------------
-- RenderWidgets - main layout function
-- Renders sorted args into a parent frame. Supports:
--   * Single column (narrow or forced)
--   * Two-column bordered panels (wide enough, auto-detected)
--   * Half-width pairing for ANY widget type
---------------------------------------------------------------------------

function O.RenderWidgets(parent, args, contentWidth, forceColumns, startY)
    local sorted = O.SortedArgs(args)
    local yOffset = startY or -O.PAD

    -- Two-column mode: auto when wide enough, unless forced to 1
    local useTwoCol = (forceColumns ~= 1) and (contentWidth > 500)

    if not useTwoCol then
        -- Single column with half-width pairing
        local i = 1
        while i <= #sorted do
            local opt = sorted[i]
            if opt.type ~= "group" then
                local nextOpt = sorted[i + 1]
                -- Pair consecutive half-width items side by side
                if opt.width == "half" and nextOpt and nextOpt.width == "half" and nextOpt.type ~= "group" then
                    local halfW = math.floor((contentWidth - O.COL_GAP) / 2)
                    local factory1 = O.widgetFactories[opt.type]
                    local factory2 = O.widgetFactories[nextOpt.type]
                    if factory1 and factory2 then
                        local w1, h1 = factory1(parent, opt, halfW)
                        local w2, h2 = factory2(parent, nextOpt, halfW)
                        w1:SetPoint("TOPLEFT", parent, "TOPLEFT", O.PAD, yOffset)
                        w2:SetPoint("TOPLEFT", parent, "TOPLEFT", O.PAD + halfW + O.COL_GAP, yOffset)
                        w1:Show()
                        w2:Show()
                        yOffset = yOffset - math.max(h1, h2) - O.SPACING
                        i = i + 2
                    else
                        i = i + 1
                    end
                else
                    local factory = O.widgetFactories[opt.type]
                    if factory then
                        local widget, h = factory(parent, opt, contentWidth)
                        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", O.PAD, yOffset)
                        widget:Show()
                        yOffset = yOffset - h - O.SPACING
                    end
                    i = i + 1
                end
            else
                i = i + 1
            end
        end
        return yOffset
    end

    -- Two-column bordered panel mode (uses the module-scope
    -- FULL_WIDTH_TYPES so custom blocks can register via
    -- O.RegisterFullWidthBlockType)
    -- First pass: separate into sections split by full-width items
    local sections = {}
    local currentLeft = {}
    local currentRight = {}
    local col = 1

    for _, opt in ipairs(sorted) do
        if opt.type ~= "group" then
            local fullWidth = FULL_WIDTH_TYPES[opt.type]
                or (opt.type == "execute" and opt.width ~= "half")
            if fullWidth then
                if #currentLeft > 0 or #currentRight > 0 then
                    table.insert(sections, { type = "pair", left = currentLeft, right = currentRight })
                    currentLeft, currentRight = {}, {}
                    col = 1
                end
                table.insert(sections, { type = "full", opt = opt })
            else
                if col == 1 then
                    table.insert(currentLeft, opt)
                    col = 2
                else
                    table.insert(currentRight, opt)
                    col = 1
                end
            end
        end
    end
    if #currentLeft > 0 or #currentRight > 0 then
        table.insert(sections, { type = "pair", left = currentLeft, right = currentRight })
    end

    -- Second pass: render sections
    local availableWidth = contentWidth - O.PAD * 2
    local panelWidth = math.floor((availableWidth - O.COL_GAP) / 2)
    local innerWidth = panelWidth - O.PANEL_PAD * 2
    local prevType = nil

    for _, section in ipairs(sections) do
        if section.type == "full" then
            if prevType == "pair" then
                yOffset = yOffset - 4
            end
            local factory = O.widgetFactories[section.opt.type]
            if factory then
                -- Use availableWidth (contentWidth - O.PAD * 2) so the
                -- widget's right edge lines up with the bordered panels
                -- below it. Passing contentWidth made notes/headers
                -- extend ~2*PAD past the panel edge.
                local widget, h = factory(parent, section.opt, availableWidth)
                widget:SetPoint("TOPLEFT", parent, "TOPLEFT", O.PAD, yOffset)
                widget:Show()
                yOffset = yOffset - h - 2
            end
        else
            local hasLeft = #section.left > 0
            local hasRight = #section.right > 0

            if hasLeft and hasRight then
                -- Two panels side by side
                local leftH = O.PANEL_PAD
                for _, opt in ipairs(section.left) do
                    local factory = O.widgetFactories[opt.type]
                    if factory then
                        local _, h = factory(parent, opt, innerWidth)
                        leftH = leftH + h + O.SPACING
                    end
                end

                local rightH = O.PANEL_PAD
                for _, opt in ipairs(section.right) do
                    local factory = O.widgetFactories[opt.type]
                    if factory then
                        local _, h = factory(parent, opt, innerWidth)
                        rightH = rightH + h + O.SPACING
                    end
                end

                local maxH = math.max(leftH, rightH) + O.PANEL_PAD

                local leftPanel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
                leftPanel:SetSize(panelWidth, maxH)
                leftPanel:SetPoint("TOPLEFT", parent, "TOPLEFT", O.PAD, yOffset)
                leftPanel:SetBackdrop(O.PANEL_BACKDROP)
                leftPanel:SetBackdropColor(unpack(O.PANEL_BG))
                leftPanel:SetBackdropBorderColor(unpack(O.PANEL_BORDER))
                leftPanel:Show()

                local ly = -O.PANEL_PAD
                for _, opt in ipairs(section.left) do
                    local factory = O.widgetFactories[opt.type]
                    if factory then
                        local widget, h = factory(leftPanel, opt, innerWidth)
                        widget:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", O.PANEL_PAD, ly)
                        widget:Show()
                        ly = ly - h - O.SPACING
                    end
                end

                local rightPanel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
                rightPanel:SetSize(panelWidth, maxH)
                rightPanel:SetPoint("TOPLEFT", parent, "TOPLEFT", O.PAD + panelWidth + O.COL_GAP, yOffset)
                rightPanel:SetBackdrop(O.PANEL_BACKDROP)
                rightPanel:SetBackdropColor(unpack(O.PANEL_BG))
                rightPanel:SetBackdropBorderColor(unpack(O.PANEL_BORDER))
                rightPanel:Show()

                local ry = -O.PANEL_PAD
                for _, opt in ipairs(section.right) do
                    local factory = O.widgetFactories[opt.type]
                    if factory then
                        local widget, h = factory(rightPanel, opt, innerWidth)
                        widget:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", O.PANEL_PAD, ry)
                        widget:Show()
                        ry = ry - h - O.SPACING
                    end
                end

                yOffset = yOffset - maxH - O.SPACING
            else
                -- Single full-width panel
                local items = hasLeft and section.left or section.right
                local fullInner = availableWidth - O.PANEL_PAD * 2

                local itemH = O.PANEL_PAD
                for _, opt in ipairs(items) do
                    local factory = O.widgetFactories[opt.type]
                    if factory then
                        local _, h = factory(parent, opt, fullInner)
                        itemH = itemH + h + O.SPACING
                    end
                end
                local panelH = itemH + O.PANEL_PAD

                local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
                panel:SetSize(availableWidth, panelH)
                panel:SetPoint("TOPLEFT", parent, "TOPLEFT", O.PAD, yOffset)
                panel:SetBackdrop(O.PANEL_BACKDROP)
                panel:SetBackdropColor(unpack(O.PANEL_BG))
                panel:SetBackdropBorderColor(unpack(O.PANEL_BORDER))
                panel:Show()

                local iy = -O.PANEL_PAD
                for _, opt in ipairs(items) do
                    local factory = O.widgetFactories[opt.type]
                    if factory then
                        local widget, h = factory(panel, opt, fullInner)
                        widget:SetPoint("TOPLEFT", panel, "TOPLEFT", O.PANEL_PAD, iy)
                        widget:Show()
                        iy = iy - h - O.SPACING
                    end
                end

                yOffset = yOffset - panelH - O.SPACING
            end
        end
        prevType = section.type
    end

    return yOffset
end
