-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Tooltip
--
-- A docked slot whose only job is to be the anchor for the global
-- GameTooltip. Hooks `GameTooltip_SetDefaultAnchor` to reroute every
-- default-anchored tooltip into this widget's frame, so item / unit /
-- spell hover tooltips appear inside the drawer instead of floating
-- at the cursor or screen edge.
--
-- Defaults to bottom-of-drawer docking (the natural place for a
-- tooltip - stacks upward as content grows). Per-widget toggle to
-- pause the anchor override without removing the widget.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID     = "bazdrawer_tooltip"
local DESIGN_WIDTH  = 280
local DESIGN_HEIGHT = 60   -- minimum slot footprint when no tooltip is up

local Tooltip = {}
addon.TooltipWidget = Tooltip

local frame              -- the widget's own frame (sits in the drawer slot)
local hookInstalled      = false
local lastTooltipHeight  = DESIGN_HEIGHT  -- last GameTooltip height we saw

---------------------------------------------------------------------------
-- Frame builder
---------------------------------------------------------------------------

function Tooltip:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", "BazUIDrawerTooltipDock", UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)
    -- Slot is intentionally empty when no tooltip is showing - any
    -- placeholder text would just be visual noise and would still be
    -- visible when the user has the widget docked but inactive.

    -- When the drawer collapses, displayFrame:Hide() cascades through
    -- its descendants and our slot becomes invisible. The GameTooltip
    -- itself, however, lives under UIParent - anchoring it to a now-
    -- invisible frame doesn't move it off-screen, so without this
    -- hook the tooltip would hover at its last position even after
    -- the drawer slid shut. OnHide fires when our visibility chain
    -- breaks; if the live tooltip is still anchored to us at that
    -- moment, dismiss it. The user's next hover after re-opening
    -- the drawer will re-anchor naturally via SetDefaultAnchor.
    f:HookScript("OnHide", function()
        if GameTooltip and GameTooltip:IsShown() then
            local _, anchor = GameTooltip:GetPoint(1)
            if anchor == f then
                GameTooltip:Hide()
            end
        end
    end)

    frame = f
    return f
end

---------------------------------------------------------------------------
-- Anchor hook
--
-- GameTooltip_SetDefaultAnchor is what most of Blizzard's hover code
-- calls when an item/unit/etc. tooltip needs a default position. By
-- hook-overriding the anchor inside that function we capture the
-- common cases (bag, action bar, unit frame, quest log, etc.). Some
-- addons that hardcode `GameTooltip:SetOwner(self, "ANCHOR_RIGHT")`
-- bypass this - those keep their own anchor, which is fine.
---------------------------------------------------------------------------

-- Floor for the dynamic scale - below this and the tooltip text gets
-- hard to read at any reasonable drawer width.
local MIN_SCALE   = 0.5
local SCALE_STEP  = 0.05  -- snap-to-grid: small width fluctuations don't cross a step
local SCALE_HYST  = 0.025 -- ignore scale changes smaller than half a step
local HEIGHT_HYST = 4     -- ignore slot-height changes under 4 design-px
local SETTLE_MS   = 80    -- coalesce reflows within this window into one

