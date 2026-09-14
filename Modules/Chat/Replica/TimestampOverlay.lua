-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: TimestampOverlay
--
-- Renders per-message timestamps as overlay FontStrings parented to
-- the chat frame, anchored to each visible-line FontString that the
-- ScrollingMessageFrame manages internally. The reasoning:
--
--   * Each AddMessage call becomes one FontString in the SMF's
--     `visibleLines` array (the SMF FontString wraps INSIDE itself,
--     so wrapped continuations don't get extra entries).
--   * If we anchor a label at TOPLEFT of that FontString, it sits at
--     the top of the message - and stays there even when the message
--     wraps to multiple visual rows. Wrapped continuations have no
--     timestamp, which matches what the user wants.
--
-- The SMF body is offset by Timestamps:ColumnWidth pixels worth of
-- leading whitespace in the text so the overlay column doesn't
-- overlap message text.
--
-- Public API (on addon.TimestampOverlay):
--   :Wire(chatFrame)             -- attach the overlay system
--   :Refresh(chatFrame)           -- recompute all overlays now
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

local TimestampOverlay = {}
addon.TimestampOverlay = TimestampOverlay

local function GetCfgEnabled()
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    return p and p.timestamps and p.timestamps.enabled or false
end

---------------------------------------------------------------------------
-- Per-frame label pool
--
-- Active labels are tracked in f._bcTSActive (anchored, visible).
-- Released labels live in f._bcTSPool (hidden, ready to reuse).
-- Refresh moves all active to pool, then re-acquires what it needs.
-- Net memory is bounded by max simultaneously visible lines.
---------------------------------------------------------------------------

-- Format helper for the on-hover tooltip. Just the date - no time,
-- since the user is hovering the visible time already. Output:
-- "Thursday, April 30, 2026". Falls back to empty string if the
-- timestamp is missing or invalid.
local function FormatHoverDate(t)
    if type(t) ~= "number" then return "" end
    -- %A = full weekday, %B = full month, %d = day-of-month, %Y = year.
    -- Strip the leading-zero on day-of-month ("April 05" -> "April 5")
    -- which date() always emits but reads awkwardly.
    return (date("%A, %B %d, %Y", t):gsub(" 0(%d,)", " %1"))
end

-- Tooltip handlers (set once per Frame at creation; the closure reads
-- the frame's _bcCapturedTime field which Refresh updates per use).
-- The hover tooltip is gated by the timestamps.hoverTooltip setting,
-- defaulting to enabled. Read the live config every entry so toggling
-- the setting takes effect immediately without /reload.
local function OnLabelEnter(self)
    if not self._bcCapturedTime or not GameTooltip then return end
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    if not (p and p.timestamps and p.timestamps.hoverTooltip ~= false) then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(FormatHoverDate(self._bcCapturedTime), 1, 1, 1)
    GameTooltip:Show()
end

local function OnLabelLeave(self)
    if GameTooltip and GameTooltip:GetOwner() == self then
        GameTooltip:Hide()
    end
end

local function AcquireLabel(f)
    local pool = f._bcTSPool
    if pool and #pool > 0 then
        local lbl = pool[#pool]
        pool[#pool] = nil
        return lbl
    end
    -- Parent labels to the FontStringContainer (the SMF's internal
    -- clipping region) instead of the chat frame directly. The SMF's
    -- own visibleLines live inside this container with clipChildren
    -- true, so anything outside its bounds (i.e. timestamps from
    -- messages that have scrolled past the top of the chat) gets
    -- clipped automatically. Falls back to the chat frame when the
    -- template doesn't expose a container.
    --
    -- Wrap the FontString in a Frame so we get OnEnter/OnLeave for
    -- the on-hover date tooltip - bare FontStrings don't take mouse
    -- events. The Frame's size is sync'd to the FontString in Refresh
    -- so the hit rect matches the visible text.
    local parent = f.FontStringContainer or f
    local lbl = CreateFrame("Frame", nil, parent)
    lbl:SetFrameLevel((parent:GetFrameLevel() or 0) + 5)
    lbl:EnableMouse(true)
    lbl.text = BazUI.Skin.Theme.FontString(lbl, "OVERLAY", "ChatFontNormal")
    lbl.text:SetJustifyH("LEFT")
    lbl.text:SetJustifyV("TOP")
    lbl.text:SetAllPoints(lbl)
    lbl:SetScript("OnEnter", OnLabelEnter)
    lbl:SetScript("OnLeave", OnLabelLeave)
    return lbl
end

-- Acquire/release for the per-message vertical bar texture that
-- separates the timestamp gutter from the message body. The bar
-- spans the full height of each visibleLine so wrapped continuations
-- stay visually anchored to their timestamp.
local function AcquireBar(f)
    local pool = f._bcTSBarPool
    if pool and #pool > 0 then
        local bar = pool[#pool]
        pool[#pool] = nil
        return bar
    end
    local parent = f.FontStringContainer or f
    local bar = parent:CreateTexture(nil, "OVERLAY")
    return bar
end

local function ReleaseAll(f)
    f._bcTSPool    = f._bcTSPool    or {}
    f._bcTSBarPool = f._bcTSBarPool or {}
    if f._bcTSActive then
        for i = #f._bcTSActive, 1, -1 do
            local lbl = f._bcTSActive[i]
            lbl:Hide()
            lbl:ClearAllPoints()
            f._bcTSPool[#f._bcTSPool + 1] = lbl
            f._bcTSActive[i] = nil
        end
    end
    if f._bcTSBars then
        for i = #f._bcTSBars, 1, -1 do
            local bar = f._bcTSBars[i]
            bar:Hide()
            bar:ClearAllPoints()
            f._bcTSBarPool[#f._bcTSBarPool + 1] = bar
            f._bcTSBars[i] = nil
        end
    end
end

---------------------------------------------------------------------------
-- :Refresh — rebuild overlays from the SMF's current visibleLines
--
-- Called from a hooked RefreshDisplay (so we always run AFTER the SMF
-- has anchored its own FontStrings). Walks visibleLines in render
-- order, looks up each one's source entry via
-- (lineIndex + scrollOffset), pulls the captured timestamp out of the
-- entry's extras using the Timestamps sentinel, formats it, and
-- parents an overlay FontString anchored at the visibleLine's TOPLEFT.
---------------------------------------------------------------------------

-- Pull our captured timestamp out of an SMF entry's extraData. The
-- SMF stores extras as a numeric-keyed table with a separate `n`
-- field for length (because nils inside extras are valid). We walk
-- that table looking for the sentinel paired with the unix time.
local function ExtractFromEntry(entry)
    if not entry then return nil end
    local ed = entry.extraData
    if type(ed) ~= "table" then return nil end
    local n = ed.n or #ed
    local SENTINEL = addon.Timestamps and addon.Timestamps.SENTINEL or "_bcTS"
    for i = 1, n - 1 do
        local v = ed[i]
        -- Extras can carry secret values (Midnight); `==` on one throws.
        if type(v) == "string" and not (issecretvalue and issecretvalue(v))
            and v == SENTINEL then
            return ed[i + 1]
        end
    end
    return nil
end

function TimestampOverlay:Refresh(f)
    if not f then return end
    f._bcTSActive = f._bcTSActive or {}
    f._bcTSBars   = f._bcTSBars   or {}
    ReleaseAll(f)

    if not GetCfgEnabled() then return end
    if not addon.Timestamps then return end
    if type(f.visibleLines) ~= "table" then return end

    -- Direct entry lookup: each visibleLine FontString carries a
    -- .messageInfo back-reference to its source historyBuffer entry
    -- (set by SMF:RefreshDisplay at line 631 of the source). That
    -- skips the GetMessageInfo path entirely - GetMessageInfo inverts
    -- the index so my earlier lineIndex+scrollOffset lookups were
    -- pulling from the wrong entries (which is why spacers ended up
    -- with timestamp overlays from other rows).
    local gutterAnchor = f.FontStringContainer or f
    -- Fallback color for the bar when a message has no explicit r/g/b
    -- (rare; happens for some system events). Uses the timestamp color
    -- so the gutter still reads as one element in those cases.
    local fbR, fbG, fbB = addon.Timestamps:ColorRGBA()
    for _, vline in ipairs(f.visibleLines) do
        if vline and vline:IsShown() then
            local entry = vline.messageInfo
            local ts    = ExtractFromEntry(entry)
            if ts then
                -- Timestamp label: top-left of message, left-aligned in
                -- the gutter. Text goes into lbl.text (the FontString
                -- inside the Frame); the Frame itself is mouse-enabled
                -- and shows the on-hover date tooltip via the
                -- OnLabelEnter/Leave scripts wired in AcquireLabel.
                local lbl = AcquireLabel(f)
                lbl:ClearAllPoints()
                lbl:SetPoint("LEFT", gutterAnchor, "LEFT", 2, 0)
                lbl:SetPoint("TOP",  vline, "TOP", 0, 0)
                -- Frame size = the gutter column width so the hit rect
                -- spans the visible timestamp area cleanly. Height
                -- tracks the SMF's font line height; using a single
                -- font line is fine because the timestamp is always
                -- one row tall.
                local colW = (addon.Timestamps and addon.Timestamps.ColumnWidth)
                    and addon.Timestamps:ColumnWidth(f) or 60
                lbl:SetSize(colW - 4, 14)
                -- Same face as the chat body, whatever it is set to.
                local fontFile, fontSize, fontFlags = f:GetFont()
                if fontFile then lbl.text:SetFont(fontFile, fontSize, fontFlags or "") end
                lbl.text:SetText(addon.Timestamps:FormatGutter(ts))
                lbl:SetAlpha(vline:GetAlpha() or 1)
                lbl._bcCapturedTime = ts
                lbl:Show()
                f._bcTSActive[#f._bcTSActive + 1] = lbl

                -- Vertical separator bar: thin texture that spans the
                -- FULL height of the message (including wrapped rows
                -- inside the same vline FontString). Anchored with
                -- -7px x-offset so its LEFT sits at (body_left - 7),
                -- giving 6px of gap to the timestamp on the left AND
                -- 6px of gap to the body text on the right (the 13px
                -- buffer in Timestamps:ColumnWidth is split evenly:
                -- 6 + 1(bar) + 6 = 13).
                --
                -- Bar color: per-message - pulled from the entry's
                -- own r/g/b (which the chat formatter set based on the
                -- ChatTypeInfo entry for that message's channel/type).
                -- Result: green bars for guild, pink for whispers,
                -- yellow for system, the channel's custom color for
                -- numbered channels, etc. Matches the message body's
                -- text color exactly.
                local barR = entry and entry.r or fbR
                local barG = entry and entry.g or fbG
                local barB = entry and entry.b or fbB
                local bar  = AcquireBar(f)
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT",     vline, "TOPLEFT",     -7, 0)
                bar:SetPoint("BOTTOMLEFT",  vline, "BOTTOMLEFT",  -7, 0)
                bar:SetWidth(1)
                bar:SetColorTexture(barR, barG, barB, 1)
                bar:SetAlpha(vline:GetAlpha() or 1)
                bar:Show()
                f._bcTSBars[#f._bcTSBars + 1] = bar
            end
        end
    end
end

---------------------------------------------------------------------------
-- :Wire — install the SMF refresh hook on a chat frame
--
-- Wraps f.RefreshDisplay (the SMF mixin method) so every redraw
-- triggers our overlay rebuild. Idempotent: skips if already wired.
-- Also runs an initial Refresh so existing visibleLines get labeled
-- (handles the post-Replay state without waiting for the next event).
---------------------------------------------------------------------------

-- Post-process visibleLines after the SMF's own RefreshLayout has
-- anchored them. We:
--   1. Shrink each line's width by the timestamp column so the SMF's
--      word-wrap algorithm wraps inside the BODY area only.
--   2. Re-anchor each line with +colW x-offset so the body's left
--      edge sits past the timestamp gutter. SetIndentedWordWrap then
--      aligns wrapped continuations to that same body-left edge.
--
-- Overlays anchor to the chat frame f directly (NOT the visibleLine),
-- using LEFT-of-f for x and TOP-of-vline for y, so they live in the
-- gutter alongside each message's first row.
local function AdjustVisibleLines(f)
    if not addon.Timestamps then return end
    local colW = addon.Timestamps:ColumnWidth(f)
    if not colW or colW <= 0 then return end
    if type(f.visibleLines) ~= "table" then return end

    local frameW = f:GetWidth() or 0
    if frameW <= colW then return end
    local bodyW = frameW - colW

    for lineIndex, vline in ipairs(f.visibleLines) do
        if vline then
            vline:SetWidth(bodyW)
            -- The first line is anchored directly to the SMF; subsequent
            -- lines are anchored to the previous visibleLine. Only the
            -- first needs its absolute-anchor x shifted; the rest
            -- inherit the offset through the chain.
            if lineIndex == 1 then
                local point, relativeTo, relativePoint, x, y = vline:GetPoint(1)
                if point and relativeTo == f then
                    vline:ClearAllPoints()
                    vline:SetPoint(point, relativeTo, relativePoint,
                        (x or 0) + colW, y or 0)
                end
            end
        end
    end
end

function TimestampOverlay:Wire(f)
    if not f or f._bcTSWired then return end
    f._bcTSWired = true
    f._bcTSActive = {}
    f._bcTSPool   = {}

    -- IndentedWordWrap is a frame-level WoW setting: when true, the
    -- chat's wrap algorithm aligns continuation lines to the first
    -- character past the first space ("Player says: hello\n   says:"
    -- pattern) - one word in from the body's left edge. With our
    -- gutter-shift anchor model we already start the body at the
    -- correct x, so any further indent just looks "too indented."
    -- Force it off; the anchor shift gives us clean column alignment.
    if type(f.SetIndentedWordWrap) == "function" then
        f:SetIndentedWordWrap(false)
    end

    -- Hook RefreshLayout so visibleLines get the body-only width +
    -- gutter offset every time SMF re-lays-out (resize, font change,
    -- etc.). Hook RefreshDisplay so the per-message overlay labels
    -- re-render after each redraw (scroll, fade, message add).
    if type(f.RefreshLayout) == "function" then
        local original = f.RefreshLayout
        f.RefreshLayout = function(self, ...)
            original(self, ...)
            AdjustVisibleLines(self)
        end
    end

    if type(f.RefreshDisplay) == "function" then
        local original = f.RefreshDisplay
        f.RefreshDisplay = function(self, ...)
            original(self, ...)
            TimestampOverlay:Refresh(self)
        end
    end

    -- Also tick on OnUpdate to catch fade-alpha changes the SMF makes
    -- between RefreshDisplay calls. Keep it cheap: only re-sync alpha,
    -- not full rebuild. Walks visibleLines + active labels + bars in
    -- parallel, skipping vlines whose entry has no sentinel
    -- (separator/spacer rows).
    f:HookScript("OnUpdate", function(self)
        if not self._bcTSActive or #self._bcTSActive == 0 then return end
        if type(self.visibleLines) ~= "table" then return end
        local activeI = 1
        for _, vline in ipairs(self.visibleLines) do
            if vline and vline:IsShown() then
                local ts = ExtractFromEntry(vline.messageInfo)
                if ts then
                    local alpha = vline:GetAlpha() or 1
                    local lbl = self._bcTSActive[activeI]
                    local bar = self._bcTSBars and self._bcTSBars[activeI]
                    if lbl then lbl:SetAlpha(alpha) end
                    if bar then bar:SetAlpha(alpha) end
                    activeI = activeI + 1
                end
            end
        end
    end)

    self:Refresh(f)
end
