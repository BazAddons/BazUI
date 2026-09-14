-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications
local BNC = addon.API

local Colors = addon.Colors
local PANEL_WIDTH = 380
local PANEL_HEIGHT = 500
local PANEL_PADDING = 10
local HEADER_HEIGHT = 36
local TAB_HEIGHT = 24
local FILTER_ROW_HEIGHT = 24
local SEARCH_ROW_HEIGHT = 26
local CARD_SPACING = 4
local CONTENT_WIDTH = PANEL_WIDTH - PANEL_PADDING * 2
local HISTORY_PAGE_SIZE = 100


-- Reused across every history card. Previously a fresh dict was
-- allocated on every CreateHistoryCard AND every ResetHistoryCard
-- call; with a busy history this was several hundred wasted tables
-- per session.
local BACKDROP_HISTORY_CARD = BazUI.Skin.Theme.BACKDROP_FLAT

-- State
local panel
local overlay
local isShown = false
local currentTab = "notifications"  -- "notifications" or "history"
local timestampTicker

-- Notifications tab state
local notifScroll
local notifActiveCards = {}
local notifActiveHeaders = {}
local notifModuleFilter = nil  -- nil = all

-- History tab state
local historyScroll
local historyActiveCards = {}
local historyModuleFilter = nil
local historyDateFilter = nil   -- nil, "today", "yesterday", "week", "month"
local historySearch = ""
local historyResults = {}
local historyPage = 1
-- Card pool for history (separate from notification cards)
local historyCardIndex = 0

local function CreateHistoryCard()
    historyCardIndex = historyCardIndex + 1
    local card = CreateFrame("Frame", "BazUINotifHistCard" .. historyCardIndex, UIParent, "BackdropTemplate")
    card:SetSize(CONTENT_WIDTH, 48)
    card:SetBackdrop(BACKDROP_HISTORY_CARD)
    card:SetBackdropColor(unpack(Colors.cardBg))
    card:SetBackdropBorderColor(unpack(Colors.cardBorder))
    card:EnableMouse(true)
    card:Hide()

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(24, 24)
    card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -8)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.title = card:CreateFontString(nil, "OVERLAY")
    card.title:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormal"))
    card.title:SetTextColor(unpack(Colors.textPrimary))
    card.title:SetJustifyH("LEFT")
    card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 6, 0)
    card.title:SetPoint("RIGHT", card, "RIGHT", -90, 0)
    card.title:SetWordWrap(false)

    card.timestamp = card:CreateFontString(nil, "OVERLAY")
    card.timestamp:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormalSmall"))
    card.timestamp:SetTextColor(unpack(Colors.textMuted))
    card.timestamp:SetJustifyH("RIGHT")
    card.timestamp:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)

    card.message = card:CreateFontString(nil, "OVERLAY")
    card.message:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontHighlightSmall"))
    card.message:SetTextColor(unpack(Colors.textSecondary))
    card.message:SetJustifyH("LEFT")
    card.message:SetWordWrap(true)
    card.message:SetPoint("TOPLEFT", card.icon, "BOTTOMLEFT", 0, -3)
    card.message:SetPoint("RIGHT", card, "RIGHT", -8, 0)

    card.priorityBar = card:CreateTexture(nil, "OVERLAY")
    card.priorityBar:SetSize(2, 1)
    card.priorityBar:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -1)
    card.priorityBar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 1)
    card.priorityBar:Hide()

    card.isSeparator = false

    card:SetScript("OnEnter", function(self)
        if not self.isSeparator then self:SetBackdropColor(unpack(Colors.cardHover)) end
    end)
    card:SetScript("OnLeave", function(self)
        if not self.isSeparator then self:SetBackdropColor(unpack(Colors.cardBg)) end
    end)

    return card
end

local function ResetHistoryCard(card)
    card:Hide()
    card:SetParent(UIParent)
    card:ClearAllPoints()
    card.priorityBar:Hide()
    card.isSeparator = false
    -- The card already has the backdrop applied from creation - just
    -- restore the colours, which are the only thing that ever changes
    -- (separator rows tint differently). Re-applying SetBackdrop on
    -- every release was rebuilding the 9-slice frame structure for no
    -- reason.
    card:SetBackdropColor(unpack(Colors.cardBg))
    card:SetBackdropBorderColor(unpack(Colors.cardBorder))
end

local historyCardPool = BazUI:CreateObjectPool(CreateHistoryCard, ResetHistoryCard)

---------------------------------------------------------------------
-- Dropdown helper
---------------------------------------------------------------------
local dropdownCounter = 0

