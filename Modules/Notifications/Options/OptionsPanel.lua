-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BNC: Options Panel
-- Uses BazUI:RegisterOptionsTable() for consistent Baz Suite styling
---------------------------------------------------------------------------
local addon = BazUI.Notifications
local BNC = addon.API

local moduleSubCategories = {}

---------------------------------------------------------------------------
-- Main Page: User Manual
---------------------------------------------------------------------------

local function GetMainOptionsTable()
    return BazUI:CreateLandingPage("Notifications", {
        subtitle = "Notification center",
        description = "A modern, polished notification center for World of Warcraft. " ..
            "Captures game events and displays them as toasts and in a browsable notification panel. " ..
            "Fifteen built-in modules cover loot, mail, quests, reputation, and more.",
        features = "Toast popups with priority-based sounds and auto-dismiss. " ..
            "Notification panel with grouping, history, and search. " ..
            "Do Not Disturb mode (manual or auto in combat/encounters). " ..
            "Open plugin API - any addon can create notification modules.",
        guide = {
            { "Bell Icon", "Left-click to open the panel. Right-click to clear all" },
            { "Toasts", "Brief popups appear for new events and auto-dismiss" },
            { "History", "Switch to the History tab to browse past notifications" },
            { "DND", "Use |cff00ff00/bnc dnd|r or enable auto-DND in Settings" },
            { "Modules", "Enable or disable individual modules in the Modules tab" },
        },
        commands = {
            { "/bnc", "Toggle notification panel" },
            { "/bnc test", "Send a test notification" },
            { "/bnc testall", "Test all active modules" },
            { "/bnc dnd", "Toggle Do Not Disturb" },
            { "/bnc clear", "Clear all notifications" },
            { "/bnc history", "Open notification history" },
            { "/bnc options", "Open settings" },
            { "/bnc scaffold <name>", "Generate a module template" },
        },
    })
end

---------------------------------------------------------------------------
-- Settings Subcategory
---------------------------------------------------------------------------

local function GetSettingsOptionsTable()
    return {
        name = "Settings",
        type = "group",
        args = {
            intro = {
                order = 0.1,
                type = "lead",
                text = "Where notifications appear, how long they stay, and how the history panel behaves. Per-module on/off lives under Modules.",
            },
            positionHeader = {
                order = 1,
                type = "header",
                name = "Bell Position",
            },
            positionNote = {
                order = 2,
                type = "note",
                style = "info",
                text = "Move the bell icon by entering Edit Mode. The notification panel and toasts always anchor to the bell, and the panel/toast growth direction is chosen automatically based on which screen corner the bell is closest to.",
            },
            resetBellTopLeft = {
                order = 3,
                type = "execute",
                name = "Reset to Top Left",
                desc = "Snap the bell back to the top-left corner.",
                width = "half",
                func = function()
                    if addon.ResetBellPosition then addon.ResetBellPosition("TOPLEFT") end
                end,
            },
            resetBellTopRight = {
                order = 4,
                type = "execute",
                name = "Reset to Top Right",
                desc = "Snap the bell back to the top-right corner.",
                width = "half",
                func = function()
                    if addon.ResetBellPosition then addon.ResetBellPosition("TOPRIGHT") end
                end,
            },
            displayHeader = {
                order = 10,
                type = "header",
                name = "Display",
            },
            toastDuration = {
                order = 11,
                type = "range",
                name = "Toast Duration (seconds)",
                min = 1, max = 15, step = 1,
                get = function() return addon.db and addon.db.toastDuration or 5 end,
                set = function(_, val) addon.SetDBValue("toastDuration", val) end,
            },
            panelOpacity = {
                order = 12,
                type = "range",
                name = "Panel Opacity",
                min = 0.5, max = 1.0, step = 0.05,
                get = function() return addon.db and addon.db.panelOpacity or 0.85 end,
                set = function(_, val) addon.SetDBValue("panelOpacity", val) end,
            },
            scale = {
                order = 13,
                type = "range",
                name = "Scale",
                min = 0.5, max = 2.0, step = 0.1,
                get = function() return addon.db and addon.db.scale or 1.0 end,
                set = function(_, val) addon.SetDBValue("scale", val) end,
            },
            maxHistory = {
                order = 14,
                type = "range",
                name = "Max Notifications",
                min = 10, max = 999, step = 10,
                get = function() return addon.db and addon.db.maxHistory or 999 end,
                set = function(_, val) addon.SetDBValue("maxHistory", val) end,
            },
            historyRetentionDays = {
                order = 14.5,
                type = "range",
                name = "History Retention (Days)",
                desc = "Persisted notification history older than this many days is pruned at login and after each new notification.",
                min = 1, max = 90, step = 1,
                get = function() return addon.db and addon.db.historyRetentionDays or 7 end,
                set = function(_, val)
                    addon.SetDBValue("historyRetentionDays", val)
                    if addon.History_Trim then addon.History_Trim(val) end
                end,
            },
            toastsEnabled = {
                order = 15,
                type = "toggle",
                name = "Enable Toast Popups",
                get = function() return addon.db and addon.db.toastsEnabled ~= false end,
                set = function(_, val) addon.SetDBValue("toastsEnabled", val) end,
            },
            soundEnabled = {
                order = 16,
                type = "toggle",
                name = "Enable Sounds",
                get = function() return addon.db and addon.db.soundEnabled ~= false end,
                set = function(_, val) addon.SetDBValue("soundEnabled", val) end,
            },
            tomtomEnabled = {
                order = 17,
                type = "toggle",
                name = "Enable TomTom Waypoints",
                get = function() return addon.db and addon.db.tomtomEnabled ~= false end,
                set = function(_, val) addon.SetDBValue("tomtomEnabled", val) end,
            },
            dndHeader = {
                order = 20,
                type = "header",
                name = "Do Not Disturb",
            },
            dndIntro = {
                order = 20.5,
                type = "note",
                style = "tip",
                text = "DND mode silences toast popups and sounds without losing notifications - they still appear in the history panel for review.",
            },
            dndEnabled = {
                order = 21,
                type = "toggle",
                name = "Enable DND (suppress toasts & sounds)",
                get = function() return addon.db and addon.db.dndEnabled end,
                set = function(_, val) addon.SetDBValue("dndEnabled", val) end,
            },
            dndAutoCombat = {
                order = 22,
                type = "toggle",
                name = "Auto-enable in combat",
                get = function() return addon.db and addon.db.dndAutoCombat end,
                set = function(_, val) addon.SetDBValue("dndAutoCombat", val) end,
            },
            dndAutoInstance = {
                order = 23,
                type = "toggle",
                name = "Auto-enable during encounters",
                get = function() return addon.db and addon.db.dndAutoInstance end,
                set = function(_, val) addon.SetDBValue("dndAutoInstance", val) end,
            },
            soundHeader = {
                order = 30,
                type = "header",
                name = "Notification Sounds",
            },
            soundHigh = {
                order = 31,
                type = "range",
                name = "High Priority Sound ID (0 = silent)",
                min = 0, max = 100000, step = 1,
                get = function() return addon.db and addon.db.soundHigh or 8959 end,
                set = function(_, val) addon.SetDBValue("soundHigh", val) end,
            },
            soundNormal = {
                order = 32,
                type = "range",
                name = "Normal Priority Sound ID (0 = silent)",
                min = 0, max = 100000, step = 1,
                get = function() return addon.db and addon.db.soundNormal or 618 end,
                set = function(_, val) addon.SetDBValue("soundNormal", val) end,
            },
            soundLow = {
                order = 33,
                type = "range",
                name = "Low Priority Sound ID (0 = silent)",
                min = 0, max = 100000, step = 1,
                get = function() return addon.db and addon.db.soundLow or 0 end,
                set = function(_, val) addon.SetDBValue("soundLow", val) end,
            },
        },
    }
