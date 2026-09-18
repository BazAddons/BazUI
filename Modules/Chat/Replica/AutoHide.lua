-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: AutoHide (scrollbar + tab-strip fade)
--
-- Tri-state visibility for the scrollbar and the tab strip:
--   "always"   - fully visible at all times (default)
--   "onscroll" - scrollbar fades in on wheel events or chat hover, holds
--                ~2s, fades out unless still hovering
--   "onhover"  - tab strip fades in on chat hover or any tab/+ hover,
--                holds ~2s, fades out unless still hovering
--   "never"    - hidden entirely (mouse wheel still scrolls)
--
-- Edit Mode forces both visible regardless of mode so the user can see
-- what they're configuring.
--
-- IMPLEMENTATION NOTE: do NOT HookScript on the SMF (`f`) directly. v143
-- through v149 did that and broke window creation in subtle ways (lost
-- the General tab, broke editbox-on-Enter, ResizeButton stuck visible).
-- The SMF has no default OnEnter handler and adding a hook to it
-- interacts poorly with later setup. clickAnywhereButton is a
-- setAllPoints child of the SMF and covers the entire chat rect, so
-- hooking IT gives identical hover detection without touching the SMF's
-- script table.
--
-- Public API (on addon.AutoHide):
--   :WireWindow(f)      -- per-window setup; call from Window:Create
--   :WireTab(tab)       -- call from Tabs.lua when a tab/addBtn is created
--   :Apply(f, inEdit)   -- call from Window:ApplySettings
--   :PingScroll(f)      -- call from the mouse-wheel handler
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

local AutoHide = {}
addon.AutoHide = AutoHide

local FADE_IN  = 0.15
local FADE_OUT = 0.50
local HOLD     = 2.00

---------------------------------------------------------------------------
-- DB readers
--
-- BazUI's onReady (which sets addon.db) fires AFTER QueueForLogin
-- callbacks, so during Window:CreateAll → ApplySettings at boot,
-- addon.db is still nil while addon.core.db is already populated.
-- Both paths checked so saved modes apply correctly on /reload.
---------------------------------------------------------------------------

local function GetChrome()
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    return p and p.windows and p.windows[1] or nil
end

local function ScrollBarMode()
    local chrome = GetChrome()
    -- Matches the module defaults, so a window that has never been given
    -- a value behaves the same as one that has.
    return (chrome and chrome.scrollbarMode) or "onscroll"
end

-- chromeFadeMode == "off"  -> bgMode/tabsMode are independent (read as-is)
-- chromeFadeMode != "off"  -> both are forced to chromeFadeMode's value
local function UnifiedMode()
    local chrome = GetChrome()
    local m = chrome and chrome.chromeFadeMode
    if m and m ~= "off" then return m end
    return nil
end

local function TabsMode()
    local unified = UnifiedMode()
    if unified then return unified end
    local chrome = GetChrome()
    return (chrome and chrome.tabsMode) or "onhover"
end

-- "Fully visible" alpha for the tab strip. User-controlled via the
-- Tabs Opacity slider. Onhover fades from 0 -> this value; always-mode
-- pins to this value. Default 1.0 (fully opaque).
local function TabsAlpha()
    local chrome = GetChrome()
    local v = chrome and chrome.tabsAlpha
    if type(v) ~= "number" then return 1 end
    return v
end

local function BgMode()
    local unified = UnifiedMode()
    if unified then return unified end
    local chrome = GetChrome()
    return (chrome and chrome.bgMode) or "onhover"
end

-- "Fully visible" alpha for the chrome panel. User-controlled via
-- Background Opacity slider. Onhover fades from 0 -> this value;
-- always-mode pins to this value.
local function BgAlpha()
    local chrome = GetChrome()
    local v = chrome and chrome.bgAlpha
    if type(v) ~= "number" then return 1 end
    return v
end

local function InEditMode()
    return addon.Window and addon.Window.dock and addon.Window.dock._inEditMode
end

---------------------------------------------------------------------------
-- Generic ping: fade in (if not already), restart hold timer, fade out
-- when timer fires (unless still hovering).
---------------------------------------------------------------------------

