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
--   Removes Blizzard's |cAARRGGBB ... |r color sequences from a
--   string. Useful when copying chat to plain text and you want a
--   cleaner result without the embedded escape codes.
---------------------------------------------------------------------------

function addon:StripColorCodes(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    return s
end
