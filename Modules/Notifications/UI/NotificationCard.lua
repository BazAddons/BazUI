-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications
local BNC = addon.API

local Colors = addon.Colors

---------------------------------------------------------------------------
-- Shared body metrics (used by both NotificationCard and Toast)
---------------------------------------------------------------------------

-- How a card's message is drawn.
--
-- Most cards say what happened in the title and put the detail
-- underneath, where it belongs: read the title, read the rest if you
-- care. A few are the other way round - the title is the category and the
-- message is the whole point of it, a coin amount or an experience gain -
-- and those can ask to be read first instead of last.
--
-- One function rather than the choice made in each renderer, because the
-- toast and the panel draw the same card and a card that changed size
-- between them would be a card that jumps when you open the panel.
function addon.ApplyMessageStyle(fontString, emphasis)
    if not fontString then return end
    local Theme = BazUI.Skin.Theme
    if emphasis then
        fontString:SetFontObject(Theme.FontObject("GameFontNormalLarge"))
        fontString:SetTextColor(unpack(Colors.textPrimary))
    else
        fontString:SetFontObject(Theme.FontObject("GameFontHighlightSmall"))
        fontString:SetTextColor(unpack(Colors.textSecondary))
    end
end

local BODY_PADDING = 8
local BODY_ICON_SIZE = 28
local TITLE_MESSAGE_GAP = 4

-- Card-specific metrics
local CARD_WIDTH = 290
local CARD_MIN_HEIGHT = 48
local TIMESTAMP_RESERVED_WIDTH = 90  -- bottom-right space reserved for the timestamp
local DISMISS_RESERVED_WIDTH  = 24  -- top-right space reserved for the dismiss button

local BACKDROP_CARD = BazUI.Skin.Theme.BACKDROP_FLAT

---------------------------------------------------------------------------
-- Shared notification body factory
--
-- Creates the visual elements common to cards and toasts:
--   icon, moduleLabel, title, message, priorityBar
--
-- Both panel cards and floating toasts call this so any future layout
-- change only has to happen in one place.
--
-- The moduleLabel is created on every body but stays hidden by default.
-- Toasts show it inline (they have no group header above them); cards
-- leave it hidden because the module is already shown by GroupHeader.
---------------------------------------------------------------------------

function addon.CreateNotificationBody(frame)
    -- Icon
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(BODY_ICON_SIZE, BODY_ICON_SIZE)
    frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", BODY_PADDING, -BODY_PADDING)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Module label (bottom-right corner - identifies source addon on toasts
    -- without displacing the title. Hidden on cards since the GroupHeader
    -- already shows the module name above them.)
    frame.moduleLabel = frame:CreateFontString(nil, "OVERLAY")
    frame.moduleLabel:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormalSmall"))
    frame.moduleLabel:SetTextColor(unpack(Colors.textMuted))
    frame.moduleLabel:SetJustifyH("RIGHT")
    frame.moduleLabel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BODY_PADDING, BODY_PADDING)
    frame.moduleLabel:Hide()

    -- Title - always anchored to the top-right of the icon
    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormal"))
    frame.title:SetTextColor(unpack(Colors.textPrimary))
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(true)
    frame.title:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 6, 0)
    frame.title:SetPoint("RIGHT", frame, "RIGHT", -BODY_PADDING, 0)

    -- Message (full-width row below the icon/title block)
    frame.message = frame:CreateFontString(nil, "OVERLAY")
    frame.message:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontHighlightSmall"))
    frame.message:SetTextColor(unpack(Colors.textSecondary))
    frame.message:SetJustifyH("LEFT")
    frame.message:SetWordWrap(true)
    frame.message:SetPoint("TOPLEFT", frame, "TOPLEFT",
        BODY_PADDING, -(BODY_PADDING + BODY_ICON_SIZE + TITLE_MESSAGE_GAP))
    frame.message:SetPoint("RIGHT", frame, "RIGHT", -BODY_PADDING, 0)

    -- Priority accent bar (left edge)
    frame.priorityBar = frame:CreateTexture(nil, "OVERLAY")
    -- Three pixels rather than two: it is a colour to be read now, not
    -- just a mark that something is there.
    frame.priorityBar:SetSize(3, 1)
    frame.priorityBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -1)
    frame.priorityBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 1)
    frame.priorityBar:Hide()
end