local function Ping(frame, targetAlpha)
    targetAlpha = targetAlpha or 1
    if not frame or not frame:IsShown() then return end
    if frame._bcFadeTimer then
        frame._bcFadeTimer:Cancel()
        frame._bcFadeTimer = nil
    end
    if frame:GetAlpha() < targetAlpha then
        UIFrameFadeIn(frame, FADE_IN, frame:GetAlpha(), targetAlpha)
    end
    frame._bcFadeTimer = C_Timer.NewTimer(HOLD, function()
        if frame._bcMouseOver then return end
        UIFrameFadeOut(frame, FADE_OUT, frame:GetAlpha(), 0)
        frame._bcFadeTimer = nil
    end)
end

local function PingScrollBar(f)
    if ScrollBarMode() ~= "onscroll" or InEditMode() then return end
    if f and f.ScrollBar then Ping(f.ScrollBar, 1) end
end

local function PingTabSystem()
    if TabsMode() ~= "onhover" or InEditMode() then return end
    local ts = addon.Tabs and addon.Tabs.system
    if ts then Ping(ts, TabsAlpha()) end
end

local function PingBg(f)
    if BgMode() ~= "onhover" or InEditMode() then return end
    if f and f._bcChromeFrame then
        Ping(f._bcChromeFrame, BgAlpha())
    end
end

---------------------------------------------------------------------------
-- :PingScroll — public mouse-wheel hook (called from HookMouseWheel)
---------------------------------------------------------------------------

function AutoHide:PingScroll(f)
    PingScrollBar(f)
end

---------------------------------------------------------------------------
-- :WireWindow — per-window hover hooks for scrollbar + tab strip
--
-- Hooks ONLY clickAnywhereButton (chat-rect hover) and the ScrollBar
-- itself. Never the SMF. Both targets have well-defined script tables
-- and HookScript composes safely with their existing handlers.
---------------------------------------------------------------------------

function AutoHide:WireWindow(f)
    if not f or f._bcAutoHideWired then return end
    f._bcAutoHideWired = true

    -- Chat-area hover: pings the scrollbar, the tab strip, AND the
    -- background chrome. Hovering the chat means the user is reading
    -- and might want any of those controls visible.
    -- Hover detection via IsMouseOver() polling. Confirmed working in
    -- v169. Tried OnEnter/OnLeave on clickAnywhereButton (HookScript
    -- and SetScript, with explicit SetMouseMotionEnabled) and neither
    -- fired reliably in modern retail. Polling is the bulletproof
    -- fallback - it's a geometric cursor-vs-rect check that doesn't
    -- depend on any mouse-event registration. Throttled to 10 Hz so
    -- the cost is ~40 ticks/sec total (4 windows × 10 Hz), each tick
    -- a single rect check + bool compare. Negligible CPU/memory.
    if not f._bcHoverTicker then
        f._bcHoverTicker = C_Timer.NewTicker(0.1, function()
            if not f or not f:IsShown() then return end
            -- Popped windows manage their own visibility - they should
            -- always show their chrome (the user explicitly detached
            -- them). Skip the auto-hide fade logic and pin chrome
            -- alpha to the user-configured bgAlpha so popped windows
            -- inherit the same appearance as the dock. _dockID is set
            -- by Window:Create / MoveTabToDock; "dock" or nil means
            -- the chat is in the main dock.
            if f._dockID and f._dockID ~= "dock" then
                local target = BgAlpha and BgAlpha() or 1
                if f._bcChromeFrame and math.abs((f._bcChromeFrame:GetAlpha() or 0) - target) > 0.01 then
                    f._bcChromeFrame:SetAlpha(target)
                end
                if f.ScrollBar and (f.ScrollBar:GetAlpha() or 0) < 1 then
                    f.ScrollBar:SetAlpha(1)
                end
                return
            end
            -- The chat assembly is the chat frame PLUS the tab strip.
            -- Treat hovering either as "over the chat" so a tab click /
            -- tab hover doesn't trip the fade-out timer on tab switch.
            -- Without the tab-strip OR, switching tabs immediately
            -- registered isOver=false on the new active window (cursor
            -- is over the tabs, not the chat content), the HOLD timer
            -- fired, the bg faded out for ~2s, and only re-faded in
            -- when the cursor finally crossed into the chat itself.
            local ts = addon.Tabs and addon.Tabs.system
            local overTabs = ts and ts.IsMouseOver and ts:IsMouseOver()
            local isOver = f:IsMouseOver() or overTabs or false
            if isOver == f._bcChatHovering then return end
            f._bcChatHovering = isOver

            if f.ScrollBar       then f.ScrollBar._bcMouseOver       = isOver end
            if f._bcChromeFrame  then f._bcChromeFrame._bcMouseOver  = isOver end
            if ts then ts._bcMouseOver = isOver end
            PingScrollBar(f)
            PingBg(f)
            PingTabSystem()
        end)
    end

    -- Scrollbar self-hover: keeps just the scrollbar visible.
    if f.ScrollBar then
        f.ScrollBar:HookScript("OnEnter", function(sb)
            sb._bcMouseOver = true
            PingScrollBar(f)
        end)
        f.ScrollBar:HookScript("OnLeave", function(sb)
            sb._bcMouseOver = false
            PingScrollBar(f)
        end)
    end