-- Compute the tooltip scale that makes its rendered pixel width match
-- the slot's rendered pixel width, snapped to SCALE_STEP increments to
-- damp flutter from async content-width fluctuations. Returns nil if
-- either width hasn't resolved yet.
local function ComputeFitScale(tooltip)
    if not frame then return nil end

    -- GameTooltip:GetWidth() returns a Midnight 12.0 "secret number"
    -- once item-tooltip data has been processed (the item-link
    -- pipeline taints downstream widths). Direct arithmetic /
    -- comparison on the secret number throws when execution is
    -- tainted by us. Launder through BazUI:SafeNumber to a plain
    -- Lua number; same fix we applied in BazUI SpeedMonitor.
    local rawW = tooltip:GetWidth()
    local naturalW = (BazUI.SafeNumber and BazUI:SafeNumber(rawW)) or 0
    if not naturalW or naturalW < 1 then return nil end

    local frameW   = frame:GetWidth() or 0
    local frameEff = frame:GetEffectiveScale() or 1
    if frameW < 1 or frameEff < 0.001 then return nil end

    local ttParent = tooltip:GetParent()
    local ttParentEff = (ttParent and ttParent:GetEffectiveScale()) or 1
    if ttParentEff < 0.001 then ttParentEff = 1 end

    -- Solve for newScale such that
    --   naturalW * newScale * ttParentEff   ==   frameW * frameEff
    local s = (frameW * frameEff) / (naturalW * ttParentEff)
    if s > 1.0 then s = 1.0 end           -- never enlarge past natural
    if s < MIN_SCALE then s = MIN_SCALE end
    -- Snap to nearest grid step so a 1-px naturalW fluctuation doesn't
    -- yield a slightly different scale every OnSizeChanged.
    s = math.floor(s / SCALE_STEP + 0.5) * SCALE_STEP
    return s
end

local lastAppliedScale = nil

-- Monotonic scaling: a tooltip's scale within a single session can
-- only get smaller, never larger. Two reasons:
--
-- 1. Big tooltips (item / unit / quest with async content) start
--    narrow and grow over the first few frames as their content
--    streams in. We need to keep rescaling - but each rescale shrinks
--    further to keep the tooltip fitting the slot.
--
-- 2. The cooking-tooltip jitter was caused by naturalW oscillating
--    between two stable widths each frame; a non-monotonic scaler
--    would bounce the tooltip between two scales forever. Monotonic
--    breaks the bounce because once we've shrunk, we can't grow back.
--
-- Hysteresis filters out tiny shrinks (sub-step deltas).
local function ApplyScaleMonotonic(tooltip, s)
    if not s then return end
    if lastAppliedScale and s >= lastAppliedScale then return end
    if lastAppliedScale and (lastAppliedScale - s) < SCALE_HYST then
        return
    end
    lastAppliedScale = s
    tooltip:SetScale(s)
end

-- Coalesce reflow requests in a short window. Many OnSizeChanged
-- events fire in quick succession as item info / aura data caches
-- populate; calling Reflow on each was the source of visible "snap"
-- jitter in surrounding widgets.
local reflowPending = false
local function ScheduleReflow()
    if reflowPending then return end
    reflowPending = true
    C_Timer.After(SETTLE_MS / 1000, function()
        reflowPending = false
        if addon.WidgetHost and addon.WidgetHost.Reflow then
            addon.WidgetHost:Reflow()
        end
    end)
end

local function ApplyAnchorTo(tooltip)
    if not frame then return end
    local module = BazUI:GetModule("Tooltip")
    if module and module:OverridesAnchor() then return end
    -- Skip when the slot itself isn't visible. This covers two cases
    -- with one check: (a) the user disabled the widget via the
    -- standard Enabled toggle, which calls widget.frame:Hide(); and
    -- (b) the drawer is collapsed, which hides our parent chain.
    -- In either case anchoring would resolve to an off-screen position
    -- and confuse the user.
    if not frame:IsVisible() then return end

    -- Always re-apply the anchor - cheap, and protects us from a
    -- third-party hook that re-anchored the tooltip elsewhere.
    tooltip:ClearAllPoints()
    -- BOTTOMRIGHT-anchor so the tooltip's bottom edge stays planted on
    -- our slot's bottom-right; content extends up and to the left as
    -- the tooltip grows. Matches the standard "bottom-right pinned
    -- tooltip" UX.
    tooltip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    -- If the tooltip is already shown this is a mid-session re-anchor
    -- (some quest UIs call SetDefaultAnchor on every cursor update).
    -- Don't reset the scale baseline - that would let the tooltip
    -- grow back up if the addon's re-anchor happened to coincide with
    -- a brief naturalW dip.
    if tooltip:IsShown() then return end

    -- Fresh session - reset GameTooltip's scale to 1.0 as a known
    -- baseline (Blizzard never resets it between tooltips, so we'd
    -- otherwise inherit whatever the previous session left behind).
    -- Then prime lastAppliedScale to 1.0 so the monotonic guard
    -- treats the first OnSizeChanged-driven shrink as the real fit.
    tooltip:SetScale(1.0)
    lastAppliedScale = 1.0
