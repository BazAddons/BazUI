-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: Equipment
--
-- What you are wearing, and what is wrong with it. One card per slot
-- down either side of the character, the slot's item level in the
-- corner, and the one thing worth saying about it underneath: no
-- enchant, or how worn it is. The character stands in the middle so the
-- page reads as the paper doll rather than a spreadsheet about one.
--
-- Everything here is asked of the client as it stands. Nothing is
-- stored, so nothing can be stale; the page is redrawn when a piece of
-- gear changes, takes damage, or finishes loading its name.
--
-- Sockets are not looked at. Forever's gear has none, and the page is
-- Forever's first.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local addon = Codex.addon
local Theme = BazUI.Skin.Theme

local TAB = "equipment"

---------------------------------------------------------------------------
-- The slots
--
-- Left column top to bottom, then right. An enchantable slot is one an
-- enchanter can put something on; the off hand only counts when what is
-- in it is a weapon or a shield. The ranged slot exists on Forever and
-- not on retail, so it is asked for by name.
---------------------------------------------------------------------------

local LEFT = {
    { id = 1,  key = "HeadSlot",     name = "Head",     enchant = true },
    { id = 2,  key = "NeckSlot",     name = "Neck" },
    { id = 3,  key = "ShoulderSlot", name = "Shoulder", enchant = true },
    { id = 15, key = "BackSlot",     name = "Back",     enchant = true },
    { id = 5,  key = "ChestSlot",    name = "Chest",    enchant = true },
    { id = 9,  key = "WristSlot",    name = "Wrist",    enchant = true },
    { id = 10, key = "HandsSlot",    name = "Hands",    enchant = true },
    { id = 6,  key = "WaistSlot",    name = "Waist" },
}

local RIGHT = {
    { id = 7,  key = "LegsSlot",          name = "Legs",      enchant = true },
    { id = 8,  key = "FeetSlot",          name = "Feet",      enchant = true },
    { id = 11, key = "Finger0Slot",       name = "Ring 1" },
    { id = 12, key = "Finger1Slot",       name = "Ring 2" },
    { id = 13, key = "Trinket0Slot",      name = "Trinket 1" },
    { id = 14, key = "Trinket1Slot",      name = "Trinket 2" },
    { id = 16, key = "MainHandSlot",      name = "Main hand", enchant = true },
    { id = 17, key = "SecondaryHandSlot", name = "Off hand",  enchant = "weapon" },
    { id = 18, key = "RangedSlot",        name = "Ranged",    enchant = true, onlyIf = "CharacterRangedSlot" },
}

-- The paper doll's own silhouette for an empty slot: a helm where a
-- helm would go, not a bag's empty square.
local function EmptyArt(def)
    -- Retail keeps this under C_PaperDollInfo, Forever's own paper doll
    -- still calls the bare name; both hand back the texture after the id.
    local fn = (C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo) or _G.GetInventorySlotInfo
    if fn and def.key then
        local ok, _, texture = pcall(fn, def.key)
        if ok and texture then return texture end
    end
    return "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
end

local OFFHAND_ENCHANTABLE = {
    INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true,
}

local function SlotExists(def)
    if not def.onlyIf then return true end
    return BazUI.Has.Frame(def.onlyIf)
end

---------------------------------------------------------------------------
-- Reading a slot
---------------------------------------------------------------------------

local function ItemLevelOf(link)
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, level = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if ok and type(level) == "number" and level > 0 then return level end
    end
    local level = select(4, C_Item.GetItemInfo(link))
    return type(level) == "number" and level or nil
end

local function EnchantOf(link)
    local id = link and link:match("item:%d+:(%d*)")
    return id ~= nil and id ~= "" and id ~= "0"
end

-- An enchant is only missing when the character has stopped growing
-- into new gear; at level 12 an unenchanted chest is not a fault.
local function EnchantsExpected()
    local max = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    return (UnitLevel("player") or 1) >= max
end

