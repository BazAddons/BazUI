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

-- One event's state as the page shows it: "off", "history" or "toast".
-- Unset keys read as the definition's default.
function BNC:GetEventChoice(moduleId, def)
    local choice = def.default or "toast"
    local shown = false
    for _, k in ipairs(BNC.EventShowKeys(def)) do
        local v = BNC:GetModuleSetting(moduleId, k)
        if v == nil then v = choice ~= "off" end
        if v ~= false then shown = true end
    end
    if not shown then return "off" end
    if def.toast then
        local t = BNC:GetModuleSetting(moduleId, def.toast)
        if t == nil then t = choice == "toast" end
        if t == false then return "history" end
    end
    return "toast"
end

function BNC:SetEventChoice(moduleId, def, choice)
    for _, k in ipairs(BNC.EventShowKeys(def)) do
        BNC:SetModuleSetting(moduleId, k, choice ~= "off")
    end
    if def.toast then
        BNC:SetModuleSetting(moduleId, def.toast, choice == "toast")
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
