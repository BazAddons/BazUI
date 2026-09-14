-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazBars Core Module
-- Addon lifecycle, slash commands, Edit Mode integration
-- Powered by BazUI framework

---------------------------------------------------------------------------
-- Addon Registration via BazUI
---------------------------------------------------------------------------

-- Declared before the assignment so the command handlers inside the
-- table below capture this local. Written as one statement, the
-- closures would bind a nil global instead (local scope starts after
-- the initializer), breaking every /bb subcommand.
local BazBars = BazUI.Bars   -- module namespace (was the BazBars global)
local addon
addon = BazUI:RegisterModule("Bars", {
    title = "Bars",
    profiles = true,
    defaults = {
        bars = {},
        keybinds = {},
        globalOverrides = {},
        minimap = { hide = false },
        fullRangeColor = true,
        showTooltips = true,
        tooltipAnchor = "default",  -- "default" = bottom-right corner, "button" = next to button
        showKeybindText = true,
        showMacroNames = true,
        -- When true: reparent Blizzard's MainActionBar (Bar 1
        -- container) to a hidden carrier so the visible buttons +
        -- chrome + endcaps all disappear. Keybinds still fire on
        -- whatever's slotted in those positions; only the visible
        -- UI is hidden. Edit Mode covers Bars 2-8 already; this
        -- option fills the gap for Bar 1.
        hideDefaultActionBar = false,
        -- When true: hide just the chrome art (border frame +
        -- gryphon/wyvern endcaps) on Bar 1, leaving the buttons
        -- visible and functional. Independent of hideDefaultActionBar
        -- (bar-hide is a superset that wins automatically).
        hideDefaultActionBarArt = false,
        -- Blizzard's stance bar is hidden; stances live on a BazUI bar
        -- (a new character's are placed there, see AutoFill.lua).
        hideStanceBar = true,
        -- AutoFill.lua: a new character's abilities go onto its bars on
        -- first login, and newly learned spells take the first empty slot.
        autoFill = true,
        autoPlaceNew = true,
        -- Buttons can be dragged only while Shift is held, so a slip
        -- never pulls an ability off a bar. Dropping onto a bar still works.
        dragRequiresShift = false,
    },

    -- Slash commands
    slash = { "/bb", "/bazbars" },
    commands = {
        create = {
            desc = "Create a new bar: /bb create [cols] [rows]",
            handler = function(args)
                local parts = {}
                for word in args:gmatch("%S+") do parts[#parts + 1] = word end
                local cols = tonumber(parts[1]) or BazBars.DEFAULT_COLS
                local rows = tonumber(parts[2]) or BazBars.DEFAULT_ROWS
                cols = math.max(1, math.min(BazBars.MAX_COLS, cols))
                rows = math.max(1, math.min(BazBars.MAX_ROWS, rows))
                local id = addon:CreateNewBar(cols, rows)
                addon:Print(("Created Bar %d (%dx%d). Use Edit Mode or /bb to configure."):format(id, cols, rows))
            end,
        },
        export = {
            desc = "Export bar config: /bb export <id>",
            handler = function(args)
                local id = tonumber(args:match("(%d+)"))
                if id then
                    local str = addon:ExportBar(id)
                    if str then
                        addon.Dialogs:ShowExportString(str)
                    else
                        addon:Print("Bar " .. id .. " not found.")
                    end
                else
                    addon:Print("Usage: /bb export <bar id>")
                end
            end,
        },
        import = {
            desc = "Import bar config: /bb import <string>",
            handler = function(args)
                local importStr = args:match("^(.+)$")
                if importStr and importStr ~= "" then
                    addon:ImportBar(importStr)
                else
                    addon.Dialogs:ShowImportDialog()
                end
            end,
        },
        duplicate = {
            desc = "Duplicate a bar: /bb duplicate <id>",
            usage = "dup, copy",
            handler = function(args)
                local id = tonumber(args:match("(%d+)"))
                if id then
                    local newID = addon:DuplicateBar(id)
                    if newID then
                        addon:Print(("Duplicated Bar %d as Bar %d."):format(id, newID))
                    end
                else
                    addon:Print("Usage: /bb duplicate <bar id>")
                end
            end,
        },
        delete = {
            desc = "Delete a bar: /bb delete <id>",
            usage = "remove",
            handler = function(args)
                local id = tonumber(args:match("(%d+)"))
                if id then
                    addon:DeleteBar(id)
                else
                    addon:Print("Usage: /bb delete <bar id>")
                end
            end,
        },
        scale = {
            desc = "Set bar scale: /bb scale <id> <scale>",
            handler = function(args)
                local parts = {}
                for word in args:gmatch("%S+") do parts[#parts + 1] = word end
                local id = tonumber(parts[1])
                local scale = tonumber(parts[2])
                if id and scale then
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:SetScale(frame, scale)
                        addon:Print(("Bar %d scale set to %.2f"):format(id, scale))
                    else
                        addon:Print("Bar " .. id .. " not found.")
                    end
                else
                    addon:Print("Usage: /bb scale <bar id> <scale>")
                end
            end,
        },
        padding = {
            desc = "Set button spacing: /bb padding <id> <pixels>",
            usage = "spacing",
            handler = function(args)
                local parts = {}
                for word in args:gmatch("%S+") do parts[#parts + 1] = word end
                local id = tonumber(parts[1])
                local spacing = tonumber(parts[2])
                if id and spacing then
                    local frame = addon.Bar:Get(id)
                    if frame then
                        addon.Bar:Resize(frame, frame.barData.rows, frame.barData.cols, spacing)
                        addon:Print(("Bar %d spacing set to %d"):format(id, spacing))
                    else
                        addon:Print("Bar " .. id .. " not found.")
                    end
                else
                    addon:Print("Usage: /bb padding <bar id> <pixels>")
                end
            end,
        },
        reset = {
            desc = "Reset all bars (reloads UI)",
            handler = function()
                addon:Print("Resetting all bars. Reload UI to apply.")
                local p = addon.db and addon.db.profile
                if p then p.bars = {} end
                ReloadUI()
            end,
        },
    },

    -- Minimap button
    minimap = {
        label = "Bars",
        icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
        onClick = function(button)
            local bb = BazUI:GetModule("Bars")
            if button == "LeftButton" then
                if bb and bb.Options then bb.Options:Open() end
            elseif button == "RightButton" then
                if bb and not InCombatLockdown() then
                    local id = bb:CreateNewBar()
                    if id then
                        bb:Print("Created Bar " .. id .. ". Enter Edit Mode to configure.")
                    end
                end
            end
        end,
    },

})

---------------------------------------------------------------------------
-- Per-character button payloads
---------------------------------------------------------------------------
--
-- Bar STRUCTURE (cols/rows/scale/position/keybind shape) lives in the
-- profile and is meant to be shared across characters. Bar PAYLOADS
-- (the actual spell/macro/item slotted into each button) are class-
-- specific, so they live OUTSIDE the profile in a per-character /
-- per-profile / per-bar bucket:
--
--   BazUIDB.barsCharButtons[charKey][profileName][barID]["r:c"] = action
--
-- LoadButton / SaveButton route reads + writes through this bucket. A
-- one-shot migration on first load with the new format moves any
-- legacy profile.bars[id].buttons into the current character's bucket
-- so users coming from earlier versions don't lose their slotted
-- abilities; other characters using the same profile then start with
-- empty bars and re-slot independently (the desired behavior).
---------------------------------------------------------------------------

-- Buttons are keyed by the character's GUID, which a deleted and
-- re-created character never shares (a same-name character did, and
-- inherited the old one's bars). Earlier builds keyed by name-realm;
-- ResolveCharBucket moves or drops those tables once at login.
local function LegacyCharKey()
    local name, realm = UnitFullName("player")
    return (name or "Unknown") .. "-" .. (realm or "Unknown")
end

local function GetCharKey()
    local guid = UnitGUID("player")
    if guid and guid ~= "" then return guid end
    return LegacyCharKey()
end

local function GetActiveProfileName()
    if BazUI and BazUI.GetActiveProfile then
        return BazUI:GetActiveProfile("Bars") or "Default"
    end
    return "Default"
end

local function CharBucket(create)
    if not BazUIDB then return nil end
    if create then BazUIDB.barsCharButtons = BazUIDB.barsCharButtons or {} end
    local cb = BazUIDB.barsCharButtons
    if not cb then return nil end
    local ck = GetCharKey()
    if create then cb[ck] = cb[ck] or {} end
    if not cb[ck] then return nil end
    local pn = GetActiveProfileName()
    if create then cb[ck][pn] = cb[ck][pn] or {} end
    return cb[ck][pn]
end

function addon:GetCharBarButtons(barID, create)
    local bucket = CharBucket(create)
    if not bucket then return nil end
    if create then bucket[barID] = bucket[barID] or {} end
    return bucket[barID]
end

function addon:GetButtonPayload(barID, key)
    local t = self:GetCharBarButtons(barID, false)
    return t and t[key] or nil
end

function addon:SetButtonPayload(barID, key, payload)
    local t = self:GetCharBarButtons(barID, true)
    if not t then return end
    t[key] = payload   -- nil clears
end

function addon:ClearCharBarButtons(barID)
    local bucket = CharBucket(false)
    if bucket then bucket[barID] = nil end
end

-- Per-character, per-profile bookkeeping that is not a bar payload
-- (AutoFill's "already filled" mark). Lives beside the bar tables under
-- a string key, which the numeric barID lookups never touch.
function addon:GetCharBarState(create)
    local bucket = CharBucket(create)
    if not bucket then return nil end
    if create then bucket._state = bucket._state or {} end
    return bucket._state
end

-- True when any bar of this character and profile holds a button.
function addon:HasAnyButtons()
    local bucket = CharBucket(false)
    if not bucket then return false end
    for key, buttons in pairs(bucket) do
        if type(key) == "number" and type(buttons) == "table" and next(buttons) then return true end
    end
    return false
end

local function IsSpellKnownHere(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
        return C_SpellBook.IsSpellKnownOrInSpellBook(spellID)
    end
    return IsSpellKnown(spellID)
end

-- One-time at login: a table saved under the old name-realm key is
-- moved to this character's GUID if it looks like this character's
-- (recorded class matches, or its spells are ones this character
-- knows) and dropped otherwise: names are unique per realm, so a
-- mismatch means that character is gone. The GUID table records the
-- class and name for next time.
function addon:ResolveCharBucket()
    local cb = BazUIDB and BazUIDB.barsCharButtons
    if not cb then return end
    local ck, legacy = GetCharKey(), LegacyCharKey()
    local _, class = UnitClass("player")

    if ck ~= legacy and not cb[ck] and cb[legacy] then
        local old = cb[legacy]
        local adopt
        if old._meta and old._meta.class then
            adopt = old._meta.class == class
        else
            local known, unknown = 0, 0
            for pn, bars in pairs(old) do
                if pn ~= "_meta" and type(bars) == "table" then
                    for barID, buttons in pairs(bars) do
                        if type(barID) == "number" and type(buttons) == "table" then
                            for _, payload in pairs(buttons) do
                                if type(payload) == "table" and payload.type == "spell"
                                    and type(payload.data) == "table" and payload.data.id then
                                    if IsSpellKnownHere(payload.data.id) then known = known + 1 else unknown = unknown + 1 end
                                end
                            end
                        end
                    end
                end
            end
            adopt = known >= unknown
        end
        if adopt then cb[ck] = old end
        cb[legacy] = nil
    end

    if cb[ck] then
        cb[ck]._meta = { class = class, name = LegacyCharKey() }
    end
end

-- One-shot migration: walks profile.bars[*].buttons and moves each
-- payload to the current character's bucket. Per-profile sentinel so
-- subsequent characters using the same profile DON'T inherit (which
-- is the bug we're fixing). Run before any LoadButton call so the
-- live load reads from the new location.
function addon:MigrateButtonsToCharStorage()
    local profile = self.db and self.db.profile
    if not profile or not profile.bars then return end
    if profile._bbCharButtonsMigrated then return end

    local moved = 0
    local barsTouched = 0
    for barID, barData in pairs(profile.bars) do
        if barData.buttons and next(barData.buttons) then
            local target = self:GetCharBarButtons(barID, true)
            if target then
                for key, payload in pairs(barData.buttons) do
                    target[key] = payload
                    moved = moved + 1
                end
                barsTouched = barsTouched + 1
            end
            barData.buttons = {}   -- clear from profile
        end
    end

    profile._bbCharButtonsMigrated = true

    if moved > 0 then
        self:Print(string.format(
            "Moved %d button payloads across %d bar(s) into per-character storage. Other characters using this profile will start with empty bars - slot their own abilities and they'll save independently.",
            moved, barsTouched))
    end
end

-- Lifecycle callbacks (defined after addon is assigned)
addon.config.onLoad = function(self)
    self.Options:Setup()
end

---------------------------------------------------------------------------
-- Hide Blizzard's default action bar (Bar 1 + endcap art)
---------------------------------------------------------------------------
--
-- Blizzard's Edit Mode lets users hide Bars 2-8, but Bar 1 (the main
-- action bar with slots 1-12 + the gryphon endcap chrome) cannot be
-- hidden through Edit Mode. Most BazBars users move all their
-- abilities onto BazBars buttons and want the default Bar 1 chrome
-- gone.
--
-- Reparenting a secure frame is blocked during combat. ApplyDefault-
-- BarHidden() bails out cleanly with a queued state if called in
-- combat; PLAYER_REGEN_ENABLED re-runs the queued change once we're
-- safe again. Out-of-combat toggling is fully live - no /reload
-- required either way.
---------------------------------------------------------------------------

local hiddenParent
local function GetHiddenParent()
    if not hiddenParent then
        hiddenParent = CreateFrame("Frame")
        hiddenParent:Hide()
    end
    return hiddenParent
end

-- Two independent toggles:
--
--   ART  - reparent the chrome to the hidden carrier too. Classic's
--          MainMenuBarArtFrame is separate from MainActionBar, and
--          Blizzard can Show its artwork again during layout updates.
--
--   BAR  - reparent the whole MainActionBar (containers + buttons +
--          art) to a hidden carrier and unregister its events. This
--          is combat-protected (deferred to PLAYER_REGEN_ENABLED if
--          called in combat). Restoring after a hide leaves Blizzard's
--          event list cleared until the next /reload, but the visible
--          state is restored live.
--
-- BAR-hide is a superset of ART-hide. When BAR is on, ART's value is
-- moot (everything is invisible anyway).
---------------------------------------------------------------------------

local function HideOne(f, hidden)
    if not f then return end
    if f._bbOriginalParent then return end   -- already hidden
    f._bbOriginalParent = f:GetParent() or _G.UIParent
    f._bbWasShown      = f:IsShown()
    f:SetParent(hidden)
    f:Hide()
end

local function RestoreOne(f)
    if not f or not f._bbOriginalParent then return end
    f:SetParent(f._bbOriginalParent)
    if f._bbWasShown then f:Show() else f:Hide() end
    f._bbOriginalParent = nil
    f._bbWasShown      = nil
end

local function SetBlizzardArtShown(show)
    local function Apply(frame)
        if show then RestoreOne(frame) else HideOne(frame, GetHiddenParent()) end
    end
    -- Era's decorative frame is a sibling of the action-button container.
    -- Its textures (including both endcaps) stay hidden even when Show is
    -- called on them; their parent remains beneath our hidden carrier.
    Apply(_G.MainMenuBarArtFrame)
    local bar = _G.MainActionBar
    if bar then
        Apply(bar.BorderArt)
        Apply(bar.EndCaps)
    end
end

local function HideMainActionBar(hidden)
    local bar = _G.MainActionBar
    if not bar then return end
    HideOne(bar, hidden)
    if not bar._bbEventsCleared then
        bar:UnregisterAllEvents()
        bar._bbEventsCleared = true
    end
end

local function ShowMainActionBar()
    local bar = _G.MainActionBar
    if not bar then return false end
    local needsReload = bar._bbEventsCleared and true or false
    RestoreOne(bar)
    return needsReload
end

function addon:ApplyDefaultBarVisibility()
    local p = addon.db and addon.db.profile
    if not p then return end
    local hideBar = p.hideDefaultActionBar    == true
    local hideArt = p.hideDefaultActionBarArt == true

    if InCombatLockdown() then
        addon._pendingBlizzardBarVisibility = { bar = hideBar, art = hideArt }
        if self.Print then
            self:Print("Cannot toggle Blizzard bar visibility during combat. Will apply when combat ends.")
        end
        return false
    end

    if hideBar then
        -- Capture the artwork's visible state before hiding its button parent.
        SetBlizzardArtShown(false)
        HideMainActionBar(GetHiddenParent())
    else
        local needsReload = ShowMainActionBar()
        -- Bar visible: apply art toggle independently.
        SetBlizzardArtShown(not hideArt)
        if needsReload and self.Print then
            self:Print("Default action bar restored. /reload to fully restore Blizzard's bar event handling.")
        end
    end

    -- Blizzard's stance bar keeps running its own show/hide logic; parked
    -- under the hidden carrier none of it is visible.
    local stance = _G.StanceBar
    if stance then
        if p.hideStanceBar ~= false then HideOne(stance, GetHiddenParent()) else RestoreOne(stance) end
    end
    return true
end

-- Back-compat alias used by onReady wiring (just runs the apply pass
-- with whatever the saved state already is).
function addon:HideDefaultActionBar()
    self:ApplyDefaultBarVisibility()
end

---------------------------------------------------------------------------
-- First-run CVar warning
-- If the player has "cast on key down" enabled, dragging BazBars buttons
-- would also fire the cast (mousedown triggers the secure click before drag
-- can start). BazBars buttons always register for mouseup, so they work
-- correctly regardless - but the user may see inconsistent behavior between
-- their Blizzard bars and BazBars. Offer to change the CVar on first run.
---------------------------------------------------------------------------

local function MaybeShowKeyDownWarning()
    if addon.db.profile.keyDownWarningShown then return end
    if not GetCVarBool("ActionButtonUseKeyDown") then
        addon.db.profile.keyDownWarningShown = true
        return
    end
    addon.db.profile.keyDownWarningShown = true
    if BazUI.Confirm then
        BazUI:Confirm({
            title       = "BazUIBars: Cast on key up?",
            body        = "BazUIBars works best with |cffffffffCast on key up|r enabled - the global game setting that also matches Blizzard's default.\n\nYou currently have |cffff7f00Cast on key down|r enabled. BazUI Bars buttons still work correctly, but your Blizzard action bars will feel slightly different from BazUI Bars.\n\nChange the setting to |cffffffffCast on key up|r now?",
            acceptLabel = "Yes, change it",
            cancelLabel = "Keep my setting",
            acceptStyle = "primary",
            onAccept    = function()
                SetCVar("ActionButtonUseKeyDown", "0")
                print("|cff3399ff[BazUI Bars]|r Cast on key up enabled.")
            end,
        })
    end
end

addon.config.onReady = function(self)
    -- The GUID and the spellbook are both available at login; the
    -- button tables need them before any bar loads.
    self:MigrateButtonsToCharStorage()
    self:ResolveCharBucket()
    self.Bar:LoadAll()
    self:HideDefaultActionBar()   -- no-op unless the option is set

    -- Abilities on the bars (AutoFill.lua): once the world is entered,
    -- spells the character doesn't know are cleared and a new
    -- character's abilities are placed; after a respec the spellbook
    -- changes and the clear runs again; each newly learned spell takes
    -- the first empty slot.
    if self.AutoFill then
        local firstWorld = true
        self:On("PLAYER_ENTERING_WORLD", function()
            if not firstWorld then return end
            firstWorld = false
            C_Timer.After(1.5, function() addon.AutoFill:OnWorldEntered() end)
        end)
        self:On("SPELLS_CHANGED", function()
            if not firstWorld then addon.AutoFill:QueuePrune() end
        end)
        self:On("LEARNED_SPELL_IN_SKILL_LINE", function(_, spellID) addon.AutoFill:OnLearned(spellID) end)
        self:On("PLAYER_REGEN_ENABLED", function()
            addon.AutoFill:PlacePending()
            addon.AutoFill:PruneIfPending()
        end)
    end
    -- Re-apply any pending default-bar visibility toggle once combat
    -- ends. Setter just stashes the desired state if called in combat.
    self:On("PLAYER_REGEN_ENABLED", function()
        if addon._pendingBlizzardBarVisibility then
            addon._pendingBlizzardBarVisibility = nil
            addon:ApplyDefaultBarVisibility()
        end
    end)

    -- Targeted updates - only run the sub-update each event actually
    -- needs, instead of the full 8-function UpdateButton for every
    -- button on every event. High-frequency combat events like
    -- SPELL_UPDATE_COOLDOWN can fire dozens of times per second in
    -- raids; doing a full update pass each time was the main perf hit.
    self:On("SPELL_UPDATE_COOLDOWN", function() addon:UpdateAllCooldowns() end)
    self:On("SPELL_UPDATE_USABLE",  function() addon:UpdateAllUsable() end)
    self:On("UNIT_POWER_UPDATE",    function() addon:UpdateAllUsable() end)
    self:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function() addon:UpdateAllGlow() end)
    self:On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function() addon:UpdateAllGlow() end)
    self:On("UPDATE_MACROS",        function() addon:UpdateAllMacroNames() end)
    -- The lit "current" state: stance and form changes, casts starting
    -- and ending, auto-attack and auto-shot toggling.
    self:On({ "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "CURRENT_SPELL_CAST_CHANGED",
              "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT" },
        function() addon:UpdateAllChecked() end)
    self:On("PLAYER_TARGET_CHANGED", function()
        addon:OnRangeEvent()
        addon:RefreshRangeTicker()
    end)

    -- These are infrequent events - a full update pass is fine.
    self:On("BAG_UPDATE",               function() addon:QueueFullUpdate() end)
    self:On("PLAYER_EQUIPMENT_CHANGED", function() addon:QueueFullUpdate() end)
    self:On("ACTIONBAR_UPDATE_STATE",   function() addon:QueueFullUpdate() end)

    -- The ticker follows the target, not combat; these just keep it
    -- honest across a combat boundary.
    self:On({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
        function() addon:RefreshRangeTicker() end)

    self:SetupEditMode()

    C_Timer.After(1, function()
        addon:UpdateAllButtons()
        addon.Keybinds:RestoreAll()
        MaybeShowKeyDownWarning()
        -- A /reload keeps the target, so pick the ticker back up.
        addon:RefreshRangeTicker()
    end)
end

-- Profile change handler
addon:OnProfileChanged(function(newProfile, oldProfile)
    -- Clear all keybinds
    if addon.Keybinds then
        local keybindOwner = _G["BazUIBarsKeybindOwner"]
        if keybindOwner and not InCombatLockdown() then
            ClearOverrideBindings(keybindOwner)
        end
    end

    -- Destroy all existing bars
    addon.Bar:DeselectAll()
    addon.Bar:DestroyAll()

    -- Recreate from new profile data
    addon.Bar:LoadAll()
    addon:ApplyDefaultBarVisibility()

    -- Restore keybinds for new profile
    if addon.Keybinds then
        addon.Keybinds:RestoreAll()
    end

    -- Refresh options panel
    addon.Options:Refresh()

    addon:Print("Profile changed. Bars reloaded.")
end)

---------------------------------------------------------------------------
-- Edit Mode Integration
---------------------------------------------------------------------------

function addon:SetupEditMode()
    if not EditModeManagerFrame then return end

    -- "Create New BazBar" button in Edit Mode panel. Auto-size to
    -- whatever the text needs + a small horizontal padding so the
    -- button hugs its label instead of stretching across the panel.
    -- Scale 1.2 so the whole button (text + chrome) reads ~20% larger
    -- without changing the auto-sizing math.
    local createBtn = CreateFrame("Button", nil, EditModeManagerFrame, "UIPanelButtonTemplate")
    createBtn:SetText("Create New BazBar")
    createBtn:SetSize((createBtn.Text:GetStringWidth() or 120) + 24, 22)
    createBtn:SetScale(1.2)
    createBtn:SetPoint("BOTTOM", EditModeManagerFrame, "BOTTOM", 0, -36)
    createBtn:SetScript("OnClick", function()
        if not InCombatLockdown() then
            local id = addon:CreateNewBar()
            if id then
                addon:Print("Created Bar " .. id)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------

-- Helper: iterate all buttons with an action and call `fn(btn)` on each.
local function ForEachButton(fn)
    for _, frame in pairs(addon.Bar:GetAll()) do
        for _, row in pairs(frame.buttons) do
            for _, btn in pairs(row) do
                if btn.action then fn(btn) end
            end
        end
    end
end

-- Full update - walks every button through all 8 sub-updates.
-- Used at startup, profile change, and rare events (BAG_UPDATE, etc.).
function addon:UpdateAllButtons()
    ForEachButton(function(btn) self.Button:UpdateButton(btn) end)
end

-- Targeted update helpers - each walks the button grid but only runs
-- the one sub-update that the triggering event actually needs.
function addon:UpdateAllCooldowns()
    ForEachButton(function(btn) self.Button:UpdateCooldown(btn) end)
end

function addon:UpdateAllUsable()
    ForEachButton(function(btn) self.Button:UpdateUsable(btn) end)
end

function addon:UpdateAllGlow()
    ForEachButton(function(btn) self.Button:UpdateGlow(btn) end)
end

function addon:UpdateAllChecked()
    ForEachButton(function(btn) self.Button:UpdateChecked(btn) end)
end

function addon:UpdateAllMacroNames()
    ForEachButton(function(btn) self.Button:UpdateMacroName(btn) end)
end

function addon:OnRangeEvent()
    ForEachButton(function(btn) self.Button:UpdateRange(btn) end)
end

---------------------------------------------------------------------------
-- Coalesced full update - infrequent events (BAG_UPDATE, equip change,
-- action bar state) may fire in rapid bursts (e.g. swapping a gear set
-- triggers one PLAYER_EQUIPMENT_CHANGED per slot). Instead of doing a
-- full update pass per event, set a dirty flag and flush once at the
-- end of the frame.
---------------------------------------------------------------------------

local fullUpdatePending = false
local flushFrame = CreateFrame("Frame")
flushFrame:Hide()
flushFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    fullUpdatePending = false
    addon:UpdateAllButtons()
end)

function addon:QueueFullUpdate()
    if fullUpdatePending then return end
    fullUpdatePending = true
    flushFrame:Show()
end

---------------------------------------------------------------------------
-- Range ticker
--
-- Range is a distance, so it changes as either of you moves, with no
-- event to announce it: the only way to keep the colour honest is to
-- poll. It used to poll in combat only, which left the colour frozen
-- at whatever it was when the target was picked - walk into range out
-- of combat and the button stayed red, walk out of range and it stayed
-- white. So it now runs whenever a target exists, in or out of combat,
-- and sits idle the rest of the time.
---------------------------------------------------------------------------

local rangeTimer = 0
local RANGE_INTERVAL = 0.2
local rangeFrame = CreateFrame("Frame")
rangeFrame:Hide()  -- starts paused; RefreshRangeTicker turns it on

rangeFrame:SetScript("OnUpdate", function(self, elapsed)
    rangeTimer = rangeTimer + elapsed
    if rangeTimer >= RANGE_INTERVAL then
        rangeTimer = 0
        addon:OnRangeEvent()
    end
end)

function addon:StartRangeTicker()
    rangeTimer = 0
    rangeFrame:Show()
end

function addon:StopRangeTicker()
    rangeFrame:Hide()
end

-- Run only while there is something to measure against.
function addon:RefreshRangeTicker()
    if UnitExists("target") then
        if not rangeFrame:IsShown() then self:StartRangeTicker() end
    else
        self:StopRangeTicker()
    end
end

addon.rangeFrame = rangeFrame

---------------------------------------------------------------------------
-- Import / Export
---------------------------------------------------------------------------

function addon:ExportBar(barID)
    local barData = self.db.profile.bars[barID]
    if not barData then return nil end

    local exportData = CopyTable(barData)
    exportData.pos = nil
    exportData.id = nil
    -- Bake the CURRENT character's slotted payloads into the export
    -- so the receiver gets both structure and contents. The profile
    -- side stays empty post-migration; reading from charButtons is
    -- where the actual data lives now.
    local charBtns = self:GetCharBarButtons(barID, false)
    if charBtns and next(charBtns) then
        exportData.buttons = CopyTable(charBtns)
    else
        exportData.buttons = nil
    end

    return BazUI:Serialize(exportData)
end

function addon:ImportBar(encodedString)
    if not encodedString or encodedString == "" then
        self:Print("No import string provided.")
        return
    end

    local barData = BazUI:Deserialize(encodedString)
    if not barData or type(barData) ~= "table" then
        self:Print("Invalid import string.")
        return
    end

    local newID = self.Bar:GetNextID()
    barData.id = newID
    barData.pos = nil
    -- Pull any imported button payloads OFF the profile entry and
    -- apply them to the current character's bucket. The profile
    -- itself stays structure-only.
    local importedButtons = barData.buttons
    barData.buttons = {}

    self.db.profile.bars[newID] = barData

    if importedButtons and next(importedButtons) then
        local target = self:GetCharBarButtons(newID, true)
        if target then
            for key, payload in pairs(importedButtons) do
                target[key] = CopyTable(payload)
            end
        end
    end

    local frame = self.Bar:Create(barData)

    for r, row in pairs(frame.buttons) do
        for c, btn in pairs(row) do
            self.Button:LoadButton(btn)
        end
    end

    self.Bar:ApplyVisibility(frame)
    self.Bar:UpdateSlotArt(frame)
    self.Bar:UpdateButtonVisibility(frame)
    self.Bar:SetBarAlpha(frame, BazBars.GetBarSetting(barData, "alpha") or 1.0)
    self.Bar:ApplyMouseoverFade(frame)
    self.Options:Refresh()

    self:Print("Imported as Bar " .. newID .. ".")
    return newID
end

---------------------------------------------------------------------------
-- Bar Management
---------------------------------------------------------------------------

function addon:DuplicateBar(sourceID)
    if InCombatLockdown() then
        self:Print("Cannot duplicate bars during combat.")
        return
    end

    local sourceData = self.db.profile.bars[sourceID]
    if not sourceData then
        self:Print("Bar " .. sourceID .. " not found.")
        return
    end

    local newID = self.Bar:GetNextID()
    local newData = CopyTable(sourceData)
    newData.id = newID
    newData.pos = nil
    newData.customName = (newData.customName or ("Bar " .. sourceID)) .. " (Copy)"
    -- Buttons live per-character now; the profile copy carries no
    -- payload data (it would be empty anyway post-migration). We
    -- copy the current character's source-bar payload into the new
    -- bar's per-char bucket below.
    newData.buttons = {}

    self.db.profile.bars[newID] = newData

    -- Mirror the current character's slotted buttons from source -> new.
    local sourceBtns = self:GetCharBarButtons(sourceID, false)
    if sourceBtns and next(sourceBtns) then
        local targetBtns = self:GetCharBarButtons(newID, true)
        for key, payload in pairs(sourceBtns) do
            targetBtns[key] = CopyTable(payload)
        end
    end

    local frame = self.Bar:Create(newData)

    for r, row in pairs(frame.buttons) do
        for c, btn in pairs(row) do
            self.Button:LoadButton(btn)
        end
    end

    self.Bar:ApplyVisibility(frame)
    self.Bar:UpdateSlotArt(frame)
    self.Bar:UpdateButtonVisibility(frame)
    self.Bar:SetBarAlpha(frame, BazBars.GetBarSetting(newData, "alpha") or 1.0)
    self.Bar:ApplyMouseoverFade(frame)
    self.Options:Refresh()

    return newID
end

function addon:CreateNewBar(cols, rows)
    if InCombatLockdown() then
        self:Print("Cannot create bars during combat.")
        return
    end

    local id = self.Bar:GetNextID()
    local barData = BazBars.DefaultBarData(id)
    barData.cols = cols or BazBars.DEFAULT_COLS
    barData.rows = rows or BazBars.DEFAULT_ROWS

    self.db.profile.bars[id] = barData
    self.Bar:Create(barData)
    self.Options:Refresh()

    return id
end

function addon:DeleteBar(id)
    if InCombatLockdown() then
        self:Print("Cannot delete bars during combat.")
        return
    end

    if self.Bar:Destroy(id) then
        self.db.profile.bars[id] = nil
        -- Clear the current character's payload for this bar. Other
        -- characters' payloads for this bar in this profile are now
        -- orphaned but harmless; they'll be cleaned up on the next
        -- per-profile cleanup pass (or never - they consume a few
        -- bytes of SV memory and are easy to ignore).
        self:ClearCharBarButtons(id)
        self.Options:Refresh()
        self:Print("Bar " .. id .. " deleted.")
    else
        self:Print("Bar " .. id .. " not found.")
    end
end
