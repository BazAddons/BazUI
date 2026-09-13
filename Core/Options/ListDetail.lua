-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: List/Detail Split Panel
-- Gold text links on dark background (Traveler's Log style).
-- Left list, right detail. Used by Widgets, Drawers, BazBars bars, etc.
---------------------------------------------------------------------------

local O = BazUI._Options

---------------------------------------------------------------------------
-- Build a list/detail split panel inside a container.
-- groupOpt: the group option containing child groups
-- container: parent frame
-- contentWidth: available width
-- yOffset: starting Y position
-- executeArgs: optional buttons above the list (Create New, etc.)
-- Returns: new yOffset after the split panel
---------------------------------------------------------------------------

function O.BuildListDetailPanel(container, groupOpt, contentWidth, yOffset, executeArgs)
    -- Selection + collapse state persistence target. `container` is
    -- typically a renderTarget Frame that gets discarded on every
    -- RefreshOptions call (Registration.lua's RenderIntoCanvas
    -- recreates it from scratch each render to avoid orphaned-frame
    -- bugs). Storing _lastSelectedItem on it would lose the user's
    -- selection every time they edit any option in the detail pane.
    -- Walk up to the longest-lived ancestor we have (window.content)
    -- and stash there with a key derived from groupOpt.name, so
    -- multiple list-details on different subcategories don't collide.
    local stateHost = container:GetParent() or container
    local stateKey  = "_bazListDetail_" .. tostring(groupOpt.name or "default")

    -- Split frame: anchors to bottom of container to fill space
    local splitFrame = CreateFrame("Frame", nil, container)
    splitFrame:SetPoint("TOPLEFT", container, "TOPLEFT", O.PAD, yOffset)
    splitFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -O.PAD, O.PAD)
    splitFrame:Show()

    -- List width via the shared resolver (28 % / 200-320 px) so the
    -- standard list/detail panel matches the User Manual exactly.
    local containerW = container:GetWidth() or contentWidth or 600
    local listW = O.ResolveListWidth(containerW)

    -- Left: list panel
    local listBg = CreateFrame("Frame", nil, splitFrame, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 0, 0)
    listBg:SetPoint("BOTTOMLEFT", 0, 0)
    listBg:SetWidth(listW)
    listBg:SetBackdrop(O.LIST_BACKDROP)
    listBg:SetBackdropColor(unpack(O.LIST_BG))
    listBg:SetBackdropBorderColor(unpack(O.PANEL_BORDER))

    -- Execute buttons at top of list (e.g. Create New Drawer)
    local listTopY = -6
    for _, execOpt in ipairs(executeArgs or {}) do
        local execBtn = CreateFrame("Button", nil, listBg, "UIPanelButtonTemplate")
        execBtn:SetSize(listW - 12, 24)
        execBtn:SetPoint("TOPLEFT", listBg, "TOPLEFT", 6, listTopY)
        execBtn:SetText(execOpt.name or "")
        execBtn:SetScript("OnClick", function()
            if execOpt.func then execOpt.func() end
        end)
        local fs = execBtn:GetFontString()
        if fs then fs:SetFontObject("GameFontHighlightSmall") end
        execBtn:Show()
        listTopY = listTopY - 28
    end

    -- List scroll
    local listScroll = CreateFrame("ScrollFrame", nil, listBg)
    listScroll:SetPoint("TOPLEFT", 4, listTopY - 2)
    listScroll:SetPoint("BOTTOMRIGHT", -14, 4)
    listScroll:EnableMouseWheel(true)

    local listScrollBar = CreateFrame("EventFrame", nil, listBg, "MinimalScrollBar")
    listScrollBar:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 2, 0)
    listScrollBar:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", 2, 0)
    ScrollUtil.InitScrollFrameWithScrollBar(listScroll, listScrollBar)

    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetWidth(listW - 26)
    listScroll:SetScrollChild(listContent)
    O.AutoHideScrollbar(listScroll, listScrollBar)

    -- Right: detail panel
    local detailFrame = CreateFrame("Frame", nil, splitFrame, "BackdropTemplate")
    detailFrame:SetPoint("TOPLEFT", listBg, "TOPRIGHT", O.PAGE_LIST_GAP, 0)
    detailFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    detailFrame:SetBackdrop(O.LIST_BACKDROP)
    detailFrame:SetBackdropColor(unpack(O.PANEL_BG))
    detailFrame:SetBackdropBorderColor(unpack(O.PANEL_BORDER))

    local detailScroll = CreateFrame("ScrollFrame", nil, detailFrame)
    detailScroll:SetPoint("TOPLEFT", 4, -4)
    detailScroll:SetPoint("BOTTOMRIGHT", -14, 4)
    detailScroll:EnableMouseWheel(true)

    local detailScrollBar = CreateFrame("EventFrame", nil, detailFrame, "MinimalScrollBar")
    detailScrollBar:SetPoint("TOPLEFT", detailScroll, "TOPRIGHT", 2, 0)
    detailScrollBar:SetPoint("BOTTOMLEFT", detailScroll, "BOTTOMRIGHT", 2, 0)
    ScrollUtil.InitScrollFrameWithScrollBar(detailScroll, detailScrollBar)
    O.AutoHideScrollbar(detailScroll, detailScrollBar)

    local detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetWidth(detailFrame:GetWidth() - 28)
    detailScroll:SetScrollChild(detailContent)

    -- Build child groups list
    local childSorted = O.SortedArgs(groupOpt.args)
    local childGroups = {}
    for _, child in ipairs(childSorted) do
        if child.type == "group" then
            childGroups[#childGroups + 1] = child
        end
    end

    -- Detect source-based grouping. When ANY child group declares a
    -- `source`, switch to collapsible-section rendering: one header
    -- per source, children listed under it. Without this, all the
    -- child groups would render flat - fine for short lists but
    -- noisy for wide lists like the BWD Widgets page once a user
    -- has many LDB feeds installed.
    local hasSourceGrouping = false
    for _, child in ipairs(childGroups) do
        if child.source then hasSourceGrouping = true break end
    end

    -- Selection is tracked by the child's `name` string (stable across
    -- list rebuilds when sections are expanded/collapsed). Persisted
    -- on stateHost (window.content) so it survives RefreshOptions
    -- rebuilds. Falls back to nil if the previously selected item
    -- no longer exists in the rebuilt list.
    local selectionState = stateHost[stateKey]
    if type(selectionState) ~= "table" then
        selectionState = {}
        stateHost[stateKey] = selectionState
    end
    local selectedKey = selectionState.selected
    -- Legacy: older sessions stored an integer index. Drop it - the
    -- restore path below will pick the first available group instead.
    if type(selectedKey) ~= "string" then selectedKey = nil end

    -- Per-source collapse state lives in the same persistent state
    -- bucket so it also survives RefreshOptions rebuilds (resets on
    -- /reload, when the entire window goes away).
    selectionState.collapsedSources = selectionState.collapsedSources or {}
    local collapsedSources = selectionState.collapsedSources

    local function GetChildByKey(key)
        if not key then return nil end
        for _, c in ipairs(childGroups) do
            if c.name == key then return c end
        end
    end

    local RenderList  -- forward declared so SelectGroup can rebuild

    local function RenderDetailFor(child)
        O.ClearChildren(detailContent)
        if not child then return end
        -- Lazy detail: pages produced by CreateManagedListPage stash a
        -- `_lazyDetailBuild` closure instead of pre-building the args
        -- table for every item upfront. We evaluate it on first
        -- selection here, then cache the result on the child so
        -- subsequent re-renders (e.g. window resize, RefreshOptions)
        -- don't repeat the work.
        if not child.args and child._lazyDetailBuild then
            child.args = child._lazyDetailBuild()
            child._lazyDetailBuild = nil  -- one-shot
        end
        if child.args then
            local dw = detailContent:GetWidth() - O.PAD
            if dw <= 0 then dw = 360 end
            local bottomY = O.RenderWidgets(detailContent, child.args, dw)
            detailContent:SetHeight(math.abs(bottomY) + O.PAD)
        end
    end

    -- Picking an item updates the selection state and re-renders both
    -- panels. The list rebuild flows the new isSelected flag through
    -- the shared row builder so the gold-gradient highlight follows
    -- the click without needing a separate per-row update path.
    local function SelectGroup(child)
        if not child then return end
        selectedKey = child.name
        selectionState.selected = selectedKey
        RenderList()
        RenderDetailFor(child)
    end

    -- Builds the row spec array O.RenderListRows consumes. Each child
    -- group becomes an "item" row; in source-grouped mode each unique
    -- source becomes a "parent" row preceding its items, with an
    -- indent so children visually nest under their header. Source
    -- parents are selectable (matches User Manual tree behaviour: a
    -- click toggles expansion and marks the header as the active row
    -- with white text). Collapsed sources skip emitting their item
    -- rows.
    local function BuildRowSpecs()
        local rows = {}
        if hasSourceGrouping then
            local bySource, sourceOrder = {}, {}
            for _, child in ipairs(childGroups) do
                local src = child.source or "Other"
                if not bySource[src] then
                    bySource[src] = {}
                    sourceOrder[#sourceOrder + 1] = src
                end
                table.insert(bySource[src], child)
            end
            for _, src in ipairs(sourceOrder) do
                local capturedSrc = src
                local sourceKey   = "__source_" .. capturedSrc
                local collapsed   = collapsedSources[capturedSrc] or false
                -- Source headers are selectable like User Manual tree
                -- parents: a click toggles expansion AND turns the
                -- header text white, matching the User Manual look.
                -- Selection just lives on the row visual; the detail
                -- panel only updates on child clicks (source headers
                -- don't have their own page content), so the previous
                -- child's content stays put until the user picks a
                -- different child.
                rows[#rows + 1] = {
                    key        = sourceKey,
                    label      = capturedSrc,
                    count      = #bySource[capturedSrc],
                    isParent   = true,
                    expanded   = not collapsed,
                    isSelected = (sourceKey == selectedKey),
                    onClick    = function()
                        collapsedSources[capturedSrc] =
                            not collapsedSources[capturedSrc]
                        selectedKey = sourceKey
                        selectionState.selected = selectedKey
                        RenderList()
                    end,
                }
                if not collapsed then
                    for _, child in ipairs(bySource[capturedSrc]) do
                        local capturedChild = child
                        rows[#rows + 1] = {
                            key        = capturedChild.name,
                            label      = capturedChild.name or "?",
                            isParent   = false,
                            isSelected = (capturedChild.name == selectedKey),
                            indent     = 18,  -- nested under section header
                            onClick    = function() SelectGroup(capturedChild) end,
                        }
                    end
                end
            end
        else
            -- Flat list (legacy behaviour for pages without source-tagged
            -- children, e.g. Drawers, Categories). When the wrapper
            -- group exposes onMoveUp / onMoveDown callbacks, every row
            -- gets up/down arrow buttons on the right edge - the topmost
            -- and bottommost rows render their boundary arrow disabled
            -- so users still see the affordance but can't move past
            -- the list edge. Pages without ordering simply don't set
            -- the callbacks and no arrows render.
            local total      = #childGroups
            local onMoveUp   = groupOpt.onMoveUp
            local onMoveDown = groupOpt.onMoveDown
            for idx, child in ipairs(childGroups) do
                local capturedChild = child
                local moveUp, moveDown
                if onMoveUp and idx > 1 then
                    moveUp = function() onMoveUp(capturedChild) end
                end
                if onMoveDown and idx < total then
                    moveDown = function() onMoveDown(capturedChild) end
                end
                rows[#rows + 1] = {
                    key        = capturedChild.name,
                    label      = capturedChild.name or "?",
                    isParent   = false,
                    isSelected = (capturedChild.name == selectedKey),
                    onClick    = function() SelectGroup(capturedChild) end,
                    moveUp     = moveUp,
                    moveDown   = moveDown,
                }
            end
        end
        return rows
    end

    RenderList = function()
        O.ClearChildren(listContent)
        local rows = BuildRowSpecs()
        local _, totalH = O.RenderListRows(listContent, rows, { width = listW - 26 })
        listContent:SetHeight(math.max(totalH or 0, 1))
    end

    RenderList()

    -- Auto-select: restore previous selection or pick the first child
    if #childGroups > 0 then
        C_Timer.After(0, function()
            detailContent:SetWidth(detailFrame:GetWidth() - 28)
            local restore = GetChildByKey(selectedKey) or childGroups[1]
            -- If the restored child sits inside a collapsed source,
            -- expand that source so the user sees their selection.
            if hasSourceGrouping and restore.source
               and collapsedSources[restore.source] then
                collapsedSources[restore.source] = false
                RenderList()
            end
            SelectGroup(restore)
        end)
    end

    detailFrame:SetScript("OnSizeChanged", function(self, w)
        detailContent:SetWidth(w - 28)
        local cur = GetChildByKey(selectedKey)
        if cur then SelectGroup(cur) end
    end)

    return splitFrame
end
