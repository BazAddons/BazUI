-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: what we are leaning on
--
-- A good deal of this addon works by taking hold of the game's own
-- furniture: a frame by name, a template, a console setting, an entry in
-- one of the game's tables. None of that is API. It is whatever the
-- client happened to be built with, and a new client is free to build it
-- differently - a frame renamed, a template folded into another, a member
-- moved. When that happens nothing errors. A hook silently never fires, a
-- frame is never hidden, a switch does nothing, and it all looks like a
-- bug in our code.
--
-- So every one of those holds is declared next to the code that takes it,
-- and /baz check reads the lot back:
--
--   BazUI:RegisterDependency{
--       module = "Nameplates",
--       label  = "C_NamePlate.GetNamePlateForUnit",
--       why    = "Finding the frame the game gave a unit.",
--       check  = function() return BazUI.Has.Member(C_NamePlate, "GetNamePlateForUnit") end,
--   }
--
-- Declared beside the code rather than in a list here, because a list
-- somewhere else is a list that goes stale the first time somebody
-- changes the code without remembering it exists.
---------------------------------------------------------------------------

local dependencies = {}

---------------------------------------------------------------------------
-- The kinds of thing worth asking about
---------------------------------------------------------------------------

BazUI.Has = {}

function BazUI.Has.Global(name)
    return _G[name] ~= nil
end

-- A frame by name. Distinct from a global because plenty of globals are
-- functions and the failure reads differently.
function BazUI.Has.Frame(name)
    local frame = _G[name]
    return frame ~= nil and type(frame) == "table" and frame.GetObjectType ~= nil
end

function BazUI.Has.Member(container, key)
    return type(container) == "table" and container[key] ~= nil
end

function BazUI.Has.Template(name)
    local info = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo(name)
    return info ~= nil
end

-- A texture file. The client has no way to be asked whether a file
-- exists, so it is asked to load one: a texture that failed comes back
-- with nothing on it. Cached, because the answer cannot change without
-- restarting the game - the client reads its art at startup the same way
-- it reads its fonts.
local textureCache = {}

function BazUI.Has.Texture(path)
    if type(path) ~= "string" or path == "" then return false end
    local known = textureCache[path]
    if known ~= nil then return known end

    local probe = BazUI._texProbe
    if not probe then
        probe = UIParent:CreateTexture(nil, "BACKGROUND")
        probe:Hide()
        BazUI._texProbe = probe
    end

    local ok = pcall(probe.SetTexture, probe, path)
    local present = ok and probe:GetTexture() ~= nil
    pcall(probe.SetTexture, probe, nil)

    textureCache[path] = present
    return present
end

-- A console setting. GetCVar answers nil for one the client has never
-- heard of, which is what a renamed setting looks like.
function BazUI.Has.CVar(name)
    local get = C_CVar and C_CVar.GetCVar or _G.GetCVar
    if not get then return false end
    local ok, value = pcall(get, name)
    return ok and value ~= nil
end

---------------------------------------------------------------------------
-- Values we may not be allowed to look at
--
-- Forever can hand back a number or a boolean that an addon may hold and
-- pass on to a widget, but may not read. Reading means more than it
-- sounds: comparing it, doing arithmetic on it, and even testing it for
-- truth all count, and all of them raise rather than answering.
--
--   local hasPower = BazUI.Secret.Read(function() return max > 0 end, true)
--
-- The reading goes in the function; the fallback is what to believe when
-- we are not allowed to know, and should be the answer that leaves the
-- interface looking normal rather than the one that hides something.
--
-- Always ask by trying. Never test the client version instead: which
-- values are secret varies by power type, by unit and by context, so a
-- rule written here would be a guess that goes stale.
---------------------------------------------------------------------------

BazUI.Secret = {}

function BazUI.Secret.Read(fn, fallback)
    local ok, value = pcall(fn)
    if not ok then return fallback end
    return value
end