end

---------------------------------------------------------------------------
-- :WireTab — hover hook for a tab (or the "+" button)
--
-- Tab buttons inherit TabSystemTopButtonTemplate which has OnEnter
-- scripts baked in; the + button has explicit SetScript("OnEnter").
-- Both are safe targets for HookScript.
---------------------------------------------------------------------------

-- Find whichever chat window is currently shown. Tabs are shared
-- across windows, so when a tab is hovered we need to know which
-- window's background to ping (only the active one's chrome is
-- visible; inactive ones are :Hide()'d).
local function ActiveWindow()
    if not addon.Window or not addon.Window.list then return nil end
    for _, f in pairs(addon.Window.list) do
        if f and f:IsShown() then return f end
    end
    return nil
end

function AutoHide:WireTab(tab)
    if not tab or tab._bcAutoHideTabHooked then return end
    tab._bcAutoHideTabHooked = true
    tab:HookScript("OnEnter", function()
        local ts = addon.Tabs and addon.Tabs.system
        if ts then ts._bcMouseOver = true end
        -- Bridge to bg state: tabs sit OUTSIDE f's rect (anchored
        -- above f's TOP), so the chat poller sees "not in chat" while
        -- the cursor is on a tab. Without this bridge, bg would start
        -- its fade-out timer the moment the cursor moves up to a tab,
        -- and it'd finish fading before the tabs do (visible desync
        -- in unified Sync mode). Treat the tab strip as part of the
        -- chat assembly for hover purposes.
        local f = ActiveWindow()
        if f and f._bcChromeFrame then
            f._bcChromeFrame._bcMouseOver = true
        end
        PingTabSystem()
        if f then PingBg(f) end
    end)
    tab:HookScript("OnLeave", function()
        local ts = addon.Tabs and addon.Tabs.system
        if ts then ts._bcMouseOver = false end
        local f = ActiveWindow()
        if f and f._bcChromeFrame then
            f._bcChromeFrame._bcMouseOver = false
        end
        PingTabSystem()
        if f then PingBg(f) end
    end)
end

---------------------------------------------------------------------------
-- :Apply — apply visibility/alpha for both scrollbar and tab strip
--
-- Called from Window:ApplySettings. Per-window for the scrollbar; the
-- tab strip is shared so we re-apply it on every call (idempotent and
-- cheap). inEditMode forces both visible regardless of mode.
---------------------------------------------------------------------------

local function PinShown(frame, alpha)
    if frame._bcFadeTimer then
        frame._bcFadeTimer:Cancel()
        frame._bcFadeTimer = nil
    end
    frame:SetAlpha(alpha or 1)
end

---------------------------------------------------------------------------
-- :SyncWindow — instant chrome+scrollbar alpha sync (no animation).
--
-- Used by the tab-switch callback in Tabs.lua. When the user clicks a
-- tab, the newly-activated window's chrome had its alpha last set when
-- it was previously hidden (possibly to 0 in onhover mode). Showing it
-- with alpha 0 then waiting for the per-window hover-poller to ping
-- causes a visible "flash" - the chrome appears blank for ~100ms then
-- fades in over 0.15s.
--
-- This helper queries cursor position right now and pins chrome/sb
-- alpha to the correct target value immediately, no UIFrameFadeIn,
-- no timer. Animations are for state transitions; tab activation is
-- a state TELEPORT, so we skip the fade.
---------------------------------------------------------------------------

