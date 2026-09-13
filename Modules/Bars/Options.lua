-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazBars Options Module
-- Now powered by BazUI OptionsPanel

local BazBars = BazUI.Bars   -- module namespace (was the BazBars global)
local addon = BazUI:GetModule("Bars")
local Options = {}
addon.Options = Options

---------------------------------------------------------------------------
-- Build options table dynamically (reflects current bars)
---------------------------------------------------------------------------

local BuildBarOptions -- forward declaration

local function GetOptionsTable()
    local options = {
        name = "Bars",
        subtitle = "Custom extra action bars",
        type = "group",
        args = {
            createBar = {
                order = 1,
                type = "execute",
                name = "Create New Bar",
                func = function()
                    local bb = BazUI:GetModule("Bars")
                    if bb and not InCombatLockdown() then
                        local id = bb:CreateNewBar()
                        if id then
                            bb:Print("Created Bar " .. id)
                            bb.Options:Refresh()
                        end
                    end
                end,
            },
            bars = {
                order = 10,
                type = "group",
                name = "",
                args = {},
            },
        },
    }

    -- Build per-bar options
    local dbBars = addon.db and addon.db.profile and addon.db.profile.bars or {}
    for id, barData in pairs(dbBars) do
        if type(barData) == "table" then
            options.args.bars.args["bar" .. id] = BuildBarOptions(id, barData)
        end
    end

    return options
end

---------------------------------------------------------------------------
-- Per-bar options group
---------------------------------------------------------------------------

