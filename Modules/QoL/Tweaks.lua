-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Quality of Life: the tweaks
--
-- Each one registers itself and, if it needs to do something, listens for
-- what it needs. Handlers are registered once and ask whether they are
-- switched on when they fire, rather than being hooked and unhooked as
-- the switch moves: a handler that checks is a handler that cannot be
-- left hanging on after its tweak was turned off.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("QoL")
if not addon then return end

local function On(key) return addon:Enabled(key) end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------

addon:RegisterTweak({
    key     = "instantQuestText",
    label   = "Instant quest text",
    desc    = "Quest text appears at once instead of fading in a word at a time. The game has this setting too, under Interface, Controls; this is the same switch.",
    section = "quests",
    order   = 1,
    cvar    = "instantQuestText",
    on      = "1",
    off     = "0",
})

---------------------------------------------------------------------------
-- Vendors
---------------------------------------------------------------------------

addon:RegisterTweak({
    key     = "autoRepair",
    label   = "Repair automatically",
    desc    = "Repairs everything the moment you open a merchant that can. Guild funds are used first where they are available and you are allowed them, so it costs you nothing before it costs you money.",
    section = "vendors",
    order   = 1,
})

addon:RegisterTweak({
    key     = "sellJunk",
    label   = "Sell gray items",
    desc    = "Sells every poor quality item in your bags when you open a merchant. Only gray: nothing you might have meant to keep.",
    section = "vendors",
    order   = 2,
})

local function Repair()
    if not (CanMerchantRepair and CanMerchantRepair()) then return end
    local cost, canRepair = GetRepairAllCost()
    if not (canRepair and cost and cost > 0) then return end

    -- The guild's money first, where there is any to be had. The call
    -- takes the money silently if it cannot, so both conditions are
    -- asked rather than assumed.
    local guild = CanGuildBankRepair and CanGuildBankRepair()
        and GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() >= cost
    RepairAllItems(guild and true or false)
    addon:Print(("Repaired for %s%s."):format(BazUI:FormatMoney(cost),
        guild and ", from guild funds" or ""))
end

local function SellJunk()
    local container = C_Container
    if not (container and container.GetContainerNumSlots) then return end

    local sold = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, container.GetContainerNumSlots(bag) or 0 do
            local info = container.GetContainerItemInfo
                and container.GetContainerItemInfo(bag, slot)
            -- Poor quality and worth something: a gray with no vendor
            -- price is a quest leftover and selling it is not possible
            -- anyway.
            if info and info.quality == 0 and not info.hasNoValue then
                container.UseContainerItem(bag, slot)
                sold = sold + 1
            end
        end
    end
    if sold > 0 then
        addon:Print(("Sold %d gray item%s."):format(sold, sold == 1 and "" or "s"))
    end
end

---------------------------------------------------------------------------
-- Convenience
---------------------------------------------------------------------------

addon:RegisterTweak({
    key     = "levelScreenshot",
    label   = "Screenshot when you level",
    desc    = "Takes a screenshot each time you gain a level. They land in your Screenshots folder.",
    section = "convenience",
    order   = 1,
})

addon:RegisterTweak({
    key     = "declineDuels",
    label   = "Decline duels",
    desc    = "Turns down duel requests without showing you the popup. Nothing is said to whoever asked.",
    section = "convenience",
    order   = 2,
})

addon:RegisterTweak({
    key     = "farCamera",
    label   = "Zoom the camera out further",
    desc    = "Raises the furthest the camera will pull back to the most the game allows. The game resets this on its own sometimes, which is why it is worth having a switch for.",
    section = "convenience",
    order   = 3,
    cvar    = "cameraDistanceMaxZoomFactor",
    on      = "2.6",
    off     = "1.9",
})

---------------------------------------------------------------------------
-- Listening
---------------------------------------------------------------------------

addon:RegisterDependencies()

for _, name in ipairs({ "RepairAllItems", "CanMerchantRepair", "CancelDuel", "Screenshot" }) do
    BazUI:RegisterDependency({
        module = "Quality of Life",
        label  = name .. "()",
        why    = "A tweak calls it.",
        check  = function() return BazUI.Has.Global(name) end,
    })
end

BazUI:QueueForModule("QoL", function()
    addon:On("MERCHANT_SHOW", function()
        if On("autoRepair") then Repair() end
        if On("sellJunk") then SellJunk() end
    end)

    addon:On("PLAYER_LEVEL_UP", function()
        if On("levelScreenshot") and Screenshot then Screenshot() end
    end)

    addon:On("DUEL_REQUESTED", function()
        if On("declineDuels") and CancelDuel then
            CancelDuel()
            -- The popup is already up by the time this fires, so it is
            -- closed as well as answered.
            if _G.StaticPopup_Hide then _G.StaticPopup_Hide("DUEL_REQUESTED") end
        end
    end)
end)