local function CreateDropdown(parent, width, items, currentValue, onChange)
    dropdownCounter = dropdownCounter + 1
    local name = "BNCDropdown" .. dropdownCounter

    local dropdown = CreateFrame("Frame", name, parent, "BackdropTemplate")
    dropdown:SetSize(width, 22)
    dropdown:SetBackdrop(BazUI.Skin.Theme.BACKDROP_FLAT)
    dropdown:SetBackdropColor(unpack(Colors.cardBg))
    dropdown:SetBackdropBorderColor(unpack(Colors.cardBorder))

    dropdown.selectedValue = currentValue
    dropdown.items = items
    dropdown.onChange = onChange

    -- Selected text
    dropdown.text = dropdown:CreateFontString(nil, "OVERLAY")
    dropdown.text:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormalSmall"))
    dropdown.text:SetTextColor(unpack(Colors.textPrimary))
    dropdown.text:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
    dropdown.text:SetPoint("RIGHT", dropdown, "RIGHT", -18, 0)
    dropdown.text:SetJustifyH("LEFT")
    dropdown.text:SetWordWrap(false)

    -- Arrow
    dropdown.arrow = dropdown:CreateFontString(nil, "OVERLAY")
    dropdown.arrow:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormalSmall"))
    dropdown.arrow:SetTextColor(unpack(Colors.textMuted))
    dropdown.arrow:SetText("v")
    dropdown.arrow:SetPoint("RIGHT", dropdown, "RIGHT", -6, 0)

    -- Menu frame (hidden by default)
    dropdown.menu = CreateFrame("Frame", name .. "Menu", dropdown, "BackdropTemplate")
    dropdown.menu:SetBackdrop(BazUI.Skin.Theme.BACKDROP_FLAT)
    dropdown.menu:SetBackdropColor(unpack(Colors.panelBg))
    dropdown.menu:SetBackdropBorderColor(unpack(Colors.cardBorder))
    dropdown.menu:SetFrameStrata("TOOLTIP")
    dropdown.menu:SetFrameLevel(200)
    dropdown.menu:Hide()
    dropdown.menu:EnableMouse(true)

    dropdown.menuItems = {}

    function dropdown:SetValue(value)
        self.selectedValue = value
        -- Find display text
        for _, item in ipairs(self.items) do
            if item.value == value then
                self.text:SetText(item.text)
                return
            end
        end
        self.text:SetText("All")
    end

    function dropdown:BuildMenu()
        -- Clear old items
        for _, mi in ipairs(self.menuItems) do mi:Hide(); mi:SetParent(nil) end
        wipe(self.menuItems)

        local menuWidth = self:GetWidth()
        local itemHeight = 20
        local yOff = 0

        for _, item in ipairs(self.items) do
            local mi = CreateFrame("Button", nil, self.menu)
            mi:SetSize(menuWidth - 2, itemHeight)
            mi:SetPoint("TOPLEFT", self.menu, "TOPLEFT", 1, -1 - yOff)

            mi.bg = mi:CreateTexture(nil, "BACKGROUND")
            mi.bg:SetAllPoints()
            mi.bg:SetColorTexture(0, 0, 0, 0)

            mi.text = mi:CreateFontString(nil, "OVERLAY")
            mi.text:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormalSmall"))
            mi.text:SetText(item.text)
            mi.text:SetPoint("LEFT", mi, "LEFT", 8, 0)
            mi.text:SetJustifyH("LEFT")

            if item.value == self.selectedValue then
                mi.text:SetTextColor(unpack(Colors.accent))
            else
                mi.text:SetTextColor(unpack(Colors.textPrimary))
            end

            local itemValue = item.value
            mi:SetScript("OnClick", function()
                self:SetValue(itemValue)
                self.menu:Hide()
                if self.onChange then self.onChange(itemValue) end
            end)
            mi:SetScript("OnEnter", function(s) s.bg:SetColorTexture(unpack(Colors.cardHover)) end)
            mi:SetScript("OnLeave", function(s) s.bg:SetColorTexture(0, 0, 0, 0) end)

            table.insert(self.menuItems, mi)
            yOff = yOff + itemHeight
        end

        self.menu:SetSize(menuWidth, yOff + 2)
        self.menu:ClearAllPoints()
        self.menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
    end

    function dropdown:SetItems(newItems)
        self.items = newItems
        self:BuildMenu()
        self:SetValue(self.selectedValue)
    end

    -- Toggle menu on click
    local clickFrame = CreateFrame("Button", nil, dropdown)
    clickFrame:SetAllPoints()
    clickFrame:SetScript("OnClick", function()
        if dropdown.menu:IsShown() then
            dropdown.menu:Hide()
        else
            dropdown:BuildMenu()
            dropdown.menu:Show()
        end
    end)
    clickFrame:SetScript("OnEnter", function()
        dropdown:SetBackdropBorderColor(unpack(Colors.accent))
    end)
    clickFrame:SetScript("OnLeave", function()
        dropdown:SetBackdropBorderColor(unpack(Colors.cardBorder))
    end)

    -- Close menu when clicking elsewhere
    dropdown.menu:SetScript("OnShow", function(self)
        self:SetPropagateKeyboardInput(false)
    end)

    -- Initialize
    dropdown:SetValue(currentValue)
    dropdown:BuildMenu()

    return dropdown
