-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Notifications: options pages
--
-- General  - what applies to every notification: toasts, sounds, the
--            history panel, Do Not Disturb, and the bell.
-- Sources  - a picker of event sources (Loot, Quests, Mail ...). Each
--            source's form: an Enabled switch on the picker row, one
--            Off / History only / Toast choice per event, its toast
--            duration and sound, and whatever extras it declares (see
--            API/ModuleRegistry.lua for the definition shapes).
---------------------------------------------------------------------------
local addon = BazUI.Notifications
local BNC = addon.API

local MODULE_KEY   = "Notifications"
local PAGE_GENERAL = "Notifications-Settings"
local PAGE_SOURCES = "Notifications-Sources"

---------------------------------------------------------------------------
-- Sounds. Every ID is in the Classic Era sound kit table.
---------------------------------------------------------------------------

local SOUNDS = {
    { 0,     "None" },
    { 8959,  "Raid warning" },
    { 8960,  "Ready check" },
    { 3175,  "Map ping" },
    { 3081,  "Whisper" },
    { 120,   "Coin drop" },
    { 878,   "Quest complete" },
    { 880,   "Player invite" },
    { 5274,  "Auction window" },
    { 7994,  "Item repaired" },
    { 8458,  "PvP queue" },
    { 12867, "Alarm clock" },
}

