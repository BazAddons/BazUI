-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: CopyChat
--
-- Adds a small copy-icon button to each chat frame's top-right corner.
-- Clicking it (or running /bc copy / /bcc) opens BazUI:OpenCopyDialog
-- with the chat's visible history pre-selected for Ctrl+A / Ctrl+C.
-- WoW's chat isn't natively selectable, so the universal idiom is
-- "show the lines in an EditBox the user can copy out of."
--
-- Public API:
--   addon.CopyChat:Wire(chatFrame)        -- attach the button
--   addon.CopyChat:OpenForFrame(frame)    -- open dialog for a specific frame
--   addon.CopyChat:OpenForActive()        -- open dialog for the current tab
--   BazChat:OpenCopyForActiveFrame()      -- back-compat for /bc copy slash
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace
local BazChat = addon.API             -- module API (the old BazChat global)

local CopyChat = {}
addon.CopyChat = CopyChat

local buttons = {}  -- [chatFrame] = button

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function FormatLines(lines, stripColors)
    if not lines or #lines == 0 then return "" end
    local out = {}
    for i, line in ipairs(lines) do
        out[i] = stripColors and addon:StripColorCodes(line) or line
    end
    return table.concat(out, "\n")
end

local function ActiveFrame()
    local idx = (addon.Window and addon.Window.GetActiveWindowIdx
                 and addon.Window:GetActiveWindowIdx()) or 1
    return addon.Window and addon.Window:Get(idx), idx
end

---------------------------------------------------------------------------
-- Public: open the dialog
---------------------------------------------------------------------------

function CopyChat:OpenForFrame(chatFrame)
    chatFrame = chatFrame or ActiveFrame()
    if not chatFrame then return end

    -- Pull up to 500 lines (covers the largest history buffer the user
    -- can configure; smaller buffers just yield fewer lines).
    local lines = addon:GetChatLines(chatFrame, 500)
    -- Strip Blizzard color codes by default - they paste as garbage in
    -- most editors. Future opt-in could expose a "keep colors" toggle.
    local content = FormatLines(lines, true)

    if not BazUI.OpenCopyDialog then
        if addon.core then
            addon.core:Print(
                "|cffff8800BazUI:OpenCopyDialog not available|r")
        end
        return
    end

    local label = chatFrame.name or ("Tab " .. (chatFrame:GetID() or "?"))
    BazUI:OpenCopyDialog({
        title    = "Chat Export - " .. label,
        subtitle = string.format(
            "%d line(s) from this tab. Ctrl+A then Ctrl+C to copy.",
            #lines),
        content  = content,
    })
end

function CopyChat:OpenForActive()
    self:OpenForFrame(ActiveFrame())
end

-- Back-compat: legacy /bc copy slash + any external addon hooking
-- BazChat:OpenCopyForActiveFrame.
function BazChat:OpenCopyForActiveFrame()
    return CopyChat:OpenForActive()
end

---------------------------------------------------------------------------
-- Per-frame button
---------------------------------------------------------------------------

local function CreateButton(chatFrame)
    if buttons[chatFrame] then return buttons[chatFrame] end

    -- Anchor to the chrome wrapper if available so the icon sits on
    -- the gold border at the top-right corner; falls back to the chat
    -- frame itself if the chrome layer isn't built.
    local anchor = chatFrame._bcChromeFrame or chatFrame

    local btn = CreateFrame("Button", nil, anchor)
    btn:SetSize(14, 14)
    btn:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -8, -8)
    btn:SetFrameLevel((anchor:GetFrameLevel() or 0) + 5)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    tex:SetVertexColor(1, 1, 1, 0.40)
    btn.tex = tex

    btn:SetScript("OnEnter", function(self)
        self.tex:SetVertexColor(1, 0.82, 0, 1)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Copy chat", 1, 0.82, 0)
            GameTooltip:AddLine("Click to open the chat in a copy dialog.",
                0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.tex:SetVertexColor(1, 1, 1, 0.40)
        if GameTooltip then GameTooltip:Hide() end
    end)
    btn:SetScript("OnClick", function()
        CopyChat:OpenForFrame(chatFrame)
    end)

    buttons[chatFrame] = btn
    return btn
end

---------------------------------------------------------------------------
-- :Wire — call once per chat frame from Window:Create
---------------------------------------------------------------------------

function CopyChat:Wire(chatFrame)
    if not chatFrame then return end
    CreateButton(chatFrame)
end
