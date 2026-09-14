-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Notifications: source registry
--
-- A source (Loot, Quests, Mail ...) registers itself and a list of
-- option definitions. The Sources options page renders those; the
-- source reads the values back through BNC:GetModuleSetting.
--
-- Option definition shapes:
--   { type = "toggle", key, label, default, desc, section }
--   { type = "slider", key, label, default, min, max, step, format, desc }
--   { type = "select", key, label, default, values = { k = "Label" }, sorting = { k, ... }, desc }
--   { type = "event",  key, label, show, toast, default, desc }
--       One game event the source reports. `show` is the setting key
--       (or a list of keys) that turns the event on and `toast` the key
--       that lets it toast. The page shows the pair as one choice:
--       Off / History only / Toast. `default` is one of those three
--       ("toast" when omitted). Without a `toast` key the event is a
--       plain on/off switch.
--   section = "blizzard" groups a toggle under "Blizzard UI".
--
-- Every source also gets, unless it declares its own:
--   toastsEnabled  - master switch for the source's toasts
--   toastDuration  - seconds a toast from this source stays up
--   sound          - "default" (by priority), 0 (none) or a sound kit ID
---------------------------------------------------------------------------
local addon = BazUI.Notifications
local BNC = addon.API

addon.moduleOptionDefs = {}

--- Create a GetSetting closure for a module. Eliminates per-module boilerplate.
--- Usage: local GetSetting = BNC:CreateGetSetting("mymodule")
function BNC:CreateGetSetting(moduleId)
    return function(key)
        return BNC:GetModuleSetting(moduleId, key)
    end
end

function BNC:RegisterModule(moduleInfo)
    if not moduleInfo or not moduleInfo.id then
        error("BNC:RegisterModule requires moduleInfo with an 'id' field")
        return
    end

    local id = moduleInfo.id
    if addon.modules[id] then
        return
    end

    local module = {
        id = id,
        name = moduleInfo.name or id,
        icon = moduleInfo.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
    }

    addon.modules[id] = module

    -- Ensure per-module settings exist with defaults
    if addon.db then
        if not addon.db.modules[id] then
            addon.db.modules[id] = { enabled = true }
        end
    end

    addon.Events:Trigger("MODULE_REGISTERED", module)
    return module
end

local STANDARD_OPTIONS = {
    { key = "toastsEnabled", label = "Show toasts",    type = "toggle", default = true },
    { key = "toastDuration", label = "Toast duration", type = "slider", default = 4, min = 1, max = 15, step = 1 },
    { key = "sound",         label = "Sound",          type = "sound",  default = "default" },
}

-- The `show` keys of an event definition, always as a list.
function BNC.EventShowKeys(def)
    if type(def.show) == "table" then return def.show end
    if def.show then return { def.show } end
    return {}
end

local function ApplyDefault(settings, opt)
    if opt.type == "event" then
        local choice = opt.default or "toast"
        for _, k in ipairs(BNC.EventShowKeys(opt)) do
            if settings[k] == nil then settings[k] = choice ~= "off" end
        end
        if opt.toast and settings[opt.toast] == nil then
            settings[opt.toast] = choice == "toast"
        end
    elseif opt.key and settings[opt.key] == nil then
        settings[opt.key] = opt.default
    end
end

function BNC:RegisterModuleOptions(moduleId, optionsDef)
    if not addon.modules[moduleId] then return end

    for _, stdOpt in ipairs(STANDARD_OPTIONS) do
        local found = false
        for _, opt in ipairs(optionsDef) do
            if opt.key == stdOpt.key then
                found = true
                break
            end
        end
        if not found then
            table.insert(optionsDef, stdOpt)
        end
    end

    addon.moduleOptionDefs[moduleId] = optionsDef

    if addon.db and addon.db.modules[moduleId] then
        for _, opt in ipairs(optionsDef) do
            ApplyDefault(addon.db.modules[moduleId], opt)
        end
    end

    addon.Events:Trigger("MODULE_OPTIONS_REGISTERED", moduleId)
end

function BNC:GetModuleSetting(moduleId, key)
    if not addon.db or not addon.db.modules[moduleId] then return nil end
    return addon.db.modules[moduleId][key]
end

