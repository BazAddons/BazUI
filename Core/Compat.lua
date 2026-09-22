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
-- A color is the exception, and it is worth stating plainly.
--
-- There was a helper here for keeping one without reading it: GetClassColor
-- will take a secret class from a tainted caller, so it looked like the way
-- to color a unit whose identity we may not have - pack what comes back
-- without looking, hand it to the bar, let the widget deal with it.
--
-- It cannot. A color whose parts are secret is accepted by every setter
-- without complaint and then drawn BLACK, with no error to notice, so the
-- bars went black instead of colored. Accepting a value and rendering it
-- are not the same thing, and the list above only promises the first.
--
-- Anything that reaches a widget as a color has to be a number we were
-- allowed to read. Where we were not allowed, the honest answer is a color
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

-- Is THIS aura readable - not: are auras readable.
--
-- The difference is the whole of it, and getting it wrong turned every
-- aura row off for the duration of every fight.
--
-- ShouldAurasBeSecret is documented as whether queries "will GENERALLY
-- produce secret values". It is a description of the situation, and in
-- combat the situation is always yes:
--
--   SecretWhenUnitAuraRestricted - Guarded APIs and events produce secret
--   values when combat, encounter, challenge mode, or PvP match addon
--   restrictions are in effect. INDIVIDUAL SPELLS MAY BE FLAGGED AS
--   NEVER OR ALWAYS SECRET, WHICH TAKES PRIORITY OVER RESTRICTIONS.
--
-- That last sentence is the one that matters. Most auras are flagged
-- never-secret and stay perfectly readable through a fight; the general
-- answer says nothing about any of them. This function used to open with
--
--   if not BazUI.Secret.AurasReadable() then return false end
--
-- so the moment a fight started it refused every aura in the game and
-- never reached the per-index question below - the precise question,
-- unreachable in exactly the situation it was written for. Rows froze on
-- whatever they were showing when the fight began, a debuff applied
-- during the fight never appeared at all, and it all came back the
-- instant combat dropped, which made it look like a refresh bug.
--
-- So: the per-index answer decides, and the general one is only the
-- fallback for a client that cannot be asked.
function BazUI.Secret.AuraReadable(unit, index, filter)
    -- A client with no restrictions at all - Classic Era - where every
    -- Should* would answer false anyway.
    if not C_Secrets then return true end
    if C_Secrets.HasSecretRestrictions and not C_Secrets.HasSecretRestrictions() then
        return true
    end

    if C_Secrets.ShouldUnitAuraIndexBeSecret then
        -- Plain arguments in, plain boolean out, so this one really can be
        -- pcall'd: it is a question about a restriction, not a read through
        -- one.
        local ok, secret = pcall(C_Secrets.ShouldUnitAuraIndexBeSecret, unit, index, filter)
        if ok then return not secret end
    end

    -- No per-index answer to be had. The general one is all there is, and
    -- being wrong here means an error the client does not let us catch,
    -- so it is believed.
    return BazUI.Secret.AurasReadable()
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
-- comparing a secret color. /baz taint named the field.
--
-- securecallfunction runs their method as theirs. The frame still hides;
-- nothing it writes on the way down is ours afterwards.
-- Run one of Blizzard's own methods as Blizzard's own code.
--
-- On Forever a method called from us stores its result as OURS, so a
-- Blizzard frame we merely asked a question of is a Blizzard frame
-- carrying our name from then on - and the game refuses the protected
-- work it does on that frame afterwards, blaming us. The blame is
-- literal: "AddOn 'BazUI' tried to call the protected function
-- MainActionBar:SetPointBase()", raised inside Blizzard's own Edit Mode
-- while it anchored a bar we never touched.
--
-- securecallfunction runs it as theirs, so what it stores stays theirs.
-- Anything of Blizzard's that we call goes through here.
--
-- Public because this kept being rewritten: QoL's draggable windows had
-- one, this file had one, and Edit Mode had none and tainted the manager.
function BazUI.SecureCall(object, method, ...)
    if not object then return end
    local fn = object[method]
    if type(fn) ~= "function" then return end
    if securecallfunction then
        return securecallfunction(fn, object, ...)
    end
    return fn(object, ...)
