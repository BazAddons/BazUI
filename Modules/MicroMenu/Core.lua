-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Micro Menu
--
-- Blizzard's micro buttons (Character, Spellbook, Talents, Quest Log,
-- Social, Guild, World Map, Game Menu, Help) adopted into a movable
-- BazUI bar and drawn as ring-framed round icons. The buttons stay
-- Blizzard's own, so tooltips, the talent flash, pushed states and the
-- level gates keep working; this module only reparents, skins and lays
-- them out.
---------------------------------------------------------------------------

local MODULE_NAME = "MicroMenu"

local addon
addon = BazUI:RegisterModule(MODULE_NAME, {
    title    = "Micro Menu",
    icon     = "Interface\\Icons\\INV_Misc_Gear_01",
    profiles = true,
    defaults = {
        enabled      = true,
        hideBlizzard = true,          -- park Blizzard's micro menu container
        orientation  = "horizontal",  -- or "vertical"
        buttonSize   = 30,
        spacing      = 6,
        position     = nil,           -- { x, y } from BazUI Edit Mode; nil = bottom right
        buttons      = {},            -- [key] = false hides that button
        mouseoverFade = false,        -- fade the bar out until the cursor is over it
        fadeAlpha    = 0,             -- opacity (percent) while faded; 0 = hidden
    },
    slash = { "/bazmicro" },
    defaultHandler = function() BazUI:OpenOptionsPanel(MODULE_NAME) end,
    commands = {
        reset = {
            desc = "Move the micro menu back to the bottom right",
            handler = function() addon:ResetPosition() end,
        },
    },
    onReady = function(self) self:Initialize() end,
})

addon.MODULE_NAME = MODULE_NAME
