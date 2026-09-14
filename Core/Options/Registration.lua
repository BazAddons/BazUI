-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: Registration & Blizzard Settings integration
--
-- Options live in the standard Options > AddOns panel:
--   * "BazUI" is the addon's category. Its canvas shows BazUI's own pages
--     (General Settings, Profiles, User Manual) as tabs across the top.
--   * Every module is a subcategory under BazUI. Its canvas shows the
--     module's pages the same way. Blizzard's panel nests two levels
--     deep, so module pages become tabs rather than a third level.
--
-- Modules register exactly as before:
--   BazUI:RegisterOptionsTable(key, tableOrFunc)
--   BazUI:AddToSettings(key, label, parentKey)
-- A key with no parentKey is a module (its own subcategory); a key with a
-- parentKey is a page (a tab) inside that module's canvas. Pages render
-- through the same widget factories as always; the panel only supplies
-- the frame they render into.
---------------------------------------------------------------------------

local O = BazUI._Options
local optionsTables = BazUI._optionsTables or {}
BazUI._optionsTables = optionsTables

local ROOT_KEY         = "BazUI"
local TAB_STRIP_HEIGHT = 30
local TAB_GAP          = 2

local rootCategory      -- Blizzard category object for BazUI
local categories = {}   -- [moduleKey] = Blizzard category (root or subcategory)
local canvases   = {}   -- [moduleKey] = canvas frame registered with the panel

---------------------------------------------------------------------------
-- Page ordering
---------------------------------------------------------------------------

