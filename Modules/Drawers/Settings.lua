-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Drawers: options pages
--
-- General      - the drawer itself: side, width, appearance, fading, and
--                the "same on every widget" fade values.
-- Drawers      - a picker of your drawer tabs: name, icon, which widgets
--                each one holds.
-- Widgets      - a picker of every registered widget: placement, fading
--                and the widget's own settings.
-- Broker Feeds - LibDataBroker feeds shown as widgets (Widgets/Broker.lua).
---------------------------------------------------------------------------

local addon = BazUI:GetModule("Drawers")

---------------------------------------------------------------------------
-- General settings (side + width + toggle)
---------------------------------------------------------------------------

local PAGE_GENERAL = "BazUIDrawer-Settings"
local PAGE_DRAWERS = "BazUIDrawer-Drawers"
local PAGE_WIDGETS = "BazUIDrawer-Widgets"

local function Refresh(page)
    if BazUI.RefreshOptions then BazUI:RefreshOptions(page) end
end

local function Locked()
    return addon:GetSetting("locked") and true or false
end

local function FadeOff()
    return addon:GetSetting("fadeEnabled") == false
end

-- Values every widget can share (the old Global Settings tab).
local WIDGET_OVERRIDES = {
    { key = "fadeTitleBar",   label = "Same title bar fade on every widget",  valueLabel = "Fade title bars" },
    { key = "fadeBackground", label = "Same background fade on every widget", valueLabel = "Fade backgrounds" },
}