local function ReadSlot(def)
    local slot = def.id
    local link = GetInventoryItemLink("player", slot)
    local reading = { def = def, slot = slot, link = link }
    if not link then return reading end

    local name, _, quality, _, _, _, _, _, equipLoc = C_Item.GetItemInfo(link)
    reading.name    = name or "Loading..."
    reading.quality = quality or GetInventoryItemQuality("player", slot)
    reading.icon    = GetInventoryItemTexture("player", slot)
    reading.level   = ItemLevelOf(link)

    local wants = def.enchant
    if wants == "weapon" then
        wants = equipLoc and OFFHAND_ENCHANTABLE[equipLoc] or false
    end
    reading.enchantable = wants and true or false
    reading.enchanted   = EnchantOf(link)

    if GetInventoryItemDurability then
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            reading.durability = cur / max
            reading.durCur, reading.durMax = cur, max
        end
    end
    return reading
end

local function Snapshot()
    local snap = { slots = {}, equipped = 0, total = 0, missing = 0,
                   durCur = 0, durMax = 0, levels = {} }
    local function Take(list, side)
        for _, def in ipairs(list) do
            if SlotExists(def) then
                local r = ReadSlot(def)
                r.side = side
                snap.slots[#snap.slots + 1] = r
                snap.total = snap.total + 1
                if r.link then
                    snap.equipped = snap.equipped + 1
                    if r.level then snap.levels[#snap.levels + 1] = r.level end
                    if r.enchantable and not r.enchanted then
                        snap.missing = snap.missing + 1
                    end
                    if r.durMax then
                        snap.durCur = snap.durCur + r.durCur
                        snap.durMax = snap.durMax + r.durMax
                    end
                end
            end
        end
    end
    Take(LEFT, "left")
    Take(RIGHT, "right")

    -- The client's own average where it has one, so the number agrees
    -- with the character sheet; our own mean where it has not.
    local avg
    if GetAverageItemLevel then
        local ok, _, equipped = pcall(GetAverageItemLevel)
        if ok and type(equipped) == "number" and equipped > 0 then avg = equipped end
    end
    if not avg and #snap.levels > 0 then
        local sum = 0
        for _, l in ipairs(snap.levels) do sum = sum + l end
        avg = sum / #snap.levels
    end
    snap.average = avg and math.floor(avg + 0.5) or nil
    snap.durability = snap.durMax > 0 and (snap.durCur / snap.durMax) or nil
    return snap
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local CARD_MAX = 58   -- as tall as a card gets
local CARD_MIN = 40   -- and as short
local CARD_GAP = 6
local MODEL_W  = 250
local STATS_W  = 300
local COL_GAP  = 14
local STAT_ROW_H = 22
local ICON     = 40

local page
local cards = {}

local function CreateCard(parent)
    local Panel = Codex.Panel
    local card = Panel.CreateBox(parent, "Button")
    card:SetHeight(CARD_MAX)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(ICON, ICON)
    card.icon:SetPoint("LEFT", 9, 0)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    card.slot = Theme.FontString(card, "OVERLAY", "GameFontHighlightSmall")
    card.slot:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -1)
    card.slot:SetJustifyH("LEFT")
    card.slot:SetTextColor(unpack(Theme.colors.textMuted))

    card.level = Theme.FontString(card, "OVERLAY", "GameFontNormal")
    card.level:SetPoint("TOPRIGHT", -10, -9)
    card.level:SetJustifyH("RIGHT")
    card.level:SetTextColor(unpack(Theme.colors.gold))

    card.name = Theme.FontString(card, "OVERLAY", "GameFontHighlight")
    card.name:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 10, 2)
    card.name:SetPoint("RIGHT", card.level, "LEFT", -8, 0)
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)

    -- The enchant, as a mark rather than two words.
    --
    -- "no enchant" written out took most of the card's lower line and ran
    -- into the item's name on anything with a long one - Apprentice
    -- Wizard's Gown sat right on top of it. The same fact fits in sixteen
    -- pixels: lit when there is an enchant, faded when there is not, and
    -- not there at all on a slot no enchanter can touch. Which is also
    -- three states where the words could only manage two.
    card.ench = CreateFrame("Frame", nil, card)
    card.ench:SetSize(16, 16)
    card.ench:SetPoint("BOTTOMRIGHT", -10, 7)
    card.ench:EnableMouse(true)
    card.ench.icon = card.ench:CreateTexture(nil, "OVERLAY")
    card.ench.icon:SetAllPoints()
    card.ench.icon:SetTexture("Interface\\Icons\\Trade_Engraving")
    card.ench.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.ench:Hide()

    -- Lit while the cursor is carrying something this slot will take.
    -- Above the box fill so it reads through a hover, and below the icon
    -- and the writing so it never sits on top of them.
    card.drop = card:CreateTexture(nil, "BORDER")
    card.drop:SetAllPoints()
    card.drop:SetColorTexture(1, 0.82, 0.25, 0.14)
    card.drop:Hide()

    -- Its own hover, because a mark nobody can read is decoration. The
    -- card's fill is set from here too, so putting the mouse on the icon
    -- does not make the card look like it was let go.
    card.ench:SetScript("OnEnter", function(self)
        Panel.SetBoxFill(card, { 0.16, 0.13, 0.07, 0.80 })
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.enchanted then
            GameTooltip:SetText("Enchanted", unpack(Theme.colors.text))
            GameTooltip:AddLine("The item's own tooltip says what it is.",
                0.6, 0.55, 0.45, true)
        else
            GameTooltip:SetText("No enchant", unpack(Theme.colors.textMuted))
            GameTooltip:AddLine("An enchanter can put something on this slot.",
                0.6, 0.55, 0.45, true)
        end
        GameTooltip:Show()
    end)
    card.ench:SetScript("OnLeave", function()
        Panel.SetBoxFill(card)
        GameTooltip:Hide()
    end)

    -- Wear only, now that the enchant has a mark of its own. Kept clear
    -- of that mark whether it is shown or not, so the lower line of every
    -- card reads along the same edge.
    card.note = Theme.FontString(card, "OVERLAY", "GameFontHighlightSmall")
    card.note:SetPoint("BOTTOMRIGHT", card.ench, "BOTTOMLEFT", -6, 1)
    card.note:SetJustifyH("RIGHT")

    card:SetScript("OnEnter", function(self)
        Panel.SetBoxFill(self, { 0.16, 0.13, 0.07, 0.80 })
        if not self.slotID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.hasItem then
            GameTooltip:SetInventoryItem("player", self.slotID)
        else
            GameTooltip:SetText(self.slotName or "", unpack(Theme.colors.text))
            GameTooltip:AddLine("Nothing equipped here.", 0.6, 0.55, 0.45, true)
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function(self)
        Panel.SetBoxFill(self)
        GameTooltip:Hide()
    end)
    -- A slot you can put something in, and take something out of.
    --
    -- One call does both directions, which is what the character sheet
    -- itself does: PickupInventoryItem with something on the cursor
    -- equips it here, and with an empty cursor picks up what is worn.
    -- Drag and click are the same action, so they share a handler.
    --
    -- Not protected, so none of the secure forwarding the portrait
    -- needed applies. The game refuses an equip in combat by itself and
    -- says so in its own words, which is better than us guessing at the
    -- rules for two-handers and off hands.
    --
    -- What a slot does NOT do is open the character sheet. Seventeen of
    -- these doing what the portrait already does two inches away, each
    -- tainting that window's health readout to say it - see
    -- portraitSecureClick in Core/UI.lua.
    local function Handle(self)
        if not self.slotID then return end
        PickupInventoryItem(self.slotID)
    end

    card:EnableMouse(true)
    card:RegisterForClicks("LeftButtonUp")
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnClick", Handle)
    card:SetScript("OnDragStart", Handle)
    card:SetScript("OnReceiveDrag", Handle)

    return card
