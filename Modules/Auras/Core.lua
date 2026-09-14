-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Auras
--
-- Player buffs and debuffs drawn as rounded icons attached to the BazUI
-- player frame: buffs above the health bar on the left, debuffs above
-- the power bar on the right, eight per row, rows stacking upward for
-- as long as they need to.
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
        gap           = 8,      -- pixels between the top of the bars and the first row
        growth        = "portrait",  -- "portrait": first icon next to the portrait, later ones move
                                     --   outward. "edge": first icon at the outer end of the bar.

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
    },
    onReady = function(self) self:Initialize() end,
})

addon.MODULE_NAME = MODULE_NAME

function addon:ResetLayout()
    for _, key in ipairs({ "perRow", "iconSize", "spacing", "gap", "growth" }) do
        self:SetSetting(key, self.config.defaults[key])
    end
    self:ApplySettings()
end
