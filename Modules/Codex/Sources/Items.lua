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

-- A subclass has to be worth a tab. The game keeps categories it no
-- longer uses - "Trade Goods (OBSOLETE)" holds three items, "Explosives
-- (OBSOLETE)" holds one - and a tab each for those crowds out the ones
-- people want while saying nothing. Anything under this many items is
-- reachable by name, by All, and by its class.
local MIN_SUBCLASS = 5

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
--
-- Held for as long as the window is open and no longer. Saving it
-- would mean opening the codex tomorrow inside last night's search for
-- cloth leg pieces, which is not what anybody opens it for.
local pickClass, pickSubclass, pickSlot

local function Picked()
    return pickClass, pickSubclass, pickSlot
end

local function Pick(class, subclass, slot)
    pickClass, pickSubclass, pickSlot = class, subclass, slot
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

---------------------------------------------------------------------------
-- Columns
--
-- What a column says depends on what you are looking at. Item level on
-- a stack of copper ore is a number nobody wants, and a slot on a
-- potion is a blank column taking up the row. So each class of item
-- brings its own set, and a column that would say nothing is not drawn
-- at all rather than drawn empty.
--
-- Name is not in here. It is the row, and it takes whatever width the
-- columns leave.
---------------------------------------------------------------------------

local COLUMN = {
    type = {
        title = "Type", width = 108, justify = "LEFT",
        text = function(rec)
            if not rec.subclassID then return "" end
            return SubclassName(rec.classID or 0, rec.subclassID)
        end,
        rank = function(rec) return (rec.classID or 0) * 100 + (rec.subclassID or 0) end,
    },
    slot = {
        title = "Slot", width = 104, justify = "LEFT",
        text = function(rec)
            if not (rec.slot and rec.slot > 0) then return "" end
            return SlotName(FoldSlot(rec.slot))
        end,
        rank = function(rec) return rec.slot or 0 end,
    },
    ilvl = {
        title = "iLvl", width = 46, justify = "RIGHT", numeric = true,
        text = function(rec)
            return (rec.ilvl and rec.ilvl > 0) and tostring(rec.ilvl) or ""
        end,
        rank = function(rec) return rec.ilvl or 0 end,
    },
    req = {
        title = "Req", width = 46, justify = "RIGHT", numeric = true,
        text = function(rec)
            return (rec.minLvl and rec.minLvl > 0) and tostring(rec.minLvl) or ""
        end,
        rank = function(rec) return rec.minLvl or 0 end,
    },
}

-- By item class. Absent means the general set; an empty list means the
-- name is the whole story, which is true of quest items and keys.
local CLASS_COLUMNS = {
    [0]  = { "type", "req" },                  -- Consumable
    [1]  = { "type", "ilvl" },                 -- Container
    [2]  = { "type", "slot", "ilvl", "req" },  -- Weapon
    [4]  = { "type", "slot", "ilvl", "req" },  -- Armor
    [5]  = { "type" },                         -- Reagent
    [6]  = { "type", "req" },                  -- Projectile
    [7]  = { "type" },                         -- Trade Goods
    [9]  = { "type", "req" },                  -- Recipe
    [11] = { "type", "ilvl" },                 -- Quiver
    [12] = {},                                 -- Quest
    [13] = {},                                 -- Key
    [15] = { "type" },                         -- Miscellaneous
}
local GENERAL_COLUMNS = { "type", "ilvl", "req" }

