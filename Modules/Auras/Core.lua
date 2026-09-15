-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Auras
--
-- Buffs and debuffs drawn as rounded icons in four rows: the player's
-- buffs and debuffs, and the target's. Each row floats where you put it
-- or docks to a bar or an action bar the same way a unit bar does, with
-- its own edge, alignment and gap. Eight per row, as many rows as there
-- are auras.
--
-- Blizzard's secure aura header (SecureAuraHeaderTemplate) creates the
-- icon buttons, sorts them, lays them out and owns the right-click
-- cancel, so all of that keeps working in combat. This module only
-- reads the attributes the header stamps on each button and paints the
-- icon, count, duration and rim.
---------------------------------------------------------------------------

local MODULE_NAME = "Auras"
local Auras = BazUI.Auras or {}
BazUI.Auras = Auras

local addon
addon = BazUI:RegisterModule(MODULE_NAME, {
    title    = "Auras",
    icon     = "Interface\\Icons\\Spell_Holy_WordFortitude",
    profiles = true,
    defaults = {
        enabled       = true,
        hideBlizzard  = true,   -- park Blizzard's BuffFrame and DebuffFrame while ours are shown

        -- Layout
        perRow        = 8,
        iconSize      = 26,
        spacing       = 3,
        -- Where each of the four rows sits: floating or docked, on
        -- which edge, aligned left, centre or right, and how far from
        -- what it is docked to. Written on first use, per group.
        groups        = {},

        -- Target
        targetEnabled = true,   -- the target's auras under the BazUI target frame
        targetOnlyMine = false, -- only debuffs the player applied

        -- Icons
        showDuration  = true,
        showCount     = true,
        showWeapons   = true,   -- weapon enchants (poisons, sharpening stones) among the buffs
        debuffBorders = true,   -- colour debuff rims by dispel type (Magic, Curse, Disease, Poison)

        -- Sorting (the header's own sort: INDEX = order applied, TIME, NAME)
        sortMethod    = "INDEX",
        sortDirection = "+",
    },
    slash = { "/bazauras" },
    defaultHandler = function() BazUI:OpenOptionsPanel(MODULE_NAME) end,
    commands = {
        reset = {
            desc = "Reset the aura layout to its defaults",
            handler = function() addon:ResetLayout() end,
        },
        preview = {
            desc = "Show or hide a preview with a full spread of auras",
            handler = function() addon:SetPreview() end,
        },
    },
    onReady = function(self) self:Initialize() end,
})

addon.MODULE_NAME = MODULE_NAME

function addon:ResetLayout()
    for _, key in ipairs({ "perRow", "iconSize", "spacing" }) do
        self:SetSetting(key, self.config.defaults[key])
    end
    -- Where the rows sit goes back to floating at their starting places,
    -- which is the half of "layout" a reset is usually reaching for.
    self:SetSetting("groups", {})
    self:ApplySettings()
end
