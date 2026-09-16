-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: Widget Factories
--
-- One form language for every settings page, sized for the Options
-- panel's canvas (about 665 px wide at the default window size):
--
--   Label                                     [control]
--   description in small muted text
--
-- Every control row is `contentWidth` wide, O.ROW_H tall (O.ROW_DESC_H
-- with a description), label on the left, control right-aligned at a
-- fixed width from O.CTRL_W / O.INPUT_W / O.VALUE_W. Section headers
-- are a gold title with a rule. Each factory returns (frame, height).
---------------------------------------------------------------------------

local O = BazUI._Options

local function Color(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

-- Row scaffold: label (and optional description) on the left, a control
-- anchor on the right. Returns frame, label, height, controlWidth.
local function BuildRow(parent, opt, contentWidth, ctrlWidth)
    local frame = CreateFrame("Frame", nil, parent)
    local labelW = contentWidth - ctrlWidth - O.ROW_GAP - O.ROW_PAD * 2

    local label = frame:CreateFontString(nil, "OVERLAY", O.LABEL_FONT)
    label:SetPoint("TOPLEFT", O.ROW_PAD, -((O.ROW_H - 14) / 2))
    label:SetWidth(labelW)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(opt.name or "")
    Color(label, O.TEXT_NORMAL)
    frame.label = label

    local h = O.ROW_H
    if opt.desc and opt.desc ~= "" then
        local desc = frame:CreateFontString(nil, "OVERLAY", O.DESC_FONT)
        desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
        desc:SetWidth(labelW)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetText(opt.desc)
        Color(desc, O.TEXT_DESC)
        frame.desc = desc
        h = math.max(O.ROW_DESC_H, O.ROW_H - 4 + (desc:GetStringHeight() or 12) + 6)
    end
    frame:SetSize(contentWidth, h)

    frame.SetRowDisabled = function(self, disabled)
        Color(self.label, disabled and O.TEXT_DISABLED or O.TEXT_NORMAL)
        if self.desc then Color(self.desc, disabled and O.TEXT_DISABLED or O.TEXT_DESC) end
    end
    return frame, h
end

-- Control anchor: vertically centered on the first line of the row.
local function AnchorControl(frame, control, width, height)
    control:SetSize(width, height)
    control:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -O.ROW_PAD, -((O.ROW_H - height) / 2))
end

-- The scaffolding, for a page that needs a control this file does not
-- have. A widget built with these is the same row as every other one, so
-- it lines up with them rather than nearly lining up.
O.BuildRow       = BuildRow
O.AnchorControl  = AnchorControl

---------------------------------------------------------------------------
-- Text blocks
---------------------------------------------------------------------------

local function CreateDescriptionWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    local fs = frame:CreateFontString(nil, "OVERLAY", O.DESC_FONT)
    fs:SetPoint("TOPLEFT", O.ROW_PAD, -2)
    fs:SetWidth(contentWidth - O.ROW_PAD * 2)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(opt.name or opt.text or "")
    Color(fs, O.TEXT_DESC)
    local h = (fs:GetStringHeight() or 12) + 6
    frame:SetSize(contentWidth, h)
    return frame, h
end

-- Section title: small gold caps with a rule running to the right edge.
local function CreateHeaderWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(contentWidth, O.HEADER_HEIGHT)
    local text = frame:CreateFontString(nil, "OVERLAY", O.HEADER_FONT)
    text:SetPoint("BOTTOMLEFT", O.ROW_PAD, 5)
    text:SetText(opt.name or "")
    Color(text, O.GOLD)
    if opt.name and opt.name ~= "" then
        local line = frame:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", text, "RIGHT", 10, 0)
        line:SetPoint("RIGHT", frame, "RIGHT", -O.ROW_PAD, 0)
        line:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
        line:SetColorTexture(unpack(O.HEADER_LINE))
    end
    frame.isHeader = true
    return frame, O.HEADER_HEIGHT
end

---------------------------------------------------------------------------
-- Toggle
---------------------------------------------------------------------------

