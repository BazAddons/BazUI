-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex: item lookup
--
-- No shipped database, and nothing to keep up to date. Two ways in:
--
--   A link or an ID   the server holds everything about one item and
--                     hands it over when asked, so this is exact and
--                     reaches anything in the game.
--   A name            the client cannot search the game's items; there
--                     is no such call, and pretending otherwise would
--                     mean shipping and maintaining a copy of the item
--                     table. So a name searches what this character has
--                     actually met: what it carries, wears, banks, and
--                     anything the client has looked up since. The index
--                     starts empty and fills in as you play.
--
-- Which is honest about the answer it can give, and says so on screen.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local addon = BazUI:GetModule("Codex")
local Theme = BazUI.Skin.Theme

local MAX_RESULTS = 200   -- drawn at once; the filter narrows past this
local ROW_H       = 20

Codex.customTabs = Codex.customTabs or {}

---------------------------------------------------------------------------
-- The index
---------------------------------------------------------------------------

local function Index()
    return addon:GetSetting("itemIndex") or {}
end

local function IndexSize()
    local n = 0
    for _ in pairs(Index()) do n = n + 1 end
    return n
end

-- Learn one item. The name is only available once the client has the
-- item's data; if it has not, we skip it and meet the item again later
-- (every path here fires repeatedly).
local function Remember(itemID)
    if not addon:GetSetting("indexItems") then return end
    itemID = tonumber(itemID)
    if not itemID then return false end
    local index = Index()
    if index[itemID] then return false end
    local name = C_Item.GetItemInfo(itemID)
    if not name then return false end
    index[itemID] = name
    addon:SetSetting("itemIndex", index)
    return true
end

