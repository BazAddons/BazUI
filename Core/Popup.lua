-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Popup
--
-- Generic popup primitive for the Baz Suite. Replaces the Blizzard
-- StaticPopupDialogs spamming + hand-rolled BackdropTemplate frames
-- that every addon ends up writing for confirm/info/form dialogs.
--
-- Layout (auto-sized; width fixed, height grows to fit content):
--   ┌────────────────────────────────┐
--   │ Title                        X │   gold header + close
--   │                                │
--   │ Body text (wraps to width)     │   optional
--   │                                │
--   │ [Field 1]                      │   optional form fields,
--   │ [Field 2]                      │   built via O.widgetFactories
--   │                                │
--   │       [Cancel]   [Accept]      │   right-aligned buttons
--   └────────────────────────────────┘
--
-- Visual primitives match the rest of BazUI - UIPanelButtonTemplate,
-- InputBoxTemplate, UICheckButtonTemplate, the
-- the shared flat chrome with DIALOG_BG/DIALOG_BORDER colors, fonts
-- from O.HEADER_FONT/O.LABEL_FONT - so popups feel native to the
-- BazUI options window, not bolted on.
--
-- Public API:
--   BazUI:OpenPopup(opts) -> popup frame
--   BazUI:ClosePopup()
--   BazUI:Confirm(opts)        -- thin wrapper for confirm dialogs
--   BazUI:Alert(opts)          -- thin wrapper for info dialogs
--
-- See doc-comments on each public function below for opts shapes.
---------------------------------------------------------------------------

BazUI = BazUI or {}

local O = BazUI._Options
local DEFAULT_WIDTH  = 360
local TITLE_HEIGHT   = 32
local BODY_LINE_GAP  = 6
local BUTTON_HEIGHT  = 26
local BUTTON_GAP     = 8
local BUTTON_MIN_W   = 80
local BUTTON_PAD_X   = 24

local popup            -- singleton frame (built on first call)
local currentOpts      -- active opts table (cleared on close)
local fieldFrames      -- array of { frame, height, key, type } for current popup
local buttonFrames     -- array of created button frames for current popup

---------------------------------------------------------------------------
-- Color helpers — apply per-button-style coloring without touching
-- the underlying Blizzard template chrome.
---------------------------------------------------------------------------

local STYLE_COLORS = {
    default     = nil,                       -- the plain white the face carries
    primary     = { 1.00, 0.82, 0.00 },      -- BazUI gold
    destructive = { 1.00, 0.40, 0.40 },      -- soft red
}

-- Through the button's font objects rather than its font string: a
-- button puts its own object back whenever its state changes, and takes
-- the object's color with it, so a tinted string lasts until the first
-- hover and no longer.
local function ApplyButtonStyle(btn, style)
    if not btn or not style then return end
    BazUI.Skin.Theme.SetButtonFont(btn, nil, STYLE_COLORS[style])
end

---------------------------------------------------------------------------
-- Field state — values flow through state.values[key], which the
-- field-factory get/set closures read and write. Buttons receive a
-- snapshot of state.values at click time.
---------------------------------------------------------------------------

local function MakeFieldOpt(field, state)
    local key = field.key
    if state.values[key] == nil and field.default ~= nil then
        state.values[key] = field.default
    end
    local opt = {
        type = field.type,
        name = field.label,
        desc = field.desc,
        get  = function() return state.values[key] end,
        set  = function(_, v) state.values[key] = v end,
    }
    if field.type == "input" then
        -- nothing extra
    elseif field.type == "toggle" then
        if state.values[key] == nil then state.values[key] = false end
    elseif field.type == "select" then
        opt.values = field.values
    elseif field.type == "range" then
        opt.min  = field.min
        opt.max  = field.max
        opt.step = field.step
        opt.format = field.format
        opt.isPercent = field.isPercent
        opt.live = field.live  -- fire setter on every drag tick when true
    end
    return opt
end

---------------------------------------------------------------------------
-- Singleton creation
---------------------------------------------------------------------------

local function CloseHandler()
    if not popup then return end
    if currentOpts and currentOpts.onClose then
        local cb = currentOpts.onClose
        currentOpts = nil
        popup:Hide()
        cb()
    else
        currentOpts = nil
        popup:Hide()
    end