local function CreateToggleWidget(parent, opt, contentWidth)
    local frame, h = BuildRow(parent, opt, contentWidth, O.CHECK_W)
    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    AnchorControl(frame, cb, O.CHECK_W, O.CHECK_W)
    cb:SetChecked(opt.get and opt.get() or false)
    cb:SetScript("OnClick", function(self)
        if opt.set then opt.set(nil, self:GetChecked() and true or false) end
    end)
    -- Clicking the label toggles too.
    local hit = CreateFrame("Button", nil, frame)
    hit:SetPoint("TOPLEFT", 0, 0)
    hit:SetPoint("BOTTOMRIGHT", cb, "BOTTOMLEFT", 0, 0)
    hit:SetScript("OnClick", function()
        if cb:IsEnabled() then cb:Click() end
    end)
    frame:SetScript("OnShow", function(self)
        local disabled = O.IsDisabled(opt)
        cb:SetEnabled(not disabled)
        cb:SetChecked(opt.get and opt.get() or false)
        self:SetRowDisabled(disabled)
    end)
    return frame, h
end

---------------------------------------------------------------------------
-- Range (slider + value box)
---------------------------------------------------------------------------

local function CreateRangeWidget(parent, opt, contentWidth)
    local frame, h = BuildRow(parent, opt, contentWidth, O.CTRL_W)
    local minVal, maxVal, step = opt.min or 0, opt.max or 100, opt.step or 1

    local function FormatValue(val)
        val = val or 0
        if opt.isPercent then return math.floor(val * 100 + 0.5) .. "%" end
        if type(opt.format) == "function" then return opt.format(val) end
        if opt.format == "percent" then return math.floor(val * 100 + 0.5) .. "%" end
        if type(opt.format) == "string" then return string.format(opt.format, val) end
        if step < 1 then return string.format("%.1f", val) end
        return tostring(math.floor(val + 0.5))
    end

    local valueBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    valueBox:SetSize(O.VALUE_W, 20)
    valueBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -O.ROW_PAD, -((O.ROW_H - 20) / 2))
    valueBox:SetAutoFocus(false)
    valueBox:SetJustifyH("CENTER")
    valueBox:SetFontObject("GameFontHighlightSmall")

    local sliderW = O.CTRL_W - O.VALUE_W - 10
    local slider = CreateFrame("Frame", nil, frame, "MinimalSliderWithSteppersTemplate")
    slider:SetSize(sliderW, 20)
    slider:SetPoint("RIGHT", valueBox, "LEFT", -10, 0)

    local val = opt.get and opt.get() or minVal
    slider.Slider:SetMinMaxValues(minVal, maxVal)
    slider.Slider:SetValueStep(step)
    slider.Slider:SetObeyStepOnDrag(true)
    slider.Slider:SetValue(val)
    valueBox:SetText(FormatValue(val))

    -- Click anywhere on the track to jump there and keep dragging; the
    -- template only drags when the thumb itself is hit.
    local overlay = CreateFrame("Button", nil, slider.Slider)
    overlay:SetAllPoints()
    overlay:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    local dragging = false
    local function ValueAtCursor()
        local cx = GetCursorPosition() / overlay:GetEffectiveScale()
        local frac = (cx - (overlay:GetLeft() or 0)) / math.max(overlay:GetWidth() or 1, 1)
        frac = math.max(0, math.min(1, frac))
        return minVal + frac * (maxVal - minVal)
    end
    overlay:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or not slider.Slider:IsEnabled() then return end
        dragging = true
        slider.Slider:SetValue(ValueAtCursor())
        self:SetScript("OnUpdate", function() if dragging then slider.Slider:SetValue(ValueAtCursor()) end end)
    end)
    overlay:SetScript("OnMouseUp", function(self)
        if not dragging then return end
        dragging = false
        self:SetScript("OnUpdate", nil)
        if opt.set then
            opt.set(nil, math.floor(slider.Slider:GetValue() / step + 0.5) * step)
        end
    end)
    overlay:SetScript("OnHide", function(self) dragging = false; self:SetScript("OnUpdate", nil) end)

    slider.Slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        valueBox:SetText(FormatValue(value))
        if (not dragging or opt.live) and opt.set then opt.set(nil, value) end
    end)

    valueBox:SetScript("OnEnterPressed", function(self)
        local n = tonumber((self:GetText():gsub("%%", "")))
        if n then
            if opt.isPercent or opt.format == "percent" then n = n / 100 end
            n = math.max(minVal, math.min(maxVal, n))
            slider.Slider:SetValue(math.floor(n / step + 0.5) * step)
        else
            self:SetText(FormatValue(slider.Slider:GetValue()))
        end
        self:ClearFocus()
    end)
    valueBox:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatValue(slider.Slider:GetValue()))
        self:ClearFocus()
    end)

    frame:SetScript("OnShow", function(self)
        local disabled = O.IsDisabled(opt)
        slider.Slider:SetEnabled(not disabled)
        if slider.Back then slider.Back:SetEnabled(not disabled) end
        if slider.Forward then slider.Forward:SetEnabled(not disabled) end
        valueBox:SetEnabled(not disabled)
        self:SetRowDisabled(disabled)
        local v = opt.get and opt.get() or minVal
        slider.Slider:SetValue(v)
        valueBox:SetText(FormatValue(v))
    end)
    return frame, h
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------

