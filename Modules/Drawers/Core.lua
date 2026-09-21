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
        widgetSpacing = 6,            -- vertical gap between docked widgets
        widgetSettings = {},          -- [widgetId] = { [key] = value } for widget-specific options
        widgetGlobalOverrides = {},   -- [key] = { enabled = bool, value = <any> } (BazUI global page)
        widgetFloating = {},          -- [widgetId] = true when detached from the drawer into free Edit Mode
        widgetPositions = {},         -- [widgetId] = { point, relPoint, x, y } for floating widgets
        widgetScale = {},             -- [widgetId] = number, how big a floating widget draws
        widgetEnabled = {},           -- [widgetId] = false to disable the widget entirely (default true)
        widgetDockedToBottom = {},    -- [widgetId] = true to dock at the drawer's bottom edge (stacks upward)
        broker = {                    -- LibDataBroker feed widgets (Widgets/Broker.lua)
            showIcon      = true,
            showLabel     = true,
            emptyText     = "-",
            autoEnableNew = true,
        },

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

        -- Whether there is a drawer at all. Off, every enabled widget
        -- floats on the screen and the drawer, its tabs and its edge
        -- strip are not drawn - see UsingDrawers below.
        useDrawers = true,
    },

    slash = { "/bwd" },
    commands = {
        fade = {
            desc = "Print what each widget's title bar is doing about fading",
            handler = function()
                local host = addon.WidgetHost
                if not (host and host.slots) then
                    addon:Print("The widget host is not up yet.")
                    return
                end
                addon:Print(("Chrome alpha the drawer last asked for: %s")
                    :format(tostring(host._chromeAlpha)))
                for id, slot in pairs(host.slots) do
                    local wants = addon:GetWidgetEffectiveSetting(id, "fadeTitleBar", true)
                    local bar = slot.titleBar
                    print(("  %s | fade=%s | alpha=%s | effective=%s | shown=%s"):format(
                        id,
                        tostring(wants),
                        bar and string.format("%.2f", bar:GetAlpha() or -1) or "no bar",
                        bar and string.format("%.2f", bar:GetEffectiveAlpha() or -1) or "-",
                        bar and tostring(bar:IsShown()) or "-"))
                end
            end,
        },
        map = {
            desc = "Print everything about where the minimap has got to",
            handler = function()
                local function Frame(label, f)
                    if not f then print(("  %s: absent"):format(label)) return end
                    local parent = f:GetParent()
                    local point, _, relPoint, x, y = f:GetPoint()
                    print(("  %s: %s parent=%s shown=%s alpha=%.2f eff=%.2f"):format(
                        label,
                        ("%.0fx%.0f @%.2f"):format(f:GetWidth() or 0, f:GetHeight() or 0, f:GetScale() or 1),
                        parent and (parent:GetName() or "unnamed") or "none",
                        tostring(f:IsShown()), f:GetAlpha() or -1, f:GetEffectiveAlpha() or -1))
                    print(("      strata=%s level=%s visible=%s at %s"):format(
                        tostring(f:GetFrameStrata()), tostring(f:GetFrameLevel()),
                        tostring(f:IsVisible()),
                        point and ("%s->%s %.0f,%.0f"):format(point, relPoint or "?", x or 0, y or 0)
                            or "unanchored"))
                end

                addon:Print(addon:UsingDrawers() and "Drawers on." or "Drawers off.")
                local w = BazUI.GetDockableWidget and BazUI:GetDockableWidget("bazdrawer_minimap")
                if not w then
                    addon:Print("  The minimap widget is not registered.")
                    return
                end
                print(("  enabled=%s floating(setting)=%s _floating=%s inDrawer=%s"):format(
                    tostring(addon:IsWidgetEnabled(w.id)),
                    tostring((addon:GetSetting("widgetFloating") or {})[w.id] and true or false),
                    tostring(w._floating and true or false),
                    tostring(addon:IsWidgetInDrawer(addon:GetActiveDrawerId(), w.id))))
                local pos = addon:GetWidgetPosition(w.id)
                print(("  saved position: %s"):format(pos
                    and (pos.point and ("%s %s %.0f,%.0f"):format(pos.point,
                            pos.relPoint or "?", pos.x or 0, pos.y or 0)
                        or ("center offset %.0f,%.0f"):format(pos.x or 0, pos.y or 0))
                    or "none"))
                print(("  design: %.0fx%.0f"):format(w.designWidth or 0, w.designHeight or 0))
                Frame("wrapper ", w.frame)
                Frame("Minimap ", _G.Minimap)
                Frame("Backdrop", _G.MinimapBackdrop)
                Frame("Cluster ", _G.MinimapCluster)
                local host = addon.WidgetHost
                print(("  slot: %s"):format(host and host.slots
                    and tostring(host.slots[w.id] ~= nil) or "?"))
            end,
        },
        float = {
            desc = "Print where each floating widget thinks it should be",
            handler = function()
                addon:Print(addon:UsingDrawers()
                    and "Drawers are on." or "Drawers are off: everything floats.")
                local any = false
                for _, w in ipairs(BazUI.GetDockableWidgets and BazUI:GetDockableWidgets() or {}) do
                    if addon:IsWidgetFloating(w.id) then
                        any = true
                        local pos = addon:GetWidgetPosition(w.id)
                        local saved = pos
                            and (pos.point
                                and ("%s %s %.0f, %.0f"):format(pos.point,
                                    pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                                or ("center offset %.0f, %.0f"):format(pos.x or 0, pos.y or 0))
                            or "nothing saved"
                        -- Not `w.frame and w.frame:GetPoint()`: an `and`
                        -- keeps only the first return, so every value
                        -- after the point would come back nil.
                        local now = "no frame"
                        if w.frame then
                            local point, _, relPoint, x, y = w.frame:GetPoint()
                            now = point
                                and ("%s %s %.0f, %.0f"):format(point,
                                    relPoint or "?", x or 0, y or 0)
                                or "unanchored"
                        end
                        print(("  %s | saved: %s | now: %s"):format(w.id, saved, now))
                    end
                end
                if not any then addon:Print("  Nothing is floating.") end
            end,
        },
        feeds = {
            desc = "LibDataBroker feeds: /bwd feeds (list) or /bwd feeds rescan",
            handler = function(args)
                if not addon.Broker then return end
                if args == "rescan" then addon.Broker:Rescan(true) else addon.Broker:PrintList() end
            end,
        },
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
        icon = "Interface\\AddOns\\BazUI\\Modules\\Drawers\\Assets\\drawers_icon.tga",
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

-- Everything the drawer reads from the profile, read again.
--
-- Called by the profile switch, which is when every one of these can have
-- changed at once. Each piece already existed - the settings page calls
-- them one at a time as you change things - so this is the same set
-- gathered rather than a second way of applying them.
--
-- Drawer:Build is not among them on purpose: it returns early when the
-- frame exists, because rebuilding would throw away every widget and make
-- them again. What changes on a profile switch is what the frame is told,
-- not the frame.
function addon:ApplySettings()
    local drawer = self.Drawer
    if not (drawer and drawer.frame) then return end

    -- Whether there is a drawer at all, before anything that arranges
    -- one: with it off the rest is arranging something nobody sees.
    if drawer.ApplyDrawerless then drawer:ApplyDrawerless() end

    -- Side, width and where it sits.
    drawer:ApplySide()
    if drawer.ApplyEdgeHotZone then drawer:ApplyEdgeHotZone() end

    -- Which drawers there are, and which widgets are in this one.
    if drawer.RefreshTabs then drawer:RefreshTabs() end
    if self.WidgetHost and self.WidgetHost.Reflow then
        self.WidgetHost:Reflow()
    end

    -- Open or shut, which is the active drawer's own answer.
    local def = self.GetActiveDrawerDef and self:GetActiveDrawerDef()
    if def and def.collapsed then drawer:Collapse() else drawer:Expand() end

    if drawer.ApplyLockUI then drawer:ApplyLockUI() end
    -- Last, and forced: the fade controller owns the background and border
    -- opacity, so nothing above has really landed until this runs.
    if drawer.EvaluateFade then drawer:EvaluateFade(true) end
end

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

    -- With no drawers, membership is not a question anybody asked: every
    -- widget that is on is on screen.
    if not self:UsingDrawers() then
        drawer = { widgets = "*" }
    end

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

-- Write an order out, numbered from one, and redraw.
--
-- Numbered from one every time rather than nudged, because until someone
-- reorders something nothing has a number at all: GetWidgetOrder answers
-- nil for a widget nobody has moved, and arithmetic on nil positions is
-- how two widgets ended up agreeing they were both tenth.
function addon:ApplyWidgetOrder(sorted)
    for i, w in ipairs(sorted) do
        self:SetWidgetOrder(w.id, i)
    end
    if self.WidgetHost and self.WidgetHost.Reflow then
        self.WidgetHost:Reflow()
    end
end

function addon:MoveWidgetUp(id)
    local sorted = self:GetSortedWidgets()
    for i, w in ipairs(sorted) do
        if w.id == id and i > 1 then
            sorted[i], sorted[i - 1] = sorted[i - 1], sorted[i]
            self:ApplyWidgetOrder(sorted)
            return
        end
    end
end

function addon:MoveWidgetDown(id)
    local sorted = self:GetSortedWidgets()
    for i, w in ipairs(sorted) do
        if w.id == id and i < #sorted then
            sorted[i], sorted[i + 1] = sorted[i + 1], sorted[i]
            self:ApplyWidgetOrder(sorted)
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

---------------------------------------------------------------------------
-- Drawers, or no drawers
--
-- With the drawer switched off there is nothing to dock into, so every
-- enabled widget floats. That is expressed here rather than branched on
-- in twenty places: IsWidgetFloating is the question the widget host,
-- the settings page and the reorder code all already ask, so answering
-- it differently is most of the feature.
---------------------------------------------------------------------------

function addon:UsingDrawers()
    return self:GetSetting("useDrawers") ~= false
end

function addon:IsWidgetFloating(id)
    if not self:UsingDrawers() then return true end
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

---------------------------------------------------------------------------
-- How big a floating widget draws
--
-- Docked, the drawer decides: a widget is scaled to fill the drawer's
-- width, which is why there was never a scale to set. Floating there is
-- nothing to fill, so the number has to come from somewhere, and with
-- no drawer at all that is every widget on screen.
--
-- A widget that scales its own contents says so with `ownsScale` and is
-- left alone - the minimap is the one, because the map has to stay
-- concentric with the ring drawn around it, so it scales the map rather
-- than the frame holding it. Offering both would be two scales
-- multiplying together, which is the conflict this avoids.
---------------------------------------------------------------------------

function addon:GetWidgetScale(id)
    local map = self:GetSetting("widgetScale")
    local v = map and tonumber(map[id])
    if not v or v <= 0 then return 1 end
    return v
end

function addon:SetWidgetScale(id, value)
    local map = self:GetSetting("widgetScale") or {}
    value = tonumber(value) or 1
    map[id] = (value == 1) and nil or value
    self:SetSetting("widgetScale", map)
end

-- Whether this widget's size is ours to set at all.
function addon:WidgetOwnsScale(id)
    local w = BazUI.GetDockableWidget and BazUI:GetDockableWidget(id)
    return (w and w.ownsScale) and true or false
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