end

---------------------------------------------------------------------
-- Build module dropdown items list
---------------------------------------------------------------------
local function GetModuleDropdownItems()
    local items = { { text = "All Modules", value = nil } }

    local moduleIds = {}
    for id in pairs(addon.modules) do
        if id ~= "_test" then table.insert(moduleIds, id) end
    end
    table.sort(moduleIds)

    for _, moduleId in ipairs(moduleIds) do
        local mod = addon.modules[moduleId]
        table.insert(items, { text = mod and mod.name or moduleId, value = moduleId })
    end
    return items
end

local function GetDateDropdownItems()
    return {
        { text = "All Time",   value = nil },
        { text = "Today",      value = "today" },
        { text = "Yesterday",  value = "yesterday" },
        { text = "This Week",  value = "week" },
        { text = "This Month", value = "month" },
    }
end


---------------------------------------------------------------------
-- History: time formatting
---------------------------------------------------------------------
local function FormatHistoryTimestamp(realTime)
    if not realTime then return "" end
    local now = time()
    local todayKey = date("%Y-%m-%d", now)
    local entryKey = date("%Y-%m-%d", realTime)

    if entryKey == todayKey then
        return date("%H:%M", realTime)
    elseif entryKey == date("%Y-%m-%d", now - 86400) then
        return "Yest " .. date("%H:%M", realTime)
    elseif (now - realTime) < 604800 then
        return date("%a %H:%M", realTime)
    else
        return date("%b %d %H:%M", realTime)
    end
end

local function GetDateRange()
    local now = time()
    local todayKey = date("%Y-%m-%d", now)

    if not historyDateFilter then
        return nil, nil
    elseif historyDateFilter == "today" then
        return todayKey, todayKey
    elseif historyDateFilter == "yesterday" then
        return date("%Y-%m-%d", now - 86400), date("%Y-%m-%d", now - 86400)
    elseif historyDateFilter == "week" then
        return date("%Y-%m-%d", now - 7 * 86400), todayKey
    elseif historyDateFilter == "month" then
        return date("%Y-%m-%d", now - 30 * 86400), todayKey
    end
    return nil, nil
end

local function RunHistorySearch()
    if not BNC_History_Search then
        historyResults = {}
        return
    end
    local startDate, endDate = GetDateRange()
    historyResults = BNC_History_Search(historySearch, historyModuleFilter, startDate, endDate)
    historyPage = 1
end