end

---------------------------------------------------------------------------
-- Where what you are holding can go
--
-- Dropping onto a card is guesswork without this: seventeen of them, and
-- the rules for which will take a two-hander or a second ring are the
-- game's rather than ours. C_PaperDollInfo.CursorCanGoInSlot is the same
-- question the character sheet asks, so the answer agrees with it.
--
-- The enchant mark stops taking the mouse while something is held, so
-- the corner it sits in does not become a dead spot for the drop.
---------------------------------------------------------------------------

local function UpdateDropTargets()
    local holding = CursorHasItem and CursorHasItem()
    local CanGo = C_PaperDollInfo and C_PaperDollInfo.CursorCanGoInSlot

    for _, card in ipairs(cards) do
        local ok = false
        if holding and card.slotID and CanGo then
            local fine, answer = pcall(CanGo, card.slotID)
            ok = fine and answer and true or false
        end
        if card.drop then card.drop:SetShown(ok) end
        if card.ench then card.ench:EnableMouse(not holding) end
    end
end

-- One row of the summary under the character.
local function CreateSummaryRow(parent)
    local Panel = Codex.Panel
    local row = Panel.CreateBandRow(parent)
    row:SetHeight(24)
    row.label = Theme.FontString(row, "OVERLAY", "GameFontNormal")
    row.label:SetPoint("LEFT", 11, 0)
    row.label:SetJustifyH("LEFT")
    row.value = Theme.FontString(row, "OVERLAY", "GameFontHighlight")
    row.value:SetPoint("RIGHT", -10, 0)
    row.value:SetJustifyH("RIGHT")
    row:EnableMouse(false)
    return row
