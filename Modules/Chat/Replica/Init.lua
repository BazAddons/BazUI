-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: Init
--
-- Bootstraps the replica chat system at PLAYER_LOGIN. Order:
--   1. Wait for PLAYER_LOGIN (chat frames are guaranteed to exist by
--      then, and BazUIDB has loaded).
--   2. Hide Blizzard's default chat windows so we don't double-render
--      everything in two places.
--   3. Create our first replica window (BazChatWindow1).
--   4. Start the event router so messages flow into it.
--
-- A separate /reload restores the user's chat exactly as Blizzard
-- left it (Restore() in HideDefault.lua) so disabling the replica
-- never feels destructive.
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

local Replica = {}
addon.Replica = Replica

local started = false

function Replica:Start()
    if started then return end

    -- 1. Hide Blizzard's default chat scaffolding so it doesn't
    --    visually overlap our window.
    if addon.HideDefault then addon.HideDefault:Apply() end

    -- 1a. Install the chat-history capture hook (idempotent). This
    --     hooks SendChatMessage so every line the user sends gets
    --     appended to BazUIDB.profile.typedHistory. Safe to call
    --     before windows are created - the hook just appends.
    if addon.History then addon.History:Install() end

    -- 1c. Install global chat filters (suppresses other players'
    --     tradeskill / opening proximity broadcasts so the Loot tab
    --     doesn't flood with "Player creates X" spam in cities).
    if addon.Channels and addon.Channels.InstallFilters then
        addon.Channels:InstallFilters()
    end

    -- 1b. Force-claim ChatFrameUtil.OpenChat (the modern-WoW
    --     replacement for the old ChatFrame_OpenChat). Pressing
    --     Enter / Slash fires this; Blizzard's default logic
    --     chooses an editbox via ChatFrameUtil.ChooseBoxForSend.
    --     Even with our DEFAULT_CHAT_FRAME claim, that chain can
    --     return a stale hidden editbox (e.g. ChatFrame1's pre-
    --     hide one). Hooking AFTER the original runs lets us
    --     re-activate our window-1 editbox if some other editbox
    --     got picked.
    -- Singleton-guard against duplicate hook installs across /reload.
    -- `addon` is a fresh table every load so a flag on it is nil
    -- post-reload; the hook would then stack on top of the previous
    -- session's still-attached hook, and on each subsequent press of
    -- "/" you'd get one SetText("/") call per stacked hook - which is
    -- exactly the "//" bug reported. Storing the flag on the
    -- Blizzard-side ChatFrameUtil table (which persists across
    -- /reload) keeps the install idempotent forever in this session.
    if not (ChatFrameUtil and ChatFrameUtil._bazChatOpenChatHooked)
       and ChatFrameUtil and type(ChatFrameUtil.OpenChat) == "function"
    then
        ChatFrameUtil._bazChatOpenChatHooked = true
        hooksecurefunc(ChatFrameUtil, "OpenChat",
            function(text, chatFrame, desiredCursorPosition)
                -- If Blizzard targeted a specific chat frame,
                -- respect that. Otherwise force ours.
                if chatFrame ~= nil then return end
                local w = addon.Window and addon.Window:Get(1)
                if not w or not w.editBox then return end

                -- Don't call SetText ourselves. Blizzard's OpenChat
                -- already stamped editbox.text + editbox.setText = 1
                -- on whichever editbox ChooseBoxForSend returned, and
                -- ChatFrameEditBoxMixin:OnUpdate applies that exactly
                -- once on the next frame. Any extra SetText we layer
                -- on top of that path lands on top of the OnChar
                -- delivery from the literal "/" keypress (which fires
                -- when our editbox gains focus mid-press), producing
                -- "//". Letting Blizzard's deferred path own the
                -- application keeps the SetText timing in sync with
                -- the keypress consumption. We just have to make sure
                -- the deferred state lives on OUR editbox, not on a
                -- different one ChooseBoxForSend may have picked.
                if ACTIVE_CHAT_EDIT_BOX == w.editBox then
                    return -- Blizzard picked ours; nothing to do
                end

                local prevActive = ACTIVE_CHAT_EDIT_BOX
                ChatEdit_ActivateChat(w.editBox)

                -- Move the deferred-text state from the editbox
                -- Blizzard had picked over to ours, then clear the
                -- previous one so its OnUpdate doesn't also fire a
                -- SetText next frame.
                if text then
                    w.editBox.text = text
                    w.editBox.setText = 1
                    w.editBox.desiredCursorPosition = desiredCursorPosition or #text
                end
                if prevActive then
                    prevActive.text = nil
                    prevActive.setText = 0
                end
            end)
    end

    -- 2. Create every chat window defined in the profile. Defaults
    --    ship General / Guild / Trade / Log; users add and remove
    --    tabs from the strip "+" button or the BazChat-Tabs page.
    if addon.Window then
        addon.Window:CreateAll()
        -- Restore popped windows + their geometry. Runs after
        -- CreateAll so the chat frames + tab strips exist by the
        -- time we re-anchor them to their popped containers.
        if addon.Window.RestorePoppedStates then
            addon.Window:RestorePoppedStates()
        end
    end

    -- 3. Hijack Blizzard's combat log: point _G.COMBATLOG at our Log
    --    window and reparent CombatLogQuickButtonFrame so the formatted
    --    output, filter presets (My actions / What happened to me?),
    --    and Additional Filters dropdown all surface on our tab. Their
    --    CombatLogDriverMixin keeps doing the heavy lifting (parsing
    --    COMBAT_LOG_EVENT_UNFILTERED + applying the filter settings);
    --    we just redirect the AddMessage destination.
    if addon.CombatLog and addon.CombatLog.Apply then
        addon.CombatLog:Apply()
    end

    started = true
end

function Replica:Stop()
    if not started then return end
    if addon.HideDefault then addon.HideDefault:Restore() end
    started = false
end

function Replica:IsRunning() return started end

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------

BazUI:QueueForModule("Chat", function()
    if not addon.core then return end
    if not addon.core:GetSetting("enabled") then return end
    Replica:Start()
end)