---------------------------------------------------------------------
-- Panel creation
---------------------------------------------------------------------
local function CreatePanel()
    -- Overlay
    overlay = CreateFrame("Button", "BazUINotifOverlay", UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("HIGH")
    overlay:SetFrameLevel(0)
    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    overlay:EnableMouse(true)
    overlay:SetScript("OnClick", function()
        if addon.TogglePanel and isShown then
            addon.TogglePanel()
        end
    end)
    overlay:Hide()

    -- Main panel
    panel = CreateFrame("Frame", "BazUINotifPanel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    -- The same flat chrome the tooltips wear.
    BazUI.Skin.Theme.ApplyFlatPanel(panel, Colors.panelBg, Colors.panelBorder)
    panel:SetFrameStrata("HIGH")
    panel:SetFrameLevel(10)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()

    -----------------------------------------------------------
    -- Header: Title + Clear all
    -----------------------------------------------------------
    panel.header = CreateFrame("Frame", nil, panel)
    panel.header:SetHeight(HEADER_HEIGHT)
    panel.header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    panel.header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)

    panel.titleText = panel.header:CreateFontString(nil, "OVERLAY")
    panel.titleText:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormalLarge"))
    panel.titleText:SetTextColor(unpack(Colors.accent))
    panel.titleText:SetText("Notifications")

    -- Settings gear button
    panel.gearBtn = CreateFrame("Button", nil, panel.header)
    panel.gearBtn:SetSize(20, 20)

    panel.gearBtn.icon = panel.gearBtn:CreateTexture(nil, "ARTWORK")
    panel.gearBtn.icon:SetSize(16, 16)
    panel.gearBtn.icon:SetPoint("CENTER", panel.gearBtn, "CENTER", 0, 0)
    panel.gearBtn.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    panel.gearBtn.icon:SetDesaturated(true)
    panel.gearBtn.icon:SetVertexColor(unpack(Colors.textMuted))

    panel.gearBtn:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(unpack(Colors.accent))
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Settings")
        GameTooltip:Show()
    end)
    panel.gearBtn:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(unpack(Colors.textMuted))
        self.icon:SetDesaturated(true)
        GameTooltip:Hide()
    end)
    panel.gearBtn:SetScript("OnClick", function()
        addon.TogglePanel()  -- close panel
        if addon.OpenOptions then addon.OpenOptions() end
    end)

    -- Clear / Purge button (changes based on tab)
    panel.actionBtn = CreateFrame("Button", nil, panel.header)
    panel.actionBtn:SetSize(55, HEADER_HEIGHT)
    panel.actionBtn.text = panel.actionBtn:CreateFontString(nil, "OVERLAY")
    panel.actionBtn.text:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormalSmall"))
    panel.actionBtn.text:SetText("Clear all")
    panel.actionBtn.text:SetTextColor(unpack(Colors.textMuted))
    panel.actionBtn.text:SetAllPoints()

    panel.actionBtn:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(Colors.accent)) end)
    panel.actionBtn:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(Colors.textMuted)) end)
    panel.actionBtn:SetScript("OnClick", function()
        if currentTab == "notifications" then
            BNC:DismissAll()
        else
            -- Purging history wipes every archived notification with
            -- no recovery. Route through the shared BazUI:Confirm
            -- primitive so the popup matches the rest of the BazUI
            -- UI (same fonts, buttons, backdrop) and the destructive
            -- accept button is visually flagged red.
            if BazUI.Confirm then
                BazUI:Confirm({
                    title       = "Purge history?",
                    body        = "Delete every archived notification? This can't be undone.",
                    acceptLabel = "Purge",
                    acceptStyle = "destructive",
                    onAccept    = function()
                        BNC:ClearHistory()
                        RunHistorySearch()
                        if panel.PopulateHistory then
                            panel.PopulateHistory()
                        end
                    end,
                })
            end
        end
    end)

    -- Header divider
    local hDiv = panel.header:CreateTexture(nil, "ARTWORK")
    hDiv:SetHeight(1)
    hDiv:SetPoint("BOTTOMLEFT", panel.header, "BOTTOMLEFT", PANEL_PADDING, 0)
    hDiv:SetPoint("BOTTOMRIGHT", panel.header, "BOTTOMRIGHT", -PANEL_PADDING, 0)
    hDiv:SetColorTexture(unpack(Colors.divider))

    -----------------------------------------------------------
    -- Tabs row
    -----------------------------------------------------------
    panel.tabRow = CreateFrame("Frame", nil, panel)
    panel.tabRow:SetHeight(TAB_HEIGHT)
    panel.tabRow:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -HEADER_HEIGHT)
    panel.tabRow:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PANEL_PADDING, -HEADER_HEIGHT)

    -- The suite's tab strip (Core/TabStrip.lua) in its underline style:
    -- text alone, the open tab bright over a gold rule.
    local TAB_KEYS = { "notifications", "history" }
    panel.tabStrip = BazUI.CreateTabStrip(nil, panel.tabRow, {
        style = "underline", tabHeight = TAB_HEIGHT, spacing = 16,
        dividerParent = panel.tabRow,
    })
    panel.tabStrip:SetPoint("BOTTOMLEFT", panel.tabRow, "BOTTOMLEFT", 0, 0)
    panel.tabStrip:SetTabSelectedCallback(function(tabID, isUserAction)
        if isUserAction then addon.SwitchTab(TAB_KEYS[tabID]) end
    end)
    panel.tabStrip:AddTab("Notifications")
    panel.tabStrip:AddTab("History")
    panel.tabStrip:Layout()
    panel.tabIDs = { notifications = 1, history = 2 }

    -----------------------------------------------------------
    -- Notifications content area
    -----------------------------------------------------------
    local tabOffset = TAB_HEIGHT
    local filterTop = HEADER_HEIGHT + tabOffset + 4
    local notifTop = filterTop + FILTER_ROW_HEIGHT + 4

    -- Module dropdown (notifications)
    panel.notifModuleDropdown = CreateDropdown(panel, 140, GetModuleDropdownItems(), nil, function(value)
        notifModuleFilter = value
        if panel.PopulateNotifications then panel.PopulateNotifications() end
    end)
    panel.notifModuleDropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -filterTop)

    -- Scroll
    notifScroll = addon.CreateScrollContainer(panel, CONTENT_WIDTH, PANEL_HEIGHT - notifTop - PANEL_PADDING)
    notifScroll.clipFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -notifTop)

    -- Empty text
    panel.notifEmpty = panel:CreateFontString(nil, "OVERLAY")
    panel.notifEmpty:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormal"))
    panel.notifEmpty:SetTextColor(unpack(Colors.textMuted))
    panel.notifEmpty:SetText("No notifications")
    panel.notifEmpty:SetPoint("CENTER", notifScroll.clipFrame, "CENTER", 0, 0)
    panel.notifEmpty:Hide()

    -----------------------------------------------------------
    -- History content area
    -----------------------------------------------------------
    local histFilterTop = filterTop
    local histSearchTop = histFilterTop + FILTER_ROW_HEIGHT + 4
    local histTop = histSearchTop + SEARCH_ROW_HEIGHT + 4

    -- Module dropdown (history)
    panel.histModuleDropdown = CreateDropdown(panel, 140, GetModuleDropdownItems(), nil, function(value)
        historyModuleFilter = value
        RunHistorySearch()
        if panel.PopulateHistory then panel.PopulateHistory() end
    end)
    panel.histModuleDropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -histFilterTop)

    -- Date dropdown (history)
    panel.histDateDropdown = CreateDropdown(panel, 120, GetDateDropdownItems(), nil, function(value)
        historyDateFilter = value
        RunHistorySearch()
        if panel.PopulateHistory then panel.PopulateHistory() end
    end)
    panel.histDateDropdown:SetPoint("LEFT", panel.histModuleDropdown, "RIGHT", 6, 0)

    -- Search box (history)
    panel.histSearchBox = BazUI.Skin.Theme.CreateSearchBox(panel, "Search history...", function(text)
        historySearch = text
        RunHistorySearch()
        if panel.PopulateHistory then panel.PopulateHistory() end
    end)
    panel.histSearchBox:SetSize(CONTENT_WIDTH, 22)
    panel.histSearchBox:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -histSearchTop)

    -- History scroll
    historyScroll = addon.CreateScrollContainer(panel, CONTENT_WIDTH, PANEL_HEIGHT - histTop - PANEL_PADDING)
    historyScroll.clipFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -histTop)

    -- History empty
    panel.histEmpty = panel:CreateFontString(nil, "OVERLAY")
    panel.histEmpty:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormal"))
    panel.histEmpty:SetTextColor(unpack(Colors.textMuted))
    panel.histEmpty:SetText("No history")
    panel.histEmpty:SetPoint("CENTER", historyScroll.clipFrame, "CENTER", 0, 0)
    panel.histEmpty:Hide()

    -- History count label
    panel.histCount = panel:CreateFontString(nil, "OVERLAY")
    panel.histCount:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormalSmall"))
    panel.histCount:SetTextColor(unpack(Colors.textMuted))
    panel.histCount:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PANEL_PADDING, 4)
    panel.histCount:Hide()

    -- Load More button (inside history scroll content)
    panel.loadMoreBtn = CreateFrame("Button", nil, historyScroll.content)
    panel.loadMoreBtn:SetSize(100, 24)
    panel.loadMoreBtn.bg = panel.loadMoreBtn:CreateTexture(nil, "BACKGROUND")
    panel.loadMoreBtn.bg:SetAllPoints()
    panel.loadMoreBtn.bg:SetColorTexture(unpack(Colors.accent))
    panel.loadMoreBtn.text = panel.loadMoreBtn:CreateFontString(nil, "OVERLAY")
    panel.loadMoreBtn.text:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormalSmall"))
    panel.loadMoreBtn.text:SetText("Load More")
    panel.loadMoreBtn.text:SetTextColor(1, 1, 1)
    panel.loadMoreBtn.text:SetAllPoints()
    panel.loadMoreBtn:SetScript("OnClick", function()
        historyPage = historyPage + 1
        panel.PopulateHistory()
    end)
    panel.loadMoreBtn:SetScript("OnEnter", function(self) self.bg:SetColorTexture(unpack(Colors.accentHover)) end)
    panel.loadMoreBtn:SetScript("OnLeave", function(self) self.bg:SetColorTexture(unpack(Colors.accent)) end)
    panel.loadMoreBtn:Hide()

    -----------------------------------------------------------
    -- Panel lifecycle
    -----------------------------------------------------------
    panel:SetScript("OnHide", function()
        isShown = false
        if overlay then overlay:Hide() end
        if timestampTicker then timestampTicker:Cancel(); timestampTicker = nil end
        addon.Events:Trigger("PANEL_HIDDEN")
    end)

    table.insert(UISpecialFrames, "BazUINotifPanel")
    addon.panel = panel