-- Returns the ordered pages of one module's canvas. Includes the module's
-- own root entry only when it has no pages or explicitly asks for it via
-- showRoot, so a module normally opens straight onto its first page.
local function GetPagesFor(parentName)
    local parentEntry = optionsTables[parentName]
    local children = {}
    for name, entry in pairs(optionsTables) do
        if entry.parent == parentName and entry.displayName then
            children[#children + 1] = { key = name, label = entry.displayName }
        end
    end
    -- Sort order:
    --   1. "General Settings" (the page people come here for)
    --   2. "User Manual"      (docs one tab over)
    --   3. "Global Settings"  (overrides that apply to every module)
    --   4. Custom sub-categories (alphabetical)
    --   5. "Profiles" last
    -- Old labels ("User Guide", "Settings", "Global Options") still
    -- resolve to the same slot so addons that haven't been renamed
    -- don't break their ordering.
    local function Rank(label)
        if label == "General Settings" or label == "Settings"
            then return 1 end
        if label == "User Manual" or label == "User Guide"
            then return 2 end
        if label == "Global Settings" or label == "Global Options"
            then return 3 end
        if label == "Profiles"
            then return 999 end
        return 500  -- custom sub-categories, sorted alphabetically among themselves
    end
    table.sort(children, function(a, b)
        local ra, rb = Rank(a.label), Rank(b.label)
        if ra ~= rb then return ra < rb end
        return a.label < b.label
    end)

    local list = {}
    -- Show the parent (landing) entry only when:
    --   * it has no children to navigate to, OR
    --   * the parent explicitly opts in via showRoot = true
    -- This means every addon defaults to "click tab -> land on first
    -- sub-category" with no separate landing page in the way.
    -- An explicit hideRoot still wins over showRoot.
    local includeParent = parentEntry
        and not parentEntry.hideRoot
        and (#children == 0 or parentEntry.showRoot)
    if includeParent then
        list[#list + 1] = {
            key = parentName,
            label = parentEntry.displayName or parentName,
            isRoot = true,
        }
    end
    for _, c in ipairs(children) do list[#list + 1] = c end
    return list
end

---------------------------------------------------------------------------
-- Content rendering (shared with the list/detail pattern)
---------------------------------------------------------------------------

local function CreateTwoPanelLayout(container, optionsTable)
    local args = optionsTable.args or {}
    local contentWidth = container:GetWidth() or 600

    -- Split args into: topArgs, groupArgs, executeArgs
    local topArgs, groupArgs, executeArgs = {}, {}, {}
    local sortedRoot = O.SortedArgs(args)
    local hasTwoPanelGroups = false

    for _, opt in ipairs(sortedRoot) do
        if opt.type == "group" and opt.inline then
            topArgs[#topArgs + 1] = opt
        elseif opt.type == "group" and not opt.inline and opt.args then
            groupArgs[#groupArgs + 1] = opt
            hasTwoPanelGroups = true
        elseif opt.type == "execute" and not hasTwoPanelGroups then
            executeArgs[#executeArgs + 1] = opt
        else
            topArgs[#topArgs + 1] = opt
        end
    end

    local yOffset = -O.PAD

    -- Shared title bar (same one the User Manual uses) - addon icon,
    -- gold title, version, horizontal rule.
    local titleFrame, headerHeight = O.BuildTitleBar(container, {
        title        = optionsTable.name,
        addonName    = optionsTable.name,
        contentWidth = contentWidth,
    })
    titleFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    yOffset = yOffset - headerHeight

    -- Top-level items
    local hasTopGroups = false
    for _, opt in ipairs(topArgs) do
        if opt.type == "group" and opt.inline then hasTopGroups = true; break end
    end

    if not hasTwoPanelGroups and not hasTopGroups then
        yOffset = O.RenderWidgets(container, args, contentWidth, nil, yOffset)
    else
        for _, opt in ipairs(topArgs) do
            if opt.type == "group" and opt.inline then
                local hdr, hh = O.widgetFactories.header(container, opt, contentWidth - O.PAD * 2)
                hdr:SetPoint("TOPLEFT", container, "TOPLEFT", O.PAD, yOffset)
                hdr:Show()
                yOffset = yOffset - hh - O.SPACING
                if opt.args then
                    yOffset = O.RenderWidgets(container, opt.args, contentWidth - O.PAD * 2, opt.columns, yOffset)
                end
            elseif opt.type == "group" then
                local hdr, hh = O.widgetFactories.header(container, opt, contentWidth - O.PAD * 2)
                hdr:SetPoint("TOPLEFT", container, "TOPLEFT", O.PAD, yOffset)
                hdr:Show()
                yOffset = yOffset - hh - O.SPACING
                if opt.args then
                    yOffset = O.RenderWidgets(container, opt.args, contentWidth - O.PAD * 2, opt.columns, yOffset)
                end
            elseif opt.type ~= "group" then
                local factory = O.widgetFactories[opt.type]
                if factory then
                    local widget, h = factory(container, opt, contentWidth - O.PAD * 2)
                    widget:SetPoint("TOPLEFT", container, "TOPLEFT", O.PAD, yOffset)
                    widget:Show()
                    yOffset = yOffset - h - O.SPACING
                end
            end
        end
    end

    -- Two-panel groups (list/detail). Two shapes are supported:
    --
    --   Wrapper shape (BWD Drawers, BazBars Bars):
    --     args = { drawers = { type="group", name="", args = {
    --       drawer_1 = ..., drawer_2 = ...
    --     } } }
    --   The single top-level group's `args` ARE the list rows.
    --
    --   Sibling shape (BazBags Categories):
    --     args = { cat_equipment = { type="group", name="Equipment", args=...},
    --              cat_consumables = { ... }, ... }
    --   Multiple top-level groups, each becomes a list row directly.
    --
    -- The wrapper-shape path is preserved for backwards compatibility.
    -- The sibling-shape path used to call BuildListDetailPanel once per
    -- group, stacking N panels on top of each other - fixed by wrapping
    -- the groups in a synthetic host so BuildListDetailPanel sees them
    -- as a single unified list.
    if #groupArgs == 1 then
        local groupOpt = groupArgs[1]
        if groupOpt.name and groupOpt.name ~= "" then
            local hdr, hh = O.widgetFactories.header(container, groupOpt, contentWidth - O.PAD * 2)
            hdr:SetPoint("TOPLEFT", container, "TOPLEFT", O.PAD, yOffset)
            hdr:Show()
            yOffset = yOffset - hh - 4
        end
        O.BuildListDetailPanel(container, groupOpt, contentWidth, yOffset, executeArgs)
    elseif #groupArgs > 1 then
        local hostGroup = { args = {} }
        for i, g in ipairs(groupArgs) do
            hostGroup.args[g._key or g.name or ("group_" .. i)] = g
        end
        O.BuildListDetailPanel(container, hostGroup, contentWidth, yOffset, executeArgs)
    end

    container:SetHeight(math.abs(yOffset) + O.PAD)
end

local function RenderIntoCanvas(container, optionsTable)
    local hasTwoPanelGroups = false
    if optionsTable.args then
        for _, opt in pairs(optionsTable.args) do
            if type(opt) == "table" and opt.type == "group" and not opt.inline and opt.args then
                hasTwoPanelGroups = true
                break
            end
        end
    end

    -- Always discard any previous render target and create a fresh
    -- one. The SelectSubcategory helper clears window.content's
    -- children (SetParent(nil)) before calling us, which leaves our
    -- cached container._renderTarget / container._scrollFrame fields
    -- pointing to orphaned frames. Reusing an orphaned frame is the
    -- blank-page bug: GetParent() returns nil, GetLeft() stays nil,
    -- and our polling TryRender exits on the parent check - so
    -- Layout() never runs. Starting fresh every render is cheap
    -- (just a Frame) and bypasses the problem entirely.
    if container._scrollFrame then
        container._scrollFrame:Hide()
        container._scrollFrame:SetParent(nil)
        container._scrollFrame = nil
    end
    if container._renderTarget then
        container._renderTarget:Hide()
        container._renderTarget:SetParent(nil)
        container._renderTarget = nil
    end

    if hasTwoPanelGroups then
        container._renderTarget = CreateFrame("Frame", nil, container)
        container._renderTarget:SetAllPoints()
        local renderTarget = container._renderTarget

        local function Layout()
            O.ClearChildren(renderTarget)
            CreateTwoPanelLayout(renderTarget, optionsTable)
            renderTarget._lastRenderedWidth = renderTarget:GetWidth() or 0
        end

        -- Wait for the layout engine to resolve the render target's
        -- size before rendering. GetLeft() is nil until a frame has
        -- been laid out. We *don't* render eagerly first - doing so
        -- at a zero width has caused corrupted render state we can't
        -- recover from. Single deferred render at known-good width is
        -- the most reliable path we've found.
        local attempts = 0
        local function TryRender()
            attempts = attempts + 1
            if not renderTarget:GetParent() then return end
            if attempts > 20 then
                -- Give up after ~1s and render anyway so the user
                -- doesn't stare at a permanent blank screen.
                Layout()
                return
            end
            local laidOut = renderTarget:GetLeft() ~= nil
            local w = renderTarget:GetWidth() or 0
            if laidOut and w > 0 then
                Layout()
                return
            end
            C_Timer.After(0.05, TryRender)
        end
        C_Timer.After(0, TryRender)

        -- Long-term safety: any future resize re-flows the content
        renderTarget:SetScript("OnSizeChanged", function(self, w)
            if not w or w <= 0 then return end
            if math.abs(w - (renderTarget._lastRenderedWidth or 0)) > 1 then
                Layout()
            end
        end)
    else
        local scroll = CreateFrame("ScrollFrame", nil, container)
        scroll:SetPoint("TOPLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", -18, 0)
        scroll:EnableMouseWheel(true)
        container._scrollFrame = scroll

        local scrollBar = CreateFrame("EventFrame", nil, container, "MinimalScrollBar")
        scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
        scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
        ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)
        O.AutoHideScrollbar(scroll, scrollBar)

        local content = CreateFrame("Frame", nil, scroll)
        scroll:SetScrollChild(content)
        container._renderTarget = content

        local function Layout(width)
            if not width or width <= 0 then return end
            content:SetWidth(width)
            O.ClearChildren(content)
            CreateTwoPanelLayout(content, optionsTable)
            -- Track on the SCROLL (per-render fresh frame), not on the
            -- container (shared across renders). Avoids stale guard
            -- preventing legitimate re-layouts on next navigation.
            scroll._lastRenderedWidth = width
        end

        local function ResolveWidth()
            local w = scroll:GetWidth() or 0
            if w <= 0 then w = (container:GetWidth() or 0) - 18 end
            return w
        end

        -- Wait for the scroll frame to be laid out, then render once
        -- at the resolved width. Avoid rendering eagerly at zero width
        -- - it's been a consistent source of blank-page bugs.
        local attempts = 0
        local function TryRender()
            attempts = attempts + 1
            if not content:GetParent() then return end
            if attempts > 20 then
                Layout(ResolveWidth())  -- last-ditch
                return
            end
            local laidOut = scroll:GetLeft() ~= nil
            local w = ResolveWidth()
            if laidOut and w > 0 then
                Layout(w)
                return
            end
            C_Timer.After(0.05, TryRender)
        end
        C_Timer.After(0, TryRender)

        -- Long-term: any future size change re-flows the content
        scroll:SetScript("OnSizeChanged", function(self, w)
            if not w or w <= 0 then return end
            content:SetWidth(w)
            if not scroll._lastRenderedWidth
               or math.abs(w - scroll._lastRenderedWidth) > 1 then
                Layout(w)
            end
        end)
    end
end

BazUI._RenderIntoCanvas = RenderIntoCanvas

---------------------------------------------------------------------------
-- Canvases: one frame per module, pages as tabs across the top
---------------------------------------------------------------------------

local function RenderPage(canvas, key)
    if not key then return end
    local entry = optionsTables[key]
    if not entry then return end
    canvas.activeKey = key

    for pageKey, tab in pairs(canvas.tabs) do
        if pageKey == key then
            PanelTemplates_SelectTab(tab)
        else
            PanelTemplates_DeselectTab(tab)
        end
    end

    O.ClearChildren(canvas.content)

    -- A customRender takes the whole content area (the User Manual's
    -- tree layout does this).
    if type(entry.customRender) == "function" then
        entry.customRender(canvas.content)
        return
    end

    local tbl = entry.func
    if type(tbl) == "function" then tbl = tbl() end
    if tbl then
        RenderIntoCanvas(canvas.content, tbl)
    end
end

local function RebuildTabs(canvas)
    local pages = GetPagesFor(canvas.moduleKey)
    for _, tab in pairs(canvas.tabs) do tab:Hide() end
    canvas.tabs = {}

    local strip = canvas.tabStrip
    if #pages <= 1 then
        -- Nothing to switch between: give the page the whole canvas.
        strip:Hide()
        canvas.content:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
    else
        strip:Show()
        canvas.content:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -6)
        local x = 4
        for i, page in ipairs(pages) do
            local tab = canvas.tabPool[i]
            if not tab then
                tab = CreateFrame("Button", nil, strip, "PanelTopTabButtonTemplate")
                canvas.tabPool[i] = tab
            end
            tab:SetID(i)
            tab:SetText(page.label)
            tab:ClearAllPoints()
            tab:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", x, 0)
            PanelTemplates_TabResize(tab, 0)
            local pageKey = page.key
            tab:SetScript("OnClick", function()
                PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
                RenderPage(canvas, pageKey)
            end)
            tab:Show()
            canvas.tabs[pageKey] = tab
            x = x + (tab:GetWidth() or 0) + TAB_GAP
        end
    end

    -- Keep a valid active page; default to the first.
    local valid = false
    for _, page in ipairs(pages) do
        if page.key == canvas.activeKey then valid = true end
    end
    if not valid then
        canvas.activeKey = pages[1] and pages[1].key or canvas.moduleKey
    end
    return pages
end

local function CreateCanvas(moduleKey)
    -- The panel parents and anchors this frame itself when the category is
    -- selected, and un-parents it when another category takes over.
    local canvas = CreateFrame("Frame")
    canvas:Hide()
    canvas.moduleKey = moduleKey
    canvas.tabs      = {}
    canvas.tabPool   = {}

    local strip = CreateFrame("Frame", nil, canvas)
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", 0, 0)
    strip:SetHeight(TAB_STRIP_HEIGHT)
    canvas.tabStrip = strip

    local content = CreateFrame("Frame", nil, canvas)
    content:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -6)
    content:SetPoint("BOTTOMRIGHT", 0, 0)
    canvas.content = content

    canvas:SetScript("OnShow", function(self)
        RebuildTabs(self)
        RenderPage(self, self.pendingKey or self.activeKey)
        self.pendingKey = nil
    end)
    canvas:SetScript("OnHide", function(self)
        O.ClearChildren(self.content)
    end)

    -- Hooks the Settings panel calls on canvas frames. Our settings apply
    -- as they change, so Okay / Defaults have nothing to do; a refresh
    -- re-renders the visible page so it shows current values.
    function canvas:OnRefresh()
        if self:IsShown() and self.activeKey then
            RenderPage(self, self.activeKey)
        end
    end
    function canvas:OnCommit() end
    function canvas:OnDefault() end

    return canvas
end

local function EnsureRoot()
    if rootCategory then return rootCategory end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return nil
    end
    local canvas = CreateCanvas(ROOT_KEY)
    canvases[ROOT_KEY] = canvas
    rootCategory = Settings.RegisterCanvasLayoutCategory(canvas, "BazUI")
    categories[ROOT_KEY] = rootCategory
    Settings.RegisterAddOnCategory(rootCategory)
    return rootCategory
end

local function EnsureModule(moduleKey)
    if moduleKey == ROOT_KEY then return EnsureRoot() end
    if categories[moduleKey] then return categories[moduleKey] end
    local root = EnsureRoot()
    if not root or not Settings.RegisterCanvasLayoutSubcategory then return nil end
    -- A module's user guide registers at file load, before the module's
    -- own landing page does at login, so the category can be created
    -- before a display name exists. Fall back to the module's title
    -- rather than its key ("Micro Menu", not "MicroMenu").
    local entry = optionsTables[moduleKey]
    local mod = BazUI.GetModule and BazUI:GetModule(moduleKey)
    local label = (entry and entry.displayName) or (mod and mod.config and mod.config.title) or moduleKey
    local canvas = CreateCanvas(moduleKey)
    canvases[moduleKey] = canvas
    local sub = Settings.RegisterCanvasLayoutSubcategory(root, canvas, label)
    categories[moduleKey] = sub
    return sub
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function BazUI:RegisterOptionsTable(key, optionsTableOrFunc)
    optionsTables[key] = optionsTables[key] or {}
    optionsTables[key].func = optionsTableOrFunc
end

-- AddToSettings(key, displayName, parentKey)
--   key         = unique key (used with RegisterOptionsTable)
--   displayName = subcategory name (modules) or tab label (pages)
--   parentKey   = optional; when given, key is a page of that module
function BazUI:AddToSettings(key, displayName, parentKey)
    local entry = optionsTables[key]
    if not entry then return end
    entry.displayName = displayName or key
    entry.parent = parentKey

    local moduleKey = parentKey or key
    EnsureModule(moduleKey)

    local canvas = canvases[moduleKey]
    if canvas and canvas:IsShown() then
        RebuildTabs(canvas)
        RenderPage(canvas, canvas.activeKey)
    end
end

-- Open the Settings panel on a module, or on one page of a module.
function BazUI:OpenOptionsPanel(key)
    key = key or ROOT_KEY
    local entry = optionsTables[key]
    local moduleKey = (entry and entry.parent) or key
    local category = categories[moduleKey] or EnsureModule(moduleKey) or rootCategory
    if not category or not Settings.OpenToCategory then return end

    local canvas = canvases[moduleKey]
    local wantsPage = entry and entry.parent and canvas
    if wantsPage then canvas.pendingKey = key end

    Settings.OpenToCategory(category:GetID())

    -- Already showing this canvas: OnShow won't fire, switch the tab now.
    if wantsPage and canvas:IsShown() then
        canvas.pendingKey = nil
        RenderPage(canvas, key)
    end
end

function BazUI:OpenSettings(key)
    return self:OpenOptionsPanel(key)
end

-- Re-render a page if it is the one currently on screen.
function BazUI:RefreshOptions(key)
    local entry = optionsTables[key]
    if not entry then return end
    local canvas = canvases[entry.parent or key]
    if canvas and canvas:IsShown() and canvas.activeKey == key then
        RenderPage(canvas, key)
    end
end

-- The Blizzard category for a module, for callers that want to open the
-- panel themselves.
function BazUI:GetOptionsCategory(moduleKey)
    return categories[moduleKey or ROOT_KEY]
end