BuildBarOptions = function(id, barData)
    return {
        order = id,
        type = "group",
        name = "Bar " .. id,
        desc = "Configure Bar " .. id,
        args = {
            barName = {
                order = 0,
                type = "input",
                name = "Bar Name",
                desc = "Custom name for this bar",
                get = function() return barData.customName or "" end,
                set = function(_, val)
                    barData.customName = (val ~= "") and val or nil
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:SetCustomName(frame, barData.customName)
                    end
                end,
            },
            layoutHeader = {
                order = 1,
                type = "header",
                name = "Layout",
            },
            orientation = {
                order = 2,
                type = "select",
                name = "Orientation",
                values = { horizontal = "Horizontal", vertical = "Vertical" },
                get = function() return barData.orientation or "horizontal" end,
                set = function(_, val)
                    barData.orientation = val
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:LayoutButtons(frame, barData)
                    end
                end,
            },
            columns = {
                order = 4,
                type = "range",
                name = "# of Icons",
                min = 1, max = BazBars.MAX_COLS, step = 1,
                get = function() return barData.cols end,
                set = function(_, val)
                    barData.cols = val
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:Resize(frame, barData.rows, val, barData.spacing)
                    end
                end,
            },
            rows = {
                order = 6,
                type = "range",
                name = "# of Rows",
                min = 1, max = BazBars.MAX_ROWS, step = 1,
                get = function() return barData.rows end,
                set = function(_, val)
                    barData.rows = val
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:Resize(frame, val, barData.cols, barData.spacing)
                    end
                end,
            },
            appearanceHeader = {
                order = 10,
                type = "header",
                name = "Appearance",
            },
            scale = {
                order = 12,
                type = "range",
                name = "Icon Size",
                min = BazBars.MIN_SCALE, max = BazBars.MAX_SCALE, step = 0.05,
                isPercent = true,
                get = function() return BazBars.GetBarSetting(barData, "scale") end,
                set = function(_, val)
                    barData.scale = val
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:SetScale(frame, val)
                    end
                end,
                disabled = function() return BazBars.IsGlobalOverrideActive("scale") end,
            },
            spacing = {
                order = 14,
                type = "range",
                name = "Icon Padding",
                min = 0, max = 20, step = 1,
                get = function() return BazBars.GetBarSetting(barData, "spacing") end,
                set = function(_, val)
                    barData.spacing = val
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:Resize(frame, barData.rows, barData.cols, val)
                    end
                end,
                disabled = function() return BazBars.IsGlobalOverrideActive("spacing") end,
            },
            barAlpha = {
                order = 16,
                type = "range",
                name = "Bar Opacity",
                min = 0, max = 1, step = 0.05,
                isPercent = true,
                get = function() return BazBars.GetBarSetting(barData, "alpha") or 1.0 end,
                set = function(_, val)
                    barData.alpha = val
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:SetBarAlpha(frame, val)
                    end
                end,
                disabled = function() return BazBars.IsGlobalOverrideActive("alpha") end,
            },
            visibilityHeader = {
                order = 20,
                type = "header",
                name = "Visibility",
            },
            mouseoverFade = {
                order = 21,
                type = "toggle",
                name = "Mouseover Fade",
                desc = "Bar fades out when mouse is not hovering over it",
                get = function() return BazBars.GetBarSetting(barData, "mouseoverFade") or false end,
                set = function(_, val)
                    barData.mouseoverFade = val
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:ApplyMouseoverFade(frame)
                    end
                end,
                disabled = function() return BazBars.IsGlobalOverrideActive("mouseoverFade") end,
            },
            alwaysShowButtons = {
                order = 22,
                type = "toggle",
                name = "Always Show Buttons",
                desc = "Show empty button slots even when no ability is assigned",
                get = function() return BazBars.GetBarSetting(barData, "alwaysShowButtons") ~= false end,
                set = function(_, val)
                    barData.alwaysShowButtons = val
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:UpdateButtonVisibility(frame)
                    end
                end,
                disabled = function() return BazBars.IsGlobalOverrideActive("alwaysShowButtons") end,
            },
            showSlotArt = {
                order = 23,
                type = "toggle",
                name = "Show Slot Art",
                desc = "Show the background texture on each button slot",
                get = function() return BazBars.GetBarSetting(barData, "showSlotArt") ~= false end,
                set = function(_, val)
                    barData.showSlotArt = val
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:UpdateSlotArt(frame)
                    end
                end,
                disabled = function() return BazBars.IsGlobalOverrideActive("showSlotArt") end,
            },
            clickThrough = {
                order = 24,
                type = "toggle",
                name = "Click-Through",
                desc = "Bar buttons stop intercepting mouse clicks. Icons, cooldowns, range tinting, and proc glow all still render - you just can't click the buttons directly while this is on. Useful for visual-reference bars.",
                get = function() return BazBars.GetBarSetting(barData, "clickThrough") or false end,
                set = function(_, val)
                    barData.clickThrough = val
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:ApplyClickThrough(frame)
                    end
                end,
                disabled = function() return BazBars.IsGlobalOverrideActive("clickThrough") end,
            },
            lockButtons = {
                order = 24,
                type = "toggle",
                name = "Lock Buttons",
                desc = "Prevent buttons from being dragged or swapped. When unlocked (default), you can drag buttons to move or swap them.",
                get = function() return barData.locked or false end,
                set = function(_, val)
                    barData.locked = val
                end,
            },
            visibilityMacroHeader = {
                order = 30,
                type = "header",
                name = "Visibility Macro",
            },
            visibilityDesc = {
                order = 31,
                type = "description",
                name = "Use WoW macro conditionals to control when this bar is visible.\n",
            },
            visibilityMacro = {
                order = 32,
                type = "input",
                name = "Visibility Condition",
                desc = "Examples:\n[combat] show; hide\n[nocombat] hide; show",
                get = function() return barData.visibilityMacro or "" end,
                set = function(_, val)
                    barData.visibilityMacro = val
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:SetVisibilityMacro(frame, val)
                    end
                end,
            },
            actionsHeader = {
                order = 90,
                type = "header",
                name = "",
            },
            deleteBar = {
                order = 100,
                type = "execute",
                name = "|cffff4444Delete This Bar|r",
                confirm        = true,
                confirmTitle   = "Delete bar?",
                confirmText    = "Delete Bar " .. id .. "? This removes the bar and every button on it. Can't be undone.",
                confirmStyle   = "destructive",
                confirmAcceptLabel = "Delete",
                confirmCancelLabel = "Cancel",
                func = function()
                    addon:DeleteBar(id)
                end,
            },
        },
    }
end

---------------------------------------------------------------------------
-- Register with BazUI OptionsPanel
---------------------------------------------------------------------------

local function GetOverrides()
    if not addon.db or not addon.db.profile then return {} end
    if not addon.db.profile.globalOverrides then addon.db.profile.globalOverrides = {} end
    return addon.db.profile.globalOverrides
end

local function SetOverride(key, field, value)
    if not addon.db or not addon.db.profile then return end
    if not addon.db.profile.globalOverrides then addon.db.profile.globalOverrides = {} end
    if not addon.db.profile.globalOverrides[key] then
        addon.db.profile.globalOverrides[key] = { enabled = false, value = nil }
    end
    addon.db.profile.globalOverrides[key][field] = value
