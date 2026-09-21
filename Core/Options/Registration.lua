-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: Registration & Blizzard Settings integration
--
-- Options live in the standard Options > AddOns panel:
--   * "BazUI" is the addon's category. Its canvas shows BazUI's own pages
--     (General, Skin, Profiles) as tabs across the top.
--   * Every module is a subcategory under BazUI, and so is the User
--     Manual, which is a module's worth of pages without a module. Each
--     canvas shows its pages the same way: Blizzard's panel nests two
--     levels deep, so pages become tabs rather than a third level.
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
-- Air between a pinned header and the page that scrolls under it, and
-- between the controls sitting side by side in it.
local PINNED_GAP       = 10
local PINNED_ROW_GAP   = 16
local TAB_GAP          = 16
local TAB_INSET        = 4
local TAB_HEIGHT       = 24

local rootCategory      -- Blizzard category object for BazUI
local categories = {}   -- [moduleKey] = Blizzard category (root or subcategory)
local canvases   = {}   -- [moduleKey] = canvas frame registered with the panel

---------------------------------------------------------------------------
-- Page ordering
---------------------------------------------------------------------------

-- Returns the ordered pages of one module's canvas. The module's own
-- entry is included only when it has no pages, so a module normally
-- opens straight onto its first page.
local function GetPagesFor(parentName)
    local parentEntry = optionsTables[parentName]
    local children = {}
    for name, entry in pairs(optionsTables) do
        if entry.parent == parentName and entry.displayName then
            children[#children + 1] = { key = name, label = entry.displayName, order = entry.order }
        end
    end
    -- Sort order: General first, the module's own pages next (by the
    -- order given to AddToSettings, else alphabetical), then Global
    -- Settings, Profiles, and the User Manual last so docs sit at the
    -- end of every tab strip. Old labels ("User Guide", "Settings",
    -- "Global Options") map to the same slots.
    local function Rank(label, order)
        if order then return 100 + order end
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
        local ra, rb = Rank(a.label, a.order), Rank(b.label, b.order)
        if ra ~= rb then return ra < rb end
        return a.label < b.label
    end)

    local list = {}
    -- A module with pages opens straight onto the first one; its own
    -- entry renders only when it has no pages to show instead.
    if parentEntry and #children == 0 then
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

    -- `opt` is optional: a header placed for a group has no block of
    -- its own to be spaced against, and takes O.SECTION_GAP above
    -- instead, which its caller has already applied.
    local function Place(widget, h, opt)
        y = y - O.MarginTop(opt, first)
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
                local widget, h = factory(content, opt, contentWidth)
                Place(widget, h, opt)
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