---------------------------------------------------------------------------
-- Shared populate helper
--
-- Fills a card/toast body with data from a notification and returns the
-- calculated total height. Options:
--   opts.showModuleLabel      - show addon-name row above title (toasts)
--   opts.bottomRightReserved  - pixels to reserve on the right of the
--                               message row, for anything sitting in that
--                               corner
--   opts.rightReservedWidth   - pixels to reserve on the right of the top
--                               row (e.g. for a card's timestamp column)
---------------------------------------------------------------------------

function addon.PopulateNotification(frame, notifData, width, opts)
    opts = opts or {}

    -- Icon
    if notifData.icon then
        frame.icon:SetTexture(notifData.icon)
        frame.icon:Show()
    else
        frame.icon:Hide()
    end

    -- Module label (bottom-right). Doesn't displace the title row.
    local labelWidth = 0
    if opts.showModuleLabel then
        local moduleName
        if notifData.module and addon.modules and addon.modules[notifData.module] then
            moduleName = addon.modules[notifData.module].name
        end
        if moduleName and moduleName ~= "" then
            frame.moduleLabel:SetText(moduleName)
            frame.moduleLabel:Show()
            labelWidth = frame.moduleLabel:GetStringWidth() or 0
        else
            frame.moduleLabel:Hide()
        end
    else
        frame.moduleLabel:Hide()
    end

    -- Text
    -- Through the theme: a player's name can hold characters the
    -- suite's face has none of, and a row of boxes is not a name.
    BazUI.Skin.Theme.SetText(frame.title, notifData.title or "")
    BazUI.Skin.Theme.SetText(frame.message, notifData.message or "")
    addon.ApplyMessageStyle(frame.message, notifData.emphasis)

    -- The band down the left. Its colour says which source the card came
    -- from, so a mixed panel groups by eye; how solid it is says how much
    -- the card wants looking at. Every card has one - a card without a
    -- band used to mean "normal", which read as less important than the
    -- chatter that had one.
    local band = BNC:GetModuleColor(notifData.module)
    local alphas = Colors.priorityAlpha or {}
    local alpha = alphas[notifData.priority or "normal"] or alphas.normal or 1
    frame.priorityBar:SetColorTexture(band[1], band[2], band[3], alpha)
    frame.priorityBar:Show()

    -- Top row width (title): reserve whatever sits in the top right, which
    -- on a card is the dismiss button and nothing else.
    local topRowRightReserve = opts.rightReservedWidth or BODY_PADDING
    local topRowWidth = width - BODY_PADDING - BODY_ICON_SIZE - 6 - topRowRightReserve
    frame.title:SetWidth(topRowWidth)

    -- The bottom row is shared: the message on one side, and on the other
    -- whatever small print that card carries - the module label on a
    -- toast, the timestamp on a card. How much room that takes is the
    -- same question either way.
    local metaWidth = (labelWidth > 0) and (labelWidth + 8)
        or (opts.bottomRightReserved or 0)

    -- Which of them gets which side. A card whose message is the point of
    -- it puts the figure on the right and the small print on the left -
    -- the shape a line in a ledger takes, and the only way a two-character
    -- amount does not sit in a corner with the rest of the row empty.
    -- Everything else keeps the message left, where a block of text
    -- belongs and where it has the room to wrap.
    local emphasis = notifData.emphasis and true or false
    frame.message:SetJustifyH(emphasis and "RIGHT" or "LEFT")
    frame.message:SetWidth(math.max(10,
        width - BODY_PADDING - BODY_PADDING - metaWidth))

    -- Height calculation
    local titleHeight = frame.title:GetStringHeight() or 14
    local msgHeight = frame.message:GetStringHeight() or 0
    local hasMessage = notifData.message and notifData.message ~= ""

    local iconRegionHeight = math.max(BODY_ICON_SIZE, titleHeight)

    -- Reposition message below the icon/title block, on whichever side of
    -- that row it has been given.
    local messageTop = -(BODY_PADDING + iconRegionHeight + TITLE_MESSAGE_GAP)
    frame.message:ClearAllPoints()
    if emphasis then
        frame.message:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -BODY_PADDING, messageTop)
    else
        frame.message:SetPoint("TOPLEFT", frame, "TOPLEFT", BODY_PADDING, messageTop)
    end

    -- The small print takes the other corner, so the two can never meet
    -- in the middle.
    if frame.moduleLabel and labelWidth > 0 then
        frame.moduleLabel:ClearAllPoints()
        frame.moduleLabel:SetJustifyH(emphasis and "LEFT" or "RIGHT")
        if emphasis then
            frame.moduleLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT",
                BODY_PADDING, BODY_PADDING)
        else
            frame.moduleLabel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",
                -BODY_PADDING, BODY_PADDING)
        end
    end

    local totalHeight = BODY_PADDING + iconRegionHeight
        + (hasMessage and (TITLE_MESSAGE_GAP + msgHeight) or 0)
        + BODY_PADDING

    -- If the module label is shown but there's no message, reserve a row
    -- below the icon/title block so the label has somewhere to sit.
    if labelWidth > 0 and not hasMessage then
        totalHeight = totalHeight + TITLE_MESSAGE_GAP + 12
    end

    return totalHeight
end

---------------------------------------------------------------------------
-- Notification Card (panel)
---------------------------------------------------------------------------