end

local SUMMARY_ROWS = { "equipped", "enchants", "durability" }
local SUMMARY_LABEL = {
    equipped   = "Equipped",
    enchants   = "Enchants",
    durability = "Durability",
}

local function Build(parent)
    local Panel = Codex.Panel
    if page then
        page:SetParent(parent)
        return page
    end

    page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT")

    -- The character, in the box between the columns.
    page.modelBox = Panel.CreateBox(page)
    local model = CreateFrame("PlayerModel", nil, page.modelBox)
    model:SetPoint("TOPLEFT", 6, -6)
    model:SetPoint("BOTTOMRIGHT", -6, 6)
    -- A hidden model frame drops what it held and comes back black, so
    -- every showing asks again. Sized by its anchors before it is asked.
    model:SetScript("OnShow", function(self) self:SetUnit("player") end)
    model:SetScript("OnModelLoaded", function(self)
        self:SetPosition(0, 0, 0)
        self:SetFacing(0)
    end)
    page.model = model

    -- The reckoning, under the character.
    page.summary = Panel.CreateBox(page)
    page.summary.plate = CreateFrame("Frame", nil, page.summary)
    page.summary.plate:SetSize(197, 40)
    page.summary.plate:SetPoint("TOP", 0, -6)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-Character-Info-Title") then
        local art = page.summary.plate:CreateTexture(nil, "ARTWORK")
        art:SetAtlas("UI-Character-Info-Title", true)
        art:SetPoint("CENTER")
    end
    page.summary.title = Theme.FontString(page.summary.plate, "OVERLAY", "GameFontNormal")
    page.summary.title:SetPoint("CENTER", 0, 1)
    page.summary.title:SetText("Equipment check")
    page.summary.title:SetTextColor(unpack(Theme.colors.gold))

    page.summary.rows = {}
    for i, key in ipairs(SUMMARY_ROWS) do
        local row = CreateSummaryRow(page.summary)
        row:SetPoint("TOPLEFT", 10, -(52 + (i - 1) * 24))
        row:SetPoint("TOPRIGHT", -10, -(52 + (i - 1) * 24))
        row.label:SetText(SUMMARY_LABEL[key])
        Panel.SetRowBand(row, i)
        page.summary.rows[key] = row
    end
    page.summary:SetHeight(52 + #SUMMARY_ROWS * 24 + 10)

    -- The item level, as a card of its own under the left column: the
    -- sheet's own figure in the sheet's own color, and under it the
    -- mean of what is actually worn, because the sheet divides by every
    -- slot and a character with six pieces on reads as a three.
    page.ilvl = Panel.CreateBox(page)
    page.ilvl.label = Theme.FontString(page.ilvl, "OVERLAY", "GameFontHighlightSmall")
    page.ilvl.label:SetPoint("TOPLEFT", 12, -9)
    page.ilvl.label:SetText("Item level")
    page.ilvl.label:SetTextColor(unpack(Theme.colors.textMuted))
    page.ilvl.value = Theme.FontString(page.ilvl, "OVERLAY", "GameFontNormalHuge")
    page.ilvl.value:SetPoint("LEFT", 12, -4)
    page.ilvl.value:SetJustifyH("LEFT")
    page.ilvl.note = Theme.FontString(page.ilvl, "OVERLAY", "GameFontHighlightSmall")
    page.ilvl.note:SetPoint("BOTTOMRIGHT", -12, 9)
    page.ilvl.note:SetPoint("LEFT", page.ilvl.value, "RIGHT", 12, 0)
    page.ilvl.note:SetJustifyH("RIGHT")
    page.ilvl.note:SetWordWrap(false)
    page.ilvl.note:SetTextColor(unpack(Theme.colors.textSoft))

    -- The character sheet's numbers, in a column of their own. The sheet
    -- keeps them behind a scroll; here there is room to lay them out,
    -- and where there is not, the column scrolls on its own.
    page.stats = Panel.CreateBox(page)
    local statScroll = CreateFrame("ScrollFrame", nil, page.stats)
    statScroll:SetPoint("TOPLEFT", 6, -8)
    statScroll:SetPoint("BOTTOMRIGHT", -6, 8)
    Codex.Panel.MakeScrollable(statScroll, page.stats, STAT_ROW_H * 2)
    local body = CreateFrame("Frame", nil, statScroll)
    body:SetSize(1, 1)
    statScroll:SetScrollChild(body)
    page.stats.scroll = statScroll
    page.stats.body = body
    page.stats.plates = {}
    page.stats.rows = {}

    return page
end

---------------------------------------------------------------------------
-- The numbers
--
-- Read the way the character sheet reads them: its own category table
-- and its own update functions, run against rows of ours shaped the way
-- it expects (a Label and a Value). Run as Blizzard's code, because on
-- Forever health is a secret number and only their code may compare it.
-- Whatever it writes on the row - the text, a tooltip, a hidden flag -
-- is what the sheet would have shown.
---------------------------------------------------------------------------

local function CallAsBlizzard(fn, ...)
    if securecallfunction then
        return pcall(securecallfunction, fn, ...)
    end
    return pcall(fn, ...)
end

-- Retail names its categories by frame; Forever by word. Either way the
-- heading is a word.
local function CategoryTitle(cat)
    if cat.categoryName and cat.categoryName ~= "" then return cat.categoryName end
    local frameName = cat.categoryFrame or ""
    local word = frameName:gsub("Category$", "")
    local key = "STAT_CATEGORY_" .. word:upper()
    return _G[key] or word
end

local function AcquireStatPlate(box, i)
    local plate = box.plates[i]
    if not plate then
        plate = Codex.Panel.CreatePlate(box.body)
        box.plates[i] = plate
    end
    return plate
end

local function AcquireStatRow(box, i)
    local row = box.rows[i]
    if not row then
        row = Codex.Panel.CreateBandRow(box.body)
        row:SetHeight(STAT_ROW_H)
        row.Label = Theme.FontString(row, "OVERLAY", "GameFontNormal")
        row.Label:SetPoint("LEFT", 11, 0)
        row.Label:SetJustifyH("LEFT")
        row.Value = Theme.FontString(row, "OVERLAY", "GameFontHighlight")
        row.Value:SetPoint("RIGHT", -8, 0)
        row.Value:SetJustifyH("RIGHT")
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            self.hover:Show()
            if self.onEnterFunc then
                CallAsBlizzard(self.onEnterFunc, self)
            elseif PaperDollStatTooltip then
                CallAsBlizzard(PaperDollStatTooltip, self)
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hover:Hide()
            GameTooltip:Hide()
        end)
        box.rows[i] = row
    end
    return row