end

---------------------------------------------------------------------
-- Populate: Notifications tab
---------------------------------------------------------------------
local function ReleaseNotifUI()
    for _, card in ipairs(notifActiveCards) do addon.CardPool:Release(card) end
    wipe(notifActiveCards)
    for _, header in ipairs(notifActiveHeaders) do addon.GroupHeaderPool:Release(header) end
    wipe(notifActiveHeaders)
end

local function PopulateNotifications()
    if not panel then return end
    ReleaseNotifUI()

    -- Filter by selected module
    local grouped, order
    if notifModuleFilter then
        local notifs = BNC:GetNotifications(notifModuleFilter)
        if #notifs > 0 then
            grouped = { [notifModuleFilter] = notifs }
            order = { notifModuleFilter }
        else
            grouped = {}
            order = {}
        end
    else
        grouped, order = BNC:GetNotificationsByModule()
    end

    local yOffset = 0

    if #order == 0 then
        panel.notifEmpty:Show()
        panel.actionBtn:Hide()
        notifScroll:SetContentHeight(1)
        return
    end

    panel.notifEmpty:Hide()
    panel.actionBtn:Show()

    for _, moduleId in ipairs(order) do
        local notifications = grouped[moduleId]
        if notifications and #notifications > 0 then
            local header = addon.GroupHeaderPool:Acquire()
            addon.SetupGroupHeader(header, moduleId)
            header:SetParent(notifScroll.content)
            header:SetWidth(CONTENT_WIDTH)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", notifScroll.content, "TOPLEFT", 0, -yOffset)
            header:Show()
            table.insert(notifActiveHeaders, header)
            yOffset = yOffset + addon.GROUP_HEADER_HEIGHT + CARD_SPACING

            for _, notif in ipairs(notifications) do
                local card = addon.CardPool:Acquire()
                addon.SetupCard(card, notif)
                card:SetParent(notifScroll.content)
                card:SetWidth(CONTENT_WIDTH)
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", notifScroll.content, "TOPLEFT", 0, -yOffset)
                card:Show()
                table.insert(notifActiveCards, card)
                yOffset = yOffset + card:GetHeight() + CARD_SPACING
            end
            yOffset = yOffset + CARD_SPACING
        end
    end

    notifScroll:SetContentHeight(yOffset)
