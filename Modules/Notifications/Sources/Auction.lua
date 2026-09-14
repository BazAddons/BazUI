-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Auction: Notifications for auction house sold, expired, outbid, won.
-- Events: CHAT_MSG_SYSTEM, AUCTION_HOUSE_AUCTION_CREATED, AUCTION_HOUSE_SHOW
-- ==========================================================================

local MODULE_ID = "auction"
local MODULE_NAME = "Auction House"
local MODULE_ICON = "Interface\\Icons\\INV_Misc_Coin_02"

local ICON_SOLD = "Interface\\Icons\\INV_Misc_Coin_01"
local ICON_EXPIRED = "Interface\\Icons\\Spell_Holy_BorrowedTime"
local ICON_OUTBID = "Interface\\Icons\\Ability_Creature_Cursed_01"
local ICON_WON = "Interface\\Icons\\Achievement_Boss_Bazil_Akumai"

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local function OnSystemMessage(event, msg)
    if not msg then return end

    if BNC.SafeFind(msg, "A buyer has been found for your auction") then
        if GetSetting("showSold") == false then return end

        local itemName = BNC.SafeMatch(msg, "auction of (.+)") or "an item"

        BNC:Push({
            module = MODULE_ID,
            title = "Auction Sold!",
            message = itemName,
            icon = ICON_SOLD,
            priority = "high",
            duration = GetSetting("toastDuration") or 5,
            silent = GetSetting("soldToasts") == false,
        })
        return
    end

    if BNC.SafeFind(msg, "auction of .+ has expired") then
        if GetSetting("showExpired") == false then return end

        local itemName = BNC.SafeMatch(msg, "auction of (.+) has expired") or "an item"

        BNC:Push({
            module = MODULE_ID,
            title = "Auction Expired",
            message = itemName,
            icon = ICON_EXPIRED,
            priority = "low",
            duration = GetSetting("toastDuration") or 4,
            silent = GetSetting("expiredToasts") == false,
        })
        return
    end

    if BNC.SafeFind(msg, "You have been outbid") then
        if GetSetting("showOutbid") == false then return end

        local itemName = BNC.SafeMatch(msg, "outbid on (.+)") or "an item"

        BNC:Push({
            module = MODULE_ID,
            title = "Outbid!",
            message = itemName,
            icon = ICON_OUTBID,
            priority = "normal",
            duration = GetSetting("toastDuration") or 5,
            silent = GetSetting("outbidToasts") == false,
        })
        return
    end

    if BNC.SafeFind(msg, "You won an auction") then
        if GetSetting("showWon") == false then return end

        local itemName = BNC.SafeMatch(msg, "auction for (.+)") or "an item"

        BNC:Push({
            module = MODULE_ID,
            title = "Auction Won!",
            message = itemName,
            icon = ICON_WON,
            priority = "normal",
            duration = GetSetting("toastDuration") or 4,
            silent = GetSetting("wonToasts") == false,
        })
        return
    end
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
pcall(function() eventFrame:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED") end)
pcall(function() eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW") end)

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage(event, ...)
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { type = "event", key = "sold",    label = "Auction sold",    show = "showSold",    toast = "soldToasts" },
    { type = "event", key = "expired", label = "Auction expired", show = "showExpired", toast = "expiredToasts" },
    { type = "event", key = "outbid",  label = "Outbid",          show = "showOutbid",  toast = "outbidToasts" },
    { type = "event", key = "won",     label = "Auction won",     show = "showWon",     toast = "wonToasts" },
    { key = "toastDuration",    label = "Toast duration", type = "slider", default = 5, min = 1, max = 15, step = 1 },
})
