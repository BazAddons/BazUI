-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: User Manual
--
-- Hosts the User Manual bottom tab. Any BazUI-compatible addon can
-- register its user guide via BazUI:RegisterUserGuide(addonName, guide).
-- Each registered guide becomes a sub-category in the User Manual tab.
--
-- Guide format:
--   {
--       title = "BazUI",                 -- optional; defaults to addonName
--       intro = "Lead paragraph.",         -- optional; shown above page list
--       pages = {                           -- optional tree of pages
--           {
--               title = "Overview",
--               text  = "Page body...",     -- supports \n\n paragraph breaks
--               children = {                -- optional sub-pages (one level)
--                   { title = "Sub Topic", text = "..." },
--               },
--           },
--           ...
--       },
--       -- Backward-compat: a flat sections list still works
--       sections = {
--           { heading = "...", text = "..." },
--       },
--   }
--
-- Text supports WoW escape codes (|cffxxxxxx...|r for colors). Use
-- \n for line breaks, \n\n for paragraph breaks.
---------------------------------------------------------------------------

local O = BazUI._Options

local guides = {}      -- [addonName] = guide table
local guideState = {}  -- [addonName] = { expanded = {[key]=true}, selectedKey = "1" }

-- List width / gap constants live in Options/Constants.lua so the
-- standard list/detail panel and the User Manual tree resolve to
-- identical dimensions.

---------------------------------------------------------------------------
-- Tree helpers
---------------------------------------------------------------------------

