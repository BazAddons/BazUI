-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex: item lookup
--
-- Three ways in:
--
--   A link or an ID   the server holds everything about one item and
--                     hands it over when asked, so this is exact and
--                     reaches anything in the game.
--   A name            the client cannot search its own items; there is
--                     no such call. So BazUI ships the game's item list
--                     for the client it is built for - Data/Items.lua,
--                     generated from the game's own tables - and a name
--                     searches that. Where the catalogue is for another
--                     client (retail, today) a name falls back to what
--                     this character has met.
--   Nothing           the list you see before typing is what this
--                     character has met: carried, worn, banked, or
--                     looked up by the client for any reason. Eighteen
--                     thousand rows is not a page anyone reads; the
--                     ones you have touched are.
--
-- A row is drawn from the client's own data the moment it has any, and
-- from the catalogue until then - so a search result is never a bare
-- number waiting on the server, and nothing is asked of the server for
-- an item nobody has pointed at.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local addon = BazUI:GetModule("Codex")
local Theme = BazUI.Skin.Theme

local ROW_H = 26   -- a banded row, the same one the rest of the codex draws
local WHEEL = 3    -- rows per notch of the wheel

-- The game's own star, the one the reputation pane marks a watched
-- faction with. A sheet of four; the hollow one and the filled one.
local STAR_FILE   = "Interface\\Common\\ReputationStar"
local STAR_EMPTY  = { 0, 0.5, 0, 0.5 }
local STAR_FILLED = { 0.5, 1, 0.5, 1 }

-- Draw a row's star for whether the item is wanted.
local function SetStar(row)
    local wanted = row.itemID and Codex.Wishlist and Codex.Wishlist.Has(row.itemID)
    row.star.tex:SetTexCoord(unpack(wanted and STAR_FILLED or STAR_EMPTY))
    row.star.tex:SetAlpha(wanted and 1 or 0.35)
    row.star.wanted = wanted and true or false
end

Codex.customTabs = Codex.customTabs or {}

---------------------------------------------------------------------------
-- The index
---------------------------------------------------------------------------

local function Index()
    return addon:GetSetting("itemIndex") or {}
end

-- The shipped item list, or nil where it describes a different client.
local function Catalogue()
    local Items = Codex.Items
    if Items and Items.Available and Items.Available() then return Items end
    return nil
end

