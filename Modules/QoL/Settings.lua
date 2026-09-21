-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Quality of Life: the module's page
--
-- Built from the list of tweaks rather than written out. A tweak that
-- registers itself appears here; one that does not, does not. There is
-- nothing to keep in step.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("QoL")

local SECTIONS = {
    quests      = { label = "Quests",      order = 1 },
    vendors     = { label = "Vendors",     order = 2 },
    convenience = { label = "Convenience", order = 3 },
    windows     = { label = "Draggable windows", order = 4 },
    addons      = { label = "Other addons' settings", order = 5 },
    other       = { label = "Other",       order = 9 },
}

-- The draggable window switches, which the two controls at the top of
-- that page act on together. Read off the tweak list rather than a
-- second list kept beside it, so a window added to Windows.lua is a
-- window "all of them" already means.
local function WindowTweaks()
    local out = {}
    for _, def in ipairs(addon.tweaks or {}) do
        if def.section == "windows" then out[#out + 1] = def end
    end
    return out
end

local function BuildSpec()
    local entries = {}
    for _, def in ipairs(addon.tweaks or {}) do
        entries[#entries + 1] = {
            key     = def.key,
            label   = def.label or def.key,
            desc    = def.desc,
            type    = "toggle",
            section = SECTIONS[def.section] and def.section or "other",
            order   = def.order or 100,
            -- A tweak that is only a console setting needs that setting to
            -- exist. instantQuestText is gone from retail, so the switch
            -- grays out there rather than sitting on and doing nothing -
            -- which is the worse of the two, because it reads as working.
            disabled = def.cvar and function()
                return not (GetCVar and GetCVar(def.cvar) ~= nil)
            end or nil,
            get     = function() return addon:Enabled(def.key) end,
            set     = function(_, value) addon:SetEnabled(def.key, value) end,
        }
    end

    entries[#entries + 1] = {
        key = "windowsNote", type = "note", section = "windows", order = 0.5,
        style = "info",
        text = "The game places these itself and puts them back every time "
            .. "they open. With one of these on, the window stays where "
            .. "you drag it instead. They all start on: until you drag "
            .. "something nothing is any different. Everything else about "
            .. "the window is the game's. Reset window positions, above, "
            .. "forgets every position at once and leaves the switches "
            .. "alone.",
    }

    -- Both of these act on the page rather than on a row of it, which is
    -- why they are pinned: they sit above the list and stay there while
    -- it scrolls, instead of being the thing you scroll past twenty
    -- switches to reach.
    entries[#entries + 1] = {
        key = "allWindows", label = "All windows draggable",
        type = "toggle", section = "windows", order = 0.1, pinned = true,
        get = function()
            local any = false
            for _, def in ipairs(WindowTweaks()) do
                any = true
                if not addon:Enabled(def.key) then return false end
            end
            return any
        end,
        set = function(_, value)
            for _, def in ipairs(WindowTweaks()) do
                addon:SetEnabled(def.key, value)
            end
        end,
    }

    entries[#entries + 1] = {
        key = "resetWindows", label = "Reset window positions",
        type = "execute", section = "windows", order = 0.2, pinned = true,
        alignRight = true,
        func = function() addon:ClearWindowPositions() end,
    }

    ---------------------------------------------------------------------
    -- Carrying somebody else's settings
    --
    -- One switch per addon we know the recipe for and the player has
    -- installed. See Core/Persist.lua: this is the same call the slash
    -- command makes, which stays for anything not on the list.
    ---------------------------------------------------------------------
    local P = BazUI.Persist
    if P then
        entries[#entries + 1] = {
            key = "addonsNote", type = "note", section = "addons",
            order = 0.5, style = "info",
            text = "This client writes every addon's settings at logout and "
                .. "never reads one back, which is why so much of your "
                .. "interface forgets itself. BazUI keeps its own somewhere "
                .. "that does come back, and can carry these too.",
        }

        for index, addOnName in ipairs(P:Known()) do
            entries[#entries + 1] = {
                key     = "persist_" .. addOnName,
                label   = addOnName,
                type    = "toggle",
                section = "addons",
                order   = index,
                desc    = "Keep " .. addOnName .. "'s settings through a reload and a logout.",
                -- Greyed rather than missing when it cannot be done, so
                -- the answer to "why not this one" is on the page.
                disabled = function()
                    return not P:CanHelp(addOnName) or P:ClientReadsVariables()
                end,
                disabledLabel = "loads before BazUI",
                get = function() return P:IsGuest(addOnName) end,
                set = function(_, value)
                    if value then P:AddGuest(addOnName) else P:RemoveGuest(addOnName) end
                end,
            }
        end

        entries[#entries + 1] = {
            key = "addonsHow", type = "note", section = "addons",
            order = 90, style = "tip",
            text = "A greyed switch is an addon that loads before BazUI. Its "
                .. "settings are already read by the time we could put them "
                .. "back, so there is nothing to be done for it. For an addon "
                .. "not listed here, |cffffd700/baz persist add <AddOn> "
                .. "<Globals>|r - the globals are on the ## SavedVariables "
                .. "line of its own .toc file.",
        }
    end

    entries[#entries + 1] = {
        key = "note", type = "note", section = "other", order = 99, style = "info",
        text = "Everything on this page starts off. These change how the "
            .. "game behaves rather than how it looks, and a switch you "
            .. "did not throw yourself is one you cannot find again when "
            .. "you want it back. Console settings are put back the way "
            .. "you had them when you turn a tweak off. The draggable "
            .. "windows have a page of their own.",
    }

    return { sections = SECTIONS, entries = entries }
end

BazUI:QueueForModule("QoL", function()
    BazUI:RegisterSettingsSpec("QoL", BuildSpec())

    BazUI:RegisterOptionsTable("QoL", function()
        return { name = "Quality of Life", type = "group", args = {} }
    end)
    BazUI:AddToSettings("QoL", "Quality of Life")

    -- Two pages out of one spec. The draggable windows are a list of
    -- twenty-odd switches that all do the same thing to different
    -- windows, which reads as a page of its own and crowds everything
    -- else when it is a section among four.
    BazUI:RegisterOptionsTable("QoL-Settings", function()
        return BazUI:BuildOptionsTableFromSpec("QoL", {
            name = "Quality of Life",
            skip = { windows = true },
        })
    end)
    BazUI:AddToSettings("QoL-Settings", "General Settings", "QoL")

    BazUI:RegisterOptionsTable("QoL-Windows", function()
        return BazUI:BuildOptionsTableFromSpec("QoL", {
            name    = "Draggable Windows",
            only    = { windows = true },
            -- The tab already says what these are.
            headers = false,
        })
    end)
    BazUI:AddToSettings("QoL-Windows", "Draggable Windows", "QoL")
end)
