-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: EditMode Module
-- Full Edit Mode framework for Baz Suite addons
-- Provides Blizzard-native overlays, grid snapping, selection management,
-- and a configurable settings popup for any registered frame.
---------------------------------------------------------------------------

local registeredFrames = {} -- [frame] = config
local isEditMode = false
local selectedFrame = nil

local pairs, ipairs, math = pairs, ipairs, math
local CreateFrame = CreateFrame
local UIParent = UIParent
local GameTooltip = GameTooltip
local GameTooltip_Hide = GameTooltip_Hide
local NineSliceUtil = NineSliceUtil

---------------------------------------------------------------------------
-- Nine-Slice Layout (matches Blizzard EditModeSystemSelectionLayout)
---------------------------------------------------------------------------

local EditModeNineSliceLayout = {
    ["TopRightCorner"]    = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
    ["TopLeftCorner"]     = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
    ["BottomLeftCorner"]  = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
    ["BottomRightCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
    ["TopEdge"]    = { atlas = "_%s-NineSlice-EdgeTop" },
    ["BottomEdge"] = { atlas = "_%s-NineSlice-EdgeBottom" },
    ["LeftEdge"]   = { atlas = "!%s-NineSlice-EdgeLeft" },
    ["RightEdge"]  = { atlas = "!%s-NineSlice-EdgeRight" },
    ["Center"]     = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}

---------------------------------------------------------------------------
-- Grid Snap Preview Lines
---------------------------------------------------------------------------

local snapLineH, snapLineV

local function GetSnapLines()
    if not snapLineH then
        snapLineH = UIParent:CreateTexture(nil, "OVERLAY")
        snapLineH:SetColorTexture(0.8, 0, 0, 0.8)
        snapLineH:SetHeight(2)
        snapLineH:Hide()
    end
    if not snapLineV then
        snapLineV = UIParent:CreateTexture(nil, "OVERLAY")
        snapLineV:SetColorTexture(0.8, 0, 0, 0.8)
        snapLineV:SetWidth(2)
        snapLineV:Hide()
    end
    return snapLineH, snapLineV
end

local function ShowSnapPreview(frame)
    if not (EditModeManagerFrame and EditModeManagerFrame.Grid
        and EditModeManagerFrame.Grid:IsShown()
        and EditModeManagerFrame.Grid.gridSpacing) then
        return
    end

    local spacing = EditModeManagerFrame.Grid.gridSpacing
    local cx, cy = frame:GetCenter()
    local scale = frame:GetScale()
    if not (cx and cy and spacing > 0) then return end

    cx = cx * scale
    cy = cy * scale

    local gridCX, gridCY = EditModeManagerFrame.Grid:GetCenter()
    local relX = cx - gridCX
    local relY = cy - gridCY
    local snapX = gridCX + math.floor(relX / spacing + 0.5) * spacing
    local snapY = gridCY + math.floor(relY / spacing + 0.5) * spacing

    local hLine, vLine = GetSnapLines()

    hLine:ClearAllPoints()
    hLine:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, snapY)
    hLine:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, snapY)
    hLine:Show()

    vLine:ClearAllPoints()
    vLine:SetPoint("TOP", UIParent, "BOTTOMLEFT", snapX, UIParent:GetHeight())
    vLine:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", snapX, 0)
    vLine:Show()
end

local function HideSnapPreview()
    if snapLineH then snapLineH:Hide() end
    if snapLineV then snapLineV:Hide() end
end

---------------------------------------------------------------------------
-- Snap Frame to Grid
---------------------------------------------------------------------------

local function SnapToGrid(frame)
    if not (EditModeManagerFrame and EditModeManagerFrame.Grid
        and EditModeManagerFrame.Grid:IsShown()
        and EditModeManagerFrame.Grid.gridSpacing) then
        return
    end

    local spacing = EditModeManagerFrame.Grid.gridSpacing
    local cx, cy = frame:GetCenter()
    local scale = frame:GetScale()
    if not (cx and cy and spacing > 0) then return end

    cx = cx * scale
    cy = cy * scale

    local gridCX, gridCY = EditModeManagerFrame.Grid:GetCenter()
    local relX = cx - gridCX
    local relY = cy - gridCY
    local snapX = gridCX + math.floor(relX / spacing + 0.5) * spacing
    local snapY = gridCY + math.floor(relY / spacing + 0.5) * spacing

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", snapX / scale, snapY / scale)
end

