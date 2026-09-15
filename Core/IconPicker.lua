-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: IconPicker
--
-- Reusable icon picker popup with category tabs, search filtering, and
-- a scrollable grid of icons. Any BazUI addon can open it with:
--
--   BazUI:ShowIconPicker(callback, currentIcon)
--     callback(texturePath) - called when the user picks an icon
--     currentIcon           - optional, highlights the current selection
--
-- Uses GetMacroItemIcons/GetMacroSpellIcons for the full WoW icon library.
---------------------------------------------------------------------------

local ICONS_PER_ROW = 10
local ICON_SIZE = 32
local ICON_GAP = 4
local GRID_WIDTH = ICONS_PER_ROW * (ICON_SIZE + ICON_GAP) - ICON_GAP + 20
local SEARCH_HEIGHT = 26
local TAB_HEIGHT = 24
local PICKER_HEIGHT = 420

local pickerFrame
local allIcons = {}        -- full icon list (populated once)
local filteredIcons = {}   -- after search filter
local iconButtons = {}     -- recycled grid buttons
local currentCallback
local currentIcon
local activeCategory = "all"

---------------------------------------------------------------------------
-- Icon data loading (lazy, one-time)
---------------------------------------------------------------------------

local CATEGORIES = {
    { id = "all",        label = "All" },
    { id = "spells",     label = "Spells" },
    { id = "items",      label = "Items" },
}

-- Spell name > icon cache, built via coroutine (WeakAuras/MacroIconSearch approach)
local spellIconCache = {}   -- [lowerName] = fileDataID
local iconToName = {}       -- [fileDataID] = displayName (first spell name found)
local cacheReady = false

local function BuildSpellIconCache()
    if cacheReady then return end
    cacheReady = true

    local co = coroutine.create(function()
        local id = 0
        local misses = 0
        while misses < 80000 do
            id = id + 1
            local info = C_Spell.GetSpellInfo(id)
            local name, icon
            if info then
                name = info.name
                icon = info.iconID
            end

            if icon == 136243 then
                misses = 0
            elseif name and name ~= "" and icon then
                local lower = name:lower()
                if not spellIconCache[lower] then
                    spellIconCache[lower] = icon
                end
                if not iconToName[icon] then
                    iconToName[icon] = name
                end
                misses = 0
            else
                misses = misses + 1
            end
            coroutine.yield()
        end
    end)

    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self)
        local start = debugprofilestop()
        while debugprofilestop() - start < 10 do
            if coroutine.status(co) ~= "dead" then
                local ok, msg = coroutine.resume(co)
                if not ok then geterrorhandler()(msg) end
            else
                self:SetScript("OnUpdate", nil)
                return
            end
        end
    end)
end

-- The cache is built LAZILY on first ShowIconPicker call - not at
-- login. Eager-building cost ~80 MB transient + ~14 MB retained per
-- session, even when the user never opens the icon picker (most
-- sessions). The picker opens fine without the spell name -> icon
-- map; search-by-spell-name just won't return results until the
-- coroutine has chewed through the spell ID space, which takes a
-- few seconds in the background and yields between iterations so
-- it never blocks the frame.