-- A pinned header: the controls that act on the whole page rather than
-- on one row of it.
--
-- A page of twenty switches puts "turn them all on" and "forget every
-- position" at the bottom, where they are the two things you have to
-- scroll past everything else to reach - and they are the two that have
-- nothing to do with any particular row. Pinned, they sit above the list
-- and stay there while it scrolls.
--
-- Rendered by the same widget factories as everything else, into a frame
-- of its own, so a pinned toggle is the same toggle it would be further
-- down the page.
--
-- Across rather than down. A header is a strip, and a strip that stacks
-- is a header eating the list it is meant to sit above - two controls
-- with a line of description each came to four lines of chrome before
-- the first switch. Side by side they come to one. Which means a pinned
-- control wants a label that says the whole thing, because there is no
-- room under it for a second line explaining the first.
local function RenderPinned(pinned, args, width)
    O.ClearChildren(pinned)

    local row = {}
    for _, opt in ipairs(O.SortedArgs(args)) do
        if not O.IsHidden(opt) and O.widgetFactories[opt.type] then
            row[#row + 1] = opt
        end
    end

    local total = math.min(width - O.PAD * 2, O.CONTENT_MAX)
    local count = math.max(#row, 1)
    local each  = math.floor((total - PINNED_ROW_GAP * (count - 1)) / count)

    local h, x = 0, O.PAD
    for _, opt in ipairs(row) do
        local widget, wh = O.widgetFactories[opt.type](pinned, opt, each)
        widget:SetPoint("TOPLEFT", pinned, "TOPLEFT", x, -O.PAD)
        widget:Show()
        if (wh or 0) > h then h = wh end
        x = x + each + PINNED_ROW_GAP
    end
    pinned:SetHeight(h + O.PAD * 2)

    -- The rule that says the list starts below here. Drawn after the
    -- clear rather than once when the frame was made, because
    -- ClearChildren takes a frame's own regions with it.
    local rule = pinned:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", O.PAD, 0)
    rule:SetPoint("BOTTOMRIGHT", -O.PAD, 0)
    rule:SetColorTexture(unpack(O.DIVIDER_COLOR))
end

local function RenderIntoCanvas(container, optionsTable)
    -- Where the reader had got to. A render builds a new scroll frame, so
    -- without this, changing one setting three quarters of the way down a
    -- page throws you back to the top of it - and the setting you just
    -- changed is the one thing you wanted to still be looking at.
    local keepOffset = container._scrollFrame
        and container._scrollFrame:GetVerticalScroll() or 0

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
    if container._pinned then
        container._pinned:Hide()
        container._pinned:SetParent(nil)
        container._pinned = nil
    end
    -- Pickers call this to re-render after a selection change; the
    -- container outlives each render, so selection state lives on it.
    container._bazRefresh = function() RenderIntoCanvas(container, optionsTable) end

    local pinnedArgs = optionsTable.pinned
    if pinnedArgs and not next(pinnedArgs) then pinnedArgs = nil end

    local pinned
    if pinnedArgs then
        pinned = CreateFrame("Frame", nil, container)
        pinned:SetPoint("TOPLEFT", 0, 0)
        pinned:SetPoint("TOPRIGHT", -18, 0)
        -- Something to sit on until the first layout measures it.
        pinned:SetHeight(1)
        container._pinned = pinned
    end

    local scroll = CreateFrame("ScrollFrame", nil, container)
    if pinned then
        scroll:SetPoint("TOPLEFT", pinned, "BOTTOMLEFT", 0, -PINNED_GAP)
    else
        scroll:SetPoint("TOPLEFT", 0, 0)
    end
    scroll:SetPoint("BOTTOMRIGHT", -18, 0)
    scroll:EnableMouseWheel(true)
    container._scrollFrame = scroll

    local scrollBar = CreateFrame("EventFrame", nil, container, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)
    BazUI.Skin.Theme.AutoFadeScrollBar(scrollBar, scroll)
    O.AutoHideScrollbar(scroll, scrollBar)

    local content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    container._renderTarget = content

    -- Put the reader back where they were, once the content is tall
    -- enough for the offset to mean anything. Through the scroll bar as
    -- well as the frame, so the thumb agrees with what is on screen.
    local function RestoreScroll(offset)
        if not offset or offset <= 0 then return end
        local range = (content:GetHeight() or 0) - (scroll:GetHeight() or 0)
        if range <= 0 then return end
        local clamped = math.min(offset, range)
        scroll:SetVerticalScroll(clamped)
        if scrollBar.SetScrollPercentage then
            scrollBar:SetScrollPercentage(clamped / range)
        end
    end

    local function Layout(width)
        if not width or width <= 0 then return end
        -- The header first: the scroll frame hangs off its bottom edge,
        -- so its height has to be right before the page below is
        -- measured against what is left.
        if pinned then RenderPinned(pinned, pinnedArgs, width) end
        content:SetWidth(width)
        O.ClearChildren(content)
        RenderPageContent(content, optionsTable, width, container)
        scroll._lastRenderedWidth = width

        -- Only the first layout after a rebuild, and a frame later: the
        -- scroll frame has not worked out its range until then.
        if keepOffset and keepOffset > 0 then
            local offset = keepOffset
            keepOffset = nil
            C_Timer.After(0, function()
                if content:GetParent() then RestoreScroll(offset) end
            end)
        end
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

---------------------------------------------------------------------------
-- Canvases: one frame per module, pages as tabs across the top
---------------------------------------------------------------------------

-- Whether a page is being drawn right now. See RefreshOptions.
local rendering = false

local function RenderPage(canvas, key)
    if not key then return end
    local entry = optionsTables[key]
    if not entry then return end
    canvas.activeKey = key
    rendering = true

    local tabID = canvas.tabIDs and canvas.tabIDs[key]
    if tabID and canvas.tabStrip.selectedTabID ~= tabID then
        canvas.tabStrip:SetTabVisuallySelected(tabID)
        canvas.tabStrip.selectedTabID = tabID
    end

    O.ClearChildren(canvas.content)

    -- A customRender takes the whole content area (the User Manual's
    -- tree layout does this).
    if type(entry.customRender) == "function" then
        entry.customRender(canvas.content)
        rendering = false
        return
    end

    local tbl = entry.func
    if type(tbl) == "function" then tbl = tbl() end
    if tbl then
        RenderIntoCanvas(canvas.content, tbl)
    end
    rendering = false
end

local function RebuildTabs(canvas)
    local pages = GetPagesFor(canvas.moduleKey)
    local strip = canvas.tabStrip
    strip:ClearTabs()
    canvas.tabIDs  = {}
    canvas.tabKeys = {}

    if #pages <= 1 then
        -- Nothing to switch between: give the page the whole canvas.
        strip:Hide()
        canvas.content:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
    else
        strip:Show()
        for _, page in ipairs(pages) do
            local tabID = strip:AddTab(page.label)
            canvas.tabIDs[page.key] = tabID
            canvas.tabKeys[tabID]   = page.key
        end

        -- Wrap rather than run off the right edge. The User Manual has a
        -- tab per module, which is more than fits on one row, and a tab
        -- you cannot see is a page you cannot reach.
        local width = (canvas:GetWidth() or 0) - TAB_INSET * 2
        strip:SetWrapWidth(width > 0 and width or nil)
        strip:Layout()

        -- Below however many rows that came to, rather than below one.
        canvas.content:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0,
            -((strip:GetHeight() or TAB_HEIGHT) + 12))
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
    canvas.tabIDs    = {}
    canvas.tabKeys   = {}

    -- The suite's tab strip (Core/TabStrip.lua) in the same underline
    -- look the notification center wears: these sit on a solid panel, so
    -- they need no plate of their own. It sizes itself to its tabs, so
    -- only the anchor is set.
    local strip = BazUI.CreateTabStrip(nil, canvas, {
        style = "underline",
        inset = TAB_INSET,
        spacing = TAB_GAP,
        tabHeight = TAB_HEIGHT,
        dividerParent = canvas,
        tabSelectSound = SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB,
    })
    strip:SetPoint("TOPLEFT", TAB_INSET, -2)
    strip:SetTabSelectedCallback(function(tabID, isUserAction)
        local key = canvas.tabKeys and canvas.tabKeys[tabID]
        if key and isUserAction then RenderPage(canvas, key) end
    end)
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

-- AddToSettings(key, displayName, parentKey, order)
--   key         = unique key (used with RegisterOptionsTable)
--   displayName = subcategory name (modules) or tab label (pages)
--   parentKey   = optional; when given, key is a page of that module
--   order       = optional; places the page among the module's own
--                 pages (after General, before the User Manual)
function BazUI:AddToSettings(key, displayName, parentKey, order)
    local entry = optionsTables[key]
    if not entry then return end
    entry.displayName = displayName or key
    entry.parent = parentKey
    entry.order = order

    local moduleKey = parentKey or key

    -- A module that is switched off adds no pages. Settings for
    -- something that is not running are settings that do nothing, and
    -- the switch that brings it back lives on the General page rather
    -- than inside the module it turns off.
    if BazUI.addons and BazUI.addons[moduleKey]
        and BazUI.IsModuleEnabled and not BazUI:IsModuleEnabled(moduleKey) then
        return
    end

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

-- Re-render whatever page is on screen, whichever it is.
--
-- A page is a readout of current values, and one setting can change
-- another: the chat window's unified fade mode sets the background and
-- tab modes along with itself. Without this the two dropdowns beside it
-- went on showing what they used to say until the window was closed and
-- opened again.
--
-- Whatever is shown, rather than a named page, because the setting that
-- changed does not know which page is displaying it - the same spec
-- feeds the options window and the Edit Mode popup.
--
-- Deferred, and only once however many settings changed. This runs from
-- inside a widget's own set handler, and rendering replaces that widget:
-- a dropdown would be pulled out from under the menu callback that is
-- still running.
local repaintQueued

function BazUI:RefreshVisibleOptions()
    if repaintQueued then return end
    repaintQueued = true
    C_Timer.After(0, function()
        repaintQueued = false
        for _, canvas in pairs(canvases) do
            if canvas:IsShown() and canvas.activeKey then
                RenderPage(canvas, canvas.activeKey)
            end
        end
    end)
end

-- Re-render a page if it is the one currently on screen.
-- Draw this page again, once whatever is drawing has finished.
--
-- A button's own handler asking for a redraw is a redraw inside the
-- render that drew the button. Done there and then, the new page is
-- built and placed - and then the outer render carries on from where it
-- was interrupted, finishing its pass with the frames and the options
-- table it captured before the click. The stale pass is the one left on
-- screen, and everything the handler just did appears not to have
-- happened: a new drawer is made, the page redrawn around it, and then
-- painted over by the page as it was a moment earlier.
--
-- So a refresh asked for mid-render waits a frame. By then the outer
-- pass has finished and there is nothing left to overwrite it.
function BazUI:RefreshOptions(key)
    local entry = optionsTables[key]
    if not entry then return end
    local canvas = canvases[entry.parent or key]
    if not (canvas and canvas:IsShown() and canvas.activeKey == key) then return end

    if rendering then
        C_Timer.After(0, function() BazUI:RefreshOptions(key) end)
        return
    end
    RenderPage(canvas, key)
end