-- Walk pages tree, producing a flat list of nodes that should be visible
-- given the current expansion state.
-- Each node: { page, key, depth, hasChildren }
local function FlattenVisibleNodes(pages, expanded, depth, parentKey, out)
    out = out or {}
    for i, page in ipairs(pages or {}) do
        local key = parentKey and (parentKey .. "/" .. i) or tostring(i)
        local hasChildren = page.children and #page.children > 0
        out[#out + 1] = { page = page, key = key, depth = depth, hasChildren = hasChildren }
        if hasChildren and expanded[key] then
            FlattenVisibleNodes(page.children, expanded, depth + 1, key, out)
        end
    end
    return out
end

-- Find the first leaf page (used for default selection)
local function FindFirstPageKey(pages, parentKey)
    if not pages or #pages == 0 then return nil end
    return parentKey and (parentKey .. "/1") or "1"
end

-- Look up a page node by its key path (e.g. "1/2")
local function FindPageByKey(pages, key)
    if not pages or not key then return nil end
    local cur = pages
    local node
    for part in string.gmatch(key, "[^/]+") do
        local idx = tonumber(part)
        if not idx or not cur or not cur[idx] then return nil end
        node = cur[idx]
        cur = node.children
    end
    return node
end

---------------------------------------------------------------------------
-- Title bar (delegates to O.BuildTitleBar so the User Manual + the
-- standard list/detail page render identical headers).
---------------------------------------------------------------------------

local function BuildTitleBar(parent, addonName, guide, contentWidth)
    return O.BuildTitleBar(parent, {
        title        = guide.title or addonName,
        addonName    = addonName,
        contentWidth = contentWidth,
    })
end

---------------------------------------------------------------------------
-- Render the page-content panel (right side)
---------------------------------------------------------------------------

-- Convert a page (from the user guide schema) into a normalized list of
-- content blocks. Supports both the new `blocks` field AND the legacy
-- `text`/`sections` fields so existing guides keep working.
local function PageToBlocks(page)
    if not page then return {} end
    if page.blocks then return page.blocks end

    local blocks = {}
    if page.text and page.text ~= "" then
        blocks[#blocks + 1] = { type = "paragraph", text = page.text }
    end
    if page.sections then
        for _, section in ipairs(page.sections) do
            if section.heading and section.heading ~= "" then
                blocks[#blocks + 1] = { type = "h3", text = section.heading }
            end
            if section.text and section.text ~= "" then
                blocks[#blocks + 1] = { type = "paragraph", text = section.text }
            end
        end
    end
    return blocks
end

local function RenderPageContent(parent, page, contentWidth)
    O.ClearChildren(parent)
    if not page then return end

    -- Page title (h1) at top, then the page's blocks
    local headerBlocks = {}
    if page.title and page.title ~= "" then
        headerBlocks[#headerBlocks + 1] = { type = "h1", text = page.title }
    end

    local allBlocks = {}
    for _, b in ipairs(headerBlocks) do allBlocks[#allBlocks + 1] = b end
    for _, b in ipairs(PageToBlocks(page)) do allBlocks[#allBlocks + 1] = b end

    -- Render each block, but keep a list so we can re-flow Y offsets
    -- whenever a collapsible expands/collapses. Without this, blocks
    -- below a collapsible are anchored at fixed Y values measured at
    -- render time, so an opened collapsible overlaps its siblings and
    -- the parent height stays too short for the scroll frame.
    local items = {}
    local innerWidth = contentWidth - O.PAD * 2
    for _, block in ipairs(allBlocks) do
        local factory = O.widgetFactories[block.type]
        if factory then
            local widget, h = factory(parent, block, innerWidth)
            widget:Show()
            items[#items + 1] = { widget = widget, height = h }
        end
    end

    local function Reflow()
        local y = -O.PAD
        for _, item in ipairs(items) do
            item.widget:ClearAllPoints()
            item.widget:SetPoint("TOPLEFT", parent, "TOPLEFT", O.PAD, y)
            -- Read the widget's CURRENT height (collapsibles change
            -- theirs as they animate; everything else stays static).
            local h = item.widget:GetHeight() or item.height
            y = y - h - O.SPACING
        end
        parent:SetHeight(math.abs(y) + O.PAD)
    end

    -- Hook each block's _onHeightChanged so any collapsible that grows
    -- or shrinks triggers a full re-flow. Non-collapsible blocks never
    -- fire the hook - assigning the field is harmless.
    for _, item in ipairs(items) do
        item.widget._onHeightChanged = Reflow
    end

    Reflow()
end

---------------------------------------------------------------------------
-- Tree list rebuild
---------------------------------------------------------------------------

local function RebuildTree(listContent, addonName, guide, listW, onSelect)
    O.ClearChildren(listContent)
    local state = guideState[addonName]
    local nodes = FlattenVisibleNodes(guide.pages, state.expanded, 0)

    local rowWidth = listW - 26
    local rows = {}
    for _, node in ipairs(nodes) do
        local capturedKey  = node.key
        local hasChildren  = node.hasChildren and true or false
        local capturedPage = node.page
        rows[#rows + 1] = {
            key        = capturedKey,
            label      = capturedPage.title or "",
            isParent   = hasChildren,
            expanded   = state.expanded[capturedKey] and true or false,
            isSelected = (capturedKey == state.selectedKey),
            depth      = node.depth,
            onClick    = function()
                if hasChildren then
                    state.expanded[capturedKey] = not state.expanded[capturedKey]
                end
                state.selectedKey = capturedKey
                onSelect(capturedPage)
                RebuildTree(listContent, addonName, guide, listW, onSelect)
            end,
        }
    end

    local _, totalH = O.RenderListRows(listContent, rows, { width = rowWidth })
    listContent:SetHeight(math.max(totalH or 0, 1))
end

---------------------------------------------------------------------------
-- Convert legacy `sections` to `pages` so everything goes through one
-- code path. Each section becomes a top-level page.
---------------------------------------------------------------------------

local function NormalizeGuide(guide)
    if guide.pages and #guide.pages > 0 then return guide end
    if guide.sections and #guide.sections > 0 then
        local pages = {}
        for _, section in ipairs(guide.sections) do
            pages[#pages + 1] = {
                title = section.heading,
                text  = section.text,
            }
        end
        -- Don't mutate caller's table - clone the relevant fields
        return {
            title    = guide.title,
            intro    = guide.intro,
            pages    = pages,
            sections = guide.sections,  -- preserved for reference
        }
    end
    return guide
end

---------------------------------------------------------------------------
-- Custom renderer: title bar + tree list (left) + content panel (right)
---------------------------------------------------------------------------

local function RenderGuide(container, addonName)
    local rawGuide = guides[addonName]
    if not rawGuide then return end
    local guide = NormalizeGuide(rawGuide)

    guideState[addonName] = guideState[addonName] or { expanded = {}, selectedKey = nil }
    local state = guideState[addonName]

    -- Default selection: first top-level page
    if not state.selectedKey then
        state.selectedKey = FindFirstPageKey(guide.pages)
    end

    local containerW = container:GetWidth() or 800

    -- Title bar at top
    local titleBar, titleH = BuildTitleBar(container, addonName, guide, containerW)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)

    -- Optional intro paragraph below title bar
    local introH = 0
    local introOffset = -titleH
    if guide.intro and guide.intro ~= "" then
        local intro = container:CreateFontString(nil, "OVERLAY")
        intro:SetFontObject(O.DESC_FONT)
        intro:SetPoint("TOPLEFT", O.PAD, introOffset - 4)
        intro:SetWidth(containerW - O.PAD * 2)
        intro:SetJustifyH("LEFT")
        intro:SetText(guide.intro)
        intro:SetTextColor(unpack(O.TEXT_DESC))
        intro:SetWordWrap(true)
        introH = intro:GetStringHeight() + 10
    end

    local belowHeaderY = -titleH - introH

    -- Split frame for list (left) + detail (right)
    local splitFrame = CreateFrame("Frame", nil, container)
    splitFrame:SetPoint("TOPLEFT", 0, belowHeaderY)
    splitFrame:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Compute list width via the shared resolver so the standard
    -- list/detail panel ends up the same size for the same container.
    local listW = O.ResolveListWidth(containerW)

    -- Left list backdrop
    local listBg = CreateFrame("Frame", nil, splitFrame, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 0, 0)
    listBg:SetPoint("BOTTOMLEFT", 0, 0)
    listBg:SetWidth(listW)
    BazUI.Skin.Theme.ApplyFlatPanel(listBg, O.LIST_BG, O.PANEL_BORDER)

    -- List scroll
    local listScroll = CreateFrame("ScrollFrame", nil, listBg)
    listScroll:SetPoint("TOPLEFT", 4, -6)
    listScroll:SetPoint("BOTTOMRIGHT", -14, 4)
    listScroll:EnableMouseWheel(true)

    local listScrollBar = CreateFrame("EventFrame", nil, listBg, "MinimalScrollBar")
    listScrollBar:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 2, 0)
    listScrollBar:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", 2, 0)
    ScrollUtil.InitScrollFrameWithScrollBar(listScroll, listScrollBar)
    BazUI.Skin.Theme.AutoFadeScrollBar(listScrollBar, listScroll)
    O.AutoHideScrollbar(listScroll, listScrollBar)

    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetWidth(listW - 26)
    listScroll:SetScrollChild(listContent)

    -- Right detail panel
    local detailFrame = CreateFrame("Frame", nil, splitFrame, "BackdropTemplate")
    detailFrame:SetPoint("TOPLEFT", listBg, "TOPRIGHT", O.PAGE_LIST_GAP, 0)
    detailFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    BazUI.Skin.Theme.ApplyFlatPanel(detailFrame, O.PANEL_BG, O.PANEL_BORDER)

    local detailScroll = CreateFrame("ScrollFrame", nil, detailFrame)
    detailScroll:SetPoint("TOPLEFT", 4, -4)
    detailScroll:SetPoint("BOTTOMRIGHT", -14, 4)
    detailScroll:EnableMouseWheel(true)

    local detailScrollBar = CreateFrame("EventFrame", nil, detailFrame, "MinimalScrollBar")
    detailScrollBar:SetPoint("TOPLEFT", detailScroll, "TOPRIGHT", 2, 0)
    detailScrollBar:SetPoint("BOTTOMLEFT", detailScroll, "BOTTOMRIGHT", 2, 0)
    ScrollUtil.InitScrollFrameWithScrollBar(detailScroll, detailScrollBar)
    BazUI.Skin.Theme.AutoFadeScrollBar(detailScrollBar, detailScroll)
    O.AutoHideScrollbar(detailScroll, detailScrollBar)

    local detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetWidth(detailFrame:GetWidth() - 28)
    detailScroll:SetScrollChild(detailContent)

    local function Select(page)
        local dw = detailContent:GetWidth() - O.PAD
        if dw <= 0 then dw = 360 end
        RenderPageContent(detailContent, page, dw)
    end

    -- Initial tree render
    RebuildTree(listContent, addonName, guide, listW, Select)

    -- Initial content render (deferred so widths settle)
    C_Timer.After(0, function()
        if not detailContent then return end
        detailContent:SetWidth(detailFrame:GetWidth() - 28)
        local page = FindPageByKey(guide.pages, state.selectedKey)
        Select(page)
    end)

    detailFrame:SetScript("OnSizeChanged", function(self, w)
        detailContent:SetWidth(w - 28)
        local page = FindPageByKey(guide.pages, state.selectedKey)
        Select(page)
    end)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- RegisterUserGuide: each addon's guide becomes a "User Guide" sub-category
-- under that addon's own bottom tab. No separate User Manual tab - docs
-- live next to the settings they describe.
function BazUI:RegisterUserGuide(addonName, guide)
    if type(addonName) ~= "string" or addonName == "" then return end
    if type(guide) ~= "table" then return end

    guides[addonName] = guide
    -- Reset view state so a re-registration doesn't strand a stale selection
    guideState[addonName] = { expanded = {}, selectedKey = nil }

    -- Register the guide as a sub-category of the addon itself
    local key = "UserGuide_" .. addonName
    local entry = BazUI._optionsTables[key] or {}
    entry.func = function() return { name = addonName, args = {} } end  -- placeholder
    entry.customRender = function(container)
        RenderGuide(container, addonName)
    end
    BazUI._optionsTables[key] = entry
    BazUI:AddToSettings(key, "User Manual", addonName)

    if BazUI.RefreshOptions then
        BazUI:RefreshOptions(key)
    end
end

BazUI._userGuides = guides

---------------------------------------------------------------------------
-- BazUI's own built-in user guide
---------------------------------------------------------------------------

BazUI:RegisterUserGuide("BazUI", {
    title = "BazUI",
    intro = "BazUI is one addon that replaces a stack of separate UI addons. Pick a topic on the left.",
    pages = {
        {
            title = "Welcome",
            blocks = {
                { type = "lead", text = "BazUI gathers the Baz Suite into a single addon built for World of Warcraft: Forever. Drawers hold the minimap, minimap buttons, quest tracker and info bar; chat and bags follow as modules." },
                { type = "h2", text = "Slash commands" },
                { type = "table",
                  columns = { "Command", "Effect" },
                  rows = {
                      { "/bazui",                 "Open BazUI in Options > AddOns" },
                      { "/bazui profile <name>",  "Switch to a profile" },
                      { "/bazui profiles",        "List profiles" },
                      { "/bazui default <name>",  "Set the profile new characters start on" },
                      { "/bui",                   "Short alias for /bazui" },
                  },
                },
                { type = "note", style = "tip", text = "BazUI lives in the standard Options > AddOns list. Each module is an entry under BazUI, and a module's pages are tabs across the top of its panel." },
            },
        },
        {
            title = "Profiles",
            blocks = {
                { type = "lead", text = "One profile covers every module. Switch profiles from the Profiles page or with /bazui profile, and assign profiles per character, class or specialisation." },
                { type = "list", items = {
                    "Create, copy, rename and delete profiles from the Profiles page.",
                    "A profile can be set as the default for new characters.",
                    "Modules react to profile changes immediately; no reload needed.",
                }},
            },
        },
    },
})
