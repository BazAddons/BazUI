-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: Widget Factories
-- Each factory creates a UI widget and returns (frame, height).
-- Redesigned with larger fonts and cleaner styling.
---------------------------------------------------------------------------

local O = BazUI._Options

---------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------

local function CreateDescriptionWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    local font = opt.fontSize == "small" and O.SMALL_FONT or O.DESC_FONT
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(font)
    fs:SetPoint("TOPLEFT")
    fs:SetWidth(contentWidth)
    fs:SetJustifyH("LEFT")
    fs:SetText(opt.name or "")
    fs:SetTextColor(unpack(O.TEXT_DESC))
    fs:SetWordWrap(true)
    local h = fs:GetStringHeight() + 4
    frame:SetSize(contentWidth, h)
    return frame, h
end

---------------------------------------------------------------------------
-- Header
---------------------------------------------------------------------------

local function CreateHeaderWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(contentWidth, O.HEADER_HEIGHT)
    local text = frame:CreateFontString(nil, "OVERLAY", O.HEADER_FONT)
    text:SetPoint("LEFT", 0, 0)
    text:SetText(opt.name or "")
    text:SetTextColor(unpack(O.GOLD))
    if opt.name and opt.name ~= "" then
        local line = frame:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", text, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        line:SetColorTexture(unpack(O.HEADER_LINE))
    end
    return frame, O.HEADER_HEIGHT
end

---------------------------------------------------------------------------
-- Toggle (Checkbox)
---------------------------------------------------------------------------

local function CreateToggleWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 0, 0)
    cb:SetChecked(opt.get and opt.get() or false)
    cb:SetScript("OnClick", function(self)
        if opt.set then opt.set(nil, self:GetChecked()) end
    end)

    local label = frame:CreateFontString(nil, "OVERLAY", O.LABEL_FONT)
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(opt.name or "")

    local totalH = O.WIDGET_HEIGHT
    if opt.desc then
        local desc = frame:CreateFontString(nil, "OVERLAY", O.DESC_FONT)
        desc:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 28, -2)
        desc:SetWidth(contentWidth - 32)
        desc:SetJustifyH("LEFT")
        desc:SetText(opt.desc)
        desc:SetTextColor(unpack(O.TEXT_DESC))
        desc:SetWordWrap(true)
        totalH = totalH + desc:GetStringHeight() + 6
    end

    frame:SetSize(contentWidth, totalH)

    -- Dynamic disabled state
    frame:SetScript("OnShow", function()
        local disabled = O.IsDisabled(opt)
        cb:SetEnabled(not disabled)
        cb:SetChecked(opt.get and opt.get() or false)
        label:SetTextColor(disabled and 0.4 or 0.9, disabled and 0.4 or 0.9, disabled and 0.4 or 0.9)
    end)

    return frame, totalH
end

---------------------------------------------------------------------------
-- Range (Slider)
---------------------------------------------------------------------------

