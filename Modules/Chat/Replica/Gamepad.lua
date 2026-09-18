-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Chat: the gamepad methods Blizzard's chat code expects
--
-- Blizzard's shared edit box calls four methods on whatever frame an edit
-- box belongs to:
--
--   ShouldDeactivateChatOnEditFocusLost -> chatFrame:IsGamepadMenuOpen()
--   OnEditFocusGained                   -> chatFrame:SetGamepadFocus()
--   OnEditFocusLost                     -> chatFrame:ClearGamepadFocus()
--   FCF_OnUpdate                        -> chatFrame:HasGamepadFocus()
--
-- All four live on FloatingChatFrameMixin, which their ChatFrame1 gets from
-- FloatingChatFrameTemplate. Ours are built from ChatFrameTemplate, so they
-- had none of them and sending a message threw.
--
-- Taking FloatingChatFrameMixin wholesale looks like the tidy answer and is
-- not. ChatFrameTemplate declares <OnLoad method="OnLoad"/>, so the mixin
-- replaces which OnLoad runs - and FloatingChatFrameMixin:OnLoad does
-- `tinsert(CHAT_FRAMES, self:GetName())` along with a pile of docking and
-- tab setup. Our windows joined Blizzard's list of floating chat frames,
-- FCF_OnUpdate began walking them sixty times a second, and reached for a
-- buttonFrame region our template has never had. Around 190 errors in a few
-- seconds, which on this client is most of the budget before it stops
-- reporting errors at all.
--
-- So: only the four methods, and nothing else. They answer the way a window
-- with no gamepad support should - it has no gamepad focus and no gamepad
-- menu - which is true, and leaves Blizzard's code to take the ordinary
-- branch every time.
--
-- Declared as an XML mixin rather than assigned from Lua so the client
-- applies it itself at CreateFrame time, and nothing of ours is written
-- onto a frame Blizzard reads afterwards.
--
-- Loaded before Chat.xml, because a mixin has to exist before the template
-- that names it.
---------------------------------------------------------------------------

-- luacheck: globals BazUIChatGamepadMixin
BazUIChatGamepadMixin = {}

function BazUIChatGamepadMixin:IsGamepadMenuOpen()
    return false
end

function BazUIChatGamepadMixin:HasGamepadFocus()
    return false
end

function BazUIChatGamepadMixin:SetGamepadFocus()
end

function BazUIChatGamepadMixin:ClearGamepadFocus()
end
