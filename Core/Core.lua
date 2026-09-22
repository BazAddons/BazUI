-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Core Module
-- Module registry, lifecycle management, module objects
---------------------------------------------------------------------------

BazUI = BazUI or {}
BazUI.addons = {}
BazUI.addonObjects = {}
local ADDON_NAME = ...
BazUI.ADDON_NAME = ADDON_NAME
BazUI.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"

---------------------------------------------------------------------------
-- Did the saved variables arrive?
--
-- Positions, bar contents and the module switches all revert on reload,
-- and two consecutive saves each held one login entry rather than the
-- second holding both - so the file is written and then not read back.
-- This writes down what BazUIDB held at each of the three moments it
-- could go missing, and says so at login.
---------------------------------------------------------------------------

local function CountKeys(t)
    if type(t) ~= "table" then return -1 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- The names matter more than the count: four keys at ADDON_LOADED is
-- either four of the nine the file holds, or four somebody else put there.
local function KeyNames(t)
    if type(t) ~= "table" then return "absent" end
    local names = {}
    for k in pairs(t) do names[#names + 1] = tostring(k) end
    table.sort(names)
    return #names > 0 and table.concat(names, ", ") or "none"
end

BazUI._svTrace = {
    atFileLoad      = CountKeys(_G.BazUIDB),
    namesAtFileLoad = KeyNames(_G.BazUIDB),
    -- EventUtil.ContinueOnAddOnLoaded runs its callback immediately when the
    -- addon already counts as loaded, and its queue is not ours to order, so
    -- the reading taken there is not necessarily the event itself. This frame
    -- is: a plain handler, registered before anything else in the addon runs.
    saysLoadedAtFileLoad = C_AddOns.IsAddOnLoaded(ADDON_NAME) and "yes" or "no",
}

-- Every change to the table, in order.
--
-- The readings so far are snapshots, and a snapshot cannot say whether the
-- file's eight keys ever arrived and were then replaced. This watches the
-- global every frame from here until login and writes down each distinct
-- shape it takes. If a table holding barsCharButtons or moduleSwitchLog
-- ever appears, the file is being read and something of ours is discarding
-- it; if one never does, the file is never executed.
BazUI._svTrace.shapes = {}

local sampler = CreateFrame("Frame")
local lastShape
sampler:SetScript("OnUpdate", function()
    local shape = KeyNames(_G.BazUIDB)
    if shape ~= lastShape then
        lastShape = shape
        local shapes = BazUI._svTrace.shapes
        shapes[#shapes + 1] = shape
        if #shapes > 12 then sampler:SetScript("OnUpdate", nil) end
    end
end)

---------------------------------------------------------------------------
-- When the saved variables are really there
--
-- Not EventUtil.ContinueOnAddOnLoaded. On this client C_AddOns.IsAddOnLoaded
-- already answers true for BazUI while BazUI's own files are still running,
-- so that helper fires its callback at once, during file load - before the
-- client has loaded the saved variables. Everything we set up in there was
-- built on a BazUIDB we had just invented, and the file on disk never got a
-- look in: positions, bar contents, ability placement and the module
-- switches all came back to their defaults on every reload.
--
-- /baz sv is what settled it: "our ADDON_LOADED: absent" - BazUIDB was nil
-- when that callback ran - against "ADDON_LOADED event:" a moment later
-- holding the four keys the callback itself had just created.
--
-- A plain handler for the event is the fix, and it is the only place in the
-- addon allowed to decide that the database exists. QueueForVariables(fn)
-- runs fn then, or at once if the moment has passed.
---------------------------------------------------------------------------

local variablesReady = false
local variablesQueue = {}

function BazUI:QueueForVariables(fn)
    if variablesReady then
        fn()
    else
        variablesQueue[#variablesQueue + 1] = fn
    end
end

-- The saved variables are late on this client, not missing.
--
-- ADDON_LOADED is where an addon is supposed to find its database, and on
-- Forever it is empty there - which is what made it look like the file was
-- never read at all. It is read; it just arrives later. Other authors on
-- the WoW UI Discord found the same thing and put it plainly: "SV don't
-- exist until PLAYER_LOGIN, SV table nil @ ADDON_LOADED". Our own /baz sv
-- has been saying the same for a day - "ADDON_LOADED: absent, login: 7
-- keys" - and we read it as our defaults arriving rather than the file.
--
-- Reading too early is worse than reading late, because what we build on
-- the nil is then written back over the file at logout. So the queue is
-- drained the moment BazUIDB is really there: at ADDON_LOADED on a client
-- that has it by then, and at PLAYER_LOGIN on one that does not.
--
-- The TOC directive LoadSavedVariablesFirst does not help; several people
-- tried it before we did.
local function ReadyVariables()
    if variablesReady then return end
    variablesReady = true

    -- Counted here rather than at a fixed event, so it counts loads rather
    -- than how early we looked. If this climbs, the file is being read.
    --
    -- Read before Persist runs, and written after, so it goes on answering
    -- the question it was made for - has the client started reading saved
    -- variables - rather than quietly becoming a readout of the place we
    -- moved them to.
    -- Both files, because they fail independently: a character came back
    -- with three previous loads while the account file was absent. Read
    -- before Persist runs and written after, so each goes on answering the
    -- question it was made for about its own file. See Core/Persist.lua.
    local t = BazUI._svTrace
    t.accountLoads = (type(_G.BazUIDB) == "table" and _G.BazUIDB.loads) or 0
    _G.BazUICharDB = _G.BazUICharDB or {}
    t.charLoads = _G.BazUICharDB.loads or 0

    -- Here, and only here. This is the moment the saved variables are as
    -- real as this client is going to make them, and the last moment
    -- before anything reads a setting: Persist may replace both globals
    -- outright with the copies the host table was holding, and a module
    -- that had already taken a reference would be writing into a table
    -- nobody is going to save. See Core/Persist.lua.
    if BazUI.Persist then BazUI.Persist:Adopt() end

    _G.BazUICharDB = _G.BazUICharDB or {}
    _G.BazUICharDB.loads = (_G.BazUICharDB.loads or 0) + 1
    _G.BazUIDB = _G.BazUIDB or {}
    _G.BazUIDB.loads = (_G.BazUIDB.loads or 0) + 1

    for _, entry in ipairs(variablesQueue) do entry() end
    wipe(variablesQueue)
end

BazUI.ReadyVariables = ReadyVariables

local svProbe = CreateFrame("Frame")
svProbe:RegisterEvent("ADDON_LOADED")
svProbe:RegisterEvent("PLAYER_LOGIN")
svProbe:RegisterEvent("PLAYER_ENTERING_WORLD")
svProbe:SetScript("OnEvent", function(self, event, name)
    local t = BazUI._svTrace
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        t.atRawEvent = CountKeys(_G.BazUIDB)
        t.namesAtRawEvent = KeyNames(_G.BazUIDB)
        self:UnregisterEvent("ADDON_LOADED")

        -- Noted, not acted on. Whatever is in BazUIDB at this point is
        -- either nothing or our own seed, and treating either as the file
        -- is how the real one got thrown away. Waiting for login costs a
        -- healthy client nothing: its saved variables are there at both
        -- moments, and no module reads a setting before login anyway.
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        t.atLoginRaw = KeyNames(_G.BazUIDB)
        ReadyVariables()
    else
        t.atEnteringWorld = CountKeys(_G.BazUIDB)
        sampler:SetScript("OnUpdate", nil)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)

---------------------------------------------------------------------------
-- Addon Object Prototype
-- Other modules extend this via BazUI.AddonMixin
---------------------------------------------------------------------------

local AddonMixin = {}
AddonMixin.__index = AddonMixin
BazUI.AddonMixin = AddonMixin

function AddonMixin:GetSetting(key)
    if self.db and self.db.profile then return self.db.profile[key] end
end

function AddonMixin:SetSetting(key, value)
    if self.db and self.db.profile then self.db.profile[key] = value end
end

---------------------------------------------------------------------------
-- Lifecycle: PLAYER_LOGIN queue
---------------------------------------------------------------------------

local loginReady = false
local loginQueue = {}
local lifecycleFrame = CreateFrame("Frame")

-- Nothing is built while a fight is on.
--
-- Almost everything the addon puts on screen is a secure frame or carries
-- one: action buttons, aura buttons, unit bars. Creating, anchoring or
-- stamping attributes on those is refused in combat - and PLAYER_LOGIN
-- fires during the fight if you /reload while something is hitting you.
-- Every module then built into a wall of refusals and never tried again,
-- which is the "reload in combat and the whole interface is gone until you
-- reload a second time" case.
--
-- So the queue waits the fight out instead. The cost is an interface that
-- arrives a few seconds late in the one case where it used to arrive
-- broken, and a line saying why, so it does not look like a crash.
--
-- Drained one at a time, checking before each, because a fight can start in
-- the middle of it. Being attacked *during* the reload is the case that
-- actually happens:
-- PLAYER_LOGIN arrives out of combat, the queue begins, and the wolf lands
-- its first hit somewhere around the fourth module. Testing only at the
-- start let everything after that point build into refusals - empty action
-- bars, a minimap left where it was made, the game's own frames back.
--
-- Whatever has not run is left in the queue and picked up when the fight
-- ends. What has already run stays run; this is about not losing the rest.
local function DrainLogin()
    -- Ordering, said out loud rather than left to which frame registered
    -- PLAYER_LOGIN first: nothing is built until the database is claimed.
    if BazUI.ReadyVariables then BazUI.ReadyVariables() end

    loginReady = true

    while loginQueue[1] do
        if InCombatLockdown() then
            lifecycleFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            BazUI:Print("Combat started while the interface was being built - "
                .. "finishing once the fight is over.")
            return
        end

        -- One module failing is not allowed to strand the rest of them.
        local entry = table.remove(loginQueue, 1)
        local ok, err = pcall(entry)
        if not ok then
            BazUI._loginErrors = BazUI._loginErrors or {}
            BazUI._loginErrors[#BazUI._loginErrors + 1] = tostring(err)
        end
    end

    -- Said out loud rather than collected quietly. A module that fails to
    -- start leaves a hole somebody has to notice, and a silent pcall is how
    -- a half-built interface looks like a mystery instead of a bug.
    local errors = BazUI._loginErrors
    if errors and #errors > 0 and not BazUI._loginErrorsTold then
        BazUI._loginErrorsTold = true
        BazUI:Print(("|cffff6666%d part%s of the interface did not start.|r Type "
            .. "|cff00ff00/baz errors|r to see why."):format(
            #errors, #errors == 1 and "" or "s"))
    end
end

lifecycleFrame:RegisterEvent("PLAYER_LOGIN")
lifecycleFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if InCombatLockdown() then
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
            print("|cff8fd3ffBazUI|r: waiting for combat to end before building the interface.")
            return
        end
        DrainLogin()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        DrainLogin()
    end
end)

-- QueueForLogin(fn)
--   Queues a callback for PLAYER_LOGIN, or runs it at once if login has
--   already happened.
function BazUI:QueueForLogin(fn)
    if loginReady then
        fn()
    else
        table.insert(loginQueue, fn)
    end
end

-- The same, for work that belongs to a module.
--
-- A module does plenty at login outside its onReady: hooking the bag
-- keys, seeding categories, registering widgets. Switching it off has to
-- stop that too, and the only honest way to know whose work a queued
-- function is, is for the file to say so. Inferring it from the call
-- stack worked in theory and not in the game.
--
-- Asked when the work would run rather than when it was queued, since a
-- module's settings are not ready while its files are still loading.
function BazUI:QueueForModule(name, fn)
    self:QueueForLogin(function()
        if BazUI.IsModuleEnabled and not BazUI:IsModuleEnabled(name) then return end
        fn()
    end)
end

---------------------------------------------------------------------------
-- Module Registration
--
-- Modules are the units of BazUI (Drawers, Chat, Bags, ...). Each one
-- registers here with its defaults, slash commands and lifecycle hooks
-- and gets back a module object whose db.profile proxy points at its
-- section of the active profile in BazUIDB. The API keeps the old
-- BazUI names (GetAddon) as an alias so ported code
-- keeps working.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Turning a module off
--
-- Off means not built, rather than built and then hidden. A module that
-- is off never runs its onReady, claims no slash command, adds no
-- minimap entry and no settings pages: it costs what an unticked box
-- ought to cost. That also means turning one back on takes a reload,
-- since what it would have built during login cannot be conjured
-- afterwards, and half of it is secure and could not be unbuilt anyway.
--
-- Kept per profile, like everything else here, so a raiding profile can
-- drop what a levelling one keeps.
---------------------------------------------------------------------------

-- Modules nobody should be able to switch off. The Codex is a window you
-- open rather than something on screen, and it is where the manual and
-- the item lookup live.
local ALWAYS_ON = { Codex = true, Tooltip = true }

local function ModuleFlags()
    local sv = _G.BazUIDB
    if not (sv and sv.profiles and sv.activeProfile) then return nil end
    local profile = sv.profiles[sv.activeProfile]
    if not profile then return nil end
    profile.Core = profile.Core or {}
    profile.Core.modules = profile.Core.modules or {}
    return profile.Core.modules
end

function BazUI:ModuleCanBeDisabled(name)
    return not ALWAYS_ON[name]
end

function BazUI:IsModuleEnabled(name)
    if ALWAYS_ON[name] then return true end
    local flags = ModuleFlags()
    return not (flags and flags[name] == false)
end

-- What the flags looked like at login, written down once so a reload can
-- be compared against what the switch was set to.
function BazUI:RecordModuleFlagsAtLogin()
    local sv = _G.BazUIDB
    if not sv then return end
    local flags = ModuleFlags()
    local seen = {}
    if flags then
        for k, v in pairs(flags) do seen[#seen + 1] = k .. "=" .. tostring(v) end
    end
    table.sort(seen)
    sv.moduleSwitchLog = sv.moduleSwitchLog or {}
    local log = sv.moduleSwitchLog
    log[#log + 1] = ("%s LOGIN flags:[%s] profile:%s"):format(
        date("%H:%M:%S"),
        #seen > 0 and table.concat(seen, ",") or "empty",
        tostring(sv.activeProfile))
    while #log > 40 do table.remove(log, 1) end
end

-- A record of every switch thrown, kept in the saved variables.
--
-- The module switches have been going back on by themselves and reading
-- the code has not explained it, so this writes down what actually
-- happened: who asked, for what, and whether the flag was there to write
-- to. Read it out of SavedVariables\BazUI.lua under moduleSwitchLog.
local function RecordSwitch(name, enabled, wrote)
    local sv = _G.BazUIDB
    if not sv then return end
    sv.moduleSwitchLog = sv.moduleSwitchLog or {}
    local log = sv.moduleSwitchLog
    log[#log + 1] = ("%s %s -> %s (%s)"):format(
        date("%H:%M:%S"), name, tostring(enabled),
        wrote and "written" or "NO FLAGS TABLE")
    -- Keep it short; only the last few matter.
    while #log > 40 do table.remove(log, 1) end
end

function BazUI:SetModuleEnabled(name, enabled)
    if ALWAYS_ON[name] then return end
    local flags = ModuleFlags()
    RecordSwitch(name, enabled, flags ~= nil)
    if not flags then return end

    -- Written out rather than `enabled and nil or false`, which cannot
    -- work: `true and nil` is nil, nil is false, and the `or` takes over
    -- every time. That idiom can never yield nil, so ticking a module
    -- switched it off again.
    if enabled then
        flags[name] = nil
    else
        flags[name] = false
    end
end

function BazUI:RegisterModule(name, config)
    self.addons[name] = config

    -- Create addon object with convenience methods
    local addon = setmetatable({
        name = name,
        config = config,
        loaded = false,
    }, AddonMixin)
    self.addonObjects[name] = addon

    -- Capture the calling file's per-addon shared table (the second
    -- vararg `(...)` in standard WoW addon Lua, conventionally named
    -- `addon` or `BazXXX` in the file's locals). This is where
    -- modules typically attach themselves (addon.Replica = Replica,
    -- addon.Window = Window, etc.) - i.e. the actual namespace tree
    -- the CPU profiler's drill-down walker needs to find functions
    -- in. WoW doesn't expose these tables anywhere by default, so we
    -- fish it out of the caller's locals via the debug API. Stored
    -- on BazUI.addonNamespaces[name] keyed by addon name.
    --
    -- Looks for a table-typed local named "addon" (the convention
    -- across the Baz suite) in the caller's frame. Falls back to
    -- scanning all locals for the first table that contains common
    -- addon-shared keys, so non-conforming naming still works.
    self.addonNamespaces = self.addonNamespaces or {}
    if debug and debug.getlocal then
        local found
        local i = 1
        while true do
            local lname, lval = debug.getlocal(2, i)
            if not lname then break end
            if type(lval) == "table" and (lname == "addon" or lname == name) then
                found = lval
                break
            end
            i = i + 1
        end
        if found then self.addonNamespaces[name] = found end
    end

    -- Deferred init on ADDON_LOADED. Every module lives inside this one
    -- addon, so its saved variables are ready when BazUI's own
    -- ADDON_LOADED fires (immediately if we're already past it).
    BazUI:QueueForVariables(function()
        -- Initialize saved variables (for addons that still have their own SV, e.g. BNC history)
        if config.savedVariable then
            local svName = config.savedVariable
            _G[svName] = _G[svName] or {}

            if not config.profiles and config.defaults then
                local sv = _G[svName]
                for k, v in pairs(config.defaults) do
                    if sv[k] == nil then sv[k] = v end
                end
            end
        end

        -- Unified profile setup: addon data lives in BazUIDB.profiles
        if config.profiles and BazUI.InitAddonProfile then
            -- Migrate old per-addon SV profiles into BazUIDB (one-time)
            if config.savedVariable and BazUI.MigrateAddonProfiles then
                BazUI:MigrateAddonProfiles(name, config.savedVariable)
            end

            -- Ensure addon section exists with defaults in active profile
            BazUI:InitAddonProfile(name, config)

            -- Auto-wire addon.db.profile proxy
            if BazUI.CreateDBProxy then
                addon.db = BazUI:CreateDBProxy(name)
            end
        end

        -- Switched off in this profile: the settings above are still
        -- set up, so what it remembers survives being turned off and on
        -- again, and nothing else about it happens.
        if not BazUI:IsModuleEnabled(name) then
            addon.disabled = true
            addon.loaded = true
            return
        end

        -- onLoad callback (SV ready, before UI)
        if config.onLoad then
            config.onLoad(addon)
        end


        -- Register slash commands (Commands module)
        if config.slash and BazUI.RegisterCommands then
            BazUI:RegisterCommands(name, config)
        end

        -- Register minimap entry (MinimapButton module)
        if config.minimap and BazUI.RegisterMinimapEntry then
            BazUI:RegisterMinimapEntry(name, config.minimap)
        end

        addon.loaded = true

        -- onReady callback (after SV + UI init + PLAYER_LOGIN). The
        -- label flows through to the memory-log phase markers so a
        -- /bazmem armwatch dump shows per-addon onReady cost.
        if config.onReady then
            BazUI:QueueForLogin(function()
                config.onReady(addon)
            end)
        end
    end)

    return addon
end

function BazUI:GetModule(name)
    return self.addonObjects[name]
end
BazUI.GetAddon = BazUI.GetModule

-- Static setting access by module name, for shared helpers that don't
-- hold a module object.
function BazUI:GetSetting(moduleName, key)
    local mod = self.addonObjects[moduleName]
    return mod and mod:GetSetting(key)
end

function BazUI:SetSetting(moduleName, key, value)
    local mod = self.addonObjects[moduleName]
    if mod then mod:SetSetting(key, value) end
end

---------------------------------------------------------------------------
-- Stack introspection

---------------------------------------------------------------------------
-- Context Menu Sections
---------------------------------------------------------------------------
--
-- Lets any addon contribute entries to a context menu owned by another
-- addon. The owning addon keeps owning the trigger and the anchor (e.g.
-- BazBags catches shift+right-click on its bag slots) and asks BazUI
-- to build the menu via OpenContextMenu(scope, anchor, context). BazUI
-- fans out to every section registered against that scope, calls each
-- section's getItems(context) at menu-open time, and assembles a single
-- MenuUtil context menu with one section per addon.
--
-- Scopes are strings that name the click context. Current vocabulary:
--   "bag-item"  - shift+right-click on a bag slot (owned by BazBags)
--
-- Sections return a list of items at menu-open time so they can inspect
-- the context and skip rendering when they have nothing to offer
-- (return nil or an empty array). Each item is one of:
--   { label, onClick, disabled = bool? }   - regular button
--   { divider = true }                     - separator within a section
--   { label, submenu = { items } }         - flyout submenu (no onClick;
--                                            hover the parent to open).
--                                            Submenus nest arbitrarily.
---------------------------------------------------------------------------

BazUI._ctxSections = BazUI._ctxSections or {}

-- The menu frame the game hands back is what gets our chrome, and its
-- own background is hidden to make room. Both are things about the menu
-- system rather than API, so /baz check asks after them.
--
-- Queued rather than declared here and now: this is the first file the
-- addon loads, and Core/Compat.lua, which takes the declaration, has not
-- loaded yet. Calling it at file scope killed the rest of this file.
BazUI:QueueForLogin(function()
    -- The coin art beside a money amount, for the same reason.
    for _, kind in ipairs({ "gold", "silver", "copper" }) do
        BazUI:RegisterDependency({
            module = "BazUI",
            label  = BazUI.COIN_ICONS[kind],
            why    = "The coin drawn beside a money amount.",
            check  = function() return BazUI.Has.Texture(BazUI.COIN_ICONS[kind]) end,
        })
    end

    BazUI:RegisterDependency({
        module = "BazUI",
        label  = "MenuUtil.CreateContextMenu returns its menu",
        why    = "The frame our context menus are skinned on.",
        check  = function()
            return BazUI.Has.Member(_G.MenuUtil, "CreateContextMenu")
        end,
    })
end)

function BazUI:RegisterContextMenuSection(scope, addonName, getItems)
    if type(scope)     ~= "string"   or scope     == "" then return end
    if type(addonName) ~= "string"   or addonName == "" then return end
    if type(getItems)  ~= "function" then return end

    local list = self._ctxSections[scope]
    if not list then
        list = {}
        self._ctxSections[scope] = list
    end
    list[#list + 1] = { addonName = addonName, getItems = getItems }
end

-- Open the registered context menu for `scope`, anchored to `anchor`,
-- with the click `context` passed to each section's getItems.
--
-- options.title (optional) - string rendered as a top-level menu title
--                            above all sections. BazBags uses this for
--                            the item link of the clicked slot, so the
--                            menu identifies its target up top.
function BazUI:OpenContextMenu(scope, anchor, context, options)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    options = options or {}

    local sections = self._ctxSections[scope]
    if not sections or #sections == 0 then return end

    -- Pre-resolve so empty sections don't leave orphaned dividers
    -- between sections that DID return items.
    local resolved = {}
    for _, section in ipairs(sections) do
        local ok, items = pcall(section.getItems, context)
        if ok and type(items) == "table" and #items > 0 then
            resolved[#resolved + 1] = {
                addonName = section.addonName,
                items     = items,
            }
        end
    end
    if #resolved == 0 then return end

    -- Recursive item renderer. Handles plain buttons, dividers, and
    -- submenus (a button whose `submenu` field is an array of child
    -- items). Submenus nest arbitrarily because RenderItem calls
    -- itself on each child.
    local function RenderItem(parent, item)
        if item.divider then
            parent:CreateDivider()
            return
        end
        if type(item.submenu) == "table" then
            local sub = parent:CreateButton(item.label or "?")
            for _, child in ipairs(item.submenu) do
                RenderItem(sub, child)
            end
            if item.disabled and sub and sub.SetDisabled then
                sub:SetDisabled(true)
            end
            return
        end
        local btn = parent:CreateButton(item.label or "?", function()
            if type(item.onClick) == "function" then
                item.onClick()
            end
        end)
        if item.disabled and btn and btn.SetDisabled then
            btn:SetDisabled(true)
        end
    end

    local menu = MenuUtil.CreateContextMenu(anchor, function(_, root)
        if options.title then
            root:CreateTitle(options.title)
        end
        for i, section in ipairs(resolved) do
            if options.title or i > 1 then root:CreateDivider() end
            root:CreateTitle(section.addonName)
            for _, item in ipairs(section.items) do
                RenderItem(root, item)
            end
        end
    end)

    -- Ours, so it wears our chrome. Done to the frame the game hands
    -- back rather than to the menu system: that frame comes out of a pool
    -- the game also uses for its own menus, and restyling every dropdown
    -- in the game is a much larger claim than making ours match.
    local theme = BazUI.Skin and BazUI.Skin.Theme
    if menu and theme and theme.ApplyMenuChrome then
        theme.ApplyMenuChrome(menu)
    end

    return menu
end

---------------------------------------------------------------------------
-- BazUI's own settings page (registered after all modules load)
---------------------------------------------------------------------------

-- Initialize unified profile structure early (before addons load)
BazUI:QueueForVariables(function()
    BazUI._svTrace.atAddonLoaded = CountKeys(_G.BazUIDB)
    BazUI._svTrace.namesAtAddonLoaded = KeyNames(_G.BazUIDB)
    BazUIDB = BazUIDB or {}
    if BazUI.InitProfiles then
        BazUI:InitProfiles()
    end
end)

BazUI:QueueForLogin(function()
    if not BazUI.RegisterOptionsTable then return end

    BazUIDB = BazUIDB or {}
    BazUIDB.minimap = BazUIDB.minimap or { hide = false }

    BazUIDB.welcomeMessage = BazUIDB.welcomeMessage == nil and true or BazUIDB.welcomeMessage

    -- (the rest of this callback registers BazUI's own pages -
    -- Landing, Settings subcategory, Profiles subcategory)
    -- Labeled "BazUISelfPages" so the memory-log phase markers
    -- attribute any allocation that happens here cleanly.

    -- Root entry. BazUI's own pages (General Settings, Profiles, User
    -- Manual) are tabs on the BazUI category's canvas; the root itself
    -- never renders because it has pages.
    BazUI:RegisterOptionsTable("BazUI", function()
        return { name = "BazUI", type = "group", args = {} }
    end)
    BazUI:AddToSettings("BazUI", "BazUI")

    -- Settings subcategory
    BazUI:RegisterOptionsTable("BazUI-Settings", function()
        local options = {
            name = "General",
            type = "group",
            args = {
                minimapBtn = {
                    order = 1,
                    type = "toggle",
                    name = "Show the minimap button",
                    desc = "The BazUI button on the minimap ring.",
                    get = function() return not BazUIDB.minimap.hide end,
                    set = function(_, val)
                        BazUIDB.minimap.hide = not val
                        if val then
                            BazUI:ShowMinimapButton()
                        else
                            BazUI:HideMinimapButton()
                        end
                    end,
                },
                welcomeMsg = {
                    order = 2,
                    type = "toggle",
                    name = "Show welcome messages",
                    desc = "The line in chat at login saying BazUI loaded.",
                    get = function() return BazUIDB.welcomeMessage end,
                    set = function(_, val) BazUIDB.welcomeMessage = val end,
                },
                -- Beta clients carry a draggable Issue Reporter that sits
                -- on top of whatever is under it, and it is in the way more
                -- often than it is wanted, so it starts hidden. The switch
                -- is here to put it back - /PTR opens the reporter without
                -- it either way - and only appears on a client that has one.
                hideIssueReporter = {
                    order = 3,
                    type = "toggle",
                    name = "Hide the Issue Reporter",
                    desc = "The beta client's draggable bug-report button.",
                    hidden = function() return _G.PTR_IssueReporter == nil end,
                    -- Written out rather than `val and nil or false`, which
                    -- cannot ever yield nil: `true and nil` is nil, and the
                    -- or takes over every time.
                    get = function() return BazUIDB.hideIssueReporter ~= false end,
                    set = function(_, val)
                        if val then
                            BazUIDB.hideIssueReporter = nil
                        else
                            BazUIDB.hideIssueReporter = false
                        end
                        BazUI:ApplyIssueReporterVisibility()
                    end,
                },
                movingHeader = {
                    order = 5,
                    type = "header",
                    name = "Moving things",
                },
                snapping = {
                    order = 6,
                    type = "toggle",
                    name = "Snap frames together when dragging",
                    desc = "Dragging one frame near another joins them, so they move as a stack. Off places everything by hand and nothing is ever grabbed at.",
                    get = function() return BazUIDB.snapping ~= false end,
                    set = function(_, val) BazUIDB.snapping = val and true or false end,
                },
                snapFreeModifier = {
                    order = 7,
                    type = "select",
                    name = "Hold to move freely",
                    desc = "Hold this while dragging and that one drag will not snap to anything, however close it gets. Let go and snapping is back. The landing line goes out while it is held, so you can see which you are getting.",
                    values = {
                        ALT   = "Alt",
                        SHIFT = "Shift",
                        CTRL  = "Ctrl",
                        NONE  = "Nothing",
                    },
                    sorting = { "ALT", "SHIFT", "CTRL", "NONE" },
                    hidden = function() return BazUIDB.snapping == false end,
                    get = function() return BazUIDB.snapFreeModifier or "ALT" end,
                    set = function(_, val) BazUIDB.snapFreeModifier = val end,
                },
                modulesHeader = {
                    order = 10,
                    type = "header",
                    name = "Modules",
                },
                modulesNote = {
                    order = 11,
                    type = "description",
                    name = "Unticking one stops it loading at all, in this profile. It takes a reload either way: what a module builds at login cannot be put back without one.",
                },
                fontFace = {
                    order = 3,
                    type = "select",
                    name = "Interface font",
                    desc = "The face BazUI draws with, on unit frames, auras, the "
                        .. "XP bar and the drawer's widgets. Chat has its own switch."
                        .. "\n\nBazUI is DorisPP, the face the addon ships. Game "
                        .. "default leaves every piece of text with the face the game "
                        .. "gave it. The rest are the game's own.\n\nThe list is what "
                        .. "this client actually has: a Russian client is offered the "
                        .. "Cyrillic cuts and not BazUI's own face, which has no "
                        .. "Cyrillic in it.\n\nYour own font can go in the addon's "
                        .. "Fonts folder as Custom.ttf - there is a note in there "
                        .. "explaining it. The game only reads fonts when it starts, "
                        .. "so it appears in this list after a restart, not a reload.",
                    values = function()
                        local out = {}
                        for _, face in ipairs(BazUI.Skin.Theme.FontFaces()) do
                            out[face.key] = face.label
                        end
                        return out
                    end,
                    sorting = function()
                        local out = {}
                        for _, face in ipairs(BazUI.Skin.Theme.FontFaces()) do
                            out[#out + 1] = face.key
                        end
                        return out
                    end,
                    get = function()
                        return BazUIDB.fontFace
                            or (BazUIDB.useFont == false and "game")
                            or "baz"
                    end,
                    set = function(_, val)
                        -- Written out in full rather than left to a
                        -- default, so that picking the game's font is not
                        -- read back later as never having chosen.
                        BazUIDB.fontFace = val
                        BazUI.Skin.Theme.RefreshFontObjects()
                        local auras = BazUI:GetModule("Auras")
                        if auras and auras.ApplySettings then auras:ApplySettings() end
                        local frames = BazUI:GetModule("UnitFrames")
                        if frames and frames.UnitBars then frames.UnitBars:ApplyAll() end
                        local chat = BazUI.Chat and BazUI.Chat.Window
                        if chat and chat.ApplyAll then chat:ApplyAll() end
                        if BazUI.Confirm then
                            BazUI:Confirm({
                                title       = "Reload now?",
                                body        = "Text already on screen keeps the old face until the interface reloads.",
                                acceptLabel = "Reload",
                                cancelLabel = "Later",
                                onAccept    = function() BazUI:RequestReload() end,
                            })
                        end
                    end,
                },
                fontFallback = {
                    order = 5,
                    type = "toggle",
                    name = "Borrow the game's font where ours cannot spell",
                    desc = "The BazUI face carries a Latin alphabet and nothing else, "
                        .. "so a name written in Chinese, Korean or Cyrillic draws as a "
                        .. "row of boxes.\n\nOn, anything it has no characters for is "
                        .. "drawn in the game's own font instead - just that piece of "
                        .. "text, with everything around it unchanged. A chat window is "
                        .. "the exception: it wears one face for every line it holds, so "
                        .. "one such message takes the whole window over.",
                    -- Only means anything while our own face is the one
                    -- drawing: a face of the game's spells everything.
                    disabled = function()
                        return not BazUI.Skin.Theme.IsFontEnabled()
                    end,
                    get = function() return BazUIDB.fontFallback ~= false end,
                    set = function(_, val)
                        BazUIDB.fontFallback = val
                        local chat = BazUI.Chat and BazUI.Chat.Window
                        if chat and chat.ApplyAll then chat:ApplyAll() end
                    end,
                },
            },
        }

        -- One tick box per module, made from the modules there are
        -- rather than a list written here that would go stale the first
        -- time one was added.
        local names = {}
        for moduleName in pairs(BazUI.addons or {}) do
            if BazUI:ModuleCanBeDisabled(moduleName) then
                names[#names + 1] = moduleName
            end
        end
        table.sort(names)

        for index, moduleName in ipairs(names) do
            local config = BazUI.addons[moduleName]
            options.args["module" .. moduleName] = {
                order = 12 + index,
                type  = "toggle",
                name  = config and config.title or moduleName,
                get   = function() return BazUI:IsModuleEnabled(moduleName) end,
                set   = function(_, value)
                    BazUI:SetModuleEnabled(moduleName, value)
                    BazUI:PromptReload(value
                        and "Turning a module on needs a reload before it can build anything."
                        or "It stops loading at the next reload.")
                end,
            }
        end

        return options
    end)
    BazUI:AddToSettings("BazUI-Settings", "General", "BazUI")

    -- Login line, suppressed by the General Settings toggle. Deferred a
    -- tick so it lands after any chat module has swapped DEFAULT_CHAT_FRAME.
    if BazUIDB.welcomeMessage ~= false then
        C_Timer.After(0, function()
            local n = 0
            for modName in pairs(BazUI.addons) do
                if modName ~= "BazUI" then n = n + 1 end
            end
            print(string.format("|cff3399ffBazUI|r v%s loaded (%d module%s). Type |cff00ff00/baz|r for options.",
                tostring(BazUI.VERSION or "?"), n, n == 1 and "" or "s"))
        end)
    end

    -- Profiles subcategory (unified for all Baz Suite addons)
    if BazUI.GetProfileOptionsTable then
        BazUI:RegisterOptionsTable("BazUI-Profiles", function()
            return BazUI:GetProfileOptionsTable()
        end)
        BazUI:AddToSettings("BazUI-Profiles", "Profiles", "BazUI")
    end
end)

---------------------------------------------------------------------------
-- Do Not Disturb: environmental state check
-- Returns true if player is in combat or an encounter is active
---------------------------------------------------------------------------

local encounterActive = false

local dndFrame = CreateFrame("Frame")
dndFrame:RegisterEvent("ENCOUNTER_START")
dndFrame:RegisterEvent("ENCOUNTER_END")
dndFrame:SetScript("OnEvent", function(_, event)
    encounterActive = (event == "ENCOUNTER_START")
end)

function BazUI:IsDND()
    return InCombatLockdown() or encounterActive
end

---------------------------------------------------------------------------
-- Notification Bridge
-- Routes to the Notifications module when it is loaded, nil otherwise.
--
-- Baz Suite addons that want to push notifications call:
--   BazUI:RegisterNotificationModule("BazBars", { icon = ..., label = ... })
-- and then:
--   BazUI:PushNotification({ module = "BazBars", title = "...", ... })
--
-- If the module is absent, both calls silently do nothing so callers don't
-- need to guard themselves.
---------------------------------------------------------------------------

local registeredNotificationModules = {}

local function NotificationAPI()
    return BazUI.Notifications and BazUI.Notifications.API
end

local function TryRegisterModule(moduleId, info)
    local BNC = NotificationAPI()
    if not BNC or not BNC.RegisterModule then return end
    if registeredNotificationModules[moduleId] then return end
    BNC:RegisterModule({
        id = moduleId,
        name = info.label or moduleId,
        icon = info.icon or "Interface\\Icons\\INV_Misc_Bell_01",
    })
    registeredNotificationModules[moduleId] = true
end

function BazUI:RegisterNotificationModule(moduleId, info)
    if not moduleId then return end
    info = info or {}
    -- Remember the registration so we can re-apply it when BNC loads later
    registeredNotificationModules[moduleId] = registeredNotificationModules[moduleId] or false
    TryRegisterModule(moduleId, info)
    -- Store info for late registration if BNC isn't loaded yet
    registeredNotificationModules[moduleId .. "_info"] = info
end

function BazUI:PushNotification(data)
    local BNC = NotificationAPI()
    if not BNC or not BNC.Push then return end
    if data and data.module and not registeredNotificationModules[data.module] then
        -- Lazy-register on first push if caller forgot to register explicitly
        local info = registeredNotificationModules[data.module .. "_info"] or {}
        TryRegisterModule(data.module, info)
    end
    return BNC:Push(data)
end

-- Auto-register the BazUI internal module for things like profile-change
-- toasts. Done on PLAYER_LOGIN so BNC has finished loading.
BazUI:QueueForLogin(function()
    BazUI:RegisterNotificationModule("_bazui", {
        label = "BazUI",
        icon = "Interface\\Icons\\INV_Gizmo_GoblingTonkController",
    })
end)

---------------------------------------------------------------------------
-- Looking at an atlas
--
-- The client keeps its artwork in packed sheets, and an atlas is a named
-- rectangle inside one. Nothing on disk says which rectangle: the sheets
-- are readable but the coordinates live in a database the game does not
-- expose, so the only way to know what a name actually looks like is to
-- put it on screen.
--
-- Worth having as a command rather than a one-off, because guessing at
-- this has cost real time. The bar fills wear these, a wrong one draws
-- black or draws nothing, and neither says why.
--
-- Two copies of each: stretched to the shape a bar would give it, which
-- is how it will really be seen, and at its own size, which is how it was
-- drawn. A name the client does not have says so rather than showing the
-- missing-texture grid.
---------------------------------------------------------------------------

local atlasWindow

local function AtlasPreview(names)
    if not atlasWindow then
        atlasWindow = CreateFrame("Frame", "BazUIAtlasPreview", UIParent,
            BackdropTemplateMixin and "BackdropTemplate" or nil)
        atlasWindow:SetFrameStrata("DIALOG")
        atlasWindow:SetPoint("CENTER")
        atlasWindow:SetMovable(true)
        atlasWindow:EnableMouse(true)
        atlasWindow:RegisterForDrag("LeftButton")
        atlasWindow:SetScript("OnDragStart", atlasWindow.StartMoving)
        atlasWindow:SetScript("OnDragStop", atlasWindow.StopMovingOrSizing)

        atlasWindow.bg = atlasWindow:CreateTexture(nil, "BACKGROUND")
        atlasWindow.bg:SetAllPoints()
        atlasWindow.bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)

        atlasWindow.rows = {}

        local close = CreateFrame("Button", nil, atlasWindow, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
        -- CloseOnEscape, not BindEscape: BindEscape only re-arms a binding
        -- for a frame that already has an escape button, and takes no
        -- handler. Called the way it was here it did nothing at all, so
        -- the window could not be closed with Escape.
        BazUI.CloseOnEscape(atlasWindow, function() atlasWindow:Hide() end)
    end

    for _, row in ipairs(atlasWindow.rows) do row:Hide() end

    local y = -28
    for index, name in ipairs(names) do
        local row = atlasWindow.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, atlasWindow)
            row:SetSize(560, 74)
            row.label = BazUI.Skin.Theme.FontString(row, "OVERLAY", "GameFontNormalSmall")
            row.label:SetPoint("TOPLEFT", 8, 0)
            row.label:SetJustifyH("LEFT")

            -- A mid gray behind each, so art that is mostly transparent
            -- reads as transparent rather than as black.
            row.mat = row:CreateTexture(nil, "BACKGROUND")
            row.mat:SetPoint("TOPLEFT", 8, -14)
            row.mat:SetSize(300, 26)
            row.mat:SetColorTexture(0.45, 0.45, 0.45, 1)

            row.stretched = row:CreateTexture(nil, "ARTWORK")
            row.stretched:SetAllPoints(row.mat)

            row.native = row:CreateTexture(nil, "ARTWORK")
            row.native:SetPoint("TOPLEFT", row.mat, "TOPRIGHT", 12, 0)

            row.note = BazUI.Skin.Theme.FontString(row, "OVERLAY", "GameFontDisableSmall")
            row.note:SetPoint("TOPLEFT", 8, -44)
            row.note:SetJustifyH("LEFT")
            atlasWindow.rows[index] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", atlasWindow, "TOPLEFT", 0, y)
        row.label:SetText(name)

        local info = C_Texture and C_Texture.GetAtlasInfo
            and C_Texture.GetAtlasInfo(name)
        if info then
            row.stretched:SetAtlas(name)
            row.stretched:Show()
            row.native:SetAtlas(name, true)
            row.native:Show()
            row.note:SetText(("%d x %d, file %s"):format(
                info.width or 0, info.height or 0, tostring(info.file)))
        else
            row.stretched:Hide()
            row.native:Hide()
            row.note:SetText("|cffff6666this client has no such atlas|r")
        end

        row:Show()
        y = y - 82
    end

    atlasWindow:SetSize(600, 36 + #names * 82)
    atlasWindow:Show()
end

---------------------------------------------------------------------------
-- BazUI's own slash commands
-- /baz (or /bazui, /bui) opens BazUI in the Options > AddOns panel. Sub-commands cover the most
-- common day-to-day actions: profile switching and default-profile setup.
---------------------------------------------------------------------------

BazUI:QueueForLogin(function()
    if not BazUI.RegisterCommands then return end

    BazUI:RegisterCommands("BazUI", {
        title = "BazUI",
        slash = { "/baz", "/bazui", "/bui" },
        defaultHandler = function()
            if BazUI.OpenOptionsPanel then
                BazUI:OpenOptionsPanel("BazUI")
            end
        end,
        commands = {
            check = {
                desc = "Check everything the addon takes hold of in the game's own UI - frames, templates, console settings - and say what is missing. Worth running first on a new client build.",
                handler = function() BazUI:PrintDependencyReport() end,
            },
            fonts = {
                desc = "Sample text in several alphabets, drawn in BazUI's face and in the game's side by side. Says whether the addon would turn this client's own language into boxes.",
                handler = function() BazUI:ShowFontTest() end,
            },
            audit = {
                desc = "Where every module's settings live, and which of them really follow the profile. Add a module name to see one of them key by key.",
                handler = function(args)
                    args = strtrim(tostring(args or ""))
                    if args ~= "" then
                        BazUI:PrintModuleSettings(args)
                    else
                        BazUI:PrintSettingsAudit()
                    end
                end,
            },
            dock = {
                desc = "What the dock thinks your layout is: everything docked, in the order it was docked, and what each piece adds to its stack. Add 'snap' to list what the snap test can see.",
                handler = function(args)
                    if strtrim(tostring(args or "")):lower() == "snap" then
                        BazUI.Dock:DescribeSnap(print)
                    else
                        BazUI.Dock:PrintLayout()
                    end
                end,
            },
            errors = {
                desc = "Anything that failed while the interface was being built. Empty is the normal answer.",
                handler = function()
                    local errors = BazUI._loginErrors
                    if not errors or #errors == 0 then
                        BazUI:Print("Everything started cleanly.")
                        return
                    end
                    BazUI:Print(("%d part%s of the interface did not start:"):format(
                        #errors, #errors == 1 and "" or "s"))
                    for index, err in ipairs(errors) do
                        print(("  |cffff6666%d.|r %s"):format(index, err))
                    end
                end,
            },
            atlas = {
                desc = "Show what one of the game's atlas images actually looks like. A name, or nothing for the ones the bar fills use.",
                handler = function(args)
                    local names = {}
                    for word in tostring(args or ""):gmatch("[^%s]+") do
                        names[#names + 1] = word
                    end
                    if #names == 0 then
                        names = {
                            "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
                            "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Status",
                            "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Status",
                            "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Status",
                        }
                    end
                    AtlasPreview(names)
                end,
            },
            profile = {
                desc = "Show or switch the active profile",
                handler = function(args)
                    if not args or args == "" then
                        BazUI:Print("Active profile: |cff00ff00" .. BazUI:GetActiveProfile() .. "|r")
                        return
                    end
                    if BazUI:SetActiveProfile(args) then
                        BazUI:Print("Switched to profile: |cff00ff00" .. args .. "|r")
                    else
                        BazUI:Print("|cffff4444No profile named '" .. args .. "'|r")
                    end
                end,
            },
            escdebug = {
                desc = "Print what Blizzard's Escape handler sees (debugging Esc not clearing the target)",
                handler = function()
                    local function shown(f) return f and f.IsShown and f:IsShown() and true or false end
                    BazUI:Print("Escape chain check:")
                    -- Our own override bindings first. Escape is bound
                    -- through SetOverrideBindingClick here, and one left
                    -- behind eats Escape for the whole game - which looks
                    -- exactly like Escape being broken.
                    if BazUI.EscapeReport then
                        for _, line in ipairs(BazUI.EscapeReport()) do
                            print("  " .. line)
                        end
                    end
                    print("  target exists:", UnitExists("target"), " charmed:", UnitIsCharmed("player"), " spell targeting:", _G.SpellIsTargeting())
                    local casting = _G.UnitCastingInfo and _G.UnitCastingInfo("player")
                    local channel = _G.UnitChannelInfo and _G.UnitChannelInfo("player")
                    print("  casting:", tostring(casting), " channeling:", tostring(channel), " (Esc stops a cast before it clears the target)")
                    print("  in combat lockdown:", InCombatLockdown())
                    local root = _G.BazUITargetFrame
                    if root then
                        print("  BazUI target frame shown:", root:IsShown(), " visible:", root:IsVisible(),
                            " driver state:", tostring(root:GetAttribute("state-visibility")))
                    end
                    if _G.Menu and _G.Menu.GetManager then
                        local okM, mgr = pcall(_G.Menu.GetManager)
                        if okM and mgr and mgr.IsAnyMenuOpen then
                            local okO, open = pcall(mgr.IsAnyMenuOpen, mgr)
                            print("  any menu open:", okO and tostring(open) or "n/a")
                        end
                    end
                    print("  GameMenu:", shown(_G.GameMenuFrame), " Help:", shown(_G.HelpFrame), " EditMode:", shown(_G.EditModeManagerFrame),
                        " Loot:", shown(_G.LootFrame), " Opacity:", shown(_G.OpacityFrame), " ModelPreview:", shown(_G.ModelPreviewFrame))
                    for i = 1, 4 do
                        local sp = _G["StaticPopup" .. i]
                        if shown(sp) then print("  StaticPopup" .. i .. " shown:", tostring(sp.which)) end
                    end
                    for _, n in ipairs(_G.UIMenus or {}) do
                        if shown(_G[n]) then print("  menu shown:", n) end
                    end
                    local any = false
                    for _, n in ipairs(UISpecialFrames) do
                        if shown(_G[n]) then print("  special frame shown:", n); any = true end
                    end
                    if not any then print("  no special frames shown") end
                    for _, area in ipairs({ "left", "center", "right", "doublewide", "fullscreen" }) do
                        local f = _G.GetUIPanel and _G.GetUIPanel(area)
                        if f then print("  UI panel " .. area .. ":", f:GetName() or "?") end
                    end
                    local dock = _G.GeneralDockManager
                    if dock and dock.overflowButton and dock.overflowButton.list then
                        print("  chat overflow list shown:", shown(dock.overflowButton.list))
                    end
                    if _G.Menu and _G.Menu.GetManager then
                        local ok, mgr = pcall(_G.Menu.GetManager)
                        if ok and mgr and mgr.GetOpenMenu then
                            local ok2, open = pcall(mgr.GetOpenMenu, mgr)
                            print("  open Menu:", ok2 and tostring(open) or "n/a")
                        end
                    end
                    print("  Reading it: 'target exists: false' with the BazUI target frame shown means the frame's visibility driver did not hide it (Unit Frames).")
                    print("  Everything false or empty with the target still existing means Esc reached ClearTarget and was blocked: check BugSack for 'ClearTarget'.")
                end,
            },
            edit = {
                desc = "Open BazUI's edit mode, to move and resize what BazUI draws",
                handler = function()
                    BazUI:ToggleEditMode()
                end,
            },
            export = {
                desc = "Print the active profile as Lua, to paste into Core/StarterProfile.lua",
                handler = function()
                    BazUI:ExportStarterProfile()
                end,
            },
            sv = {
                desc = "Report whether the saved variables were there when BazUI started",
                handler = function()
                    BazUI:ReportSavedVariables()
                end,
            },
            persist = {
                desc = "Keep another addon's settings too: add <AddOn> [Globals], remove <AddOn>, or nothing to list",
                handler = function(args)
                    BazUI:PersistCommand(args)
                end,
            },
            auras = {
                desc = "What the client will let us read about auras right now, and what each row is holding - add 'spike' to test the AuraContainer route",
                handler = function(args)
                    BazUI:ReportAuras(args)
                end,
            },
            taint = {
                desc = "Report which Blizzard globals and frames BazUI has taken over (add 'all' for every addon)",
                handler = function(args)
                    BazUI.Taint.Report(not (args and args:lower():find("all")))
                end,
            },
            profiles = {
                desc = "List all profiles",
                handler = function()
                    local active  = BazUI:GetActiveProfile()
                    local default = BazUI:GetDefaultProfile()
                    BazUI:Print("Profiles:")
                    for _, name in ipairs(BazUI:ListProfiles()) do
                        local tags = ""
                        if name == active  then tags = tags .. " |cff00ff00(active)|r"  end
                        if name == default then tags = tags .. " |cffffd700(default)|r" end
                        print("  " .. name .. tags)
                    end
                end,
            },
            default = {
                desc = "Set the profile new characters auto-attach to (or print the current default)",
                handler = function(args)
                    if not args or args == "" then
                        BazUI:Print("Default profile for new characters: |cffffd700" .. BazUI:GetDefaultProfile() .. "|r")
                        return
                    end
                    if BazUI:SetDefaultProfile(args) then
                        BazUI:Print("'|cffffd700" .. args .. "|r' set as the default for new characters.")
                    else
                        BazUI:Print("|cffff4444No profile named '" .. args .. "'|r")
                    end
                end,
            },
        },
    })
end)

---------------------------------------------------------------------------
-- BazUI is standalone. Running it next to the BazCore-based suite means two
-- addons fighting over the minimap, quest tracker and chat, so say so once.
---------------------------------------------------------------------------
-- /baz persist - looking after another addon's settings.
--
-- Not a setting on a page, because this is a repair for a broken client
-- rather than a preference, and the list of addons it applies to is one
-- somebody types once and forgets. See Core/Persist.lua.
function BazUI:PersistCommand(args)
    local P = BazUI.Persist
    if not P then return end
    args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local verb, rest = args:match("^(%S+)%s*(.*)$")
    verb = verb and verb:lower() or nil

    if verb == "add" then
        local addOnName, globals = rest:match("^(%S+)%s*(.*)$")
        if not addOnName then
            BazUI:Print("Which addon? /baz persist add TomTom")
            return
        end
        local list
        if globals and globals ~= "" then
            list = {}
            for word in globals:gmatch("[%w_]+") do list[#list + 1] = word end
        end
        local ok, result = P:AddGuest(addOnName, list)
        if ok then
            BazUI:Print(("Now keeping %s's settings: %s. They come back from the next login on.")
                :format(addOnName, table.concat(result, ", ")))
        else
            BazUI:Print("Cannot: " .. tostring(result))
        end
        return
    end

    if verb == "remove" or verb == "forget" then
        local addOnName = rest:match("^(%S+)")
        if addOnName and P:RemoveGuest(addOnName) then
            BazUI:Print(addOnName .. " is on its own again. Its settings here are let go.")
        else
            BazUI:Print("Not looking after " .. tostring(addOnName) .. ".")
        end
        return
    end

    local guests = P:Guests()
    if #guests == 0 then
        BazUI:Print("Not looking after any other addon's settings. "
            .. "|cffffd700/baz persist add TomTom|r to start.")
    else
        BazUI:Print("Also keeping the settings of:")
        for _, name in ipairs(guests) do
            local globals = P:GuestGlobals(name) or {}
            print(("  %s - %s%s"):format(name, table.concat(globals, ", "),
                (P.guestReport and P.guestReport[name])
                    and ("  (" .. P.guestReport[name] .. " this login)") or ""))
        end
    end
    print("  |cff888888Only for addons that load after BazUI, and only on a client "
        .. "that does not read saved variables back.|r")
end

---------------------------------------------------------------------------
-- /baz auras - what the client will let us read, aura by aura
--
-- Written because "my debuff does not show up" has four possible answers
-- and they are indistinguishable from the outside: the client refused the
-- read, the client allowed it and there was nothing there, the row has no
-- slot stamped with that index, or the slot is there and painting and is
-- somewhere you are not looking.
--
-- So it asks all four, in order, and prints what it got. Run it while the
-- thing that is missing should be on screen - in combat, if that is when
-- it goes wrong, because that is the whole question.
---------------------------------------------------------------------------

local function AuraLine(unit, index, filter)
    local secret = "-"
    if C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret then
        local ok, is = pcall(C_Secrets.ShouldUnitAuraIndexBeSecret, unit, index, filter)
        secret = ok and (is and "|cffff4444secret|r" or "|cff00ff00readable|r")
            or "|cffff4444could not ask|r"
    end

    local allowed = BazUI.Secret and BazUI.Secret.AuraReadable
        and BazUI.Secret.AuraReadable(unit, index, filter)

    -- Only read where we have just been told we may. The point of this
    -- command is not to find out the hard way.
    local name = "|cff888888not read|r"
    if allowed then
        local ok, got = pcall(function()
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
                return a and a.name or false
            end
            return (UnitAura(unit, index, filter)) or false
        end)
        if not ok then name = "|cffff4444the read threw|r"
        elseif got == false then name = "|cff888888nothing there|r"
        else name = tostring(got) end
    end

    return ("    %d  %s  ->  %s"):format(index, secret, name)
end

-- /baz auras spike - the one road left, tried in one command.
--
-- Everything BazUI's aura rows do is built on READING auras, and on this
-- client that is refused during combat by every route there is. The way
-- out is not to read them: AuraContainer is an intrinsic Blizzard ships
-- for addons to instantiate, and its own TOC says why the XML is loaded
-- globally -
--
--   "to allow intrinsics and templates to be instantiated by external
--    code without making their created objects implicitly forbidden"
--
-- The frames it makes carry secret aspects for their text, cooldown,
-- alpha and texcoords, so the ENGINE draws a value we are never handed.
-- Nothing here reads an aura, which is exactly why it might work.
--
-- A spike, not a feature: it proves the thing renders on Forever at all,
-- which nothing has yet. If it does, Modules/Auras/Frames.lua gets rebuilt
-- on it and loses the hand-rolled header, the spare-slot headroom and the
-- whole secret dance with it.
function BazUI:SpikeAuraContainer(off)
    if BazUI._auraSpikeHost and off then
        BazUI._auraSpikeHost:Hide()
        BazUI._auraSpikeHost = nil
        BazUI._auraSpike = nil
        BazUI:Print("Aura spike removed.")
        return
    end
    if BazUI._auraSpikeHost then
        -- Already up: read it where it stands rather than tearing down the
        -- very state worth looking at.
        BazUI:Print("Aura spike, as it stands:")
        return BazUI:ReportAuraSpike()
    end

    BazUI:Print("Aura spike: letting the engine draw the target's debuffs.")

    -- A host of our own, which is the bit that is definitely visible.
    --
    -- The first attempt put a background straight onto the container and
    -- nothing appeared at all. A container lays itself out from what it is
    -- holding, so an empty one is very likely zero by zero - and a texture
    -- anchored to all points of a frame with no size is a texture with no
    -- size. This way the marker cannot vanish, and where the icons end up
    -- relative to it is itself information.
    local host = CreateFrame("Frame", "BazUIAuraSpikeHost", UIParent)
    host:SetSize(320, 64)
    host:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    host:SetFrameStrata("HIGH")
    local bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.6, 0, 0.6, 0.55)
    host:Show()
    BazUI._auraSpikeHost = host
    print("  |cffff66ffa PURPLE box is below the middle of your screen|r")

    local ok, container = pcall(CreateFrame, "AuraContainer", "BazUIAuraSpike",
        host, "CustomAuraContainerTemplate")
    if not ok or not container then
        print("  |cffff4444the intrinsic would not build|r: " .. tostring(container))
        return
    end
    print("  |cff00ff00built|r")

    container:SetAllPoints(host)

    local step, err
    step, err = pcall(container.SetUnit, container, "target")
    print(("  SetUnit('target'): %s"):format(step and "|cff00ff00ok|r"
        or ("|cffff4444" .. tostring(err) .. "|r")))

    -- With a SIZE, which is the whole of why the first two attempts drew
    -- nothing. CustomAuraContainerGroupLayoutDefaultOptions ships
    --
    --   elementWidth = nil;  elementHeight = nil;
    --
    -- so the engine made its ten aura frames exactly as asked and laid
    -- them out with no dimensions to lay out. The count said it was
    -- working while the screen said it was not, and both were right.
    --
    -- initializeFrame as well as the layout options: the individual aura
    -- frames take AccessRestrictionFlags after creation and cannot be
    -- touched by us afterwards, so that callback is the only moment any
    -- per-frame styling can happen.
    step, err = pcall(container.AddAuraGroup, container, "debuffs", "HARMFUL", {
        layout = {
            elementWidth   = 32,
            elementHeight  = 32,
            elementSpacing = 4,
            lineSpacing    = 4,
        },
        -- initializeFrame has to BUILD the artwork, not just size it.
        --
        -- CustomAuraButtonTemplate is mixins and nothing else - no
        -- textures, no regions, not one line of XML art:
        --
        --   <AuraButton name="CustomAuraButtonTemplate" virtual="true">
        --     <Mixins> ... </Mixins>
        --   </AuraButton>
        --
        -- It supplies behaviour and the secret-aspect binding; the look is
        -- the caller's job. So ten frames of the right size, holding real
        -- auras, drew nothing at all - correctly. SetIcon is what hands
        -- the engine something to paint into, and from then on the icon
        -- carries Alpha/VertexColor/TexCoords/Shown as secret aspects that
        -- the engine drives and we never read.
        initializeFrame = function(frame)
            pcall(frame.SetSize, frame, 32, 32)

            local made, tex = pcall(frame.CreateTexture, frame, nil, "ARTWORK")
            if not made or not tex then return end
            tex:SetAllPoints(frame)
            pcall(frame.SetIcon, frame, tex)
        end,
    })
    print(("  AddAuraGroup('HARMFUL', 32px + SetIcon): %s"):format(step and "|cff00ff00ok|r"
        or ("|cffff4444" .. tostring(err) .. "|r")))

    -- The switch. Without it the container is inert:
    --
    --   ShouldRegisterForDynamicEvents() = IsVisible() and IsEnabled()
    --   ParseAllAuras()                  = returns early if not IsEnabled()
    --
    -- and `enabled` starts nil. So it never registers for UNIT_AURA and
    -- never parses an aura, while still pre-creating its batch of frames -
    -- which is why the count read 10 through two attempts that displayed
    -- nothing. Set last, so the refresh it triggers sees the finished setup.
    step, err = pcall(container.SetEnabled, container, true)
    print(("  SetEnabled(true): %s"):format(step and "|cff00ff00ok|r"
        or ("|cffff4444" .. tostring(err) .. "|r")))

    container:Show()
    BazUI._auraSpike = container

    -- Asked a second later, because the engine fills these in its own time
    -- and in batches. GetAuraGroupFrameCount is the question that matters:
    -- it says whether the engine made any aura frames at all, which is a
    -- different failure from making them and drawing them somewhere else.
    C_Timer.After(1, function() BazUI:ReportAuraSpike() end)
end

-- Asked whenever, because the interesting moment is while a debuff is
-- actually ticking and rebuilding the thing to look at it destroys the
-- state being looked at.
function BazUI:ReportAuraSpike()
    do
        local c = BazUI._auraSpike
        if not c then return end
        local function Ask(label, fn, ...)
            local good, value = pcall(fn, c, ...)
            print(("  %s: %s"):format(label,
                good and tostring(value) or ("|cffff4444" .. tostring(value) .. "|r")))
        end
        print("  |cffffd700one second on:|r")
        Ask("shown",        c.IsShown)
        Ask("enabled",      c.IsEnabled)
        Ask("width",        c.GetWidth)
        Ask("height",       c.GetHeight)
        Ask("aura frames",  c.GetAuraGroupFrameCount, "debuffs")

        -- The aura frames themselves are deliberately NOT touched.
        --
        -- They carry DenyTaintedAccessWhenAurasAreSecret, applied after
        -- creation, so the moment one is holding a secret aura it becomes
        -- a forbidden object and even GetWidth on it is an error. Asking
        -- was worth one run - an empty frame answered '32x32, shown false'
        -- and a filled one answered 'forbidden', which is how we know the
        -- engine is populating them at all - but it is an error per frame
        -- per look from here on, and this client stops reporting errors
        -- after a hundred.
        --
        -- Which is the deal this whole approach makes: the engine will
        -- draw what we may not see, and in exchange we do not get to ask
        -- what it drew. The screen is the readout.
        print("  |cffffd700Look at the purple box - that is the readout.|r")
        print("  |cff888888Icons there means the engine is drawing auras we"
            .. " are not allowed to read, which is the whole point.|r")
        print("  |cff888888'/baz auras spike' re-reads this; add 'off' to"
            .. " remove the box.|r")
    end
end

function BazUI:ReportAuras(args)
    args = args and args:lower() or ""
    if args:find("spike") then
        return BazUI:SpikeAuraContainer(args:find("off") ~= nil)
    end
    local deep = args:find("all")

    BazUI:Print("Auras: what the client will let us read")
    print("  in combat: " .. tostring(InCombatLockdown() and "|cffffd700yes|r" or "no"))

    if not C_Secrets then
        print("  C_Secrets: |cff00ff00absent - nothing is restricted on this client|r")
    else
        local function Ask(fn, label)
            if not fn then return print("  " .. label .. ": |cff888888not on this client|r") end
            local ok, value = pcall(fn)
            print(("  %s: %s"):format(label,
                ok and tostring(value) or "|cffff4444could not ask|r"))
        end
        Ask(C_Secrets.HasSecretRestrictions, "HasSecretRestrictions")
        Ask(C_Secrets.ShouldAurasBeSecret,   "ShouldAurasBeSecret  (the GENERAL answer - not the one we act on)")
    end

    if InCombatLockdown() then
        print("  |cffffd700Nothing below will be readable, and that is the"
            .. " client, not BazUI.|r")
        print("  |cff888888In combat every aura is secret, and a secret aura"
            .. " cannot be read by an addon at all:|r")
        print("  |cff888888  GetAuraDataByIndex errors outright - 'Auras cannot"
            .. " be accessed when secret while tainted'.|r")
        print("  |cff888888  UNIT_AURA does arrive, but its payload is a secret"
            .. " table that cannot be indexed or counted.|r")
        print("  |cff888888Rows therefore hold what they last saw and catch up"
            .. " when the fight ends. Blizzard's own frames are untainted,"
            .. " which is the whole of why theirs keep working.|r")
    end

    for _, unit in ipairs({ "player", "target" }) do
        if UnitExists(unit) then
            for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
                print(("  |cffffd700%s %s|r"):format(unit, filter))
                local shown = 0
                for index = 1, deep and 40 or 8 do
                    print(AuraLine(unit, index, filter))
                    shown = shown + 1
                end
                if shown == 0 then print("    none") end
            end
        else
            print(("  |cffffd700%s|r: nothing there"):format(unit))
        end
    end

    -- And what the rows actually made of it. A readable aura that no slot
    -- is stamped for is a different bug from one the client refused.
    local auras = BazUI.GetModule and BazUI:GetModule("Auras")
    if auras and auras.ReportRows then auras:ReportRows() end
end
function BazUI:ReportSavedVariables()
    local t = BazUI._svTrace or {}
    local function Say(n)
        n = n or -1
        if n < 0 then return "|cffff4444absent|r" end
        if n == 0 then return "|cffff4444empty|r" end
        return "|cff00ff00" .. n .. " keys|r"
    end
    BazUI:Print(("Saved variables - Core.lua ran: %s, ADDON_LOADED: %s, login: %s, now: %s"):format(
        Say(t.atFileLoad), Say(t.atAddonLoaded), Say(t.atLogin), Say(CountKeys(_G.BazUIDB))))

    print("  when Core.lua ran: " .. tostring(t.namesAtFileLoad)
        .. "  (addon already counts as loaded: " .. tostring(t.saysLoadedAtFileLoad) .. ")")
    print("  ADDON_LOADED event: " .. tostring(t.namesAtRawEvent))
    print("  our ADDON_LOADED:   " .. tostring(t.namesAtAddonLoaded))
    -- What the table held at PLAYER_LOGIN, before anything of ours touched
    -- it. This is the one that matters now: if the file is read late, the
    -- saved keys are here and something of ours is discarding them; if it
    -- says absent, the file was never read at all.
    print("  at PLAYER_LOGIN:    " .. tostring(t.atLoginRaw))
    print("  entering world:     " .. tostring(t.atEnteringWorld) .. " keys")
    print("  now:              " .. KeyNames(_G.BazUIDB))

    for i, shape in ipairs(BazUI._svTrace.shapes or {}) do
        print("  shape " .. i .. ": " .. shape)
    end

    print(("  account file remembered %s previous load%s, the per-character file %s"):format(
        tostring(t.accountLoads), (t.accountLoads == 1) and "" or "s",
        tostring(t.charLoads)))

    -- Where the settings really are on a client that will not read its
    -- own. See Core/Persist.lua.
    if BazUI.Persist then
        print("  host table (" .. BazUI.Persist.HOST .. "): " .. BazUI.Persist:Describe())
        for _, line in ipairs(BazUI.Persist:Detail()) do
            print("    " .. line)
        end
        local keys = BazUI.Persist:Keys()
        print("  it is holding " .. #keys .. " table"
            .. ((#keys == 1) and "" or "s") .. " of ours"
            .. ((#keys > 0) and (": " .. table.concat(keys, ", ")) or ""))
        -- When the host table turned up, which decides whether another
        -- addon's settings can be restored before it reads them.
        for _, line in ipairs(BazUI.Persist.hostTrace or {}) do
            print("    " .. line)
        end
    end

    -- "Interface" is not a metadata key the client hands back, which is why
    -- this used to print a question mark and tell us nothing at all. Any X-
    -- field is readable, so the TOC carries a copy of its own interface line
    -- under one.
    --
    -- Worth having because a TOC is read when the client launches and never
    -- again - /reload does not re-read it - so a test of a TOC change that
    -- cannot tell those two apart proves nothing either way.
    local _, build, _, iface = GetBuildInfo()
    print(("  client build %s wants interface |cffffd700%s|r; our TOC declares |cffffd700%s|r")
        :format(tostring(build), tostring(iface),
            tostring(C_AddOns.GetAddOnMetadata(BazUI.ADDON_NAME, "X-Interface-Stamp") or "?")))

    local log = _G.BazUIDB and _G.BazUIDB.moduleSwitchLog
    if type(log) == "table" then
        print("  logins remembered: " .. #log .. " (more than one means the file is being read back)")
        for i = math.max(1, #log - 4), #log do print("    " .. tostring(log[i])) end
    end
end

-- The beta client's Issue Reporter, down unless asked for. SuppressFrame
-- keeps it down: theirs shows itself again on a good few events.
function BazUI:ApplyIssueReporterVisibility()
    local frame = _G.PTR_IssueReporter
    if not frame then return end
    BazUI.SuppressFrame(frame, function()
        return _G.BazUIDB == nil or _G.BazUIDB.hideIssueReporter ~= false
    end)
end

BazUI:QueueForLogin(function()
    BazUI:ApplyIssueReporterVisibility()
    BazUI._svTrace.atLogin = CountKeys(_G.BazUIDB)
    BazUI:ReportSavedVariables()
    BazUI:RecordModuleFlagsAtLogin()
end)

BazUI:QueueForLogin(function()
    local clash = {}
    for _, name in ipairs({ "BazCore", "BazWidgetDrawers", "LibBazWidget", "BazWidgets", "BazChat", "BazBags", "BazBars", "BazNotificationCenter" }) do
        if C_AddOns.IsAddOnLoaded(name) then clash[#clash + 1] = name end
    end
    if #clash > 0 then
        print("|cffff4444BazUI|r: BazUI replaces " .. table.concat(clash, ", ") ..
            ". Disable those addons on this character so the two suites don't fight over the same frames.")
    end
end)
