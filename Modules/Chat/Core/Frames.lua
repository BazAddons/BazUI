-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Chat Frame Helpers
--
-- Thin utility layer over Blizzard's chat frame globals so modules
-- don't have to repeat the iteration / lookup boilerplate. Anything
-- that needs to walk all chat windows, find the active tab, or
-- bracket the AddMessage hook with a guard goes here.
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

---------------------------------------------------------------------------
-- IterateChatFrames(fn)
--   Calls fn(chatFrame, index, tab) for every numbered chat frame the
--   client has (1..NUM_CHAT_WINDOWS). Skips frames the user hasn't
--   created yet. The tab arg is _G["ChatFrame<i>Tab"], handy for
--   modules that anchor visuals to the tab strip.
---------------------------------------------------------------------------

function addon:IterateChatFrames(fn)
    for i = 1, NUM_CHAT_WINDOWS do
        local cf = _G["ChatFrame" .. i]
        if cf then
            fn(cf, i, _G["ChatFrame" .. i .. "Tab"])
        end
    end
end

---------------------------------------------------------------------------
-- ActiveChatFrame()
--   Best-effort guess at "the chat frame the user is currently looking
--   at." Falls back to ChatFrame1 if we can't tell. Used by the
--   /bazchat copy slash so it grabs the chat the user expects.
---------------------------------------------------------------------------

function addon:ActiveChatFrame()
    -- SELECTED_CHAT_FRAME is the canonical signal Blizzard uses for
    -- "what edit-box presses target." Falls back to ChatFrame1.
    return SELECTED_CHAT_FRAME or _G.ChatFrame1
end

---------------------------------------------------------------------------
-- GetChatLines(chatFrame, maxLines)
--   Returns the visible chat lines as an array of strings, oldest
--   first. Walks the message history via :GetMessageInfo / a manual
--   index sweep so the result matches what the user sees on screen.
--   Used by the Copy Chat module.
---------------------------------------------------------------------------

function addon:GetChatLines(chatFrame, maxLines)
    if not chatFrame or not chatFrame.GetNumMessages then return {} end
    local total = chatFrame:GetNumMessages() or 0
    if total == 0 then return {} end

    local startIdx = 1
    if maxLines and maxLines < total then
        startIdx = total - maxLines + 1
    end

    local out = {}
    for i = startIdx, total do
        local text = chatFrame:GetMessageInfo(i)
        if text then out[#out + 1] = text end
    end
    return out
end

---------------------------------------------------------------------------
-- StripColorCodes(s)
--   Turns a chat line into plain text: every escape sequence the client
--   can put in one, gone, with the words it was wrapping kept.
--
--   Colors were all this removed to begin with, which left the links and
--   textures behind - and an EditBox will not take a string with those
--   in it at all. Not truncate: refuse, silently, keeping nothing. That
--   is what an empty copy dialog with a character count under it was.
--
--   A link keeps its bracketed name, which is the readable half and the
--   only part worth pasting into a bug report. An inline texture has no
--   words in it, so it goes entirely. Anything left holding a bare pipe
--   is swept up at the end, because one stray escape loses the whole
--   line.
---------------------------------------------------------------------------

function addon:StripColorCodes(s)
    if type(s) ~= "string" then return "" end

    -- Colors: |cAARRGGBB ... |r
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")

    -- Hyperlinks: |Hitem:...|h[Iron Bar]|h -> [Iron Bar]
    s = s:gsub("|H.-|h(.-)|h", "%1")

    -- Inline art: textures |T...|t and atlases |A...|a
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")

    -- An escaped pipe means a literal one.
    s = s:gsub("||", "|")

    -- Whatever is left is a fragment of something malformed. Dropping it
    -- costs a character; keeping it costs the entire line.
    s = s:gsub("|", "")

    return s
end
