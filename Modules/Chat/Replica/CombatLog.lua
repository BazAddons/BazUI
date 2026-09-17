-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: Combat Log
--
-- Hijacks Blizzard's combat log so its formatted output (every parsed
-- COMBAT_LOG_EVENT_UNFILTERED line, with source/dest/spell/amount
-- coloring per the user's filter settings) lands on BazChat's Log tab
-- instead of the hidden ChatFrame2.
--
-- Mechanism: `_G.COMBATLOG` is a global Blizzard sets to ChatFrame2 in
-- Blizzard_CombatLog/Mainline/Blizzard_CombatLog.lua. Their
-- CombatLogDriverMixin:OnCombatLogMessage / OnCombatLogRefilterStarted
-- / OnCombatLogMessageLimitChanged / OnCombatLogEntriesCleared all
-- call methods on `COMBATLOG` (AddMessage / BackFillMessage / Clear /
-- SetMaxLines). We just rebind the global to our Log frame after their
-- addon loads. Our SMF supports every method they call.
--
-- The combat-log filter UI (the "Additional Filters" dropdown +
-- refilter progress bar) lives in CombatLogQuickButtonFrame_Custom,
-- parented to ChatFrame2 in their XML. We reparent it onto our Log
-- frame's top-right so the user can still configure filters.
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

local CombatLog = {}
addon.CombatLog = CombatLog

---------------------------------------------------------------------------
-- Calling into Blizzard's combat log without tainting it
--
-- Taint follows the call, and it does not wash off. Blizzard_CombatLog
-- applies its filters while it loads, which starts the processor's
-- refilter ticker - and that ticker calls C_CombatLogSecure, a namespace
-- the client marks SecureOnly. A tainted caller gets nothing back from
-- it, and their own code takes the answer straight to math.min, whose
-- documented return is not nilable. So loading their addon from our code
-- gave 300 errors a session in a file we never touch.
--
-- securecallfunction is the way in: the callee runs without our taint, so
-- the load, the filter it applies and the ticker it starts are all clean.
-- Falls back to pcall where the client has no such thing, which keeps the
-- old behaviour rather than inventing a new one.
---------------------------------------------------------------------------

local function SecureCall(fn, ...)
    if type(fn) ~= "function" then return end
    if securecallfunction then
        -- Still inside a pcall: this used to be one, and losing the guard
        -- would turn a fault in their code into a fault in ours.
        return pcall(securecallfunction, fn, ...)
    end
    return pcall(fn, ...)
end

-- The Log tab is window index 4 (DEFAULTS.windows[4] in Core/Init.lua,
-- eventGroup = "LOG"). Resolved lazily so the rebind survives any
-- future renumbering.
local function GetLogFrame()
    if not addon.Window or not addon.Window.Get then return nil end
    -- Find the window whose canonical group is LOG. Fall back to
    -- index 4 if the lookup helper isn't available.
    if addon.Window.GetByGroup then
        local f = addon.Window:GetByGroup("LOG")
        if f then return f end
    end
    return addon.Window:Get(4)
end

-- Height we reserve at the top of the Log frame for the QuickButton
-- strip. Blizzard's bar is 24 px; +2 padding so chat lines don't crowd
-- the bottom edge of the buttons.
local QUICKBUTTON_HEIGHT = 26

-- Mirror Chrome.lua's local INSET_* constants. We need them so we can
-- re-anchor the Log frame's chrome to the DOCK (full-size) instead of
-- the SMF (which shrinks when we inset the chat content). Keep these
-- in sync with Chrome.lua's locals; if those change, update here too.
local CHROME_INSET_LEFT   = 10
local CHROME_INSET_RIGHT  = 26
local CHROME_INSET_TOP    = 11
local CHROME_INSET_BOTTOM = 29

-- The chrome panel (NineSlice backdrop + corners + scrollbar zone) is
-- normally anchored to the SMF's corners with INSET_* offsets. Once we
-- shrink the SMF top by QUICKBUTTON_HEIGHT, the chrome follows and
-- visually shrinks too - the Log tab's window appears 26 px shorter
-- than the other tabs' windows. Re-anchoring the chrome to the dock
-- (which has the same intended size as a full-height SMF would) keeps
-- the visible chat-box dimensions identical across tabs while leaving
-- the chat-text rendering area inset to make room for the QuickButton
-- bar.
local function ReanchorChromeToDock(targetFrame, dock)
    local chrome = targetFrame._bcChromeFrame
    if not chrome or not dock then return end
    chrome:ClearAllPoints()
    chrome:SetPoint("TOPLEFT",     dock, "TOPLEFT",
        -CHROME_INSET_LEFT,  CHROME_INSET_TOP)
    chrome:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT",
         CHROME_INSET_RIGHT, -CHROME_INSET_BOTTOM)
end

-- Push the Log frame's top edge down by QUICKBUTTON_HEIGHT so there's
-- room for the QuickButton strip above the chat content. The frame is
-- normally SetAllPoints(addon.Window.dock); we override with a
-- four-point anchor that offsets the top against THAT same dock (NOT
-- the frame's UIParent parent - anchoring to UIParent makes the Log
-- window cover the whole screen).
local function InsetLogFrameTop(targetFrame)
    if targetFrame._bcLogFrameInsetApplied then return end
    local dock = addon.Window and addon.Window.dock
    if not dock then return end
    targetFrame:ClearAllPoints()
    targetFrame:SetPoint("TOPLEFT",     dock, "TOPLEFT",     0, -QUICKBUTTON_HEIGHT)
    targetFrame:SetPoint("TOPRIGHT",    dock, "TOPRIGHT",    0, -QUICKBUTTON_HEIGHT)
    targetFrame:SetPoint("BOTTOMLEFT",  dock, "BOTTOMLEFT",  0, 0)
    targetFrame:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 0, 0)
    targetFrame._bcLogFrameInsetApplied = true