end

-- Hide it the way the widget system hides things, not the way Edit Mode
-- hides things.
--
-- EditModeSystemMixin:SetupVisibilityFunctionOverrides keeps the real
-- methods before it replaces them:
--
--   self.HideBase   = self.Hide;    self.Hide   = self.HideOverride
--   self.ShowBase   = self.Show;    self.Show   = self.ShowOverride
--   self.IsShownBase = self.IsShown
--
-- so a frame of theirs that is an Edit Mode system has both, and the
-- plain one does only what it says. HideOverride does a great deal more:
--
--   HideOverride -> ShouldBreakSnappedFramesOnHide -> BreakSnappedFrames
--                -> ClearAllPointsOverride -> ClearFrameSnap
--                -> snappedToFrame = nil
--
-- and an action bar's own HideOverride goes on into UpdateVisibility and
-- EditModeManagerFrame:UpdateActionBarLayout, which is SetPointBase on a
-- protected frame.
--
-- Every one of those is a write to their bookkeeping, made while we are
-- the ones asking, and securecallfunction did not keep them theirs -
-- /baz taint reported MainActionBar.snappedToFrame as BazUI's after a
-- session of simply having the bar switched off. It is also where the
-- blocked SetPointBase came from.
--
-- None of that machinery is wanted. We want the frame not drawn. HideBase
-- is exactly that and nothing else, and it leaves isShownExternal and the
-- snap state alone - so their books still say what they said, which is
-- the honest outcome: we are hiding a frame, not resigning it from Edit
-- Mode.
local BASE_METHOD = {
    Hide     = "HideBase",
    Show     = "ShowBase",
    SetShown = "SetShownBase",
    IsShown  = "IsShownBase",
}

-- Invisible as well as hidden.
--
-- Belt and braces, and the braces do work the belt cannot:
--
--  * Hiding is refused on a protected frame during combat. Alpha is not
--    protected at all - of the alpha calls only GetEffectiveAlpha carries
--    an access predicate, and we never make it - so a frame we are not
--    allowed to put away we can at least stop drawing. That is the whole
--    of what a mid-fight reload looks like: the game's frames where it
--    left them, and nothing able to move them until the fight ends.
--
--  * Their own code shows these frames for reasons of its own. Picking an
--    ability up off a bar makes the game show its bar to offer you the
--    empty slots, and between their Show and our Hide the frame is on
--    screen for a moment. At alpha zero there is nothing to see.
--
-- The alpha it had is kept rather than assumed to be 1, so handing the
-- frame back gives it back exactly as it was found.
local fadedByUs = setmetatable({}, { __mode = "k" })

local function Conceal(frame)
    if fadedByUs[frame] ~= nil then return end
    local ok, was = pcall(frame.GetAlpha, frame)
    fadedByUs[frame] = (ok and was) or 1
    pcall(BazUI.SecureCall, frame, "SetAlpha", 0)
end

local function Reveal(frame)
    local was = fadedByUs[frame]
    if was == nil then return end
    fadedByUs[frame] = nil
    pcall(BazUI.SecureCall, frame, "SetAlpha", was)
end

local function CallClean(frame, method)
    local base = BASE_METHOD[method]
    if base and type(frame[base]) == "function" then
        return BazUI.SecureCall(frame, base)
    end
    return BazUI.SecureCall(frame, method)
end

-- Open one of Blizzard's own panels from a click of ours.
--
-- ToggleCharacter called plainly runs the character sheet's OnShow as
-- BazUI, and on Forever that OnShow compares the player's health - a
-- secret number, which our execution may not compare. The sheet opened
-- and threw six errors doing it. securecallfunction runs the toggle as
-- theirs, so what it does on the way up is not ours.
function BazUI.OpenCharacterSheet(tab)
    local fn = _G.ToggleCharacter
    if type(fn) ~= "function" then return false end
    if securecallfunction then
        securecallfunction(fn, tab or "PaperDollFrame")
    else
        fn(tab or "PaperDollFrame")
    end
    return true
