-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: Timestamps
--
-- Two-column timestamp rendering. The timestamp is NOT prefixed into
-- the message text anymore - that approach made wrapped continuation
-- lines align under the timestamp instead of under the message body.
-- Instead:
--   * Each AddMessage carries the unix time in the SMF entry's extras
--     (marked with a sentinel so we don't collide with other addons'
--     extras that might also live there).
--   * Replica/TimestampOverlay walks the SMF's visibleLines after
--     every RefreshDisplay and parents a small FontString to each
--     line's TOPLEFT, showing the formatted time.
--   * Message text is padded with leading whitespace sized to the
--     timestamp column width so the SMF's word-wrap leaves room for
--     the overlay.
--
-- Public API:
--   addon.Timestamps:Pad(text, chatFrame)  -> padded text (or unchanged)
--   addon.Timestamps:FormatTime(t)         -> formatted time string
--   addon.Timestamps:ColorCode()           -> "|cAARRGGBB" escape
--   addon.Timestamps.SENTINEL              -- string used in extras
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

local Timestamps = {}
addon.Timestamps = Timestamps

-- Sentinel marker we drop into SMF entry extras so we can find our
-- captured timestamp later regardless of how many other extras the
-- caller passed. Pair: { ..., SENTINEL, <unix-time>, ... }.
Timestamps.SENTINEL = "_bcTS"

local function GetCfg()
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    return p and p.timestamps or nil
end

-- |cAARRGGBB color escape from a {r,g,b,a} table (each in 0..1).
local function ToColorCode(rgba)
    if type(rgba) ~= "table" then return "|cff8c8c8c" end
    local r = math.floor((rgba[1] or 0.5) * 255)
    local g = math.floor((rgba[2] or 0.5) * 255)
    local b = math.floor((rgba[3] or 0.5) * 255)
    local a = math.floor((rgba[4] or 1.0) * 255)
    return string.format("|c%02x%02x%02x%02x", a, r, g, b)
end

---------------------------------------------------------------------------
-- :ColorCode — escape sequence for the timestamp overlay
---------------------------------------------------------------------------

function Timestamps:ColorCode()
    local cfg = GetCfg() or {}
    return ToColorCode(cfg.color)
end

---------------------------------------------------------------------------
-- :FormatTime — render the unix time as the user's chosen strftime format
---------------------------------------------------------------------------

function Timestamps:FormatTime(t)
    local cfg = GetCfg()
    if not cfg or not cfg.enabled then return "" end
    local fmt = (cfg.format ~= "" and cfg.format) or "%H:%M:%S"
    return date(fmt, t)
end

---------------------------------------------------------------------------
-- :ColorRGBA — accessor for the user's timestamp color as a 4-tuple.
-- Used by the texture-bar separator to match the timestamp tint.
---------------------------------------------------------------------------

function Timestamps:ColorRGBA()
    local cfg = GetCfg() or {}
    local c = cfg.color
    if type(c) ~= "table" then return 0.55, 0.55, 0.55, 1 end
    return c[1] or 0.55, c[2] or 0.55, c[3] or 0.55, c[4] or 1
end

---------------------------------------------------------------------------
-- :FormatGutter — gutter label text: just the timestamp.
--
-- The visual separator between timestamp and message body is now a
-- texture bar (rendered by Replica/TimestampOverlay) that extends the
-- full message height, so wrapped continuations stay visually tied to
-- their timestamp. We don't append a separator character to the
-- timestamp text - that approach doesn't span message height.
---------------------------------------------------------------------------

function Timestamps:FormatGutter(t)
    local cfg = GetCfg()
    if not cfg or not cfg.enabled then return "" end
    return self:ColorCode() .. self:FormatTime(t) .. "|r"
end

-- Non-breaking space (UTF-8 encoding of U+00A0). We use this instead
-- of regular spaces for the leading padding because:
--   * Some chat code paths trim leading regular whitespace before the
--     SMF gets the line - that wipes out our padding entirely.
--   * NBSP renders as space-width but is NOT trimmed by ASCII-aware
--     trimmers, so it survives the round-trip.
--   * The chat formatter's word-wrap respects regular spaces only as
--     break points, so a run of NBSPs stays contiguous + non-breaking
--     (which is what we want for a fixed column).
local NBSP = "\194\160"

---------------------------------------------------------------------------
-- :ColumnWidth — compute the timestamp overlay's pixel width.
--
-- Measures the user's CURRENT format with a max-width sample time
-- (23:59:59 / 12:59:59 PM) plus a trailing buffer. Cached only when
-- the result is positive so a transient "feature disabled" call
-- doesn't poison the cache with 0 forever.
---------------------------------------------------------------------------

