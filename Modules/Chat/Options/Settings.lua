-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Settings page
--
-- Built from the unified SettingsSpec (Replica/SettingsSpec.lua) via
-- BazUI:BuildOptionsTableFromSpec. The Edit Mode popup in
-- Replica/Window.lua reads from the same spec - so the two surfaces
-- stay aligned automatically. Adding a new chrome/behavior setting
-- means editing one place (the spec); both panels pick it up.
--
-- Registered as a sub-page under BazChat's bottom tab in BazUI's
-- standalone options window.
---------------------------------------------------------------------------

local addonName = BazUI.Chat.MODULE_NAME

local PAGE_KEY = "BazUIChat-Settings"

local INTRO =
    "BazUIChat is a full chat replacement built on top of Blizzard's own "
    .. "ChatFrameMixin formatter. These options control the chat dock's "
    .. "chrome and behavior and apply to every tab. The same controls also "
    .. "live inline in Edit Mode - both views edit the same saved settings, "
    .. "so changes here mirror live to the popup and vice versa."

---------------------------------------------------------------------------
-- Register with BazUI
---------------------------------------------------------------------------

BazUI:QueueForLogin(function()
    if not BazUI.RegisterOptionsTable then return end
    if not BazUI.BuildOptionsTableFromSpec then return end

    local function BuildPage()
        return BazUI:BuildOptionsTableFromSpec(addonName, {
            name  = "Chat",
            intro = INTRO,
        })
    end

    -- Top-level addon entry (becomes the bottom tab in the BazUI
    -- standalone options window).
    BazUI:RegisterOptionsTable(addonName, BuildPage)
    BazUI:AddToSettings(addonName, "Chat")

    -- Settings sub-category in the left sidebar under BazChat.
    BazUI:RegisterOptionsTable(PAGE_KEY, BuildPage)
    BazUI:AddToSettings(PAGE_KEY, "Settings", addonName)
end)