local function LoadIcons()
    if #allIcons > 0 then return end

    -- Load the base icon set from Blizzard's APIs
    local spellRaw, itemRaw = {}, {}
    if GetLooseMacroIcons then GetLooseMacroIcons(spellRaw) end
    if GetMacroIcons then GetMacroIcons(spellRaw) end
    if GetLooseMacroItemIcons then GetLooseMacroItemIcons(itemRaw) end
    if GetMacroItemIcons then GetMacroItemIcons(itemRaw) end

    local seen = {}

    local function AddEntries(raw, cat)
        for _, tex in ipairs(raw) do
            local asNum = tonumber(tex)
            if asNum then
                if not seen[asNum] then
                    seen[asNum] = true
                    allIcons[#allIcons + 1] = { id = asNum, cat = cat, name = "" }
                end
            else
                local path = "INTERFACE\\ICONS\\" .. tex
                local texLower = tex:lower()
                if not seen[texLower] then
                    seen[texLower] = true
                    allIcons[#allIcons + 1] = { id = path, cat = cat, name = texLower }
                end
            end
        end
    end

    AddEntries(spellRaw, "spells")
    AddEntries(itemRaw, "items")
end

---------------------------------------------------------------------------
-- Filtering
---------------------------------------------------------------------------

local function ApplyFilter(searchText)
    filteredIcons = {}
    local search = searchText and searchText:lower() or ""

    if search == "" then
        -- No search: show everything in the active category
        for _, entry in ipairs(allIcons) do
            local matchCat = (activeCategory == "all") or (entry.cat == activeCategory)
            if matchCat then
                filteredIcons[#filteredIcons + 1] = entry.id
            end
        end
    else
        -- Search active: match icons whose display name contains the query.
        -- Use iconToName (reverse lookup) so we match the name that will
        -- show in the tooltip, not every spell that shares the same icon.
        local seen = {}

        -- First: named icons from the base set (string paths)
        for _, entry in ipairs(allIcons) do
            local matchCat = (activeCategory == "all") or (entry.cat == activeCategory)
            if matchCat and entry.name and entry.name ~= "" then
                if entry.name:find(search, 1, true) then
                    filteredIcons[#filteredIcons + 1] = entry.id
                    seen[entry.id] = true
                end
            end
        end

        -- Second: FileDataID icons whose display name matches
        for _, entry in ipairs(allIcons) do
            if not seen[entry.id] and type(entry.id) == "number" then
                local matchCat = (activeCategory == "all") or (entry.cat == activeCategory)
                if matchCat then
                    local displayName = iconToName[entry.id]
                    if displayName and displayName:lower():find(search, 1, true) then
                        filteredIcons[#filteredIcons + 1] = entry.id
                        seen[entry.id] = true
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Grid rendering
---------------------------------------------------------------------------

local scrollOffset = 0

local function GetVisibleRows()
    local gridH = PICKER_HEIGHT - SEARCH_HEIGHT - TAB_HEIGHT - 60
    return math.floor(gridH / (ICON_SIZE + ICON_GAP))
end

local function RenderGrid()
    if not pickerFrame then return end
    local grid = pickerFrame.grid

    -- Hide all existing buttons
    for _, btn in ipairs(iconButtons) do
        btn:Hide()
    end

    local visibleRows = GetVisibleRows()
    local totalVisible = visibleRows * ICONS_PER_ROW
    local startIdx = scrollOffset * ICONS_PER_ROW + 1

    for i = 1, totalVisible do
        local dataIdx = startIdx + i - 1
        local iconId = filteredIcons[dataIdx]
        if not iconId then break end

        local btn = iconButtons[i]
        if not btn then
            btn = CreateFrame("Button", nil, grid)
            btn:SetSize(ICON_SIZE, ICON_SIZE)

            btn.tex = btn:CreateTexture(nil, "ARTWORK")
            btn.tex:SetAllPoints()
            btn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            btn.border = btn:CreateTexture(nil, "OVERLAY")
            btn.border:SetPoint("TOPLEFT", -1, 1)
            btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
            btn.border:SetColorTexture(1, 0.82, 0, 1)
            btn.border:Hide()

            btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
            btn.highlight:SetAllPoints()
            btn.highlight:SetColorTexture(1, 1, 1, 0.2)

            btn:SetScript("OnClick", function(self)
                if self._iconId and currentCallback then
                    currentCallback(self._iconId)
                end
                pickerFrame:Hide()
            end)

            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if type(self._iconId) == "number" then
                    local name = iconToName[self._iconId]
                    if name then
                        GameTooltip:SetText(name)
                    else
                        GameTooltip:SetText("Icon " .. self._iconId)
                    end
                else
                    local name = self._iconId:match("[^\\]+$") or self._iconId
                    GameTooltip:SetText(name)
                end
                GameTooltip:Show()
            end)

            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            iconButtons[i] = btn
        end

        btn._iconId = iconId
        btn.tex:SetTexture(iconId)

        -- Highlight current selection
        if currentIcon and iconId == currentIcon then
            btn.border:Show()
        else
            btn.border:Hide()
        end

        local col = (i - 1) % ICONS_PER_ROW
        local row = math.floor((i - 1) / ICONS_PER_ROW)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", grid, "TOPLEFT",
            col * (ICON_SIZE + ICON_GAP),
            -row * (ICON_SIZE + ICON_GAP))
        btn:Show()
    end

    -- Update scroll range
    local totalRows = math.ceil(#filteredIcons / ICONS_PER_ROW)
    local maxScroll = math.max(0, totalRows - visibleRows)
    if scrollOffset > maxScroll then scrollOffset = maxScroll end
end

---------------------------------------------------------------------------
-- Build the picker frame (one-time)
---------------------------------------------------------------------------

local function BuildPicker()
    if pickerFrame then return pickerFrame end

    local f = CreateFrame("Frame", "BazUIIconPicker", UIParent, "BackdropTemplate")
    f:SetSize(GRID_WIDTH + 20, PICKER_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    BazUI.Skin.Theme.ApplyFlatPanel(f)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Choose an Icon")
    title:SetTextColor(1, 0.82, 0)

    -- Close button
    local close = BazUI.Skin.Theme.CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Category tabs
    f.tabs = {}
    local tabX = 10
    for i, cat in ipairs(CATEGORIES) do
        local tab = CreateFrame("Button", nil, f)
        tab:SetSize(60, TAB_HEIGHT)
        tab:SetPoint("TOPLEFT", tabX, -28)

        tab.bg = tab:CreateTexture(nil, "BACKGROUND")
        tab.bg:SetAllPoints()
        tab.bg:SetColorTexture(0.1, 0.1, 0.15, 0.8)

        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tab.label:SetPoint("CENTER")
        tab.label:SetText(cat.label)

        tab._catId = cat.id

        tab:SetScript("OnClick", function(self)
            activeCategory = self._catId
            scrollOffset = 0
            -- Update tab visuals
            for _, t in ipairs(f.tabs) do
                if t._catId == activeCategory then
                    t.bg:SetColorTexture(0.15, 0.35, 0.6, 0.8)
                    t.label:SetTextColor(1, 0.82, 0)
                else
                    t.bg:SetColorTexture(0.1, 0.1, 0.15, 0.8)
                    t.label:SetTextColor(0.8, 0.8, 0.8)
                end
            end
            ApplyFilter(f.searchBox:GetText())
            RenderGrid()
        end)

        tab:SetScript("OnEnter", function(self)
            if self._catId ~= activeCategory then
                self.bg:SetColorTexture(0.12, 0.2, 0.35, 0.8)
            end
        end)
        tab:SetScript("OnLeave", function(self)
            if self._catId ~= activeCategory then
                self.bg:SetColorTexture(0.1, 0.1, 0.15, 0.8)
            end
        end)

        f.tabs[i] = tab
        tabX = tabX + 64
    end

    -- Search box
    local search = BazUI.Skin.Theme.CreateSearchBox(f, "Search icons...", function(text)
        scrollOffset = 0
        ApplyFilter(text)
        RenderGrid()
    end)
    search:SetSize(GRID_WIDTH - 10, SEARCH_HEIGHT)
    search:SetPoint("TOPLEFT", 14, -56)
    f.searchBox = search

    -- Grid container
    local grid = CreateFrame("Frame", nil, f)
    grid:SetPoint("TOPLEFT", 10, -86)
    grid:SetPoint("BOTTOMRIGHT", -10, 10)
    f.grid = grid

    -- Mouse wheel scrolling
    f:SetScript("OnMouseWheel", function(_, delta)
        scrollOffset = scrollOffset - delta
        if scrollOffset < 0 then scrollOffset = 0 end
        local totalRows = math.ceil(#filteredIcons / ICONS_PER_ROW)
        local maxScroll = math.max(0, totalRows - GetVisibleRows())
        if scrollOffset > maxScroll then scrollOffset = maxScroll end
        RenderGrid()
    end)

    -- ESC closes
    tinsert(UISpecialFrames, "BazUIIconPicker")

    pickerFrame = f
    return f
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function BazUI:ShowIconPicker(callback, selectedIcon)
    LoadIcons()
    -- Kick off the spell name -> icon cache on first open. Idempotent;
    -- a `cacheReady` flag short-circuits subsequent calls. Yields per
    -- iteration so the picker is usable immediately even while the
    -- coroutine is still running in the background.
    BuildSpellIconCache()

    local f = BuildPicker()
    currentCallback = callback
    currentIcon = selectedIcon
    activeCategory = "all"
    scrollOffset = 0

    -- Reset tab visuals
    for _, tab in ipairs(f.tabs) do
        if tab._catId == "all" then
            tab.bg:SetColorTexture(0.15, 0.35, 0.6, 0.8)
            tab.label:SetTextColor(1, 0.82, 0)
        else
            tab.bg:SetColorTexture(0.1, 0.1, 0.15, 0.8)
            tab.label:SetTextColor(0.8, 0.8, 0.8)
        end
    end

    f.searchBox:SetText("")
    ApplyFilter("")
    RenderGrid()
    f:Show()
    f:Raise()
end

