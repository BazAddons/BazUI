-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications
local BNC = addon.API

-- Store module option definitions for the options panel
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

-- Register module-specific options
-- optionsDef is an array of: { key = "showSubzones", label = "Show Subzone Changes", type = "toggle", default = true }
-- or: { key = "zoneDuration", label = "Zone Toast Duration", type = "slider", default = 4, min = 1, max = 15, step = 1 }
-- Standard options auto-injected into every module unless already present
local STANDARD_OPTIONS = {
    { key = "soundEnabled",  label = "Play Sound",     type = "toggle", default = true },
    { key = "toastsEnabled", label = "Enable Toasts",  type = "toggle", default = true },
}

function BNC:RegisterModuleOptions(moduleId, optionsDef)
    if not addon.modules[moduleId] then return end

    -- Auto-inject standard options if not already declared
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

    -- Initialize defaults in saved variables
    if addon.db and addon.db.modules[moduleId] then
        for _, opt in ipairs(optionsDef) do
            if addon.db.modules[moduleId][opt.key] == nil then
                addon.db.modules[moduleId][opt.key] = opt.default
            end
        end
    end

    addon.Events:Trigger("MODULE_OPTIONS_REGISTERED", moduleId)
end

-- Get a module-specific setting value (respects global overrides)
function BNC:GetModuleSetting(moduleId, key)
    if not addon.db or not addon.db.modules[moduleId] then return nil end

    -- Check global overrides
    local overrides = addon.db.globalOverrides
    if overrides then
        -- Direct key match (soundEnabled, toastsEnabled)
        local override = overrides[key]
        if override and override.enabled then
            return override.value
        end
        -- Duration keys: any key ending in "Duration" uses toastDuration override
        if overrides.toastDuration and overrides.toastDuration.enabled then
            if key:find("Duration$") then
                return overrides.toastDuration.value
            end
        end
    end

    return addon.db.modules[moduleId][key]
end

-- Check if a global override is active for a given key
function BNC:IsGlobalOverrideActive(key)
    local overrides = addon.db and addon.db.globalOverrides
    if not overrides then return false end
    if overrides[key] and overrides[key].enabled then return true end
    if key:find("Duration$") and overrides.toastDuration and overrides.toastDuration.enabled then return true end
    return false
end

-- Set a module-specific setting value
function BNC:SetModuleSetting(moduleId, key, value)
    if not addon.db then return end
    if not addon.db.modules[moduleId] then
        addon.db.modules[moduleId] = { enabled = true }
    end
    addon.db.modules[moduleId][key] = value
    addon.Events:Trigger("MODULE_SETTING_CHANGED", moduleId, key, value)
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
