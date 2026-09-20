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
-- The rows are built here rather than by Blizzard's secure aura header,
-- which does not exist on every client. Each row creates its own icon
-- buttons, sorts them, lays them out and stamps the aura each one shows
-- on it; the buttons are real secure action buttons, so right-clicking
-- still cancels a buff. See Frames.lua for what that costs in combat.
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
        -- Square or round. Round is a mask over the same box, so the
        -- footprint, the spacing and a filling row's arithmetic are the
        -- same either way.
        iconShape     = "square",
        -- The rows you have made. Each carries what it shows and of
        -- whom, where it sits, and how many icons it fits across.
        -- Seeded with four on a new profile.
        rows          = {},

        -- Icons
        showDuration  = true,
        showCount     = true,
        showWeapons   = true,   -- weapon enchants (poisons, sharpening stones) among the buffs
        debuffBorders = true,   -- color debuff rims by dispel type (Magic, Curse, Disease, Poison)

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
            handler = function() addon:SetPreviewWanted() end,
        },
    },
    onReady = function(self) self:Initialize() end,
})

addon.MODULE_NAME = MODULE_NAME

function addon:ResetLayout()
    for _, key in ipairs({ "perRow", "iconSize", "spacing" }) do
        self:SetSetting(key, self.config.defaults[key])
    end
    -- Rows go back to the four you started with, floating where they
    -- began, which is the half of "layout" a reset is reaching for.
    --
    -- Taken down one at a time rather than by emptying the list. The
    -- list is what says which rows exist; the frames and headers built
    -- from it are elsewhere, and dropping the list without taking those
    -- down leaves them on screen with nothing to delete them by.
    local ids = {}
    for _, def in ipairs(self:Rows()) do ids[#ids + 1] = def.id end
    for _, id in ipairs(ids) do self:RemoveRow(id) end

    self:SetSetting("rows", {})
    self:SeedRows()
    self:ApplySettings()
end
