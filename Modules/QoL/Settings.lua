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
    other       = { label = "Other",       order = 9 },
}

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
            get     = function() return addon:Enabled(def.key) end,
            set     = function(_, value) addon:SetEnabled(def.key, value) end,
        }
    end

    entries[#entries + 1] = {
        key = "note", type = "note", section = "other", order = 99, style = "info",
        text = "Everything here starts off. These change how the game "
            .. "behaves rather than how it looks, and a switch you did not "
            .. "throw yourself is one you cannot find again when you want "
            .. "it back. Console settings are put back the way you had "
            .. "them when you turn a tweak off.",
    }

    return { sections = SECTIONS, entries = entries }
end

BazUI:QueueForModule("QoL", function()
    BazUI:RegisterSettingsSpec("QoL", BuildSpec())

    BazUI:RegisterOptionsTable("QoL", function()
        return { name = "Quality of Life", type = "group", args = {} }
    end)
    BazUI:AddToSettings("QoL", "Quality of Life")

    BazUI:RegisterOptionsTable("QoL-Settings", function()
        return BazUI:BuildOptionsTableFromSpec("QoL", { name = "Quality of Life" })
    end)
    BazUI:AddToSettings("QoL-Settings", "General Settings", "QoL")
end)
