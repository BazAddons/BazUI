-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Bags - Category layout module
--
-- One layout: thin full-width divider rows mark each category, items
-- pack into a regular grid below. Each category always starts a fresh
-- row with its own divider, so the reading order is top-to-bottom in
-- clean chapters.
--
-- Compared to a chunky Sections-style header this saves ~6 px of
-- vertical space per category while still being instantly scannable.
-- Bag.lua's Refresh dispatches here when bagMode == "categories".
---------------------------------------------------------------------------

local MODULE_NAME = "Bags"
local addon = BazUI:GetAddon(MODULE_NAME)
if not addon then return end

addon.Layouts = addon.Layouts or {}
local Layouts = addon.Layouts

---------------------------------------------------------------------------
-- Tunables
---------------------------------------------------------------------------

local DIVIDER_HEIGHT       = 18
local DIVIDER_GAP_BELOW    = 4   -- gap between divider and first item row
local CATEGORY_GAP         = 6   -- gap between one category's items and the next divider
local TITLE_COLOR          = { 1.00, 0.82, 0.00 }    -- suite gold, matches headers
local DIVIDER_LINE_COLOR   = { 0.55, 0.42, 0.18, 0.85 }

---------------------------------------------------------------------------
-- Divider-row pool - one per category. A divider is a thin (~18 px)
-- full-width Button containing a chevron + category name + a subtle
-- horizontal line that fades out to the right edge. Reads like the
-- title rule on a chapter divider.
---------------------------------------------------------------------------

local dividerRows = {}

local function GetOrCreateDividerRow(parent, key)
    local row = dividerRows[key]
    if row then
        row:SetParent(parent)
        return row
    end

    row = CreateFrame("Button", nil, parent)
    row:SetHeight(DIVIDER_HEIGHT)

    -- Hover background (subtle so it doesn't compete with the items).
    local hover = row:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.04)
    hover:Hide()
    row.hover = hover

    -- Collapse / expand chevron, anchored to the very left of the row.
    row.toggle = row:CreateTexture(nil, "OVERLAY")
    row.toggle:SetSize(12, 12)
    row.toggle:SetPoint("LEFT", 4, 0)

    -- Category title in suite gold.
    row.text = BazUI.Skin.Theme.FontString(row, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row.toggle, "RIGHT", 6, 0)
    row.text:SetTextColor(unpack(TITLE_COLOR))

    -- Faint horizontal rule that fills the rest of the row beyond the
    -- title text. Visible without competing with the icons below.
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetHeight(1)
    row.line:SetPoint("LEFT", row.text, "RIGHT", 8, 0)
    row.line:SetPoint("RIGHT", -8, 0)
    row.line:SetColorTexture(unpack(DIVIDER_LINE_COLOR))

    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)

    dividerRows[key] = row
    return row
end

---------------------------------------------------------------------------
-- Drop-slot pool - full-size empty bag slot with a gold "+" centered,
-- one per category. Visible only while the cursor is holding an item.
-- Drop the item into the slot to pin it to that category - feels like
-- dragging into the category itself rather than aiming at a tiny
-- target on the divider.
---------------------------------------------------------------------------

local dropSlots = {}

local function ExtractCursorItemID()
    -- GetCursorInfo's second return is the itemID for an item cursor on
    -- retail, but the link form is more reliable across patches. Try
    -- both: parse the link first, then fall back to the raw itemID.
    local infoType, idOrLink, itemLink = GetCursorInfo()
    if infoType ~= "item" then return nil end
    if itemLink then
        local id = itemLink:match("|Hitem:(%d+):")
        if id then return tonumber(id) end
    end
    if type(idOrLink) == "number" then return idOrLink end
    if type(idOrLink) == "string" then
        local id = idOrLink:match("|Hitem:(%d+):")
        if id then return tonumber(id) end
    end
    return nil
end

