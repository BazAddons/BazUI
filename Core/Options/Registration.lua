-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: Registration & Window
--
-- Provides the BazUI options window - a large standalone frame with:
--   * Bottom tabs, one per top-level Baz addon
--   * Left sidebar, one item per sub-category of the active addon
--   * Content area on the right
--
-- Addons register via BazUI:RegisterOptionsTable() and
-- BazUI:AddToSettings(). All options are displayed inside BazUI's
-- window - no longer registered with Blizzard's Settings panel.
---------------------------------------------------------------------------

local O = BazUI._Options
local optionsTables = BazUI._optionsTables or {}
BazUI._optionsTables = optionsTables

local window            -- the standalone window (created on demand)
local activeAddon       -- name of the currently active bottom tab
local activeSubcategory -- name of the currently active left sidebar item
local bottomTabs = {}   -- [addonName] = tab frame
local sidebarRows = {}  -- [entryKey] = row frame

local WINDOW_WIDTH   = 1618
local WINDOW_HEIGHT  = 883
local TAB_HEIGHT     = 32
local SIDEBAR_WIDTH  = 200
local SIDEBAR_ROW_H  = 28

---------------------------------------------------------------------------
-- Layout helpers
---------------------------------------------------------------------------

-- Returns a sorted array of addon entries that are top-level (no parent).
-- These get bottom tabs in the window.
local function GetTopLevelEntries()
    local entries = {}
    for name, entry in pairs(optionsTables) do
        if not entry.parent and entry.displayName then
            entries[#entries + 1] = { name = name, entry = entry }
        end
    end
    -- BazUI always first, User Manual always last, rest alphabetical
    table.sort(entries, function(a, b)
        if a.name == "BazUI" then return true end
        if b.name == "BazUI" then return false end
        if a.name == "UserManual" then return false end
        if b.name == "UserManual" then return true end
        return a.name < b.name
    end)
    return entries
end

-- Returns a sorted array of sub-category entries for a given parent.
-- Includes the parent itself as the first entry (landing page).
local function GetSubcategoriesFor(parentName)
    local parentEntry = optionsTables[parentName]
    local children = {}
    for name, entry in pairs(optionsTables) do
        if entry.parent == parentName and entry.displayName then
            children[#children + 1] = { key = name, label = entry.displayName }
        end
    end
    -- Sort order:
    --   1. "User Manual"      (docs up top so new users find them first)
    --   2. "General Settings" (main settings page)
    --   3. "Global Settings"  (overrides that apply to every module)
    --   4. Custom sub-categories (alphabetical)
    --   5. "Profiles" last
    -- Old labels ("User Guide", "Settings", "Global Options") still
    -- resolve to the same slot so addons that haven't been renamed
    -- don't break their ordering.
    local function Rank(label)
        if label == "User Manual" or label == "User Guide"
            then return 1 end
        if label == "General Settings" or label == "Settings"
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
-- Content rendering (reused from list/detail pattern)
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
-- Window construction
---------------------------------------------------------------------------

local function SelectSubcategory(key)
    activeSubcategory = key
    if not window then return end
    -- Tag the moment of selection so the persistent memory log shows
    -- which sub-page the user navigated to. Helpful for finding
    -- "User Manual click was the spike trigger" type insights.
    if BazUI.MarkMemoryEvent then
        BazUI:MarkMemoryEvent("subcat_select", key)
        BazUI:MarkMemoryEvent("phase", "subcat:" .. tostring(key) .. ":start")
    end

    -- Update sidebar highlights. Uses the same gold-gradient
    -- highlight + white-on-selected text the sub-lists use, so the
    -- main left sidebar visually matches the right-panel list. The
    -- old solid-blue LIST_SELECTED fill stuck out as the only place
    -- in the suite that didn't follow the gold-gradient pattern.
    for entryKey, row in pairs(sidebarRows) do
        local isSel = (entryKey == key)
        O.ShowHighlightGroup(row.hlGroup, isSel)
        if isSel then
            row.text:SetTextColor(1, 1, 1)         -- white when selected
            row.text:SetAlpha(1.0)
        else
            row.text:SetTextColor(unpack(O.GOLD))  -- gold otherwise
            row.text:SetAlpha(0.75)
        end
    end

    -- Render the selected entry into content area
    local entry = optionsTables[key]
    if not entry then return end
    O.ClearChildren(window.content)

    -- A customRender function takes full control of the content panel.
    -- Used by the User Manual to render its own tree-based layout.
    if type(entry.customRender) == "function" then
        if BazUI.MarkMemoryEvent then
            BazUI:MarkMemoryEvent("phase", "subcat:" .. key .. ":before-customRender")
        end
        entry.customRender(window.content)
        if BazUI.MarkMemoryEvent then
            BazUI:MarkMemoryEvent("phase", "subcat:" .. key .. ":after-customRender")
        end
        return
    end

    if BazUI.MarkMemoryEvent then
        BazUI:MarkMemoryEvent("phase", "subcat:" .. key .. ":before-funcEval")
    end
    local tbl = entry.func
    if type(tbl) == "function" then tbl = tbl() end
    if BazUI.MarkMemoryEvent then
        BazUI:MarkMemoryEvent("phase", "subcat:" .. key .. ":after-funcEval")
    end
    if tbl then
        if BazUI.MarkMemoryEvent then
            BazUI:MarkMemoryEvent("phase", "subcat:" .. key .. ":before-RenderIntoCanvas")
        end
        RenderIntoCanvas(window.content, tbl)
        if BazUI.MarkMemoryEvent then
            BazUI:MarkMemoryEvent("phase", "subcat:" .. key .. ":after-RenderIntoCanvas")
        end
    end
end

local function RenderSidebar()
    if not window then return end
    O.ClearChildren(window.sidebar)
    sidebarRows = {}

    local subs = GetSubcategoriesFor(activeAddon)
    local y = -8
    for _, sub in ipairs(subs) do
        local row = CreateFrame("Button", nil, window.sidebar)
        row:SetSize(SIDEBAR_WIDTH - 8, SIDEBAR_ROW_H)
        row:SetPoint("TOPLEFT", 4, y)

        -- Hover background (subtle white tint, only when not selected).
        local hover = row:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.05)
        hover:Hide()
        row.hover = hover

        -- Gold-gradient selection highlight - same one the sub-lists
        -- and the User Manual tree use, so all three lists match.
        row.hlGroup = O.BuildSelectionHighlight(row, SIDEBAR_ROW_H)
        O.ShowHighlightGroup(row.hlGroup, false)

        local text = row:CreateFontString(nil, "OVERLAY", O.LIST_FONT)
        text:SetPoint("LEFT", 10, 0)
        text:SetText(sub.label)
        text:SetTextColor(unpack(O.GOLD))
        text:SetAlpha(0.75)
        row.text = text

        local capturedKey = sub.key
        row:SetScript("OnClick", function() SelectSubcategory(capturedKey) end)
        row:SetScript("OnEnter", function(self)
            if activeSubcategory ~= capturedKey then
                self.hover:Show()
                self.text:SetAlpha(1.0)
            end
        end)
        row:SetScript("OnLeave", function(self)
            if activeSubcategory ~= capturedKey then
                self.hover:Hide()
                self.text:SetAlpha(0.75)
            end
        end)

        sidebarRows[sub.key] = row
        y = y - SIDEBAR_ROW_H
    end

    -- Default to the root (landing page) entry
    local firstKey = subs[1] and subs[1].key or activeAddon
    SelectSubcategory(firstKey)
end

local function SelectAddon(name)
    activeAddon = name
    if not window then return end
    if BazUI.MarkMemoryEvent then
        BazUI:MarkMemoryEvent("addon_select", name)
    end

    -- Update bottom tab visuals
    for tabName, tab in pairs(bottomTabs) do
        if tabName == name then
            PanelTemplates_SelectTab(tab)
        else
            PanelTemplates_DeselectTab(tab)
        end
    end

    RenderSidebar()
end

local function RenderBottomTabs()
    if not window then return end
    -- Hide all existing tabs
    for _, tab in pairs(bottomTabs) do
        tab:Hide()
    end
    bottomTabs = {}

    local entries = GetTopLevelEntries()
    local x = 12
    for i, item in ipairs(entries) do
        local tab = CreateFrame("Button", "BazUIOptionsTab" .. i, window, "PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(item.entry.displayName or item.name)
        tab:SetPoint("TOPLEFT", window, "BOTTOMLEFT", x, 2)
        PanelTemplates_TabResize(tab, 0)

        local capturedName = item.name
        tab:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            SelectAddon(capturedName)
        end)

        bottomTabs[item.name] = tab
        x = x + tab:GetWidth() + 3  -- small gap between tabs
    end
end

local function EnsureWindow()
    if window then return window end

    -- PortraitFrameTemplate = same chrome as PlayerSpellsFrame (Talents/Spec window)
    local f = CreateFrame("Frame", "BazUIOptionsWindow", UIParent, "PortraitFrameTemplate")
    f:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetToplevel(true)
    f:Hide()

    -- Set custom portrait icon (BazUI logo)
    -- The portrait lives at f.PortraitContainer.portrait (named via $parentPortrait)
    local portrait = (f.PortraitContainer and f.PortraitContainer.portrait) or f.portrait
    if portrait then
        portrait:SetTexture("Interface\\AddOns\\BazUI\\Media\\IconRound.png")
    end

    -- Set the title (PortraitFrameTemplate provides SetTitle helper)
    if f.SetTitle then f:SetTitle("BazUI Options") end

    -- Overlay the spec-background atlas on top of the default rocky Bg
    -- to match the Specialization window's darker look
    local specBg = f:CreateTexture(nil, "BACKGROUND", nil, -3)
    specBg:SetAtlas("spec-background")
    specBg:SetPoint("TOPLEFT", 4, -22)
    specBg:SetPoint("BOTTOMRIGHT", -4, 4)

    -- Content area: fills the main body of the window, leaving space
    -- below for the bottom tab strip
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 10, -64)
    content:SetPoint("BOTTOMRIGHT", -10, 12)
    f.contentWrapper = content

    -- Sidebar (left side of content) - subtle border only so the
    -- PortraitFrameTemplate rocky background shows through
    local sidebar = CreateFrame("Frame", nil, content, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    sidebar:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
    })
    sidebar:SetBackdropBorderColor(unpack(O.PANEL_BORDER))
    f.sidebar = sidebar

    -- Vertical divider line between sidebar and content (gold accent)
    local divider = content:CreateTexture(nil, "OVERLAY")
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 5, 0)
    divider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 5, 0)
    divider:SetColorTexture(0.35, 0.3, 0.18, 0.6)

    -- Content panel (right of sidebar) - also transparent
    local contentPanel = CreateFrame("Frame", nil, content)
    contentPanel:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 12, 0)
    contentPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    f.content = contentPanel

    -- Bottom tab container (hangs below the window, like PlayerSpellsFrame)
    local tabContainer = CreateFrame("Frame", nil, f)
    tabContainer:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 0)
    tabContainer:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, 0)
    tabContainer:SetHeight(TAB_HEIGHT)
    f.tabContainer = tabContainer

    tinsert(UISpecialFrames, "BazUIOptionsWindow")

    -- Auto-mark window show/hide in the persistent memory log so the
    -- user can pinpoint exactly which UI action caused a memory spike
    -- without having to /bazmem mark by hand each time.
    f:HookScript("OnShow", function()
        if BazUI.MarkMemoryEvent then
            BazUI:MarkMemoryEvent("panel_show", activeAddon or "")
        end
    end)
    f:HookScript("OnHide", function()
        if BazUI.MarkMemoryEvent then
            BazUI:MarkMemoryEvent("panel_hide")
        end
    end)

    window = f
    return f
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function BazUI:RegisterOptionsTable(addonName, optionsTableOrFunc)
    optionsTables[addonName] = optionsTables[addonName] or {}
    optionsTables[addonName].func = optionsTableOrFunc