end

-- Whether the sheet would have left this stat out: the update hid the
-- row itself, its value sits at the category's hideAt, or its showFunc
-- says no. The comparison is done carefully, because the value may be
-- a number our code is not allowed to look at.
local function StatHidden(row, stat)
    if not row:IsShown() then return true end
    local okBlank, blank = pcall(function()
        local t = row.Value:GetText()
        return t == nil or t == ""
    end)
    if okBlank and blank then return true end
    if stat.showFunc then
        local ok, show = pcall(stat.showFunc)
        if ok and not show then return true end
    end
    if stat.hideAt ~= nil then
        local ok, hidden = pcall(function() return row.numericValue == stat.hideAt end)
        if ok and hidden then return true end
    end
    return false
end

local function FillStats(box, width)
    local info = PAPERDOLL_STATINFO
    local cats = PAPERDOLL_STATCATEGORIES
    local plateN, rowN, y = 0, 0, 4
    if type(info) == "table" and type(cats) == "table" then
        for _, cat in ipairs(cats) do
            if (cat.unit or "player") == "player" then
                local rowsHere = 0
                local plateIndex = plateN + 1
                local plateY = y
                y = y + 40 + 4

                for _, stat in ipairs(cat.stats or {}) do
                    local entry = info[stat.stat]
                    if entry and entry.updateFunc then
                        rowN = rowN + 1
                        local row = AcquireStatRow(box, rowN)
                        row.unit = "player"
                        row.tooltip, row.tooltip2, row.tooltip3, row.onEnterFunc = nil, nil, nil, nil
                        row.numericValue = nil
                        row:Show()
                        local ok = CallAsBlizzard(entry.updateFunc, row, "player")
                        if ok and not StatHidden(row, stat) then
                            rowsHere = rowsHere + 1
                            row:ClearAllPoints()
                            row:SetPoint("TOPLEFT", 0, -y)
                            row:SetWidth(width)
                            Codex.Panel.SetRowBand(row, rowsHere)
                            row:Show()
                            y = y + STAT_ROW_H
                        else
                            row:Hide()
                            rowN = rowN - 1
                            -- the row stays in the pool for the next stat
                            box.rows[rowN + 1] = row
                        end
                    end
                end

                if rowsHere > 0 then
                    plateN = plateIndex
                    local plate = AcquireStatPlate(box, plateN)
                    plate:ClearAllPoints()
                    plate:SetPoint("TOP", box.body, "TOP", 0, -plateY)
                    plate.title:SetText(CategoryTitle(cat))
                    plate:Show()
                    y = y + 6
                else
                    y = plateY
                end
            end
        end
    end
    for i = plateN + 1, #box.plates do box.plates[i]:Hide() end
    for i = rowN + 1, #box.rows do box.rows[i]:Hide() end

    box.body:SetSize(width, math.max(y, 1))
    box.scroll.bazContentH = y
    Codex.Panel.UpdateScrollHint(box.scroll)