end

---------------------------------------------------------------------
-- Populate: History tab
---------------------------------------------------------------------
local function ReleaseHistoryUI()
    for _, card in ipairs(historyActiveCards) do historyCardPool:Release(card) end
    wipe(historyActiveCards)
end

local function PopulateHistory()
    if not panel then return end
    ReleaseHistoryUI()

    local totalCount = #historyResults
    local endIdx = math.min(historyPage * HISTORY_PAGE_SIZE, totalCount)

    if panel.histCount then
        if totalCount == 0 then
            panel.histCount:SetText("")
        else
            panel.histCount:SetText(string.format("%d of %d", endIdx, totalCount))
        end
    end

    if totalCount == 0 then
        panel.histEmpty:Show()
        panel.loadMoreBtn:Hide()
        historyScroll:SetContentHeight(1)
        return
    end
    panel.histEmpty:Hide()

    local yOffset = 0
    local lastDateKey = nil

    for i = 1, endIdx do
        local entry = historyResults[i]
        if not entry then break end

        -- Date separator
        local entryDateKey = entry.realTime and date("%Y-%m-%d", entry.realTime) or "?"
        if entryDateKey ~= lastDateKey then
            lastDateKey = entryDateKey
            local sep = historyCardPool:Acquire()
            sep:SetParent(historyScroll.content)
            sep:SetWidth(CONTENT_WIDTH)
            sep:SetHeight(22)
            sep:ClearAllPoints()
            sep:SetPoint("TOPLEFT", historyScroll.content, "TOPLEFT", 0, -yOffset)
            sep:SetBackdrop(nil)
            sep.isSeparator = true

            local todayKey = date("%Y-%m-%d", time())
            local displayDate
            if entryDateKey == todayKey then
                displayDate = "Today"
            elseif entryDateKey == date("%Y-%m-%d", time() - 86400) then
                displayDate = "Yesterday"
            else
                displayDate = date("%A, %b %d", entry.realTime)
            end

            local accentHex = string.format("%02x%02x%02x", Colors.accent[1]*255, Colors.accent[2]*255, Colors.accent[3]*255)
            sep.title:SetText("|cff" .. accentHex .. displayDate .. "|r")
            sep.title:ClearAllPoints()
            sep.title:SetPoint("LEFT", sep, "LEFT", 4, 0)
            sep.title:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormalSmall"))
            sep.message:SetText("")
            sep.timestamp:SetText("")
            sep.icon:Hide()
            sep.priorityBar:Hide()
            sep:Show()
            table.insert(historyActiveCards, sep)
            yOffset = yOffset + 22 + 2
        end

        -- Card
        local card = historyCardPool:Acquire()
        card:SetParent(historyScroll.content)
        card:SetWidth(CONTENT_WIDTH)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", historyScroll.content, "TOPLEFT", 0, -yOffset)
        card.isSeparator = false

        if entry.icon then card.icon:SetTexture(entry.icon); card.icon:Show()
        else card.icon:Hide() end

        card.title:SetText(entry.title or "")
        card.title:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormal"))
        card.title:ClearAllPoints()
        card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 6, 0)
        card.title:SetPoint("RIGHT", card, "RIGHT", -90, 0)
        card.message:SetText(entry.message or "")
        card.timestamp:SetText(FormatHistoryTimestamp(entry.realTime))

        if entry.priority == "high" then
            card.priorityBar:SetColorTexture(unpack(Colors.priorityHigh)); card.priorityBar:Show()
        elseif entry.priority == "low" then
            card.priorityBar:SetColorTexture(unpack(Colors.priorityLow)); card.priorityBar:Show()
        else
            card.priorityBar:Hide()
        end

        card.message:SetWidth(CONTENT_WIDTH - 16)
        local msgH = card.message:GetStringHeight() or 0
        local hasMsg = entry.message and entry.message ~= ""
        local h = 8 + 24 + (hasMsg and (3 + msgH) or 0) + 8
        card:SetHeight(math.max(40, h))
        card:Show()
        table.insert(historyActiveCards, card)
        yOffset = yOffset + card:GetHeight() + CARD_SPACING
    end

    -- Load more
    if endIdx < totalCount then
        panel.loadMoreBtn:ClearAllPoints()
        panel.loadMoreBtn:SetPoint("TOPLEFT", historyScroll.content, "TOPLEFT", (CONTENT_WIDTH - 100) / 2, -(yOffset + 6))
        panel.loadMoreBtn:Show()
        yOffset = yOffset + 36
    else
        panel.loadMoreBtn:Hide()
    end

    historyScroll:SetContentHeight(yOffset + 10)
