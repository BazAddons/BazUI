-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: Layout Engine
--
-- One column. Every widget is rendered at the content width and stacked
-- with O.SPACING between rows; a section header gets O.SECTION_GAP of
-- air above it so sections read as groups. Groups are skipped here
-- (the page renderer handles them). Legacy hints such as
-- width = "half" or columns = 2 are ignored: the canvas is not wide
-- enough for two columns to help.
---------------------------------------------------------------------------

local O = BazUI._Options

-- Kept for callers that registered block types under the old two-column
-- engine; every block is full width now.
function O.RegisterFullWidthBlockType() end

-- Renders sorted args into `parent` from `startY` downward. Returns the
-- y offset below the last widget.
function O.RenderWidgets(parent, args, contentWidth, _, startY)
    local sorted = O.SortedArgs(args)
    local y = startY or -O.PAD
    contentWidth = math.min(contentWidth, O.CONTENT_MAX)
    local first = true

    for _, opt in ipairs(sorted) do
        if opt.type ~= "group" then
            if O.IsHidden(opt) then
                -- skip
            else
                local factory = O.widgetFactories[opt.type]
                if factory then
                    if opt.type == "header" and not first then
                        y = y - O.SECTION_GAP
                    end
                    local widget, h = factory(parent, opt, contentWidth)
                    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", O.PAD, y)
                    widget:Show()
                    y = y - h - O.SPACING
                    first = false
                end
            end
        end
    end
    return y
end