---------------------------------------------------------------------------
-- Position Persistence
---------------------------------------------------------------------------

local function SavePosition(frame, config)
    if config.positionKey == false then
        -- Addon manages its own position
        if config.onPositionChanged then
            config.onPositionChanged(frame)
        end
        return
    end

    if config.addonName and config.positionKey then
        local cx, cy = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local es = frame:GetEffectiveScale()
        local ues = UIParent:GetEffectiveScale()
        local x = cx * es - ux * ues
        local y = cy * es - uy * ues
        local addonObj = BazUI:GetAddon(config.addonName)
        if addonObj then
            addonObj:SetSetting(config.positionKey, { x = x, y = y })
        end
    end

    if config.onPositionChanged then
        config.onPositionChanged(frame)
    end
end

---------------------------------------------------------------------------
-- Nudge
---------------------------------------------------------------------------

local function NudgeFrame(frame, dx, dy)
    local config = registeredFrames[frame]
    if not config then return end

    local es = frame:GetEffectiveScale()
    local cx, cy = frame:GetCenter()
    if not (cx and cy) then return end

    cx = cx * es + dx
    cy = cy * es + dy

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / es, cy / es)
    SavePosition(frame, config)
end

---------------------------------------------------------------------------
-- Overlay Creation (Nine-Slice with label and mouse interaction)
---------------------------------------------------------------------------

local function CreateEditOverlay(frame, config)
    local overlay = CreateFrame("Frame", nil, frame, "NineSliceCodeTemplate")
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(frame:GetFrameLevel() + 10)
    overlay.isSelected = false

    NineSliceUtil.ApplyLayout(overlay, EditModeNineSliceLayout, "editmode-actionbar-highlight")

    local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    label:SetPoint("CENTER")
    label:SetText("")
    label:Hide()
    overlay.label = label

    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")

    overlay:SetScript("OnDragStart", function(self)
        local parent = self:GetParent()
        parent:SetMovable(true)
        parent:StartMoving()
        parent.isDragging = true

        self:SetScript("OnUpdate", function()
            if parent.isDragging then
                ShowSnapPreview(parent)
            end
        end)
    end)

    overlay:SetScript("OnDragStop", function(self)
        local parent = self:GetParent()
        parent:StopMovingOrSizing()
        parent:SetMovable(false)
        parent.isDragging = false

        self:SetScript("OnUpdate", nil)
        HideSnapPreview()

        SnapToGrid(parent)
        SavePosition(parent, config)
    end)

    overlay:SetScript("OnEnter", function(self)
        if not self.isSelected then
            self.label:SetText("Click to Edit")
            self.label:Show()
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(config.label or "Frame", 1, 1, 1)
        GameTooltip:Show()
    end)

    overlay:SetScript("OnLeave", function(self)
        if not self.isSelected then
            self.label:Hide()
        end
        GameTooltip_Hide()
    end)

    overlay:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            if self.isSelected then
                BazUI:DeselectEditFrame(frame)
            else
                BazUI:SelectEditFrame(frame)
            end
        end
    end)

    overlay:Hide()
    frame._bazEditOverlay = overlay
    return overlay
end

---------------------------------------------------------------------------
-- Settings Popup
---------------------------------------------------------------------------

local settingsPopup = nil
local popupSavedState = nil

local POPUP_WIDTH = 340
local LABEL_WIDTH = 100
local SLIDER_WIDTH = 140
local ROW_HEIGHT = 32
local ROW_SPACING = 2
local BTN_WIDTH = POPUP_WIDTH - 30

-- Widget Builders

