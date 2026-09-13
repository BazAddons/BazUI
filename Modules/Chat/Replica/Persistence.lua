-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: Persistence
--
-- Captures every line that hits a chat frame's AddMessage, stores it
-- per-tab in the SavedVariable, and replays the history on the next
-- /reload (or relog) so the chat picks up where you left off instead
-- of starting blank.
--
-- Storage shape (per window):
--   addon.db.profile.windows[idx].history = {
--       { text = "...", r = 1, g = 0.5, b = 0.5, time = <unix> },
--       ...   -- newest at the end, capped to persistMaxLines
--   }
--
-- Public API (on addon.Persistence):
--   :Append(idx, text, r, g, b)   -- per-line, called from HookAddMessage
--   :Replay(f, idx)                -- on Window:Create, populates the SMF
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

local Persistence = {}
addon.Persistence = Persistence

-- Persistence cap is tied to windows[1].maxLines (the History Buffer
-- slider in Settings / Edit Mode). Storing more lines than the SMF can
-- display is wasted CPU on replay - the chat would just drop the older
-- ones from its in-memory buffer the moment we push them in. Tying
-- the two settings means the History Buffer slider controls BOTH
-- "how much chat to keep visible" and "how much chat to persist."
local DEFAULT_MAX_LINES = 500

local function GetWindow(idx)
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    return p and p.windows and p.windows[idx] or nil
end

local function MaxLines()
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    local chrome = p and p.windows and p.windows[1]
    return (chrome and chrome.maxLines) or DEFAULT_MAX_LINES
end

---------------------------------------------------------------------------
-- :Append — per-line capture
--
-- Skips entries that look like our own end-of-history separator (those
-- start with `|cff8ce0ff--- `) so reload after reload doesn't stack
-- separators on top of each other.
---------------------------------------------------------------------------

function Persistence:Append(idx, text, r, g, b)
    if type(text) ~= "string" then return end

    -- Defensive: skip secret/protected strings. The HookAddMessage
    -- caller probes for these and bypasses Persistence entirely, but
    -- the guard is cheap and protects against future direct callers.
    -- pcall a comparison; if it errors, text is secret.
    local probeOk = pcall(function() return text == "" end)
    if not probeOk then return end

    if text == "" then return end
    if text:find("^|cff%x%x%x%x%x%x%-%-%- ") then return end
    -- Skip blank-row spacers (legacy from the old per-message spacing
    -- implementation). v201 uses SetSpacing() for inter-line gaps so
    -- no spacer rows are emitted into the SMF anymore - guard remains
    -- so older histories that contain " " entries don't replay them.
    if text == " " then return end

    local ws = GetWindow(idx)
    if not ws then return end
    ws.history = ws.history or {}

    table.insert(ws.history, {
        text = text,
        r    = r,
        g    = g,
        b    = b,
        time = time(),
    })

    local cap = MaxLines()
    while #ws.history > cap do
        table.remove(ws.history, 1)   -- drop oldest
    end
end

---------------------------------------------------------------------------
-- :Replay — push the saved history into the chat frame
--
-- Called from Window:Create AFTER the chat is set up but BEFORE channel
-- subscription, so historic messages render before any live messages
-- come in. Uses the chat frame's CAPTURED original AddMessage (saved on
-- f._bcOriginalAddMessage by HookAddMessage) to bypass our own hook -
-- otherwise replaying would re-append every line, doubling history on
-- each reload.
---------------------------------------------------------------------------

function Persistence:Replay(f, idx)
    if not f then return end
    local ws = GetWindow(idx)
    if not ws or not ws.history or #ws.history == 0 then return end

    local addMessage = f._bcOriginalAddMessage or f.AddMessage
    if type(addMessage) ~= "function" then return end

    -- Tag each replayed entry with our timestamp sentinel so the
    -- overlay system shows historic stamps with their original capture
    -- moment. We bypass the AddMessage hook here (using the captured
    -- original) to avoid re-appending replayed lines back into history,
    -- so the sentinel goes in directly via the SMF's extras channel.
    -- No leading padding: AdjustVisibleLines shifts the SMF body past
    -- the gutter for us, so the raw text renders at the correct x.
    --
    -- Channel-name rewrite is also applied here (replay-time) so
    -- replayed history matches the live-render look. The rewrite
    -- reads the user's CURRENT settings - so toggling the feature
    -- off and reloading shows historic lines with full brackets again.
    local SENTINEL = addon.Timestamps and addon.Timestamps.SENTINEL or "_bcTS"
    for _, entry in ipairs(ws.history) do
        local rendered = entry.text
        if addon.ChannelNames and addon.ChannelNames.Rewrite then
            rendered = addon.ChannelNames:Rewrite(rendered)
        end
        addMessage(f, rendered, entry.r, entry.g, entry.b,
            nil, nil, SENTINEL, entry.time)
    end

    -- Bracket the end-of-history separator with blank rows so the
    -- session boundary is visually distinct from both the last
    -- historic message and the first live message that follows.
    -- The blank " " rows are full font-line gaps regardless of the
    -- SetSpacing-based per-line spacing - the boundary is a meaningful
    -- visual break, so it earns the extra height on both sides.
    --
    -- The "restored HH:MM:SS" portion uses Timestamps:FormatTime so
    -- it follows the user's chosen format (12-hour vs 24-hour, with
    -- or without seconds) rather than a hardcoded "%H:%M:%S". Falls
    -- back to "%H:%M:%S" when the timestamps module isn't loaded.
    local restoredAt
    if addon.Timestamps and addon.Timestamps.FormatTime then
        restoredAt = addon.Timestamps:FormatTime(time())
        if not restoredAt or restoredAt == "" then
            restoredAt = date("%H:%M:%S")
        end
    else
        restoredAt = date("%H:%M:%S")
    end
    local sep = string.format(
        "|cff8ce0ff--- end of history (%d lines, restored %s) ---|r",
        #ws.history, restoredAt)
    addMessage(f, " ", 1, 1, 1)
    addMessage(f, sep, 0.55, 0.85, 1)
    addMessage(f, " ", 1, 1, 1)
end
