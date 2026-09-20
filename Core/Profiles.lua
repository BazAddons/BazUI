-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Profiles Module
-- Unified profile system - one profile controls all Baz Suite addons
-- Profiles stored in BazUIDB.profiles[profileName][addonName] = { ... }
---------------------------------------------------------------------------

local DEFAULT_PROFILE = "BazUI"

-- What that profile used to be called.
--
-- Renaming somebody's profile is rewriting their settings, and a profile
-- name turns up in character pins, in the default-profile pointer and in
-- whatever they have written down. So an install that already has a
-- "Default" keeps it and goes on using it as its fallback; only a fresh
-- one gets the new name. The two never coexist as the fallback - the
-- moment a "BazUI" profile exists, that is the one.
local LEGACY_DEFAULT = "Default"

-- The profile to fall back on: the one that cannot be deleted or renamed,
-- and the one a character with no pin ends up wearing.
--
-- Asked for by name from the panels as well, so that the control that
-- greys out Rename and the code that refuses it are answering the same
-- question. They used to hold a copy of the name each, which was fine
-- while there was only ever one name.
local function FallbackProfile(sv)
    sv = sv or BazUIDB
    local profiles = sv and sv.profiles
    if profiles and profiles[LEGACY_DEFAULT] and not profiles[DEFAULT_PROFILE] then
        return LEGACY_DEFAULT
    end
    return DEFAULT_PROFILE
end

function BazUI:GetFallbackProfile()
    return FallbackProfile()
end

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
    -- A shipped layout that says nothing about a module is not asking for
    -- that module to be left bare - it simply did not have it when the
    -- arrangement was made. The starter layout stands in, so choosing one
    -- never comes out worse than a fresh install.
    local starter = (source and source[addonName])
        or (BazUI.StarterProfile and BazUI.StarterProfile[addonName])
    if starter then DeepMerge(section, starter) end
end

-- Everything in a layout that is not a module's section.
--
-- FillAllAddonDefaults walks the list of registered modules, so a key
-- belonging to the profile itself would be dropped on the way through -
-- and the skin is exactly that kind of key. It is also most of what tells
-- Classic and Modern apart, so losing it would have made the two shipped
-- layouts look like each other.
--
-- Only ever fills a gap. A profile that already says something keeps it.
local function ApplyProfileKeys(profile, source)
    if not source then return end
    for key, value in pairs(source) do
        if not (BazUI.addons and BazUI.addons[key]) and profile[key] == nil then
            profile[key] = (type(value) == "table") and CopyTable(value) or value
        end
    end
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
    ApplyProfileKeys(profile, source or BazUI.StarterProfile)
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
    local fallback = FallbackProfile(sv)
    if not sv.profiles[fallback] then
        sv.profiles[fallback] = {}
    end

    -- Default-profile pointer: which profile should brand-new characters
    -- inherit? Falls back to the built-in "Default" if not set, or if
    -- the pointed-to profile no longer exists.
    if sv.defaultProfile and not sv.profiles[sv.defaultProfile] then
        sv.defaultProfile = nil
    end
    local defaultName = sv.defaultProfile or fallback

    -- A character used to be pinned to the default profile the first time
    -- it logged in. Nobody asked for that pin, and because a character
    -- pin outranks everything, it undid any profile you switched to the
    -- moment you reloaded - the switch held all session and then quietly
    -- went back.
    --
    -- The pins that were written are cleared here rather than left to
    -- confuse. Only the ones pointing at the default profile: pinning a
    -- character to the default is what the fallback does anyway, so
    -- dropping it changes nothing for anyone who meant it, while a pin
    -- to any other profile was deliberate and is left alone.
    local charKey = GetCharacterKey()
    if charKey ~= "Unknown" and sv.assignments[charKey] == defaultName then
        sv.assignments[charKey] = nil
    end

    -- What this character should wear. A pin it was deliberately given
    -- wins; failing that, whatever it was last switched to, so a reload
    -- leaves you where you were; failing that, the default.
    sv.activeProfile = self:ResolveProfile() or fallback

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

