-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Profiles Module
-- Unified profile system - one profile controls all Baz Suite addons
-- Profiles stored in BazUIDB.profiles[profileName][addonName] = { ... }
---------------------------------------------------------------------------

local DEFAULT_PROFILE = "Default"

-- Profile change callbacks per addon
local profileCallbacks = {} -- [addonName] = { handler1, handler2, ... }

---------------------------------------------------------------------------
-- Character Identity
---------------------------------------------------------------------------

local function GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name and realm and (name .. " - " .. realm) or "Unknown"
end

local function GetClassKey()
    local _, class = UnitClass("player")
    return class or "UNKNOWN"
end

local function GetSpecKey()
    local class = GetClassKey()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex then return nil end
    local _, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    return specName and (class .. ":" .. specName) or nil
end

---------------------------------------------------------------------------
-- Fill defaults for an addon section within a profile
---------------------------------------------------------------------------

local function FillAddonDefaults(profileSection, defaults)
    if not defaults then return end
    for k, v in pairs(defaults) do
        if profileSection[k] == nil then
            if type(v) == "table" then
                profileSection[k] = CopyTable(v)
            else
                profileSection[k] = v
            end
        end
    end
end

-- Starter profile: BazUI.StarterProfile (Core/StarterProfile.lua) holds
-- the shipped layout. It is laid over a module's coded defaults only when
-- that module's section has just been created, so a fresh install, a new
-- profile, or a module added to an old install all start with the BazUI
-- layout, while nobody's existing settings ever change.
local function DeepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            DeepMerge(dst[k], v)
        elseif type(v) == "table" then
            dst[k] = CopyTable(v)
        else
            dst[k] = v
        end
    end
end

-- The layout to lay over a fresh section, which is the shipped one unless
-- a preset was named. A preset is the same shape as BazUI.StarterProfile -
-- module name to settings - because it is the same thing with a label on
-- it, baked from an arrangement made in game by the same exporter.
local function ApplyStarter(addonName, section, source)
    local starter = (source or BazUI.StarterProfile)
    starter = starter and starter[addonName]
    if starter then DeepMerge(section, starter) end
end

local function FillAllAddonDefaults(profile, source)
    for addonName, config in pairs(BazUI.addons) do
        if config.profiles and config.defaults then
            local fresh = profile[addonName] == nil
            if fresh then
                profile[addonName] = {}
            end
            FillAddonDefaults(profile[addonName], config.defaults)
            if fresh then ApplyStarter(addonName, profile[addonName], source) end
        end
    end
end

---------------------------------------------------------------------------
-- Shipped layouts
--
-- A few arrangements that come with the addon, so somebody installing it
-- has something to choose between rather than one look to accept or
-- rebuild from nothing.
--
-- Each is a profile-shaped table, registered from its own file under
-- Core/Presets and written by tools/bake-starter.py from a layout made in
-- game - the same route the shipped starter takes, because it is the same
-- kind of thing.
--
-- Applying one never overwrites what you have. It makes a new profile and
-- switches to it, so a preset is somewhere to start rather than something
-- that can cost you an afternoon's arranging.
---------------------------------------------------------------------------

local presets, presetOrder = {}, {}