local function CreateRangeWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(contentWidth, 54)

    local label = frame:CreateFontString(nil, "OVERLAY", O.LABEL_FONT)
    label:SetPoint("TOPLEFT", 0, 0)

    local minVal = opt.min or 0
    local maxVal = opt.max or 100
    local step = opt.step or 1

    local function FormatValue(val)
        if opt.isPercent then return math.floor((val or 0) * 100) .. "%" end
        if opt.format then return string.format(opt.format, val or 0) end
        if step < 1 then return string.format("%.1f", val or 0) end
        return tostring(math.floor(val or 0))
    end

    local val = opt.get and opt.get() or minVal
    -- Label keeps the "name: value" format so a glance down the page
    -- reads naturally even when the editbox is collapsed/out of focus.
    label:SetText((opt.name or "") .. ": " .. FormatValue(val))

    -- Reserve right-edge space for the editable value box so the
    -- slider doesn't fight it for clicks. Width fits "100%" or 4 digits.
    local EDITBOX_W = 56

    local slider = CreateFrame("Frame", nil, frame, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("TOPLEFT", 0, -22)
    slider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -EDITBOX_W - 12, -22)
    -- 24px (was 20) gives a friendlier vertical hit area for the
    -- diamond thumb in MinimalSliderWithSteppersTemplate.
    slider:SetHeight(24)

    slider.Slider:SetMinMaxValues(minVal, maxVal)
    slider.Slider:SetValueStep(step)
    slider.Slider:SetObeyStepOnDrag(true)
    slider.Slider:SetValue(val)

    -- Click-anywhere-to-snap overlay.
    --
    -- MinimalSliderWithSteppersTemplate decides drag-vs-track-click by
    -- hit-testing the cursor against the thumb texture's exact rect.
    -- That rect is small (~16x16) and clicks landing on what visually
    -- looks like the thumb often miss it, getting routed as page-step
    -- clicks instead - so the slider feels ungrabbable on long ranges.
    --
    -- This invisible button covers the entire trough. Mouse-down sets
    -- the slider value to the cursor's fractional position, then
    -- OnUpdate keeps tracking the cursor until release. Net effect:
    -- click anywhere -> snap there + drag from there, like every
    -- modern slider widget. Steppers (slider.Back / slider.Forward)
    -- live outside the overlay's bounds and keep working.
    local overlay = CreateFrame("Button", nil, slider.Slider)
    overlay:SetAllPoints()
    overlay:RegisterForClicks("LeftButtonDown", "LeftButtonUp")

    local dragging = false
    local function ValueAtCursor()
        local cx = GetCursorPosition() / overlay:GetEffectiveScale()
        local left = overlay:GetLeft() or 0
        local width = overlay:GetWidth() or 1
        local frac = (cx - left) / width
        if frac < 0 then frac = 0 end
        if frac > 1 then frac = 1 end
        return minVal + frac * (maxVal - minVal)
    end

    overlay:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        dragging = true
        slider.Slider:SetValue(ValueAtCursor())
        self:SetScript("OnUpdate", function()
            if dragging then slider.Slider:SetValue(ValueAtCursor()) end
        end)
    end)
    overlay:SetScript("OnMouseUp", function(self)
        if not dragging then return end
        dragging = false
        self:SetScript("OnUpdate", nil)
        -- Commit the final value. OnValueChanged below skips opt.set
        -- while `dragging` is true, so the setter fires exactly once
        -- per drag here on release - important for setters with
        -- expensive side effects (Categories.Reorder rebuilds the bag).
        if opt.set then
            local v = math.floor(slider.Slider:GetValue() / step + 0.5) * step
            opt.set(nil, v)
        end
    end)
    overlay:SetScript("OnHide", function(self)
        dragging = false
        self:SetScript("OnUpdate", nil)
    end)

    -- Editable value box on the right. Bypasses slider precision for
    -- ranges where the user knows the exact value they want (e.g.
    -- Order = 36). Slider OnValueChanged keeps the box in sync; the
    -- box's commit writes through SetValue so the standard set()
    -- chain fires from one place only.
    local valueBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    valueBox:SetPoint("LEFT", slider, "RIGHT", 16, 0)
    valueBox:SetSize(EDITBOX_W - 8, 22)
    valueBox:SetAutoFocus(false)
    valueBox:SetJustifyH("CENTER")
    valueBox:SetText(FormatValue(val))

    -- OnValueChanged updates the visual surfaces (label + editbox) on
    -- every change for live feedback. opt.set is suppressed while a
    -- drag is in progress - overlay's OnMouseUp commits exactly once
    -- on release. Stepper buttons and the editbox commit via direct
    -- SetValue calls outside any drag, so this branch fires opt.set
    -- for them as before.
    --
    -- opt.live = true overrides the suppression: the setter fires on
    -- every drag tick, for callers (e.g. the BazBars flyout config
    -- form) that drive a live preview off the slider value.
    slider.Slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        label:SetText((opt.name or "") .. ": " .. FormatValue(value))
        valueBox:SetText(FormatValue(value))
        if (not dragging or opt.live) and opt.set then
            opt.set(nil, value)
        end
    end)

    -- EditBox commit on Enter: parse, clamp, snap to step, write
    -- through the slider so a single OnValueChanged path handles all
    -- updates. Strips a trailing % so percent ranges accept "75%" or
    -- "75". Empty / non-numeric input reverts to the slider's value.
    valueBox:SetScript("OnEnterPressed", function(self)
        local raw = self:GetText():gsub("%%", "")
        local n = tonumber(raw)
        if n then
            if opt.isPercent then n = n / 100 end
            if n < minVal then n = minVal end
            if n > maxVal then n = maxVal end
            n = math.floor(n / step + 0.5) * step
            slider.Slider:SetValue(n)
        else
            self:SetText(FormatValue(slider.Slider:GetValue()))
        end
        self:ClearFocus()
    end)
    valueBox:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatValue(slider.Slider:GetValue()))
        self:ClearFocus()
    end)

    -- Disabled state
    frame:SetScript("OnShow", function()
        local disabled = O.IsDisabled(opt)
        slider.Slider:SetEnabled(not disabled)
        slider.Back:SetEnabled(not disabled)
        slider.Forward:SetEnabled(not disabled)
        valueBox:SetEnabled(not disabled)
        label:SetTextColor(disabled and 0.4 or 0.9, disabled and 0.4 or 0.9, disabled and 0.4 or 0.9)
        local v = opt.get and opt.get() or minVal
        slider.Slider:SetValue(v)
        label:SetText((opt.name or "") .. ": " .. FormatValue(v))
        valueBox:SetText(FormatValue(v))
    end)

    return frame, 54
end

---------------------------------------------------------------------------
-- Input (EditBox)
---------------------------------------------------------------------------

local function CreateInputWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(contentWidth, 50)

    local label = frame:CreateFontString(nil, "OVERLAY", O.LABEL_FONT)
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(opt.name or "")

    local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", 0, -20)
    editBox:SetSize(math.min(contentWidth, 400), 22)
    editBox:SetAutoFocus(false)
    editBox:SetText(opt.get and opt.get() or "")
    editBox:SetScript("OnEnterPressed", function(self)
        if opt.set then opt.set(nil, self:GetText()) end
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(opt.get and opt.get() or "")
        self:ClearFocus()
    end)

    return frame, 50
