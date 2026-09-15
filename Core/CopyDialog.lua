-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: CopyDialog
--
-- Reusable scrollable text-export / text-import popup for any Baz addon
-- (or any addon depending on BazUI). WoW's sandbox can't write to or
-- read from a real OS clipboard, so the standard idiom is "show a frame
-- with an EditBox the user can Ctrl+A / Ctrl+C / Ctrl+V on." This
-- module bundles that frame + the niceties (Select All button, ESC
-- close, drag-to-move, character count) in one shared instance.
--
-- Public API:
--   BazUI:OpenCopyDialog(opts) -> frame
--
-- opts = {
--   title       = "...",          -- required, big gold text at top
--   subtitle    = "...",          -- optional small gray instruction line
--
--   content     = "...",          -- pre-fill text. For export, the data
--                                 -- you want the user to copy. For import,
--                                 -- pass nil/"" to start with an empty box.
--
--   editable    = true|false,     -- defaults to true. Even export-only
--                                 -- dialogs keep this true so the user
--                                 -- can edit before copying if desired
--                                 -- (the text is discarded on close).
--
--   width       = number,         -- default 640
--   height      = number,         -- default 460
--
--   onAccept    = function(text)  -- if set, an Accept button appears next
--                 end,            -- to Close. Clicking it (or Enter on
--                                 -- single-line) calls this with the
--                                 -- current EditBox text. Use this for
--                                 -- import flows where you need the
--                                 -- pasted content back.
--   acceptText  = "Import",       -- default "Accept"; ignored without onAccept
--
--   onClose     = function() end, -- optional; fired when the dialog hides
-- }
--
-- Returns the dialog frame. The same frame is reused across every call
-- (mirrors Blizzard's StaticPopup pattern); the latest opts win.
---------------------------------------------------------------------------

BazUI = BazUI or {}

local DEFAULT_W = 640
local DEFAULT_H = 460

local dialog
local currentOpts

local function HookClose(f)
    local function Close()
        f:Hide()
        if currentOpts and currentOpts.onClose then
            local cb = currentOpts.onClose
            currentOpts = nil
            cb()
        else
            currentOpts = nil
        end
    end
    f._close = Close
    return Close
end

local function CreateDialog()
    local f = CreateFrame("Frame", "BazUICopyDialog", UIParent, "BackdropTemplate")
    f:SetSize(DEFAULT_W, DEFAULT_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    BazUI.Skin.Theme.ApplyFlatPanel(f)
    f:Hide()

    local close = HookClose(f)

    -- Title + subtitle
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.title:SetTextColor(1, 0.82, 0)

    f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
    f.subtitle:SetTextColor(0.75, 0.75, 0.75)

    -- Top-right close X
    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", 0, 0)
    x:SetScript("OnClick", close)

    -- Scrollable EditBox using the same MinimalScrollBar pattern the
    -- Options window / list-detail / User Manual panels use - so the
    -- copy dialog visually matches the rest of the BazUI UI rather
    -- than the chunky stock UIPanelScrollFrameTemplate look.
    --
    -- IMPORTANT: the EditBox is the DIRECT scroll child (not wrapped in
    -- a backdrop frame). When a multi-line EditBox sits inside an
    -- intermediate scroll-child frame, WoW's selection highlight
    -- rectangles desync from the visible text under ScrollUtil-driven
    -- scrolling - the highlight bands stay parked at their original
    -- y-positions while the text scrolls past underneath. Putting the
    -- EditBox as the scroll child directly keeps the highlight glued
    -- to the text. The backdrop visual is drawn on a sibling frame
    -- BEHIND the scroll viewport.
    local editBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    editBg:SetPoint("TOPLEFT", 16, -56)
    editBg:SetPoint("BOTTOMRIGHT", -22, 50)
    BazUI.Skin.Theme.ApplyFlatPanel(editBg, { 0.03, 0.03, 0.05, 0.6 }, BazUI.Skin.Theme.colors.edge)
    f.editBg = editBg

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT",     editBg, "TOPLEFT",      6, -6)
    scroll:SetPoint("BOTTOMRIGHT", editBg, "BOTTOMRIGHT", -6,  6)
    scroll:EnableMouseWheel(true)
    f.scroll = scroll

    local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT",     scroll, "TOPRIGHT",    4, 0)
    scrollBar:SetPoint("BOTTOMLEFT",  scroll, "BOTTOMRIGHT", 4, 0)
    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)
        BazUI.Skin.Theme.AutoFadeScrollBar(scrollBar, scroll)
    end
    f.scrollBar = scrollBar

    -- EditBox is the scroll child directly. Width is set in ApplySize;
    -- height auto-grows with multi-line content so the ScrollFrame's
    -- scroll range matches the actual text extent.
    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(0)              -- 0 = unlimited
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", close)
    scroll:SetScrollChild(editBox)
    -- Re-highlight on focus so a fresh copy flow stays one-step.
    editBox:SetScript("OnEditFocusGained", function(self)
        if currentOpts and currentOpts._autoHighlight then
            self:HighlightText()
        end
    end)
    f.editBox = editBox

    -- Bottom buttons + status row
    f.selectAllBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.selectAllBtn:SetSize(110, 24)
    f.selectAllBtn:SetPoint("BOTTOMLEFT", 16, 14)
    f.selectAllBtn:SetText("Select All")
    f.selectAllBtn:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("LEFT", f.selectAllBtn, "RIGHT", 12, 0)
    f.hint:SetTextColor(0.7, 0.7, 0.7)

    f.acceptBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.acceptBtn:SetSize(100, 24)
    f.acceptBtn:Hide()
    f.acceptBtn:SetScript("OnClick", function()
        if currentOpts and currentOpts.onAccept then
            local text = editBox:GetText()
            local cb = currentOpts.onAccept
            currentOpts = nil
            f:Hide()
            cb(text)
        end
    end)

    f.closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.closeBtn:SetSize(100, 24)
    f.closeBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    f.closeBtn:SetText("Close")
    f.closeBtn:SetScript("OnClick", close)

    f.stats = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.stats:SetPoint("BOTTOMLEFT", 16, 38)
    f.stats:SetTextColor(0.55, 0.55, 0.55)

    -- ESC closes via UISpecialFrames.
    table.insert(UISpecialFrames, "BazUICopyDialog")

    return f
end

-- Resize the dialog and recompute the EditBox width so word-wrap fits
-- the new viewport. The EditBox auto-grows in height with content, so
-- nothing else needs explicit sizing. Insets:
--   editBg: TOPLEFT 16, -56  /  BOTTOMRIGHT -22, 50
--   scroll: 6px inside editBg on every side
--   editBox width = scroll viewport (= dialog w - 16 - 22 - 6 - 6 = w - 50)
local function ApplySize(f, w, h)
    f:SetSize(w, h)
    f.editBox:SetWidth(w - 50)
end

function BazUI:OpenCopyDialog(opts)
    opts = opts or {}
    if not dialog then dialog = CreateDialog() end

    local w = opts.width  or DEFAULT_W
    local h = opts.height or DEFAULT_H
    ApplySize(dialog, w, h)

    -- Title / subtitle
    dialog.title:SetText(opts.title or "Copy / Paste")
    dialog.subtitle:SetText(opts.subtitle or "")

    -- Content (multi-line)
    dialog.editBox:SetText(opts.content or "")

    -- Editability: default true so the EditBox accepts focus + selection;
    -- callers wanting a read-only feel can pass false.
    if opts.editable == false then
        dialog.editBox:SetEnabled(false)
    else
        dialog.editBox:SetEnabled(true)
    end

    -- Accept button (only shown when caller wires onAccept)
    if opts.onAccept then
        dialog.acceptBtn:SetText(opts.acceptText or "Accept")
        dialog.acceptBtn:ClearAllPoints()
        dialog.acceptBtn:SetPoint("RIGHT", dialog.closeBtn, "LEFT", -8, 0)
        dialog.acceptBtn:Show()
        dialog.closeBtn:SetText("Cancel")
        dialog.hint:SetText("")
    else
        dialog.acceptBtn:Hide()
        dialog.closeBtn:SetText("Close")
        dialog.hint:SetText("then press |cffffd700Ctrl+C|r to copy")
    end

    -- Stats line: character count + caller-supplied stat string if any
    local statsText
    if opts.stats then
        statsText = opts.stats
    else
        local n = #(opts.content or "")
        statsText = string.format("%d characters", n)
    end
    dialog.stats:SetText(statsText)

    currentOpts = opts
    -- Auto-highlight only for export (content pre-filled, no onAccept).
    -- For import flows the user is pasting INTO an empty box, so
    -- highlighting nothing on focus is the right default.
    currentOpts._autoHighlight = (opts.onAccept == nil) and (#(opts.content or "") > 0)

    dialog:Show()
    dialog:Raise()
    dialog.editBox:SetFocus()
    if currentOpts._autoHighlight then
        dialog.editBox:HighlightText()
    end

    return dialog
end

