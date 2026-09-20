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
--   Optional fields:
--     when      whether the question applies at all. Use it for a hold on
--               another addon: without this, an integration for something
--               that is not installed reads as broken.
--     whenNote  what to say instead, when it does not apply.
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

-- The same question, when the caller needs to know whether it could be
-- answered at all.
--
-- Read hands back a stand-in and the caller cannot tell the difference,
-- which is what you want nearly every time. Not always, though: a secret
-- string can be handed to a font string and printed, but not read, not
-- measured and not even tested for truth - so code that has to choose
-- between two of them needs a plain boolean to branch on, and the value
-- itself only to pass along. This returns both.
function BazUI.Secret.Try(fn)
    return pcall(fn)
end

-- Whether two unit tokens name the same unit.
--
-- UnitIsUnit is SecretWhenUnitComparisonRestricted, and what it hands
-- back is a secret *boolean* - the one kind that cannot even be tested
-- for truth, so `if UnitIsUnit(a, b) then` raises before the body is
-- reached. Every caller wants the same fallback, so it lives here rather
-- than in each of them: a comparison we are not allowed to make counts as
-- "not the same unit", which leaves the interface plain instead of
-- marking the wrong thing.
function BazUI.Secret.IsUnit(a, b)
    if not (a and b and UnitIsUnit) then return false end
    return BazUI.Secret.Read(function()
        return UnitIsUnit(a, b) and true or false
    end, false)
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
-- A colour is the exception, and it is worth stating plainly.
--
-- There was a helper here for keeping one without reading it: GetClassColor
-- will take a secret class from a tainted caller, so it looked like the way
-- to colour a unit whose identity we may not have - pack what comes back
-- without looking, hand it to the bar, let the widget deal with it.
--
-- It cannot. A colour whose parts are secret is accepted by every setter
-- without complaint and then drawn BLACK, with no error to notice, so the
-- bars went black instead of coloured. Accepting a value and rendering it
-- are not the same thing, and the list above only promises the first.
--
-- Anything that reaches a widget as a colour has to be a number we were
-- allowed to read. Where we were not allowed, the honest answer is a colour
-- of our own choosing. See Core/Units.lua.

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

    -- Combat only stops us where the frame is actually protected.
    --
    -- Refusing on InCombatLockdown alone was too broad, and the player's
    -- casting bar is the frame that showed it: it appears while you are
    -- casting, which is very often mid-fight, and it is a plain status bar
    -- that the game re-shows through its managed-frame system. We declined
    -- to hide it every time it mattered, so it sat under the action bars
    -- through every fight.
    --
    -- IsProtected answers the real question, and answers it per frame. A
    -- protected one is still left alone, and picked up when the fight ends.
    local function Blocked(f)
        return InCombatLockdown() and f:IsProtected()
    end

    if suppressWanted[frame] == nil then
        frame:HookScript("OnShow", function(self)
            local test = suppressWanted[self]
            if test and test() and not Blocked(self) then
                suppressedByUs[self] = true
                CallClean(self, "Hide")
            end
        end)
    end
    suppressWanted[frame] = wanted

    if Blocked(frame) then return true end
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
-- And not by holding the keyboard either, which is what this used to do.
-- EnableKeyboard(true) hands the frame every key, and the only way to pass
-- the rest along is SetPropagateKeyboardInput - which this client marks
-- HasRestrictions, so an addon calling it is refused. The propagation was
-- never switched back on, and every panel opened with `uiSpecialFrame`
-- silently swallowed every keybind for as long as it was up. Escape still
-- worked, because we handled that one ourselves, which is exactly why it
-- went unnoticed: the bags opened with B and would not close with it.
--
-- So take one key instead of all of them. An override binding claims
-- Escape alone and leaves the keyboard alone, which is both narrower than
-- what we were doing and closer to what was meant.
---------------------------------------------------------------------------

-- Both override-binding calls are protected in combat, so a panel shown or
-- hidden mid-fight is remembered and settled when the fight ends.
local escapeButtons  = setmetatable({}, { __mode = "k" })
local escapePending  = setmetatable({}, { __mode = "k" })
local escapeWatcher
local escapeCount    = 0

local function EscapeWatcher()
    if escapeWatcher then return end
    escapeWatcher = CreateFrame("Frame")
    escapeWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    escapeWatcher:SetScript("OnEvent", function()
        for frame, wanted in pairs(escapePending) do
            escapePending[frame] = nil
            if wanted and frame:IsShown() then
                BazUI.BindEscape(frame)
            else
                ClearOverrideBindings(frame)
            end
        end
    end)
end

-- The thing the binding clicks. Parented to UIParent and left shown, not
-- parented to the panel: an override binding clicks a button by name, and a
-- button inside a hidden panel is not there to be clicked. It is a pixel
-- wide, transparent and takes no mouse, so nothing but the binding finds
-- it.
local function EscapeButton(frame, onEscape)
    local btn = escapeButtons[frame]
    if btn then return btn end

    escapeCount = escapeCount + 1
    btn = CreateFrame("Button", "BazUIEscapeCatcher" .. escapeCount, UIParent)
    btn:SetSize(1, 1)
    btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    btn:SetAlpha(0)
    btn:EnableMouse(false)
    btn:SetScript("OnClick", function()
        if onEscape then onEscape(frame) else frame:Hide() end
    end)

    escapeButtons[frame] = btn
    return btn
