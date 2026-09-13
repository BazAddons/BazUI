-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazBars Macro Action Handler
-- Blizzard macros dragged from the macro UI. Stored by name (stable across
-- reorder/delete) and resolved to a live index/body at runtime. Custom
-- user-written macrotext is handled separately by Actions/MacroText.lua.

local BazBars = BazUI.Bars   -- module namespace (was the BazBars global)
local Actions = BazBars.Actions

---------------------------------------------------------------------------
-- Local helpers
---------------------------------------------------------------------------

-- Parses #showtooltip <SpellName> from the first line of a macro body.
-- Returns the resolved display name, or nil if no #showtooltip directive.
-- Strips leading conditionals like [spec:1] and picks the first of a
-- ;-separated list.
local function ParseShowtooltip(body)
    if not body then return nil end
    local line = body:match("^#showtooltip%s*(.-)\n") or body:match("^#showtooltip%s*(.-)$")
    if not line or line == "" then return nil end

    local name = line:match("%]%s*(.+)") or line
    name = name:match("^([^;]+)")
    if name then
        return name:match("^%s*(.-)%s*$")
    end
end

-- Look up a macro by name and return (index, iconID, body).
local function GetMacroByName(name)
    if not name then return nil end
    for i = 1, (MAX_ACCOUNT_MACROS or 120) + (MAX_CHARACTER_MACROS or 18) do
        local macroName, iconID, body = GetMacroInfo(i)
        if macroName == name then
            return i, iconID, body
        end
    end
end

---------------------------------------------------------------------------
-- Handler
---------------------------------------------------------------------------

local Macro = {
    type = "macro",
    priority = 70,
}

---------------------------------------------------------------------------
-- Cursor
---------------------------------------------------------------------------

function Macro.fromCursor()
    local cType, macroIndex = GetCursorInfo()
    if cType ~= "macro" or not macroIndex then return end
    local name = GetMacroInfo(macroIndex)
    if not name then return end
    return { name = name }
end

function Macro.pickup(data)
    if not data or not data.name then return end
    local index = GetMacroByName(data.name)
    if index then
        PickupMacro(index)
    end
end

---------------------------------------------------------------------------
-- Button attributes
-- Cast by macro name so subsequent edits to the macro body take effect
-- automatically.
---------------------------------------------------------------------------

function Macro.apply(button, data)
    button:SetAttribute("type", "macro")
    button:SetAttribute("macro", data.name)
end

---------------------------------------------------------------------------
-- Visuals
---------------------------------------------------------------------------

function Macro.getIcon(data)
    local _, iconID, body = GetMacroByName(data.name)

    -- Prefer the spell/item referenced by #showtooltip, if any.
    if body then
        local showName = ParseShowtooltip(body)
        if showName then
            local tex = C_Spell.GetSpellTexture(showName)
            if tex then return tex end
            local itemID = C_Item.GetItemIDForItemInfo(showName)
            if itemID then
                local itemTex = C_Item.GetItemIconByID(itemID)
                if itemTex then return itemTex end
            end
        end
    end

    return iconID
end

function Macro.getName(data)
    return data.name
end

function Macro.showTooltip(data)
    local _, _, body = GetMacroByName(data.name)

    if body then
        local showName = ParseShowtooltip(body)
        if showName then
            local spellInfo = C_Spell.GetSpellInfo(showName)
            if spellInfo and spellInfo.spellID then
                GameTooltip:SetSpellByID(spellInfo.spellID)
                return
            end
            local itemID = C_Item.GetItemIDForItemInfo(showName)
            if itemID then
                GameTooltip:SetItemByID(itemID)
                return
            end
        end
    end

    GameTooltip:SetText(data.name, 1, 1, 1)
end

---------------------------------------------------------------------------
-- Persistence
---------------------------------------------------------------------------

function Macro.serialize(data)
    return { name = data.name }
end

function Macro.deserialize(saved)
    if not saved or not saved.name then return nil end
    -- Don't reject missing macros - the user may have the macro on another
    -- character and the button should still exist (showing ? until the
    -- macro is available).
    return { name = saved.name }
end

---------------------------------------------------------------------------
-- Legacy migration
-- Old format stored macros as { command="macro", value=macroName,
-- macrotext=cachedBody }. For Blizzard macros we only need the name; the
-- body is fetched live from GetMacroInfo. Older versions stored the macro
-- by index (number); handle that case too by converting to name.
---------------------------------------------------------------------------

function Macro.migrate(legacy)
    if legacy.command ~= "macro" then return nil end

    local name = legacy.value
    if type(name) == "number" then
        name = GetMacroInfo(name) -- legacy index > name
    end
    if type(name) ~= "string" or name == "" then return nil end

    return { name = name }
end

---------------------------------------------------------------------------
-- Register
---------------------------------------------------------------------------

Actions:Register(Macro)
