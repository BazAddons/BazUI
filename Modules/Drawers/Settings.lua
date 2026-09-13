-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Settings
-- Landing page + Settings subcategory + Widgets subcategory.
-- The Widgets subcategory uses BazUI's list/detail options pattern
-- (same shape BazBars uses for per-bar options).

local addon = BazUI:GetModule("Drawers")

---------------------------------------------------------------------------
-- General settings (side + width + toggle)
---------------------------------------------------------------------------

local function GetSettingsOptionsTable()
    return {
        name = "Settings",
        type = "group",
        args = {
            intro = {
                order = 0.1,
                type = "lead",
                text = "Configure how the drawer looks and behaves on screen. Settings here apply to the active drawer.",
            },
            layoutHeader = {
                order = 1,
                type = "header",
                name = "Layout",
            },
            side = {
                order = 2,
                type = "select",
                name = "Screen Side",
                desc = "Which edge of the screen the drawer slides out from.",
                values = { right = "Right", left = "Left" },
                get = function() return addon:GetSetting("side") or "right" end,
                set = function(_, val)
                    if addon.Drawer then addon.Drawer:SetSide(val) end
                end,
            },
            width = {
                order = 3,
                type = "range",
                name = "Drawer Width",
                desc = "Width of the drawer. Docked widgets scale proportionally to fill this width.",
                min = (addon.Drawer and addon.Drawer.MIN_WIDTH) or 120,
                max = (addon.Drawer and addon.Drawer.MAX_WIDTH) or 400,
                step = 2,
                get = function()
                    return addon:GetSetting("width")
                        or (addon.Drawer and addon.Drawer.DEFAULT_WIDTH)
                        or 222
                end,
                set = function(_, val)
                    if addon.Drawer then addon.Drawer:SetWidth(val) end
                end,
            },
            -- "Behavior" section dropped - "Toggle Drawer" wasn't a
            -- setting but a one-shot action, available via /bwd toggle.

            appearanceHeader = {
                order = 20,
                type = "header",
                name = "Appearance",
            },
            appearanceLockNote = {
                order = 20.5,
                type = "note",
                style = "info",
                text = "Appearance and fade settings are disabled while the drawer is locked. Click the padlock on the drawer's bottom bar to unlock.",
            },
            backgroundOpacity = {
                order = 21,
                type = "range",
                name = "Background Opacity",
                desc = "Alpha of the drawer's backdrop fill (the dark panel colour).",
                min = 0, max = 1, step = 0.05,
                get = function() return addon:GetSetting("backgroundOpacity") or 0.9 end,
                set = function(_, val)
                    addon:SetSetting("backgroundOpacity", val)
                    if addon.Drawer then addon.Drawer:ApplyAppearance() end
                end,
                disabled = function() return addon:GetSetting("locked") and true or false end,
            },
            frameOpacity = {
                order = 22,
                type = "range",
                name = "Frame Opacity",
                desc = "Maximum alpha of the drawer's border and tab chrome when fully visible. Docked widgets always stay at full opacity.",
                min = 0.2, max = 1, step = 0.05,
                get = function() return addon:GetSetting("frameOpacity") or 1.0 end,
                set = function(_, val)
                    addon:SetSetting("frameOpacity", val)
                    if addon.Drawer then addon.Drawer:EvaluateFade(true) end
                end,
                disabled = function() return addon:GetSetting("locked") and true or false end,
            },

            fadingHeader = {
                order = 30,
                type = "header",
                name = "Fading",
            },
            fadingIntro = {
                order = 30.5,
                type = "note",
                style = "tip",
                text = "Set Faded Opacity to 0 for a fully invisible drawer when you're not hovering it. Widget content always stays at full opacity, even while the chrome is faded.",
            },
            fadeEnabled = {
                order = 31,
                type = "toggle",
                name = "Enable Fade",
                desc = "Fade the drawer's backdrop and tab when the mouse isn't over it. Docked widgets stay at full opacity so their content is always readable.",
                get = function() return addon:GetSetting("fadeEnabled") ~= false end,
                set = function(_, val)
                    addon:SetSetting("fadeEnabled", val)
                    if addon.Drawer then addon.Drawer:EvaluateFade(true) end
                end,
                disabled = function() return addon:GetSetting("locked") and true or false end,
            },
            fadedOpacity = {
                order = 32,
                type = "range",
                name = "Faded Opacity",
                desc = "Target alpha when the drawer is faded out.",
                min = 0, max = 1, step = 0.05,
                get = function() return addon:GetSetting("fadedOpacity") or 0.3 end,
                set = function(_, val)
                    addon:SetSetting("fadedOpacity", val)
                    if addon.Drawer then addon.Drawer:EvaluateFade(true) end
                end,
                disabled = function() return addon:GetSetting("locked") and true or false end,
            },
            fadeDelay = {
                order = 33,
                type = "range",
                name = "Fade Delay",
                desc = "Seconds to wait after the mouse leaves before starting to fade.",
                min = 0, max = 5, step = 0.1,
                get = function() return addon:GetSetting("fadeDelay") or 1.0 end,
                set = function(_, val) addon:SetSetting("fadeDelay", val) end,
                disabled = function() return addon:GetSetting("locked") and true or false end,
            },
            fadeDuration = {
                order = 34,
                type = "range",
                name = "Fade Duration",
                desc = "Length of the fade animation in seconds.",
                min = 0.05, max = 2, step = 0.05,
                get = function() return addon:GetSetting("fadeDuration") or 0.3 end,
                set = function(_, val) addon:SetSetting("fadeDuration", val) end,
                disabled = function() return addon:GetSetting("locked") and true or false end,
            },
            edgeRevealPx = {
                order = 35,
                type = "range",
                name = "Edge Reveal Distance",
                desc = "Width of the invisible hot zone along the active screen edge. Moving the cursor anywhere inside this strip reveals the tab when the drawer is closed.",
                min = 2, max = 50, step = 1,
                get = function() return addon:GetSetting("edgeRevealPx") or 8 end,
                set = function(_, val)
                    addon:SetSetting("edgeRevealPx", val)
                    if addon.Drawer and addon.Drawer.ApplyEdgeHotZone then
                        addon.Drawer:ApplyEdgeHotZone()
                    end
                end,
                disabled = function() return addon:GetSetting("locked") and true or false end,
            },
            fadeTabWhenClosed = {
                order = 36,
                type = "toggle",
                name = "Fade Tab When Closed",
                desc = "When off, the tab stays at full opacity while the drawer is collapsed (edge reveal no longer needed).",
                get = function() return addon:GetSetting("fadeTabWhenClosed") ~= false end,
                set = function(_, val)
                    addon:SetSetting("fadeTabWhenClosed", val)
                    if addon.Drawer then addon.Drawer:EvaluateFade(true) end
                end,
                disabled = function() return addon:GetSetting("locked") and true or false end,
            },
            alwaysShowInCombat = {
                order = 37,
                type = "toggle",
                name = "Always Show In Combat",
                desc = "Force the drawer to full opacity whenever you're in combat, ignoring fade settings.",
                get = function() return addon:GetSetting("disableFadeInCombat") and true or false end,
                set = function(_, val)
                    addon:SetSetting("disableFadeInCombat", val)
                    if addon.Drawer then addon.Drawer:EvaluateFade(true) end
                end,
                disabled = function() return addon:GetSetting("locked") and true or false end,
            },
        },
    }
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

