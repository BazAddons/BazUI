-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: Typed Input History
--
-- Persists the last N messages the user typed into chat across /reload
-- and game restarts. Up-arrow / down-arrow in the edit box cycles
-- through these via Blizzard's built-in editBox:AddHistoryLine API -
-- we just feed it our saved list on every new edit-box creation.
--
-- Capture: hooksecurefunc("SendChatMessage", ...) catches every real
-- chat message the player sends (say / yell / party / channel / guild
-- / whisper / etc.). This fires AFTER the edit box clears its text,
-- but the message text is one of the function arguments so we don't
-- need to read editBox state - clean and patch-resilient.
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

local History = {}
addon.History = History

-- How many lines to remember. Blizzard's default is 32; 50 gives a
-- bit more headroom without exploding the saved-variable file.
local MAX_LINES = 50

-- Re-entry guard for Add(). When Add() rebuilds the native editbox
-- history (calls eb:AddHistoryLine for every saved entry), our
-- AddHistoryLine hook calls Add() in turn, and the rebuild loop
-- recurses through Add -> AddHistoryLine -> Add ... blowing the
-- stack and hard-crashing the client. Setting `rebuilding = true`
-- before the loop and checking it at the top of Add (and in the
-- AddHistoryLine hook) breaks the cycle.
local rebuilding = false