end

function BazUI.BindEscape(frame)
    local btn = escapeButtons[frame]
    if not btn then return end
    if InCombatLockdown() then
        escapePending[frame] = true
        EscapeWatcher()
        return
    end
    escapePending[frame] = nil
    SetOverrideBindingClick(frame, true, "ESCAPE", btn:GetName())
end

function BazUI.UnbindEscape(frame)
    if InCombatLockdown() then
        escapePending[frame] = false
        EscapeWatcher()
        return
    end
    escapePending[frame] = nil
    ClearOverrideBindings(frame)
end

-- What the Escape system currently holds, for /baz escdebug.
--
-- Escape is an override binding here, and an override binding that is not
-- cleared swallows Escape for the whole game - so when Escape stops
-- working the first question is which of our frames still has it, and
-- whether that frame is even on screen.
function BazUI.EscapeReport()
    local lines = {}

    local bound = GetBindingAction and GetBindingAction("ESCAPE")
    lines[#lines + 1] = ("ESCAPE currently runs: %s"):format(
        (bound and bound ~= "" ) and bound or "nothing bound")

    local n = 0
    for frame, btn in pairs(escapeButtons) do
        n = n + 1
        lines[#lines + 1] = ("  %s  shown %s  pending %s"):format(
            (frame.GetName and frame:GetName()) or tostring(frame),
            tostring(frame:IsShown() and true or false),
            tostring(escapePending[frame]))
        if bound == btn:GetName() then
            lines[#lines] = lines[#lines] .. "   |cffffd700<- this one has Escape|r"
        end
    end
    if n == 0 then lines[#lines + 1] = "  nothing has asked for Escape" end
    lines[#lines + 1] = ("in combat: %s"):format(tostring(InCombatLockdown()))
    return lines
end

function BazUI.CloseOnEscape(frame, onEscape)
    if not (frame and frame.HookScript) then return false end
    if not (SetOverrideBindingClick and ClearOverrideBindings) then return false end

    EscapeButton(frame, onEscape)

    frame:HookScript("OnShow", function(self) BazUI.BindEscape(self) end)
    frame:HookScript("OnHide", function(self) BazUI.UnbindEscape(self) end)

    if frame:IsShown() then BazUI.BindEscape(frame) end
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

-- One hold that several names could satisfy.
--
-- A frame the game renamed between clients is still one thing we are
-- taking hold of, and registering each spelling separately makes the
-- report cry wolf: PartyMemberFrame1 through 4 are absent on any client
-- that pools its party frames, which is normal and not worth a line
-- saying MISSING. Six of thirteen on the first retail run were this, and
-- a report you learn to read past is no report at all.
--
-- So: any one of them counts, and it fails only when none is there, which
-- is the case that actually matters. The label names every spelling
-- tried, so a real failure is still diagnosable.
--
--   names  the spellings, in the order they are worth trying
--   has    what to ask of each. BazUI.Has.Frame by default
function BazUI:RegisterAnyDependency(def)
    if not (def and def.label and def.names and def.names[1]) then return end
    local names = def.names
    local has = def.has or BazUI.Has.Frame
    self:RegisterDependency({
        module = def.module,
        label  = def.label,
        why    = def.why,
        check  = function()
            for _, name in ipairs(names) do
                if has(name) then return true end
            end
            return false
        end,
    })
end

-- Every declared hold, asked now. Returns the list and how many failed,
-- so something other than the slash command could show this later.
function BazUI:CheckDependencies()
    local results, missing = {}, 0

    for _, def in ipairs(dependencies) do
        -- Some holds are only holds when something else is installed.
        -- Zygor's notification centre is four of them, and on a machine
        -- without Zygor they reported MISSING every time - which is not a
        -- fault, it is an addon that is not there. Four red lines nobody
        -- can act on teaches you to read past the colour, which is the
        -- one thing this report must not do.
        --
        -- `when` says whether the question applies at all. A hold that
        -- does not apply is reported as such and counts toward nothing.
        local applies = true
        if def.when then
            local okWhen, wanted = pcall(def.when)
            applies = okWhen and wanted and true or false
        end

        -- A check that errors is a check that failed: whatever it was
        -- reaching for was not there to be reached.
        local present = false
        if applies then
            local ok, found = pcall(def.check)
            present = ok and found and true or false
            if not present then missing = missing + 1 end
        end

        results[#results + 1] = {
            module  = def.module or "BazUI",
            label   = def.label,
            why     = def.why,
            present = present,
            applies = applies,
            note    = def.whenNote,
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
        if not entry.applies then
            print("    |cff888888n/a|r     " .. entry.label
                .. (entry.note and ("  - " .. entry.note) or ""))
        elseif entry.present then
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