local function GetOrCreateDropSlot(parent, key, slotSize)
    local slot = dropSlots[key]
    if slot then
        slot:SetParent(parent)
        slot:SetSize(slotSize, slotSize)
        return slot
    end

    slot = CreateFrame("Button", nil, parent)
    slot:SetSize(slotSize, slotSize)
    slot._categoryKey = key

    -- Empty bag-slot artwork (matches the surrounding empty slots so
    -- the drop target reads as "another slot in this category").
    slot.bg = slot:CreateTexture(nil, "BACKGROUND")
    slot.bg:SetAllPoints()
    BazUI.SetAtlasOrTexture(slot.bg, "bags-item-slot64", "Interface\\Buttons\\UI-EmptySlot-Disabled")

    -- Gold "+" centered in the slot. GameFontNormalHuge is gold by
    -- default; SetTextColor pins the exact suite gold so it tracks
    -- the divider title color even if the font is themed.
    slot.plus = BazUI.Skin.Theme.FontString(slot, "OVERLAY", "GameFontNormalHuge")
    slot.plus:SetPoint("CENTER", 0, 1)
    slot.plus:SetText("+")
    slot.plus:SetTextColor(unpack(TITLE_COLOR))

    -- Subtle hover glow - gold tint on a centered overlay so the slot
    -- pulses when the cursor enters, telegraphing the drop affordance.
    slot.hi = slot:CreateTexture(nil, "HIGHLIGHT")
    slot.hi:SetAllPoints()
    slot.hi:SetColorTexture(1, 0.82, 0, 0.18)

    slot:RegisterForClicks("LeftButtonUp")
    slot:RegisterForDrag("LeftButton")

    slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local catName = (addon.Categories.Get(self._categoryKey) or {}).name
                        or self._categoryKey
        GameTooltip:SetText("Pin to " .. catName, 1, 0.82, 0)
        GameTooltip:AddLine("Drop the held item here to pin it to this category.",
                            1, 1, 1, true)
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- OnReceiveDrag fires when the user releases a drag into us.
    -- OnClick handles the click-to-drop case (cursor still has item
    -- after a pickup-by-click). Both go through the same commit path.
    local function Commit(self)
        local itemID = ExtractCursorItemID()
        if not itemID then return end
        addon.Categories.AddItem(itemID, self._categoryKey)
        ClearCursor()
        if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
    end
    slot:SetScript("OnReceiveDrag", Commit)
    slot:SetScript("OnClick", Commit)

    slot:Hide()
    dropSlots[key] = slot
    return slot
end

local function HideAllDropSlots()
    for _, slot in pairs(dropSlots) do
        slot:Hide()
    end
end

local function HideAllDividerRows()
    for _, row in pairs(dividerRows) do
        row:Hide()
    end
end

-- Public hide-all so Bag.lua can clear our chrome when it switches
-- back to bag mode (otherwise stale dividers + drop slots remain
-- visible). Drop slots only ever render in Categories mode +
-- Categorize toggle, but hiding them here is a cheap safety net.
function Layouts.HideAll()
    HideAllDividerRows()
    HideAllDropSlots()
end

---------------------------------------------------------------------------
-- Per-bag rendering - same thin-divider chrome as Categories mode,
-- but groups items by their equipped bag instead of by item type.
-- One divider per bag (Backpack / Bag 1 / Bag 2 / ... / Keyring),
-- each followed by that bag's slot grid.
--
-- Reuses the same dividerRows pool as Categories mode - divider keys
-- are namespaced ("bag_<id>" vs "<categoryKey>") so they coexist
-- without collision. Layouts.HideAll cleans both up when switching
-- back to default Bags mode.
---------------------------------------------------------------------------

-- Bag order and divider labels come from the module core (addon.GetAllBagIDs
-- and addon.BagLabel) so the keyring and reagent bag appear only where the
-- client has them.