-- What the classifier would have asked the client for, from the
-- catalogue instead. Missing what the table does not carry - bind type,
-- equip slot, stack size - so a custom rule on one of those simply does
-- not match until the item has been loaded, which is the fail-safe way
-- round.
local function CatalogueMeta(rec)
    return {
        name = rec.name, quality = rec.quality,
        ilvl = rec.ilvl, minLvl = rec.minLvl,
        classID = rec.classID, subclassID = rec.subclassID,
    }
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
    if not (ok and list) then return {} end
    -- The bag has categories for its empty slots. An item lookup has no
    -- empty slots to look up.
    local out = {}
    for _, cat in ipairs(list) do
        if not (type(cat.key) == "string" and cat.key:find("^empty")) then
            out[#out + 1] = cat
        end
    end
    return out
end

local function CategoryOf(itemID)
    if classified[itemID] then return classified[itemID] end
    local cats = BagsCategories()
    if not (cats and cats.Classify) then return nil end

    -- The classifier reads the item's type and quality, which the
    -- client only has once the item is loaded. The catalogue has both,
    -- so an item the client has never seen is classified from that and
    -- the server is not asked - a search across the whole game would
    -- otherwise be thousands of requests for items nobody pointed at.
    if not C_Item.GetItemInfo(itemID) then
        local cat = Catalogue()
        local rec = cat and cat.Get(itemID)
        if rec then
            local ok, key = pcall(cats.Classify, itemID, rec.quality, rec.classID, CatalogueMeta(rec))
            if ok and key then
                classified[itemID] = key
                return key
            end
            return nil
        end
        -- No catalogue for this client: wait for the item and ask
        -- again, rather than cache a wrong answer for the session.
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

    -- Every item the game has, where the catalogue is for this client.
    local cat = Catalogue()
    if cat then
        local hits = cat.Search(needle)
        if #hits == 0 then
            return {}, string.format(
                "Nothing called that among the %d items in the game. Paste a link or an item number to look up anything else.",
                cat.Count())
        end
        return hits
    end

    -- Otherwise, what this character has met.
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
local pendingHits = {}   -- what the header resolved, for the list to draw

local function AcquireRow(parent)
    local row = table.remove(pool)
    if row then
        row:SetParent(parent)
        return row
    end

    row = Codex.Panel.CreateBandRow(parent)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.label = Theme.FontString(row, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    -- The star. Hollow and faint until you want the thing; filled and
    -- bright once you do. One click either way, and the Wishlist page
    -- follows in the same redraw.
    row.star = CreateFrame("Button", nil, row)
    row.star:SetSize(18, 18)
    row.star:SetPoint("RIGHT", -8, 0)
    row.star.tex = row.star:CreateTexture(nil, "ARTWORK")
    row.star.tex:SetAllPoints()
    row.star.tex:SetTexture(STAR_FILE)
    row.star:SetScript("OnClick", function(self)
        local r = self:GetParent()
        if not (r.itemID and Codex.Wishlist) then return end
        Codex.Wishlist.Toggle(r.itemID)
        SetStar(r)
    end)
    row.star:SetScript("OnEnter", function(self)
        local r = self:GetParent()
        r.hover:Show()
        self.tex:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.wanted and "On your wishlist" or "Want it",
            unpack(Theme.colors.text))
        GameTooltip:AddLine(self.wanted and "Click to take it off." or "Click to add it to the Wishlist.",
            0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    row.star:SetScript("OnLeave", function(self)
        local r = self:GetParent()
        r.hover:Hide()
        SetStar(r)
        GameTooltip:Hide()
    end)

    row.owned = Theme.FontString(row, "OVERLAY", "GameFontHighlightSmall")
    row.owned:SetPoint("RIGHT", row.star, "LEFT", -8, 0)
    row.owned:SetJustifyH("RIGHT")
    row.label:SetPoint("RIGHT", row.owned, "LEFT", -10, 0)

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

-- The header resolves the query and hands the result down to the list,
-- so both halves of the page are drawn from one answer and the line of
-- text above the list is never a pass behind it.
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

    -- Categories are the player's to add to, so the row has no fixed
    -- width and wraps to a second line rather than running off the edge.
    local stripHeight = 0
    if hasCategories then
        h.strip:SetWrapWidth(width)
        h.strip:Layout()
        stripHeight = math.ceil(h.strip:GetHeight() or 20)
    end

    local hits, note = Resolve(query)
    local category = addon:GetSetting("itemCategory") or "all"
    if category ~= "all" then hits = InCategory(hits, category) end
    pendingHits = hits

    -- The count already sits in the rail, so this line is kept for the
    -- times there is something to say that the rail cannot say.
    if note then
        headerNote = note
    elseif #hits == 0 then
        if IndexSize() > 0 then
            headerNote = "Nothing in this category matches."
        elseif Catalogue() then
            headerNote = "Nothing met yet. Items join this list as you carry, wear, bank and loot them. Type a name to search every item in the game."
        else
            headerNote = "Nothing here yet. Items join the list as you carry, wear, bank and loot them; a link or an item number looks up anything else."
        end
    else
        headerNote = nil
    end

    h.note:ClearAllPoints()
    h.note:SetPoint("TOPLEFT", hasCategories and h.strip or h.box, "BOTTOMLEFT", 2, -7)
    h.note:SetPoint("RIGHT", h, "RIGHT", -2, 0)
    h.note:SetText(headerNote or "")
    h.note:SetShown(headerNote ~= nil)

    local noteHeight = 0
    if headerNote then
        noteHeight = 7 + math.ceil((h.note:GetStringHeight() or 12) + 2)
    end

    local height = 22 + (hasCategories and 6 + stripHeight or 0) + noteHeight + 8
    h:SetHeight(height)
    return height
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

-- The list is virtual. It used to draw one frame per result and stop
-- at two hundred, which was a cap you noticed the moment there were
-- eighteen thousand items to search. Now the card is the height of the
-- page, holds only the rows that fit in it, and the wheel changes which
-- slice of the results those rows show. Twenty frames, however many
-- hits; nothing is capped and nothing tall is ever built.
--
-- `first` is the index of the top row. It is kept across renders - a
-- bag update redraws the page and must not throw you back to the top -
-- and reset only when the question changes.

local function Build(parent)
    if page then
        page:SetParent(parent)
        return page
    end

    page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT")
    page.rows = {}
    page.first = 0
    page.hits = {}

    -- Results live in the same card the rest of the codex draws, so a
    -- lookup and a lockout read as pages of one book.
    page.card = Codex.Panel.CreateBox(page)
    page.card:SetPoint("TOPLEFT")
    page.card:SetPoint("TOPRIGHT")

    -- The same arrow every scrolling block wears, in the same place.
    page.hint = page.card:CreateTexture(nil, "OVERLAY")
    page.hint:SetPoint("BOTTOM", page.card, "BOTTOM", 0, 4)
    BazUI.SetArrowTexture(page.hint, "DOWN", 20)
    page.hint:SetAlpha(0.45)
    page.hint:Hide()

    page.card:EnableMouseWheel(true)
    page.card:SetScript("OnMouseWheel", function(_, delta)
        local most = math.max(0, #page.hits - (page.visible or 1))
        local to = math.max(0, math.min(most, page.first - delta * WHEEL))
        if to ~= page.first then
            page.first = to
            page.FillRows()
        end
    end)

    return page
end

-- Draw the rows for the current slice. Rows are taken from the pool
-- and handed back each time; twenty of them, so it costs nothing.
local function FillRows()
    if not page then return end
    ReleaseRows()

    local hits = page.hits
    local visible = page.visible or 0
    local y = 10

    for i = page.first + 1, math.min(#hits, page.first + visible) do
        local itemID = hits[i]
        local name, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(itemID)
        if not name then
            -- Not loaded this session. The catalogue has the name, the
            -- colour and the picture, which is all a row needs, so the
            -- server is not asked for a search result; hovering the row
            -- asks for the tooltip, which is when it becomes wanted.
            local cat = Catalogue()
            local rec = cat and cat.Get(itemID)
            if rec then
                name, quality, texture = rec.name, rec.quality, rec.icon
            else
                -- Known by name from the met list only: ask, and draw
                -- what we have meanwhile.
                if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
                name = Index()[itemID] or ("Item " .. itemID)
            end
        end

        local row = AcquireRow(page.card)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 10, -y)
        row:SetPoint("TOPRIGHT", -10, -y)
        Codex.Panel.SetRowBand(row, i)
        row.itemID = itemID
        SetStar(row)
        row.icon:SetTexture(texture
            or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
            or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.label:SetText(name)
        local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if color then
            row.label:SetTextColor(color.r, color.g, color.b)
        else
            row.label:SetTextColor(unpack(Theme.colors.text))
        end
        local count = C_Item.GetItemCount(itemID, true) or 0
        row.owned:SetText(count > 0 and ("carrying " .. count) or "")
        row.owned:SetTextColor(unpack(Theme.colors.textMuted))
        row:Show()
        page.rows[#page.rows + 1] = row
        y = y + ROW_H
    end

    local most = math.max(0, #hits - visible)
    page.hint:SetShown(most > 0 and page.first < most)
end

-- What the last render was asked, so a redraw for some other reason -
-- a bag update, a loaded item - keeps its place, and only a new
-- question starts from the top.
local lastQuestion

local function Render(content, width)
    local p = Build(content)
    p.FillRows = FillRows
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT")
    p:SetWidth(width)
    p:Show()

    -- The header already resolved the query for this pass.
    p.hits = pendingHits or {}

    local question = query .. "\1" .. tostring(addon:GetSetting("itemCategory") or "all")
    if question ~= lastQuestion then
        lastQuestion = question
        p.first = 0
    end

    -- The card is the page: as tall as the room below the header, and
    -- no taller, so the panel has nothing of its own to scroll.
    local room = math.max((Codex.Panel.ContentHeight() or 300) - 2, ROW_H + 20)
    p.visible = math.max(1, math.floor((room - 20) / ROW_H))
    p.first = math.max(0, math.min(p.first, #p.hits - p.visible))

    local cardHeight = (#p.hits > 0)
        and (math.min(#p.hits, p.visible) * ROW_H + 20)
        or 28
    p.card:SetHeight(cardHeight)
    p.card:SetShown(#p.hits > 0)

    FillRows()

    local used = (#p.hits > 0) and cardHeight or 1
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
        local catalogue = Catalogue()
        if catalogue then
            highlights[#highlights + 1] = { value = catalogue.Count(), label = "items in the game" }
        end
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

BazUI:QueueForModule("Codex", function()
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
