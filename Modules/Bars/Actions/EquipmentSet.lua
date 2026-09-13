-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazBars EquipmentSet Action Handler
-- Equipment sets from the character equipment manager. Stored by setID
-- (stable across renames) and cast via "/equipset <name>" macro.

local BazBars = BazUI.Bars   -- module namespace (was the BazBars global)
local Actions = BazBars.Actions

---------------------------------------------------------------------------
-- Local helpers
---------------------------------------------------------------------------

local function GetSetName(setID)
    if not setID then return nil end
    local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
    return name
end

local function GetSetIcon(setID)
    if not setID then return nil end
    local _, icon = C_EquipmentSet.GetEquipmentSetInfo(setID)
    return icon
end

-- Legacy support: sets used to be stored by name. Resolve name > setID.
local function GetSetIDByName(name)
    if not name then return nil end
    local ids = C_EquipmentSet.GetEquipmentSetIDs()
    if not ids then return nil end
    for _, id in ipairs(ids) do
        local setName = C_EquipmentSet.GetEquipmentSetInfo(id)
        if setName == name then
            return id
        end
    end
end

---------------------------------------------------------------------------
-- Handler
---------------------------------------------------------------------------

local EquipmentSet = {
    type = "equipmentset",
    priority = 70,
}

---------------------------------------------------------------------------
-- Cursor
---------------------------------------------------------------------------

function EquipmentSet.fromCursor()
    local cType, setName, _, setID = GetCursorInfo()
    if cType ~= "equipmentset" then return end
    -- GetCursorInfo returns (type, name, ?, setID) for equipmentset - prefer
    -- the numeric ID, but fall back to resolving by name if needed.
    if type(setID) == "number" then
        return { id = setID }
    end
    if setName then
        local id = GetSetIDByName(setName)
        if id then return { id = id } end
    end
end

function EquipmentSet.pickup(data)
    if not data or not data.id then return end
    C_EquipmentSet.PickupEquipmentSet(data.id)
end

---------------------------------------------------------------------------
-- Button attributes
-- Cast via "/equipset <name>" macro. The name is looked up from setID at
-- apply time, so renaming the set doesn't break the button (though it
-- does require a /reload or re-apply after rename to pick up the new name).
---------------------------------------------------------------------------

function EquipmentSet.apply(button, data)
    local name = GetSetName(data.id)
    if not name then return end
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "/equipset " .. name)
end

---------------------------------------------------------------------------
-- Visuals
---------------------------------------------------------------------------

function EquipmentSet.getIcon(data)
    return GetSetIcon(data.id)
end

function EquipmentSet.getName(data)
    return GetSetName(data.id)
end

function EquipmentSet.showTooltip(data)
    local name = GetSetName(data.id)
    if name then
        GameTooltip:SetText(name, 1, 1, 1)
    end
end

---------------------------------------------------------------------------
-- Persistence
---------------------------------------------------------------------------

function EquipmentSet.serialize(data)
    return { id = data.id }
end

function EquipmentSet.deserialize(saved)
    if not saved or not saved.id then return nil end
    -- Don't reject missing sets; the user may have the set on another
    -- character. The button shows ? until the set is available.
    return { id = saved.id }
end

---------------------------------------------------------------------------
-- Legacy migration
-- Old format stored sets as { command="equipmentset", value=setName, id=setID }.
-- Prefer the stored id; fall back to resolving by name.
---------------------------------------------------------------------------

function EquipmentSet.migrate(legacy)
    if legacy.command ~= "equipmentset" then return nil end

    if type(legacy.id) == "number" then
        return { id = legacy.id }
    end
    if type(legacy.value) == "string" then
        local id = GetSetIDByName(legacy.value)
        if id then return { id = id } end
    end
end

---------------------------------------------------------------------------
-- Register
---------------------------------------------------------------------------

if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo then
    Actions:Register(EquipmentSet)
end