function Layouts.RenderPerBag(ctx)
    local frame          = ctx.frame
    local cols           = ctx.cols
    local SLOT_SIZE      = ctx.SLOT_SIZE
    local SLOT_SPACING_X = ctx.SLOT_SPACING_X
    local SLOT_SPACING_Y = ctx.SLOT_SPACING_Y
    local SIDE_PAD       = ctx.SIDE_PAD
    local TOP_PAD        = ctx.TOP_PAD
    local IsCollapsed    = ctx.IsCollapsed
    local SetCollapsed   = ctx.SetCollapsed
    local GetOrCreateSlotButton = ctx.GetOrCreateSlotButton
    local UpdateSlot     = ctx.UpdateSlot
    local Refresh        = ctx.Refresh
    local hideEmpty      = ctx.hideEmpty and true or false

    -- Hide bag-mode chunky-section chrome and Categories-mode
    -- dividers/drop slots so we start from a known-clean slate.
    for _, sec in pairs(addon.Bag.sections) do
        sec.header:Hide()
        sec.body:Hide()
    end
    HideAllDividerRows()
    HideAllDropSlots()

    local y = -TOP_PAD

    for _, bagID in ipairs(addon.GetAllBagIDs()) do
        local n = C_Container.GetContainerNumSlots(bagID) or 0
        if n > 0 then
            local key = "bag_" .. tostring(bagID)
            local collapsed = IsCollapsed(key)

            local divider = GetOrCreateDividerRow(frame, key)
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT",  frame, "TOPLEFT",  SIDE_PAD,  y)
            divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_PAD, y)
            divider.text:SetText(addon.BagLabel(bagID))
            divider.toggle:SetTexture(collapsed
                and "Interface\\Buttons\\UI-PlusButton-Up"
                or  "Interface\\Buttons\\UI-MinusButton-Up")
            local capturedKey = key
            divider:SetScript("OnClick", function()
                SetCollapsed(capturedKey, not IsCollapsed(capturedKey))
                if Refresh then Refresh() end
            end)
            divider:Show()

            y = y - DIVIDER_HEIGHT - DIVIDER_GAP_BELOW

            if not collapsed then
                -- Collect (bagID, slotID) pairs for this bag, honouring
                -- the user's Hide Empty Slots setting.
                local items = {}
                for slotID = 1, n do
                    if hideEmpty then
                        local info = C_Container.GetContainerItemInfo(bagID, slotID)
                        if info and info.iconFileID then
                            items[#items + 1] = { bagID = bagID, slotID = slotID }
                        end
                    else
                        items[#items + 1] = { bagID = bagID, slotID = slotID }
                    end
                end

                for i, p in ipairs(items) do
                    local btn = GetOrCreateSlotButton(p.bagID, p.slotID)
                    local col = (i - 1) % cols
                    local row = math.floor((i - 1) / cols)
                    if btn then
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                        SIDE_PAD + col * (SLOT_SIZE + SLOT_SPACING_X),
                        y - row * (SLOT_SIZE + SLOT_SPACING_Y))
                    btn:Show()
                    UpdateSlot(btn, p.bagID, p.slotID)
                    end
                end

                if #items > 0 then
                    local rows  = math.ceil(#items / cols)
                    local bodyH = rows * SLOT_SIZE + math.max(0, rows - 1) * SLOT_SPACING_Y
                    y = y - bodyH - CATEGORY_GAP
                else
                    -- Empty bag (e.g. equipped but contains nothing
                    -- and Hide Empty is on). Still leaves the divider
                    -- visible so the user knows the bag exists.
                    y = y - CATEGORY_GAP
                end
            else
                y = y - CATEGORY_GAP
            end
        end
    end

    return y
end

---------------------------------------------------------------------------
-- Render - the only category layout.
--
-- Each category gets a thin full-width divider row, then its items
-- in a regular grid below. Items wrap inside the category. The next
-- category always starts on a fresh row.
--
-- ctx is a table of frame primitives Bag.lua hands us so this module
-- doesn't have to re-look up addon state.
---------------------------------------------------------------------------

function Layouts.Render(ctx)
    local frame          = ctx.frame
    local cols           = ctx.cols
    local SLOT_SIZE      = ctx.SLOT_SIZE
    local SLOT_SPACING_X = ctx.SLOT_SPACING_X
    local SLOT_SPACING_Y = ctx.SLOT_SPACING_Y
    local SIDE_PAD       = ctx.SIDE_PAD
    local TOP_PAD        = ctx.TOP_PAD
    local IsCollapsed    = ctx.IsCollapsed
    local SetCollapsed   = ctx.SetCollapsed
    local GetOrCreateSlotButton = ctx.GetOrCreateSlotButton
    local UpdateSlot     = ctx.UpdateSlot
    local Refresh        = ctx.Refresh

    local Categories = addon.Categories
    local byCategory = Categories.GetPairsByCategory()
    local catList    = Categories.GetOrdered()

    -- Categorize mode (toggled via left-click on the bag's portrait)
    -- reveals every category - including hidden ones and ones with
    -- zero items - and shows a gold "+" drop slot at the end of each
    -- grid for click-to-pin / drag-to-pin. Outside of categorize
    -- mode the bag stays clean: no drop slots, no empty categories,
    -- no hidden ones.
    local categorizeMode = (addon.Bag and addon.Bag.IsCategorizeMode
                            and addon.Bag.IsCategorizeMode()) and true or false

    -- A `hidden = true` flag on a category suppresses it from the bag
    -- panel during normal use - no divider, no items, no drop slot.
    -- During categorize mode hidden categories DO render (so the user
    -- can pin items into them by drop slot) but get a gray "(hidden)"
    -- tag on the divider so they're visually distinguishable.
    local hiddenByKey = {}
    for _, info in ipairs(Categories.GetAll()) do
        if info.hidden then hiddenByKey[info.key] = true end
    end

    -- Hide bag-mode section chrome in case the user just switched modes.
    for _, sec in pairs(addon.Bag.sections) do
        sec.header:Hide()
        sec.body:Hide()
    end
    HideAllDividerRows()
    HideAllDropSlots()

    local y = -TOP_PAD

    for _, cat in ipairs(catList) do
        local items     = byCategory[cat.key] or {}
        local hasItems  = #items > 0
        local isHidden  = hiddenByKey[cat.key] == true

        -- Visibility rules:
        --   * Normal mode:   show only categories with items, skip hidden ones
        --   * Categorize:    show every category (incl. empty + hidden) so
        --                    the user can manage pins everywhere
        local visible
        if categorizeMode then
            visible = true
        else
            visible = hasItems and not isHidden
        end

        if visible then
            local collapsed = IsCollapsed(cat.key)

            -- Divider row spans the full width. Hidden categories get
            -- a gray "(hidden)" tag during categorize mode so the user
            -- can tell at a glance which ones are excluded from
            -- normal display.
            local titleText = cat.title or cat.name or cat.key
            if isHidden then
                titleText = titleText .. "  |cff888888(hidden)|r"
            end
            local divider = GetOrCreateDividerRow(frame, cat.key)
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT",  frame, "TOPLEFT",  SIDE_PAD,  y)
            divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_PAD, y)
            divider.text:SetText(titleText)
            divider.toggle:SetTexture(collapsed
                and "Interface\\Buttons\\UI-PlusButton-Up"
                or  "Interface\\Buttons\\UI-MinusButton-Up")
            local key = cat.key
            divider:SetScript("OnClick", function()
                SetCollapsed(key, not IsCollapsed(key))
                if Refresh then Refresh() end
            end)
            divider:Show()

            y = y - DIVIDER_HEIGHT - DIVIDER_GAP_BELOW

            if not collapsed then
                -- Render real bag items first.
                for i, p in ipairs(items) do
                    local btn = GetOrCreateSlotButton(p.bagID, p.slotID)
                    local col = (i - 1) % cols
                    local row = math.floor((i - 1) / cols)
                    if btn then
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                        SIDE_PAD + col * (SLOT_SIZE + SLOT_SPACING_X),
                        y - row * (SLOT_SIZE + SLOT_SPACING_Y))
                    btn:Show()
                    UpdateSlot(btn, p.bagID, p.slotID)
                    end
                end

                -- One extra "drop slot" at the end during categorize
                -- mode. Counts as a real slot for layout math so the
                -- category grows by one cell (and wraps to a new row
                -- if the previous row was full).
                local effective = #items
                if categorizeMode then
                    local nextI = #items + 1
                    local col = (nextI - 1) % cols
                    local row = math.floor((nextI - 1) / cols)
                    local drop = GetOrCreateDropSlot(frame, cat.key, SLOT_SIZE)
                    drop:ClearAllPoints()
                    drop:SetPoint("TOPLEFT", frame, "TOPLEFT",
                        SIDE_PAD + col * (SLOT_SIZE + SLOT_SPACING_X),
                        y - row * (SLOT_SIZE + SLOT_SPACING_Y))
                    drop:Show()
                    effective = effective + 1
                end

                local rows  = math.max(math.ceil(effective / cols), categorizeMode and 1 or 0)
                local bodyH = rows * SLOT_SIZE + math.max(0, rows - 1) * SLOT_SPACING_Y
                y = y - bodyH - CATEGORY_GAP
            else
                y = y - CATEGORY_GAP
            end
        end
    end

    return y
end