local function BuildWidgetGroup(widget, index, total)
    local id = widget.id
    local args = {
        enabled = {
            order = 0.05,
            type = "toggle",
            name = "Enabled",
            desc = "Turn this widget on or off entirely. A disabled widget is hidden everywhere - not docked in any drawer, not floating, and any side-effects (e.g. durability-frame override for Repair) are restored to defaults.",
            get = function() return addon:IsWidgetEnabled(id) end,
            set = function(_, val)
                if addon.WidgetHost and addon.WidgetHost.SetWidgetEnabled then
                    addon.WidgetHost:SetWidgetEnabled(id, val)
                else
                    addon:SetWidgetEnabled(id, val)
                end
            end,
        },
        enabledNote = {
            order = 0.06,
            type = "note",
            style = "info",
            text = "Disabling a widget hides it everywhere - no drawer slot, no floating frame. Any side-effects (like the Repair widget's durability-frame override) are also restored to Blizzard defaults.",
        },
        -- Move Up/Down buttons removed - ordering is handled by
        -- drag-to-reorder on the widget's title bar inside the drawer
        -- (hold half a second > drag). Having the buttons here was
        -- misleading since the order is global, not per-drawer.
        dockingHeader = { order = 1, type = "header", name = "Docking" },
        floating = {
            order = 2,
            type = "toggle",
            name = "Floating",
            desc = "Detach this widget from the drawer and let it float freely. Use Edit Mode to drag the detached widget to wherever you want.",
            get = function() return addon:IsWidgetFloating(id) end,
            set = function(_, val)
                if addon.WidgetHost and addon.WidgetHost.SetWidgetFloating then
                    addon.WidgetHost:SetWidgetFloating(id, val)
                end
            end,
        },
        collapsed = {
            order = 3,
            type = "toggle",
            name = "Collapsed",
            desc = "Hide the widget's content, leaving only its title bar visible in the drawer.",
            get = function() return addon:IsWidgetCollapsed(id) end,
            set = function(_, val)
                addon:SetWidgetCollapsed(id, val)
                if addon.WidgetHost then addon.WidgetHost:Reflow() end
            end,
            disabled = function() return addon:IsWidgetFloating(id) end,
        },
        dockedToBottom = {
            order = 4,
            type = "toggle",
            name = "Dock to Bottom",
            desc = "Pin this widget to the drawer's bottom edge. Bottom-docked widgets stack upward from the drawer bottom and grow toward the middle as their content extends, instead of pushing the widgets below them down.",
            get = function() return addon:IsWidgetDockedToBottom(id) end,
            set = function(_, val)
                addon:SetWidgetDockedToBottom(id, val)
                if addon.WidgetHost then addon.WidgetHost:Reflow() end
            end,
            disabled = function() return addon:IsWidgetFloating(id) end,
        },

        fadeHeader = { order = 5, type = "header", name = "Fading" },
        fadeTitleBar = {
            order = 6,
            type = "toggle",
            name = "Fade Title Bar",
            desc = "Fade this widget's title bar with the drawer chrome.",
            get = function()
                return addon:GetWidgetEffectiveSetting(id, "fadeTitleBar", true) ~= false
            end,
            set = function(_, val)
                addon:SetWidgetSetting(id, "fadeTitleBar", val)
                if addon.Drawer then addon.Drawer:EvaluateFade(true) end
            end,
            disabled = function()
                local o = addon:GetSetting("widgetGlobalOverrides")
                return o and o.fadeTitleBar and o.fadeTitleBar.enabled or false
            end,
        },
        fadeBackground = {
            order = 7,
            type = "toggle",
            name = "Fade Background",
            desc = "Fade this widget's background with the drawer chrome.",
            get = function()
                return addon:GetWidgetEffectiveSetting(id, "fadeBackground", true) ~= false
            end,
            set = function(_, val)
                addon:SetWidgetSetting(id, "fadeBackground", val)
                if addon.Drawer then addon.Drawer:EvaluateFade(true) end
            end,
            disabled = function()
                local o = addon:GetSetting("widgetGlobalOverrides")
                return o and o.fadeBackground and o.fadeBackground.enabled or false
            end,
        },

    }

    -- Widgets can supply their own options via widget:GetOptionsArgs().
    -- Their internal order values (often 1..N) would collide with the
    -- top-level Docking/Fading order slots, so we shift them all into
    -- the 20+ range - preserving the widget's own relative ordering
    -- while guaranteeing they sit after the "Widget Settings" header.
    if widget.GetOptionsArgs then
        local ok, extra = pcall(widget.GetOptionsArgs, widget)
        if ok and type(extra) == "table" and next(extra) then
            args.widgetSettingsHeader = {
                order = 19,
                type = "header",
                name = "Widget Settings",
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
        desc = "Configure " .. (widget.label or id),
        source = source,
        args = args,
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
        widgetArgs["widget_" .. widget.id] = BuildWidgetGroup(widget, i, #sorted)
    end

    return {
        name = "Widgets",
        type = "group",
        args = {
            intro = {
                order = -1,
                type = "lead",
                text = "Per-widget settings for every widget currently registered with BazUI Drawers. Use the Enabled toggle to turn a widget off entirely; use the Drawers page to choose which drawer(s) each widget appears in.",
            },
            widgets = {
                order = 1,
                type = "group",
                name = "",
                args = widgetArgs,
            },
        },
    }
end

---------------------------------------------------------------------------
-- Global Options (applies to all widgets at once)
---------------------------------------------------------------------------

local function GetGlobalOptionsTable()
    local page = BazUI:CreateGlobalOptionsPage("Drawers", {
        getOverrides = function() return addon:GetGlobalOverrides() end,
        setOverride = function(key, field, value)
            addon:SetGlobalOverride(key, field, value)
        end,
        overrides = {
            { key = "fadeTitleBar",   label = "Fade Title Bar",   type = "toggle", default = true },
            { key = "fadeBackground", label = "Fade Background",  type = "toggle", default = true },
        },
    })

    -- Prepend a lead + note explaining how overrides cascade. The builder
    -- already includes its own boilerplate description; we slot our lead
    -- in above it so the page has a clear intro.
    page.args = page.args or {}
    page.args.intro = {
        order = -1,
        type = "lead",
        text = "Overrides set here apply to every widget at once, regardless of each widget's individual setting.",
    }
    page.args.introNote = {
        order = -0.5,
        type = "note",
        style = "info",
        text = "Enable a specific override to force its value across all widgets. Disable the override to return each widget to its own per-widget setting.",
    }
    return page
end

---------------------------------------------------------------------------
-- Drawers subcategory (create/manage/configure drawer tabs)
---------------------------------------------------------------------------

local AUTO_SWITCH_OPTIONS = {
    { value = "",              label = "None (manual only)" },
    { value = "openWorld",     label = "Open World / Questing" },
    { value = "dungeon",      label = "Dungeon (5-man)" },
    { value = "raid",         label = "Raid" },
    { value = "challengeMode", label = "Mythic+ (Challenge Mode)" },
    { value = "delve",        label = "Delve" },
    { value = "battleground",  label = "Battleground" },
    { value = "arena",        label = "Arena" },
}

local function BuildDrawerGroup(drawerDef, drawerId, index, total)
    local allWidgets = BazUI.GetDockableWidgets and BazUI:GetDockableWidgets() or {}

    -- Build auto-switch dropdown values
    local autoValues = {}
    for _, opt in ipairs(AUTO_SWITCH_OPTIONS) do
        autoValues[opt.value] = opt.label
    end

    local args = {
        identityHeader = {
            order = 0,
            type = "header",
            name = "Identity",
        },
        labelInput = {
            order = 1,
            type = "input",
            name = "Drawer Name",
            desc = "Display name shown in the tab tooltip.",
            get = function()
                local def = addon:GetDrawer(drawerId)
                return def and def.label or ""
            end,
            set = function(_, val)
                addon:RenameDrawer(drawerId, val)
                BazUI:RefreshOptions("BazUIDrawer-Drawers")
            end,
        },
        labelSpacer = {
            order = 1.5,
            type = "spacer",
            height = 8,
        },
        chooseIcon = {
            order = 2,
            type = "execute",
            name = "Choose Icon",
            desc = "Pick an icon for this drawer's tab.",
            width = "half",
            func = function()
                BazUI:ShowIconPicker(function(iconId)
                    local drawers = addon:GetSetting("drawers") or {}
                    if drawers[drawerId] then
                        drawers[drawerId].icon = iconId
                        addon:SetSetting("drawers", drawers)
                        if addon.Drawer and addon.Drawer.RefreshTabs then
                            addon.Drawer:RefreshTabs()
                        end
                        BazUI:RefreshOptions("BazUIDrawer-Drawers")
                    end
                end, drawerDef.icon)
            end,
        },
        iconPreview = {
            order = 2.5,
            type = "execute",
            name = "|T" .. (drawerDef.icon or "Interface\\Icons\\INV_Misc_QuestionMark") .. ":32:32|t",
            width = "half",
            borderless = true,
            func = function() end,  -- not clickable; Choose Icon button handles changes
        },

        autoHeader = { order = 10, type = "header", name = "Auto-Switch" },
        autoSwitchEnabled = {
            order = 11,
            type = "toggle",
            name = "Enable Auto-Switch",
            desc = "Automatically switch to this drawer when entering the selected game context.",
            get = function()
                local def = addon:GetDrawer(drawerId)
                return def and def.autoSwitchEnabled or false
            end,
            set = function(_, val)
                local drawers = addon:GetSetting("drawers") or {}
                if drawers[drawerId] then
                    drawers[drawerId].autoSwitchEnabled = val
                    addon:SetSetting("drawers", drawers)
                end
            end,
        },
        autoSwitchTrigger = {
            order = 12,
            type = "select",
            name = "Trigger",
            desc = "Game context that activates this drawer.",
            values = autoValues,
            get = function()
                local def = addon:GetDrawer(drawerId)
                return def and def.autoSwitch or ""
            end,
            set = function(_, val)
                local drawers = addon:GetSetting("drawers") or {}
                if drawers[drawerId] then
                    drawers[drawerId].autoSwitch = (val ~= "") and val or nil
                    addon:SetSetting("drawers", drawers)
                end
            end,
            disabled = function()
                local def = addon:GetDrawer(drawerId)
                return not (def and def.autoSwitchEnabled)
            end,
        },

        widgetHeader = { order = 20, type = "header", name = "Widgets" },
        widgetDesc = {
            order = 21,
            type = "note",
            style = "info",
            text = "Check which widgets appear in this drawer. A widget can be in multiple drawers.",
        },
    }

    -- Add a toggle for each available widget. Globally-disabled widgets
    -- (toggled off on the Widgets subcategory) are filtered out entirely
    -- so the per-drawer list only shows the widgets that can actually
    -- appear anywhere - matches the user expectation that the drawer
    -- "available widgets" reflects the enabled set, not the registered
    -- set.
    local widgetOrder = 22
    for _, w in ipairs(allWidgets) do
        local wid = w.id
        if addon:IsWidgetEnabled(wid) then
            args["widget_" .. wid] = {
                order = widgetOrder,
                type = "toggle",
                name = WidgetDisplayName(wid, w),
                get = function()
                    return addon:IsWidgetInDrawer(drawerId, wid)
                end,
                set = function(_, val)
                    if val then
                        addon:AddWidgetToDrawer(drawerId, wid)
                    else
                        addon:RemoveWidgetFromDrawer(drawerId, wid)
                    end
                    -- No RefreshOptions here: the checkbox visual updates
                    -- natively, and the drawer reflows via AddWidgetToDrawer.
                    -- Avoiding the rebuild preserves scroll position.
                end,
            }
            widgetOrder = widgetOrder + 1
        end
    end

    -- Also include dormant widgets (still filtered by global enable).
    local LBW = BazUI.Widgets
    if LBW and LBW.dormant then
        local seen = {}
        for _, w in ipairs(allWidgets) do seen[w.id] = true end
        for id, entry in pairs(LBW.dormant) do
            if not seen[id] and addon:IsWidgetEnabled(id) then
                local wid = id
                args["widget_" .. wid] = {
                    order = widgetOrder,
                    type = "toggle",
                    name = WidgetDisplayName(wid, entry.widget),
                    get = function()
                        return addon:IsWidgetInDrawer(drawerId, wid)
                    end,
                    set = function(_, val)
                        if val then
                            addon:AddWidgetToDrawer(drawerId, wid)
                        else
                            addon:RemoveWidgetFromDrawer(drawerId, wid)
                        end
                    end,
                }
                widgetOrder = widgetOrder + 1
            end
        end
    end

    -- Delete button (can't delete last drawer)
    local drawerCount = 0
    local drawers = addon:GetSetting("drawers") or {}
    for _ in pairs(drawers) do drawerCount = drawerCount + 1 end

    args.deleteHeader = { order = 100, type = "header", name = "Delete" }
    args.deleteNote = {
        order = 100.5,
        type = "note",
        style = "danger",
        text = "Permanently removes this drawer tab. The widgets it contained are unaffected - they stay registered and can be assigned to other drawers.",
    }
    args.deleteDrawer = {
        order = 101,
        type = "execute",
        name = "Delete This Drawer",
        desc = "Permanently remove this drawer tab.",
        func = function()
            addon:DeleteDrawer(drawerId)
            BazUI:RefreshOptions("BazUIDrawer-Drawers")
        end,
        disabled = function() return drawerCount <= 1 end,
        confirm = true,
        confirmText = "Are you sure you want to delete the '" .. (drawerDef.label or drawerId) .. "' drawer?",
    }

    return {
        order = index,
        type = "group",
        name = drawerDef.label or drawerId,
        args = args,
    }
end

local function GetDrawersOptionsTable()
    local sorted = addon:GetSortedDrawers()
    local drawerArgs = {}

    for i, entry in ipairs(sorted) do
        drawerArgs["drawer_" .. entry.id] = BuildDrawerGroup(entry.def, entry.id, i, #sorted)
    end

    return {
        name = "Drawers",
        type = "group",
        args = {
            intro = {
                order = -1,
                type = "lead",
                text = "Each drawer is its own preset of widgets, width, fade, and layout. Run multiple drawers for different game modes (questing / M+ / PvP) and switch between them via the tabs at the top of the drawer.",
            },
            createDrawer = {
                order = 0,
                type = "execute",
                name = "Create New Drawer",
                func = function()
                    -- Generate a unique ID
                    local id = "drawer_" .. time()
                    addon:CreateDrawer(id, "New Drawer")
                    addon:SetActiveDrawer(id)
                    BazUI:RefreshOptions("BazUIDrawer-Drawers")
                end,
            },
            drawers = {
                order = 1,
                type = "group",
                name = "",
                args = drawerArgs,
            },
        },
    }
end

---------------------------------------------------------------------------
-- Register pages
---------------------------------------------------------------------------

BazUI:QueueForLogin(function()
    if not BazUI.RegisterOptionsTable then return end

    -- Landing page (user manual)
    BazUI:RegisterOptionsTable("Drawers", function()
        return BazUI:CreateLandingPage("Drawers", {
            subtitle = "Slide-out widget drawer for the Baz Suite",

            description =
                "Drawers is a full-height slide-out panel that docks " ..
                "to either edge of your screen and hosts a vertical stack " ..
                "of widgets: Quest Tracker, Minimap, Minimap Buttons, " ..
                "Info Bar and Zone Text.\n\n" ..

                "The drawer is built around three concepts:\n" ..
                "* A persistent slide-out panel that fades to invisible " ..
                "when you're not interacting with it and pops back on " ..
                "hover.\n" ..
                "* A pull-tab handle on the active edge for one-click " ..
                "open/close, plus an invisible edge hot zone that re-" ..
                "reveals the tab when collapsed.\n" ..
                "* A widget host that uniformly scales each widget to " ..
                "the drawer's width and stacks them vertically with " ..
                "collapsible, draggable title bars.\n\n" ..

                "Widgets come from BazUI's own modules and appear in the " ..
                "drawer automatically. Widgets can also be dormant - they " ..
                "register and unregister themselves based on game state.",

            features =
                "DRAWER\n" ..
                "* Slide-out side panel with a metal pull-tab handle.\n" ..
                "* Switchable side (left or right) with automatic flip.\n" ..
                "* Configurable width with live re-scaling of all widgets.\n" ..
                "* Edge hot zone for easy tab re-reveal when collapsed.\n" ..
                "* Background and frame opacity sliders.\n\n" ..

                "FADE SYSTEM\n" ..
                "* Chrome fades as a single unit; widget content stays readable.\n" ..
                "* Configurable delay, duration, and faded opacity (default 0 = invisible).\n" ..
                "* Optional 'force full opacity in combat' mode.\n" ..
                "* Lock icon fades in sync with drawer chrome.\n\n" ..

                "LOCK SYSTEM\n" ..
                "* Padlock icon on the bottom bar (appears on hover, fades with chrome).\n" ..
                "* When locked: drawer stays open, all chrome is hidden, title bars collapse for a tight layout.\n\n" ..

                "WIDGET HOST\n" ..
                "* Per-widget title bars with collapse chevron and live status text.\n" ..
                "* Drag-to-reorder: hold a title bar to grab it (turns green), drag to swap positions.\n" ..
                "* Move Up / Move Down buttons in the settings panel (side by side at top).\n" ..
                "* Floating mode: detach any widget and position it via Edit Mode.\n" ..
                "* Per-widget enable/disable, per-widget settings, and global overrides.\n" ..
                "* Dormant widgets: appear and disappear based on game conditions.\n\n" ..

                "BUILT-IN WIDGETS\n" ..
                "* Zone Text - zone name colored by PVP status.\n" ..
                "* Minimap - reparents the real Blizzard minimap at a fixed scale.\n" ..
                "* Minimap Buttons - adopts LibDBIcon buttons into a tidy grid.\n" ..
                "* Quest Tracker - tracked quests with objectives, quest item buttons and completion text.\n" ..
                "* Info Bar - clock, calendar, and tracking button in one row.",

            guide = {
                {
                    "1. First Look",
                    "On first login the drawer appears on the right edge " ..
                    "with all built-in widgets stacked: Zone, Minimap, " ..
                    "Minimap Buttons, Quest Tracker, and Info " ..
                    "Bar. Hover over the drawer to see it appear, move " ..
                    "away and it fades to invisible. The metal pull-tab " ..
                    "on the drawer edge is your primary control - click " ..
                    "to slide it off-screen, click again to bring it back.",
                },
                {
                    "2. Opening and Closing",
                    "Click the pull-tab to toggle the drawer. When " ..
                    "collapsed, move your cursor to the screen edge and " ..
                    "the tab fades back into view. Slash commands: " ..
                    "/bwd toggle, /bwd show, or /bwd hide.",
                },
                {
                    "3. Choosing a Side and Width",
                    "Settings > Layout > Side switches left/right. " ..
                    "Width scales all docked widgets proportionally - " ..
                    "wider drawer means bigger widgets, not empty space.",
                },
                {
                    "4. Fading",
                    "The drawer chrome (backdrop, border, tab, bottom bar) " ..
                    "fades as a unit. Widget content stays at full opacity. " ..
                    "Default faded opacity is 0 (invisible). Tune via " ..
                    "Settings > Fading: delay, duration, opacity target, " ..
                    "combat override, and tab-when-closed behavior.",
                },
                {
                    "5. The Lock",
                    "Hover the drawer to see the padlock icon on the " ..
                    "bottom bar. Click it to lock. When locked: the " ..
                    "drawer stays open permanently, all chrome is hidden, " ..
                    "title bars collapse for a tight layout, and the lock " ..
                    "icon fades in/out with the same timing as the chrome.",
                },
                {
                    "6. Reordering Widgets",
                    "Two ways to reorder: (1) Hold-and-drag a title bar " ..
                    "in the drawer - hold for half a second until it turns " ..
                    "green, then drag up/down. (2) Use the Move Up / Move " ..
                    "Down buttons at the top of each widget's settings " ..
                    "page. Both methods work for dormant widgets too.",
                },
                {
                    "7. Collapsing Widgets",
                    "Click any title bar to collapse that widget's " ..
                    "content, leaving only the title bar visible. Click " ..
                    "again to expand. State is saved per profile.",
                },
                {
                    "8. Floating a Widget",
                    "On a widget's settings page, check Floating to " ..
                    "detach it from the drawer. It becomes a free-floating " ..
                    "frame you can position via Blizzard's Edit Mode. " ..
                    "Uncheck to dock it back in its saved position.",
                },
                {
                    "9. Dormant Widgets",
                    "Some widgets are dormant - they only appear when " ..
                    "relevant. For example, Dungeon Finder only shows " ..
                    "when you're queued. Dormant widgets are marked with " ..
                    "[D] in the Widgets settings list and can still be " ..
                    "reordered and configured while dormant.",
                },
                {
                    "10. Modules",
                    "Modules lists every registered widget with an on/off " ..
                    "toggle. Disabling a widget removes its slot entirely " ..
                    "and stops its events. Re-enabling restores it.",
                },
                {
                    "11. Global Options",
                    "Global Options lets you set defaults that apply to " ..
                    "all widgets at once (e.g. Fade Title Bar, Fade " ..
                    "Background). Enabled globals override per-widget " ..
                    "settings of the same key.",
                },
                {
                    "12. Troubleshooting",
                    "Drawer gone? Type /bwd show. Widget stuck floating " ..
                    "off-screen? Toggle Floating off and on in its settings. " ..
                    "Fade looks wrong? Hover and unhover to refresh. " ..
                    "Setting won't change? Check if the drawer is locked.",
                },
            },

            commands = {
                { "/bwd toggle", "Open or close the drawer" },
                { "/bwd show",   "Open the drawer" },
                { "/bwd hide",   "Close the drawer" },
            },
        })
    end)
    BazUI:AddToSettings("Drawers", "Drawers")

    -- Settings subcategory
    BazUI:RegisterOptionsTable("BazUIDrawer-Settings", GetSettingsOptionsTable)
    BazUI:AddToSettings("BazUIDrawer-Settings", "General Settings", "Drawers")

    -- Global Options subcategory (per-key overrides across all widgets)
    BazUI:RegisterOptionsTable("BazUIDrawer-GlobalOptions", GetGlobalOptionsTable)
    BazUI:AddToSettings("BazUIDrawer-GlobalOptions", "Global Settings", "Drawers")

    -- Drawers subcategory (create/manage drawer tabs)
    BazUI:RegisterOptionsTable("BazUIDrawer-Drawers", GetDrawersOptionsTable)
    BazUI:AddToSettings("BazUIDrawer-Drawers", "Drawers", "Drawers")

    -- Widgets subcategory (list/detail - same shape as BazBars' Bar Options)
    BazUI:RegisterOptionsTable("BazUIDrawer-Widgets", GetWidgetsOptionsTable)
    BazUI:AddToSettings("BazUIDrawer-Widgets", "Widgets", "Drawers")
    -- Enable/Disable sub-category merged into the Widgets page - each
    -- widget's detail panel now has an "Enabled" toggle at the top.
    -- GetModulesOptionsTable is still defined but no longer exposed
    -- as a separate sidebar entry.
end)
