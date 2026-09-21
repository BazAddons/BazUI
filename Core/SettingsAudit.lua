-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: settings audit
--
-- /baz settings - where every module's settings actually live.
--
-- The promise of one profile system is that anything you change while
-- wearing a profile is remembered by that profile, and comes back when
-- you wear it again. Three things can break that promise, and none of
-- them announce themselves:
--
--   1  A module without `profiles = true` never gets a db at all.
--      SetSetting is `if self.db and self.db.profile`, so every write
--      silently does nothing and the setting is gone at the next login.
--
--   2  A module with its own savedVariable keeps those keys outside the
--      profile system. They survive a logout, so they look saved - but
--      they are the same on every profile, which is the opposite of what
--      a profile is for.
--
--   3  Anything written straight to BazUIDB is global for the same
--      reason. Some of that is right (which profile is active, where the
--      options window was scrolled to); some of it is a module taking a
--      shortcut.
--
-- So this reports what is true rather than what was intended: it reads
-- the saved variables themselves. Two profiles holding different values
-- for a key is the only real proof that the key is per-profile, so the
-- report compares the active profile against every other one and says
-- which keys actually differ somewhere.
--
-- Read-only. It never writes a setting.
---------------------------------------------------------------------------

local function Count(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function SortedKeys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = tostring(k) end
    table.sort(out)
    return out
end

-- Same value, to the depth a setting ever goes. Positions and colors are
-- small tables, so a shallow compare would call every one of them equal.
local function Same(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not Same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

---------------------------------------------------------------------------

-- Whether a profile switch will actually redraw this module: either it
-- asked for OnProfileChanged itself, or FireProfileChanged can find an
-- ApplySettings to call - on the module object or on its namespace, the
-- same two places FireProfileChanged looks.
local function Redraws(name, addonObj)
    if BazUI.HasProfileCallback and BazUI:HasProfileCallback(name) then return true end
    if addonObj and type(addonObj.ApplySettings) == "function" then return true end
    local namespace = BazUI.addonNamespaces and BazUI.addonNamespaces[name]
    return (namespace and type(namespace.ApplySettings) == "function") and true or false
end

local function ModuleReport(name, config)
    local sv       = BazUIDB or {}
    local profiles = sv.profiles or {}
    local active   = sv.activeProfile or "Default"
    local section  = profiles[active] and profiles[active][name]
    local addonObj = BazUI.GetAddon and BazUI:GetAddon(name)

    local report = {
        name      = name,
        profiles  = config.profiles and true or false,
        hasDB     = (addonObj and addonObj.db and addonObj.db.profile) and true or false,
        applies   = Redraws(name, addonObj),
        savedVar  = config.savedVariable,
        keys      = Count(section),
        missing   = {},
        varying   = 0,
        elsewhere = 0,
    }

    -- Declared defaults that the profile has no entry for. A key that is
    -- never written is a key whose control is not wired to anything.
    for key in pairs(config.defaults or {}) do
        if not section or section[key] == nil then
            report.missing[#report.missing + 1] = tostring(key)
        end
    end
    table.sort(report.missing)

    -- Keys that genuinely hold different values in different profiles.
    -- This is the only honest test of "per-profile": defaults are equal
    -- everywhere until something is changed, so a low number here on a
    -- fresh profile means nothing, and a zero on a module you have been
    -- setting up means a great deal.
    if section then
        for key, value in pairs(section) do
            for profileName, profile in pairs(profiles) do
                if profileName ~= active and profile[name]
                    and not Same(value, profile[name][key]) then
                    report.varying = report.varying + 1
                    break
                end
            end
        end
    end

    if report.savedVar then
        report.elsewhere = Count(_G[report.savedVar])
    end

    return report
end

local function PrintModules()
    local rows = {}
    for name, config in pairs(BazUI.addons or {}) do
        rows[#rows + 1] = ModuleReport(name, config)
    end
    table.sort(rows, function(a, b) return a.name < b.name end)

    BazUI:Print("|cffffd700Where each module's settings live|r")
    print("  |cff999999module          in profile  differs  notes|r")

    for _, r in ipairs(rows) do
        local notes = {}
        if not r.profiles then
            notes[#notes + 1] = "|cffff4444no profile section - nothing it saves is kept|r"
        elseif not r.hasDB then
            notes[#notes + 1] = "|cffff4444no db - every SetSetting is doing nothing|r"
        end
        if r.savedVar then
            notes[#notes + 1] = ("|cffff8800%d key(s) in %s, the same on every profile|r")
                :format(r.elsewhere, r.savedVar)
        end
        if not r.applies then
            notes[#notes + 1] = "|cffff8800no ApplySettings - will not redraw on a switch|r"
        end
        if #r.missing > 0 then
            notes[#notes + 1] = ("%d default(s) never written: %s"):format(
                #r.missing, table.concat(r.missing, ", "))
        end

        print(("  %-15s %9d  %7d  %s"):format(
            r.name, r.keys, r.varying,
            #notes > 0 and table.concat(notes, "; ") or "|cff44ff44ok|r"))
    end
end

-- Everything in the saved variables that is not inside a profile. Named
-- rather than counted, because whether a given one belongs here is a
-- judgement - the active profile's name obviously does; a module's
-- layout obviously does not.
local KNOWN_GLOBAL = {
    profiles = "the profiles themselves",
    activeProfile = "which one you are wearing",
    defaultProfile = "which one new characters start on",
    assignments = "profiles pinned to a character, spec or class",
    lastProfile = "what each character was last switched to",
    profilePageSelection = "which profile the options page is looking at",
    collapsibles = "which options sections are folded up",
    starterExport = "a baked layout, written by the developer tools",
    starterExportScreen = "same",
    minimapAngle = "where the minimap button sits",
    minimap = "whether the minimap button is shown",
    editMode = "the Edit Mode grid",
    snapping = "whether dragging snaps",
    dockSequence = "the running count of dockings, so a stack is measured as it stood when each piece joined",
    snapFreeModifier = "the key that suspends snapping",
    welcomeMessage = "the login line",
    hideIssueReporter = "the error reporter",
    useFont = "the interface font",
    fontFace = "which of the game's own faces BazUI borrows",
    fontFallback = "whether a string our face cannot spell borrows the game's",
    skin = "left over from when the skin was global; it moves into the profiles on load",
    notifications = "notification history",
    barsCharButtons = "per-character action bar pages",
}

local function PrintGlobals()
    BazUI:Print("|cffffd700Kept outside the profiles, shared by all of them|r")
    for _, key in ipairs(SortedKeys(BazUIDB)) do
        if key ~= "profiles" then
            local note = KNOWN_GLOBAL[key]
            local size = type(BazUIDB[key]) == "table"
                and ("%d key(s)"):format(Count(BazUIDB[key]))
                or tostring(BazUIDB[key])
            print(("  %-22s %-14s %s"):format(key, size,
                note and ("|cff999999" .. note .. "|r")
                     or "|cffff8800not accounted for - should this follow the profile?|r"))
        end
    end
end

local function PrintProfiles()
    local sv = BazUIDB or {}
    local names = SortedKeys(sv.profiles)
    BazUI:Print(("|cffffd700Profiles|r  %d, wearing |cff00ff00%s|r")
        :format(#names, tostring(sv.activeProfile)))
    if #names < 2 then
        print("  |cff999999With only one profile, the 'differs' column above is" ..
              " always zero - make a second and change something to test.|r")
    end
end

-- One module, key by key, across every profile.
--
-- The summary says how many keys differ somewhere; when the answer is
-- surprising, the next question is always "which one, and what does each
-- profile actually hold". Answering that by eye meant /dump into a
-- nested table, so it is answered here instead.
local function Describe(value)
    local kind = type(value)
    if kind == "table" then
        -- Positions and colors are the tables that matter here, and
        -- they are small and flat. Anything larger is summarised.
        local parts, count = {}, 0
        for k, v in pairs(value) do
            count = count + 1
            if count > 4 or type(v) == "table" then
                return ("{%d key(s)}"):format(Count(value))
            end
            parts[#parts + 1] = ("%s=%s"):format(tostring(k), tostring(v))
        end
        table.sort(parts)
        return "{" .. table.concat(parts, " ") .. "}"
    elseif kind == "nil" then
        return "|cff666666-|r"
    end
    return tostring(value)
end

function BazUI:PrintModuleSettings(name)
    local sv       = BazUIDB or {}
    local profiles = sv.profiles or {}
    local active   = sv.activeProfile

    -- Named loosely, since nobody types "UnitFrames" exactly.
    local match
    for moduleName in pairs(BazUI.addons or {}) do
        if moduleName:lower() == name:lower() then match = moduleName break end
    end
    if not match then
        for moduleName in pairs(BazUI.addons or {}) do
            if moduleName:lower():find(name:lower(), 1, true) then match = moduleName break end
        end
    end
    if not match then
        BazUI:Print("No module called '" .. name .. "'.")
        return
    end

    local order = SortedKeys(profiles)
    BazUI:Print(("|cffffd700%s|r, key by key"):format(match))
    print("  |cff999999" .. table.concat(order, "   ") .. "   (|cff00ff00" ..
        tostring(active) .. "|r|cff999999 is the one in use)|r")

    -- Every key any profile has for this module, not just the active
    -- one: a key written only while wearing another profile is exactly
    -- the thing worth seeing.
    local keys = {}
    for _, profileName in ipairs(order) do
        for key in pairs(profiles[profileName][match] or {}) do keys[key] = true end
    end
    for _, key in ipairs(SortedKeys(keys)) do
        local cells, seen, same = {}, nil, true
        for _, profileName in ipairs(order) do
            local section = profiles[profileName][match] or {}
            cells[#cells + 1] = Describe(section[key])
            if seen == nil then seen = cells[#cells]
            elseif seen ~= cells[#cells] then same = false end
        end
        print(("  %-22s %s%s"):format(key,
            same and "|cff999999" or "|cffffd700",
            table.concat(cells, "   ") .. "|r"))
    end
    print("  |cff999999Gold means the profiles disagree, which is what" ..
        " per-profile looks like. Gray means they all hold the same thing.|r")
end

function BazUI:PrintSettingsAudit()
    PrintProfiles()
    PrintModules()
    PrintGlobals()
    BazUI:Print("|cff999999'in profile' is how many keys this profile holds for the" ..
        " module. 'differs' is how many of them hold a different value in some" ..
        " other profile - the proof that a key really is per-profile." ..
        " |cffffd700/baz settings <module>|r|cff999999 shows one module key by key.|r")
end