local function GetSettingsOptionsTable()
    local args = {
        layoutHeader = { order = 10, type = "header", name = "Layout" },
        side = {
            order = 11, type = "select", name = "Screen side",
            values = { right = "Right", left = "Left" },
            sorting = { "right", "left" },
            get = function() return addon:GetSetting("side") or "right" end,
            set = function(_, val)
                if addon.Drawer then addon.Drawer:SetSide(val) end
            end,
        },
        width = {
            order = 12, type = "range", name = "Width",
            desc = "Docked widgets scale to fill it.",
            min = (addon.Drawer and addon.Drawer.MIN_WIDTH) or 120,
            max = (addon.Drawer and addon.Drawer.MAX_WIDTH) or 400,
            step = 2, format = "%d px",
            get = function()
                return addon:GetSetting("width")
                    or (addon.Drawer and addon.Drawer.DEFAULT_WIDTH)
                    or 222
            end,
            set = function(_, val)
                if addon.Drawer then addon.Drawer:SetWidth(val) end
            end,
        },
        widgetSpacing = {
            order = 13, type = "range", name = "Space between widgets",
            min = 0, max = 24, step = 1, format = "%d px",
            get = function() return addon:GetSetting("widgetSpacing") or 6 end,
            set = function(_, val)
                addon:SetSetting("widgetSpacing", val)
                if addon.WidgetHost and addon.WidgetHost.Reflow then addon.WidgetHost:Reflow() end
            end,
        },

        appearanceHeader = { order = 20, type = "header", name = "Appearance" },
        lockedNote = {
            order = 21, type = "description",
            name = "The drawer is locked. Click the padlock on its bottom bar to change these.",
            hidden = function() return not Locked() end,
        },
        backgroundOpacity = {
            order = 22, type = "range", name = "Background opacity",
            min = 0, max = 1, step = 0.05, isPercent = true,
            get = function() return addon:GetSetting("backgroundOpacity") or 0.9 end,
            set = function(_, val)
                addon:SetSetting("backgroundOpacity", val)
                if addon.Drawer then addon.Drawer:ApplyAppearance() end
            end,
            disabled = Locked,
        },
        frameOpacity = {
            order = 23, type = "range", name = "Frame opacity",
            desc = "The border and tab when fully shown. Widgets always stay solid.",
            min = 0.2, max = 1, step = 0.05, isPercent = true,
            get = function() return addon:GetSetting("frameOpacity") or 1.0 end,
            set = function(_, val)
                addon:SetSetting("frameOpacity", val)
                if addon.Drawer then addon.Drawer:EvaluateFade(true) end
            end,
            disabled = Locked,
        },

        fadingHeader = { order = 30, type = "header", name = "Fading" },
        fadeEnabled = {
            order = 31, type = "toggle", name = "Fade when the cursor leaves",
            desc = "The backdrop, border and tab fade; widget content stays readable.",
            get = function() return addon:GetSetting("fadeEnabled") ~= false end,
            set = function(_, val)
                addon:SetSetting("fadeEnabled", val)
                if addon.Drawer then addon.Drawer:EvaluateFade(true) end
                Refresh(PAGE_GENERAL)
            end,
            disabled = Locked,
        },
        fadedOpacity = {
            order = 32, type = "range", name = "Faded opacity",
            desc = "0 makes the drawer invisible until you hover it.",
            min = 0, max = 1, step = 0.05, isPercent = true,
            get = function() return addon:GetSetting("fadedOpacity") or 0.3 end,
            set = function(_, val)
                addon:SetSetting("fadedOpacity", val)
                if addon.Drawer then addon.Drawer:EvaluateFade(true) end
            end,
            disabled = Locked, hidden = FadeOff,
        },
        fadeDelay = {
            order = 33, type = "range", name = "Fade after",
            min = 0, max = 5, step = 0.1, format = "%.1f s",
            get = function() return addon:GetSetting("fadeDelay") or 1.0 end,
            set = function(_, val) addon:SetSetting("fadeDelay", val) end,
            disabled = Locked, hidden = FadeOff,
        },
        fadeDuration = {
            order = 34, type = "range", name = "Fade takes",
            min = 0.05, max = 2, step = 0.05, format = "%.2f s",
            get = function() return addon:GetSetting("fadeDuration") or 0.3 end,
            set = function(_, val) addon:SetSetting("fadeDuration", val) end,
            disabled = Locked, hidden = FadeOff,
        },
        alwaysShowInCombat = {
            order = 35, type = "toggle", name = "Stay fully visible in combat",
            get = function() return addon:GetSetting("disableFadeInCombat") and true or false end,
            set = function(_, val)
                addon:SetSetting("disableFadeInCombat", val)
                if addon.Drawer then addon.Drawer:EvaluateFade(true) end
            end,
            disabled = Locked, hidden = FadeOff,
        },
        fadeTabWhenClosed = {
            order = 36, type = "toggle", name = "Fade the tab while the drawer is closed",
            desc = "Off keeps the pull-tab visible so you never have to find it.",
            get = function() return addon:GetSetting("fadeTabWhenClosed") ~= false end,
            set = function(_, val)
                addon:SetSetting("fadeTabWhenClosed", val)
                if addon.Drawer then addon.Drawer:EvaluateFade(true) end
                Refresh(PAGE_GENERAL)
            end,
            disabled = Locked, hidden = FadeOff,
        },
        edgeRevealPx = {
            order = 37, type = "range", name = "Reveal the tab within",
            desc = "Moving the cursor this close to the screen edge brings the faded tab back.",
            min = 2, max = 50, step = 1, format = "%d px",
            get = function() return addon:GetSetting("edgeRevealPx") or 8 end,
            set = function(_, val)
                addon:SetSetting("edgeRevealPx", val)
                if addon.Drawer and addon.Drawer.ApplyEdgeHotZone then
                    addon.Drawer:ApplyEdgeHotZone()
                end
            end,
            disabled = Locked,
            hidden = function() return FadeOff() or addon:GetSetting("fadeTabWhenClosed") == false end,
        },

        widgetsHeader = { order = 40, type = "header", name = "All widgets" },
        widgetsDesc = {
            order = 41, type = "description",
            name = "Force one value on every widget. A widget's own setting is grayed out while its override is on.",
        },
    }

    for i, def in ipairs(WIDGET_OVERRIDES) do
        local key = def.key
        local function Override()
            local o = addon:GetGlobalOverrides()
            o[key] = o[key] or { enabled = false }
            return o[key]
        end
        args["same_" .. key] = {
            order = 41 + i * 2, type = "toggle", name = def.label,
            get = function() return Override().enabled == true end,
            set = function(_, val)
                if Override().value == nil then addon:SetGlobalOverride(key, "value", true) end
                addon:SetGlobalOverride(key, "enabled", val)
                Refresh(PAGE_GENERAL)
                Refresh(PAGE_WIDGETS)
            end,
        }
        args["value_" .. key] = {
            order = 42 + i * 2, type = "toggle", name = def.valueLabel,
            hidden = function() return Override().enabled ~= true end,
            get = function() return Override().value ~= false end,
            set = function(_, val) addon:SetGlobalOverride(key, "value", val) end,
        }
    end

    return { name = "General", type = "group", args = args }
end