end

-- Reanchor the quick-button bar to fill the inset we just carved out
-- at the top of our Log frame. The bar's children (preset buttons +
-- additional-filters dropdown + progress bar) lay out automatically
-- via Blizzard_CombatLog_Update_QuickButtons - we just give them a
-- container that's the right size and parented to our frame.
local function ReparentQuickButtonFrame(targetFrame)
    local qbf = _G.CombatLogQuickButtonFrame_Custom
        or _G.CombatLogQuickButtonFrame
    if not qbf or not targetFrame then return end
    qbf:SetParent(targetFrame)
    qbf:ClearAllPoints()
    qbf:SetPoint("BOTTOMLEFT",  targetFrame, "TOPLEFT",  0, 0)
    qbf:SetPoint("BOTTOMRIGHT", targetFrame, "TOPRIGHT", 0, 0)
    qbf:SetHeight(QUICKBUTTON_HEIGHT)
    qbf:SetFrameStrata(targetFrame:GetFrameStrata() or "MEDIUM")
    qbf:SetFrameLevel((targetFrame:GetFrameLevel() or 5) + 5)
    qbf:Show()
end

local function ApplyRedirect()
    local target = GetLogFrame()
    if not target then return false end

    if _G.COMBATLOG ~= target then
        _G.COMBATLOG = target
    end

    InsetLogFrameTop(target)
    if addon.Window and addon.Window.dock then
        ReanchorChromeToDock(target, addon.Window.dock)
    end
    ReparentQuickButtonFrame(target)

    -- Reapply the inset whenever the frame is resized. Edit Mode's
    -- resize handler and BazChat's own re-SetAllPoints in tab-switch
    -- paths clobber our four-point anchor; without the rehook the bar
    -- starts overlapping the tabs again as soon as the user drags
    -- the resize handle. Idempotent via the _bcLogFrameInsetApplied
    -- flag reset.
    if not target._bcLogFrameInsetHooked then
        target._bcLogFrameInsetHooked = true
        target:HookScript("OnSizeChanged", function(self)
            self._bcLogFrameInsetApplied = nil
            InsetLogFrameTop(self)
            if addon.Window and addon.Window.dock then
                ReanchorChromeToDock(self, addon.Window.dock)
            end
        end)
    end

    -- Stub buttonFrame so Blizzard's FCF_SetButtonSide call from
    -- Edit Mode (FloatingChatFrame.lua:1344) doesn't error on our
    -- replica frame. The replica window is built from a custom
    -- template that has no buttonFrame, but Edit Mode iterates every
    -- registered chat frame and calls ClearAllPoints / SetPoint on
    -- their buttonFrame. Giving it a hidden dummy frame turns the
    -- call into a harmless no-op.
    if not target.buttonFrame then
        local stub = CreateFrame("Frame", nil, target)
        stub:Hide()
        stub:SetSize(1, 1)
        target.buttonFrame = stub
    end

    -- Repopulate the preset filter buttons (My actions / What happened
    -- to me? + any user-defined filters) now that COMBATLOG points at
    -- our frame - the layout reads COMBATLOG width to decide which
    -- buttons fit on the strip. Safe to call any time after the
    -- combat-log addon's OnLoad has run.
    SecureCall(_G.Blizzard_CombatLog_Update_QuickButtons)

    -- Sync the message limit Blizzard's driver tracks with our Log
    -- frame's actual SetMaxLines value so OnCombatLogMessageLimitChanged
    -- doesn't shrink our buffer. Default 500 from Core/Init.lua.
    if target.GetMaxLines and target.SetMaxLines then
        target:SetMaxLines(target:GetMaxLines() or 500)
    end

    return true
end

---------------------------------------------------------------------------
-- Public: Apply()
--
-- Called from Replica:Start AFTER Window:CreateAll. If
-- Blizzard_CombatLog hasn't loaded yet (it's a load-on-demand addon
-- bundled into the game UI), defer until ADDON_LOADED fires for it.
---------------------------------------------------------------------------

function CombatLog:Apply()
    -- Off by default, and this is the whole reason why.
    --
    -- Blizzard_CombatLog is LoadOnDemand and nothing in the game's own
    -- UI loads it, so the only way their formatted output reaches the
    -- Log tab is if we ask for it. Their ADDON_LOADED handler then calls
    -- C_CombatLog.RefilterEntries() unconditionally, and on the Forever
    -- beta the refilter ticker errors every tick: it asks
    -- C_CombatLogSecure.GetEntryCount(), gets nil, and hands that to
    -- math.min. Hundreds of errors a session, in their file, on a
    -- function in a secure environment we cannot reach or patch.
    --
    -- Not tested by client version: the switch is the user's, and any
    -- client where it behaves can have it on. If it is off we simply
    -- never load their addon, and the Log tab keeps whatever BazUI
    -- itself puts there.
    local core = addon.core
    if not (core and core.GetSetting
        and core:GetSetting("loadBlizzardCombatLog")) then return end

    if C_AddOns and C_AddOns.LoadAddOn then
        SecureCall(C_AddOns.LoadAddOn, "Blizzard_CombatLog")
    end

    if ApplyRedirect() then return end

    -- Couldn't apply yet (Log frame missing or Blizzard combat log
    -- not loaded). Wait for the addon to finish loading then retry.
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", function(self, event, name)
        if event == "ADDON_LOADED" and name ~= "Blizzard_CombatLog" then
            return
        end
        if ApplyRedirect() then
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
        end
    end)
end