function BazUI:RegisterPreset(def)
    if type(def) ~= "table" or type(def.id) ~= "string" then return end
    if type(def.profile) ~= "table" then return end
    if not presets[def.id] then presetOrder[#presetOrder + 1] = def.id end
    presets[def.id] = {
        id          = def.id,
        name        = def.name or def.id,
        description = def.description,
        profile     = def.profile,
    }
    return def.id
end

function BazUI:GetPreset(id) return presets[id] end

function BazUI:GetPresets()
    local out = {}
    for _, id in ipairs(presetOrder) do out[#out + 1] = presets[id] end
    return out
end

-- Make a profile from a preset and switch to it.
--
-- The name is the preset's unless one is given, with a number added
-- rather than replacing a profile that already has that name. Picking
-- "Compact" twice gives you "Compact 2", not a lost afternoon.
function BazUI:CreateProfileFromPreset(presetId, profileName)
    local preset = presets[presetId]
    if not preset then return nil end

    local sv = BazUIDB
    if not sv then return nil end
    sv.profiles = sv.profiles or {}

    local name = profileName or preset.name
    if sv.profiles[name] then
        local n = 2
        while sv.profiles[name .. " " .. n] do n = n + 1 end
        name = name .. " " .. n
    end

    -- Built empty and filled from the preset, rather than copied from the
    -- profile you are on: a preset is meant to be what it says, not what
    -- you happened to have plus what it mentions.
    sv.profiles[name] = {}
    FillAllAddonDefaults(sv.profiles[name], preset.profile)

    self:SetActiveProfile(name)
    return name
end

---------------------------------------------------------------------------
-- Profile Initialization
-- Called once during BazUI's own ADDON_LOADED
---------------------------------------------------------------------------

function BazUI:InitProfiles()
    local sv = BazUIDB

    if not sv.profiles then
        sv.profiles = {}
    end
    if not sv.assignments then
        sv.assignments = {}
    end

    -- Create Default profile if it doesn't exist
    if not sv.profiles[DEFAULT_PROFILE] then
        sv.profiles[DEFAULT_PROFILE] = {}
    end

    -- Default-profile pointer: which profile should brand-new characters
    -- inherit? Falls back to the built-in "Default" if not set, or if
    -- the pointed-to profile no longer exists.
    if sv.defaultProfile and not sv.profiles[sv.defaultProfile] then
        sv.defaultProfile = nil
    end
    local defaultName = sv.defaultProfile or DEFAULT_PROFILE

    -- New character on first login: assign directly to the default profile
    -- (no per-character copy). Changes to the default propagate to every
    -- character using it, which is what users expect from a "default."
    local charKey = GetCharacterKey()
    if charKey ~= "Unknown" and not sv.assignments[charKey] then
        sv.assignments[charKey] = defaultName
    end

    -- Resolve which profile this character should use
    sv.activeProfile = self:ResolveProfile() or DEFAULT_PROFILE

    -- Ensure the resolved profile exists
    if not sv.profiles[sv.activeProfile] then
        sv.profiles[sv.activeProfile] = {}
    end
end

---------------------------------------------------------------------------
-- Per-Addon Profile Setup
-- Called from RegisterModule when profiles = true
-- Ensures the addon's section exists and has defaults filled
---------------------------------------------------------------------------

function BazUI:InitAddonProfile(addonName, config)
    -- Set the profile structure up rather than giving up on it. This used
    -- to return when BazUIDB.profiles was missing, which left the module
    -- with no defaults at all: the db proxy creates its section on the
    -- first write, so the section existed but held only whatever had been
    -- written by hand. addon.db.profile.bars came back nil and creating a
    -- bar errored. Nothing here depends on load order any more.
    BazUIDB = BazUIDB or {}
    local sv = BazUIDB
    if not sv.profiles and self.InitProfiles then
        self:InitProfiles()
    end
    if not sv.profiles then return end

    local profileName = sv.activeProfile or DEFAULT_PROFILE
    local profile = sv.profiles[profileName]
    if not profile then
        profile = {}
        sv.profiles[profileName] = profile
    end

    -- Ensure addon section exists; a brand-new one also gets the starter layout
    local fresh = profile[addonName] == nil
    if fresh then
        profile[addonName] = {}
    end

    -- Fill defaults
    FillAddonDefaults(profile[addonName], config.defaults)
    if fresh then ApplyStarter(addonName, profile[addonName]) end
end

---------------------------------------------------------------------------
-- Defaults, checked over again
--
-- One pass at login over every module that keeps settings in a profile,
-- filling anything the active profile is missing. A module that registered
-- before the profile structure existed, a profile written by an older
-- build, a section the db proxy created on a stray write - all of them end
-- up whole. Only missing keys are written, so nobody's settings change.
---------------------------------------------------------------------------

function BazUI:RepairProfileDefaults()
    local sv = BazUIDB
    if not sv or not sv.profiles then return end

    local profileName = sv.activeProfile or DEFAULT_PROFILE
    local profile = sv.profiles[profileName]
    if not profile then return end

    FillAllAddonDefaults(profile)
end

BazUI:QueueForLogin(function()
    BazUI:RepairProfileDefaults()
end)

---------------------------------------------------------------------------
-- Migration: Pull old per-addon SavedVariables into BazUIDB
---------------------------------------------------------------------------

function BazUI:MigrateAddonProfiles(addonName, oldSVName)
    local oldSV = _G[oldSVName]
    if not oldSV or not oldSV.profiles then return end

    local sv = BazUIDB

    -- Migrate each profile
    for profileName, profileData in pairs(oldSV.profiles) do
        if not sv.profiles[profileName] then
            sv.profiles[profileName] = {}
        end
        -- Only migrate if this addon doesn't already have data in the unified profile
        if not sv.profiles[profileName][addonName] then
            sv.profiles[profileName][addonName] = profileData
        end
    end

    -- Migrate assignments (first addon's assignments win for shared scopes)
    if oldSV.assignments then
        for scope, profileName in pairs(oldSV.assignments) do
            if not sv.assignments[scope] then
                sv.assignments[scope] = profileName
            end
        end
    end

    -- Use the old active profile if we haven't set one yet
    if sv.activeProfile == DEFAULT_PROFILE and oldSV.activeProfile and oldSV.activeProfile ~= DEFAULT_PROFILE then
        if sv.profiles[oldSV.activeProfile] then
            sv.activeProfile = oldSV.activeProfile
        end
    end

    -- Clear old profile data from the addon's SV (keep non-profile data like history)
    oldSV.profiles = nil
    oldSV.assignments = nil
    oldSV.activeProfile = nil
end

---------------------------------------------------------------------------
-- Profile Resolution
-- Determines which profile a character should use based on assignments
---------------------------------------------------------------------------

function BazUI:ResolveProfile()
    local sv = BazUIDB
    if not sv or not sv.assignments then return DEFAULT_PROFILE end

    local assignments = sv.assignments

    -- Priority 1: Character-specific
    local charKey = GetCharacterKey()
    if assignments[charKey] then
        return assignments[charKey]
    end

    -- Priority 2: Class + Spec
    local specKey = GetSpecKey()
    if specKey and assignments[specKey] then
        return assignments[specKey]
    end

    -- Priority 3: Class only
    local classKey = GetClassKey()
    if assignments[classKey] then
        return assignments[classKey]
    end

    -- Priority 4: Default
    return DEFAULT_PROFILE
end

---------------------------------------------------------------------------
-- Profile Management API (unified - no addonName parameter)
---------------------------------------------------------------------------

function BazUI:GetActiveProfile()
    local sv = BazUIDB
    return sv and sv.activeProfile or DEFAULT_PROFILE
end

---------------------------------------------------------------------------
-- Default-Profile Pointer
-- The "default" profile is the one new characters auto-attach to on
-- their first login. Any profile can be promoted to default; the
-- built-in "Default" is the fallback.
---------------------------------------------------------------------------

function BazUI:GetDefaultProfile()
    local sv = BazUIDB
    return (sv and sv.defaultProfile) or DEFAULT_PROFILE
end

function BazUI:SetDefaultProfile(profileName)
    local sv = BazUIDB
    if not sv or not sv.profiles or not sv.profiles[profileName] then
        return false
    end
    sv.defaultProfile = profileName
    BazUI:Fire("BAZ_DEFAULT_PROFILE_CHANGED", profileName)
    return true
end

function BazUI:ClearDefaultProfile()
    local sv = BazUIDB
    if not sv then return false end
    sv.defaultProfile = nil
    BazUI:Fire("BAZ_DEFAULT_PROFILE_CHANGED", DEFAULT_PROFILE)
    return true
end

function BazUI:SetActiveProfile(profileName)
    local sv = BazUIDB
    if not sv or not sv.profiles[profileName] then return false end

    local oldProfile = sv.activeProfile
    sv.activeProfile = profileName

    -- Fill defaults for all addons in the new profile
    FillAllAddonDefaults(sv.profiles[profileName])

    -- Fire callbacks for all addons
    for addonName, config in pairs(BazUI.addons) do
        if config.profiles then
            self:FireProfileChanged(addonName, profileName, oldProfile)
        end
    end

    -- Push a toast through BazNotificationCenter if it's installed
    if oldProfile ~= profileName then
        BazUI:PushNotification({
            module = "_bazui",
            title = "Profile Changed",
            message = "Switched to " .. profileName,
            icon = "Interface\\Icons\\INV_Misc_Book_09",
            priority = "low",
        })
    end
    return true
end

function BazUI:CreateProfile(profileName)
    local sv = BazUIDB
    if not sv then return false end

    sv.profiles = sv.profiles or {}
    if sv.profiles[profileName] then return false end

    sv.profiles[profileName] = {}
    FillAllAddonDefaults(sv.profiles[profileName])

    BazUI:Fire("BAZ_PROFILE_CREATED", profileName)
    return true
end

function BazUI:CopyProfile(fromName, toName)
    local sv = BazUIDB
    if not sv or not sv.profiles then return false end

    local source = sv.profiles[fromName]
    if not source then return false end

    if not sv.profiles[toName] then
        sv.profiles[toName] = {}
    end

    -- Deep copy entire profile (all addon sections)
    wipe(sv.profiles[toName])
    for k, v in pairs(source) do
        if type(v) == "table" then
            sv.profiles[toName][k] = CopyTable(v)
        else
            sv.profiles[toName][k] = v
        end
    end

    BazUI:Fire("BAZ_PROFILE_COPIED", fromName, toName)
    return true
end

function BazUI:DeleteProfile(profileName)
    local sv = BazUIDB
    if not sv or not sv.profiles then return false end

    if sv.activeProfile == profileName then return false end
    if profileName == DEFAULT_PROFILE then return false end

    sv.profiles[profileName] = nil

    -- Clean up assignments pointing to deleted profile
    if sv.assignments then
        for scope, assignedProfile in pairs(sv.assignments) do
            if assignedProfile == profileName then
                sv.assignments[scope] = nil
            end
        end
    end

    -- If the default-profile pointer was on this one, fall back to "Default"
    if sv.defaultProfile == profileName then
        sv.defaultProfile = nil
    end

    BazUI:Fire("BAZ_PROFILE_DELETED", profileName)
    return true
end

function BazUI:RenameProfile(oldName, newName)
    local sv = BazUIDB
    if not sv or not sv.profiles then return false end

    if not oldName or not newName or oldName == "" or newName == "" then return false end
    if oldName == newName then return true end
    if oldName == DEFAULT_PROFILE then return false end
    if sv.profiles[newName] then return false end

    sv.profiles[newName] = sv.profiles[oldName]
    sv.profiles[oldName] = nil

    if sv.activeProfile == oldName then
        sv.activeProfile = newName
    end

    if sv.assignments then
        for scope, assignedProfile in pairs(sv.assignments) do
            if assignedProfile == oldName then
                sv.assignments[scope] = newName
            end
        end
    end

    -- Move the default-profile pointer if it was on the renamed profile
    if sv.defaultProfile == oldName then
        sv.defaultProfile = newName
    end

    BazUI:Fire("BAZ_PROFILE_RENAMED", oldName, newName)
    return true
end

function BazUI:ResetProfile(profileName)
    local sv = BazUIDB
    if not sv or not sv.profiles then return false end

    profileName = profileName or sv.activeProfile
    local profile = sv.profiles[profileName]
    if not profile then return false end

    wipe(profile)
    FillAllAddonDefaults(profile)

    if profileName == sv.activeProfile then
        for addonName, config in pairs(BazUI.addons) do
            if config.profiles then
                self:FireProfileChanged(addonName, profileName, profileName)
            end
        end
    end

    BazUI:Fire("BAZ_PROFILE_RESET", profileName)
    return true
end

function BazUI:ListProfiles()
    local sv = BazUIDB
    if not sv or not sv.profiles then return {} end

    local list = {}
    for name in pairs(sv.profiles) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

---------------------------------------------------------------------------
-- Profile Assignment (unified)
---------------------------------------------------------------------------

-- Which profile a scope is pinned to, or nil.
--
-- The page needs this to show the auto-assign switches as switches. They
-- used to be three buttons you pressed and got no answer from, so there
-- was no way to see what a character was already pinned to except by
-- logging in as it.
function BazUI:GetAssignment(scope)
    local sv = BazUIDB
    if not (sv and sv.assignments) then return nil end
    local key = scope == "character" and GetCharacterKey()
             or scope == "class"     and GetClassKey()
             or scope == "spec"      and GetSpecKey()
    return key and sv.assignments[key] or nil
end

-- What that scope is called on this character, for the switch's label:
-- "This class" says less than "Mage" when you are deciding.
function BazUI:GetAssignmentLabel(scope)
    if scope == "character" then return GetCharacterKey() end
    if scope == "class"     then return GetClassKey() end
    if scope == "spec"      then return GetSpecKey() end
    return nil
end

function BazUI:AssignProfile(scope, profileName)
    local sv = BazUIDB
    if not sv then return false end

    sv.assignments = sv.assignments or {}

    local scopeKey
    if scope == "character" then
        scopeKey = GetCharacterKey()
    elseif scope == "class" then
        scopeKey = GetClassKey()
    elseif scope == "spec" then
        scopeKey = GetSpecKey()
        if not scopeKey then return false end
    else
        return false
    end

    if profileName then
        sv.assignments[scopeKey] = profileName
    else
        sv.assignments[scopeKey] = nil
    end

    return true
end

---------------------------------------------------------------------------
-- Profile Change Callbacks
---------------------------------------------------------------------------

function BazUI:FireProfileChanged(addonName, newProfile, oldProfile)
    local callbacks = profileCallbacks[addonName]
    if callbacks then
        for _, fn in ipairs(callbacks) do
            fn(newProfile, oldProfile)
        end
    end

    -- And the module's own ApplySettings, whether or not it remembered to
    -- ask for it.
    --
    -- Every module that draws anything needs to redraw when the profile
    -- underneath it changes, so wiring that up by hand in each onReady is
    -- a step that can be forgotten - and had been, by three of the twelve.
    -- Chat, Drawers and Notifications kept showing the old profile until
    -- somebody reloaded, which is the sort of thing that reads as the
    -- switch not working.
    --
    -- Deferred by a frame. A profile change is a pile of settings landing
    -- at once, and a module that rebuilds itself partway through that
    -- reads some of the new values and some of the old.
    --
    -- Called after the callbacks, not instead of them: a module that asked
    -- for OnProfileChanged is relying on the order it set up, and this is
    -- an extra pass on top rather than a replacement. ApplySettings has to
    -- be safe to call twice, which is what it means for a thing to be
    -- named ApplySettings.
    local addonObj = BazUI.GetModule and BazUI:GetModule(addonName)
    if addonObj and type(addonObj.ApplySettings) == "function" then
        C_Timer.After(0, function()
            local ok, err = pcall(addonObj.ApplySettings, addonObj)
            if not ok then
                BazUI:Print(("|cffff4444%s could not redraw for the new profile:|r %s")
                    :format(tostring(addonName), tostring(err)))
            end
        end)
    end

    BazUI:Fire("BAZ_PROFILE_CHANGED", addonName, newProfile, oldProfile)
end

---------------------------------------------------------------------------
-- DB Proxy: addon.db.profile accessor
-- Reads/writes BazUIDB.profiles[activeProfile][addonName][key]
---------------------------------------------------------------------------

function BazUI:CreateDBProxy(addonName)
    local profileProxy = setmetatable({}, {
        __index = function(_, key)
            local sv = BazUIDB
            if not sv or not sv.profiles then return nil end
            local profileName = sv.activeProfile or DEFAULT_PROFILE
            local profile = sv.profiles[profileName]
            if not profile or not profile[addonName] then return nil end
            return profile[addonName][key]
        end,
        __newindex = function(_, key, value)
            local sv = BazUIDB
            if not sv then return end
            local profileName = sv.activeProfile or DEFAULT_PROFILE
            if not sv.profiles then sv.profiles = {} end
            if not sv.profiles[profileName] then sv.profiles[profileName] = {} end
            if not sv.profiles[profileName][addonName] then sv.profiles[profileName][addonName] = {} end
            sv.profiles[profileName][addonName][key] = value
        end,
        __pairs = function(_)
            local sv = BazUIDB
            if not sv or not sv.profiles then return next, {}, nil end
            local profileName = sv.activeProfile or DEFAULT_PROFILE
            local section = sv.profiles[profileName] and sv.profiles[profileName][addonName]
            return next, section or {}, nil
        end,
    })

    return { profile = profileProxy }
end

-- AddonMixin method
local AddonMixin = BazUI.AddonMixin

function AddonMixin:OnProfileChanged(handler)
    if not profileCallbacks[self.name] then
        profileCallbacks[self.name] = {}
    end
    table.insert(profileCallbacks[self.name], handler)
end

-- The Profiles page itself lives in Core/ProfilesPage.lua. This file is
-- the profile system; a page about it is a different thing, and by the
-- end the page was two thirds of the file.
