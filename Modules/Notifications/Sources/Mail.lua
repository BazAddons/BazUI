-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Mail: Alerts for new mail arrival and mailbox contents summary.
-- Events: PLAYER_ENTERING_WORLD, UPDATE_PENDING_MAIL, MAIL_SHOW, MAIL_CLOSED
-- ==========================================================================

local MODULE_ID = "mail"
local MODULE_NAME = "Mail"
local MODULE_ICON = "Interface\\Icons\\INV_Letter_01"

local ICON_MAIL = "Interface\\Icons\\INV_Letter_01"
local ICON_MAIL_AH = "Interface\\Icons\\INV_Misc_Coin_01"

-- Tracks count across mailbox opens to only notify about genuinely new items
local lastMailCount = 0
-- Guards against duplicate "new mail" toasts within a single session
local hasNotifiedNewMail = false

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local function OnNewMail()
    if GetSetting("showNewMail") == false then return end
    if hasNotifiedNewMail then return end
    hasNotifiedNewMail = true

    BNC:Push({
        module = MODULE_ID,
        title = "New Mail",
        message = "You've got mail!",
        icon = ICON_MAIL,
        priority = "normal",
        duration = GetSetting("mailDuration") or 5,
        silent = GetSetting("mailToasts") == false,
    })
end

local function OnMailCleared()
    hasNotifiedNewMail = false
end

-- Summarises inbox contents when the mailbox is opened, showing up to 5 new items
local function OnMailboxOpened()
    if GetSetting("showMailDetails") == false then return end

    local numItems = GetInboxNumItems()
    if numItems == 0 then return end

    local newCount = numItems - lastMailCount
    if newCount <= 0 then
        lastMailCount = numItems
        return
    end

    local maxToShow = math.min(newCount, 5)

    for i = 1, maxToShow do
        local _, _, sender, subject, money, _, _, hasItem = GetInboxHeaderInfo(i)

        if sender or subject then
            local title = sender or "Unknown"
            local message = subject or "No subject"

            local icon = ICON_MAIL
            local priority = "low"

            -- Gold attached likely means AH proceeds
            if money and money > 0 then
                icon = ICON_MAIL_AH
                local gold = math.floor(money / 10000)
                local silver = math.floor((money % 10000) / 100)
                local moneyStr = ""
                if gold > 0 then
                    moneyStr = "|cffffd700" .. gold .. "|rg"
                end
                if silver > 0 then
                    moneyStr = moneyStr .. (moneyStr ~= "" and " " or "") .. "|cffc7c7cf" .. silver .. "|rs"
                end
                if moneyStr ~= "" then
                    message = message .. " (" .. moneyStr .. ")"
                end
                priority = "normal"
            end

            if hasItem then
                message = message .. " [Has Attachments]"
            end

            BNC:Push({
                module = MODULE_ID,
                title = title,
                message = message,
                icon = icon,
                priority = priority,
                duration = GetSetting("detailDuration") or 4,
                silent = GetSetting("detailToasts") == false,
            })
        end
    end

    -- Overflow notice for remaining unseen messages
    if newCount > maxToShow then
        BNC:Push({
            module = MODULE_ID,
            title = "Mail",
            message = "+" .. (newCount - maxToShow) .. " more messages",
            icon = ICON_MAIL,
            priority = "low",
            duration = 3,
            silent = true,
        })
    end

    lastMailCount = numItems
end

-- Snapshot count on close so next open can diff against it
local function OnMailboxClosed()
    lastMailCount = GetInboxNumItems()
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UPDATE_PENDING_MAIL")
eventFrame:RegisterEvent("MAIL_INBOX_UPDATE")
eventFrame:RegisterEvent("MAIL_SHOW")
eventFrame:RegisterEvent("MAIL_CLOSED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        hasNotifiedNewMail = false
        if HasNewMail() then
            OnNewMail()
        end
    elseif event == "UPDATE_PENDING_MAIL" then
        if HasNewMail() then
            OnNewMail()
        else
            OnMailCleared()
        end
    elseif event == "MAIL_SHOW" then
        -- Brief delay so inbox data is populated before we read it
        C_Timer.After(0.5, OnMailboxOpened)
    elseif event == "MAIL_CLOSED" then
        OnMailboxClosed()
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { key = "showNewMail",     label = "Show New Mail Alert",          type = "toggle", default = true },
    { key = "showMailDetails", label = "Show Mail Details on Open",    type = "toggle", default = true },
    { key = "mailToasts",      label = "Toast on New Mail",            type = "toggle", default = true },
    { key = "detailToasts",    label = "Toast Mail Details",           type = "toggle", default = true },
    { key = "mailDuration",    label = "New Mail Toast Duration",      type = "slider", default = 5, min = 1, max = 15, step = 1 },
    { key = "detailDuration",  label = "Detail Toast Duration",        type = "slider", default = 4, min = 1, max = 15, step = 1 },
})