end

---------------------------------------------------------------------------
-- Modules Subcategory - list/detail panel
-- One unified page with a list of modules on the left and the selected
-- module's enable toggle + settings on the right. Same shape BWD's
-- Drawers / Widgets sub-categories use.
---------------------------------------------------------------------------

-- Build the args table for one module's detail panel: enable toggle on
-- top, then any module-specific options registered via the option-defs
-- system. Shared with the (now-deprecated) per-module pages below.
local function BuildModuleArgs(moduleId)
    local args = {
        enabled = {
            order = 1,
            type = "toggle",
            name = "Enable Module",
            desc = "Toggle this module's notifications on or off.",
            get = function()
                if not addon.db then return true end
                local settings = addon.db.modules[moduleId]
                if not settings then return true end
                return settings.enabled ~= false
            end,
            set = function(_, val)
                if not addon.db.modules[moduleId] then
                    addon.db.modules[moduleId] = {}
                end
                addon.db.modules[moduleId].enabled = val
                addon.Events:Trigger("MODULE_TOGGLED", moduleId, val)
            end,
        },
    }

    local optDefs = addon.moduleOptionDefs and addon.moduleOptionDefs[moduleId]
    if optDefs then
        -- Header before the per-module options so it's visually grouped
        args._optsHeader = {
            order = 5,
            type = "header",
            name = "Module Settings",
        }
        for i, optDef in ipairs(optDefs) do
            local key = optDef.key
            local default = optDef.default
            local disabledFunc = function()
                return BNC:IsGlobalOverrideActive(key)
            end
            if optDef.type == "toggle" then
                args[key] = {
                    order = 10 + i,
                    type = "toggle",
                    name = optDef.label,
                    get = function()
                        local val = BNC:GetModuleSetting(moduleId, key)
                        if val == nil then return default ~= false end
                        return val ~= false
                    end,
                    set = function(_, val)
                        BNC:SetModuleSetting(moduleId, key, val)
                    end,
                    disabled = disabledFunc,
                }
            elseif optDef.type == "slider" then
                args[key] = {
                    order = 10 + i,
                    type = "range",
                    name = optDef.label,
                    min = optDef.min or 1,
                    max = optDef.max or 15,
                    step = optDef.step or 1,
                    get = function()
                        local val = BNC:GetModuleSetting(moduleId, key)
                        if val == nil then return default or optDef.min or 1 end
                        return val
                    end,
                    set = function(_, val)
                        BNC:SetModuleSetting(moduleId, key, val)
                    end,
                    disabled = disabledFunc,
                }
            end
        end
    end

    return args
