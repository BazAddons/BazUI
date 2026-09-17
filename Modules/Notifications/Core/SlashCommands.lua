-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BNC: Slash Command Helpers
-- Slash registration handled by BazUI:RegisterModule() in Init.lua
-- This file defines the test burst and scaffold helper functions
---------------------------------------------------------------------------
local addon = BazUI.Notifications
local BNC = addon.API

function addon.SendTestBurst()
    local delay = 0

    if addon.modules["zones"] then
        C_Timer.After(delay, function()
            BNC:Push({
                module = "zones",
                title = "Elwynn Forest",
                message = "Goldshire",
                icon = "Interface\\Icons\\INV_Misc_Map_01",
                priority = "normal",
                duration = 4,
            })
        end)
        delay = delay + 0.3
    end

    if addon.modules["loot"] then
        C_Timer.After(delay, function()
            BNC:Push({
                module = "loot",
                title = "|cff1eff00Rugged Leather|r",
                message = "x3",
                icon = "Interface\\Icons\\INV_Misc_LeatherScrap_08",
                priority = "low",
                duration = 4,
            })
        end)
        delay = delay + 0.2

        C_Timer.After(delay, function()
            BNC:Push({
                module = "loot",
                title = "|cff0070ddBlade of Valor|r",
                message = "",
                icon = "Interface\\Icons\\INV_Sword_39",
                priority = "normal",
                duration = 4,
            })
        end)
        delay = delay + 0.2

        C_Timer.After(delay, function()
            BNC:Push({
                module = "loot",
                title = "Coin Received",
                message = "|cffffd7002|rg |cffc7c7cf34|rs |cffeda55f15|rc",
                emphasis = true,
                icon = "Interface\\Icons\\INV_Misc_Coin_01",
                priority = "low",
                duration = 3,
            })
        end)
        delay = delay + 0.2

        C_Timer.After(delay, function()
            BNC:Push({
                module = "loot",
                title = "|cffa335eeStaff of Infinite Mysteries|r",
                message = "",
                icon = "Interface\\Icons\\INV_Staff_30",
                priority = "high",
                duration = 5,
            })
        end)
        delay = delay + 0.3
    end

    if addon.modules["quests"] then
        C_Timer.After(delay, function()
            BNC:Push({
                module = "quests",
                title = "A Threat Within",
                message = "Wolves slain 6/10",
                icon = "Interface\\Icons\\INV_Scroll_02",
                priority = "low",
                duration = 3,
            })
        end)
        delay = delay + 0.3

        C_Timer.After(delay, function()
            BNC:Push({
                module = "quests",
                title = "Quest Completed",
                message = "A Threat Within",
                icon = "Interface\\Icons\\Achievement_Quests_Completed_08",
                priority = "high",
                duration = 5,
            })
        end)
        delay = delay + 0.2
    end

    C_Timer.After(delay, function()
        BNC:Push({
            module = "_test",
            title = "BNC Test Complete",
            message = "All systems working!",
            icon = "Interface\\Icons\\INV_Misc_Bell_01",
            priority = "normal",
        })
    end)
end

function addon.ScaffoldModule(moduleName)
    if not moduleName or moduleName == "" then
        print("|cff00aaff[BNC]|r Usage: /bnc scaffold MyModule")
        print("  Prints a complete module template to chat.")
        return
    end

    local displayName = moduleName
    local moduleId = moduleName:lower():gsub("%s+", "")
    local folderName = "BNC-" .. moduleName:gsub("%s+", "")

    print("|cff00aaff[BNC]|r === Module Scaffold: " .. folderName .. " ===")
    print("|cff00aaff[BNC]|r Create folder: Interface/AddOns/" .. folderName)
    print(" ")
    print("|cff88ff88-- FILE: " .. folderName .. "/" .. folderName .. ".toc|r")
    print("## Interface: 120001")
    print("## Title: BazUI Notifications - " .. displayName)
    print("## Notes: Description of your module.")
    print("## Author: YourName")
    print("## Version: 1")
    print("## RequiredDeps: BazUI Notifications")
    print("## IconTexture: Interface\\Icons\\INV_Misc_QuestionMark")
    print("## Category: Baz Suite")
    print(folderName .. ".lua")
    print(" ")
    print("|cff88ff88-- FILE: " .. folderName .. "/" .. folderName .. ".lua|r")
    print('local MODULE_ID = "' .. moduleId .. '"')
    print('local MODULE_NAME = "' .. displayName .. '"')
    print('local MODULE_ICON = "Interface\\\\Icons\\\\INV_Misc_QuestionMark"')
    print(" ")
    print("local GetSetting = BNC:CreateGetSetting(MODULE_ID)")
    print(" ")
    print("BNC:RegisterModule({ id = MODULE_ID, name = MODULE_NAME, icon = MODULE_ICON })")
    print(" ")
    print("BNC:RegisterModuleOptions(MODULE_ID, {")
    print('    { key = "showAlerts", label = "Show Alerts", type = "toggle", default = true },')
    print('    { key = "alertDuration", label = "Alert Duration", type = "slider", default = 5, min = 1, max = 15, step = 1 },')
    print("})")
    print(" ")
    print("-- Listen for events:")
    print('BNC:Listen("YOUR_EVENT_HERE", function(event, ...)')
    print("    if GetSetting(\"showAlerts\") == false then return end")
    print("    BNC:NewNotification(MODULE_ID)")
    print('        :title("Something Happened")')
    print('        :message("Details")')
    print('        :priority("normal")')
    print("        :send()")
    print("end)")
    print(" ")
    print("|cff00aaff[BNC]|r === End Scaffold ===")
end