-- Which functions will take one
--
-- The client documents this itself. Every entry in
-- Blizzard_APIDocumentationGenerated carries a SecretArguments field, and
-- "AllowedWhenTainted" means an addon may pass a secret to it. That is a
-- short list, and worth knowing by heart, because everything on it is a
-- place a value we may not read can still do its job:
--
--   StatusBar   SetValue, SetMinMaxValues, SetStatusBarColor,
--               SetStatusBarDesaturated
--   FontString  SetText, SetFormattedText, SetTextColor, SetTextToFit
--   Texture     SetTexture, SetAtlas, SetColorTexture, SetVertexColor,
--               SetTexCoord, SetDesaturated, SetRotation
--   Frame       SetAlpha, SetAlphaFromBoolean, SetID
--   Numbers     BreakUpLargeNumbers, AbbreviateNumbers,
--               RoundToNearestString, FloorToNearestString,
--               TruncateWhenZero
--   Color       GetClassColor, EvaluateColorFromBoolean, WrapTextInColor
--
-- So a health bar can be filled, a number can be written out with its
-- thousands separators, and a class color can be found, all without ever
-- being allowed to look. Anything absent raises: SetGradient, string
-- format, indexing a table with one, and every comparison.
--
-- Note what that costs. A color whose parts are secret can be painted but
-- not shaded, so whatever holds one has to know. Ours say so with a
-- `secret` field, and Core/StatusBar drops its gradient when it sees it.

-- Keep what a call handed back without looking at any of it. The number of
-- values returned is never itself secret, so it is the one thing we can
-- test - which is what makes this safe where `if r then` would raise.
function BazUI.Secret.Color(...)
    if select("#", ...) < 3 then return nil end
    local r, g, b = ...
    return { r, g, b, 1, secret = true }
end

-- Refused, which is not the same as secret
--
-- Most guarded APIs hand back a secret value and let you carry it about.
-- A few refuse instead, and the aura reads are the ones that matter to us:
-- C_UnitAuras.GetAuraDataByIndex and its neighbours carry
-- RequiresUnitAuraAccess, whose documented failure mode is "Error" rather
-- than "ReturnNothing".
--
-- **pcall does not catch it.** It is reported as a restriction violation
-- with the taint attached, not as a Lua error the caller may swallow, so
-- wrapping the call changes nothing except where the traceback points. The
-- only way not to have the error is not to make the call.
--
-- Which the client will tell us, and precisely: C_Secrets answers per unit,
-- per index, before anything is read. Ask first.
--
-- HasSecretRestrictions is the cheap way out on a client that has none of
-- this - Classic Era - where every Should* would answer false anyway.

function BazUI.Secret.AurasReadable()
    if not C_Secrets then return true end
    if C_Secrets.HasSecretRestrictions and not C_Secrets.HasSecretRestrictions() then
        return true
    end
    if C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return false
    end
    return true
end

function BazUI.Secret.AuraReadable(unit, index, filter)
    if not BazUI.Secret.AurasReadable() then return false end
    if C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret then
        -- Plain arguments in, plain boolean out, so this one really can be
        -- pcall'd: it is a question about a restriction, not a read through
        -- one.
        local ok, secret = pcall(C_Secrets.ShouldUnitAuraIndexBeSecret, unit, index, filter)
        if ok and secret then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- Can this client run a secure handler snippet?
--
-- Snippets are strings compiled inside the restricted environment, which
-- Blizzard's RestrictedExecution.lua does with `loadstring_untainted`. On
-- Forever build 69893 that file captures the global at load and gets nil,
-- so every snippet dies with "attempt to call a nil value" the first time
-- it runs - inside their code, from a click, with nothing to catch it.
--
-- Nothing an addon can fix, and nothing an addon can survive either: the
-- failure happens at click time, not when the snippet is installed, so
-- there is no pcall to put around it. The only sound response is not to
-- install one, and to do the job insecurely instead where that is
-- possible at all.
--
-- Asked once and remembered, because it cannot change within a session.
---------------------------------------------------------------------------

local snippetsUsable

function BazUI.SecureSnippetsUsable()
    if snippetsUsable == nil then
        snippetsUsable = (_G.loadstring_untainted ~= nil)
    end
    return snippetsUsable
end

---------------------------------------------------------------------------
-- Keeping one of Blizzard's frames out of the way
--
-- Not by replacing its Show, and not by replacing its OnShow. Both write
-- to a frame we do not own. Forever's Edit Mode managed frames are
-- protected, and writing to ObjectiveTrackerFrame's method table left
-- Blizzard's own `self:Show()` looking at a nil - an error in their file,
-- from our hook, with nothing in the message to say so.
--
-- HookScript appends a handler and touches nothing else, so the frame
-- keeps every script it shipped with. State is held here rather than in
-- fields on their frame, for the same reason.
--
--   BazUI.SuppressFrame(ObjectiveTrackerFrame, function() return hide end)
--
-- The test is asked each time the frame shows, so the switch can change
-- without anything being unhooked. Hiding is skipped in combat: these are
-- protected frames, and the call would fail anyway.
---------------------------------------------------------------------------