end

local function Percent(fraction)
    return string.format("%d%%", math.floor(fraction * 100 + 0.5))
end

local function FillCard(card, r, expectEnchants)
    local Panel = Codex.Panel
    card.slotID   = r.slot
    card.slotName = r.def.name
    card.hasItem  = r.link ~= nil
    card.slot:SetText(r.def.name)

    if not r.link then
        card.icon:SetTexture(EmptyArt(r.def))
        card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        card.icon:SetAlpha(0.6)
        card.name:SetText("Empty")
        card.name:SetTextColor(unpack(Theme.colors.textMuted))
        card.level:SetText("")
        card.note:SetText("")
        card.ench:Hide()
        Panel.SetBoxBorder(card, nil)
        return
    end

    card.icon:SetTexture(r.icon)
    card.icon:SetAlpha(1)
    card.name:SetText(r.name)
    local c = r.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r.quality]
    if c then card.name:SetTextColor(c.r, c.g, c.b) else card.name:SetTextColor(unpack(Theme.colors.text)) end
    card.level:SetText(r.level and tostring(r.level) or "")

    -- The enchant is a mark, and it says all three of its states by
    -- itself: absent on a slot nothing can go on, faded when something
    -- could and has not, lit when it has.
    card.ench:SetShown(r.enchantable and true or false)
    card.ench.enchanted = r.enchanted and true or false
    if r.enchantable then
        card.ench.icon:SetDesaturated(not r.enchanted)
        card.ench.icon:SetAlpha(r.enchanted and 1 or 0.4)
    end

    -- The note is wear alone. The border still carries the warning for
    -- either, so a card worth looking at is still outlined.
    local note, noteColor, border
    if r.enchantable and not r.enchanted and expectEnchants then
        border = Theme.colors.caution
    end
    if r.durability and r.durability < 1 then
        note = Percent(r.durability)
        if r.durability < 0.3 then
            noteColor, border = Theme.colors.caution, Theme.colors.caution
        else
            noteColor = Theme.colors.textMuted
        end
    end
    card.note:SetText(note or "")
    if note then card.note:SetTextColor(unpack(noteColor)) end
    Panel.SetBoxBorder(card, border)