local function CreateCard(index)
    local card = CreateFrame("Button", "BazUINotifCard" .. index, UIParent, "BackdropTemplate")
    card:SetSize(CARD_WIDTH, CARD_MIN_HEIGHT)
    card:SetBackdrop(BACKDROP_CARD)
    card:SetBackdropColor(unpack(Colors.cardBg))
    card:SetBackdropBorderColor(unpack(Colors.cardBorder))
    card:EnableMouse(true)
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card:Hide()

    -- Shared body: icon, moduleLabel, title, message, priorityBar
    addon.CreateNotificationBody(card)

    -- Timestamp (card-only, bottom-right)
    --
    -- Bottom rather than top, because the dismiss button lives in the top
    -- right corner and the two were sitting on top of one another. Nothing
    -- else is down there: a card never shows the module label, which is
    -- what that corner is for on a toast.
    card.timestamp = card:CreateFontString(nil, "OVERLAY")
    card.timestamp:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormalSmall"))
    card.timestamp:SetTextColor(unpack(Colors.textMuted))
    card.timestamp:SetJustifyH("RIGHT")
    card.timestamp:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -BODY_PADDING, BODY_PADDING)

    -- Dismiss button (card-only)
    card.dismissBtn = CreateFrame("Button", nil, card)
    card.dismissBtn:SetSize(16, 16)
    card.dismissBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4, -4)
    card.dismissBtn:Hide()

    card.dismissBtn.text = card.dismissBtn:CreateFontString(nil, "OVERLAY")
    card.dismissBtn.text:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormalSmall"))
    card.dismissBtn.text:SetText("x")
    card.dismissBtn.text:SetTextColor(unpack(Colors.dismissNormal))
    card.dismissBtn.text:SetAllPoints()

    card.dismissBtn:SetScript("OnEnter", function(self)
        self.text:SetTextColor(unpack(Colors.dismissHover))
    end)
    card.dismissBtn:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(Colors.dismissNormal))
    end)
    card.dismissBtn:SetScript("OnClick", function()
        if card.notificationId then
            BNC:DismissNotification(card.notificationId)
        end
    end)

    -- Hover effects + item tooltip
    card:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(Colors.cardHover))
        self.dismissBtn:Show()
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    card:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(Colors.cardBg))
        self.dismissBtn:Hide()
        if self.itemLink then
            GameTooltip:Hide()
        end
    end)

    -- Click handler: ctrl-click dressing room, shift-click link, else waypoint/onClick
    card:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if self.notificationId then
                BNC:DismissNotification(self.notificationId)
            end
            return
        end
        if self.itemLink then
            if IsControlKeyDown() then
                DressUpItemLink(self.itemLink)
                return
            end
            if IsShiftKeyDown() then
                ChatEdit_InsertLink(self.itemLink)
                return
            end
        end
        if self.waypointData then
            BNC:SetWaypoint(self.waypointData)
        elseif self.onClickCallback then
            addon.SafeCall(self.onClickCallback)
        end
    end)

    return card
end

local function ResetCard(card)
    card:Hide()
    card:SetParent(UIParent)
    card:ClearAllPoints()
    card.notificationId = nil
    card.onClickCallback = nil
    card.waypointData = nil
    card.itemLink = nil
    card.priorityBar:Hide()
    card.dismissBtn:Hide()
    card:SetBackdropColor(unpack(Colors.cardBg))
end

-- Create the card pool
addon.CardPool = BazUI:CreateObjectPool(CreateCard, ResetCard)

-- Helper to configure a card with notification data
function addon.SetupCard(card, notifData)
    card.notificationId = notifData.id
    card.onClickCallback = notifData.onClick
    card.waypointData = notifData.waypoint
    card.itemLink = notifData.itemLink

    local totalHeight = addon.PopulateNotification(card, notifData, CARD_WIDTH, {
        showModuleLabel = false,
        rightReservedWidth = DISMISS_RESERVED_WIDTH,
        bottomRightReserved = TIMESTAMP_RESERVED_WIDTH,
    })
    card:SetHeight(math.max(CARD_MIN_HEIGHT, totalHeight))

    -- Timestamp
    local timeStr = addon.FormatRelativeTime(notifData.timestamp)
    if notifData.realTime then
        timeStr = addon.FormatCardTimestamp(notifData.realTime) .. " - " .. timeStr
    end
    card.timestamp:SetText(timeStr)
    -- The far side from the message, for the same reason.
    card.timestamp:ClearAllPoints()
    if notifData.emphasis then
        card.timestamp:SetJustifyH("LEFT")
        card.timestamp:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT",
            BODY_PADDING, BODY_PADDING)
    else
        card.timestamp:SetJustifyH("RIGHT")
        card.timestamp:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT",
            -BODY_PADDING, BODY_PADDING)
    end
    card.notifTimestamp = notifData.timestamp
    card.notifRealTime = notifData.realTime

    return card
end

function addon.UpdateCardTimestamp(card)
    if card.notifTimestamp then
        local timeStr = addon.FormatRelativeTime(card.notifTimestamp)
        if card.notifRealTime then
            timeStr = addon.FormatCardTimestamp(card.notifRealTime) .. " - " .. timeStr
        end
        card.timestamp:SetText(timeStr)
    end
end

addon.CARD_WIDTH = CARD_WIDTH