local suppressWanted = setmetatable({}, { __mode = "k" })
local suppressedByUs = setmetatable({}, { __mode = "k" })

-- Hide and Show are not simple on one of Blizzard's Edit Mode systems.
-- EditModeSystemMixin replaces both, and their versions write back into the
-- frame's own snap state: HideOverride breaks snapped frames, and breaking a
-- snap ends in ClearAllPointsOverride -> ClearFrameSnap -> snappedToFrame =
-- nil. Called plainly from here, that write belongs to BazUI, and
-- EditModeFrameSetup reads snappedToFrame on the way into Edit Mode - which
-- is how hiding an action bar surfaced as their compact party frames
-- comparing a secret colour. /baz taint named the field.
--
-- securecallfunction runs their method as theirs. The frame still hides;
-- nothing it writes on the way down is ours afterwards.
local function CallClean(frame, method)
    local fn = frame[method]
    if type(fn) ~= "function" then return end
    if securecallfunction then
        securecallfunction(fn, frame)
    else
        fn(frame)
    end
end

function BazUI.SuppressFrame(frame, wanted)
    if not (frame and frame.HookScript and type(wanted) == "function") then
        return false
    end

    if suppressWanted[frame] == nil then
        frame:HookScript("OnShow", function(self)
            local test = suppressWanted[self]
            if test and test() and not InCombatLockdown() then
                suppressedByUs[self] = true
                CallClean(self, "Hide")
            end
        end)
    end
    suppressWanted[frame] = wanted

    if InCombatLockdown() then return true end
    if wanted() then
        suppressedByUs[frame] = true
        CallClean(frame, "Hide")
    elseif suppressedByUs[frame] then
        -- Only ever put back what we took down. Calling Show on a frame
        -- we do not own marks its shown state as ours, and Blizzard's
        -- Edit Mode reads that state on the way in; anything we never
        -- hid is left entirely alone.
        suppressedByUs[frame] = nil
        CallClean(frame, "Show")
    end
    return true
end

---------------------------------------------------------------------------
-- Escape closes this window
--
-- Not through UISpecialFrames, which is the sanctioned way and, on
-- Forever, a taint source. Their CloseSpecialWindows walks that list
-- doing `_G[name]`, and reading a global an addon created taints the
-- read - inside the panel manager, which then carries the taint into
-- whatever it was doing. Opening Edit Mode goes through ShowUIPanel ->
-- CloseWindows -> CloseSpecialWindows, so every one of our frames on
-- that list poisoned it.
--
-- A keyboard handler on the frame itself touches nothing of theirs.
-- Keys propagate normally; only Escape is taken, and only while the
-- frame is up.
---------------------------------------------------------------------------

-- SetPropagateKeyboardInput is protected in combat, and a panel built for
-- the first time during a fight reaches this before anything can stop it -
-- opening the bags mid-fight put an ADDON_ACTION_BLOCKED in the log every
-- time. Every call goes through here, and in combat none of them happen.
--
-- Keyboard setup missed that way is picked up once the fight ends, so a
-- panel first opened in combat takes Escape from then on. What is lost is
-- Escape closing that panel during the fight it was opened in, which is
-- the game's own rule rather than a compromise: it will not let an addon
-- take a key in combat at all.
local combatWatcher
local pendingKeyboard = setmetatable({}, { __mode = "k" })

local function SetPropagate(frame, propagate)
    if InCombatLockdown() then return false end
    frame:SetPropagateKeyboardInput(propagate)
    return true
end

local function EnableEscape(frame)
    if InCombatLockdown() then
        pendingKeyboard[frame] = true
        if not combatWatcher then
            combatWatcher = CreateFrame("Frame")
            combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
            combatWatcher:SetScript("OnEvent", function()
                for f in pairs(pendingKeyboard) do
                    f:EnableKeyboard(true)
                    f:SetPropagateKeyboardInput(true)
                    pendingKeyboard[f] = nil
                end
            end)
        end
        return
    end
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
end

function BazUI.CloseOnEscape(frame, onEscape)
    if not (frame and frame.EnableKeyboard) then return false end

    EnableEscape(frame)
    frame:HookScript("OnKeyDown", function(self, key)
        if key ~= "ESCAPE" then
            SetPropagate(self, true)
            return
        end
        -- Taken, so the press does not also reach the game menu. If the
        -- press cannot be taken it is left to propagate, and Escape does
        -- whatever it would have done without us.
        if not SetPropagate(self, false) then return end
        if onEscape then onEscape(self) else self:Hide() end
    end)
    -- Left propagating when it goes away, so a frame that is hidden
    -- while Escape is held cannot swallow the next key it sees.
    frame:HookScript("OnHide", function(self)
        SetPropagate(self, true)
    end)
    return true