-- Same dual-path the other Replica modules use: addon.db is set in
-- BazUI's onReady (which fires after profile init), but addon.core.db
-- is populated earlier - so the fallback covers any frame-creation
-- timing where addon.db hasn't been stamped yet.
local function db()
    return (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
end

local function listRef()
    local p = db()
    if not p then return nil end
    p.typedHistory = p.typedHistory or {}
    return p.typedHistory
end

---------------------------------------------------------------------------
-- Public: Add(text)
--   Append `text` to the persistent history. Drops the oldest entry
--   when the cap is hit. Skips duplicates of the most-recent entry so
--   re-sending the same message doesn't spam the up-arrow buffer.
--
--   ALSO rebuilds every live editbox's native history from the
--   canonical saved list. Without this, messages sent in the current
--   session only show up in up-arrow cycling AFTER a /reload (since
--   the editbox's native history is only populated at frame creation
--   via History:Apply). The rebuild path uses ClearHistory + repeated
--   AddHistoryLine - cheap because the list caps at MAX_LINES (50).
---------------------------------------------------------------------------
function History:Add(text)
    if rebuilding then return end                  -- crash guard
    if not text or text == "" then return end
    local list = listRef()
    if not list then return end
    if list[#list] == text then return end   -- same as last? skip
    list[#list + 1] = text
    while #list > MAX_LINES do
        table.remove(list, 1)
    end

    -- Push the canonical list into every live tab's editbox so the
    -- new message is immediately available via up-arrow on any tab.
    -- The `rebuilding` flag short-circuits our AddHistoryLine hook
    -- so it doesn't re-enter Add() for each push below.
    rebuilding = true
    if addon.Window and addon.Window.list then
        for _, win in pairs(addon.Window.list) do
            local eb = win and win.editBox
            if eb and eb.ClearHistory and eb.AddHistoryLine then
                eb:ClearHistory()
                for _, t in ipairs(list) do
                    eb:AddHistoryLine(t)
                end
            end
        end
    end
    rebuilding = false
end

---------------------------------------------------------------------------
-- Public: Apply(editBox)
--
-- Wires arrow-key history navigation onto the editbox. The default
-- ChatFrameEditBoxTemplate has ignoreArrows="true" + an inherited
-- OnArrowPressed that only handles the autocomplete dropdown - chat
-- history isn't a built-in editbox behavior in modern retail. We
-- install our own OnArrowPressed that walks the saved typedHistory
-- list, moving backward through previous messages on UP and forward
-- on DOWN. The editbox's `AltArrowKeyMode = false` (set in
-- Window.lua) ensures arrows reach the script handler instead of
-- propagating to the game's move-forward keybind.
--
-- Also calls AddHistoryLine so the editbox's native history list
-- stays in sync (some Blizzard internals read from it - e.g. some
-- copy/paste paths). The actual cycling we implement below uses our
-- own per-editbox cursor + the canonical saved list.
---------------------------------------------------------------------------
function History:Apply(editBox)
    if not editBox then return end

    -- Mirror saved history into the editbox's native list (cheap
    -- belt-and-suspenders; also gives us a non-empty history if any
    -- Blizzard code path reads from the native list directly).
    if editBox.AddHistoryLine then
        local list = listRef()
        if list then
            -- Guard the seed loop: the AddHistoryLine hook installed
            -- below will fire for each call here once it's wired up
            -- on a re-Apply, and re-entering Add() during a seed
            -- crashes the same way the rebuild loop did. Setting
            -- `rebuilding` keeps both paths in sync.
            rebuilding = true
            for _, text in ipairs(list) do
                editBox:AddHistoryLine(text)
            end
            rebuilding = false
        end

        -- We DELIBERATELY do not hook editBox:AddHistoryLine here.
        -- Blizzard's chat send path calls AddHistoryLine with a
        -- *prefixed* form of the message (e.g. "/say hi" for a plain
        -- "hi" typed in say mode - see ChatFrameEditBoxMixin:AddHistory
        -- in BlizzardInterfaceCode/...ChatFrameEditBox.lua), so hooking
        -- that method captured both the raw input ("hi", from our
        -- OnEnterPressed pre-hook below) AND the prefixed form
        -- ("/say hi") for the same send. The prefixed form landed last,
        -- so UP brought back "/say hi" instead of "hi" - reported as
        -- "second-to-last instead of last". The OnEnterPressed pre-hook
        -- below handles slash commands too (the editbox text is "/dance"
        -- before Blizzard parses it), so dropping AddHistoryLine doesn't
        -- lose any capture path.
    end

    -- Robust pre-send capture. The hooks above (C_ChatInfo.SendChatMessage,
    -- legacy SendChatMessage, editBox:AddHistoryLine) catch the standard
    -- send paths, but Blizzard occasionally reroutes chat plumbing (recent
    -- Mixin restructuring of ChatFrameEditBox in 12.x) and a hooksecurefunc
    -- can silently no-op on a method that's been moved to a different mixin
    -- table. Wrapping the editbox's OnEnterPressed script gives us a
    -- guaranteed capture point: we read the text *before* Blizzard's
    -- handler clears it, then defer to the original. Add() de-dupes
    -- consecutive identical entries so this firing alongside any of the
    -- other hooks is harmless.
    if not editBox._bcEnterHooked then
        editBox._bcEnterHooked = true
        local origEnter = editBox:GetScript("OnEnterPressed")
        editBox:SetScript("OnEnterPressed", function(self, ...)
            local text = self:GetText()
            if text and text ~= "" then
                History:Add(text)
            end
            if origEnter then origEnter(self, ...) end
        end)
    end

    -- Per-editbox history cursor. nil = "not currently navigating;"
    -- a number = "showing entry at that index of the saved list."
    -- Reset on focus-gain + on text-change-from-typing so the user's
    -- own typing doesn't confuse the cursor.
    editBox._bcHistIdx = nil

    -- Hook OnEditFocusGained / OnTextChanged to reset the cursor when
    -- the user starts a fresh navigation context. The native send-
    -- text path also clears the editbox, so the cursor naturally
    -- resets between messages.
    editBox:HookScript("OnEditFocusGained", function(self)
        self._bcHistIdx = nil
    end)
    -- Note: HookScript("OnTextChanged") would fire even when WE set
    -- the text from history navigation, which would reset our cursor
    -- mid-cycle. Skip it; the focus-gained reset is sufficient.

    -- Arrow handling: SetScript (not HookScript) so we definitively own
    -- OnArrowPressed. We manually dispatch to the inherited autocomplete
    -- handler at the top of our function so the dropdown still wins
    -- when it's visible - HookScript silently fails if no prior script
    -- was set, which I suspect is the case in some chat-event timing
    -- scenarios.
    local function NavigateHistory(self, key)
        -- Defer to the autocomplete dropdown when it's the active
        -- consumer of arrow keys for this editbox.
        if _G.AutoCompleteEditBox_OnArrowPressed then
            local handled = _G.AutoCompleteEditBox_OnArrowPressed(self, key)
            if handled then return end
        end
        -- Defensive: if AutoCompleteBox is showing for us, also bail.
        local acb = _G.AutoCompleteBox
        if acb and acb:IsShown() and acb.parent == self then return end

        local list = listRef()
        if not list or #list == 0 then return end

        local idx = self._bcHistIdx
        if key == "UP" then
            if idx == nil then
                idx = #list                       -- newest entry
            elseif idx > 1 then
                idx = idx - 1
            end
        elseif key == "DOWN" then
            if idx == nil then return end
            if idx < #list then
                idx = idx + 1
            else
                self._bcHistIdx = nil
                pcall(self.SetText, self, "")
                return
            end
        else
            return
        end

        self._bcHistIdx = idx
        pcall(self.SetText, self, list[idx] or "")
        if self.SetCursorPosition then
            pcall(self.SetCursorPosition, self, #(list[idx] or ""))
        end
    end

    editBox:SetScript("OnArrowPressed", NavigateHistory)

    -- A previous build also wired OnKeyDown for "UP"/"DOWN" as
    -- belt-and-suspenders, but that fired in addition to our
    -- OnArrowPressed handler so a single press advanced the cursor
    -- TWICE: idx nil -> #list (sets newest), then idx #list -> #list-1
    -- (sets second-newest, overwriting the first SetText). UP appeared
    -- to skip the most-recent entry. OnArrowPressed is reliable on
    -- ChatFrameEditBoxTemplate, so we don't need the redundancy -
    -- removed to fix the double-step.
end

---------------------------------------------------------------------------
-- Install
--
-- All capture happens through History:Apply (the OnEnterPressed pre-hook
-- on each BazChat editbox), which reads the raw editbox text *before*
-- Blizzard's ParseText runs. That gives us the user's actual typed input
-- (e.g. "/say hi", or "/dance", or just "hi") regardless of which send
-- path Blizzard takes after parsing.
--
-- Earlier versions also hooked C_ChatInfo.SendChatMessage and the
-- legacy SendChatMessage as redundancy, but those fire with the
-- POST-parse text (Blizzard's ProcessChatType rewrites the editbox
-- text from "/say hi" to "hi" and changes the chat type, then SendText
-- calls C_ChatInfo.SendChatMessage("hi", "SAY", ...)). Adding both the
-- raw "/say hi" and the post-parse "hi" produced two history entries
-- per send and pressing UP returned the post-parse entry even though
-- the user expected their typed form. Dropping those hooks keeps the
-- list aligned with what the user actually typed.
---------------------------------------------------------------------------

function History:Install()
    -- nothing to do; capture lives in History:Apply per editbox.
end