end

---------------------------------------------------------------------------
-- Execute (Button)
---------------------------------------------------------------------------

local function CreateExecuteWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    local isHalf = (opt.width == "half")
    local borderless = opt.borderless
    frame:SetSize(contentWidth, O.WIDGET_HEIGHT + 4)
    local btnWidth = isHalf and contentWidth or math.min(260, contentWidth)
    -- Use if/else; the `and/or` ternary breaks when the true value is nil
    local template
    if borderless then
        template = nil
    else
        template = "UIPanelButtonTemplate"
    end
    local btn = CreateFrame("Button", nil, frame, template)
    btn:SetPoint("LEFT", 0, 0)
    btn:SetSize(btnWidth, O.WIDGET_HEIGHT)
    if borderless then
        -- Static display: just a centered label, no hover, not clickable
        btn:EnableMouse(false)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        btn.label:SetPoint("CENTER")
        btn.label:SetText(opt.name or "")
    else
        btn:SetText(opt.name or "Execute")
    end

    btn:SetScript("OnClick", function()
        if opt.confirm then
            -- Route through BazUI:Confirm so the popup matches the rest
            -- of the BazUI UI (same fonts, buttons, backdrop). The
            -- caller can opt into a destructive (red) accept button by
            -- setting confirmStyle = "destructive" on the option entry,
            -- or pass confirmAcceptLabel / confirmCancelLabel for custom
            -- button text. Defaults preserve the old "Yes / No" feel.
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
                -- Pre-Popup BazUI (089-): silently fall through to the
                -- action so the click isn't lost. Should never trigger
                -- in practice since this file ships in the same package.
                opt.func()
            end
        else
            if opt.func then opt.func() end
        end
    end)

    if opt.desc then
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(opt.desc, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Disabled state
    frame:SetScript("OnShow", function()
        btn:SetEnabled(not O.IsDisabled(opt))
    end)

    return frame, O.WIDGET_HEIGHT + 4
end

---------------------------------------------------------------------------
-- Select (Dropdown)
---------------------------------------------------------------------------

local function CreateSelectWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(contentWidth, 54)

    local label = frame:CreateFontString(nil, "OVERLAY", O.LABEL_FONT)
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(opt.name or "")

    -- WowStyle1DropdownTemplate is the modern Blizzard dropdown widget
    -- (chevron arrow on the right, bordered box, checkmark on the
    -- selected item via SetupMenu/CreateRadio). Same template the Edit
    -- Mode framework uses, so dropdowns look identical across the
    -- Options page and Edit Mode popups.
    local btn = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    btn:SetPoint("TOPLEFT", 0, -22)

    -- Measuring FontString for sizing the dropdown to the widest value
    -- so labels never get clipped. Hidden so it doesn't render.
    local probe = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    probe:Hide()

    local function GetValues()
        local v = opt.values
        if type(v) == "function" then v = v() end
        return v or {}
    end

    -- Size the dropdown to the WIDEST value text plus chrome padding.
    -- 36 px accounts for the template's left padding + the chevron
    -- arrow on the right; clamped to contentWidth as the absolute
    -- upper bound and 100 px as a sensible lower bound.
    local MIN_W = 100
    local PADDING = 36
    local function ResizeToFitLongest()
        local values = GetValues()
        local maxW = MIN_W
        for _, v in pairs(values) do
            probe:SetText(v)
            local w = probe:GetStringWidth() or 0
            if w > maxW then maxW = w end
        end
        local final = math.min(maxW + PADDING, contentWidth)
        btn:SetWidth(final)
    end

    local function UpdateLabel()
        local val = opt.get and opt.get()
        local values = GetValues()
        btn:SetDefaultText(values[val] or val or "Select...")
    end

    -- The dropdown menu itself is built lazily on each open via
    -- SetupMenu's callback. CreateRadio gives the modern checkmark-on-
    -- selected-row appearance instead of a flat clickable list.
    btn:SetupMenu(function(dropdown, rootDescription)
        local values = GetValues()
        local currentVal = opt.get and opt.get()
        for k, v in pairs(values) do
            rootDescription:CreateRadio(
                v,
                function() return currentVal == k end,
                function()
                    if opt.set then opt.set(nil, k) end
                    UpdateLabel()
                end
            )
        end
    end)

    UpdateLabel()
    ResizeToFitLongest()

    frame:SetScript("OnShow", function()
        UpdateLabel()
        ResizeToFitLongest()
        if O.IsDisabled(opt) then
            btn:Disable()
        else
            btn:Enable()
        end
    end)

    return frame, 54
end

---------------------------------------------------------------------------
-- Factory Registry
---------------------------------------------------------------------------

O.widgetFactories = {
    description = CreateDescriptionWidget,
    header      = CreateHeaderWidget,
    toggle      = CreateToggleWidget,
    range       = CreateRangeWidget,
    input       = CreateInputWidget,
    execute     = CreateExecuteWidget,
    select      = CreateSelectWidget,
}