local function ActiveColumns()
    local class = Picked()
    local keys = class and CLASS_COLUMNS[class] or GENERAL_COLUMNS
    local out = {}
    for _, key in ipairs(keys) do out[#out + 1] = key end
    return out
end

-- Where everything sits, measured in from the right edge of the card.
-- The name gets what is left. Worked out once per render and handed to
-- the header and every row, so a column and its heading cannot drift
-- apart.
local RIGHT_PAD, STAR_W, MET_W, OWNED_W, COL_GAP = 10, 18, 16, 74, 8

local function ColumnLayout(keys)
    local layout = { star = RIGHT_PAD }
    layout.met = layout.star + STAR_W + COL_GAP
    layout.owned = layout.met + MET_W + COL_GAP
    local right = layout.owned + OWNED_W + COL_GAP
    layout.columns = {}
    for i = #keys, 1, -1 do
        local key = keys[i]
        local width = COLUMN[key].width
        layout.columns[key] = { right = right, width = width }
        right = right + width + COL_GAP
    end
    layout.nameRight = right + 2
    return layout
end

-- What a row knows about its item. The catalog where there is one, and
-- the client for an item met on a build with no catalog.
local function RecordFor(itemID)
    local cat = Catalog()
    local rec = cat and cat.Get(itemID)
    if rec then return rec end

    local name, _, quality, ilvl, minLvl, _, _, _, _, _, _, classID, subclassID =
        C_Item.GetItemInfo(itemID)
    if not name then return nil end
    return {
        id = itemID, name = name, quality = quality,
        ilvl = ilvl, minLvl = minLvl,
        classID = classID, subclassID = subclassID,
    }
end

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

    -- One string per column, made on demand and kept with the row.
    row.cols = {}

    -- The star. Hollow and faint until you want the thing; filled and
    -- bright once you do. One click either way, and the Wishlist page
    -- follows in the same redraw.
    row.star = CreateFrame("Button", nil, row)
    row.star:SetSize(18, 18)
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
    row.owned:SetJustifyH("RIGHT")

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
        -- No width cap worth the name. These labels are the client's
        -- own words and some are long ("Trade Goods (OBSOLETE)"); a cap
        -- clipped them to an ellipsis while the row still had room to
        -- the right of it. The strip wraps to a second line when it
        -- genuinely runs out of width, which is the honest limit.
        local strip = BazUI.CreateTabStrip(nil, header, {
            style = "panel", tabHeight = 20, spacing = 3,
            minTabWidth = 44, maxTabWidth = 400,
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
            -- The one that is picked stays, however small, so a pick
            -- never vanishes from under the cursor.
            if sc.count >= MIN_SUBCLASS or sc.id == subclass then
                entries[#entries + 1] = { id = sc.id, label = SubclassName(class, sc.id) }
            end
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

-- The list is virtual. It draws only the rows that fit in the card and
-- the wheel changes which slice of the results those rows show, so
-- seventeen thousand results cost the same as twenty.
--
-- `first` is the index of the top row. It is kept across renders - a
-- bag update redraws the page and must not throw you back to the top -
-- and reset only when the question changes.

local HEADER_H = 22

-- What the list is sorted by, and which way. Kept for the session
-- rather than saved: a sort is something you do while looking for one
-- thing, and opening the tab tomorrow wanting last night's sort is
-- rarer than opening it wanting the names in order.
local sortKey, sortDesc = "name", false
local sortedHits, sortedFor

local function SortHits(hits, question)
    local signature = table.concat({ question, sortKey, tostring(sortDesc), tostring(#hits) }, "\2")
    if sortedFor == signature then return sortedHits end

    local out = {}
    for i, id in ipairs(hits) do out[i] = id end

    if sortKey ~= "name" then
        local col = COLUMN[sortKey]
        -- Ranked once per item rather than on every comparison: a sort
        -- of seventeen thousand asks this a quarter of a million times.
        local rank, name = {}, {}
        for _, id in ipairs(out) do
            local rec = RecordFor(id)
            rank[id] = rec and col.rank(rec) or 0
            name[id] = rec and rec.name or ""
        end
        table.sort(out, function(a, b)
            if rank[a] ~= rank[b] then
                if sortDesc then return rank[a] > rank[b] end
                return rank[a] < rank[b]
            end
            return name[a] < name[b]
        end)
    elseif sortDesc then
        local name = {}
        for _, id in ipairs(out) do
            local rec = RecordFor(id)
            name[id] = rec and rec.name or ""
        end
        table.sort(out, function(a, b) return name[a] > name[b] end)
    end
    -- Ascending by name is the order the catalog is already in.

    sortedHits, sortedFor = out, signature
    return out
end

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
    page.heads = {}

    -- Results live in the same card the rest of the codex draws, so a
    -- lookup and a lockout read as pages of one book.
    page.card = Codex.Panel.CreateBox(page)
    page.card:SetPoint("TOPLEFT")
    page.card:SetPoint("TOPRIGHT")

    -- The heading strip, inside the card above the rows.
    page.head = CreateFrame("Frame", nil, page.card)
    page.head:SetPoint("TOPLEFT", 10, -8)
    page.head:SetPoint("TOPRIGHT", -10, -8)
    page.head:SetHeight(HEADER_H)
    page.head.rule = page.head:CreateTexture(nil, "ARTWORK")
    page.head.rule:SetHeight(1)
    page.head.rule:SetPoint("BOTTOMLEFT")
    page.head.rule:SetPoint("BOTTOMRIGHT")
    page.head.rule:SetColorTexture(unpack(Theme.colors.edge))

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

-- One clickable heading. Click to sort by it, click again to turn it
-- round. Numbers start at the biggest, words at A, because that is
-- what each is usually being asked for.
local function AcquireHead(key)
    local head = page.heads[key]
    if head then return head end

    head = CreateFrame("Button", nil, page.head)
    head:SetHeight(HEADER_H)
    head.text = Theme.FontString(head, "OVERLAY", "GameFontNormalSmall")
    head.text:SetPoint("LEFT")
    head.text:SetPoint("RIGHT")
    head.text:SetWordWrap(false)
    head.arrow = head:CreateTexture(nil, "OVERLAY")
    head.arrow:SetSize(10, 5)
    head:SetScript("OnClick", function(self)
        if sortKey == self.key then
            sortDesc = not sortDesc
        else
            sortKey = self.key
            sortDesc = COLUMN[self.key] and COLUMN[self.key].numeric or false
        end
        page.first = 0
        Codex.Panel:QueueRefresh()
    end)
    head:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
    head:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(sortKey == self.key and Theme.colors.gold or Theme.colors.textMuted))
    end)
    page.heads[key] = head
    return head
end

local function FillHeader(keys, layout)
    for _, head in pairs(page.heads) do head:Hide() end

    local function Place(key, title, justify, width, right)
        local head = AcquireHead(key)
        head.key = key
        head.text:SetText(title)
        head.text:SetJustifyH(justify)
        head:ClearAllPoints()
        if width then
            head:SetWidth(width)
            head:SetPoint("RIGHT", page.head, "RIGHT", -right, 0)
        else
            head:SetPoint("LEFT", page.head, "LEFT", 28, 0)
            head:SetPoint("RIGHT", page.head, "RIGHT", -right, 0)
        end
        head.text:SetTextColor(unpack(sortKey == key and Theme.colors.gold or Theme.colors.textMuted))

        head.arrow:ClearAllPoints()
        head.arrow:SetShown(sortKey == key)
        if sortKey == key then
            BazUI.SetArrowTexture(head.arrow, sortDesc and "DOWN" or "UP", 10)
            if justify == "RIGHT" then
                head.arrow:SetPoint("RIGHT", head.text, "LEFT", -3, 0)
            else
                head.arrow:SetPoint("LEFT", head.text, "LEFT",
                    math.min(head.text:GetStringWidth() or 0, head:GetWidth() or 0) + 3, 0)
            end
        end
        head:Show()
    end

    Place("name", "Name", "LEFT", nil, layout.nameRight)
    for _, key in ipairs(keys) do
        local col, spot = COLUMN[key], layout.columns[key]
        Place(key, col.title, col.justify, spot.width, spot.right)
    end
end

-- Draw the rows for the current slice. Rows are taken from the pool
-- and handed back each time; twenty of them, so it costs nothing.
local function FillRows()
    if not page then return end
    ReleaseRows()

    local hits = page.hits
    local visible = page.visible or 0
    local keys, layout = page.keys or {}, page.layout
    local y = 0

    for i = page.first + 1, math.min(#hits, page.first + visible) do
        local itemID = hits[i]
        local rec = RecordFor(itemID)
        local name, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(itemID)
        if not name then
            -- Not loaded this session. The catalog has the name, the
            -- color and the picture, which is all a row needs, so the
            -- server is not asked for a search result; hovering the row
            -- asks for the tooltip, which is when it becomes wanted.
            if rec then
                name, quality, texture = rec.name, rec.quality, rec.icon
            else
                if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
                name = Index()[itemID] or ("Item " .. itemID)
            end
        end

        local row = AcquireRow(page.card)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 10, -(y + HEADER_H + 10))
        row:SetPoint("TOPRIGHT", -10, -(y + HEADER_H + 10))
        Codex.Panel.SetRowBand(row, i)
        row.itemID = itemID
        SetStar(row)

        row.star:ClearAllPoints()
        row.star:SetPoint("RIGHT", -layout.star, 0)
        row.met:ClearAllPoints()
        row.met:SetPoint("RIGHT", -layout.met, 0)
        row.met:SetShown(Index()[itemID] ~= nil)
        row.owned:ClearAllPoints()
        row.owned:SetWidth(OWNED_W)
        row.owned:SetPoint("RIGHT", -layout.owned, 0)

        -- The columns this class wants, and nothing else shown.
        for key, fs in pairs(row.cols) do fs:Hide() end
        for _, key in ipairs(keys) do
            local col, spot = COLUMN[key], layout.columns[key]
            local fs = row.cols[key]
            if not fs then
                fs = Theme.FontString(row, "OVERLAY", "GameFontHighlightSmall")
                fs:SetWordWrap(false)
                row.cols[key] = fs
            end
            fs:ClearAllPoints()
            fs:SetWidth(spot.width)
            fs:SetPoint("RIGHT", -spot.right, 0)
            fs:SetJustifyH(col.justify)
            fs:SetText(rec and col.text(rec) or "")
            fs:SetTextColor(unpack(Theme.colors.textMuted))
            fs:Show()
        end

        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -layout.nameRight, 0)
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

    local class, subclass, slot = Picked()
    local question = table.concat({ query, tostring(class), tostring(subclass), tostring(slot) }, "\1")
    if question ~= lastQuestion then
        lastQuestion = question
        p.first = 0
    end

    -- The header already resolved the query for this pass; the order is
    -- this page's to decide.
    p.hits = SortHits(pendingHits or {}, question)
    p.keys = ActiveColumns()
    p.layout = ColumnLayout(p.keys)

    -- The card is the page: as tall as the room below the header, and
    -- no taller, so the panel has nothing of its own to scroll.
    local room = math.max((Codex.Panel.ContentHeight() or 300) - 2, ROW_H + 40)
    p.visible = math.max(1, math.floor((room - 20 - HEADER_H) / ROW_H))
    p.first = math.max(0, math.min(p.first, math.max(0, #p.hits - p.visible)))

    local cardHeight = (#p.hits > 0)
        and (HEADER_H + math.min(#p.hits, p.visible) * ROW_H + 20)
        or 28
    p.card:SetHeight(cardHeight)
    p.card:SetShown(#p.hits > 0)
    p.head:SetShown(#p.hits > 0)

    if #p.hits > 0 then
        FillHeader(p.keys, p.layout)
    end
    FillRows()

    local used = (#p.hits > 0) and cardHeight or 1
    p:SetHeight(used)
    Codex.customTabs.items.height = used
end

Codex.customTabs.items = {
    label        = "Items",
    order        = 30,
    -- Everything this tab was holding, let go. Called when the window
    -- opens; see Panel:ResetForOpen.
    Reset        = function()
        query = ""
        pendingID = nil
        pickClass, pickSubclass, pickSlot = nil, nil, nil
        sortKey, sortDesc = "name", false
        sortedHits, sortedFor = nil, nil
        lastQuestion = nil
        if header and header.box then header.box:SetText("") end
        if page then page.first = 0 end
    end,
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