end

local function Render(content, width)
    local p = Build(content)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT")
    p:SetWidth(width)
    p:Show()

    local snap = Snapshot()
    local expectEnchants = EnchantsExpected()

    -- Sized to the window rather than the other way round: the tallest
    -- column decides how tall a card may be, so the page never scrolls.
    local rows = { left = 1, right = 0 }   -- the left starts at one: the item level card
    for _, r in ipairs(snap.slots) do rows[r.side] = rows[r.side] + 1 end
    local tallestCount = math.max(rows.left, rows.right, 1)
    local avail = Codex.Panel.ContentHeight()
    local cardH = math.floor((avail - CARD_GAP * (tallestCount - 1)) / tallestCount)
    cardH = math.max(CARD_MIN, math.min(CARD_MAX, cardH))

    local colW = math.floor((width - MODEL_W - STATS_W - COL_GAP * 3) / 2)
    local leftX, rightX = 0, colW + COL_GAP + MODEL_W + COL_GAP
    local statsX = rightX + colW + COL_GAP
    local ys = { left = 0, right = 0 }

    for i, r in ipairs(snap.slots) do
        local card = cards[i]
        if not card then
            card = CreateCard(p)
            cards[i] = card
        end
        local x = r.side == "left" and leftX or rightX
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", x, -ys[r.side])
        card:SetSize(colW, cardH)
        card.icon:SetSize(math.max(24, cardH - 18), math.max(24, cardH - 18))
        FillCard(card, r, expectEnchants)
        card:Show()
        ys[r.side] = ys[r.side] + cardH + CARD_GAP
    end
    for i = #snap.slots + 1, #cards do cards[i]:Hide() end

    -- The item level card closes the left column.
    p.ilvl:ClearAllPoints()
    p.ilvl:SetPoint("TOPLEFT", leftX, -ys.left)
    p.ilvl:SetSize(colW, cardH)
    p.ilvl.value:SetText(snap.average and tostring(snap.average) or "-")
    if GetItemLevelColor then
        local ok, r, g, b = pcall(GetItemLevelColor)
        if ok and r then p.ilvl.value:SetTextColor(r, g, b) else p.ilvl.value:SetTextColor(unpack(Theme.colors.gold)) end
    else
        p.ilvl.value:SetTextColor(unpack(Theme.colors.gold))
    end
    if #snap.levels > 0 then
        local sum = 0
        for _, l in ipairs(snap.levels) do sum = sum + l end
        local worn = math.floor(sum / #snap.levels + 0.5)
        p.ilvl.note:SetText(("worn pieces average %d"):format(worn))
    else
        p.ilvl.note:SetText("nothing worn")
    end
    p.ilvl:Show()
    ys.left = ys.left + cardH + CARD_GAP

    local leftH  = math.max(ys.left - CARD_GAP, 1)
    local rightH = math.max(ys.right - CARD_GAP, 1)
    local tallest = math.max(leftH, rightH)

    -- The character stands as tall as the columns leave room for, with
    -- the reckoning fixed beneath.
    local summaryH = p.summary:GetHeight()
    local modelH = math.max(tallest - summaryH - CARD_GAP, 200)
    p.modelBox:ClearAllPoints()
    p.modelBox:SetPoint("TOPLEFT", colW + COL_GAP, 0)
    p.modelBox:SetSize(MODEL_W, modelH)
    p.summary:ClearAllPoints()
    p.summary:SetPoint("TOPLEFT", p.modelBox, "BOTTOMLEFT", 0, -CARD_GAP)
    p.summary:SetWidth(MODEL_W)

    -- The stats column ends where the other three end, whichever of
    -- them reaches furthest.
    local pageH = math.max(tallest, modelH + CARD_GAP + summaryH)
    p.stats:ClearAllPoints()
    p.stats:SetPoint("TOPLEFT", statsX, 0)
    p.stats:SetSize(width - statsX, pageH)
    FillStats(p.stats, (width - statsX) - 12)

    if p.model:IsShown() then
        p.model:SetUnit("player")
    end

    local sums = p.summary.rows
    sums.equipped.value:SetText(string.format("%d of %d", snap.equipped, snap.total))
    if snap.missing > 0 then
        sums.enchants.value:SetText(string.format("%d missing", snap.missing))
        sums.enchants.value:SetTextColor(unpack(expectEnchants and Theme.colors.caution or Theme.colors.textSoft))
    else
        sums.enchants.value:SetText("all on")
        sums.enchants.value:SetTextColor(unpack(Theme.colors.success))
    end
    if snap.durability then
        sums.durability.value:SetText(Percent(snap.durability))
        sums.durability.value:SetTextColor(unpack(snap.durability < 0.3 and Theme.colors.caution or Theme.colors.text))
    else
        sums.durability.value:SetText("-")
        sums.durability.value:SetTextColor(unpack(Theme.colors.textMuted))
    end

    p:SetHeight(pageH)
    Codex.customTabs[TAB].height = pageH
end

Codex.customTabs[TAB] = {
    label  = "Equipment",
    order  = 25,
    icon   = "Interface\\Icons\\INV_Chest_Cloth_17",
    Render = Render,
    Hide   = function()
        if page then page:Hide() end
    end,
    height = 1,
    GetHighlights = function()
        local snap = Snapshot()
        local out = {}
        if snap.average then
            out[#out + 1] = { value = snap.average, label = "average item level" }
        end
        out[#out + 1] = {
            value = snap.missing,
            label = snap.missing == 1 and "enchant missing" or "enchants missing",
            color = (snap.missing > 0 and EnchantsExpected()) and Theme.colors.caution or nil,
        }
        if snap.durability then
            out[#out + 1] = {
                value = Percent(snap.durability),
                label = "durability",
                color = snap.durability < 0.3 and Theme.colors.caution or nil,
            }
        end
        return out
    end,
}

---------------------------------------------------------------------------
-- Staying current
---------------------------------------------------------------------------

BazUI:QueueForModule("Codex", function()
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    watcher:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    watcher:RegisterEvent("PLAYER_LEVEL_UP")
    -- Picking something up and putting it down are the two moments the
    -- highlighting has to answer, and neither is an inventory change.
    watcher:RegisterEvent("CURSOR_CHANGED")
    watcher:SetScript("OnEvent", function(_, event)
        if not (Codex.IsShown and Codex:IsShown()) then return end
        if event == "CURSOR_CHANGED" then
            -- Read after the client has settled the cursor; asked during
            -- the event it still describes what was there a moment ago.
            C_Timer.After(0, UpdateDropTargets)
            return
        end
        if event == "PLAYER_EQUIPMENT_CHANGED" and page and page.model and page.model:IsShown() then
            if page.model.RefreshUnit then page.model:RefreshUnit() else page.model:SetUnit("player") end
        end
        if (addon:GetSetting("activeTab") or "today") == TAB then
            Codex.Panel:QueueRefresh()
        end
    end)
end)
