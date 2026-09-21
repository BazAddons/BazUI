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
--                     searches that. Where the catalog is for another
--                     client (retail, today) a name falls back to what
--                     this character has met.
--   Nothing           every item in the game, in name order, for
--                     browsing - by class, subclass and slot, which is
--                     the tree the auction house browses by. The list
--                     is virtual, so seventeen thousand rows cost the
--                     same as twenty. An item this character has met -
--                     carried, worn, banked, or looked up by the client
--                     for any reason - wears a mark on its row. Where
--                     there is no catalog the met items are the list.
--
-- A row is drawn from the client's own data the moment it has any, and
-- from the catalog until then - so a search result is never a bare
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
local function Catalog()
    local Items = Codex.Items
    if Items and Items.Available and Items.Available() then return Items end
    return nil
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

-- What the page shows before you type anything: every item there is,
-- where the catalog is for this client, and otherwise what you have
-- met. The box narrows a list that is already there rather than
-- summoning one out of nothing.
local function Everything()
    local cat = Catalog()
    if cat then return cat.All() end
    local index = Index()
    local ids = {}
    for itemID in pairs(index) do ids[#ids + 1] = itemID end
    return Sorted(ids, index)
end

---------------------------------------------------------------------------
-- The tree
--
-- The game's own: class, then subclass, and for armor the slot, which is
-- the tree the auction house browses by. Weapon splits into Daggers,
-- Staves, Swords; Armor into Cloth, Leather, Mail, Plate and then into
-- Head, Chest, Legs. The names come from the client in your language,
-- so nothing is written down; the counts come from the catalog. With no
-- catalog there is no tree, only All, because the tree is built by
-- counting what there is.
--
-- The Bags categories used to be the tabs here. They are about how you
-- sort a bag, and Equipment as a bag category is not Armor as a class;
-- for browsing the whole game the game's taxonomy is the right one.
---------------------------------------------------------------------------

local ARMOR = 4

-- Slots the auction house folds together: a robe is a chest piece, and
-- the right-hand ranged slot is the ranged slot.
local SLOT_FOLD = { [20] = 5, [26] = 15 }

local function FoldSlot(inv)
    return SLOT_FOLD[inv] or inv
end

local function ClassName(classID)
    local name = C_Item and C_Item.GetItemClassInfo and C_Item.GetItemClassInfo(classID)
        or (_G.GetItemClassInfo and _G.GetItemClassInfo(classID))
    return name or ("Class " .. classID)
end

local function SubclassName(classID, subclassID)
    local name = C_Item and C_Item.GetItemSubClassInfo and C_Item.GetItemSubClassInfo(classID, subclassID)
        or (_G.GetItemSubClassInfo and _G.GetItemSubClassInfo(classID, subclassID))
    return name or ("Type " .. subclassID)
end

local function SlotName(inv)
    local name = C_Item and C_Item.GetItemInventorySlotInfo and C_Item.GetItemInventorySlotInfo(inv)
        or (_G.GetItemInventorySlotInfo and _G.GetItemInventorySlotInfo(inv))
    return name or ("Slot " .. inv)
end

-- Counted once from the catalog: which classes there are, which
-- subclasses each has, which slots each armor type comes in.
local tree

local function ById(a, b) return a.id < b.id end

local function BuildTree()
    if tree then return tree end
    local cat = Catalog()
    if not cat then return nil end

    local classes, order = {}, {}
    for _, rec in pairs(cat.Load()) do
        local c = classes[rec.classID]
        if not c then
            c = { id = rec.classID, count = 0, subs = {}, subOrder = {} }
            classes[rec.classID] = c
            order[#order + 1] = c
        end
        c.count = c.count + 1

        local sc = c.subs[rec.subclassID]
        if not sc then
            sc = { id = rec.subclassID, count = 0, slots = {}, slotOrder = {} }
            c.subs[rec.subclassID] = sc
            c.subOrder[#c.subOrder + 1] = sc
        end
        sc.count = sc.count + 1

        if rec.classID == ARMOR and rec.slot and rec.slot > 0 then
            local inv = FoldSlot(rec.slot)
            local sl = sc.slots[inv]
            if not sl then
                sl = { id = inv, count = 0 }
                sc.slots[inv] = sl
                sc.slotOrder[#sc.slotOrder + 1] = sl
            end
            sl.count = sl.count + 1
        end
    end

    table.sort(order, ById)
    for _, c in ipairs(order) do
        table.sort(c.subOrder, ById)
        for _, sc in ipairs(c.subOrder) do table.sort(sc.slotOrder, ById) end
    end
    tree = { classes = order, byClass = classes }
    return tree
end

-- What is picked. Numbers, or nil for "all of them" at that level.
local function Picked()
    return tonumber(addon:GetSetting("itemClass")),
           tonumber(addon:GetSetting("itemSubclass")),
           tonumber(addon:GetSetting("itemSlot"))
end

local function Pick(class, subclass, slot)
    addon:SetSetting("itemClass", class)
    addon:SetSetting("itemSubclass", subclass)
    addon:SetSetting("itemSlot", slot)
end

-- The hits that are inside whatever is picked. A straight pass over
-- the list against the catalog, seventeen thousand comparisons at the
-- most, which is nothing.
local function Narrow(hits)
    local class, subclass, slot = Picked()
    if not class then return hits end
    local cat = Catalog()
    if not cat then return hits end
    local byID = cat.Load()
    local out = {}
    for _, itemID in ipairs(hits) do
        local rec = byID[itemID]
        if rec and rec.classID == class
            and (not subclass or rec.subclassID == subclass)
            and (not slot or (rec.slot and FoldSlot(rec.slot) == slot))
        then
            out[#out + 1] = itemID
        end
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

    -- Every item the game has, where the catalog is for this client.
    local cat = Catalog()
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
        GameTooltip:SetText(self.wanted and "Remove from Wishlist" or "Add to Wishlist",
            unpack(Theme.colors.text))
        GameTooltip:Show()
    end)
    row.star:SetScript("OnLeave", function(self)
        local r = self:GetParent()
        r.hover:Hide()
        SetStar(r)
        GameTooltip:Hide()
    end)

    -- The mark for an item this character has met. Drawn on the row
    -- rather than filtered into a tab of its own: the question "have I
    -- seen this" is asked about the item in front of you, and a mark
    -- answers it there. A frame rather than a bare texture so it can
    -- say in words what it means.
    row.met = CreateFrame("Frame", nil, row)
    row.met:SetSize(16, 16)
    row.met:SetPoint("RIGHT", row.star, "LEFT", -6, 0)
    row.met.tex = row.met:CreateTexture(nil, "ARTWORK")
    row.met.tex:SetAllPoints()
    row.met.tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    row.met.tex:SetAlpha(0.85)
    row.met:SetScript("OnEnter", function(self)
        self:GetParent().hover:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Seen on this character", unpack(Theme.colors.text))
        GameTooltip:Show()
    end)
    row.met:SetScript("OnLeave", function(self)
        self:GetParent().hover:Hide()
        GameTooltip:Hide()
    end)

    row.owned = Theme.FontString(row, "OVERLAY", "GameFontHighlightSmall")
    row.owned:SetPoint("RIGHT", row.met, "LEFT", -6, 0)
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

    -- Three strips, one per level of the tree: class, subclass, and for
    -- armor the slot. Each appears when the level above has a pick.
    header.strips = {}
    local above = header.box
    for level = 1, 3 do
        local strip = BazUI.CreateTabStrip(nil, header, {
            style = "panel", tabHeight = 20, spacing = 3,
            minTabWidth = 44, maxTabWidth = 130,
        })
        strip:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -6)
        strip.keys = {}
        strip:Hide()
        header.strips[level] = strip
        above = strip
    end
    header.strip = header.strips[1]

    header.note = Theme.FontString(header, "OVERLAY", "GameFontHighlightSmall")
    header.note:SetPoint("TOPLEFT", header.strip, "BOTTOMLEFT", 2, -7)
    header.note:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    header.note:SetJustifyH("LEFT")
    header.note:SetJustifyV("TOP")
    header.note:SetHeight(26)
    header.note:SetWordWrap(true)
    header.note:SetTextColor(unpack(Theme.colors.textMuted))

    return header
end

-- Fill one strip with a list of { id, label }, an All in front, and
-- select the one that is picked. `onPick` gets the id, or nil for All.
local function FillStrip(strip, entries, picked, onPick)
    strip:ClearTabs()
    strip.keys = {}
    local activeID

    local function Add(id, label)
        local tabID = strip:AddTab(label)
        strip.keys[tabID] = id or false
        if id == picked then activeID = tabID end
    end

    Add(nil, "All")
    for _, e in ipairs(entries) do Add(e.id, e.label) end

    strip:SetTabSelectedCallback(function(tabID, isUserAction)
        if not isUserAction then return end
        local id = strip.keys[tabID]
        onPick(id or nil)
    end)
    strip:Layout()
    if activeID then
        strip:SetTabVisuallySelected(activeID)
        strip.selectedTabID = activeID
    end
end

-- Lay the tree out across the strips for what is picked. Called on
-- every header render, since a pick changes which strips exist.
local function RebuildTree()
    local t = BuildTree()
    local class, subclass, slot = Picked()
    local s1, s2, s3 = header.strips[1], header.strips[2], header.strips[3]

    if not t then
        -- No catalog: nothing to browse by, so no strips at all.
        s1:Hide(); s2:Hide(); s3:Hide()
        return 0
    end

    local shown = 1
    local entries = {}
    for _, c in ipairs(t.classes) do
        entries[#entries + 1] = { id = c.id, label = ClassName(c.id) }
    end
    FillStrip(s1, entries, class, function(id)
        Pick(id, nil, nil)
        Codex.Panel:QueueRefresh()
    end)
    s1:Show()

    local c = class and t.byClass[class]
    if c and #c.subOrder > 1 then
        entries = {}
        for _, sc in ipairs(c.subOrder) do
            entries[#entries + 1] = { id = sc.id, label = SubclassName(class, sc.id) }
        end
        FillStrip(s2, entries, subclass, function(id)
            Pick(class, id, nil)
            Codex.Panel:QueueRefresh()
        end)
        s2:Show()
        shown = 2
    else
        s2:Hide()
    end

    local sc = c and subclass and c.subs[subclass]
    if class == ARMOR and sc and #sc.slotOrder > 1 then
        entries = {}
        for _, sl in ipairs(sc.slotOrder) do
            entries[#entries + 1] = { id = sl.id, label = SlotName(sl.id) }
        end
        FillStrip(s3, entries, slot, function(id)
            Pick(class, subclass, id)
            Codex.Panel:QueueRefresh()
        end)
        s3:Show()
        shown = 3
    else
        s3:Hide()
    end

    return shown
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

    -- The strips, for what is picked. Each wraps to a second line
    -- rather than running off the edge, so their heights are read back.
    local shown = RebuildTree()
    local stripsHeight = 0
    local last = h.box
    for level = 1, shown do
        local strip = h.strips[level]
        strip:SetWrapWidth(width)
        strip:Layout()
        stripsHeight = stripsHeight + 6 + math.ceil(strip:GetHeight() or 20)
        last = strip
    end

    local hits, note = Resolve(query)
    hits = Narrow(hits)
    pendingHits = hits

    -- What you are looking at, always: how many rows this is, and of
    -- how many when it is a part of something. The tiles say how many
    -- items there are in all; this says how many are in front of you.
    local cat = Catalog()
    local total = cat and cat.Count() or IndexSize()
    if note then
        headerNote = note
    elseif #hits == 0 then
        headerNote = (total == 0)
            and "Nothing here yet. Items join the list as you carry, wear, bank and loot them; a link or an item number looks up anything else."
            or "Nothing matches."
    elseif #hits == total then
        headerNote = string.format("%s items", BreakUpLargeNumbers(#hits))
    else
        headerNote = string.format("%s of %s items", BreakUpLargeNumbers(#hits), BreakUpLargeNumbers(total))
    end

    h.note:ClearAllPoints()
    h.note:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 2, -7)
    h.note:SetPoint("RIGHT", h, "RIGHT", -2, 0)
    h.note:SetText(headerNote or "")
    h.note:Show()
    local noteHeight = 7 + math.ceil((h.note:GetStringHeight() or 12) + 2)

    local height = 22 + stripsHeight + noteHeight + 8
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
            -- Not loaded this session. The catalog has the name, the
            -- color and the picture, which is all a row needs, so the
            -- server is not asked for a search result; hovering the row
            -- asks for the tooltip, which is when it becomes wanted.
            local cat = Catalog()
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
        row.met:SetShown(Index()[itemID] ~= nil)
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

    local class, subclass, slot = Picked()
    local question = table.concat({ query, tostring(class), tostring(subclass), tostring(slot) }, "\1")
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
        local catalog = Catalog()
        if catalog then
            highlights[#highlights + 1] = { value = catalog.Count(), label = "items in the game" }
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