local function CreateSettingSlider(parent, widgetDef)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(POPUP_WIDTH - 30, ROW_HEIGHT)

    local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    text:SetPoint("LEFT")
    text:SetSize(LABEL_WIDTH, ROW_HEIGHT)
    text:SetJustifyH("LEFT")
    text:SetText(widgetDef.label)

    local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("LEFT", text, "RIGHT", 5, 0)
    slider:SetSize(SLIDER_WIDTH, ROW_HEIGHT)

    local valText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    valText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valText:SetWidth(50)
    valText:SetJustifyH("RIGHT")
    valText:SetTextColor(1, 0.82, 0)

    local formatFunc = widgetDef.format or function(v) return tostring(math.floor(v + 0.5)) end
    row.formatFunc = formatFunc

    slider.Slider:SetMinMaxValues(widgetDef.min or 0, widgetDef.max or 100)
    slider.Slider:SetValueStep(widgetDef.step or 1)
    slider.Slider:SetObeyStepOnDrag(true)

    local step = widgetDef.step or 1
    slider.Slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        valText:SetText(formatFunc(value))
        if row.onChange then
            row.onChange(value)
        end
    end)

    row.SetValue = function(self, val)
        slider.Slider:SetValue(val)
        valText:SetText(formatFunc(val))
    end

    row.GetValue = function(self)
        return slider.Slider:GetValue()
    end

    return row
end

local function CreateSettingCheckbox(parent, widgetDef)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(POPUP_WIDTH - 30, ROW_HEIGHT)

    local cb = CreateFrame("CheckButton", nil, row)
    cb:SetSize(26, 26)
    cb:SetPoint("LEFT", 0, 0)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")

    local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(widgetDef.label)

    cb:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if row.onChange then
            row.onChange(self:GetChecked())
        end
    end)

    row.checkbox = cb

    row.SetValue = function(self, val)
        cb:SetChecked(val)
    end

    row.GetValue = function(self)
        return cb:GetChecked()
    end

    return row
end

local function CreateSettingDropdown(parent, widgetDef)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(POPUP_WIDTH - 30, ROW_HEIGHT)

    local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    text:SetPoint("LEFT")
    text:SetSize(LABEL_WIDTH, ROW_HEIGHT)
    text:SetJustifyH("LEFT")
    text:SetText(widgetDef.label)

    local btn = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    btn:SetPoint("LEFT", text, "RIGHT", 5, 0)
    btn:SetWidth(SLIDER_WIDTH)

    local options = widgetDef.options or {}
    row.dropdown = btn
    row.options = options
    row.selectedValue = nil

    -- Refresh enabled-state from widgetDef.disabled() callback. Polled
    -- via OnUpdate (throttled) so the dropdown reacts live to other
    -- widgets toggling its disabled state. Grayed visually + click
    -- disabled + (optional) `disabledLabel` shown instead of value.
    row.UpdateDisabled = function(self)
        local isDisabled = (widgetDef.disabled and widgetDef.disabled())
            and true or false
        if isDisabled == self._lastDisabled then return end
        self._lastDisabled = isDisabled
        if isDisabled then
            btn:Disable()
            text:SetTextColor(0.5, 0.5, 0.5)
            if widgetDef.disabledLabel then
                btn:SetDefaultText(widgetDef.disabledLabel)
            end
        else
            btn:Enable()
            text:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
            if self.selectedValue then self:SetValue(self.selectedValue) end
        end
    end

    row.SetValue = function(self, val)
        self.selectedValue = val
        local found = false
        for _, opt in ipairs(options) do
            if opt.value == val then
                btn:SetDefaultText(opt.label)
                found = true
                break
            end
        end
        if not found then
            btn:SetDefaultText("Custom")
        end
        self:UpdateDisabled()
    end

    row.Setup = function(self)
        btn:SetupMenu(function(dropdown, rootDescription)
            for _, opt in ipairs(options) do
                rootDescription:CreateRadio(opt.label, function() return row.selectedValue == opt.value end, function()
                    row.selectedValue = opt.value
                    btn:SetDefaultText(opt.label)
                    if row.onChange then
                        row.onChange(opt.value)
                    end
                end)
            end
        end)
    end

    -- Live-poll disabled state at ~5 Hz when a callback is provided.
    -- Cheap (a single bool compare per tick) and avoids needing a
    -- popup-wide refresh API. Only registers OnUpdate when actually
    -- needed (most widgets don't use disabled, so they pay nothing).
    if widgetDef.disabled then
        row:SetScript("OnUpdate", function(self, elapsed)
            self._t = (self._t or 0) + elapsed
            if self._t < 0.2 then return end
            self._t = 0
            self:UpdateDisabled()
        end)
    end

    return row
end

local function CreateSettingInput(parent, widgetDef)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(POPUP_WIDTH - 30, ROW_HEIGHT)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    label:SetPoint("LEFT")
    label:SetSize(LABEL_WIDTH, ROW_HEIGHT)
    label:SetJustifyH("LEFT")
    label:SetText(widgetDef.label)

    local editBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    editBox:SetSize(SLIDER_WIDTH, 20)
    editBox:SetPoint("LEFT", label, "RIGHT", 8, 0)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if row.onChange then
            row.onChange(self:GetText())
        end
    end)

    row.editBox = editBox

    row.SetValue = function(self, val)
        editBox:SetText(val or "")
    end

    row.GetValue = function(self)
        return editBox:GetText()
    end

    return row