end

local function GetModulesOptionsTable()
    -- Sort modules alphabetically
    local sorted = {}
    for id, module in pairs(addon.modules) do
        if id ~= "_test" then
            table.insert(sorted, { id = id, name = module.name })
        end
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)

    -- Build one child group per module so BazUI's CreateTwoPanelLayout
    -- renders a list/detail panel automatically.
    local moduleGroups = {}
    for i, info in ipairs(sorted) do
        moduleGroups["mod_" .. info.id] = {
            order = i,
            type = "group",
            name = info.name,
            args = BuildModuleArgs(info.id),
        }
    end

    return {
        name = "Modules",
        type = "group",
        args = {
            intro = {
                order = 0.1,
                type = "lead",
                text = "Pick a module on the left to enable/disable it and adjust its specific settings. Each module captures a different category of game events.",
            },
            modules = {
                order = 10,
                type = "group",
                name = "",
                args = moduleGroups,
            },
        },
    }
end

---------------------------------------------------------------------------
-- Global Options Subcategory
---------------------------------------------------------------------------

local function GetGlobalOptionsTable()
    return BazUI:CreateGlobalOptionsPage("Notifications", {
        getOverrides = function()
            if not addon.db then return {} end
            if not addon.db.globalOverrides then addon.db.globalOverrides = {} end
            return addon.db.globalOverrides
        end,
        setOverride = function(key, field, value)
            if not addon.db then return end
            if not addon.db.globalOverrides then addon.db.globalOverrides = {} end
            if not addon.db.globalOverrides[key] then
                addon.db.globalOverrides[key] = { enabled = false, value = nil }
            end
            addon.db.globalOverrides[key][field] = value
        end,
        overrides = {
            { key = "toastDuration",  label = "Toast Duration",  type = "slider",  default = 5, min = 1, max = 15, step = 1 },
            { key = "soundEnabled",   label = "Play Sound",      type = "toggle",  default = true },
            { key = "toastsEnabled",  label = "Enable Toasts",   type = "toggle",  default = true },
        },
    })
end

---------------------------------------------------------------------------
-- Per-Module Settings Subcategory
---------------------------------------------------------------------------

-- Per-module sub-categories are no longer separate sidebar entries -
-- everything lives inside the unified Modules list/detail page now.
-- This stub stays so the "create on module register" event chain still
-- has something to call; it just refreshes the Modules page.
local function CreateModuleOptionsPage(moduleId)
    if not addon.modules[moduleId] then return end
    moduleSubCategories[moduleId] = true
    if BazUI.RefreshOptions then
        BazUI:RefreshOptions("Notifications-Modules")
    end
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

local function TryCreateAllPendingPages()
    for moduleId in pairs(addon.moduleOptionDefs) do
        if not moduleSubCategories[moduleId] then
            CreateModuleOptionsPage(moduleId)
        end
    end
end

local optionsReady = false

addon.Events:Register("CORE_LOADED", function()
    -- Main page (user manual) - must be first so parent category exists
    BazUI:RegisterOptionsTable("Notifications", GetMainOptionsTable)
    BazUI:AddToSettings("Notifications", "Notifications")

    -- Settings subcategory
    BazUI:RegisterOptionsTable("Notifications-Settings", GetSettingsOptionsTable)
    BazUI:AddToSettings("Notifications-Settings", "General Settings", "Notifications")

    -- Global Options subcategory
    BazUI:RegisterOptionsTable("Notifications-GlobalOptions", GetGlobalOptionsTable)
    BazUI:AddToSettings("Notifications-GlobalOptions", "Global Settings", "Notifications")

    -- Modules subcategory
    BazUI:RegisterOptionsTable("Notifications-Modules", GetModulesOptionsTable)
    BazUI:AddToSettings("Notifications-Modules", "Modules", "Notifications")

    -- Now safe to create per-module pages
    optionsReady = true
    TryCreateAllPendingPages()
end)

-- These fire before CORE_LOADED, so guard with optionsReady
addon.Events:Register("MODULE_REGISTERED", function()
    if optionsReady then TryCreateAllPendingPages() end
end)
addon.Events:Register("MODULE_OPTIONS_REGISTERED", function()
    if optionsReady then TryCreateAllPendingPages() end
end)
addon.Events:Register("PLAYER_READY", TryCreateAllPendingPages)

function addon.OpenOptions()
    BazUI:OpenOptionsPanel("Notifications")
end