local function CreateInputWidget(parent, opt, contentWidth)
    local frame, h = BuildRow(parent, opt, contentWidth, O.INPUT_W)
    local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    AnchorControl(frame, editBox, O.INPUT_W - 8, 20)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetText(opt.get and opt.get() or "")
    editBox:SetScript("OnEnterPressed", function(self)
        if opt.set then opt.set(nil, self:GetText()) end
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(opt.get and opt.get() or "")
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        if opt.commitOnFocusLost ~= false and opt.set then opt.set(nil, self:GetText()) end
    end)
    frame:SetScript("OnShow", function(self)
        local disabled = O.IsDisabled(opt)
        editBox:SetEnabled(not disabled)
        editBox:SetText(opt.get and opt.get() or "")
        self:SetRowDisabled(disabled)
    end)
    return frame, h
end

---------------------------------------------------------------------------
-- Execute (button)
---------------------------------------------------------------------------

local function CreateExecuteWidget(parent, opt, contentWidth)
    -- The label doubles as the button text when there's no separate
    -- description, so the row doesn't say the same thing twice.
    local rowOpt = { name = opt.desc and opt.name or "", desc = opt.desc }
    local btnText = opt.name or "Run"
    local probe = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    probe:SetText(btnText)
    local btnW = math.max(O.BUTTON_MIN_W, math.min(O.BUTTON_MAX_W, (probe:GetStringWidth() or 60) + 28))
    probe:Hide()

    local frame, h = BuildRow(parent, rowOpt, contentWidth, btnW)
    if rowOpt.name == "" then frame.label:SetText("") end
    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    AnchorControl(frame, btn, btnW, 22)
    btn:SetText(btnText)
    local fs = btn:GetFontString()
    if fs then fs:SetFontObject("GameFontHighlightSmall") end
    local danger = opt.style == "danger" or opt.confirmStyle == "destructive"
        or (type(opt.name) == "string" and opt.name:find("|cffff4444", 1, true))
    if danger and fs then
        fs:SetText((opt.name or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        fs:SetTextColor(1, 0.45, 0.45)
    end
    -- Left-align the button when the row has no label of its own, so a
    -- lone action reads as part of the form rather than floating right.
    if rowOpt.name == "" and not opt.alignRight then
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", O.ROW_PAD, -((O.ROW_H - 22) / 2))
    end

    btn:SetScript("OnClick", function()
        if opt.confirm then
            if BazUI.Confirm then
                BazUI:Confirm({
                    title       = opt.confirmTitle or "Confirm",
                    body        = opt.confirmText  or "Are you sure?",
                    acceptLabel = opt.confirmAcceptLabel or "Yes",
                    cancelLabel = opt.confirmCancelLabel or "No",
                    acceptStyle = opt.confirmStyle or "primary",
                    onAccept    = function() if opt.func then opt.func() end end,
                })
            elseif opt.func then
                opt.func()
            end
        elseif opt.func then
            opt.func()
        end
    end)
    if opt.desc and rowOpt.name == "" then
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(opt.desc, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    frame:SetScript("OnShow", function(self)
        local disabled = O.IsDisabled(opt)
        btn:SetEnabled(not disabled)
        self:SetRowDisabled(disabled)
    end)
    return frame, h
end

---------------------------------------------------------------------------
-- Select (dropdown)
---------------------------------------------------------------------------

local function GetValues(opt)
    local v = opt.values
    if type(v) == "function" then v = v() end
    return v or {}
end

-- Values render sorted by label unless the table carries `sorting`
-- (an array of keys) the way AceConfig allows.
local function OrderedKeys(opt, values)
    if type(opt.sorting) == "table" then return opt.sorting end
    local keys = {}
    for k in pairs(values) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(values[a]) < tostring(values[b]) end)
    return keys
end

local function CreateSelectWidget(parent, opt, contentWidth)
    local values = GetValues(opt)
    -- Fixed 180, widening to 240 only when a value needs it.
    local probe = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local longest = 0
    for _, v in pairs(values) do
        probe:SetText(tostring(v))
        longest = math.max(longest, probe:GetStringWidth() or 0)
    end
    probe:Hide()
    local ddW = math.max(O.CTRL_W, math.min(O.CTRL_MAX_W, longest + 40))

    local frame, h = BuildRow(parent, opt, contentWidth, ddW)
    local btn = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    AnchorControl(frame, btn, ddW, 22)

    local function UpdateLabel()
        local vals = GetValues(opt)
        local val = opt.get and opt.get()
        btn:SetDefaultText(vals[val] or (val ~= nil and tostring(val)) or "Select...")
    end
    btn:SetupMenu(function(_, rootDescription)
        local vals = GetValues(opt)
        local current = opt.get and opt.get()
        for _, k in ipairs(OrderedKeys(opt, vals)) do
            local key = k
            rootDescription:CreateRadio(tostring(vals[key]),
                function() return current == key end,
                function()
                    if opt.set then opt.set(nil, key) end
                    UpdateLabel()
                end)
        end
    end)
    UpdateLabel()
    frame:SetScript("OnShow", function(self)
        UpdateLabel()
        local disabled = O.IsDisabled(opt)
        if disabled then btn:Disable() else btn:Enable() end
        self:SetRowDisabled(disabled)
    end)
    return frame, h
end

---------------------------------------------------------------------------
-- Registry

---------------------------------------------------------------------------
-- Flags: one row, several small labeled checkboxes
--
-- For a setting that is not one yes-or-no but a handful of independent
-- ones that belong together, where splitting them into a row each would
-- bury the thing they describe. Notifications uses it to say where an
-- event goes: the panel, a toast, the chat box, any combination.
--
--   opt.flags = { { label = "Toast", get = fn, set = fn }, ... }
---------------------------------------------------------------------------

local FLAG_GAP = 10

local function CreateFlagsWidget(parent, opt, contentWidth)
    local flags = opt.flags or {}

    -- Measure the labels so the row reserves what it actually needs.
    local probe = parent:CreateFontString(nil, "OVERLAY", O.DESC_FONT)
    local widths, total = {}, 0
    for i, flag in ipairs(flags) do
        probe:SetText(flag.label or "")
        local w = math.ceil(probe:GetStringWidth() or 0)
        widths[i] = w
        total = total + w + O.CHECK_W + 2 + FLAG_GAP
    end
    probe:Hide()
    total = math.max(total - FLAG_GAP, O.CHECK_W)

    local frame, h = BuildRow(parent, opt, contentWidth, total)
    frame.checks = {}

    local x = -O.ROW_PAD
    for i = #flags, 1, -1 do
        local flag = flags[i]

        local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        cb:SetSize(O.CHECK_W, O.CHECK_W)
        cb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", x, -((O.ROW_H - O.CHECK_W) / 2))
        cb:SetScript("OnClick", function(self)
            if flag.set then flag.set(nil, self:GetChecked() and true or false) end
        end)

        local text = frame:CreateFontString(nil, "OVERLAY", O.DESC_FONT)
        text:SetPoint("RIGHT", cb, "LEFT", -2, 0)
        text:SetText(flag.label or "")
        Color(text, O.TEXT_DESC)

        cb._label = text
        cb._flag  = flag
        -- Set now as well as in OnShow: a row built into an already
        -- visible page never receives an OnShow, and would sit there
        -- reading unchecked whatever the setting says.
        cb:SetChecked(flag.get and flag.get() or false)
        frame.checks[#frame.checks + 1] = cb

        x = x - (O.CHECK_W + 2 + widths[i] + FLAG_GAP)
    end

    frame:SetScript("OnShow", function(self)
        local disabled = O.IsDisabled(opt)
        for _, cb in ipairs(self.checks) do
            cb:SetEnabled(not disabled)
            cb:SetChecked(cb._flag.get and cb._flag.get() or false)
            Color(cb._label, disabled and O.TEXT_DISABLED or O.TEXT_DESC)
        end
        self:SetRowDisabled(disabled)
    end)
    return frame, h
end

---------------------------------------------------------------------------
-- Color
--
-- A swatch with its hex beside it, opening the game's own color picker.
--
-- get() answers four numbers and set() is handed four, rather than a
-- table: every color in this addon is already { r, g, b, a } and a widget
-- that traded in tables would have to guess whether it had been given one
-- of those or one of the game's { r = , g = , b = }. Both are accepted
-- coming back from get(), since a caller handing over one of its own
-- tables is the obvious thing to do.
--
-- The swatch and the picker are separate from the row, because the Skin
-- tab needs both inside a row of its own making.
---------------------------------------------------------------------------

local SWATCH_W = 44
local SWATCH_H = 16
local HEX_W    = 60

-- A button showing a color, over a light half and a dark half so a low
-- alpha reads as see-through rather than as a darker color.
function O.CreateSwatch(parent, width, height)
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(width or SWATCH_W, height or SWATCH_H)

    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(unpack(O.HEADER_LINE))

    local light = swatch:CreateTexture(nil, "BACKGROUND", nil, 1)
    light:SetPoint("TOPLEFT")
    light:SetPoint("BOTTOMRIGHT", swatch, "BOTTOM", 0, 0)
    light:SetColorTexture(0.65, 0.65, 0.65, 1)

    local dark = swatch:CreateTexture(nil, "BACKGROUND", nil, 1)
    dark:SetPoint("TOPLEFT", swatch, "TOP", 0, 0)
    dark:SetPoint("BOTTOMRIGHT")
    dark:SetColorTexture(0.15, 0.15, 0.15, 1)

    local fill = swatch:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    swatch.fill = fill

    function swatch:SetColor(r, g, b, a)
        fill:SetColorTexture(r or 1, g or 1, b or 1, a or 1)
    end

    return swatch
end

-- One place that knows how to drive the game's color picker: it reports a
-- new color as it is dragged and the original if it is cancelled, so a
-- caller only has to say what to do with a color.
function O.OpenColorPicker(r, g, b, a, hasAlpha, onChange)
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
    local wasR, wasG, wasB, wasA = r or 1, g or 1, b or 1, a or 1

    local function Commit()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = wasA
        if hasAlpha then
            -- The picker calls it opacity and counts the other way.
            local opacity = ColorPickerFrame.GetColorAlpha
                and ColorPickerFrame:GetColorAlpha() or 0
            na = 1 - opacity
        end
        onChange(nr, ng, nb, na)
    end

    ColorPickerFrame:SetupColorPickerAndShow({
        r = wasR, g = wasG, b = wasB,
        opacity     = 1 - wasA,
        hasOpacity  = hasAlpha and true or false,
        swatchFunc  = Commit,
        opacityFunc = Commit,
        cancelFunc  = function() onChange(wasR, wasG, wasB, wasA) end,
    })
end

local function CreateColorWidget(parent, opt, contentWidth)
    local ctrlWidth = HEX_W + 6 + SWATCH_W
    local frame, h = BuildRow(parent, opt, contentWidth, ctrlWidth)

    local box = CreateFrame("Frame", nil, frame)
    AnchorControl(frame, box, ctrlWidth, SWATCH_H)

    local hex = box:CreateFontString(nil, "OVERLAY", O.DESC_FONT)
    hex:SetPoint("LEFT", box, "LEFT", 0, 0)
    hex:SetWidth(HEX_W)
    hex:SetJustifyH("RIGHT")
    Color(hex, O.TEXT_DESC)

    local swatch = O.CreateSwatch(box, SWATCH_W, SWATCH_H)
    swatch:SetPoint("RIGHT", box, "RIGHT", 0, 0)

    local function Read()
        if not opt.get then return 1, 1, 1, 1 end
        local r, g, b, a = opt.get(opt)
        if type(r) == "table" then
            local c = r
            r, g, b, a = c[1] or c.r, c[2] or c.g, c[3] or c.b, c[4] or c.a
        end
        return r or 1, g or 1, b or 1, a or 1
    end

    local function Refresh()
        local r, g, b, a = Read()
        swatch:SetColor(r, g, b, a)
        hex:SetText(("#%02X%02X%02X"):format(r * 255, g * 255, b * 255))
    end

    swatch:SetScript("OnClick", function()
        local r, g, b, a = Read()
        O.OpenColorPicker(r, g, b, a, opt.hasAlpha, function(nr, ng, nb, na)
            if opt.set then opt.set(opt, nr, ng, nb, na) end
            Refresh()
        end)
    end)

    frame:SetScript("OnShow", function(self)
        local disabled = O.IsDisabled(opt)
        swatch:SetEnabled(not disabled)
        swatch:SetAlpha(disabled and 0.4 or 1)
        self:SetRowDisabled(disabled)
        Refresh()
    end)
    Refresh()

    return frame, h
end

---------------------------------------------------------------------------

O.widgetFactories = {
    description = CreateDescriptionWidget,
    header      = CreateHeaderWidget,
    toggle      = CreateToggleWidget,
    range       = CreateRangeWidget,
    slider      = CreateRangeWidget,
    input       = CreateInputWidget,
    execute     = CreateExecuteWidget,
    select      = CreateSelectWidget,
    flags       = CreateFlagsWidget,
    color       = CreateColorWidget,
}