-- Bags asks the client which containers this build actually has, so the
-- codex asks Bags rather than guessing at bag numbers of its own.
local function BagIDs()
    local bags = BazUI:GetModule("Bags")
    if bags and bags.GetAllBagIDs then return bags.GetAllBagIDs() end
    local ids = { Enum.BagIndex.Backpack }
    for i = 1, (NUM_BAG_SLOTS or 4) do
        local id = Enum.BagIndex["Bag_" .. i]
        if id then ids[#ids + 1] = id end
    end
    return ids
end

local function ScanContainers(ids)
    local learned = false
    for _, bagID in ipairs(ids) do
        local slots = C_Container.GetContainerNumSlots(bagID) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and info.itemID and Remember(info.itemID) then learned = true end
        end
    end
    return learned
end

local function ScanBags()
    return ScanContainers(BagIDs())
end

-- Only possible while the bank is open; the client knows nothing about
-- it otherwise.
local function ScanBank()
    local ids = { Enum.BagIndex.Bank }
    for i = 1, (NUM_BANKBAGSLOTS or 7) do
        local id = Enum.BagIndex["BankBag_" .. i]
        if id then ids[#ids + 1] = id end
    end
    return ScanContainers(ids)
end

local function ScanEquipped()
    local learned = false
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id and Remember(id) then learned = true end
    end
    return learned
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------

local pendingID

local function Sorted(ids, index)
    table.sort(ids, function(a, b) return (index[a] or "") < (index[b] or "") end)
    return ids
end

-- Everything the character has met, by name. This is what the page
-- shows before you type anything: the box narrows a list that is
-- already there rather than summoning one out of nothing.
local function Everything()
    local index = Index()
    local ids = {}
    for itemID in pairs(index) do ids[#ids + 1] = itemID end
    return Sorted(ids, index)
end

---------------------------------------------------------------------------
-- Categories
--
-- Bags already owns a category model and the classifier that places an
-- item in one, and those categories are the player's own: renamed,
-- reordered, added to. The codex asks Bags rather than growing a second
-- set of names that would drift away from the first.
---------------------------------------------------------------------------

local classified = {}   -- [itemID] = categoryKey, for this session

local function BagsCategories()
    local bags = BazUI:GetModule("Bags")
    return bags and bags.Categories or nil
end

local function BagCategories()
    local cats = BagsCategories()
    if not (cats and cats.GetAll) then return {} end
    local ok, list = pcall(cats.GetAll)
    return (ok and list) or {}
end

local function CategoryOf(itemID)
    if classified[itemID] then return classified[itemID] end
    local cats = BagsCategories()
    if not (cats and cats.Classify) then return nil end

    -- The classifier reads the item's type and quality, which the
    -- client only has once the item is loaded. Classifying too early
    -- lands everything in the catch-all, so wait and ask again rather
    -- than cache a wrong answer for the session.
    if not C_Item.GetItemInfo(itemID) then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return nil
    end

    local ok, key = pcall(cats.Classify, itemID)
    if not ok or not key then return nil end
    classified[itemID] = key
    return key
end

local function InCategory(ids, key)
    local out = {}
    for _, itemID in ipairs(ids) do
        if CategoryOf(itemID) == key then out[#out + 1] = itemID end
    end
    return out
end

-- A number or a link resolves exactly, anywhere in the game. Anything
-- else narrows the list. The second return is a line to show above it.
local function Resolve(query)
    query = (query or ""):trim()
    if query == "" then
        return Everything(), nil
    end

    local id = tonumber(query:match("item:(%d+)") or query)
    if id then
        if C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(id) then
            return {}, "No item carries the number " .. id .. "."
        end
        if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(id) then
            pendingID = id
            if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
            return {}, "Asking the server about item " .. id .. "..."
        end
        return { id }
    end

    local needle = query:lower()
    local index = Index()
    local hits = {}
    for itemID, name in pairs(index) do
        if type(name) == "string" and name:lower():find(needle, 1, true) then
            hits[#hits + 1] = itemID
        end
    end
    if #hits == 0 then
        return {}, string.format(
            "Nothing matching in the %d items this character has met. Paste a link or an item number to look up anything else.",
            IndexSize())
    end
    return Sorted(hits, index)
end

---------------------------------------------------------------------------
-- The page
--
-- This tab draws itself rather than handing rows to the panel: it owns a
-- text field, and its rows carry item art and a link.
---------------------------------------------------------------------------

local page, pool = nil, {}
local query = ""
local headerNote

local function AcquireRow(parent)
    local row = table.remove(pool)
    if row then
        row:SetParent(parent)
        return row
    end

    row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(Theme.colors.bgHover[1], Theme.colors.bgHover[2],
        Theme.colors.bgHover[3], 0.5)
    row.hover:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.label = Theme.FontString(row, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetJustifyH("LEFT")

    row.owned = Theme.FontString(row, "OVERLAY", "GameFontHighlightSmall")
    row.owned:SetPoint("RIGHT", -4, 0)
    row.owned:SetJustifyH("RIGHT")
    row.label:SetPoint("RIGHT", row.owned, "LEFT", -6, 0)

    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        if not self.itemID then return end
        local _, link = C_Item.GetItemInfo(self.itemID)
        if not link then return end
        -- Shift-click drops the link wherever you are typing, the way
        -- every other item in the game behaves.
        if IsShiftKeyDown() then
            if ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        elseif IsControlKeyDown() then
            DressUpItemLink(link)
        end
    end)
    return row
end

local function ReleaseRows()
    if not page then return end
    for _, row in ipairs(page.rows) do
        row:Hide()
        pool[#pool + 1] = row
    end
    page.rows = {}
end

---------------------------------------------------------------------------
-- The header
--
-- The box and the category row sit above the scroll so they stay put
-- while the list moves under them.
---------------------------------------------------------------------------

local header

local function BuildHeader(host)
    if header then
        header:SetParent(host)
        return header
    end

    header = CreateFrame("Frame", nil, host)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")

    header.box = Theme.CreateSearchBox(header, "Filter by name, or paste a link or an item number", function(text)
        query = text
        pendingID = nil
        Codex.Panel:QueueRefresh()
    end)
    header.box:SetPoint("TOPLEFT", 0, 0)
    header.box:SetPoint("TOPRIGHT", 0, 0)

    -- The categories are the ones from your bags, including any you
    -- made yourself: one classifier, one set of names, one place to
    -- change them.
    local strip = BazUI.CreateTabStrip(nil, header, {
        style = "panel", tabHeight = 20, spacing = 3,
        minTabWidth = 44, maxTabWidth = 110,
    })
    strip:SetPoint("TOPLEFT", header.box, "BOTTOMLEFT", 0, -6)
    header.strip = strip
    header.stripKeys = {}

    header.note = Theme.FontString(header, "OVERLAY", "GameFontHighlightSmall")
    header.note:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 2, -7)
    header.note:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    header.note:SetJustifyH("LEFT")
    header.note:SetJustifyV("TOP")
    header.note:SetHeight(26)
    header.note:SetWordWrap(true)
    header.note:SetTextColor(unpack(Theme.colors.textMuted))

    return header
end

local function RebuildCategories()
    local strip = header.strip
    strip:ClearTabs()
    header.stripKeys = {}

    local active = addon:GetSetting("itemCategory") or "all"
    local activeID

    local function Add(key, label)
        local id = strip:AddTab(label)
        header.stripKeys[id] = key
        if key == active then activeID = id end
    end

    Add("all", "All")
    for _, cat in ipairs(BagCategories() or {}) do
        Add(cat.key, cat.name or cat.key)
    end

    strip:SetTabSelectedCallback(function(tabID, isUserAction)
        local key = header.stripKeys[tabID]
        if not key then return end
        addon:SetSetting("itemCategory", key)
        if isUserAction then Codex.Panel:QueueRefresh() end
    end)
    strip:Layout()
    if activeID then
        strip:SetTabVisuallySelected(activeID)
        strip.selectedTabID = activeID
    end
end

local function RenderHeader(host, width)
    local h = BuildHeader(host)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT")
    h:SetWidth(width)
    h:Show()

    if not h._categoriesBuilt then
        h._categoriesBuilt = true
        RebuildCategories()
    end

    local hasCategories = #(BagCategories() or {}) > 0
    h.strip:SetShown(hasCategories)
    h.note:ClearAllPoints()
    h.note:SetPoint("TOPLEFT", hasCategories and h.strip or h.box, "BOTTOMLEFT", 2, -7)
    h.note:SetPoint("RIGHT", h, "RIGHT", -2, 0)
    h.note:SetText(headerNote or "")

    -- The note keeps a fixed two lines whatever it says, so the list
    -- below does not jump every time the wording changes length.
    local height = 22 + 6 + (hasCategories and 27 or 0) + 26 + 8
    h:SetHeight(height)
    return height
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

local function Build(parent)
    if page then
        page:SetParent(parent)
        return page
    end

    page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT")
    page.rows = {}

    -- Results live in the same card the rest of the codex draws, so a
    -- lookup and a lockout read as pages of one book.
    page.card = CreateFrame("Frame", nil, page)
    page.card:SetPoint("TOPLEFT")
    page.card:SetPoint("TOPRIGHT")
    Theme.ApplyFlatPanel(page.card, Theme.colors.bgRaised, Theme.colors.edge)

    return page
end

local function Render(content, width)
    local p = Build(content)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT")
    p:SetWidth(width)
    p:Show()
    ReleaseRows()

    local hits, note = Resolve(query)
    local y = 6

    local category = addon:GetSetting("itemCategory") or "all"
    local total = #hits
    if category ~= "all" then
        hits = InCategory(hits, category)
    end

    if note then
        headerNote = note
    elseif #hits == 0 then
        headerNote = (IndexSize() == 0)
            and "Nothing here yet. Items join the list as you carry, wear, bank and loot them; a link or an item number looks up anything else."
            or "Nothing in this category matches."
    else
        local shown = math.min(#hits, MAX_RESULTS)
        local head = (#hits == total)
            and string.format("%d items met", #hits)
            or string.format("%d of %d", #hits, IndexSize())
        headerNote = shown < #hits
            and string.format("%s, showing the first %d. Keep typing to narrow it.", head, shown)
            or head
    end
    if header and header:IsShown() then
        header.note:SetText(headerNote)
    end

    for i = 1, math.min(#hits, MAX_RESULTS) do
        local itemID = hits[i]
        local name, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(itemID)
        if not name then
            -- Known by name from the index but not yet loaded this
            -- session: ask, and draw what we have meanwhile.
            if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
            name = Index()[itemID] or ("Item " .. itemID)
        end

        local row = AcquireRow(p.card)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 1, -y)
        row:SetPoint("TOPRIGHT", -1, -y)
        row.itemID = itemID
        row.icon:SetTexture(texture
            or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
            or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.label:SetText(name)
        local colour = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if colour then
            row.label:SetTextColor(colour.r, colour.g, colour.b)
        else
            row.label:SetTextColor(unpack(Theme.colors.text))
        end
        local count = C_Item.GetItemCount(itemID, true) or 0
        row.owned:SetText(count > 0 and ("carrying " .. count) or "")
        row.owned:SetTextColor(unpack(Theme.colors.textMuted))
        row:Show()
        p.rows[#p.rows + 1] = row
        y = y + ROW_H
    end

    local cardHeight = math.max(y + 6, 28)
    p.card:SetHeight(cardHeight)
    p.card:SetShown(#hits > 0)

    local used = (#hits > 0) and cardHeight or 1
    p:SetHeight(used)
    Codex.customTabs.items.height = used
end

Codex.customTabs.items = {
    label        = "Items",
    order        = 30,
    RenderHeader = RenderHeader,
    Render       = Render,
    Hide         = function()
        if page then page:Hide() end
        if header then header:Hide() end
    end,
    height = 1,
    GetHighlights = function()
        local highlights = {
            { value = IndexSize(), label = "items this character has met" },
        }
        local key = addon:GetSetting("itemCategory")
        if key and key ~= "all" then
            for _, cat in ipairs(BagCategories()) do
                if cat.key == key then
                    highlights[#highlights + 1] = {
                        value = #InCategory(Everything(), key),
                        label = "in " .. (cat.name or key),
                    }
                    break
                end
            end
        end
        return highlights
    end,
}

---------------------------------------------------------------------------
-- Meeting items
--
-- Every path an item takes past this character adds it to the index:
-- carried, worn, banked, or simply looked up by the client for any
-- reason at all, which covers loot, vendors, quest rewards and links
-- other people post.
---------------------------------------------------------------------------

BazUI:QueueForLogin(function()
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("BAG_UPDATE_DELAYED")
    watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    watcher:RegisterEvent("BANKFRAME_OPENED")
    watcher:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    watcher:SetScript("OnEvent", function(_, event, arg1)
        local learned
        if event == "GET_ITEM_INFO_RECEIVED" then
            learned = Remember(arg1)
            -- A lookup the search box is waiting on has arrived.
            if pendingID and arg1 == pendingID then
                pendingID = nil
                learned = true
            end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            learned = ScanEquipped()
        elseif event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then
            learned = ScanBank()
        else
            learned = ScanBags()
        end
        if learned and Codex:IsShown() then Codex.Panel:QueueRefresh() end
    end)

    -- Items are not loaded the instant the world is, so the first sweep
    -- waits for the client to catch up. Anything it misses arrives
    -- through GET_ITEM_INFO_RECEIVED anyway.
    C_Timer.After(5, function()
        ScanBags()
        ScanEquipped()
    end)
end)