end

-- Build a stub canvas for Blizzard's Settings panel. Shows the addon
-- title, version, and a big "Open Options" button that launches our
-- standalone window with the correct tab active.
local function CreateBlizzardStub(addonName, displayName)
    local canvas = CreateFrame("Frame")

    local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    title:SetPoint("CENTER", 0, 80)
    title:SetText(displayName or addonName)
    title:SetTextColor(1, 0.82, 0)

    -- Version
    local version
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        version = C_AddOns.GetAddOnMetadata(addonName, "Version")
    end
    if version then
        local vtext = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        vtext:SetPoint("CENTER", 0, 40)
        vtext:SetText("Version: " .. version)
        vtext:SetTextColor(0.7, 0.7, 0.7)
    end

    local desc = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    desc:SetPoint("CENTER", 0, 0)
    desc:SetText("BazUI options have moved to their own window.")
    desc:SetTextColor(0.9, 0.9, 0.9)

    local btn = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    btn:SetSize(220, 36)
    btn:SetPoint("CENTER", 0, -50)
    btn:SetText("Open Options")
    local fs = btn:GetFontString()
    if fs then fs:SetFontObject("GameFontNormalLarge") end
    btn:SetScript("OnClick", function()
        -- Defer to next frame to escape Blizzard's secure code path,
        -- then hide their panel and open ours. SettingsPanel:Close() is
        -- a secure call that taints if invoked from inside an addon click.
        C_Timer.After(0, function()
            if SettingsPanel and SettingsPanel:IsShown() then
                SettingsPanel:Hide()
            end
            BazUI:OpenOptionsPanel(addonName)
        end)
    end)

    return canvas