function AutoHide:SyncWindow(f)
    if not f then return end
    -- Treat the tab strip as part of the chat assembly for hover
    -- purposes - same OR the polling ticker uses. Without this a
    -- tab click reads "not hovering" because the cursor is over the
    -- tabs (not the chat content), and SyncWindow snaps the chrome's
    -- alpha to 0 immediately. The ticker then re-pings it back in
    -- 100ms later, producing the visible flash/fade-in the user sees
    -- on every tab switch.
    local hovering = (f.IsMouseOver and f:IsMouseOver()) or false
    local ts = addon.Tabs and addon.Tabs.system
    if not hovering and ts and ts.IsMouseOver and ts:IsMouseOver() then
        hovering = true
    end
    local inEdit   = InEditMode()

    -- Background chrome
    if f._bcChromeFrame then
        f._bcChromeFrame._bcMouseOver = hovering
        if f._bcChromeFrame._bcFadeTimer then
            f._bcChromeFrame._bcFadeTimer:Cancel()
            f._bcChromeFrame._bcFadeTimer = nil
        end
        local mode = BgMode()
        if mode == "never" and not inEdit then
            f._bcChromeFrame:SetAlpha(0)
        elseif mode == "always" or inEdit or hovering then
            f._bcChromeFrame:SetAlpha(BgAlpha())
        else  -- onhover, not hovering
            f._bcChromeFrame:SetAlpha(0)
        end
    end

    -- Scrollbar
    if f.ScrollBar then
        f.ScrollBar._bcMouseOver = hovering
        if f.ScrollBar._bcFadeTimer then
            f.ScrollBar._bcFadeTimer:Cancel()
            f.ScrollBar._bcFadeTimer = nil
        end
        local mode = ScrollBarMode()
        if mode == "never" and not inEdit then
            f.ScrollBar:SetShown(false)
        else
            f.ScrollBar:SetShown(true)
            if mode == "always" or inEdit or hovering then
                f.ScrollBar:SetAlpha(1)
            else  -- onscroll, not hovering
                f.ScrollBar:SetAlpha(0)
            end
        end
    end
end

function AutoHide:Apply(f, inEditMode)
    -- Per-window: scrollbar
    if f and f.ScrollBar then
        local mode = ScrollBarMode()
        if mode == "never" and not inEditMode then
            f.ScrollBar:SetShown(false)
        else
            f.ScrollBar:SetShown(true)
            if mode == "always" or inEditMode then
                PinShown(f.ScrollBar, 1)
            elseif not f.ScrollBar._bcMouseOver then  -- onscroll, idle
                f.ScrollBar:SetAlpha(0)
            end
        end
    end

    -- Per-window: the background chrome panel. bgAlpha is the
    -- visible-state opacity; onhover fades 0 -> bgAlpha; "never" pins
    -- to 0 so the chat text floats with no panel behind it. We use
    -- alpha (not Hide()) for "never" because Chrome.lua's OnShow hook
    -- on the chat would re-Show the chrome on tab switches.
    if f and f._bcChromeFrame then
        local mode = BgMode()
        if mode == "always" or inEditMode then
            PinShown(f._bcChromeFrame, BgAlpha())
        elseif mode == "never" then
            if f._bcChromeFrame._bcFadeTimer then
                f._bcChromeFrame._bcFadeTimer:Cancel()
                f._bcChromeFrame._bcFadeTimer = nil
            end
            f._bcChromeFrame:SetAlpha(0)
        elseif not f._bcChromeFrame._bcMouseOver then  -- onhover, idle
            f._bcChromeFrame:SetAlpha(0)
        end
    end

    -- Shared: tab strip. tabsAlpha is the user-chosen visible-state
    -- opacity (slider in Edit Mode + Settings); always/Edit-Mode pin
    -- to it, onhover fades from 0 -> tabsAlpha.
    local ts = addon.Tabs and addon.Tabs.system
    if ts then
        local mode = TabsMode()
        if mode == "never" and not inEditMode then
            ts:Hide()
        else
            ts:Show()
            if mode == "always" or inEditMode then
                PinShown(ts, TabsAlpha())
            elseif not ts._bcMouseOver then  -- onhover, idle
                ts:SetAlpha(0)
            end
        end
    end
end