function BNC:SetModuleSetting(moduleId, key, value)
    if not addon.db then return end
    if not addon.db.modules[moduleId] then
        addon.db.modules[moduleId] = { enabled = true }
    end
    addon.db.modules[moduleId][key] = value
    addon.Events:Trigger("MODULE_SETTING_CHANGED", moduleId, key, value)
end


---------------------------------------------------------------------------
-- Where an event goes
--
-- Three independent destinations, because they answer different
-- questions. The panel is the record you can go back to; a toast is
-- something you want to see happen; the chat box is for the things you
-- read in a stream with everything else.
--
--   panel   kept in the notification list and the history
--   toast   pops on screen
--   chat    printed into the chat frame
--
-- The panel switch doubles as the master: a source checks its show keys
-- before raising anything at all, so turning every destination off stops
-- the work as well as the noise. Turning the panel off on its own leaves
-- the event raised, and only the destinations you left on receive it.
---------------------------------------------------------------------------

function BNC.EventChatKey(def)
    return def.chat or (def.key .. "Chat")
end

function BNC.EventPanelKey(def)
    return def.panel or (def.key .. "Panel")
end

function BNC:GetEventDestination(moduleId, def, which)
    if which == "toast" then
        if not def.toast then return false end
        local v = BNC:GetModuleSetting(moduleId, def.toast)
        if v == nil then return (def.default or "toast") == "toast" end
        return v ~= false
    end

    if which == "chat" then
        return BNC:GetModuleSetting(moduleId, BNC.EventChatKey(def)) == true
    end

    -- panel: on unless it was explicitly turned off, and only while the
    -- event is raised at all.
    if not BNC:IsEventRaised(moduleId, def) then return false end
    return BNC:GetModuleSetting(moduleId, BNC.EventPanelKey(def)) ~= false
end

-- Whether the source should raise this event at all: true when any
-- destination wants it.
function BNC:IsEventRaised(moduleId, def)
    for _, k in ipairs(BNC.EventShowKeys(def)) do
        local v = BNC:GetModuleSetting(moduleId, k)
        if v == nil then v = (def.default or "toast") ~= "off" end
        if v ~= false then return true end
    end
    return false
end

function BNC:SetEventDestination(moduleId, def, which, on)
    if which == "toast" then
        if def.toast then BNC:SetModuleSetting(moduleId, def.toast, on) end
    elseif which == "chat" then
        BNC:SetModuleSetting(moduleId, BNC.EventChatKey(def), on)
    else
        BNC:SetModuleSetting(moduleId, BNC.EventPanelKey(def), on)
    end

    -- The show keys are the master switch the sources themselves read,
    -- so they follow whether anything at all still wants this event.
    local wanted = (which == "panel" and on)
        or (which ~= "panel" and BNC:GetModuleSetting(moduleId, BNC.EventPanelKey(def)) ~= false)
        or BNC:GetEventDestination(moduleId, def, "toast")
        or BNC:GetEventDestination(moduleId, def, "chat")
        or on
    for _, k in ipairs(BNC.EventShowKeys(def)) do
        BNC:SetModuleSetting(moduleId, k, wanted and true or false)
    end
end

-- The definition behind one of a module's declared events.
function BNC:GetEventDef(moduleId, eventKey)
    for _, def in ipairs(addon.moduleOptionDefs[moduleId] or {}) do
        if def.type == "event" and def.key == eventKey then return def end
    end
end

function BNC:UnregisterModule(id)
    if not addon.modules[id] then return end
    addon.modules[id] = nil
    addon.moduleOptionDefs[id] = nil
    addon.Events:Trigger("MODULE_UNREGISTERED", id)
end

function BNC:IsModuleEnabled(id)
    if not addon.db then return true end  -- default enabled before DB loads
    local settings = addon.db.modules[id]
    if not settings then return true end  -- default enabled if no settings yet
    return settings.enabled ~= false
end

function BNC:GetModule(id)
    return addon.modules[id]
end

function BNC:GetAllModules()
    return addon.modules
end

-- Register internal test module
addon.Events:Register("CORE_LOADED", function()
    BNC:RegisterModule({
        id = "_test",
        name = "BNC",
        icon = "Interface\\Icons\\INV_Misc_Bell_01",
    })
end)
