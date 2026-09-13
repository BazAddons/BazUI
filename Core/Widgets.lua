-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Widget registry
--
-- Dockable widgets are the units the Drawers module hosts. In the old
-- suite this registry was LibBazWidget-1.0 so third-party addons could
-- publish widgets; BazUI is one addon, so it lives here. Same contract:
--
--   Required:  widget.id, widget.frame
--   Display:   widget.label, widget.icon
--   Sizing:    widget.designWidth, widget.designHeight
--   Optional:  widget:GetDesiredHeight(), widget:GetStatusText(),
--              widget:GetOptionsArgs(), widget:OnDock(host), widget:OnUndock()
--
-- Dormant widgets register and unregister themselves from an event-driven
-- condition (a queue widget that only exists while queued, say).
---------------------------------------------------------------------------

local Widgets = {
    registered = {},   -- array of widget tables, insertion order
    byId       = {},   -- [id] = widget
    callbacks  = {},   -- listeners fired on any registry change
    dormant    = {},   -- [id] = { widget, opts, frame, active }
}
BazUI.Widgets = Widgets

local function FireCallbacks()
    for _, fn in ipairs(Widgets.callbacks) do
        pcall(fn)
    end
end

function Widgets:RegisterWidget(widget)
    if type(widget) ~= "table" or not widget.id then
        error("BazUI.Widgets:RegisterWidget requires a widget table with an 'id' field", 2)
    end
    if self.byId[widget.id] then
        for i, w in ipairs(self.registered) do
            if w.id == widget.id then
                self.registered[i] = widget
                break
            end
        end
    else
        table.insert(self.registered, widget)
    end
    self.byId[widget.id] = widget
    FireCallbacks()
end

function Widgets:UnregisterWidget(id)
    if not self.byId[id] then return end
    self.byId[id] = nil
    for i, w in ipairs(self.registered) do
        if w.id == id then
            table.remove(self.registered, i)
            break
        end
    end
    FireCallbacks()
end

function Widgets:GetWidgets()      return self.registered end
function Widgets:GetWidget(id)     return self.byId[id]   end

function Widgets:RegisterCallback(fn)
    if type(fn) == "function" then
        table.insert(self.callbacks, fn)
    end
end

---------------------------------------------------------------------------
-- Dormant widgets
---------------------------------------------------------------------------

function Widgets:RegisterDormantWidget(widget, opts)
    if type(widget) ~= "table" or not widget.id then
        error("BazUI.Widgets:RegisterDormantWidget requires a widget table with an 'id' field", 2)
    end
    if not opts or type(opts.condition) ~= "function" then
        error("BazUI.Widgets:RegisterDormantWidget requires opts.condition", 2)
    end
    local id = widget.id
    if self.dormant[id] then
        self:UnregisterDormantWidget(id)
    end

    local listener = CreateFrame("Frame")
    local entry = { widget = widget, opts = opts, frame = listener, active = false }
    self.dormant[id] = entry

    local function Evaluate()
        local shouldBeActive = opts.condition()
        if shouldBeActive and not entry.active then
            entry.active = true
            Widgets:RegisterWidget(widget)
        elseif not shouldBeActive and entry.active then
            entry.active = false
            Widgets:UnregisterWidget(id)
        end
    end

    if opts.events then
        for _, event in ipairs(opts.events) do
            pcall(listener.RegisterEvent, listener, event)
        end
    end
    listener:SetScript("OnEvent", Evaluate)
    Evaluate()
end

function Widgets:UnregisterDormantWidget(id)
    local entry = self.dormant[id]
    if not entry then return end
    if entry.frame then
        entry.frame:UnregisterAllEvents()
        entry.frame:SetScript("OnEvent", nil)
        entry.frame:Hide()
    end
    if entry.active then
        self:UnregisterWidget(id)
    end
    self.dormant[id] = nil
end

function Widgets:IsDormantWidgetActive(id)
    local entry = self.dormant[id]
    return entry and entry.active or false
end

---------------------------------------------------------------------------
-- Method names the modules were written against.
---------------------------------------------------------------------------

function BazUI:RegisterDockableWidget(widget)      Widgets:RegisterWidget(widget)   end
function BazUI:UnregisterDockableWidget(id)        Widgets:UnregisterWidget(id)     end
function BazUI:GetDockableWidgets()                return Widgets:GetWidgets()      end
function BazUI:GetDockableWidget(id)               return Widgets:GetWidget(id)     end
function BazUI:RegisterDockableWidgetCallback(fn)  Widgets:RegisterCallback(fn)     end