end

local function GetSettingsOptionsTable()
    return {
        name = "Settings",
        type = "group",
        args = {
            intro = {
                order = 0.1,
                type = "lead",
                text = "Display, tooltip, and combat preferences that apply to every BazBar. Per-bar settings live under Bar Options.",
            },
            blizzardHeader = {
                order = 0.4,
                type = "header",
                name = "Blizzard UI",
            },
            hideDefaultActionBar = {
                order = 0.5,
                type = "toggle",
                name = "Hide Default Action Bar (Bar 1)",
                desc = "Hide Blizzard's main action bar (slots 1-12 plus all chrome). Edit Mode lets you hide bars 2-8 already; this fills the gap for Bar 1.\n\nKeybinds 1-12 still fire whatever's slotted on those buttons; only the visible UI is hidden. Toggling in combat is deferred until combat ends.",
                get = function() return addon.db.profile.hideDefaultActionBar == true end,
                set = function(_, val)
                    addon.db.profile.hideDefaultActionBar = val
                    if addon.ApplyDefaultBarVisibility then
                        addon:ApplyDefaultBarVisibility()
                    end
                end,
            },
            hideDefaultActionBarArt = {
                order = 0.6,
                type = "toggle",
                name = "Hide Bar 1 Art Only",
                desc = "Hide just the chrome (the gryphon/wyvern endcaps and the dark border frame) on Bar 1, while keeping the buttons themselves visible. Useful if you still use Bar 1's buttons but want the decorative art gone.\n\nIgnored when 'Hide Default Action Bar' is on (everything is hidden anyway).",
                get = function() return addon.db.profile.hideDefaultActionBarArt == true end,
                set = function(_, val)
                    addon.db.profile.hideDefaultActionBarArt = val
                    if addon.ApplyDefaultBarVisibility then
                        addon:ApplyDefaultBarVisibility()
                    end
                end,
            },
            displayHeader = {
                order = 1,
                type = "header",
                name = "Display",
            },
            fullRangeColor = {
                order = 2,
                type = "toggle",
                name = "Full Button Range Color",
                desc = "Tint the entire button red when out of range (icon, frame, hotkey). When off, only the hotkey text turns red.",
                get = function() return addon.db.profile.fullRangeColor ~= false end,
                set = function(_, val) addon.db.profile.fullRangeColor = val end,
            },
            showTooltips = {
                order = 3,
                type = "toggle",
                name = "Show Tooltips",
                desc = "Show spell/item tooltips when hovering buttons",
                get = function() return addon.db.profile.showTooltips ~= false end,
                set = function(_, val) addon.db.profile.showTooltips = val end,
            },
            tooltipAnchor = {
                order = 4,
                type = "select",
                name = "Tooltip Position",
                desc = "Where BazUI Bars tooltips appear when hovering a button.",
                values = {
                    default = "Default (bottom-right corner)",
                    button  = "Next to button",
                },
                get = function() return addon.db.profile.tooltipAnchor or "default" end,
                set = function(_, val) addon.db.profile.tooltipAnchor = val end,
            },
            showKeybindText = {
                order = 5,
                type = "toggle",
                name = "Show Keybind Text",
                desc = "Display hotkey text on buttons",
                get = function() return addon.db.profile.showKeybindText ~= false end,
                set = function(_, val)
                    addon.db.profile.showKeybindText = val
                    for _, frame in pairs(addon.Bar:GetAll()) do
                        for r, row in pairs(frame.buttons) do
                            for c, btn in pairs(row) do
                                if btn.HotKey then
                                    btn.HotKey:SetShown(val and btn.HotKey:GetText() ~= "")
                                end
                            end
                        end
                    end
                end,
            },
            showMacroNames = {
                order = 6,
                type = "toggle",
                name = "Show Macro Names",
                desc = "Display macro name text on buttons",
                get = function() return addon.db.profile.showMacroNames ~= false end,
                set = function(_, val)
                    addon.db.profile.showMacroNames = val
                    for _, frame in pairs(addon.Bar:GetAll()) do
                        for _, row in pairs(frame.buttons) do
                            for _, btn in pairs(row) do
                                if btn.Name then
                                    local isMacro = btn.action and btn.action.type == "macro"
                                    btn.Name:SetShown(val and isMacro)
                                end
                            end
                        end
                    end
                end,
            },
            combatHeader = {
                order = 10,
                type = "header",
                name = "Combat",
            },
            combatNote = {
                order = 10.5,
                type = "note",
                style = "info",
                text = "BazUIBars buttons always cast on key up. The setting below only affects Blizzard's default action bars.",
            },
            castOnKeyDown = {
                order = 11,
                type = "toggle",
                name = "Cast on Key Down",
                desc = "Default bars cast on keypress instead of keyrelease. Required for hold-to-cast features like One Button Combat.",
                get = function() return GetCVarBool("ActionButtonUseKeyDown") end,
                set = function(_, val)
                    SetCVar("ActionButtonUseKeyDown", val and "1" or "0")
                end,
            },
        },
    }
