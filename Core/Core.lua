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
lifecycleFrame:RegisterEvent("PLAYER_LOGIN")
lifecycleFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        loginReady = true
        for _, entry in ipairs(loginQueue) do
            entry()
        end
        wipe(loginQueue)
        self:UnregisterEvent("PLAYER_LOGIN")
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

function BazUI:SetModuleEnabled(name, enabled)
    if ALWAYS_ON[name] then return end
    local flags = ModuleFlags()
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
    EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
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

    MenuUtil.CreateContextMenu(anchor, function(_, root)
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
end

---------------------------------------------------------------------------
-- BazUI's own settings page (registered after all modules load)
---------------------------------------------------------------------------

-- Initialize unified profile structure early (before addons load)
EventUtil.ContinueOnAddOnLoaded("BazUI", function()
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
                bazFont = {
                    order = 3,
                    type = "toggle",
                    name = "Use the BazUI font",
                    desc = "DorisPP, the face BazUI ships, on unit frames, auras, the XP bar and the drawer's widgets. Chat has its own switch.",
                    get = function() return BazUIDB.useFont ~= false end,
                    set = function(_, val)
                        BazUIDB.useFont = val
                        -- Mirrored font objects re-point in place, so
                        -- everything drawn through one changes at once.
                        BazUI.Skin.Theme.RefreshFontObjects()
                        -- Modules that set their fonts on every apply
                        -- change straight away; the rest draw their text
                        -- once, at login.
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
                                onAccept    = function() ReloadUI() end,
                            })
                        end
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
            print(string.format("|cff3399ffBazUI|r v%s loaded (%d module%s). Type |cff00ff00/bazui|r for options.",
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
-- BazUI's own slash commands
-- /bazui (or /bui) opens BazUI in the Options > AddOns panel. Sub-commands cover the most
-- common day-to-day actions: profile switching and default-profile setup.
---------------------------------------------------------------------------

BazUI:QueueForLogin(function()
    if not BazUI.RegisterCommands then return end

    BazUI:RegisterCommands("BazUI", {
        title = "BazUI",
        slash = { "/bazui", "/bui" },
        defaultHandler = function()
            if BazUI.OpenOptionsPanel then
                BazUI:OpenOptionsPanel("BazUI")
            end
        end,
        commands = {
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
