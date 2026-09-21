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
        buttons      = {},            -- [key] = false hides that button
        -- Where it sits, whether it floats, how it fades: all the
        -- drawer's, because the micro menu is a drawer widget. See
        -- Bar.lua and DESIGN-elements.md.
    },
    slash = { "/bazmicro" },
    -- The settings live on the drawer's widget page now, so this opens
    -- that rather than a module page with nothing on it.
    defaultHandler = function() BazUI:OpenOptionsPanel("Drawers") end,
    commands = {
        reset = {
            desc = "Where the micro menu lives now",
            handler = function()
                addon:Print("The micro menu is a drawer widget - where it "
                    .. "sits is set in |cffffd700/bazdrawers|r, or by dragging "
                    .. "it in Edit Mode.")
            end,
        },
        debug = {
            desc = "Print the bar's current state",
            handler = function() addon:PrintDebug() end,
        },
    },
    onReady = function(self) self:Initialize() end,
})

addon.MODULE_NAME = MODULE_NAME