end

-- AddToSettings: register an addon or sub-category with the BazUI options window.
--   addonName   = unique key (used with RegisterOptionsTable)
--   displayName = label shown on the tab / sidebar
--   parentName  = optional; if given, this is a sub-category of that parent addon
function BazUI:AddToSettings(addonName, displayName, parentName)
    local entry = optionsTables[addonName]
    if not entry then return end
    entry.displayName = displayName or addonName
    entry.parent = parentName

    -- Only BazUI registers with Blizzard's Settings panel as a stub.
    -- Other Baz addons are accessed via the BazUI options window's
    -- bottom tabs - no need to clutter Blizzard's AddOn list with all of them.
    if addonName == "BazUI" and not parentName and not entry.blizzardCategory
        and Settings and Settings.RegisterCanvasLayoutCategory then
        local stub = CreateBlizzardStub(addonName, entry.displayName)
        local category = Settings.RegisterCanvasLayoutCategory(stub, entry.displayName)
        Settings.RegisterAddOnCategory(category)
        entry.blizzardCategory = category
        entry.blizzardCanvas = stub
    end

    -- If the window already exists, refresh tabs/sidebar so this entry shows up
    if window and window:IsShown() then
        RenderBottomTabs()
        if activeAddon and not parentName and addonName == activeAddon then
            RenderSidebar()
        elseif activeAddon == parentName then
            RenderSidebar()
        end
    end