end

local function CreateNudgeWidget(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(POPUP_WIDTH - 30, ROW_HEIGHT)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    label:SetPoint("LEFT")
    label:SetSize(LABEL_WIDTH, ROW_HEIGHT)
    label:SetJustifyH("LEFT")
    label:SetText("Nudge")

    local NUDGE_SIZE = 26
    local function MakeNudgeBtn(anchorTo, rotation, dx, dy)
        local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btn:SetSize(NUDGE_SIZE, NUDGE_SIZE)
        btn:SetPoint("LEFT", anchorTo, "RIGHT", 4, 0)
        btn:SetText("")
        local arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(14, 14)
        arrow:SetPoint("CENTER")
        -- Atlas names differ per flavour; fall back to a texture that
        -- every client ships rather than erroring on an unknown atlas.
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("NPE_ArrowUp") then
            arrow:SetAtlas("NPE_ArrowUp")
        else
            arrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
        end
        arrow:SetRotation(rotation)
        btn:SetScript("OnClick", function()
            if selectedFrame then
                NudgeFrame(selectedFrame, dx, dy)
            end
        end)
        return btn
    end

    local b1 = MakeNudgeBtn(label, math.pi / 2, -1, 0)    -- Left
    local b2 = MakeNudgeBtn(b1, -math.pi / 2, 1, 0)       -- Right
    local b3 = MakeNudgeBtn(b2, 0, 0, 1)                    -- Up
    MakeNudgeBtn(b3, math.pi, 0, -1)                        -- Down

    row.SetValue = function() end
    row.GetValue = function() return nil end

    return row
end

local function CreateSettingColorPicker(parent, widgetDef)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(POPUP_WIDTH - 30, ROW_HEIGHT)

    local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    text:SetPoint("LEFT")
    text:SetSize(LABEL_WIDTH, ROW_HEIGHT)
    text:SetJustifyH("LEFT")
    text:SetText(widgetDef.label)

    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(24, 24)
    swatch:SetPoint("LEFT", text, "RIGHT", 8, 0)

    local swatchBg = swatch:CreateTexture(nil, "BACKGROUND")
    swatchBg:SetAllPoints()
    swatchBg:SetColorTexture(1, 1, 1)

    local swatchTex = swatch:CreateTexture(nil, "ARTWORK")
    swatchTex:SetAllPoints()
    swatchTex:SetColorTexture(1, 1, 1)
    row.swatchTex = swatchTex

    local border = swatch:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.3, 0.3, 0.3)
    border:SetDrawLayer("OVERLAY", -1)

    local valText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valText:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    valText:SetTextColor(0.7, 0.7, 0.7)
    row.valText = valText

    row.currentColor = { r = 1, g = 1, b = 1, a = 1 }

    swatch:SetScript("OnClick", function()
        local info = {}
        info.r = row.currentColor.r
        info.g = row.currentColor.g
        info.b = row.currentColor.b
        info.opacity = 1 - (row.currentColor.a or 1)
        info.hasOpacity = widgetDef.hasAlpha
        info.swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = 1
            if widgetDef.hasAlpha then
                a = 1 - ColorPickerFrame:GetColorAlpha()
            end
            row.currentColor = { r = r, g = g, b = b, a = a }
            swatchTex:SetColorTexture(r, g, b, a)
            valText:SetText(string.format("#%02x%02x%02x", r * 255, g * 255, b * 255))
            if row.onChange then
                row.onChange(row.currentColor)
            end
        end
        info.cancelFunc = function()
            local c = row.currentColor
            swatchTex:SetColorTexture(c.r, c.g, c.b, c.a)
            valText:SetText(string.format("#%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255))
        end
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    row.SetValue = function(self, val)
        if type(val) == "table" then
            row.currentColor = { r = val.r or 1, g = val.g or 1, b = val.b or 1, a = val.a or 1 }
        end
        local c = row.currentColor
        swatchTex:SetColorTexture(c.r, c.g, c.b, c.a)
        valText:SetText(string.format("#%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255))
    end

    row.GetValue = function(self)
        return row.currentColor
    end

    return row
end

local function CreateActionButton(parent, actionDef)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(BTN_WIDTH, 28)
    btn:SetText(actionDef.label)
    btn.SetValue = function() end
    btn.GetValue = function() return nil end
    return btn
end

-- Collapsible Sections

local function CreateSection(parent, label, startExpanded)
    local section = CreateFrame("Frame", nil, parent)
    section:SetWidth(POPUP_WIDTH - 20)
    section.children = {}
    section.expanded = startExpanded ~= false

    local header = CreateFrame("Button", nil, section)
    header:SetSize(POPUP_WIDTH - 20, 24)
    header:SetPoint("TOP")

    local arrowDown = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    arrowDown:SetPoint("LEFT", 5, 0)
    arrowDown:SetText("|TInterface\\Buttons\\Arrow-Down-Up:14:14|t")
    section.arrowDown = arrowDown

    local arrowRight = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    arrowRight:SetPoint("LEFT", 5, 0)
    arrowRight:SetText("|TInterface\\ChatFrame\\ChatFrameExpandArrow:14:14|t")
    section.arrowRight = arrowRight

    local headerText = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    headerText:SetPoint("LEFT", arrowDown, "RIGHT", 4, 0)
    headerText:SetText(label)
    headerText:SetTextColor(1, 0.82, 0)

    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetPoint("LEFT", headerText, "RIGHT", 6, 0)
    line:SetPoint("RIGHT", header, "RIGHT", -5, 0)
    line:SetHeight(1)
    line:SetColorTexture(0.5, 0.5, 0.5, 0.4)

    section.header = header

    function section:AddChild(child)
        self.children[#self.children + 1] = child
        child:SetParent(self)
    end

    function section:Layout(yStart)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", self:GetParent(), "TOPLEFT", 10, yStart)

        if self.expanded then
            self.arrowDown:Show()
            self.arrowRight:Hide()
            local y = -28
            for _, child in ipairs(self.children) do
                child:ClearAllPoints()
                child:SetPoint("TOPLEFT", self, "TOPLEFT", 5, y)
                child:Show()
                y = y - (child:GetHeight() + ROW_SPACING)
            end
            local totalHeight = -y + 28
            self:SetHeight(totalHeight)
            return totalHeight
        else
            self.arrowDown:Hide()
            self.arrowRight:Show()
            for _, child in ipairs(self.children) do
                child:Hide()
            end
            self:SetHeight(24)
            return 24
        end
    end

    header:SetScript("OnClick", function()
        section.expanded = not section.expanded
        if parent.LayoutSections then
            parent:LayoutSections()
        end
    end)

    return section
end

-- Popup Frame

local function BuildPopup()
    local f = CreateFrame("Frame", "BazUIEditModePopup", UIParent)
    f:SetSize(POPUP_WIDTH, 600)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    local border = CreateFrame("Frame", nil, f, "DialogBorderTranslucentTemplate")
    border:SetAllPoints()

    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -15)
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function()
        if selectedFrame then
            BazUI:DeselectEditFrame(selectedFrame)
        end
    end)

    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            if selectedFrame then
                BazUI:DeselectEditFrame(selectedFrame)
            end
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    f:Hide()
    return f
end

local function GetOrCreatePopup()
    if not settingsPopup then
        settingsPopup = BuildPopup()
    end
    return settingsPopup
end

-- Widget Value Helpers

local function GetWidgetValue(widgetDef, config)
    if widgetDef.get then
        return widgetDef.get()
    end
    if config.addonName and widgetDef.key then
        local addonObj = BazUI:GetAddon(config.addonName)
        if addonObj then return addonObj:GetSetting(widgetDef.key) end
    end
    return nil
end

local function SetWidgetValue(widgetDef, config, value)
    if widgetDef.set then
        widgetDef.set(value)
    elseif config.addonName and widgetDef.key then
        local addonObj = BazUI:GetAddon(config.addonName)
        if addonObj then addonObj:SetSetting(widgetDef.key, value) end
    end
    if config.onSettingChanged and widgetDef.key then
        config.onSettingChanged(selectedFrame, widgetDef.key, value)
    end
end

local function PopulatePopup(frame, config)
    local popup = GetOrCreatePopup()

    if popup.sections then
        for _, sec in ipairs(popup.sections) do
            sec:Hide()
            for _, child in ipairs(sec.children) do
                child:Hide()
                child:SetParent(nil)
            end
        end
    end
    if popup.topWidgets then
        for _, w in ipairs(popup.topWidgets) do
            w:Hide()
            w:SetParent(nil)
        end
    end
    popup.sections = {}
    popup.topWidgets = {}
    popup.widgetMap = {}

    popup.title:SetText(config.label or "Settings")

    local settings = config.settings or {}
    local sectionMap = {}
    local sectionOrder = {}
    local firstSection = true

    for _, widgetDef in ipairs(settings) do
        local sectionName = widgetDef.section or "General"
        if not sectionMap[sectionName] then
            local sec = CreateSection(popup, sectionName, firstSection)
            sectionMap[sectionName] = sec
            sectionOrder[#sectionOrder + 1] = sectionName
            firstSection = false
        end

        local widget
        if widgetDef.type == "slider" then
            widget = CreateSettingSlider(popup, widgetDef)
        elseif widgetDef.type == "checkbox" then
            widget = CreateSettingCheckbox(popup, widgetDef)
        elseif widgetDef.type == "dropdown" then
            widget = CreateSettingDropdown(popup, widgetDef)
        elseif widgetDef.type == "input" then
            widget = CreateSettingInput(popup, widgetDef)
        elseif widgetDef.type == "color" then
            widget = CreateSettingColorPicker(popup, widgetDef)
        elseif widgetDef.type == "nudge" then
            widget = CreateNudgeWidget(popup)
        end

        if widget then
            widget.onChange = function(value)
                SetWidgetValue(widgetDef, config, value)
            end

            local currentVal = GetWidgetValue(widgetDef, config)
            if currentVal ~= nil then
                widget:SetValue(currentVal)
            end

            if widgetDef.type == "dropdown" and widget.Setup then
                widget:Setup()
            end

            sectionMap[sectionName]:AddChild(widget)

            if widgetDef.key then
                popup.widgetMap[widgetDef.key] = widget
            end
        end
    end

    for _, name in ipairs(sectionOrder) do
        popup.sections[#popup.sections + 1] = sectionMap[name]
    end

    local actions = config.actions
    if actions and #actions > 0 then
        local secActions = CreateSection(popup, "Actions", false)

        for _, actionDef in ipairs(actions) do
            local btn = CreateActionButton(popup, actionDef)

            if actionDef.builtin == "revert" then
                btn:SetScript("OnClick", function()
                    if not popupSavedState then return end
                    for key, savedVal in pairs(popupSavedState) do
                        local widget = popup.widgetMap[key]
                        if widget then
                            widget:SetValue(savedVal)
                            for _, wd in ipairs(settings) do
                                if wd.key == key then
                                    SetWidgetValue(wd, config, savedVal)
                                    break
                                end
                            end
                        end
                    end
                end)
            elseif actionDef.builtin == "resetPosition" then
                btn:SetScript("OnClick", function()
                    if not selectedFrame then return end
                    if config.positionKey and config.positionKey ~= false and config.addonName then
                        local addonObj = BazUI:GetAddon(config.addonName)
                        if addonObj then addonObj:SetSetting(config.positionKey, nil) end
                    end
                    selectedFrame:ClearAllPoints()
                    local defaultPos = config.defaultPosition or { x = 0, y = 0 }
                    selectedFrame:SetPoint("CENTER", UIParent, "CENTER", defaultPos.x, defaultPos.y)
                    SavePosition(selectedFrame, config)
                end)
            elseif actionDef.onClick then
                btn:SetScript("OnClick", function()
                    actionDef.onClick(selectedFrame)
                end)
            end

            secActions:AddChild(btn)
        end

        popup.sections[#popup.sections + 1] = secActions
    end

    function popup:LayoutSections()
        local y = -40 -- below title
        for _, sec in ipairs(self.sections) do
            local h = sec:Layout(y)
            y = y - h - 4
        end
        self:SetHeight(math.abs(y) + 20)
    end

    popup:LayoutSections()

    popupSavedState = {}
    for _, widgetDef in ipairs(settings) do
        if widgetDef.key then
            popupSavedState[widgetDef.key] = GetWidgetValue(widgetDef, config)
        end
    end

    local fes = frame:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    local screenW = UIParent:GetWidth()
    local screenH = UIParent:GetHeight()

    local frameRight = frame:GetRight() * fes / uiScale
    local frameLeft = frame:GetLeft() * fes / uiScale
    local frameTop = frame:GetTop() * fes / uiScale
    local popupW = popup:GetWidth()

    local x, y
    if frameRight + popupW + 10 > screenW then
        x = frameLeft - popupW - 10
    else
        x = frameRight + 10
    end
    y = math.min(frameTop + 10, screenH - 10)

    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    popup:Show()
end

local function HidePopup()
    if settingsPopup then
        settingsPopup:Hide()
    end
    popupSavedState = nil
end

---------------------------------------------------------------------------
-- Selection Management
---------------------------------------------------------------------------

function BazUI:SelectEditFrame(frame)
    local config = registeredFrames[frame]
    if not config then return end

    if selectedFrame and selectedFrame ~= frame then
        BazUI:DeselectEditFrame(selectedFrame)
    end

    if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
        EditModeManagerFrame:ClearSelectedSystem()
    end

    local overlay = frame._bazEditOverlay
    if overlay then
        overlay.isSelected = true
        NineSliceUtil.ApplyLayout(overlay, EditModeNineSliceLayout, "editmode-actionbar-selected")
        overlay.label:SetText(config.label or "")
        overlay.label:Show()
    end

    selectedFrame = frame

    if config.onSelect then
        config.onSelect(frame)
    end

    if (config.settings and #config.settings > 0) or (config.actions and #config.actions > 0) then
        PopulatePopup(frame, config)
    end
end

function BazUI:DeselectEditFrame(frame)
    if not frame then return end
    local config = registeredFrames[frame]

    local overlay = frame._bazEditOverlay
    if overlay then
        overlay.isSelected = false
        NineSliceUtil.ApplyLayout(overlay, EditModeNineSliceLayout, "editmode-actionbar-highlight")
        overlay.label:Hide()
    end

    if selectedFrame == frame then
        selectedFrame = nil
    end

    HidePopup()

    if config and config.onDeselect then
        config.onDeselect(frame)
    end
end

function BazUI:GetSelectedEditFrame()
    return selectedFrame
end

---------------------------------------------------------------------------
-- Edit Mode State
---------------------------------------------------------------------------

local function EnterEditMode()
    isEditMode = true
    for frame, config in pairs(registeredFrames) do
        if not frame._bazEditOverlay then
            CreateEditOverlay(frame, config)
        end
        frame._bazEditOverlay.label:SetText("")
        frame._bazEditOverlay:Show()

        if config.onEnter then
            config.onEnter(frame)
        end
    end
    BazUI:Fire("BAZ_EDITMODE_ENTER")
end

local function ExitEditMode()
    if selectedFrame then
        BazUI:DeselectEditFrame(selectedFrame)
    end

    isEditMode = false
    for frame, config in pairs(registeredFrames) do
        if frame._bazEditOverlay then
            frame._bazEditOverlay:Hide()
        end

        if config.onExit then
            config.onExit(frame)
        end
    end
    BazUI:Fire("BAZ_EDITMODE_EXIT")
end

if EventRegistry then
    EventRegistry:RegisterCallback("EditMode.Enter", EnterEditMode)
    EventRegistry:RegisterCallback("EditMode.Exit", ExitEditMode)
end

if EditModeManagerFrame then
    hooksecurefunc(EditModeManagerFrame, "SelectSystem", function()
        if selectedFrame then
            BazUI:DeselectEditFrame(selectedFrame)
        end
    end)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function BazUI:RegisterEditModeFrame(frame, config)
    registeredFrames[frame] = config

    if isEditMode then
        CreateEditOverlay(frame, config)
        frame._bazEditOverlay:Show()
    end
end

-- Replace a frame's settings without re-registering it, which would
-- build a second overlay on top of the first. Used by anything whose
-- choices depend on what else exists, like a list of things to dock to.
function BazUI:UpdateEditModeSettings(frame, settings)
    local config = registeredFrames[frame]
    if not config then return end
    config.settings = settings
    if settingsPopup and settingsPopup:IsShown() and selectedFrame == frame then
        PopulatePopup(frame, config)
    end
end

function BazUI:UpdateEditModeLabel(frame, newLabel)
    local config = registeredFrames[frame]
    if config then
        config.label = newLabel
    end
    local overlay = frame._bazEditOverlay
    if overlay and overlay.isSelected then
        overlay.label:SetText(newLabel or "")
    end
    if settingsPopup and settingsPopup:IsShown() and selectedFrame == frame then
        settingsPopup.title:SetText(newLabel or "Settings")
    end
end

function BazUI:UnregisterEditModeFrame(frame)
    if selectedFrame == frame then
        BazUI:DeselectEditFrame(frame)
    end
    if frame._bazEditOverlay then
        frame._bazEditOverlay:Hide()
        frame._bazEditOverlay = nil
    end
    registeredFrames[frame] = nil
end

function BazUI:IsEditMode()
    return isEditMode
end

---------------------------------------------------------------------------
-- Making things from Edit Mode
--
-- One button on Blizzard's Edit Mode panel that offers everything BazUI
-- can create. Modules register what they make rather than each bolting
-- its own button onto the panel, which is how this started and would not
-- have survived a third thing wanting one.
--
--   BazUI:RegisterEditModeCreator("Bars", function() return {
--       { label = "Action bar", onClick = function() ... end },
--   } end)
--
-- The entries are ordinary context-menu items, so a creator can offer a
-- submenu when it makes more than one kind of thing.
---------------------------------------------------------------------------

-- Registered straight through as a context-menu section, so a module
-- that loads late simply appears the next time the menu opens.
function BazUI:RegisterEditModeCreator(name, getItems)
    if type(name) ~= "string" or type(getItems) ~= "function" then return end
    BazUI:RegisterContextMenuSection("editmode-create", name, getItems)
end

function BazUI:OpenEditModeCreateMenu(anchor)
    if InCombatLockdown() then
        BazUI:Print("Create things after combat ends.")
        return
    end
    BazUI:OpenContextMenu("editmode-create", anchor, {}, { title = "Create" })
end

function BazUI:SetupEditModeCreateButton()
    if not EditModeManagerFrame or self._editCreateButton then return end

    local button = CreateFrame("Button", nil, EditModeManagerFrame, "UIPanelButtonTemplate")
    button:SetText("Create")
    button:SetSize((button.Text:GetStringWidth() or 120) + 28, 22)
    button:SetScale(1.2)
    button:SetPoint("BOTTOM", EditModeManagerFrame, "BOTTOM", 0, -36)
    button:SetScript("OnClick", function(self) BazUI:OpenEditModeCreateMenu(self) end)
    self._editCreateButton = button
end

BazUI:QueueForLogin(function()
    BazUI:SetupEditModeCreateButton()
end)
