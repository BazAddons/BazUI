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

---------------------------------------------------------------------------
-- Register with BazUI
---------------------------------------------------------------------------

BazUI:QueueForModule("Chat", function()
    if not BazUI.RegisterOptionsTable then return end
    if not BazUI.BuildOptionsTableFromSpec then return end

    -- The module entry itself never renders: its pages are tabs.
    BazUI:RegisterOptionsTable(addonName, function()
        return { name = "Chat", type = "group", args = {} }
    end)
    BazUI:AddToSettings(addonName, "Chat")

    BazUI:RegisterOptionsTable(PAGE_KEY, function()
        return BazUI:BuildOptionsTableFromSpec(addonName, { name = "General" })
    end)
    BazUI:AddToSettings(PAGE_KEY, "General", addonName)
end)