end

local function GetGlobalOptionsTable()
    return BazUI:CreateGlobalOptionsPage("Bars", {
        getOverrides = GetOverrides,
        setOverride = SetOverride,
        overrides = {
            { key = "scale",             label = "Icon Size",           type = "slider",  default = 1.0, min = BazBars.MIN_SCALE, max = BazBars.MAX_SCALE, step = 0.05 },
            { key = "alpha",             label = "Bar Opacity",         type = "slider",  default = 1.0, min = 0, max = 1, step = 0.05 },
            { key = "spacing",           label = "Icon Padding",        type = "slider",  default = 2, min = 0, max = 20, step = 1 },
            { key = "showSlotArt",       label = "Show Slot Art",       type = "toggle",  default = true },
            { key = "alwaysShowButtons", label = "Always Show Buttons", type = "toggle",  default = true },
            { key = "mouseoverFade",     label = "Mouseover Fade",      type = "toggle",  default = false },
            { key = "clickThrough",      label = "Click-Through",       type = "toggle",  default = false },
        },
    })
end

function Options:Setup()
    -- Parent category - addon info and quick guide
    BazUI:RegisterOptionsTable("Bars", function()
        return BazUI:CreateLandingPage("Bars", {
            subtitle = "Custom extra action bars",
            description = "Create unlimited custom action bars, completely independent of Blizzard's action bar system. " ..
                "Drag spells, items, macros, mounts and equipment sets onto your bars.",
            features = "Unlimited bars with up to 24x24 button grids. " ..
                "Blizzard-native button styling with cooldowns, proc glows, and range tinting. " ..
                "Full Edit Mode integration with grid snapping and settings popup. " ..
                "Quick keybind mode, import/export, bar duplication, visibility macros, and mouseover fade. " ..
                "Masque skinning support.",
            guide = {
                { "Creating Bars", "Open Edit Mode and click \"Create New BazBar\", or use |cff00ff00/bb create|r" },
                { "Adding Actions", "Drag spells, items, macros, mounts or equipment sets onto any button" },
                { "Removing", "Shift+Drag to remove, or Shift+Right-Click > Clear button" },
                { "Settings", "Edit Mode > click bar > settings popup, or |cff00ff00/bb|r for full options" },
                { "Keybinds", "Edit Mode > select bar > Quick Keybind Mode. Hover + press key to bind" },
            },
            commands = {
                { "/bb", "Open settings" },
                { "/bb create [cols] [rows]", "Create a new bar" },
                { "/bb delete <id>", "Delete a bar" },
                { "/bb duplicate <id>", "Duplicate a bar" },
                { "/bb export <id>", "Export bar config" },
                { "/bb import", "Import bar config" },
                { "/bb reset", "Reset all bars" },
            },
        })
    end)
    BazUI:AddToSettings("Bars", "Bars")

    -- Settings subcategory
    BazUI:RegisterOptionsTable("BazUIBars-Settings", GetSettingsOptionsTable)
    BazUI:AddToSettings("BazUIBars-Settings", "General Settings", "Bars")

    -- Global Options subcategory
    BazUI:RegisterOptionsTable("BazUIBars-Global", GetGlobalOptionsTable)
    BazUI:AddToSettings("BazUIBars-Global", "Global Settings", "Bars")

    -- Bar Options subcategory
    BazUI:RegisterOptionsTable("BazUIBars-Bars", GetOptionsTable)
    BazUI:AddToSettings("BazUIBars-Bars", "Bar Options", "Bars")
end

function Options:Refresh()
    BazUI:RegisterOptionsTable("BazUIBars-Bars", GetOptionsTable)
    BazUI:RefreshOptions("BazUIBars-Bars")
end

function Options:Open()
    BazUI:OpenOptionsPanel("Bars")
end
