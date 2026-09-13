-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazBars MacroText Action Handler
-- Custom user-written macrotext created via the in-addon macrotext editor.
-- Unlike all other handlers, MacroText actions don't come from a WoW cursor
-- drag - they're placed directly by the editor. Because there's no natural
-- way to represent custom macrotext on the WoW cursor, these buttons can't
-- currently be shift-dragged between BazBars; you edit a button's macrotext
-- in place with the editor.

local BazBars = BazUI.Bars   -- module namespace (was the BazBars global)
local Actions = BazBars.Actions

---------------------------------------------------------------------------
-- Local helpers
---------------------------------------------------------------------------

-- Parses "#showtooltip <SpellName>" from the first line of a macrotext body.
-- Returns the resolved display name, or nil if no directive is present.
-- Strips leading conditionals like [spec:1] and picks the first of a
-- semicolon-separated list.
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

---------------------------------------------------------------------------
-- Handler
---------------------------------------------------------------------------

local MacroText = {
    type = "macrotext",
    priority = 20, -- highest priority, but nothing ever matches it from cursor
}

---------------------------------------------------------------------------
-- Cursor - not applicable
-- Custom macrotext never exists on the WoW cursor, so fromCursor is a no-op
-- and pickup does nothing. Swap support would require an internal state
-- system and is deferred.
---------------------------------------------------------------------------

function MacroText.fromCursor()
    return nil
end

function MacroText.pickup(data)
    -- No-op. Shift-drag from a MacroText button just clears it.
end

---------------------------------------------------------------------------
-- Button attributes
---------------------------------------------------------------------------

function MacroText.apply(button, data)
    if not data or not data.body or data.body == "" then return end
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", data.body)
end

---------------------------------------------------------------------------
-- Visuals
-- Icon and tooltip come from #showtooltip if present, otherwise a generic
-- "macro" question-mark icon.
---------------------------------------------------------------------------

local GENERIC_MACRO_ICON = 136376 -- Interface\Icons\INV_Misc_QuestionMark

function MacroText.getIcon(data)
    if not data or not data.body then return GENERIC_MACRO_ICON end

    local showName = ParseShowtooltip(data.body)
    if showName then
        local tex = C_Spell.GetSpellTexture(showName)
        if tex then return tex end
        local itemID = C_Item.GetItemIDForItemInfo(showName)
        if itemID then
            local itemTex = C_Item.GetItemIconByID(itemID)
            if itemTex then return itemTex end
        end
    end

    return GENERIC_MACRO_ICON
end

function MacroText.getName(data)
    if not data or not data.body then return "Macro" end
    local showName = ParseShowtooltip(data.body)
    return showName or "Macro"
end

function MacroText.showTooltip(data)
    if not data or not data.body then
        GameTooltip:SetText("Macro", 1, 1, 1)
        return
    end

    local showName = ParseShowtooltip(data.body)
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
        GameTooltip:SetText(showName, 1, 1, 1)
        return
    end

    -- No #showtooltip - show the first line of the macrotext as a hint
    local firstLine = data.body:match("^([^\n]+)")
    GameTooltip:SetText(firstLine or "Macro", 1, 1, 1)
end

---------------------------------------------------------------------------
-- Persistence
---------------------------------------------------------------------------

function MacroText.serialize(data)
    return { body = data.body }
end

function MacroText.deserialize(saved)
    if not saved or not saved.body or saved.body == "" then return nil end
    return { body = saved.body }
end

---------------------------------------------------------------------------
-- Legacy migration
-- Legacy buttons could have macrotext set as an override on top of any
-- command type (spell/item/etc). We only claim entries where the macrotext
-- is "custom" - i.e., it doesn't match the native body of the underlying
-- Blizzard macro. For legacy entries where command="macro" AND macrotext
-- matches the Blizzard macro body, the Macro handler claims it (Macro
-- priority 70 > MacroText priority 20, so Macro runs first).
--
-- Since Macro already claimed macro-type legacy entries, this migrate
-- function only runs for entries Macro rejected. That effectively means:
-- legacy buttons with macrotext override that we'd otherwise lose. We
-- preserve them as pure macrotext (losing the native type fallback).
---------------------------------------------------------------------------

function MacroText.migrate(legacy)
    if not legacy.macrotext or legacy.macrotext == "" then return nil end
    return { body = legacy.macrotext }
end

---------------------------------------------------------------------------
-- Public helper for the editor
-- The macrotext editor calls this to place or update a MacroText action
-- on a button. If the button had any other action type, it's replaced.
---------------------------------------------------------------------------

function BazBars.Actions:SetMacroText(button, body)
    local a = BazUI:GetModule("Bars")
    if not a or not a.Button then return end

    if not body or body == "" then
        a.Button:ClearAction(button)
        return
    end

    a.Button:SetActionFromHandler(button, MacroText, { body = body })
end

---------------------------------------------------------------------------
-- Register
---------------------------------------------------------------------------

Actions:Register(MacroText)
