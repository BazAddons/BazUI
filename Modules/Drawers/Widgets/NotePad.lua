-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Note Pad
--
-- Persistent text editor for personal notes. Saved per character.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_notepad"
local DESIGN_WIDTH = 220
local DESIGN_HEIGHT = 140
local PAD          = 8

local NoteWidget = {}
local frame

local function GetNote()
    return addon:GetWidgetSetting(WIDGET_ID, "text", "") or ""
end

local function SetNote(text)
    addon:SetWidgetSetting(WIDGET_ID, "text", text or "")
end

function NoteWidget:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", "BazUIDrawerNotePad", UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- Subtle backdrop for the text area
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetPoint("TOPLEFT", PAD, -PAD)
    f.bg:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.6)

    -- Border
    f.border = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.border:SetPoint("TOPLEFT", PAD - 1, -PAD + 1)
    f.border:SetPoint("BOTTOMRIGHT", -PAD + 1, PAD - 1)
    BazUI.Skin.Theme.ApplyFlatPanel(f.border, { 0, 0, 0, 0 }, BazUI.Skin.Theme.colors.edge)

    -- Scroll frame for the edit box
    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", PAD + 4, -PAD - 4)
    f.scroll:SetPoint("BOTTOMRIGHT", -PAD - 22, PAD + 4)

    f.editBox = CreateFrame("EditBox", nil, f.scroll)
    f.editBox:SetMultiLine(true)
    f.editBox:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontHighlight"))
    f.editBox:SetWidth(f.scroll:GetWidth() - 8)
    f.editBox:SetAutoFocus(false)
    f.editBox:SetMaxLetters(2000)
    f.editBox:SetText(GetNote())
    f.editBox:SetTextInsets(2, 2, 2, 2)
    f.editBox:SetScript("OnTextChanged", function(self)
        SetNote(self:GetText())
    end)
    f.editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.scroll:SetScrollChild(f.editBox)

    -- Resize editbox with scroll
    f.scroll:SetScript("OnSizeChanged", function(self, w)
        f.editBox:SetWidth(w - 8)
    end)

    frame = f
    return f
end

function NoteWidget:GetDesiredHeight() return DESIGN_HEIGHT end

function NoteWidget:GetStatusText()
    local text = GetNote()
    local len = #text
    if len == 0 then return "empty", 0.6, 0.6, 0.6 end
    return len .. " chars", 0.7, 0.7, 0.7
end

function NoteWidget:Init()
    local f = self:Build()
    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Note Pad",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return NoteWidget:GetDesiredHeight() end,
        GetStatusText    = function() return NoteWidget:GetStatusText() end,
    })
end

BazUI:QueueForLogin(function() NoteWidget:Init() end)