end

local function CreatePopupFrame()
    local f = CreateFrame("Frame", "BazUIPopup", UIParent, "BackdropTemplate")
    -- FULLSCREEN_DIALOG sits above DIALOG strata, so this confirm /
    -- alert popup reliably renders on top of any DIALOG-level UI like
    -- BazUI's Edit Mode settings panel or BazUI's standalone
    -- Options window. At plain DIALOG strata both frames tied at the
    -- same FrameLevel and render order was order-of-creation, which
    -- meant the popup backdrop landed BEHIND the Edit Mode panel
    -- while the popup's children (buttons, text) rendered in front -
    -- a half-and-half visual that looks broken.
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    -- DIALOG_* tones rather than the inline PANEL_* tones - this is a
    -- floating dialog so the border needs to read clearly against
    -- arbitrary game content behind it, and the bg should be solid
    -- enough to feel modal rather than translucent over the world.
    BazUI.Skin.Theme.ApplyDialog(f, O.DIALOG_BG)
    f:SetPoint("CENTER")
    f:Hide()

    -- Title (gold, top-left)
    f.title = f:CreateFontString(nil, "OVERLAY", O.HEADER_FONT)
    f.title:SetPoint("TOPLEFT", O.PAD, -O.PAD)
    f.title:SetTextColor(unpack(O.GOLD))

    -- Close X (top-right)
    local x = BazUI.Skin.Theme.CreateCloseButton(f)
    x:SetPoint("TOPRIGHT", 0, 0)
    x:SetScript("OnClick", CloseHandler)
    f.closeX = x

    -- Body text (multi-line, word-wrapped)
    f.body = f:CreateFontString(nil, "OVERLAY", O.LABEL_FONT)
    f.body:SetPoint("TOPLEFT",  O.PAD, -(O.PAD + TITLE_HEIGHT))
    f.body:SetPoint("TOPRIGHT", -O.PAD, -(O.PAD + TITLE_HEIGHT))
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    f.body:SetWordWrap(true)
    f.body:SetTextColor(unpack(O.TEXT_NORMAL))

    -- Field area (children added per-show, anchored under body)
    f.fieldArea = CreateFrame("Frame", nil, f)
    -- Sized + positioned in ApplyOpts after the body height is known.

    -- ESC closes without putting us on UISpecialFrames, which taints
    -- Blizzard's panel manager when it walks that list.
    BazUI.CloseOnEscape(f)

    return f
end

---------------------------------------------------------------------------
-- ApplyOpts — wire the singleton with the new opts and re-layout.
---------------------------------------------------------------------------

local function ClearPreviousFields(f)
    if fieldFrames then
        for _, ff in ipairs(fieldFrames) do
            if ff.frame and ff.frame.Hide then ff.frame:Hide() end
            if ff.frame and ff.frame.SetParent then ff.frame:SetParent(nil) end
        end
    end
    fieldFrames = {}
end

local function ClearPreviousButtons(f)
    if buttonFrames then
        for _, btn in ipairs(buttonFrames) do
            if btn and btn.Hide then btn:Hide() end
            if btn and btn.SetParent then btn:SetParent(nil) end
        end
    end
    buttonFrames = {}
end

