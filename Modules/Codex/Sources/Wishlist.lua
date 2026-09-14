-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex: wishlist
--
-- The things you are playing towards. Drop an item link in the box, or
-- shift-click an item anywhere in the game while the box has the cursor,
-- and it joins the list with the date you wanted it. When one turns up
-- in your bags the row says so, which is the only automatic part: the
-- codex does not know where anything drops and will not pretend to.
--
-- The list lives in the profile, so it follows you the way the rest of
-- your settings do.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local addon = BazUI:GetModule("Codex")
local Theme = BazUI.Skin.Theme

local ROW_H  = 22
local HEAD_H = 50

Codex.customTabs = Codex.customTabs or {}

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

local function List()
    return addon:GetSetting("wishlist") or {}
end

local function Save(list)
    addon:SetSetting("wishlist", list)
    Codex.Panel:QueueRefresh()
end

-- Accepts a link, an item number, or a name already in the item index.
local function Add(text)
    text = (text or ""):trim()
    if text == "" then return false, nil end

    local itemID = tonumber(text:match("item:(%d+)") or text)
    if not itemID then
        local needle = text:lower()
        for id, name in pairs(addon:GetSetting("itemIndex") or {}) do
            if type(name) == "string" and name:lower() == needle then
                itemID = id
                break
            end
        end
    end
    if not itemID then
        return false, "Drop in an item link, or an item number."
    end
    if C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(itemID) then
        return false, "No item carries the number " .. itemID .. "."
    end

    local list = List()
    if list[itemID] then
        return false, (C_Item.GetItemInfo(itemID) or ("Item " .. itemID)) .. " is already on the list."
    end
    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    list[itemID] = { added = time() }
    Save(list)
    return true, nil
end

local function Remove(itemID)
    local list = List()
    list[itemID] = nil
    Save(list)
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local page, pool = nil, {}
local message

local function AcquireRow(parent)
    local row = table.remove(pool)
    if row then
        row:SetParent(parent)
        return row
    end

    row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)

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

    row.detail = Theme.FontString(row, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetPoint("RIGHT", -22, 0)
    row.detail:SetJustifyH("RIGHT")
    row.label:SetPoint("RIGHT", row.detail, "LEFT", -6, 0)

    -- One way off the list, and it is where your eye already is.
    row.drop = CreateFrame("Button", nil, row)
    row.drop:SetSize(16, 16)
    row.drop:SetPoint("RIGHT", -2, 0)
    row.drop.text = Theme.FontString(row.drop, "OVERLAY", "GameFontNormal")
    row.drop.text:SetAllPoints()
    row.drop.text:SetText("x")
    row.drop.text:SetTextColor(unpack(Theme.colors.textMuted))
    row.drop:SetScript("OnEnter", function(self)
        self.text:SetTextColor(unpack(Theme.colors.danger))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Take this off the wishlist", unpack(Theme.colors.text))
        GameTooltip:Show()
    end)
    row.drop:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(Theme.colors.textMuted))
        GameTooltip:Hide()
    end)
    row.drop:SetScript("OnClick", function(self)
        Remove(self:GetParent().itemID)
    end)

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
        if not (self.itemID and IsShiftKeyDown() and ChatEdit_InsertLink) then return end
        local _, link = C_Item.GetItemInfo(self.itemID)
        if link then ChatEdit_InsertLink(link) end
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

    page.box = Theme.CreateSearchBox(page, "Drop an item link here to want it")
    page.box:SetPoint("TOPLEFT", 0, 0)
    page.box:SetPoint("TOPRIGHT", 0, 0)
    -- The box adds rather than filters, so Enter is the commit and the
    -- field empties itself ready for the next one.
    page.box:SetScript("OnEnterPressed", function(self)
        local ok, err = Add(self:GetText())
        message = err
        if ok then message = nil end
        self:SetText("")
        self:ClearFocus()
        Codex.Panel:QueueRefresh()
    end)
    -- Shift-clicking an item writes its link into the focused box; catch
    -- that and take the item straight away.
    page.box:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.placeholder:SetShown(text == "")
        if text:find("item:%d+") then
            local ok, err = Add(text)
            message = ok and nil or err
            self:SetText("")
            Codex.Panel:QueueRefresh()
        end
    end)

    page.note = Theme.FontString(page, "OVERLAY", "GameFontHighlightSmall")
    page.note:SetPoint("TOPLEFT", page.box, "BOTTOMLEFT", 2, -6)
    page.note:SetPoint("TOPRIGHT", page.box, "BOTTOMRIGHT", -2, -6)
    page.note:SetJustifyH("LEFT")
    page.note:SetTextColor(unpack(Theme.colors.textMuted))

    return page
end

local function Render(content, width)
    local p = Build(content)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT")
    p:SetWidth(width)
    p:Show()
    ReleaseRows()

    local list = List()
    local entries = {}
    for itemID, data in pairs(list) do
        entries[#entries + 1] = {
            itemID = itemID,
            added  = (type(data) == "table" and data.added) or 0,
            name   = C_Item.GetItemInfo(itemID) or ("Item " .. itemID),
        }
    end
    table.sort(entries, function(a, b)
        if a.added ~= b.added then return a.added > b.added end
        return a.name < b.name
    end)

    if message then
        p.note:SetText(message)
        p.note:SetTextColor(unpack(Theme.colors.warn))
    elseif #entries == 0 then
        p.note:SetText("Nothing on the list yet. Shift-click an item into the box above, or paste its link.")
        p.note:SetTextColor(unpack(Theme.colors.textMuted))
    else
        p.note:SetText(#entries == 1 and "1 thing you are after" or (#entries .. " things you are after"))
        p.note:SetTextColor(unpack(Theme.colors.textMuted))
    end

    local y = HEAD_H
    for _, entry in ipairs(entries) do
        local itemID = entry.itemID
        local name, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(itemID)
        if not name and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end

        local row = AcquireRow(p)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        row.itemID = itemID
        row.icon:SetTexture(texture
            or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
            or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.label:SetText(name or entry.name)
        local colour = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if colour then
            row.label:SetTextColor(colour.r, colour.g, colour.b)
        else
            row.label:SetTextColor(unpack(Theme.colors.text))
        end

        -- Having it is the only thing the client can tell us; everything
        -- else about wanting an item lives in your head.
        local count = C_Item.GetItemCount(itemID, true) or 0
        if count > 0 then
            row.detail:SetText(count > 1 and ("got " .. count) or "got it")
            row.detail:SetTextColor(0.45, 0.75, 0.45, 1)
        elseif entry.added > 0 then
            row.detail:SetText("wanted " .. BazUI:FormatSpan(time() - entry.added) .. " ago")
            row.detail:SetTextColor(unpack(Theme.colors.textMuted))
        else
            row.detail:SetText("")
        end

        row:Show()
        p.rows[#p.rows + 1] = row
        y = y + ROW_H
    end

    p:SetHeight(math.max(y, 1))
    Codex.customTabs.wishlist.height = y
end

Codex.customTabs.wishlist = {
    label  = "Wishlist",
    order  = 40,
    Render = Render,
    Hide   = function() if page then page:Hide() end end,
    height = 1,
}

-- Picking something up off the list is worth noticing.
BazUI:QueueForLogin(function()
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("BAG_UPDATE_DELAYED")
    watcher:SetScript("OnEvent", function()
        if Codex:IsShown() then Codex.Panel:QueueRefresh() end
    end)
end)
