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
local headerNote, headerWarn

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

---------------------------------------------------------------------------
-- The header
--
-- The box stays above the scroll so you can drop links into it however
-- far down the list you have scrolled.
---------------------------------------------------------------------------

local header

local function BuildHeader(host)
    if header then
        header:SetParent(host)
        return header
    end

    header = CreateFrame("Frame", nil, host)
    header:SetPoint("TOPLEFT")

    header.box = Theme.CreateSearchBox(header, "Drop an item link here to want it")
    header.box:SetPoint("TOPLEFT", 0, 0)
    header.box:SetPoint("TOPRIGHT", 0, 0)
    -- The box adds rather than filters, so Enter is the commit and the
    -- field empties itself ready for the next one.
    header.box:SetScript("OnEnterPressed", function(self)
        local ok, err = Add(self:GetText())
        message = ok and nil or err
        self:SetText("")
        self:ClearFocus()
        Codex.Panel:QueueRefresh()
    end)
    -- Shift-clicking an item writes its link into the focused box; catch
    -- that and take the item straight away.
    header.box:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.placeholder:SetShown(text == "")
        if text:find("item:%d+") then
            local ok, err = Add(text)
            message = ok and nil or err
            self:SetText("")
            Codex.Panel:QueueRefresh()
        end
    end)

    header.note = Theme.FontString(header, "OVERLAY", "GameFontHighlightSmall")
    header.note:SetPoint("TOPLEFT", header.box, "BOTTOMLEFT", 2, -7)
    header.note:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    header.note:SetJustifyH("LEFT")
    header.note:SetJustifyV("TOP")
    header.note:SetHeight(26)
    header.note:SetWordWrap(true)
    header.note:SetTextColor(unpack(Theme.colors.textMuted))

    return header
end

local function RenderHeader(host, width)
    local h = BuildHeader(host)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT")
    h:SetWidth(width)
    h:Show()
    h.note:SetText(headerNote or "")
    h.note:SetTextColor(unpack(headerWarn and Theme.colors.warn or Theme.colors.textMuted))

    local height = 22 + 7 + 26 + 8
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

    -- The list sits in the same card the rest of the codex draws.
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
        headerNote, headerWarn = message, true
    elseif #entries == 0 then
        headerNote = "Nothing on the list yet. Shift-click an item into the box above, or paste its link."
        headerWarn = false
    else
        headerNote = #entries == 1 and "1 thing you are after"
            or (#entries .. " things you are after")
        headerWarn = false
    end
    if header and header:IsShown() then
        header.note:SetText(headerNote)
        header.note:SetTextColor(unpack(headerWarn and Theme.colors.warn or Theme.colors.textMuted))
    end

    local y = 6
    for _, entry in ipairs(entries) do
        local itemID = entry.itemID
        local name, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(itemID)
        if not name and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end

        local row = AcquireRow(p.card)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 1, -y)
        row:SetPoint("TOPRIGHT", -1, -y)
        row.itemID = itemID
        row.icon:SetTexture(texture
            or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
            or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.label:SetText(name or entry.name)
        local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if color then
            row.label:SetTextColor(color.r, color.g, color.b)
        else
            row.label:SetTextColor(unpack(Theme.colors.text))
        end

        -- Having it is the only thing the client can tell us; everything
        -- else about wanting an item lives in your head.
        local count = C_Item.GetItemCount(itemID, true) or 0
        if count > 0 then
            row.detail:SetText(count > 1 and ("got " .. count) or "got it")
            row.detail:SetTextColor(unpack(Theme.colors.success))
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

    local cardHeight = math.max(y + 6, 28)
    p.card:SetHeight(cardHeight)
    p.card:SetShown(#entries > 0)

    local used = (#entries > 0) and cardHeight or 1
    p:SetHeight(used)
    Codex.customTabs.wishlist.height = used
end

Codex.customTabs.wishlist = {
    label        = "Wishlist",
    order        = 40,
    RenderHeader = RenderHeader,
    Render       = Render,
    Hide         = function()
        if page then page:Hide() end
        if header then header:Hide() end
    end,
    height = 1,
    GetHighlights = function()
        local wanted, got = 0, 0
        for itemID in pairs(List()) do
            wanted = wanted + 1
            if (C_Item.GetItemCount(itemID, true) or 0) > 0 then got = got + 1 end
        end
        return {
            { value = wanted - got, label = "still wanted" },
            { value = got, label = "already yours",
              color = got > 0 and Theme.colors.success or nil },
        }
    end,
}

-- Picking something up off the list is worth noticing.
BazUI:QueueForModule("Codex", function()
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("BAG_UPDATE_DELAYED")
    watcher:SetScript("OnEvent", function()
        if Codex:IsShown() then Codex.Panel:QueueRefresh() end
    end)
end)