function Timestamps:ColumnWidth(chatFrame)
    if not chatFrame then return 0 end
    if chatFrame._bcTSColWidth and chatFrame._bcTSColWidth > 0 then
        return chatFrame._bcTSColWidth
    end

    local cfg = GetCfg()
    if not cfg or not cfg.enabled then return 0 end

    -- Probe via a hidden FontString sharing the chat's font. Leave it
    -- parented (no SetParent(nil)) so the FontInstance stays valid for
    -- GetStringWidth; the FontString is hidden + offscreen and never
    -- rendered, so the cost is bounded.
    local probe = chatFrame._bcTSProbe
    if not probe then
        probe = BazUI.Skin.Theme.FontString(chatFrame, "BACKGROUND", "ChatFontNormal")
        probe:Hide()
        chatFrame._bcTSProbe = probe
    end
    -- Measure in whatever face the chat is actually using.
    local fontFile, fontSize, fontFlags = chatFrame:GetFont()
    if fontFile then probe:SetFont(fontFile, fontSize, fontFlags or "") end
    -- Wide-sample for the user's current format. 23:59:59 maximizes the
    -- 24-hour cases; 12:59:59 PM (the same time formatted with %I/%p)
    -- maximizes the 12-hour cases. We pick whichever is wider, then
    -- add a fixed 13px buffer that splits evenly into 6 + 1 + 6:
    -- 6px gap, 1px bar, 6px gap. Symmetric centering.
    local fmt = (cfg.format ~= "" and cfg.format) or "%H:%M:%S"
    local sampleA = date(fmt, 86399)        -- 24-hour
    local sampleB = date(fmt, 86399 - 12*3600)  -- 12-hour
    probe:SetText(sampleA)
    local wA = probe:GetStringWidth() or 0
    probe:SetText(sampleB)
    local wB = probe:GetStringWidth() or 0
    local w = math.max(wA, wB) + 13   -- 13px buffer (6 + 1 bar + 6)
    -- Floor at a sensible minimum so a measurement glitch doesn't leave
    -- us with zero padding and overlapping text.
    w = math.max(math.ceil(w), 60)
    chatFrame._bcTSColWidth = w
    return w
end

---------------------------------------------------------------------------
-- :Pad — prepend leading non-breaking spaces sized to the timestamp
-- column.
--
-- Because the padding is NBSPs, the chat formatter's word-wrap does
-- NOT use them as break points - the entire padding + first word
-- of the message becomes one giant "word" from the SMF's perspective.
-- That's actually the correct geometry: the SMF wraps at the first
-- regular space in the message body, and SetIndentedWordWrap aligns
-- continuation lines to the start of that wrappable region.
---------------------------------------------------------------------------

function Timestamps:Pad(text, chatFrame)
    local cfg = GetCfg()
    if not cfg or not cfg.enabled then return text end
    if type(text) ~= "string" or text == "" then return text end
    if not chatFrame then return text end

    local padding = chatFrame._bcTSPadding
    if not padding or padding == "" then
        local colW = self:ColumnWidth(chatFrame)
        if colW <= 0 then return text end   -- can't measure yet, no caching
        local probe = chatFrame._bcTSProbe
        if not probe then
            probe = BazUI.Skin.Theme.FontString(chatFrame, "BACKGROUND", "ChatFontNormal")
            probe:Hide()
            chatFrame._bcTSProbe = probe
        end
        local fontFile, fontSize, fontFlags = chatFrame:GetFont()
        if fontFile then probe:SetFont(fontFile, fontSize, fontFlags or "") end
        probe:SetText(NBSP)
        local nbspW = probe:GetStringWidth() or 4
        local n = math.ceil(colW / math.max(nbspW, 1))
        -- Floor at 12 NBSPs so a probe glitch doesn't leave us with too
        -- little padding (worst case = a few extra NBSPs, no visual harm).
        n = math.max(n, 12)
        padding = string.rep(NBSP, n)
        chatFrame._bcTSPadding = padding
    end
    return padding .. text
end

---------------------------------------------------------------------------
-- :InvalidateLayout — drop cached padding/width on a chat frame so the
-- next message recomputes. Call when font, format, or column logic changes.
---------------------------------------------------------------------------

function Timestamps:InvalidateLayout(chatFrame)
    if not chatFrame then return end
    chatFrame._bcTSColWidth = nil
    chatFrame._bcTSPadding  = nil
end

---------------------------------------------------------------------------
-- :ExtractTimestamp — find our sentinel in the extras tail of a
-- f:GetMessageInfo() result and return the paired unix time. Returns
-- nil when no sentinel is present (e.g. messages added before the
-- refactor, or the end-of-history separator).
---------------------------------------------------------------------------

function Timestamps:ExtractTimestamp(...)
    local n = select("#", ...)
    -- extras start at position 7: text, r, g, b, messageId, holdTime, ...
    for i = 7, n - 1 do
        local v = select(i, ...)
        -- Extras can carry secret values (Midnight); `==` on one throws.
        if type(v) == "string" and not (issecretvalue and issecretvalue(v))
            and v == self.SENTINEL then
            return select(i + 1, ...)
        end
    end
    return nil
end
