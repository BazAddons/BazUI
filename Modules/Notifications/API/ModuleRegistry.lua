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

---------------------------------------------------------------------------
-- Getting at a source's settings
--
-- Every source's settings live in addon.db.modules, and everything below
-- used to reach into that table after checking `addon.db`. That check
-- cannot fail: addon.db is a proxy onto the active profile, so it is a
-- table whether or not there is anything behind it. When the profile
-- section has not been filled in - a brand-new install, a profile made
-- while the module was switched off - addon.db.modules is nil and the
-- reach through it errors.
--
-- So: one way in, and it answers a table or nothing, never a crash.
-- ModuleSettings makes what is missing, PeekModuleSettings does not, and
-- the difference is whether the caller is about to write.
---------------------------------------------------------------------------

-- Set the first time the table had to be built here rather than by the
-- profile defaults. It should never happen; if it does, this says what
-- the world looked like at the time. Read it with
--   /dump BazUI.Notifications.dbRepair
addon.dbRepair = nil

local function AllModuleSettings(create)
    if not addon.db then return nil end

    local all = addon.db.modules
    if type(all) == "table" then return all end
    if not create then return nil end

    if not addon.dbRepair then
        local sv = BazUIDB
        local profileName = sv and (sv.activeProfile or "?") or "no BazUIDB"
        local section = sv and sv.profiles and sv.profiles[profileName]
        addon.dbRepair = {
            when       = date("%Y-%m-%d %H:%M:%S"),
            profile    = profileName,
            hadProfile = section ~= nil,
            hadSection = section and section.Notifications ~= nil or false,
            hasCopyTable = type(CopyTable) == "function",
            build      = select(4, GetBuildInfo()),
        }
        -- Saved as well as held, because the answer is usually wanted after
        -- something has gone wrong, and a client that crashed is a client
        -- that cannot be asked. It rides along in the profile and can be
        -- read straight out of SavedVariables\BazUI.lua.
        addon.db.dbRepair = addon.dbRepair
    end

    all = {}
    addon.db.modules = all
    return all
end

local function ModuleSettings(moduleId)
    local all = AllModuleSettings(true)
    if not all then return nil end
    local one = all[moduleId]
    if not one then
        one = { enabled = true }
        all[moduleId] = one
    end
    return one
end

local function PeekModuleSettings(moduleId)
    local all = AllModuleSettings(false)
    return all and all[moduleId] or nil
end

-- Published so the rest of the module reads settings the same way.
function BNC:GetModuleSettings(moduleId)
    return PeekModuleSettings(moduleId)
end

--- Create a GetSetting closure for a module. Eliminates per-module boilerplate.
--- Usage: local GetSetting = BNC:CreateGetSetting("mymodule")
-- The color of a source's band. Always answers something drawable.
function BNC:GetModuleColor(moduleId)
    local module = addon.modules[moduleId]
    return (module and module.color)
        or addon.ModuleColorDefault
        or { 0.62, 0.48, 0.20, 1 }
end

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
        -- The band down the left of this source's cards. One it brought
        -- itself, else the one this addon keeps for it, else a default -
        -- so a source somebody else writes still gets a band.
        color = moduleInfo.color
            or (addon.ModuleColors and addon.ModuleColors[id])
            or addon.ModuleColorDefault,
    }

    addon.modules[id] = module

    -- Ensure per-module settings exist with defaults
    ModuleSettings(id)

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

    local settings = ModuleSettings(moduleId)
    if settings then
        for _, opt in ipairs(optionsDef) do
            ApplyDefault(settings, opt)
        end
    end

    addon.Events:Trigger("MODULE_OPTIONS_REGISTERED", moduleId)
end

function BNC:GetModuleSetting(moduleId, key)
    local settings = PeekModuleSettings(moduleId)
    if not settings then return nil end
    return settings[key]
end

function BNC:SetModuleSetting(moduleId, key, value)
    local settings = ModuleSettings(moduleId)
    if not settings then return end
    settings[key] = value
    addon.Events:Trigger("MODULE_SETTING_CHANGED", moduleId, key, value)
end


---------------------------------------------------------------------------
-- Where an event goes
--
-- Three places, and they are three different things rather than three
-- shades of one:
--
--   default  the game's own alert for this, left alone or suppressed.
--            Only offered where the event has one and we can silence
--            it; most do not.
--   toast    this module: a toast on screen and a line in the history.
--   chat     printed into the chat frame.
--
-- Toast and chat are the two this module can deliver, so between them
-- they decide whether the source raises the event at all. Default is not
-- a delivery at all: it governs whether Blizzard's own display is left
-- in place, which is why it can be on with both others off.
---------------------------------------------------------------------------

function BNC.EventChatKey(def)
    return def.chat or (def.key .. "Chat")
end

function BNC:GetEventDestination(moduleId, def, which)
    if which == "default" then
        -- The stored setting asks the opposite question - whether to
        -- hide Blizzard's own - so the switch reads inverted.
        if not def.blizzard then return false end
        return BNC:GetModuleSetting(moduleId, def.blizzard) == false
    end

    if which == "chat" then
        return BNC:GetModuleSetting(moduleId, BNC.EventChatKey(def)) == true
    end

    -- toast
    if not BNC:IsEventRaised(moduleId, def) then return false end
    if not def.toast then return true end
    local v = BNC:GetModuleSetting(moduleId, def.toast)
    if v == nil then return (def.default or "toast") == "toast" end
    return v ~= false
end

-- Whether the source should raise this event at all.
function BNC:IsEventRaised(moduleId, def)
    for _, k in ipairs(BNC.EventShowKeys(def)) do
        local v = BNC:GetModuleSetting(moduleId, k)
        if v == nil then v = (def.default or "toast") ~= "off" end
        if v ~= false then return true end
    end
    return false
end

function BNC:SetEventDestination(moduleId, def, which, on)
    if which == "default" then
        if def.blizzard then BNC:SetModuleSetting(moduleId, def.blizzard, not on) end
        -- Some of Blizzard's displays are silenced by unregistering the
        -- frame's events, which cannot be undone while the interface is
        -- running. Say so rather than leaving it looking broken.
        if on and def.blizzardReload and BazUI.PromptReload then
            BazUI:PromptReload(def.blizzardReload)
        end
        return
    end

    if which == "chat" then
        BNC:SetModuleSetting(moduleId, BNC.EventChatKey(def), on)
    else
        if def.toast then BNC:SetModuleSetting(moduleId, def.toast, on) end
    end

    -- The show keys are the master the sources themselves read, so they
    -- follow whether this module still has anywhere to put the event.
    local toast = (which == "toast") and on
        or (which ~= "toast" and def.toast
            and BNC:GetModuleSetting(moduleId, def.toast) ~= false)
    local chat = (which == "chat") and on
        or (which ~= "chat"
            and BNC:GetModuleSetting(moduleId, BNC.EventChatKey(def)) == true)
    local wanted = toast or chat
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
    -- Enabled unless the settings say otherwise, which covers both "no
    -- database yet" and "no settings for this source yet".
    local settings = PeekModuleSettings(id)
    if not settings then return true end
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