-- values + sorting for a sound dropdown. A saved ID outside the list
-- is listed by number so the dropdown never shows a blank.
local function SoundValues(current, withDefault)
    local values, sorting = {}, {}
    if withDefault then
        values["default"] = "By priority"
        sorting[#sorting + 1] = "default"
    end
    for _, s in ipairs(SOUNDS) do
        values[s[1]] = s[2]
        sorting[#sorting + 1] = s[1]
    end
    if type(current) == "number" and values[current] == nil then
        values[current] = "Sound #" .. current
        sorting[#sorting + 1] = current
    end
    return values, sorting
end

local function DB(key, default)
    local v = addon.db and addon.db[key]
    if v == nil then return default end
    return v
end

local function Setter(key)
    return function(_, val) addon.SetDBValue(key, val) end
end

local function Refresh(page)
    if BazUI.RefreshOptions then BazUI:RefreshOptions(page) end
end

---------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------

local function GetGeneralOptionsTable()
    local function soundsOff() return DB("soundEnabled", true) == false end
    local function PrioritySound(order, label, key, default)
        local function get() return DB(key, default) end
        local values, sorting = SoundValues(get(), false)
        return {
            order = order, type = "select", name = label,
            values = values, sorting = sorting,
            get = get, set = Setter(key), disabled = soundsOff,
        }
    end

    return {
        name = "General",
        type = "group",
        args = {
            toastsHeader = { order = 10, type = "header", name = "Toasts" },
            toastsEnabled = {
                order = 11, type = "toggle", name = "Show toasts",
                desc = "Off keeps every notification in the history panel only.",
                get = function() return DB("toastsEnabled", true) ~= false end,
                set = Setter("toastsEnabled"),
            },
            toastDuration = {
                order = 12, type = "range", name = "Default duration",
                desc = "For notifications sent by other addons. Each source sets its own.",
                min = 1, max = 15, step = 1, format = "%d s",
                get = function() return DB("toastDuration", 5) end,
                set = Setter("toastDuration"),
            },
            toastScale = {
                order = 13, type = "range", name = "Toast size",
                desc = "How large the pop-ups are. The Scale setting below covers the bell and the history panel.",
                min = 0.6, max = 2, step = 0.05, isPercent = true,
                get = function() return DB("toastScale", 1) end,
                set = Setter("toastScale"),
            },
            toastPreview = {
                order = 14, type = "execute", name = "Show a sample",
                desc = "Raises a few toasts so you can size them against the real thing. They never reach your history.",
                func = function()
                    if addon.ShowToastPreview then addon.ShowToastPreview() end
                end,
            },
            soundEnabled = {
                order = 13, type = "toggle", name = "Play sounds",
                get = function() return DB("soundEnabled", true) ~= false end,
                set = function(_, val)
                    addon.SetDBValue("soundEnabled", val)
                    Refresh(PAGE_GENERAL)
                end,
            },
            soundHigh   = PrioritySound(14, "High priority sound",   "soundHigh",   8959),
            soundNormal = PrioritySound(15, "Normal priority sound", "soundNormal", 3175),
            soundLow    = PrioritySound(16, "Low priority sound",    "soundLow",    0),

            panelHeader = { order = 20, type = "header", name = "History panel" },
            panelOpacity = {
                order = 21, type = "range", name = "Background opacity",
                min = 0.5, max = 1, step = 0.05, isPercent = true,
                get = function() return DB("panelOpacity", 0.85) end,
                set = Setter("panelOpacity"),
            },
            scale = {
                order = 22, type = "range", name = "Scale",
                desc = "Bell and panel.",
                min = 0.5, max = 2, step = 0.1, format = "%.1f",
                get = function() return DB("scale", 1) end,
                set = Setter("scale"),
            },
            historyRetentionDays = {
                order = 23, type = "range", name = "Keep history for",
                min = 1, max = 90, step = 1, format = "%d days",
                get = function() return DB("historyRetentionDays", 7) end,
                set = function(_, val)
                    addon.SetDBValue("historyRetentionDays", val)
                    if addon.History_Trim then addon.History_Trim(val) end
                end,
            },

            dndHeader = { order = 30, type = "header", name = "Do Not Disturb" },
            dndDesc = {
                order = 31, type = "description",
                name = "Silences toasts and sounds. Notifications still land in the history panel.",
            },
            dndEnabled = {
                order = 32, type = "toggle", name = "Do Not Disturb",
                get = function() return DB("dndEnabled", false) == true end,
                set = Setter("dndEnabled"),
            },
            dndAutoCombat = {
                order = 33, type = "toggle", name = "Turn on in combat",
                get = function() return DB("dndAutoCombat", false) == true end,
                set = Setter("dndAutoCombat"),
            },
            dndAutoInstance = {
                order = 34, type = "toggle", name = "Turn on during boss encounters",
                get = function() return DB("dndAutoInstance", false) == true end,
                set = Setter("dndAutoInstance"),
            },

            bellHeader = { order = 40, type = "header", name = "Bell" },
            bellDesc = {
                order = 41, type = "description",
                name = "Drag the bell in Edit Mode. The panel and toasts follow it and grow away from the nearest screen corner.",
            },
            resetBellTopLeft = {
                order = 42, type = "execute", name = "Reset to top left",
                func = function()
                    if addon.ResetBellPosition then addon.ResetBellPosition("TOPLEFT") end
                end,
            },
            resetBellTopRight = {
                order = 43, type = "execute", name = "Reset to top right",
                func = function()
                    if addon.ResetBellPosition then addon.ResetBellPosition("TOPRIGHT") end
                end,
            },
        },
    }
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------

local CHOICES      = { toast = "Toast", history = "History only", off = "Off" }
local CHOICE_ORDER = { "toast", "history", "off" }

-- Sections of a source's form, in display order.
local SECTION_EVENTS, SECTION_OPTIONS, SECTION_TOASTS, SECTION_BLIZZARD = 1, 2, 3, 4
local SECTION_NAMES = { "Events", "Options", "Toasts", "Blizzard UI" }
local TOAST_KEYS    = { toastsEnabled = 1, toastDuration = 2, sound = 3 }

local function SectionOf(def)
    if def.type == "event" then return SECTION_EVENTS end
    if TOAST_KEYS[def.key] then return SECTION_TOASTS end
    if def.section == "blizzard" then return SECTION_BLIZZARD end
    return SECTION_OPTIONS
end

local function BuildOption(moduleId, def, disabled)
    local opt = { name = def.label or def.key, desc = def.desc, disabled = disabled }
    local function Current(default)
        local v = BNC:GetModuleSetting(moduleId, def.key)
        if v == nil then return default end
        return v
    end

    if def.type == "event" then
        if def.toast then
            opt.type, opt.values, opt.sorting = "select", CHOICES, CHOICE_ORDER
            opt.get = function() return BNC:GetEventChoice(moduleId, def) end
            opt.set = function(_, val) BNC:SetEventChoice(moduleId, def, val) end
        else
            opt.type = "toggle"
            opt.get = function() return BNC:GetEventChoice(moduleId, def) ~= "off" end
            opt.set = function(_, val) BNC:SetEventChoice(moduleId, def, val and "toast" or "off") end
        end
    elseif def.type == "toggle" then
        opt.type = "toggle"
        opt.get = function() return Current(def.default ~= false) ~= false end
        opt.set = function(_, val)
            BNC:SetModuleSetting(moduleId, def.key, val)
            if def.key == "toastsEnabled" then Refresh(PAGE_SOURCES) end
        end
    elseif def.type == "slider" then
        opt.type = "range"
        opt.min, opt.max, opt.step = def.min or 1, def.max or 15, def.step or 1
        opt.format = def.format or (def.key == "toastDuration" and "%d s") or nil
        opt.get = function() return Current(def.default or opt.min) end
        opt.set = function(_, val) BNC:SetModuleSetting(moduleId, def.key, val) end
    elseif def.type == "select" then
        opt.type, opt.values, opt.sorting = "select", def.values, def.sorting
        opt.get = function() return Current(def.default) end
        opt.set = function(_, val) BNC:SetModuleSetting(moduleId, def.key, val) end
    elseif def.type == "sound" then
        local function get() return Current("default") end
        local values, sorting = SoundValues(get(), true)
        opt.type, opt.values, opt.sorting = "select", values, sorting
        opt.get = get
        opt.set = function(_, val) BNC:SetModuleSetting(moduleId, def.key, val) end
    else
        return nil
    end
    return opt
end

local function BuildSourceArgs(moduleId)
    local defs = addon.moduleOptionDefs[moduleId] or {}
    local function disabled() return not BNC:IsModuleEnabled(moduleId) end

    local hasToastChoice = false
    for _, def in ipairs(defs) do
        if def.type == "event" and def.toast then hasToastChoice = true end
    end

    local sections = { {}, {}, {}, {} }
    for _, def in ipairs(defs) do
        -- The source-wide toast switch is redundant once every event
        -- offers Toast / History only itself.
        if not (def.key == "toastsEnabled" and hasToastChoice) then
            local list = sections[SectionOf(def)]
            list[#list + 1] = def
        end
    end
    table.sort(sections[SECTION_TOASTS], function(a, b)
        return (TOAST_KEYS[a.key] or 9) < (TOAST_KEYS[b.key] or 9)
    end)

    local args, order = {}, 0
    local function Add(key, opt)
        if not opt then return end
        order = order + 1
        opt.order = order
        args[key] = opt
    end

    for s = 1, #sections do
        local list = sections[s]
        if #list > 0 then
            Add("hdr" .. s, { type = "header", name = SECTION_NAMES[s] })
            for i, def in ipairs(list) do
                Add(tostring(def.key or ("event" .. i)), BuildOption(moduleId, def, disabled))
            end
        end
    end
    return args
end

local function GetSourcesOptionsTable()
    local sorted = {}
    for id, module in pairs(addon.modules) do
        if id ~= "_test" then
            sorted[#sorted + 1] = { id = id, name = module.name }
        end
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)

    local groups = {}
    for i, info in ipairs(sorted) do
        local id = info.id
        groups["src_" .. id] = {
            order = i,
            type = "group",
            name = info.name,
            args = BuildSourceArgs(id),
            toggle = {
                name = "Enabled",
                get = function() return BNC:IsModuleEnabled(id) end,
                set = function(_, val)
                    if not addon.db then return end
                    addon.db.modules[id] = addon.db.modules[id] or {}
                    addon.db.modules[id].enabled = val
                    addon.Events:Trigger("MODULE_TOGGLED", id, val)
                    Refresh(PAGE_SOURCES)
                end,
            },
        }
    end

    return {
        name = "Sources",
        type = "group",
        args = {
            sources = {
                order = 1,
                type = "group",
                name = "",
                pickerLabel = "Source",
                emptyText = "No sources have registered yet.",
                args = groups,
            },
        },
    }
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

local function RefreshSources()
    Refresh(PAGE_SOURCES)
end

addon.Events:Register("CORE_LOADED", function()
    -- The module entry itself never renders: its pages are tabs.
    BazUI:RegisterOptionsTable(MODULE_KEY, function()
        return { name = "Notifications", type = "group", args = {} }
    end)
    BazUI:AddToSettings(MODULE_KEY, "Notifications")

    BazUI:RegisterOptionsTable(PAGE_GENERAL, GetGeneralOptionsTable)
    BazUI:AddToSettings(PAGE_GENERAL, "General", MODULE_KEY)

    BazUI:RegisterOptionsTable(PAGE_SOURCES, GetSourcesOptionsTable)
    BazUI:AddToSettings(PAGE_SOURCES, "Sources", MODULE_KEY)
end)

-- Sources register at load and again as their options arrive; keep the
-- page current if it is on screen.
addon.Events:Register("MODULE_REGISTERED", RefreshSources)
addon.Events:Register("MODULE_OPTIONS_REGISTERED", RefreshSources)
addon.Events:Register("PLAYER_READY", RefreshSources)

function addon.OpenOptions()
    BazUI:OpenOptionsPanel(MODULE_KEY)
end