local function ApplyOpts(opts)
    local f = popup
    local width = opts.width or DEFAULT_WIDTH

    f.title:SetText(opts.title or "")

    -- Body text (or hidden when empty)
    if opts.body and opts.body ~= "" then
        f.body:SetText(opts.body)
        f.body:Show()
    else
        f.body:SetText("")
        f.body:Hide()
    end

    -- The state table threads field values through every get/set
    -- closure. Pre-seed with field defaults; button onClick callbacks
    -- receive the live values at click time.
    local state = { values = {} }
    f._bcState = state

    ClearPreviousFields(f)
    ClearPreviousButtons(f)

    local contentWidth = width - O.PAD * 2

    -- Position cursor below body (or directly under title if no body)
    f.body:SetWidth(contentWidth)
    local bodyHeight = f.body:IsShown() and (f.body:GetStringHeight() or 0) or 0
    local fieldsTopY = O.PAD + TITLE_HEIGHT
        + (bodyHeight > 0 and (bodyHeight + BODY_LINE_GAP) or 0)

    -- Build fields via O.widgetFactories so they look identical to the
    -- input controls on Options pages.
    local fieldsHeight = 0
    if opts.fields and #opts.fields > 0 then
        f.fieldArea:ClearAllPoints()
        f.fieldArea:SetPoint("TOPLEFT", O.PAD, -fieldsTopY)
        f.fieldArea:SetWidth(contentWidth)

        local y = 0
        for _, field in ipairs(opts.fields) do
            local factory = O.widgetFactories and O.widgetFactories[field.type]
            if factory then
                local widget, h = factory(f.fieldArea, MakeFieldOpt(field, state),
                    contentWidth)
                widget:SetPoint("TOPLEFT", 0, -y)
                widget:Show()
                fieldFrames[#fieldFrames + 1] = {
                    frame = widget, height = h, key = field.key,
                }
                y = y + (h or O.WIDGET_HEIGHT) + O.SPACING
            end
        end
        fieldsHeight = y
        f.fieldArea:SetHeight(math.max(fieldsHeight, 1))
        f.fieldArea:Show()
    else
        f.fieldArea:Hide()
    end

    -- Buttons row (right-aligned). Built last so we know the popup
    -- height before anchoring them at the bottom.
    local buttons = opts.buttons or {}
    if #buttons == 0 then
        -- Auto-add a single OK button when none specified, so the popup
        -- is always dismissable without relying on the X.
        buttons = { { label = "OK", style = "primary",
                      onClick = function() end } }
    end

    local buttonsTopY = O.PAD + TITLE_HEIGHT
        + (bodyHeight > 0 and (bodyHeight + BODY_LINE_GAP) or 0)
        + (fieldsHeight > 0 and (fieldsHeight + O.SPACING) or 0)
        + O.SPACING
    -- The popup height is buttonsTopY + button height + padding.
    local popupHeight = buttonsTopY + BUTTON_HEIGHT + O.PAD

    -- Right-anchor buttons in reverse order so the FIRST entry in the
    -- opts.buttons array sits leftmost (visual reading order matches
    -- the array order).
    local rightCursor = -O.PAD
    for i = #buttons, 1, -1 do
        local def = buttons[i]
        local btn = BazUI.Skin.Theme.CreateButton(f)
        btn:SetHeight(BUTTON_HEIGHT)
        btn:SetText(def.label or "OK")
        local autoW = (btn:GetTextWidth() or 40) + BUTTON_PAD_X
        btn:SetWidth(math.max(autoW, BUTTON_MIN_W))
        btn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", rightCursor, O.PAD)
        ApplyButtonStyle(btn, def.style)
        local cb = def.onClick
        btn:SetScript("OnClick", function()
            local values = f._bcState and f._bcState.values or {}
            -- Close BEFORE invoking the callback so the callback can
            -- safely call OpenPopup again (chained confirms etc.)
            -- without our singleton fighting itself.
            local cb2  = cb
            local opts2 = currentOpts
            currentOpts = nil
            f:Hide()
            if cb2 then cb2(values, f) end
            if opts2 and opts2.onClose then opts2.onClose() end
        end)
        buttonFrames[#buttonFrames + 1] = btn
        rightCursor = rightCursor - btn:GetWidth() - BUTTON_GAP
    end

    f:SetSize(width, popupHeight)
end

---------------------------------------------------------------------------
-- Public: BazUI:OpenPopup(opts)
--
-- opts (table):
--   title         string                title text (gold)
--   body          string?               optional body text (wraps)
--   fields        table?                optional form fields. each:
--                                         { type = "input"|"toggle"|"select"|"range",
--                                           key, label, desc?,
--                                           default?, values? (select),
--                                           min/max/step? (range), ... }
--   buttons       table?                optional button defs. each:
--                                         { label, style?, onClick? }
--                                       style: "default"|"primary"|"destructive"
--                                       onClick: function(values, popup)
--                                       Default = single "OK" primary.
--   width         number?               popup width (default 360, height auto)
--   onClose       function?             fires on ANY close path
---------------------------------------------------------------------------

function BazUI:OpenPopup(opts)
    opts = opts or {}
    if not popup then popup = CreatePopupFrame() end
    currentOpts = opts
    ApplyOpts(opts)
    popup:Show()
    popup:Raise()
    return popup
end

function BazUI:ClosePopup()
    if popup and popup:IsShown() then
        CloseHandler()
    end
end

---------------------------------------------------------------------------
-- Public: BazUI:Confirm(opts)
--
-- Thin wrapper for two-button confirm dialogs. Translates to the
-- canonical OpenPopup shape.
--
-- opts:
--   title         string            (required)
--   body          string?
--   acceptLabel   string?           default "OK"
--   acceptStyle   string?           default "primary"
--   cancelLabel   string?           default "Cancel"
--   onAccept      function?
--   onCancel      function?
---------------------------------------------------------------------------

function BazUI:Confirm(opts)
    opts = opts or {}
    return self:OpenPopup({
        title = opts.title,
        body  = opts.body,
        width = opts.width,
        buttons = {
            { label   = opts.cancelLabel or "Cancel",
              style   = "default",
              onClick = function() if opts.onCancel then opts.onCancel() end end },
            { label   = opts.acceptLabel or "OK",
              style   = opts.acceptStyle or "primary",
              onClick = function() if opts.onAccept then opts.onAccept() end end },
        },
    })
end

---------------------------------------------------------------------------
-- Public: BazUI:Alert(opts)
--
-- Thin wrapper for single-button info dialogs.
--
-- opts:
--   title         string            (required)
--   body          string?
--   acceptLabel   string?           default "OK"
--   onAccept      function?
---------------------------------------------------------------------------

function BazUI:Alert(opts)
    opts = opts or {}
    return self:OpenPopup({
        title = opts.title,
        body  = opts.body,
        width = opts.width,
        buttons = {
            { label   = opts.acceptLabel or "OK",
              style   = "primary",
              onClick = function() if opts.onAccept then opts.onAccept() end end },
        },
    })
end

---------------------------------------------------------------------------
-- Public: BazUI:PromptReload(reason)
--
-- Some settings cannot take effect until the interface is rebuilt. The
-- honest thing is to say so at the moment the setting is changed, and to
-- offer the reload rather than leaving the player to find the command.
--
-- Reasons collect: flip three such settings and you are asked once, with
-- all three listed, because being asked three times is worse than not
-- being asked at all. The prompt is not modal and Later simply closes
-- it; the setting is already saved either way, and will apply on the
-- next reload whenever that happens.
---------------------------------------------------------------------------

local reloadReasons = {}
local reloadPending = false

-- Ask for a reload, and say so if the game will not have it.
--
-- ReloadUI is a protected call. On clients that enforce that - Forever
-- does - an addon asking for it is refused, the screen prints "Interface
-- action failed because of an AddOn", and our button appears to do
-- nothing. There is no unprotected way to reload from an addon, so the
-- honest thing is to ask and then own up.
--
-- If the reload happens we are gone long before the timer; if we are
-- still here half a second later, it was refused.
function BazUI:RequestReload()
    ReloadUI()
    C_Timer.After(0.5, function()
        BazUI:Print("The game would not let an addon reload for you. Type |cff00ff00/reload|r.")
    end)
end

function BazUI:PromptReload(reason)
    if reason and reason ~= "" then
        for _, existing in ipairs(reloadReasons) do
            if existing == reason then reason = nil break end
        end
        if reason then reloadReasons[#reloadReasons + 1] = reason end
    end
    if reloadPending then return end
    reloadPending = true

    -- One frame's grace, so a change that writes several settings at
    -- once gathers them into a single question.
    C_Timer.After(0, function()
        reloadPending = false
        local body = "These need the interface reloaded before they take effect:"
        for _, r in ipairs(reloadReasons) do
            body = body .. "|n|cffd9c7a0" .. r .. "|r"
        end
        if #reloadReasons == 0 then
            body = "This needs the interface reloaded before it takes effect."
        end
        wipe(reloadReasons)

        BazUI:OpenPopup({
            title = "Reload needed",
            body  = body,
            buttons = {
                { label = "Later", style = "default" },
                { label = "Reload now", style = "primary",
                  onClick = function() BazUI:RequestReload() end },
            },
        })
    end)
end
