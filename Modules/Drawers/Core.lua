-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Core
-- Addon lifecycle via BazUI framework
--
-- BazUI Drawers is a slide-out side panel host that other Baz Suite
-- addons can dock widgets into. The visual style mirrors Blizzard's
-- Compact Raid Frame Manager so it feels like a native game UI element.

local MODULE_NAME = "Drawers"

-- Default top-to-bottom order applied to a fresh "default" drawer
-- on first install. Without this, GetSortedWidgets falls back to
-- alphabetical-by-id, which doesn't match the curated layout. Gaps
-- of 10 leave room to slot extra widgets between defaults later.
local DEFAULT_WIDGET_ORDER = {
    bazdrawer_zonetext        = 10,
    bazdrawer_minimap         = 20,
    bazdrawer_minimapbuttons  = 30,
    bazdrawer_questtracker    = 40,
}

local addon
addon = BazUI:RegisterModule(MODULE_NAME, {
    title = "Drawers",
    profiles = true,
    defaults = {
        side = "right",
        width = 222,
        widgetSettings = {},          -- [widgetId] = { [key] = value } for widget-specific options
        widgetGlobalOverrides = {},   -- [key] = { enabled = bool, value = <any> } (BazUI global page)
        widgetFloating = {},          -- [widgetId] = true when detached from the drawer into free Edit Mode
        widgetPositions = {},         -- [widgetId] = { point, relPoint, x, y } for floating widgets
        widgetEnabled = {},           -- [widgetId] = false to disable the widget entirely (default true)
        widgetDockedToBottom = {},    -- [widgetId] = true to dock at the drawer's bottom edge (stacks upward)

        -- Appearance
        backgroundOpacity = 0.9,   -- alpha of the drawer's backdrop fill
        frameOpacity      = 1.0,   -- max alpha of the drawer frame (base for fade)

        -- Fading
        fadeEnabled         = true,
        fadedOpacity        = 0,     -- target alpha when faded out
        fadeDelay           = 1.0,   -- seconds to wait after mouse leaves before starting fade
        fadeDuration        = 0.3,   -- fade animation duration in seconds
        edgeRevealPx        = 8,     -- cursor proximity to active screen edge to reveal tab
        fadeTabWhenClosed   = true,  -- whether the tab fades too when drawer is collapsed
        disableFadeInCombat = false, -- force full opacity while in combat

        -- Lock
        locked = false,

        -- Multi-drawer
        transitionStyle = "instant", -- "instant", "fade", "slide"
        activeDrawer = "default",
        drawers = {},                -- populated by migration on first load
    },

    slash = { "/bwd" },
    commands = {
        toggle = {
            desc = "Toggle the drawer open/closed",
            handler = function()
                if addon.Drawer then addon.Drawer:Toggle() end
            end,
        },
        show = {
            desc = "Open the drawer",
            handler = function()
                if addon.Drawer then addon.Drawer:Expand() end
            end,
        },
        hide = {
            desc = "Close the drawer",
            handler = function()
                if addon.Drawer then addon.Drawer:Collapse() end
            end,
        },
        open = {
            desc = "Open a specific drawer by name",
            usage = "<name>",
            handler = function(args)
                if not args or args == "" then
                    addon:Print("Usage: /bwd open <drawer name>")
                    local sorted = addon:GetSortedDrawers()
                    local names = {}
                    for _, entry in ipairs(sorted) do
                        names[#names + 1] = entry.def.label or entry.id
                    end
                    addon:Print("Available: " .. table.concat(names, ", "))
                    return
                end
                local search = args:lower()
                local sorted = addon:GetSortedDrawers()
                for _, entry in ipairs(sorted) do
                    local label = (entry.def.label or entry.id):lower()
                    if label == search or label:find(search, 1, true) then
                        -- Switch to this drawer and expand
                        addon:SetActiveDrawer(entry.id)
                        if addon.Drawer then
                            addon.Drawer.collapsed = false
                            addon:SetDrawerCollapsed(entry.id, false)
                            addon.Drawer:ApplySide()
                            if addon.Drawer.frame and addon.Drawer.frame.displayFrame then
                                addon.Drawer.frame.displayFrame:Show()
                            end
                            if addon.Drawer._edgeHotZone then
                                addon.Drawer._edgeHotZone:Hide()
                            end
                            if addon.Drawer.EvaluateFade then
                                addon.Drawer:EvaluateFade(true)
                            end
                            addon.Drawer:RefreshTabs()
                        end
                        addon:Print("Switched to drawer: " .. (entry.def.label or entry.id))
                        return
                    end
                end
                addon:Print("No drawer found matching '" .. args .. "'")
            end,
        },
        list = {
            desc = "List all drawers",
            handler = function()
                local sorted = addon:GetSortedDrawers()
                local activeId = addon:GetActiveDrawerId()
                addon:Print("Drawers:")
                for _, entry in ipairs(sorted) do
                    local label = entry.def.label or entry.id
                    local marker = entry.id == activeId and " |cff44dd44(active)|r" or ""
                    addon:Print("  " .. label .. marker)
                end
            end,
        },
    },

    minimap = {
        label = "Drawers",
        icon = 7416769,  -- Suramar Dresser (FileDataID)
    },

    onReady = function(self)
        -- First-run defaults: on a brand-new profile, only the curated
        -- default widgets (Zone, Minimap, Quest Tracker) are enabled.
        -- Existing profiles keep their old permissive behavior.
        if addon.ApplyFirstRunDefaults then addon:ApplyFirstRunDefaults() end

        -- Multi-drawer migration: create "default" drawer from flat settings.
        -- Widget list is set to "*" (all) so it dynamically includes every
        -- registered widget. This avoids timing issues where widgets haven't
        -- registered yet at onReady time.
        local drawers = self:GetSetting("drawers")
        if not drawers or not next(drawers) then
            -- Seed the default drawer's widget order. If the user has
            -- legacy single-drawer order data, preserve it; otherwise
            -- start with the curated default top-to-bottom order.
            local existingOrder = self:GetSetting("widgetOrder")
            local seedOrder
            if existingOrder and next(existingOrder) then
                seedOrder = existingOrder
            else
                seedOrder = {}
                for k, v in pairs(DEFAULT_WIDGET_ORDER) do seedOrder[k] = v end
            end

            self:SetSetting("drawers", {
                default = {
                    label = "Default",
                    icon = "Interface\\Icons\\INV_Misc_Gear_01",
                    order = 1,
                    collapsed = self:GetSetting("collapsed") or false,
                    autoSwitch = nil,
                    autoSwitchEnabled = false,
                    widgets = "*",  -- special: means "all registered widgets"
                    widgetOrder = seedOrder,
                    widgetCollapsed = self:GetSetting("widgetCollapsed") or {},
                },
            })
            self:SetSetting("activeDrawer", "default")
        end

        self:SetupDrawer()
    end,
})

function addon:SetupDrawer()
    if not self.Drawer then return end
    self.Drawer:Build()

    -- Restore saved collapsed state from the active drawer
    local drawer = self:GetActiveDrawerDef()
    if drawer and drawer.collapsed then
        self.Drawer:Collapse()
    else
        self.Drawer:Expand()
    end
end

---------------------------------------------------------------------------
-- Multi-drawer API
--
-- Each drawer has its own widget assignment, order, and collapsed states.
-- Global settings (side, width, fade, lock) are shared across all drawers.
---------------------------------------------------------------------------

function addon:GetActiveDrawerId()
    return self:GetSetting("activeDrawer") or "default"
end

function addon:GetActiveDrawerDef()
    local drawers = self:GetSetting("drawers") or {}
    return drawers[self:GetActiveDrawerId()]
end

function addon:GetDrawers()
    return self:GetSetting("drawers") or {}
end

function addon:GetDrawer(id)
    local drawers = self:GetSetting("drawers") or {}
    return drawers[id]
end

function addon:GetSortedDrawers()
    local drawers = self:GetSetting("drawers") or {}
    local sorted = {}
    for id, def in pairs(drawers) do
        sorted[#sorted + 1] = { id = id, def = def }
    end
    table.sort(sorted, function(a, b)
        return (a.def.order or 100) < (b.def.order or 100)
    end)
    return sorted
end

function addon:SetActiveDrawer(id)
    local drawers = self:GetSetting("drawers") or {}
    if not drawers[id] then return end
    self:SetSetting("activeDrawer", id)
    if self.WidgetHost and self.WidgetHost.Reflow then
        self.WidgetHost:Reflow()
    end
    if self.Drawer and self.Drawer.RefreshTabs then
        self.Drawer:RefreshTabs()
    end
end

function addon:CreateDrawer(id, label, icon)
    local drawers = self:GetSetting("drawers") or {}
    if drawers[id] then return end
    -- Find the next order number
    local maxOrder = 0
    for _, def in pairs(drawers) do
        if (def.order or 0) > maxOrder then maxOrder = def.order end
    end
    drawers[id] = {
        label = label or id,
        icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        order = maxOrder + 1,
        collapsed = true,
        autoSwitch = nil,
        autoSwitchEnabled = false,
        widgets = {},
        widgetOrder = {},
        widgetCollapsed = {},
    }
    self:SetSetting("drawers", drawers)
    if self.Drawer and self.Drawer.RefreshTabs then
        self.Drawer:RefreshTabs()
    end
end

function addon:DeleteDrawer(id)
    local drawers = self:GetSetting("drawers") or {}
    -- Can't delete the last drawer
    local count = 0
    for _ in pairs(drawers) do count = count + 1 end
    if count <= 1 then return end
    drawers[id] = nil
    self:SetSetting("drawers", drawers)
    -- If we deleted the active drawer, switch to the first remaining one
    if self:GetActiveDrawerId() == id then
        local remainingId = next(drawers)
        if remainingId then self:SetActiveDrawer(remainingId) end
    end
    if self.Drawer and self.Drawer.RefreshTabs then
        self.Drawer:RefreshTabs()
    end
end

function addon:RenameDrawer(id, label)
    local drawers = self:GetSetting("drawers") or {}
    if not drawers[id] then return end
    drawers[id].label = label
    self:SetSetting("drawers", drawers)
    if self.Drawer and self.Drawer.RefreshTabs then
        self.Drawer:RefreshTabs()
    end
end

function addon:IsWidgetInDrawer(drawerId, widgetId)
    local drawers = self:GetSetting("drawers") or {}
    local def = drawers[drawerId]
    if not def or not def.widgets then return false end
    if def.widgets == "*" then return true end
    for _, wid in ipairs(def.widgets) do
        if wid == widgetId then return true end
    end
    return false
end

function addon:AddWidgetToDrawer(drawerId, widgetId)
    local drawers = self:GetSetting("drawers") or {}
    local def = drawers[drawerId]
    if not def then return end
    def.widgets = def.widgets or {}
    -- Don't add duplicates
    for _, wid in ipairs(def.widgets) do
        if wid == widgetId then return end
    end
    def.widgets[#def.widgets + 1] = widgetId
    self:SetSetting("drawers", drawers)
    if drawerId == self:GetActiveDrawerId() then
        if self.WidgetHost and self.WidgetHost.Reflow then
            self.WidgetHost:Reflow()
        end
    end
end

function addon:RemoveWidgetFromDrawer(drawerId, widgetId)
    local drawers = self:GetSetting("drawers") or {}
    local def = drawers[drawerId]
    if not def or not def.widgets then return end
    -- If wildcard, convert to explicit list first
    if def.widgets == "*" then
        local allWidgets = BazUI.GetDockableWidgets and BazUI:GetDockableWidgets() or {}
        local explicit = {}
        for _, w in ipairs(allWidgets) do
            explicit[#explicit + 1] = w.id
        end
        def.widgets = explicit
    end
    for i, wid in ipairs(def.widgets) do
        if wid == widgetId then
            table.remove(def.widgets, i)
            break
        end
    end
    self:SetSetting("drawers", drawers)
    if drawerId == self:GetActiveDrawerId() then
        if self.WidgetHost and self.WidgetHost.Reflow then
            self.WidgetHost:Reflow()
        end
    end
end

---------------------------------------------------------------------------
-- Widget collapsed state (per-drawer, per-widget)
---------------------------------------------------------------------------

function addon:IsWidgetCollapsed(id)
    local drawer = self:GetActiveDrawerDef()
    if not drawer then return false end
    local map = drawer.widgetCollapsed
    return (map and map[id]) and true or false
end

function addon:SetWidgetCollapsed(id, val)
    local drawers = self:GetSetting("drawers") or {}
    local drawerId = self:GetActiveDrawerId()
    local def = drawers[drawerId]
    if not def then return end
    def.widgetCollapsed = def.widgetCollapsed or {}
    def.widgetCollapsed[id] = val and true or nil
    self:SetSetting("drawers", drawers)
end

---------------------------------------------------------------------------
-- Widget ordering (per-drawer, per-widget)
---------------------------------------------------------------------------

function addon:GetWidgetOrder(id)
    local drawer = self:GetActiveDrawerDef()
    if not drawer then return nil end
    local map = drawer.widgetOrder
    return map and map[id]
end

function addon:SetWidgetOrder(id, n)
    local drawers = self:GetSetting("drawers") or {}
    local drawerId = self:GetActiveDrawerId()
    local def = drawers[drawerId]
    if not def then return end
    def.widgetOrder = def.widgetOrder or {}
    def.widgetOrder[id] = n
    self:SetSetting("drawers", drawers)
end

-- Returns widget tables for the active drawer, sorted by order.
function addon:GetSortedWidgets()
    local allWidgets = BazUI.GetDockableWidgets and BazUI:GetDockableWidgets() or {}
    local drawer = self:GetActiveDrawerDef()
    if not drawer or not drawer.widgets then return {} end

    local copy = {}
    if drawer.widgets == "*" then
        -- Wildcard: include all registered widgets
        for _, w in ipairs(allWidgets) do
            copy[#copy + 1] = w
        end
    else
        -- Build a set of widget IDs assigned to the active drawer
        local assigned = {}
        for _, wid in ipairs(drawer.widgets) do
            assigned[wid] = true
        end
        for _, w in ipairs(allWidgets) do
            if assigned[w.id] then
                copy[#copy + 1] = w
            end
        end
    end

    table.sort(copy, function(a, b)
        local oa = addon:GetWidgetOrder(a.id) or 10000
        local ob = addon:GetWidgetOrder(b.id) or 10000
        if oa == ob then return (a.id or "") < (b.id or "") end
        return oa < ob
    end)
    return copy
end

-- Swap `id` with its neighbor in the sorted list and persist the new order.
local function ApplyReorder(sorted)
    for i, w in ipairs(sorted) do
        addon:SetWidgetOrder(w.id, i)
    end
    if addon.WidgetHost and addon.WidgetHost.Reflow then
        addon.WidgetHost:Reflow()
    end
end

function addon:MoveWidgetUp(id)
    local sorted = self:GetSortedWidgets()
    for i, w in ipairs(sorted) do
        if w.id == id and i > 1 then
            sorted[i], sorted[i - 1] = sorted[i - 1], sorted[i]
            ApplyReorder(sorted)
            return
        end
    end
end

function addon:MoveWidgetDown(id)
    local sorted = self:GetSortedWidgets()
    for i, w in ipairs(sorted) do
        if w.id == id and i < #sorted then
            sorted[i], sorted[i + 1] = sorted[i + 1], sorted[i]
            ApplyReorder(sorted)
            return
        end
    end
end

---------------------------------------------------------------------------
-- Drawer collapsed state (per-drawer)
---------------------------------------------------------------------------

function addon:IsDrawerCollapsed(drawerId)
    local def = self:GetDrawer(drawerId or self:GetActiveDrawerId())
    return def and def.collapsed or false
end

function addon:SetDrawerCollapsed(drawerId, val)
    local drawers = self:GetSetting("drawers") or {}
    local def = drawers[drawerId or self:GetActiveDrawerId()]
    if not def then return end
    def.collapsed = val and true or false
    self:SetSetting("drawers", drawers)
end

---------------------------------------------------------------------------
-- Generic per-widget settings store. Widgets that need their own
-- persistent options read/write through here instead of maintaining
-- their own SavedVariables, so everything lives in BazUI Drawers' profile.
---------------------------------------------------------------------------

function addon:GetWidgetSetting(widgetId, key, default)
    local map = self:GetSetting("widgetSettings")
    if map and map[widgetId] and map[widgetId][key] ~= nil then
        return map[widgetId][key]
    end
    return default
end

function addon:SetWidgetSetting(widgetId, key, val)
    local map = self:GetSetting("widgetSettings") or {}
    map[widgetId] = map[widgetId] or {}
    map[widgetId][key] = val
    self:SetSetting("widgetSettings", map)
end

---------------------------------------------------------------------------
-- Global widget overrides (BazUI-style)
--
-- A global override for a given key replaces the per-widget setting of
-- that key across ALL widgets. Stored as:
--   widgetGlobalOverrides[key] = { enabled = bool, value = <any> }
--
-- GetWidgetEffectiveSetting resolves the precedence chain:
--   global override (if enabled) > per-widget setting > default
---------------------------------------------------------------------------

function addon:GetGlobalOverrides()
    local map = self:GetSetting("widgetGlobalOverrides")
    if not map then
        map = {}
        self:SetSetting("widgetGlobalOverrides", map)
    end
    return map
end

function addon:SetGlobalOverride(key, field, value)
    local map = self:GetGlobalOverrides()
    map[key] = map[key] or {}
    map[key][field] = value
    self:SetSetting("widgetGlobalOverrides", map)
    if addon.WidgetHost and addon.WidgetHost.Reflow then
        addon.WidgetHost:Reflow()
    end
    if addon.Drawer and addon.Drawer.EvaluateFade then
        addon.Drawer:EvaluateFade(true)
    end
end

function addon:GetWidgetEffectiveSetting(widgetId, key, default)
    local overrides = self:GetSetting("widgetGlobalOverrides")
    if overrides and overrides[key] and overrides[key].enabled then
        if overrides[key].value ~= nil then
            return overrides[key].value
        end
    end
    return self:GetWidgetSetting(widgetId, key, default)
end

---------------------------------------------------------------------------
-- Floating widget state (per-widget, persisted)
--
-- A widget is either DOCKED (parented into a slot inside the drawer and
-- sized by the widget host) or FLOATING (reparented to UIParent with its
-- own saved anchor and registered with BazUI Edit Mode for drag).
---------------------------------------------------------------------------

function addon:IsWidgetFloating(id)
    local map = self:GetSetting("widgetFloating")
    return (map and map[id]) and true or false
end

function addon:SetWidgetFloating(id, val)
    local map = self:GetSetting("widgetFloating") or {}
    map[id] = val and true or nil
    self:SetSetting("widgetFloating", map)
end

---------------------------------------------------------------------------
-- Dock end (top vs bottom of the drawer)
--
-- Each widget normally stacks from the drawer's top edge. Toggling
-- `dockedToBottom` puts it in a separate "bottom stack" that anchors
-- to the drawer's bottom edge and grows upward as content extends.
-- Widgets can declare their own `defaultDockToBottom` at registration
-- (e.g. a tooltip widget where bottom-anchored is the natural default).
---------------------------------------------------------------------------

function addon:IsWidgetDockedToBottom(id)
    local map = self:GetSetting("widgetDockedToBottom")
    if map and map[id] ~= nil then
        return map[id] and true or false
    end
    -- Fall back to the widget's registration-time default.
    local widget = BazUI.GetDockableWidget and BazUI:GetDockableWidget(id)
    return (widget and widget.defaultDockToBottom) and true or false
end

function addon:SetWidgetDockedToBottom(id, val)
    local map = self:GetSetting("widgetDockedToBottom") or {}
    -- Always record an explicit true/false. Storing nil for "off"
    -- would cause the next IsWidgetDockedToBottom call to fall
    -- through to the widget's registration default - silently
    -- ignoring the user's explicit choice for any widget that
    -- declared defaultDockToBottom = true.
    map[id] = val and true or false
    self:SetSetting("widgetDockedToBottom", map)
end

function addon:GetWidgetPosition(id)
    local map = self:GetSetting("widgetPositions")
    return map and map[id]
end

function addon:SetWidgetPosition(id, pos)
    local map = self:GetSetting("widgetPositions") or {}
    map[id] = pos
    self:SetSetting("widgetPositions", map)
end

---------------------------------------------------------------------------
-- Widget enabled state (per-widget, persisted; default enabled)
--
-- A disabled widget is hidden entirely - not in the drawer slot stack,
-- not floating, just parked off-screen with its frame hidden. Re-enabling
-- restores the previous dock/float state.
---------------------------------------------------------------------------

-- Widgets new characters should see by default. Every other widget
-- starts disabled for fresh profiles and the user opts in via the
-- Widgets settings. Existing profiles are unaffected - see
-- widgetEnableStrict logic below.
local DEFAULT_ENABLED_WIDGETS = {
    bazdrawer_zonetext        = true,
    bazdrawer_minimap         = true,
    bazdrawer_minimapbuttons  = true,
    bazdrawer_questtracker    = true,
}

function addon:IsWidgetEnabled(id)
    local map = self:GetSetting("widgetEnabled") or {}
    if map[id] ~= nil then
        return map[id] and true or false
    end
    -- Unset - fall back to the per-profile default mode.
    -- Strict mode (fresh profiles) > only the curated allowlist is on.
    -- Permissive mode (existing profiles pre-migration) > all on.
    if self:GetSetting("widgetEnableStrict") then
        return DEFAULT_ENABLED_WIDGETS[id] == true
    end
    return true
end

function addon:SetWidgetEnabled(id, val)
    local wasEnabled = self:IsWidgetEnabled(id)
    local map = self:GetSetting("widgetEnabled") or {}
    -- Always record an explicit true/false now that "unset" has a
    -- per-profile meaning - leaving nil would make the value depend
    -- on strict mode instead of reflecting the user's choice.
    map[id] = val and true or false
    self:SetSetting("widgetEnabled", map)

    -- When transitioning from disabled -> enabled, materialise any
    -- wildcard drawers (widgets = "*") into explicit lists EXCLUDING
    -- this widget. Without this the wildcard would auto-include the
    -- newly-enabled widget in every drawer, robbing the user of the
    -- chance to opt in per-drawer. With explicit lists the per-drawer
    -- toggle starts OFF and the user adds the widget on the Drawers
    -- page where they want it.
    if val and not wasEnabled then
        self:_MaterializeWildcardDrawers(id)
    end
end

-- Convert any drawer's `widgets = "*"` wildcard into an explicit list
-- of currently-enabled widget IDs, optionally excluding `excludeId`.
-- Used when a new widget is enabled so it doesn't auto-appear in
-- existing wildcard drawers.
function addon:_MaterializeWildcardDrawers(excludeId)
    local drawers = self:GetSetting("drawers") or {}
    local changed = false
    local allWidgets = BazUI.GetDockableWidgets and BazUI:GetDockableWidgets() or {}
    for _, def in pairs(drawers) do
        if def.widgets == "*" then
            local explicit = {}
            for _, w in ipairs(allWidgets) do
                if w.id ~= excludeId and self:IsWidgetEnabled(w.id) then
                    explicit[#explicit + 1] = w.id
                end
            end
            def.widgets = explicit
            changed = true
        end
    end
    if changed then
        self:SetSetting("drawers", drawers)
    end
end

-- Apply first-run defaults for a fresh profile.
-- Runs on onReady. For a brand-new profile (no widget-related saved
-- state yet), enables strict mode so unset widgets default OFF. For
-- existing profiles with customizations, leaves permissive mode so
-- players don't lose widgets they were already seeing.
function addon:ApplyFirstRunDefaults()
    if self:GetSetting("widgetEnableStrict") ~= nil then
        return  -- already migrated
    end
    local function nonEmpty(key)
        local t = self:GetSetting(key)
        return t and next(t) ~= nil
    end
    local hasCustomization =
           nonEmpty("widgetEnabled")
        or nonEmpty("widgetSettings")
        or nonEmpty("widgetFloating")
        or nonEmpty("widgetPositions")
    if hasCustomization then
        -- Existing profile - preserve old permissive behavior so the
        -- player doesn't wake up with widgets missing.
        self:SetSetting("widgetEnableStrict", false)
    else
        -- Fresh profile - apply the curated default set.
        self:SetSetting("widgetEnableStrict", true)
    end
end
