-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: Hide Default
--
-- Hides Blizzard's default chat frames (ChatFrame1..10 and their
-- associated tabs / edit boxes / buttons) so our replica frames can
-- own the screen real estate. Reversible: HideDefault:Restore() puts
-- everything back, used when the user disables BazChat or unloads the
-- replica module.
--
-- We DO NOT call frame:UnregisterAllEvents() - other addons may have
-- registered events on Blizzard's chat frames and expect them to keep
-- firing. We just hide and reposition off-screen.
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

local HideDefault = {}
addon.HideDefault = HideDefault

-- Track which frames we've hidden so Restore() knows what to undo.
local hidden = {}

---------------------------------------------------------------------------
-- Internals
---------------------------------------------------------------------------

local function HideOne(frame)
    if not frame or hidden[frame] then return end

    -- Layered neutralization:
    --   1. Hide()              - normal invisibility
    --   2. SetAlpha(0)         - if Blizzard re-Show()s it, still invisible
    --   3. EnableMouse(false)  - can't be clicked through to
    --   4. ClearAllPoints + offscreen anchor - even if alpha somehow
    --      gets restored, the frame is at -10000,-10000 which is far
    --      outside any reasonable screen
    -- This is more thorough than a simple Hide() (which FCF can undo)
    -- and safer than an OnShow re-hide hook (which broke the chat
    -- keybind path - see git history for why we don't do that).
    --
    -- Capture original state first so Restore() can put things back
    -- exactly as Blizzard left them (other addons may have positioned
    -- these frames before us).
    local point, relTo, relPoint, x, y
    if frame.GetPoint and frame:GetNumPoints() > 0 then
        point, relTo, relPoint, x, y = frame:GetPoint(1)
    end
    hidden[frame] = {
        shown    = frame:IsShown(),
        alpha    = frame.GetAlpha and frame:GetAlpha() or 1,
        mouse    = frame.IsMouseEnabled and frame:IsMouseEnabled() or false,
        point    = point, relTo = relTo, relPoint = relPoint, x = x, y = y,
    }
    frame:Hide()
    if frame.SetAlpha then frame:SetAlpha(0) end
    if frame.EnableMouse then frame:EnableMouse(false) end
    if frame.ClearAllPoints and frame.SetPoint then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, -10000)
    end
end

local function RestoreOne(frame)
    local entry = hidden[frame]
    if not entry then return end
    -- Reverse the layered neutralization: restore alpha, mouse,
    -- position, and visibility. If we never captured a point (frame
    -- had none originally), we just leave it offscreen but the user's
    -- intent in that case is to disable BazChat anyway, so they'll
    -- /reload to clean up.
    if frame.SetAlpha then frame:SetAlpha(entry.alpha or 1) end
    if frame.EnableMouse then frame:EnableMouse(entry.mouse) end
    if entry.point and frame.ClearAllPoints and frame.SetPoint then
        frame:ClearAllPoints()
        frame:SetPoint(entry.point, entry.relTo or UIParent,
            entry.relPoint or entry.point, entry.x or 0, entry.y or 0)
    end
    if entry.shown then frame:Show() end
    hidden[frame] = nil
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Apply()
--   Hides all default chat windows + their UI scaffolding. Idempotent
--   (calling twice is a no-op for already-hidden frames).
function HideDefault:Apply()
    for i = 1, NUM_CHAT_WINDOWS do
        local cf = _G["ChatFrame" .. i]
        HideOne(cf)
        HideOne(_G["ChatFrame" .. i .. "Tab"])
        HideOne(_G["ChatFrame" .. i .. "EditBox"])
        -- Other companion frames Blizzard creates per chat window:
        HideOne(_G["ChatFrame" .. i .. "ButtonFrame"])
        HideOne(_G["ChatFrame" .. i .. "ResizeButton"])

        -- Blizzard Edit Mode integration: each ChatFrame has the
        -- EditModeSystemMixin, and OnEditModeEnter checks
        -- `self.defaultHideSelection` before calling HighlightSystem.
        -- Setting it true means Edit Mode never shows the highlight,
        -- so the user can't see it, click it, or drag it. Without
        -- this, dragging the highlight throws errors because our
        -- offscreen anchor (-10000,-10000) breaks Blizzard's
        -- snap-magnetism math (GetScaledSelectionSides:GetLeft -> nil).
        if cf then
            cf.defaultHideSelection = true
            -- If Edit Mode is currently active, the highlight may
            -- already be shown - clear it now too.
            if cf.ClearHighlight then cf:ClearHighlight() end
        end
    end
    -- The shared chat-strip elements that aren't per-frame.
    HideOne(_G["GeneralDockManager"])
    HideOne(_G["ChatFrameMenuButton"])
    HideOne(_G["ChatFrameChannelButton"])
    HideOne(_G["QuickJoinToastButton"])
end

-- Restore()
--   Reverses Apply(): every frame we hid is shown again (if it was
--   shown originally). Other addons' state is untouched.
function HideDefault:Restore()
    for frame in pairs(hidden) do
        RestoreOne(frame)
    end
    -- After Restore() the `hidden` table is empty.

    -- Re-enable Blizzard Edit Mode highlights on default chat frames.
    for i = 1, NUM_CHAT_WINDOWS do
        local cf = _G["ChatFrame" .. i]
        if cf then cf.defaultHideSelection = nil end
    end
end

-- IsApplied()
function HideDefault:IsApplied()
    return next(hidden) ~= nil
end
