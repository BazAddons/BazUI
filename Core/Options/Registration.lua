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
    -- Sort order: General first, the module's own pages next
    -- (alphabetical), then Global Settings, Profiles, and the User
    -- Manual last so docs sit at the end of every tab strip. Old labels
    -- ("User Guide", "Settings", "Global Options") map to the same slots.
    local function Rank(label)
        if label == "General" or label == "General Settings" or label == "Settings"
            then return 1 end
        if label == "Global Settings" or label == "Global Options"
            then return 600 end
        if label == "Profiles"
            then return 800 end
        if label == "User Manual" or label == "User Guide"
            then return 900 end
        return 500
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

-- Renders one options table into `content` (the scroll child): a single
-- column of widgets, sections as headers, inline groups as a header plus
-- their args, and every non-inline group collected into one picker
-- (dropdown + the selected item's form). Executes that come before the
-- first group become buttons on the picker row.
local function RenderPageContent(content, optionsTable, width, stateHost)
    local contentWidth = math.min(width - O.PAD * 2, O.CONTENT_MAX)
    local args = optionsTable.args or {}
    local sorted = O.SortedArgs(args)
    -- Executes ahead of the first non-inline group become buttons on
    -- the picker row; pages without such a group keep them inline.
    local hasPickers = false
    for _, opt in ipairs(sorted) do
        if opt.type == "group" and not opt.inline and opt.args then hasPickers = true break end
    end
    local y = -O.PAD
    local pickerGroups, pickerButtons = {}, {}
    local seenGroup, first = false, true

    local function Place(widget, h)
        widget:SetPoint("TOPLEFT", content, "TOPLEFT", O.PAD, y)
        widget:Show()
        y = y - h - O.SPACING
        first = false
    end

    for _, opt in ipairs(sorted) do
        if opt.type == "group" and opt.inline then
            if opt.name and opt.name ~= "" then
                if not first then y = y - O.SECTION_GAP end
                Place(O.widgetFactories.header(content, opt, contentWidth))
            end
            if opt.args then
                y = O.RenderWidgets(content, opt.args, contentWidth, nil, y)
                first = false
            end
        elseif opt.type == "group" and opt.args then
            pickerGroups[#pickerGroups + 1] = opt
            seenGroup = true
        elseif opt.type == "execute" and hasPickers and not seenGroup then
            pickerButtons[#pickerButtons + 1] = opt
        elseif not O.IsHidden(opt) then
            local factory = O.widgetFactories[opt.type]
            if factory then
                if opt.type == "header" and not first then y = y - O.SECTION_GAP end
                Place(factory(content, opt, contentWidth))
            end
        end
    end

    if #pickerGroups == 1 then
        local g = pickerGroups[1]
        if g.name and g.name ~= "" then
            if not first then y = y - O.SECTION_GAP end
            Place(O.widgetFactories.header(content, g, contentWidth))
        end
        y = O.RenderPickerGroup(content, g, contentWidth, y, pickerButtons, stateHost)
    elseif #pickerGroups > 1 then
        local host = { args = {}, _key = optionsTable.name or "items", pickerLabel = optionsTable.pickerLabel }
        for i, g in ipairs(pickerGroups) do
            host.args[g._key or g.name or ("group_" .. i)] = g
        end
        if not first then y = y - O.SECTION_GAP end
        y = O.RenderPickerGroup(content, host, contentWidth, y, pickerButtons, stateHost)
    end

    content:SetHeight(math.abs(y) + O.PAD)
end

local function RenderIntoCanvas(container, optionsTable)
    -- Fresh scroll frame and content every render: reusing a frame whose
    -- parent was cleared is the blank-page bug of old.
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
    -- Pickers call this to re-render after a selection change; the
    -- container outlives each render, so selection state lives on it.
    container._bazRefresh = function() RenderIntoCanvas(container, optionsTable) end

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
        RenderPageContent(content, optionsTable, width, container)
        scroll._lastRenderedWidth = width
    end

    local function ResolveWidth()
        local w = scroll:GetWidth() or 0
        if w <= 0 then w = (container:GetWidth() or 0) - 18 end
        return w
    end

    -- Render once the scroll frame has a real width; rendering at zero
    -- width has produced blank pages before.
    local attempts = 0
    local function TryRender()
        attempts = attempts + 1
        if not content:GetParent() then return end
        if attempts > 20 then
            Layout(ResolveWidth())
            return
        end
        local w = ResolveWidth()
        if scroll:GetLeft() ~= nil and w > 0 then
            Layout(w)
            return
        end
        C_Timer.After(0.05, TryRender)
    end
    C_Timer.After(0, TryRender)

    scroll:SetScript("OnSizeChanged", function(_, w)
        if not w or w <= 0 then return end
        content:SetWidth(w)
        if not scroll._lastRenderedWidth or math.abs(w - scroll._lastRenderedWidth) > 1 then
            Layout(w)
        end
    end)
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