end

-- Attach to panel for external access
local function AttachPopulators()
    panel.PopulateNotifications = PopulateNotifications
    panel.PopulateHistory = PopulateHistory
end

---------------------------------------------------------------------
-- Tab switching
---------------------------------------------------------------------
function addon.SwitchTab(tabKey)
    if not panel then return end

    currentTab = tabKey

    local tabID = panel.tabIDs and panel.tabIDs[tabKey]
    if tabID then
        panel.tabStrip:SetTabVisuallySelected(tabID)
        panel.tabStrip.selectedTabID = tabID
    end

    if tabKey == "notifications" then
        panel.actionBtn.text:SetText("Clear all")

        -- Show notif elements
        panel.notifModuleDropdown:Show()
        notifScroll.clipFrame:Show()

        -- Hide history elements
        panel.histModuleDropdown:Hide()
        panel.histDateDropdown:Hide()
        panel.histSearchBox:Hide()
        historyScroll.clipFrame:Hide()
        panel.histEmpty:Hide()
        panel.histCount:Hide()
        panel.loadMoreBtn:Hide()

        -- Refresh dropdown items
        panel.notifModuleDropdown:SetItems(GetModuleDropdownItems())
        panel.notifModuleDropdown:SetValue(notifModuleFilter)

        PopulateNotifications()

    elseif tabKey == "history" then
        panel.actionBtn.text:SetText("Purge")

        -- Hide notif elements
        panel.notifModuleDropdown:Hide()
        notifScroll.clipFrame:Hide()
        panel.notifEmpty:Hide()

        -- Show history elements
        panel.histModuleDropdown:Show()
        panel.histDateDropdown:Show()
        panel.histSearchBox:Show()
        historyScroll.clipFrame:Show()
        panel.histCount:Show()

        -- Refresh dropdown items
        panel.histModuleDropdown:SetItems(GetModuleDropdownItems())
        panel.histModuleDropdown:SetValue(historyModuleFilter)
        panel.histDateDropdown:SetValue(historyDateFilter)

        RunHistorySearch()
        PopulateHistory()
    end
end