---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Compose a widget's display label with status + tag badges
--
-- Returns "<label>  [D]  [LDB]  ..." where:
--   - [D] (green) - dormant widget that is currently sleeping
--   - widget.tags (any) - static badges set at registration time, each
--     of the form { text = "X", color = "rrggbb" }. Lets addons like
--     BazBrokerWidget mark every widget they provide so the user knows
--     where it came from at a glance.
---------------------------------------------------------------------------
local function WidgetDisplayName(id, widget)
    local name = widget and widget.label or id

    local LBW = BazUI.Widgets
    if LBW and LBW.dormant and LBW.dormant[id] then
        if not LBW:IsDormantWidgetActive(id) then
            name = name .. "  |cff60ff60[D]|r"
        end
    end

    if widget and widget.tags then
        for _, tag in ipairs(widget.tags) do
            local color = tag.color or "ffffff"
            local text  = tag.text  or "?"
            name = name .. "  |cff" .. color .. "[" .. text .. "]|r"
        end
    end

    return name
end

-- Per-widget options group (built dynamically per widget)
---------------------------------------------------------------------------

local function BuildWidgetGroup(widget, index)
    local id = widget.id
    local function Floating() return addon:IsWidgetFloating(id) end
    local function Overridden(key)
        local o = addon:GetSetting("widgetGlobalOverrides")
        return o and o[key] and o[key].enabled or false
    end
    local function OverrideDesc(key)
        if Overridden(key) then return "Set for every widget under General." end
    end
    local args = {
        -- Ordering is by drag on the widget's title bar in the drawer
        -- (hold half a second, then drag); it is global, not per drawer.
        placementHeader = { order = 1, type = "header", name = "Placement" },
        floating = {
            order = 2, type = "toggle", name = "Floating",
            desc = "Detached from the drawer. Move it in Edit Mode.",
            get = Floating,
            set = function(_, val)
                if addon.WidgetHost and addon.WidgetHost.SetWidgetFloating then
                    addon.WidgetHost:SetWidgetFloating(id, val)
                end
                Refresh(PAGE_WIDGETS)
            end,
        },
        collapsed = {
            order = 3, type = "toggle", name = "Collapsed",
            desc = "Only the title bar shows in the drawer.",
            get = function() return addon:IsWidgetCollapsed(id) end,
            set = function(_, val)
                addon:SetWidgetCollapsed(id, val)
                if addon.WidgetHost then addon.WidgetHost:Reflow() end
            end,
            disabled = Floating,
        },
        dockedToBottom = {
            order = 4, type = "toggle", name = "Pin to the bottom of the drawer",
            desc = "Pinned widgets stack up from the bottom edge instead of pushing others down.",
            get = function() return addon:IsWidgetDockedToBottom(id) end,
            set = function(_, val)
                addon:SetWidgetDockedToBottom(id, val)
                if addon.WidgetHost then addon.WidgetHost:Reflow() end
            end,
            disabled = Floating,
        },

        fadeHeader = { order = 5, type = "header", name = "Fading" },
        fadeTitleBar = {
            order = 6, type = "toggle", name = "Fade the title bar with the drawer",
            desc = OverrideDesc("fadeTitleBar"),
            get = function()
                return addon:GetWidgetEffectiveSetting(id, "fadeTitleBar", true) ~= false
            end,
            set = function(_, val)
                addon:SetWidgetSetting(id, "fadeTitleBar", val)
                if addon.Drawer then addon.Drawer:EvaluateFade(true) end
            end,
            disabled = function() return Overridden("fadeTitleBar") end,
        },
        fadeBackground = {
            order = 7, type = "toggle", name = "Fade the background with the drawer",
            desc = OverrideDesc("fadeBackground"),
            get = function()
                return addon:GetWidgetEffectiveSetting(id, "fadeBackground", true) ~= false
            end,
            set = function(_, val)
                addon:SetWidgetSetting(id, "fadeBackground", val)
                if addon.Drawer then addon.Drawer:EvaluateFade(true) end
            end,
            disabled = function() return Overridden("fadeBackground") end,
        },
    }

    -- Widgets can supply their own options via widget:GetOptionsArgs().
    -- Their internal order values (often 1..N) would collide with the
    -- top-level order slots, so we shift them all into the 20+ range,
    -- preserving the widget's own relative ordering under its header.
    if widget.GetOptionsArgs then
        local ok, extra = pcall(widget.GetOptionsArgs, widget)
        if ok and type(extra) == "table" and next(extra) then
            args.widgetSettingsHeader = {
                order = 19,
                type = "header",
                name = widget.label or "Widget settings",
            }
            local BASE = 20
            for key, opt in pairs(extra) do
                if type(opt) == "table" then
                    -- Add BASE so ordering becomes 20+, 21, 22, ...
                    -- (preserves widget-internal order but always
                    -- sits below our section headers).
                    opt.order = (opt.order or 0) + BASE
                    args[key] = opt
                end
            end
        end
    end

    local displayName = WidgetDisplayName(id, widget)

    -- Infer the widget's source/category. If the registering addon set
    -- `widget.source` explicitly that wins; otherwise we look at the
    -- ID prefix (the convention across the Baz Suite). The Widgets
    -- list panel groups by this, with a collapsible header per source.
    local source = widget.source
    if not source and type(id) == "string" then
        if id:sub(1, 10) == "bazdrawer_" then
            source = "Drawers"
        elseif id:sub(1, 11) == "bazwidgets_" then
            source = "BazWidgets"
        elseif id:sub(1, 8) == "bazcore_" then
            source = "BazUI"
        elseif id:sub(1, 10) == "bazbroker_" then
            source = "LibDataBroker"
        end
    end
    source = source or "Other"

    return {
        order = index,
        type = "group",
        name = displayName,
        source = source,
        args = args,
        toggle = {
            name = "Enabled",
            get = function() return addon:IsWidgetEnabled(id) end,
            set = function(_, val)
                if addon.WidgetHost and addon.WidgetHost.SetWidgetEnabled then
                    addon.WidgetHost:SetWidgetEnabled(id, val)
                else
                    addon:SetWidgetEnabled(id, val)
                end
                Refresh(PAGE_WIDGETS)
            end,
        },
    }