end

---------------------------------------------------------------------------
-- Forwarding a click to one of Blizzard's own buttons
--
-- Opening one of their panels by calling the toggle ourselves cannot be
-- made clean. securecallfunction runs the toggle as theirs, which helps,
-- but the call reaches the panel manager and goes out through
-- SetAttribute into a secure snippet - and our taint goes with it. The
-- character sheet's OnShow then reads the player's health as BazUI and is
-- refused: "attempt to compare a secret number value (execution tainted
-- by BazUI)". Wrapping the call turned six of those into one; it could
-- not turn one into none.
--
-- The way the game means this to be done is to not make the call. A
-- button inheriting SecureActionButtonTemplate, with type "click" and a
-- clickbutton, has Blizzard's own secure handler carry the click from the
-- keypress - so when their panel opens there is nothing of ours on the
-- stack to taint it.
--
-- This puts such a button over something we already draw. Returns it, or
-- nil when this client cannot do it, so a caller can keep whatever it was
-- doing before rather than losing the click altogether.
---------------------------------------------------------------------------

-- Where to put the overlay, without a region anywhere in the chain.
--
-- A protected frame may not be anchored to a region, and the check walks
-- the chain rather than looking only at what it was handed - so putting
-- an ordinary frame in between and pointing THAT at a texture is refused
-- just the same. A region is therefore not anchored to at all: its own
-- anchors are borrowed instead, which point at a frame or this cannot be
-- done.
local function AnchorPlan(anchorTo)
    if anchorTo.GetFrameLevel then return { frame = anchorTo } end

    local count = anchorTo.GetNumPoints and anchorTo:GetNumPoints() or 0
    if count == 0 then return nil end
    local points = {}
    for i = 1, count do
        local point, rel, relPoint, x, y = anchorTo:GetPoint(i)
        rel = rel or anchorTo:GetParent()
        if not (rel and rel.GetFrameLevel) then return nil end
        points[#points + 1] = { point, rel, relPoint, x or 0, y or 0 }
    end
    local w, h = anchorTo:GetSize()
    return { points = points, w = w, h = h }
end

-- anchorTo   frame or region the overlay should cover
-- target     one of Blizzard's buttons, or its global name
-- opts       parent, levelBump, clicks (table), relayMotion (frame whose
--            OnEnter/OnLeave should still fire under the overlay)
function BazUI.SecureForward(anchorTo, target, opts)
    opts = opts or {}
    if type(target) == "string" then target = _G[target] end
    if not (anchorTo and target and target.GetFrameLevel) then return nil end
    if not (BazUI.Has and BazUI.Has.Template("SecureActionButtonTemplate")) then
        return nil
    end

    local plan = AnchorPlan(anchorTo)
    if not plan then return nil end

    local parent = opts.parent
        or (anchorTo.GetFrameLevel and anchorTo)
        or anchorTo:GetParent()
    if not parent then return nil end

    local hit = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    hit:SetFrameLevel((parent:GetFrameLevel() or 1) + (opts.levelBump or 1))
    hit:RegisterForClicks(unpack(opts.clicks or { "LeftButtonUp" }))

    -- Anchoring and attributes are both refused in combat, and the thing
    -- being covered may well be built during one. Done when we can, and
    -- again when the fight ends if we could not.
    local function Wire()
        if InCombatLockdown() then return false end
        hit:ClearAllPoints()
        if plan.frame then
            hit:SetAllPoints(plan.frame)
        else
            if (plan.w or 0) > 0 and (plan.h or 0) > 0 then hit:SetSize(plan.w, plan.h) end
            for _, pt in ipairs(plan.points) do
                hit:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
            end
        end
        hit:SetAttribute("type", "click")
        hit:SetAttribute("clickbutton", target)
        return true
    end

    if not Wire() then
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        waiter:SetScript("OnEvent", function(self)
            if Wire() then self:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        end)
    end

    -- An overlay takes the mouse, and with it whatever the thing
    -- underneath was doing on hover: a bar that changes what it says
    -- under the cursor would simply stop.
    local under = opts.relayMotion
    if under then
        hit:SetScript("OnEnter", function()
            local fn = under:GetScript("OnEnter")
            if fn then fn(under) end
        end)
        hit:SetScript("OnLeave", function()
            local fn = under:GetScript("OnLeave")
            if fn then fn(under) end
        end)
    end

    return hit
end

-- Frames we were refused mid-fight, and the one watcher that settles
-- them. Weak keys: a frame nobody else is holding is not worth keeping
-- alive to hide it.
local suppressPending = setmetatable({}, { __mode = "k" })
local suppressWatcher

local function Settle(frame)
    local wanted = suppressWanted[frame]
    if not wanted then return end

    if wanted() then
        Conceal(frame)
        suppressedByUs[frame] = true
        CallClean(frame, "Hide")
    else
        -- Only ever put back what we took down. Calling Show on a frame
        -- we do not own marks its shown state as ours, and Blizzard's
        -- Edit Mode reads that state on the way in; anything we never
        -- hid is left entirely alone.
        if suppressedByUs[frame] then
            suppressedByUs[frame] = nil
            CallClean(frame, "Show")
        end
        -- Outside that test, because a frame can be faded without having
        -- been hidden - which is exactly what happens when we are refused
        -- the hide mid-fight - and it still has to be handed back.
        Reveal(frame)
    end
end

local function SuppressWatcher()
    if suppressWatcher then return end
    suppressWatcher = CreateFrame("Frame")
    suppressWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    suppressWatcher:SetScript("OnEvent", function()
        local waiting = suppressPending
        suppressPending = setmetatable({}, { __mode = "k" })
        for frame in pairs(waiting) do pcall(Settle, frame) end
    end)
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
            if not (test and test() and not Blocked(self)) then return end

            -- Straight away, in their OnShow, not a frame later.
            --
            -- It was a frame later for a while, and the reason was real:
            -- OnShow fires in the MIDDLE of whatever is showing the frame,
            -- and on an action bar that is
            --
            --   EditModeActionBarMixin:ShowOverride()
            --       self.isShownExternal = true
            --       self:UpdateVisibility()  -- ShowBase is in here, and
            --   end                          -- so is UpdateActionBarLayout
            --
            -- so hiding from inside it meant our Hide ran while their Show
            -- was half done. That was fatal when Hide meant HideOverride,
            -- which runs BreakSnappedFrames and lands on SetPointBase - a
            -- protected call, refused, leaving the bar up until a reload.
            --
            -- CallClean uses HideBase now. There is no BreakSnappedFrames
            -- and no SetPointBase anywhere in that path - it is the plain
            -- widget hide, safe to make from anywhere we are allowed to
            -- hide the frame at all, and Blocked already answers that. So
            -- the delay bought nothing and cost a visible flicker: drag an
            -- ability, the game shows its own bar to offer the empty
            -- slots, and the bar was on screen for a frame before going
            -- back down.
            Conceal(self)
            suppressedByUs[self] = true
            CallClean(self, "Hide")
        end)
    end
    suppressWanted[frame] = wanted

    if Blocked(frame) then
        -- Parked, not dropped.
        --
        -- This used to return here and say no more about it, while the
        -- note above promised the frame would be "picked up when the fight
        -- ends". Nothing picked it up. Reload during a fight and
        -- Blizzard's action bars were never hidden at all - they simply
        -- turned up when the fight finished, looking like something we had
        -- just decided to show.
        --
        -- The OnShow hook above is not enough on its own: it only fires if
        -- the frame is shown AFTER we hooked it, and a frame that was
        -- already up when we were refused never shows again.
        -- Cannot hide it. Can stop it being drawn, which is most of what
        -- hiding it was for.
        Conceal(frame)
        suppressPending[frame] = true
        SuppressWatcher()
        return true
    end

    Settle(frame)
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
        -- Zygor's notification center is four of them, and on a machine
        -- without Zygor they reported MISSING every time - which is not a
        -- fault, it is an addon that is not there. Four red lines nobody
        -- can act on teaches you to read past the color, which is the
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