---------------------------------------------------------------------
-- Layout helpers
---------------------------------------------------------------------
local function UpdateHeaderLayout()
    if not panel or not addon.db then return end
    local pos = addon.db.position
    local isLeft = (pos == "TOPLEFT" or pos == "BOTTOMLEFT")

    panel.titleText:ClearAllPoints()
    panel.actionBtn:ClearAllPoints()
    panel.gearBtn:ClearAllPoints()

    if isLeft then
        panel.titleText:SetPoint("LEFT", panel.header, "LEFT", 40, 0)
        panel.gearBtn:SetPoint("RIGHT", panel.header, "RIGHT", -PANEL_PADDING, 0)
        panel.actionBtn:SetPoint("RIGHT", panel.gearBtn, "LEFT", -6, 0)
    else
        panel.titleText:SetPoint("LEFT", panel.header, "LEFT", PANEL_PADDING, 0)
        panel.gearBtn:SetPoint("RIGHT", panel.header, "RIGHT", -40, 0)
        panel.actionBtn:SetPoint("RIGHT", panel.gearBtn, "LEFT", -6, 0)
    end
end

local function ReanchorPanel()
    if not panel or not addon.db then return end
    local btn = addon.GetToggleButton and addon.GetToggleButton()
    panel:ClearAllPoints()

    if btn then
        local pos = addon.db.position
        local inset = 3
        if pos == "TOPLEFT" then
            panel:SetPoint("TOPLEFT", btn, "TOPLEFT", -inset, inset)
        elseif pos == "TOPRIGHT" then
            panel:SetPoint("TOPRIGHT", btn, "TOPRIGHT", inset, inset)
        elseif pos == "BOTTOMLEFT" then
            panel:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -inset, -inset)
        elseif pos == "BOTTOMRIGHT" then
            panel:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", inset, -inset)
        end
    else
        addon.AnchorToCorner(panel, addon.db.position, 0, 30)
    end
end

local function UpdatePanelOpacity()
    if not panel or not addon.db then return end
    BazUI.Skin.Theme.SetFlatPanelColor(panel, Colors.panelBg, addon.db.panelOpacity)
end

---------------------------------------------------------------------
-- Show / Hide / Toggle
---------------------------------------------------------------------
local function ShowPanel()
    if not panel then return end
    addon.Animations.StopAll(panel)

    ReanchorPanel()
    UpdateHeaderLayout()
    UpdatePanelOpacity()
    AttachPopulators()

    -- Default to notifications tab
    addon.SwitchTab("notifications")

    overlay:Show()
    addon.Animations.FadeIn(panel, 0.2)
    isShown = true

    if timestampTicker then timestampTicker:Cancel() end
    timestampTicker = C_Timer.NewTicker(30, function()
        if currentTab == "notifications" then
            for _, card in ipairs(notifActiveCards) do
                addon.UpdateCardTimestamp(card)
            end
        end
    end)

    addon.Events:Trigger("PANEL_SHOWN")
end

local function HidePanel()
    if not panel then return end
    addon.Animations.StopAll(panel)
    overlay:Hide()
    panel:Hide()
end

function addon.TogglePanel()
    if isShown then HidePanel() else ShowPanel() end
end

function addon.IsPanelShown()
    return isShown
end

-- Public: open directly to history tab
function addon.ShowHistoryPanel()
    if not isShown then
        ShowPanel()
    end
    addon.SwitchTab("history")
end

---------------------------------------------------------------------
-- Events
---------------------------------------------------------------------
addon.Events:Register("CORE_LOADED", function()
    CreatePanel()
    ReanchorPanel()
end)

-- Debounced repopulate. Burst events (looting trash, multi-quest
-- turn-ins, achievement chains) used to call PopulateNotifications
-- once per event - and PopulateNotifications releases every active
-- card back to the pool then re-acquires + re-anchors them all. With
-- 5 events firing in the same frame and 30 cards visible, that's
-- 150 SetPoint/SetParent calls when only 5 are needed. Coalesce into
-- one render at the end of the frame batch.
local pendingPopulate = false
local function SchedulePopulate()
    if pendingPopulate then return end
    if not (isShown and currentTab == "notifications") then return end
    pendingPopulate = true
    C_Timer.After(0, function()
        pendingPopulate = false
        if isShown and currentTab == "notifications" then
            PopulateNotifications()
        end
    end)
end

addon.Events:Register("NOTIFICATION_ADDED",     SchedulePopulate)
addon.Events:Register("NOTIFICATION_UPDATED",   SchedulePopulate)
addon.Events:Register("NOTIFICATION_DISMISSED", SchedulePopulate)
addon.Events:Register("NOTIFICATIONS_CLEARED",  SchedulePopulate)
addon.Events:Register("HISTORY_CLEARED", function()
    if isShown and currentTab == "history" then
        RunHistorySearch()
        PopulateHistory()
    end
end)

addon.Events:Register("SETTING_CHANGED_position", function()
    ReanchorPanel()
    UpdateHeaderLayout()
end)
addon.Events:Register("SETTING_CHANGED_panelOpacity", UpdatePanelOpacity)
addon.Events:Register("SETTING_CHANGED_scale", function(scale)
    if panel then panel:SetScale(scale or 1) end
end)
