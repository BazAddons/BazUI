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
    BazUI.Skin.Theme.ApplyDialog(f)
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
    local x = BazUI.Skin.Theme.CreateCloseButton(f)
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

    -- Said out loud rather than left to creation order. These two are
    -- siblings, and which one covers the other decided whether the text
    -- was visible at all - a dark panel drawn over the viewport looks
    -- exactly like an empty box.
    local base = f:GetFrameLevel() or 1
    editBg:SetFrameLevel(base)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT",     editBg, "TOPLEFT",      6, -6)
    scroll:SetPoint("BOTTOMRIGHT", editBg, "BOTTOMRIGHT", -6,  6)
    scroll:SetFrameLevel(base + 2)
    scroll:EnableMouseWheel(true)
    f.scroll = scroll

    local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT",     scroll, "TOPRIGHT",    4, 0)
    scrollBar:SetPoint("BOTTOMLEFT",  scroll, "BOTTOMRIGHT", 4, 0)
    scrollBar:SetFrameLevel(base + 3)
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
    -- A real ceiling rather than 0. Zero is supposed to mean "no limit",
    -- and Blizzard's own code never passes it - every call site in the
    -- client names a number. A chat export runs to a few tens of
    -- thousands of characters, so this is a ceiling nothing will reach.
    editBox:SetMaxLetters(1000000)
    editBox:SetFontObject("ChatFontNormal")
    -- The font object belongs to the chat, whose colour is whatever the
    -- last thing to draw with it left behind. This box is for reading
    -- back what you are about to copy, so it says white itself.
    editBox:SetTextColor(1, 1, 1)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", close)
    scroll:SetScrollChild(editBox)
    -- Re-highlight on focus so a fresh copy flow stays one-step.
    editBox:SetScript("OnEditFocusGained", function(self)
        if currentOpts and currentOpts._autoHighlight then
            self:HighlightText()
        end
    end)
    -- Read-only is not disabled. A disabled EditBox cannot hold focus,
    -- and a box with no focus never sees Ctrl+C - the keystroke falls
    -- through to the game, and C opens the character sheet. So a
    -- read-only box stays live and simply puts back what it was given
    -- whenever a keystroke changes it.
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and currentOpts and currentOpts._readOnly
            and self:GetText() ~= (currentOpts.content or "") then
            self:SetText(currentOpts.content or "")
            self:HighlightText()
        end
    end)
    f.editBox = editBox

    -- Bottom buttons + status row
    f.selectAllBtn = BazUI.Skin.Theme.CreateButton(f)
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

    f.acceptBtn = BazUI.Skin.Theme.CreateButton(f)
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

    f.closeBtn = BazUI.Skin.Theme.CreateButton(f)
    f.closeBtn:SetSize(100, 24)
    f.closeBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    f.closeBtn:SetText("Close")
    f.closeBtn:SetScript("OnClick", close)

    f.stats = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.stats:SetPoint("BOTTOMLEFT", 16, 38)
    f.stats:SetTextColor(0.55, 0.55, 0.55)

    -- ESC closes without putting us on UISpecialFrames, which taints
    -- Blizzard's panel manager when it walks that list.
    BazUI.CloseOnEscape(f)

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

-- Give the EditBox a height.
--
-- A ScrollFrame's child has to have a size, and this one only ever had a
-- width: nothing set its height, so it was nothing tall. That draws
-- exactly what we were looking at - the cursor sits at the insertion
-- point and every line of text has no room to be in.
--
-- Measured from the content, generously. A wrapped line takes more room
-- than the newline count knows about, and spare height costs only a
-- little empty scroll range while too little costs the text.
local function SizeEditBoxToContent(f, content)
    local _, fontH = f.editBox:GetFont()
    fontH = (tonumber(fontH) or 12) + 2

    -- string.char(10) rather than an escape, so the newline being counted
    -- cannot be eaten by whatever edits this file next.
    local newline = string.char(10)
    local _, lines = (content or ""):gsub(newline, newline)
    lines = (lines or 0) + 1

    local viewport = f.scroll:GetHeight() or 0
    f.editBox:SetHeight(math.max(viewport, (lines * 2 + 4) * fontH))
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

    -- Always enabled, so it can be focused and copied from; read-only is
    -- enforced by the OnTextChanged handler putting the content back.
    dialog.editBox:SetEnabled(true)
    opts._readOnly = (opts.editable == false)

    -- A font of our own rather than the chat's ChatFontNormal. A core
    -- dialog should not depend on a font object another module owns and
    -- repoints, and an EditBox with no usable font cannot hold text at
    -- all. Theme.FontFile falls back to the client's own face when ours
    -- is not loadable, so this is always something real.
    local fontFile = BazUI.Skin.Theme.FontFile()
    if fontFile then
        dialog.editBox:SetFont(fontFile, 13, "")
    end

    -- Content (multi-line)
    dialog.editBox:SetText(opts.content or "")

    -- Read it back. An EditBox can refuse text without saying so, and it
    -- refuses the whole string rather than trimming it: one stray escape
    -- sequence anywhere in a chat export and the box stays empty with a
    -- character count underneath it promising thousands. Better it says
    -- so than leaves somebody staring at a blank panel.
    local wanted = #(opts.content or "")
    local kept   = #(dialog.editBox:GetText() or "")
    if kept ~= wanted then
        BazUI:Print(("|cffff8800Copy dialog kept %d of %d characters.|r")
            :format(kept, wanted))
    end

    -- After the text, since the height comes from it.
    SizeEditBoxToContent(dialog, opts.content)

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

