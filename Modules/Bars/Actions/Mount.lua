-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazBars Mount Action Handler
-- Mounts from the mount journal. The cursor type is "mount" (older WoW
-- versions used "companion" which we normalize). Secure casting uses a
-- "/cast <MountName>" macro because SecureActionButton doesn't have a
-- native mount type.

local BazBars = BazUI.Bars   -- module namespace (was the BazBars global)
local Actions = BazBars.Actions

local RANDOM_FAVORITE_MOUNT_ID = 268435455
local RANDOM_MOUNT_ICON = 413588  -- Interface\Icons\Mount_Random

-- Tracks the exact mountID the user is currently picking up, so that
-- swapping preserves skin/variant info that GetMountFromSpell() collapses.
-- Cleared when consumed or when the cursor stops matching.
local pickedUpMountID = nil

---------------------------------------------------------------------------
-- Local helpers
---------------------------------------------------------------------------

local function GetMountName(mountID)
    if not mountID then return nil end
    if mountID == RANDOM_FAVORITE_MOUNT_ID then
        return "Random Favorite Mount"
    end
    local name = C_MountJournal.GetMountInfoByID(mountID)
    return name
end

local function GetMountSpellID(mountID)
    if not mountID or mountID == RANDOM_FAVORITE_MOUNT_ID then return nil end
    local _, spellID = C_MountJournal.GetMountInfoByID(mountID)
    return spellID
end

---------------------------------------------------------------------------
-- Handler
---------------------------------------------------------------------------

local Mount = {
    type = "mount",
    priority = 30, -- before Spell (50) so spell-form mount cursors are caught here
}

---------------------------------------------------------------------------
-- Cursor
-- Mounts can appear on the cursor in two forms:
--   1. Native: GetCursorInfo() returns "mount" + mountID (from mount journal)
--   2. Spell: when we re-pick up a mount from a BazBar, we put the mount's
--      summon spell on the cursor (since there's no stable mount pickup API).
--      We detect this case via C_MountJournal.GetMountFromSpell() so the
--      mount can be swapped between BazBars without being "downgraded" to a
--      plain spell button.
---------------------------------------------------------------------------

function Mount.fromCursor()
    local cType, id1, id3, id2 = GetCursorInfo()

    -- Native mount cursor from mount journal drag:
    --   cType = "mount", id1 = mountID (matches C_MountJournal)
    if cType == "mount" and id1 then
        pickedUpMountID = nil
        return { id = id1 }
    end

    -- Companion cursor from PickupSpell on a mount summon spell:
    --   cType = "companion", id3 = "MOUNT", id1 is an internal index (NOT mountID)
    -- We rely on the cache to recover the correct mountID here.
    if cType == "companion" and id3 == "MOUNT" then
        if pickedUpMountID then
            local data = { id = pickedUpMountID }
            pickedUpMountID = nil
            return data
        end
        -- No cache - we can't reliably map id1 to a mountID, give up.
        return nil
    end

    -- Spell cursor: some spellbook-learned mount spells come through here.
    if cType == "spell" and id2 then
        if pickedUpMountID then
            local cachedSpellID = GetMountSpellID(pickedUpMountID)
            if cachedSpellID == id2 then
                local data = { id = pickedUpMountID }
                pickedUpMountID = nil
                return data
            end
        end
        if C_MountJournal.GetMountFromSpell then
            local mountID = C_MountJournal.GetMountFromSpell(id2)
            if mountID then
                pickedUpMountID = nil
                return { id = mountID }
            end
        end
    end

    -- Cursor is empty or has something unrelated - clear the cache
    if not cType then
        pickedUpMountID = nil
    end
end

function Mount.pickup(data)
    if not data or not data.id then return end
    -- Remember the exact mountID so fromCursor can recover it when the
    -- cursor is a "companion"-type cursor that doesn't expose the mountID.
    pickedUpMountID = data.id
    -- Put the mount's summon spell on the cursor so it can be placed on
    -- other bars (including Blizzard's default action bars).
    local spellID = GetMountSpellID(data.id)
    if spellID then
        C_Spell.PickupSpell(spellID)
    end
end

---------------------------------------------------------------------------
-- Button attributes
-- Secure casting via /cast macro (no native "mount" type in SecureActionButton).
---------------------------------------------------------------------------

function Mount.apply(button, data)
    if data.id == RANDOM_FAVORITE_MOUNT_ID then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", "/run C_MountJournal.SummonByID(0)")
        return
    end

    local name = GetMountName(data.id)
    if name then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", "/cast " .. name)
    end
end

---------------------------------------------------------------------------
-- Visuals
---------------------------------------------------------------------------

function Mount.getIcon(data)
    if data.id == RANDOM_FAVORITE_MOUNT_ID then
        return RANDOM_MOUNT_ICON
    end
    local _, _, icon = C_MountJournal.GetMountInfoByID(data.id)
    return icon
end

function Mount.getName(data)
    return GetMountName(data.id)
end

function Mount.showTooltip(data)
    if data.id == RANDOM_FAVORITE_MOUNT_ID then
        GameTooltip:SetText("Summon Random Favorite Mount", 1, 1, 1)
        return
    end
    local name = GetMountName(data.id)
    if name then
        GameTooltip:SetText(name, 1, 1, 1)
    end
end

---------------------------------------------------------------------------
-- Persistence
---------------------------------------------------------------------------

function Mount.serialize(data)
    return { id = data.id }
end

function Mount.deserialize(saved)
    if not saved or not saved.id then return nil end
    -- Random favorite sentinel is always valid
    if saved.id == RANDOM_FAVORITE_MOUNT_ID then return { id = saved.id } end
    -- Verify the mount still exists
    local name = C_MountJournal.GetMountInfoByID(saved.id)
    if not name then return nil end
    return { id = saved.id }
end

---------------------------------------------------------------------------
-- Legacy migration
-- Old format: { command = "mount", value = mountID }
---------------------------------------------------------------------------

function Mount.migrate(legacy)
    if legacy.command ~= "mount" and legacy.command ~= "companion" then return nil end
    local id = tonumber(legacy.value)
    if not id then return nil end
    return { id = id }
end

---------------------------------------------------------------------------
-- Register
---------------------------------------------------------------------------

-- Only clients with a mount journal can resolve mount IDs.
if C_MountJournal and C_MountJournal.GetMountInfoByID then
    Actions:Register(Mount)
end