end

---------------------------------------------------------------------------
-- The spell book
--
-- Era answers GetNumSpellTabs / GetSpellTabInfo / GetSpellBookItemInfo,
-- a run of loose values. Forever replaced the family with C_SpellBook,
-- which hands back tables and takes a spell bank rather than a book
-- type. Two clients, one book, so callers ask here and get the three
-- things they actually want: how many lines, where a line starts, and
-- what is sitting in a slot.
---------------------------------------------------------------------------

BazUI.SpellBook = {}

local BOOK_TYPE  = _G.BOOKTYPE_SPELL or "spell"
local SPELL_BANK = _G.Enum and _G.Enum.SpellBookSpellBank
    and _G.Enum.SpellBookSpellBank.Player or 0

function BazUI.SpellBook.NumSkillLines()
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        return C_SpellBook.GetNumSpellBookSkillLines() or 0
    end
    if _G.GetNumSpellTabs then return _G.GetNumSpellTabs() or 0 end
    return 0
end

-- Where a line starts and how long it is. The first slot in the line is
-- the offset plus one, which is the one part both clients agree on.
function BazUI.SpellBook.SkillLine(index)
    if C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo then
        local info = C_SpellBook.GetSpellBookSkillLineInfo(index)
        if not info then return 0, 0 end
        return info.itemIndexOffset or 0, info.numSpellBookItems or 0
    end
    if _G.GetSpellTabInfo then
        local _, _, offset, count = _G.GetSpellTabInfo(index)
        return offset or 0, count or 0
    end
    return 0, 0
end

-- What is in one slot: its kind, its spell, and whether it is passive.
-- The kind is whatever that client calls it - Era says "SPELL", Forever
-- gives an Enum.SpellBookItemType - so callers compare against both
-- rather than this deciding for them.
function BazUI.SpellBook.Item(slot)
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local info = C_SpellBook.GetSpellBookItemInfo(slot, SPELL_BANK)
        if not info then return nil, nil, false end
        return info.itemType, info.spellID or info.actionID, info.isPassive or false
    end
    if _G.GetSpellBookItemInfo then
        local kind, id = _G.GetSpellBookItemInfo(slot, BOOK_TYPE)
        return kind, id, nil
    end
    return nil, nil, false
end

---------------------------------------------------------------------------
-- Declaring and reading back
---------------------------------------------------------------------------

function BazUI:RegisterDependency(def)
    if not (def and def.label and def.check) then return end
    dependencies[#dependencies + 1] = def
end

-- Every declared hold, asked now. Returns the list and how many failed,
-- so something other than the slash command could show this later.
function BazUI:CheckDependencies()
    local results, missing = {}, 0

    for _, def in ipairs(dependencies) do
        -- A check that errors is a check that failed: whatever it was
        -- reaching for was not there to be reached.
        local ok, present = pcall(def.check)
        present = ok and present and true or false
        if not present then missing = missing + 1 end
        results[#results + 1] = {
            module  = def.module or "BazUI",
            label   = def.label,
            why     = def.why,
            present = present,
        }
    end

    table.sort(results, function(a, b)
        if a.module ~= b.module then return a.module < b.module end
        return a.label < b.label
    end)

    return results, missing
end

function BazUI:PrintDependencyReport()
    local results, missing = self:CheckDependencies()

    if #results == 0 then
        self:Print("Nothing is declared as a dependency yet.")
        return
    end

    self:Print(("Checking %d things the addon takes hold of in the game's own UI:"):format(#results))

    local lastModule
    for _, entry in ipairs(results) do
        if entry.module ~= lastModule then
            lastModule = entry.module
            print("  |cffffd700" .. entry.module .. "|r")
        end
        if entry.present then
            print("    |cff44ff44ok|r      " .. entry.label)
        else
            print("    |cffff4444MISSING|r " .. entry.label
                .. (entry.why and ("  - " .. entry.why) or ""))
        end
    end

    if missing == 0 then
        self:Print("|cff44ff44Everything is where we expect it.|r")
    else
        self:Print(("|cffff4444%d missing.|r Anything above marked MISSING will fail quietly rather than error, so start there."):format(missing))
    end
end
