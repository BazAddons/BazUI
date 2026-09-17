-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Loot: Item loot, gold gains, and loot alert suppression.
-- Events: PLAYER_ENTERING_WORLD, PLAYER_MONEY, CHAT_MSG_LOOT,
--         LOOT_OPENED
-- ==========================================================================

local MODULE_ID = "loot"
local MODULE_NAME = "Loot"
local MODULE_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 },  -- Poor (gray)
    [1] = { 1.00, 1.00, 1.00 },  -- Common (white)
    [2] = { 0.12, 1.00, 0.00 },  -- Uncommon (green)
    [3] = { 0.00, 0.44, 0.87 },  -- Rare (blue)
    [4] = { 0.64, 0.21, 0.93 },  -- Epic (purple)
    [5] = { 1.00, 0.50, 0.00 },  -- Legendary (orange)
    [6] = { 0.90, 0.80, 0.50 },  -- Artifact (gold)
    [7] = { 0.00, 0.80, 1.00 },  -- Heirloom (light blue)
}

local SUPPRESSED_FRAMES = {
}

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local function GetMinQuality()
    return GetSetting("minQuality") or 1
end


local lastMoney = 0

local function OnPlayerMoney()
    if GetSetting("showGold") == false then return end

    local current = GetMoney()
    local diff = current - lastMoney
    lastMoney = current

    if diff > 0 then
        BNC:Push({
            event = "gold",
            module = MODULE_ID,
            -- "Coin" rather than "Gold": most of these are silver and
            -- copper, and a card headed Gold that says 2c reads as a
            -- mistake.
            title = "Coin Received",
            message = BazUI:FormatMoney(diff),
            -- The amount is the whole point of this one, so it is drawn
            -- to be read first rather than last.
            emphasis = true,
            icon = "Interface\\Icons\\INV_Misc_Coin_01",
            priority = "low",
            duration = GetSetting("toastDuration") or 3,
            silent = GetSetting("goldToasts") == false,
        })
    end
end

