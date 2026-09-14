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

local MAX_RESULTS = 60
local ROW_H       = 20
local HEAD_H      = 50

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

-- A number or a link resolves exactly. Anything else is a name search
-- over the index. The second return is a line to show instead of rows.
local function Resolve(query)
    query = (query or ""):trim()
    if query == "" then
        return {}, string.format(
            "Search by name across the %d items this character has met, or paste an item link or an item number for anything else.",
            IndexSize())
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
    table.sort(hits, function(a, b) return (index[a] or "") < (index[b] or "") end)
    return hits
end

---------------------------------------------------------------------------
-- The page
--
-- This tab draws itself rather than handing rows to the panel: it owns a
-- text field, and its rows carry item art and a link.
---------------------------------------------------------------------------

local page, pool = nil, {}
local query = ""

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

local function Build(parent)
    if page then
        page:SetParent(parent)
        return page
    end

    page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT")
    page.rows = {}

    page.box = Theme.CreateSearchBox(page, "Item name, link or number", function(text)
        query = text
        pendingID = nil
        Codex.Panel:QueueRefresh()
    end)
    page.box:SetPoint("TOPLEFT", 0, 0)
    page.box:SetPoint("TOPRIGHT", 0, 0)

    page.note = Theme.FontString(page, "OVERLAY", "GameFontHighlightSmall")
    page.note:SetPoint("TOPLEFT", page.box, "BOTTOMLEFT", 2, -6)
    page.note:SetPoint("TOPRIGHT", page.box, "BOTTOMRIGHT", -2, -6)
    page.note:SetJustifyH("LEFT")
    page.note:SetTextColor(unpack(Theme.colors.textMuted))

    -- Results live in the same card the rest of the codex draws, so a
    -- lookup and a lockout read as pages of one book.
    page.card = CreateFrame("Frame", nil, page)
    page.card:SetPoint("TOPLEFT", 0, -HEAD_H)
    page.card:SetPoint("TOPRIGHT", 0, -HEAD_H)
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

    if note then
        p.note:SetText(note)
    else
        local shown = math.min(#hits, MAX_RESULTS)
        p.note:SetText(shown < #hits
            and string.format("%d found, showing the first %d", #hits, shown)
            or string.format("%d found", #hits))
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

    local total = HEAD_H + (#hits > 0 and cardHeight or 0)
    p:SetHeight(math.max(total, 1))
    Codex.customTabs.items.height = total
end

Codex.customTabs.items = {
    label  = "Items",
    order  = 30,
    Render = Render,
    Hide   = function() if page then page:Hide() end end,
    height = 1,
    GetHighlights = function()
        return {
            { value = IndexSize(), label = "items this character has met" },
        }
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