end

local function InstallHooks()
    if hookInstalled then return end
    hookInstalled = true

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if tooltip == GameTooltip then
            ApplyAnchorTo(tooltip)
        end
    end)

    -- Once content fills in, re-fit the scale (we may have anchored
    -- pre-content with no usable width) and recompute slot height so
    -- the drawer slot grows to match the rendered tooltip.
    --
    -- BWD's host scales the widget's frame by `frame:GetScale()` -
    -- our reported `_desiredHeight` is in design (pre-host-scale)
    -- coordinates. We want the rendered slot height to equal the
    -- tooltip's rendered pixel height, so:
    --   designHeight * hostScale  ==  ttLogicalH * ttScale
    --   designHeight = ttLogicalH * ttScale / hostScale
    -- Every OnSizeChanged tries to tighten the scale via the
    -- monotonic guard. Big tooltips that grow as async content
    -- arrives keep shrinking until they fit; tooltips whose
    -- naturalW oscillates settle at the smallest seen scale and
    -- never bounce back up.
    --
    -- Height tracking is gated on a hysteresis threshold so a
    -- 1-2 px Blizzard auto-resize doesn't drive a Reflow chain,
    -- but the slot can still grow for content that arrives late.
    GameTooltip:HookScript("OnSizeChanged", function(self)
        if not frame or not frame:IsVisible() then return end
        local _, anchor = self:GetPoint(1)
        if anchor ~= frame then return end

        ApplyScaleMonotonic(self, ComputeFitScale(self))

        -- Same secret-number caveat as ComputeFitScale: GetHeight on
        -- an item-data-bearing tooltip is tainted. Launder before
        -- doing any arithmetic / comparisons.
        local ttLogicalH = (BazUI.SafeNumber and BazUI:SafeNumber(self:GetHeight())) or 0
        local ttScale    = self:GetScale() or 1
        local hostScale  = frame:GetScale() or 1
        if hostScale < 0.001 then hostScale = 1 end

        local design = (ttLogicalH * ttScale) / hostScale
        if design < DESIGN_HEIGHT then design = DESIGN_HEIGHT end
        if math.abs(design - lastTooltipHeight) >= HEIGHT_HYST then
            lastTooltipHeight = design
            ScheduleReflow()
        end
    end)

    -- When the tooltip closes, fall back to the minimum slot height
    -- and clear the per-session scale baseline so the next hover
    -- starts from 1.0 again.
    GameTooltip:HookScript("OnHide", function()
        lastAppliedScale = nil
        if math.abs(lastTooltipHeight - DESIGN_HEIGHT) >= HEIGHT_HYST then
            lastTooltipHeight = DESIGN_HEIGHT
            ScheduleReflow()
        end
    end)
end

---------------------------------------------------------------------------
-- Widget host hooks
---------------------------------------------------------------------------

function Tooltip:GetDesiredHeight()
    return math.max(lastTooltipHeight, DESIGN_HEIGHT)
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function Tooltip:Init()
    local f = self:Build()

    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Tooltip",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        -- Tooltip belongs at the drawer bottom by default - grows
        -- upward as content expands, which matches how BOTTOMRIGHT-
        -- pinned tooltips naturally behave.
        defaultDockToBottom = true,
        GetDesiredHeight    = function() return Tooltip:GetDesiredHeight() end,
    })

    InstallHooks()
end

BazUI:QueueForLogin(function() Tooltip:Init() end)