local function OnLootReceived(event, msg, playerName, languageName, channelName, targetName, ...)
    if GetSetting("showItems") == false then return end

    -- Only show our own loot (other players' loot uses "Playername receives loot")
    if not BNC.SafeFind(msg, "^You ") then return end

    local itemLink = BNC.SafeMatch(msg, "(|c%x+|Hitem.-|h%[.-%]|h|r)")
    if not itemLink then
        itemLink = BNC.SafeMatch(msg, "(|Hitem.-|h%[.-%]|h)")
    end
    if not itemLink then return end

    local quantity = tonumber(BNC.SafeMatch(msg, "x(%d+)%s*$")) or tonumber(BNC.SafeMatch(msg, "x(%d+)")) or 1

    -- Look up item details. The previous code wrapped each GetItemInfo
    -- call in pcall + a table-build for the multi-return values, doing
    -- this up to 4 times in a fallback chain. AOE loot bursts (5-10
    -- items per kill) made this expensive enough to feel as a hitch.
    -- Direct multi-value returns avoid the per-event table allocations,
    -- and GetItemInfoInstant is non-blocking so it's safe as a fallback
    -- (it doesn't trigger server roundtrips like GetItemInfo can).
    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemLink)

    local instantClassID
    if not itemName then
        local instName, _, instQuality, _, instTexture, instClassID = C_Item.GetItemInfoInstant(itemLink)
        instantClassID = instClassID
        itemName    = instName or BNC.SafeMatch(itemLink, "%[(.-)%]") or "Unknown Item"
        itemQuality = instQuality or 0
        itemTexture = instTexture or "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    -- Skip quest items if BNC-Quests is handling them. Reuse the
    -- classID we already fetched above when possible to avoid a
    -- second GetItemInfoInstant call.
    if GetSetting("hideQuestItems") ~= false and BNC:IsModuleEnabled("quests") then
        local classID = instantClassID
        if classID == nil then
            classID = select(6, C_Item.GetItemInfoInstant(itemLink))
        end
        if classID == 12 then return end  -- Enum.ItemClass.Questitem = 12
    end

    if itemQuality < GetMinQuality() then return end

    local qualityColor = QUALITY_COLORS[itemQuality] or QUALITY_COLORS[1]
    local colorHex = string.format("|cff%02x%02x%02x",
        qualityColor[1] * 255,
        qualityColor[2] * 255,
        qualityColor[3] * 255
    )

    local title = colorHex .. itemName .. "|r"
    local message = ""
    if quantity > 1 then
        message = "x" .. quantity
    end

    local priority = "low"
    if itemQuality >= 4 then
        priority = "high"
    elseif itemQuality >= 3 then
        priority = "normal"
    end

    BNC:Push({
        event = "items",
        module = MODULE_ID,
        title = title,
        message = message,
        icon = itemTexture,
        priority = priority,
        duration = GetSetting("toastDuration") or 4,
        silent = GetSetting("itemToasts") == false,
        itemLink = itemLink,
    })
end

local function SetupAutoLoot()
    if GetSetting("autoLoot") == false then return end
    SetCVar("autoLootDefault", "1")
end

local function OnLootOpened()
    if GetSetting("hideLootFrame") == false then return end
    if LootFrame and LootFrame:IsShown() then
        -- The loot window is a UI panel. Hiding it directly leaves the
        -- panel manager believing its slot is still occupied, and the
        -- next Escape press goes to "closing" that ghost panel instead
        -- of clearing the target. HideUIPanel releases the slot.
        if HideUIPanel and not InCombatLockdown() then
            HideUIPanel(LootFrame)
        else
            -- HideUIPanel refuses in combat; a plain Hide still works and
            -- the next CloseAllWindows releases the slot.
            LootFrame:Hide()
        end
    end
end

-- Suppress default loot toast/alert banners
local lootAlertsHooked = false

local function SetupLootAlertSuppression()
    if GetSetting("hideLootAlerts") == false then return end
    if lootAlertsHooked then return end
    lootAlertsHooked = true

    local systemNames = {
        "LootAlertSystem",
        "LootUpgradeAlertSystem",
        "MoneyWonAlertSystem",
        "HonorAwardedAlertSystem",
        "LegendaryItemAlertSystem",
        "GarrisonFollowerAlertSystem",
    }

    for _, name in ipairs(systemNames) do
        local system = _G[name]
        if system then
            BNC:HookAlertSystem(system, function() return GetSetting("hideLootAlerts") ~= false end)
        end
    end

    -- Catch-all: modern alert frames are pooled and anonymous (no GetName),
    -- so hide any frame that comes through AlertFrame when suppression is on
    if AlertFrame and AlertFrame.AddAlertFrame then
        hooksecurefunc(AlertFrame, "AddAlertFrame", function(self, frame)
            if GetSetting("hideLootAlerts") ~= false and type(frame) == "table" and frame.Hide then
                frame:Hide()
            end
        end)
    end
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_MONEY")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:RegisterEvent("LOOT_OPENED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        lastMoney = GetMoney()
        SetupAutoLoot()
        SetupLootAlertSuppression()
    elseif event == "LOOT_OPENED" then
        OnLootOpened()
    elseif event == "PLAYER_MONEY" then
        OnPlayerMoney()
    elseif event == "CHAT_MSG_LOOT" then
        OnLootReceived(event, ...)
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { type = "event", key = "items", label = "Item loot",  show = "showItems", toast = "itemToasts", blizzard = "hideLootAlerts" },
    { type = "event", key = "gold",  label = "Coin gains", show = "showGold",  toast = "goldToasts" },
    { key = "minQuality",     label = "Minimum item quality", desc = "Items below this quality are skipped.", type = "select", default = 0,
      values = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic" }, sorting = { 0, 1, 2, 3, 4 } },
    { key = "hideQuestItems", label = "Skip quest items", desc = "Quests already reports these.", type = "toggle", default = true },
    { key = "autoLoot",       label = "Auto-loot",        type = "toggle", default = true },
    { key = "toastDuration",    label = "Toast duration", type = "slider", default = 4, min = 1, max = 15, step = 1 },
    { key = "hideLootFrame",  label = "Hide the loot window",        type = "toggle", default = true, section = "blizzard" },
})

for _, frameName in ipairs(SUPPRESSED_FRAMES) do
    BNC:SuppressBlizzardFrame(frameName)
end