end

-- Returns EVERY registered widget (dockable + dormant), regardless of
-- which drawer they're in. Used by the Widgets settings page so the
-- user can configure any widget's per-widget settings even if it's
-- not currently docked in their active drawer.
local function GetAllRegisteredWidgets()
    local result = {}
    local seen = {}

    local dockable = BazUI.GetDockableWidgets and BazUI:GetDockableWidgets() or {}
    for _, w in ipairs(dockable) do
        result[#result + 1] = w
        seen[w.id] = true
    end

    local LBW = BazUI.Widgets
    if LBW and LBW.dormant then
        for id, entry in pairs(LBW.dormant) do
            if not seen[id] and entry.widget then
                result[#result + 1] = entry.widget
                seen[id] = true
            end
        end
    end

    -- Sort by user's saved widget order, falling back to ID for ties
    table.sort(result, function(a, b)
        local oa = addon:GetWidgetOrder(a.id) or 10000
        local ob = addon:GetWidgetOrder(b.id) or 10000
        if oa == ob then return (a.id or "") < (b.id or "") end
        return oa < ob
    end)

    return result
end

local function GetWidgetsOptionsTable()
    local sorted = GetAllRegisteredWidgets()

    local widgetArgs = {}
    for i, widget in ipairs(sorted) do
        widgetArgs["widget_" .. widget.id] = BuildWidgetGroup(widget, i)
    end

    return {
        name = "Widgets",
        type = "group",
        args = {
            widgets = {
                order = 1,
                type = "group",
                name = "",
                pickerLabel = "Widget",
                emptyText = "No widgets have registered yet.",
                args = widgetArgs,
            },
        },
    }
end

---------------------------------------------------------------------------
-- Drawers subcategory (create/manage/configure drawer tabs)
---------------------------------------------------------------------------

local function DrawerIcon(drawerDef)
    return drawerDef.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function BuildDrawerGroup(drawerDef, drawerId, index)
    local allWidgets = BazUI.GetDockableWidgets and BazUI:GetDockableWidgets() or {}

    local args = {
        identityHeader = { order = 1, type = "header", name = "Tab" },
        labelInput = {
            order = 2, type = "input", name = "Name",
            desc = "Shown in the tab's tooltip.",
            get = function()
                local def = addon:GetDrawer(drawerId)
                return def and def.label or ""
            end,
            set = function(_, val)
                addon:RenameDrawer(drawerId, val)
                Refresh(PAGE_DRAWERS)
            end,
        },
        chooseIcon = {
            order = 3, type = "execute", name = "Choose icon",
            desc = "|T" .. DrawerIcon(drawerDef) .. ":18:18:0:0:64:64:4:60:4:60|t  The icon on this drawer's tab.",
            func = function()
                BazUI:ShowIconPicker(function(iconId)
                    local drawers = addon:GetSetting("drawers") or {}
                    if drawers[drawerId] then
                        drawers[drawerId].icon = iconId
                        addon:SetSetting("drawers", drawers)
                        if addon.Drawer and addon.Drawer.RefreshTabs then
                            addon.Drawer:RefreshTabs()
                        end
                        Refresh(PAGE_DRAWERS)
                    end
                end, drawerDef.icon)
            end,
        },

        widgetHeader = { order = 10, type = "header", name = "Widgets in this drawer" },
    }

    -- One switch per enabled widget. Widgets turned off on the Widgets
    -- page can't appear anywhere, so they are left out here.
    local list = {}
    local seen = {}
    for _, w in ipairs(allWidgets) do
        if addon:IsWidgetEnabled(w.id) then
            list[#list + 1] = { id = w.id, widget = w }
            seen[w.id] = true
        end
    end
    local LBW = BazUI.Widgets
    if LBW and LBW.dormant then
        for id, entry in pairs(LBW.dormant) do
            if not seen[id] and addon:IsWidgetEnabled(id) then
                list[#list + 1] = { id = id, widget = entry.widget }
            end
        end
    end
    table.sort(list, function(a, b)
        local la = a.widget and a.widget.label or a.id
        local lb = b.widget and b.widget.label or b.id
        return la < lb
    end)

    for i, entry in ipairs(list) do
        local wid = entry.id
        args["widget_" .. wid] = {
            order = 10 + i,
            type = "toggle",
            name = WidgetDisplayName(wid, entry.widget),
            get = function() return addon:IsWidgetInDrawer(drawerId, wid) end,
            set = function(_, val)
                if val then
                    addon:AddWidgetToDrawer(drawerId, wid)
                else
                    addon:RemoveWidgetFromDrawer(drawerId, wid)
                end
            end,
        }
    end
    if #list == 0 then
        args.noWidgets = {
            order = 11, type = "description",
            name = "Every widget is turned off. Enable some on the Widgets page first.",
        }
    end

    return {
        order = index,
        type = "group",
        name = drawerDef.label or drawerId,
        args = args,
        _drawerId = drawerId,
    }
end

local function DrawerCount()
    local n = 0
    for _ in pairs(addon:GetSetting("drawers") or {}) do n = n + 1 end
    return n
end

local function GetDrawersOptionsTable()
    local sorted = addon:GetSortedDrawers()
    local drawerArgs = {}

    for i, entry in ipairs(sorted) do
        drawerArgs["drawer_" .. entry.id] = BuildDrawerGroup(entry.def, entry.id, i)
    end

    return {
        name = "Drawers",
        type = "group",
        args = {
            createDrawer = {
                order = 0,
                type = "execute",
                name = "New drawer",
                func = function()
                    local id = "drawer_" .. time()
                    addon:CreateDrawer(id, "New Drawer")
                    addon:SetActiveDrawer(id)
                    Refresh(PAGE_DRAWERS)
                end,
            },
            drawers = {
                order = 1,
                type = "group",
                name = "",
                pickerLabel = "Drawer",
                emptyText = "No drawers yet. Click New drawer to make one.",
                args = drawerArgs,
                itemActions = {
                    {
                        name = "Delete", style = "danger",
                        confirm = true, confirmTitle = "Delete drawer?",
                        confirmText = function(item)
                            return string.format("Delete the %s drawer? Its widgets stay registered and can go in other drawers.",
                                item and item.name or "selected")
                        end,
                        confirmStyle = "destructive", confirmAcceptLabel = "Delete", confirmCancelLabel = "Cancel",
                        disabled = function() return DrawerCount() <= 1 end,
                        func = function(item)
                            addon:DeleteDrawer(item._drawerId)
                            Refresh(PAGE_DRAWERS)
                        end,
                    },
                },
            },
        },
    }
end

---------------------------------------------------------------------------
-- Register pages
---------------------------------------------------------------------------

BazUI:QueueForModule("Drawers", function()
    if not BazUI.RegisterOptionsTable then return end

    -- The module entry itself never renders: its pages are tabs.
    BazUI:RegisterOptionsTable("Drawers", function()
        return { name = "Drawers", type = "group", args = {} }
    end)
    BazUI:AddToSettings("Drawers", "Drawers")

    BazUI:RegisterOptionsTable(PAGE_GENERAL, GetSettingsOptionsTable)
    BazUI:AddToSettings(PAGE_GENERAL, "General", "Drawers")

    BazUI:RegisterOptionsTable(PAGE_DRAWERS, GetDrawersOptionsTable)
    BazUI:AddToSettings(PAGE_DRAWERS, "Drawers", "Drawers", 10)

    BazUI:RegisterOptionsTable(PAGE_WIDGETS, GetWidgetsOptionsTable)
    BazUI:AddToSettings(PAGE_WIDGETS, "Widgets", "Drawers", 20)

    if addon.Broker and addon.Broker.GetOptionsTable then
        BazUI:RegisterOptionsTable("BazUIDrawer-Broker", addon.Broker.GetOptionsTable)
        BazUI:AddToSettings("BazUIDrawer-Broker", "Broker Feeds", "Drawers", 30)
    end
end)