---------------------------------------------------------------------------
-- The profiles that come with the addon
--
-- Three of them, so somebody installing it has something to compare
-- rather than one look to accept or rebuild from nothing. "BazUI" wears
-- the starter layout; Classic and Modern are shipped layouts registered
-- from their own files under Core/Presets.
--
-- Made once and written down as made. Deleting one has to stick, or a
-- profile you got rid of turns up again at the next login - so what has
-- been created is remembered rather than worked out from what is there
-- now.
--
-- At login rather than at ADDON_LOADED, because building a profile means
-- filling every module's section and the modules have not registered yet
-- when the profile structure is first set up.
---------------------------------------------------------------------------

local SHIPPED = {
    { name = DEFAULT_PROFILE },
    { name = "Classic", preset = "Classic" },
    { name = "Modern",  preset = "Modern"  },
}

function BazUI:SeedShippedProfiles()
    local sv = BazUIDB
    if not (sv and sv.profiles) then return end
    sv.shippedProfiles = sv.shippedProfiles or {}

    -- An install from before the shipped set already has the starter
    -- layout, under the name it went by then. Counting it as made keeps a
    -- second copy of the same arrangement from appearing beside it.
    if sv.profiles[LEGACY_DEFAULT] and not sv.profiles[DEFAULT_PROFILE] then
        sv.shippedProfiles[DEFAULT_PROFILE] = true
    end

    for _, shipped in ipairs(SHIPPED) do
        if not sv.shippedProfiles[shipped.name] then
            sv.shippedProfiles[shipped.name] = true
            if not sv.profiles[shipped.name] then
                local preset = shipped.preset and self:GetPreset(shipped.preset)
                sv.profiles[shipped.name] = {}
                FillAllAddonDefaults(sv.profiles[shipped.name],
                    preset and preset.profile or nil)
            end
        end
    end
end

BazUI:QueueForLogin(function()
    BazUI:SeedShippedProfiles()
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

    -- Priority 4: whatever this character was last switched to. A
    -- profile that has since been deleted is skipped rather than
    -- resurrected.
    local last = sv.lastProfile and sv.lastProfile[charKey]
    if last and sv.profiles and sv.profiles[last] then
        return last
    end

    -- Priority 5: the profile new characters start on.
    return sv.defaultProfile or DEFAULT_PROFILE
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

    -- Remembered per character, so a reload comes back to it. Per
    -- character rather than one global answer because two characters
    -- wearing different profiles is the ordinary case, and a single
    -- value would mean whichever logged in last decided for both.
    --
    -- Not written as an assignment: a pin is something the player set on
    -- the Profiles page and expects to hold, and quietly rewriting it
    -- every time somebody tried another layout would make the pins on
    -- that page lie.
    local charKey = GetCharacterKey()
    if charKey ~= "Unknown" then
        sv.lastProfile = sv.lastProfile or {}
        sv.lastProfile[charKey] = profileName
    end

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
    if profileName == FallbackProfile(sv) then return false end

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
    if oldName == FallbackProfile(sv) then return false end
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

    -- And what each character was last switched to, or a rename would
    -- send everyone back to the default on their next reload.
    if sv.lastProfile then
        for charKey, name in pairs(sv.lastProfile) do
            if name == oldName then
                sv.lastProfile[charKey] = newName
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

-- Whether a module asked to be told about a profile change. Only the
-- settings audit needs this; profileCallbacks is a file-local and the
-- question is worth answering honestly rather than by guessing from
-- outside.
function BazUI:HasProfileCallback(addonName)
    local list = profileCallbacks[addonName]
    return (list and #list > 0) and true or false
end

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
    -- Looked for on the object RegisterModule handed back, and then on
    -- the module's own namespace table, because they are not always the
    -- same table. Notifications keeps its ApplySettings on
    -- BazUI.Notifications, so this looked straight past it - and that
    -- module was left as the one thing still showing the old profile
    -- after a fallback written to stop exactly that. The bell staying
    -- put when you switched layouts was this, not a position that had
    -- failed to save.
    local host = BazUI.GetModule and BazUI:GetModule(addonName)
    if not (host and type(host.ApplySettings) == "function") then
        local namespace = BazUI.addonNamespaces and BazUI.addonNamespaces[addonName]
        if namespace and type(namespace.ApplySettings) == "function" then
            host = namespace
        end
    end

    if host and type(host.ApplySettings) == "function" then
        C_Timer.After(0, function()
            local ok, err = pcall(host.ApplySettings, host)
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