end

-- Helper: bracket a function call with memory-log phase markers so a
-- /bazmem watch dump shows the exact KB allocated by each construction
-- step (EnsureWindow, RenderBottomTabs, SelectAddon, ...). The markers
-- only fire when MemoryLog is loaded, so they're safe to leave in
-- production (they're cheap and useful for users reporting hitches).
local function PhaseMark(label)
    if BazUI.MarkMemoryEvent then
        BazUI:MarkMemoryEvent("phase", label)
    end
end

function BazUI:OpenOptionsPanel(addonName)
    PhaseMark("open:start")

    PhaseMark("open:before-EnsureWindow")
    EnsureWindow()
    PhaseMark("open:after-EnsureWindow")

    PhaseMark("open:before-RenderBottomTabs")
    RenderBottomTabs()
    PhaseMark("open:after-RenderBottomTabs")

    -- Figure out which top-level addon to activate.
    -- If addonName is a sub-category, switch to its parent first, then select the sub-category.
    local entry = optionsTables[addonName]
    local topLevel = addonName
    local subcategory = nil
    if entry and entry.parent then
        topLevel = entry.parent
        subcategory = addonName
    end

    -- If the requested addon isn't registered, fall back to the first top-level
    if not optionsTables[topLevel] or not optionsTables[topLevel].displayName then
        local entries = GetTopLevelEntries()
        if #entries > 0 then
            topLevel = entries[1].name
        end
    end

    PhaseMark("open:before-SelectAddon=" .. tostring(topLevel))
    SelectAddon(topLevel)
    PhaseMark("open:after-SelectAddon")

    if subcategory then
        PhaseMark("open:before-SelectSubcategory=" .. tostring(subcategory))
        SelectSubcategory(subcategory)
        PhaseMark("open:after-SelectSubcategory")
    end

    PhaseMark("open:before-Show")
    window:Show()
    window:Raise()
    PhaseMark("open:after-Show")

    PhaseMark("open:end")
end

function BazUI:RefreshOptions(addonName)
    if not window or not window:IsShown() then return end
    -- Only re-render if the refreshed addon/sub-category is currently showing
    if activeSubcategory == addonName then
        local entry = optionsTables[addonName]
        if not entry then return end
        O.ClearChildren(window.content)
        if type(entry.customRender) == "function" then
            entry.customRender(window.content)
            return
        end
        local tbl = entry.func
        if type(tbl) == "function" then tbl = tbl() end
        if tbl then
            RenderIntoCanvas(window.content, tbl)
        end
    end
end
