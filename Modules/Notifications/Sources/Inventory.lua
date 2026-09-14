-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Inventory: Bag space and equipment durability warnings with repair detection.
-- Events: PLAYER_ENTERING_WORLD, BAG_UPDATE, UPDATE_INVENTORY_DURABILITY, MERCHANT_SHOW
-- ==========================================================================

local MODULE_ID = "inventory"
local MODULE_NAME = "Inventory"
local MODULE_ICON = "Interface\\Icons\\INV_Misc_Bag_07"

local ICON_BAGS = "Interface\\Icons\\INV_Misc_Bag_07"
local ICON_DURABILITY = "Interface\\Icons\\Trade_BlackSmithing"
local ICON_REPAIR = "Interface\\Icons\\Ability_Repair"

local lastFreeSlots = nil
local lastDurabilityWarned = false
local DURABILITY_CHECK_INTERVAL = 30

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local function GetTotalFreeSlots()
    local free = 0
    local total = 0
    for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        local slots = C_Container.GetContainerNumSlots(bag)
        if slots and slots > 0 then
            total = total + slots
            local freeInBag = C_Container.GetContainerNumFreeSlots(bag)
            free = free + (freeInBag or 0)
        end
    end
    return free, total
end

local function GetLowestDurability()
    local lowest = 100
    -- Equipment slots 1-18 (head through ranged)
    for slot = 1, 18 do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 then
            local pct = (current / maximum) * 100
            if pct < lowest then
                lowest = pct
            end
        end
    end
    return math.floor(lowest)
end

-- Only fires when crossing below threshold, not on every bag change
local function CheckBagSpace()
    if GetSetting("showBagsFull") == false then return end

    local free = GetTotalFreeSlots()
    local threshold = GetSetting("bagThreshold") or 3

    if lastFreeSlots and lastFreeSlots > threshold and free <= threshold and free >= 0 then
        local message = free == 0 and "Your bags are full!" or (free .. " slots remaining")
        BNC:Push({
            module = MODULE_ID,
            title = "Bags Almost Full",
            message = message,
            icon = ICON_BAGS,
            priority = free == 0 and "high" or "normal",
            duration = GetSetting("bagDuration") or 5,
            silent = GetSetting("bagToasts") == false,
        })
    end

    lastFreeSlots = free
end

local function CheckDurability()
    if GetSetting("showDurability") == false then return end

    local lowest = GetLowestDurability()
    local threshold = GetSetting("durabilityThreshold") or 20

    if lowest <= threshold and not lastDurabilityWarned then
        lastDurabilityWarned = true
        BNC:Push({
            module = MODULE_ID,
            title = "Low Durability",
            message = "Lowest item at " .. lowest .. "%",
            icon = ICON_DURABILITY,
            priority = lowest <= 10 and "high" or "normal",
            duration = GetSetting("durabilityDuration") or 5,
            silent = GetSetting("durabilityToasts") == false,
        })
    elseif lowest > threshold then
        lastDurabilityWarned = false
    end
end

local function OnRepairAll()
    if GetSetting("showRepaired") == false then return end

    lastDurabilityWarned = false

    BNC:Push({
        module = MODULE_ID,
        title = "Equipment Repaired",
        message = "All items restored to full durability",
        icon = ICON_REPAIR,
        priority = "low",
        duration = GetSetting("repairedDuration") or 3,
        silent = GetSetting("repairedToasts") == false,
    })
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")

pcall(function() eventFrame:RegisterEvent("MERCHANT_SHOW") end)

local lastBagUpdate = 0

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, function()
            lastFreeSlots = GetTotalFreeSlots()
            CheckDurability()
        end)
    elseif event == "BAG_UPDATE" then
        -- Throttle rapid bag updates (e.g. mass loot)
        local now = GetTime()
        if now - lastBagUpdate > 0.5 then
            lastBagUpdate = now
            C_Timer.After(0.2, CheckBagSpace)
        end
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        CheckDurability()
    elseif event == "MERCHANT_SHOW" then
        -- Detect auto-repair by checking durability after a brief delay
        C_Timer.After(1, function()
            local lowest = GetLowestDurability()
            if lowest >= 99 and lastDurabilityWarned then
                OnRepairAll()
            end
        end)
    end
end)

C_Timer.NewTicker(DURABILITY_CHECK_INTERVAL, function()
    CheckDurability()
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { key = "showBagsFull",          label = "Show Bags Full Warning",       type = "toggle", default = true },
    { key = "showDurability",        label = "Show Low Durability",          type = "toggle", default = true },
    { key = "showRepaired",          label = "Show Equipment Repaired",      type = "toggle", default = true },
    { key = "bagThreshold",          label = "Bag Warning Threshold (slots)",type = "slider", default = 3, min = 1, max = 20, step = 1 },
    { key = "durabilityThreshold",   label = "Durability Warning (%)",       type = "slider", default = 20, min = 5, max = 50, step = 5 },
    { key = "bagToasts",             label = "Toast on Bags Warning",        type = "toggle", default = true },
    { key = "durabilityToasts",      label = "Toast on Durability Warning",  type = "toggle", default = true },
    { key = "repairedToasts",        label = "Toast on Repair",              type = "toggle", default = true },
    { key = "bagDuration",           label = "Bag Toast Duration",           type = "slider", default = 5, min = 1, max = 15, step = 1 },
    { key = "durabilityDuration",    label = "Durability Toast Duration",    type = "slider", default = 5, min = 1, max = 15, step = 1 },
    { key = "repairedDuration",      label = "Repair Toast Duration",        type = "slider", default = 3, min = 1, max = 15, step = 1 },
})
