-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazBars Item Action Handler
-- Handles bag items.

local BazBars = BazUI.Bars   -- module namespace (was the BazBars global)
local Actions = BazBars.Actions

---------------------------------------------------------------------------
-- Local helpers
---------------------------------------------------------------------------

local function GetItemName(itemID)
    local info = C_Item.GetItemInfo(itemID)
    return info and info.itemName or nil
end

-- SecureActionButton accepts the item by name OR "item:<id>". Prefer name
-- when available (works immediately) and fall back to the item: syntax for
-- items whose info isn't cached yet.
local function GetItemAttribute(itemID)
    return GetItemName(itemID) or ("item:" .. itemID)
end

---------------------------------------------------------------------------
-- Handler
---------------------------------------------------------------------------

local Item = {
    type = "item",
    priority = 80,
}

---------------------------------------------------------------------------
-- Cursor
---------------------------------------------------------------------------

function Item.fromCursor()
    local cType, itemID = GetCursorInfo()
    if cType ~= "item" or not itemID then return end
    -- Skip toys - they have cursor type "item" but must be cast by name.
    -- Leave them for the Toy handler (when registered) or the legacy path.
    if PlayerHasToy and PlayerHasToy(itemID) then return end
    return { id = itemID }
end

function Item.pickup(data)
    if data and data.id then
        C_Item.PickupItem(data.id)
    end
end

---------------------------------------------------------------------------
-- Button attributes
---------------------------------------------------------------------------

function Item.apply(button, data)
    button:SetAttribute("type", "item")
    button:SetAttribute("item", GetItemAttribute(data.id))
end

function Item.applySelfCast(button, data)
    button:SetAttribute("type2", "item")
    button:SetAttribute("item2", GetItemAttribute(data.id))
    button:SetAttribute("unit2", "player")
end

---------------------------------------------------------------------------
-- Visuals
---------------------------------------------------------------------------

function Item.getIcon(data)
    return C_Item.GetItemIconByID(data.id)
end

function Item.getName(data)
    return GetItemName(data.id)
end

function Item.getCount(data)
    local count = C_Item.GetItemCount(data.id, false, true) or 0
    if count <= 1 then return "" end
    if count > 999 then return "*" end
    return tostring(count)
end

-- Whether the player still has one of these.
--
-- Answered here rather than by the button, because "have you got one" is
-- an item question and it has a catch: a trinket you are wearing is in no
-- bag at all and is still very much yours. Counting charges as well, so a
-- wand with three left reads as held rather than as a single object.
--
-- The bank is deliberately not counted. Something put away is not
-- something you can click, and a slot that sits there unusable until you
-- next visit a bank is worse than one you refill by dragging.
function Item.isHeld(data)
    local count = C_Item.GetItemCount(data.id, false, true) or 0
    if count > 0 then return true end
    if C_Item.IsEquippedItem and C_Item.IsEquippedItem(data.id) then return true end
    return false
end

-- Item cooldowns moved namespaces over the years: C_Item on Retail,
-- C_Container on Classic, a bare global before that.
local GetItemCooldownCompat = (C_Item and C_Item.GetItemCooldown)
    or (C_Container and C_Container.GetItemCooldown)
    or GetItemCooldown

function Item.getCooldown(data)
    if not GetItemCooldownCompat then return end
    local start, duration, enable = GetItemCooldownCompat(data.id)
    if not start then return end
    return start, duration, enable
end

function Item.isUsable(data)
    -- Always render items at full color when they're on a bar.
    -- C_Item.IsUsableItem returns false for trade goods (herbs, ore,
    -- raw fish, feathers, etc.) because they're not click-to-activate
    -- items - that drove the icon-dim tint in UpdateUsable, making
    -- those slots look broken when really they're just being used to
    -- track inventory count. Range / cooldown / stack-count visuals
    -- already give the right feedback for items that actually have
    -- a usable state (potions, scrolls, on-use trinkets); the
    -- IsUsableItem dimming added nothing on top of that.
    return true, false
end

function Item.isInRange(data, unit)
    if not unit or not UnitExists(unit) then return nil end
    -- C_Item.IsItemInRange is protected in combat for non-enemy units
    -- (10.2.0 hotfix 2023-11-16; enemies re-permitted 2023-12-11).
    -- Calling it on a friendly target mid-combat raises
    -- ADDON_ACTION_BLOCKED, which pcall cannot catch. Return nil
    -- ("unknown") like the no-target case so the button keeps its
    -- usability color. Same guard LibRangeCheck-3.0 uses.
    if InCombatLockdown() and not UnitCanAttack("player", unit) then return nil end
    return C_Item.IsItemInRange(data.id, unit)
end

function Item.showTooltip(data)
    GameTooltip:SetItemByID(data.id)
end

---------------------------------------------------------------------------
-- Persistence
---------------------------------------------------------------------------

function Item.serialize(data)
    return { id = data.id }
end

function Item.deserialize(saved)
    if not saved or not saved.id then return nil end
    -- Items can be unknown when the user hasn't loaded them yet (not in
    -- bags, not encountered). We DON'T reject here - the cache will fill
    -- in eventually and the button will just show ? until it does.
    return { id = saved.id }
end

---------------------------------------------------------------------------
-- Legacy migration
-- Old format: { command = "item", value = itemID }
-- Note: legacy code also stored toys as "item" + id. The Toy handler's
-- migrate runs first (lower priority = checked first in Registry order),
-- so if the legacy row was actually a toy it gets claimed there.
---------------------------------------------------------------------------

function Item.migrate(legacy)
    if legacy.command ~= "item" then return nil end
    local id = tonumber(legacy.value)
    if not id then return nil end
    return { id = id }
end

---------------------------------------------------------------------------
-- Register
---------------------------------------------------------------------------

Actions:Register(Item)
