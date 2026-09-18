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
-- What an overlay says about a frame
--
-- The atlas says whether a frame is selected. The colour says what it is
-- in a dock stack, which is otherwise invisible while editing: move the
-- host and everything hanging off it comes too, move a follower and it
-- only changes its place in the stack. Those are different enough actions
-- that they should not look the same before you take them.
--
--   gold   the frame a stack hangs off
--   blue   carried by a host
--   plain  stands on its own
---------------------------------------------------------------------------

local OVERLAY_TINTS = {
    host     = { 1.00, 0.82, 0.00 },
    follower = { 0.35, 0.70, 1.00 },
    free     = { 1.00, 1.00, 1.00 },
}

local NINE_SLICE_PIECES = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

local function DockRole(frame)
    local Dock = BazUI.Dock
    if not Dock then return "free" end
    if Dock.IsDocked and Dock:IsDocked(frame) then return "follower" end
    local followers = Dock.GetFollowers and Dock:GetFollowers(frame)
    if followers and #followers > 0 then return "host" end
    return "free"
end

-- Re-applies the layout as well as the tint, because ApplyLayout replaces
-- the textures and a colour set before it would be thrown away.
local function ApplyOverlayLook(frame, overlay)
    if not overlay then return end
    NineSliceUtil.ApplyLayout(overlay, EditModeNineSliceLayout,
        overlay.isSelected and "editmode-actionbar-selected" or "editmode-actionbar-highlight")

    local tint = OVERLAY_TINTS[DockRole(frame)] or OVERLAY_TINTS.free
    for _, piece in ipairs(NINE_SLICE_PIECES) do
        local tex = overlay[piece]
        if tex and tex.SetVertexColor then
            tex:SetVertexColor(tint[1], tint[2], tint[3])
        end
    end
end

-- A stack can be rearranged inside a session, so the colours are worked
-- out again rather than settled once when the overlay was built.
function BazUI:RefreshEditOverlays()
    for frame in pairs(registeredFrames) do
        ApplyOverlayLook(frame, frame._bazEditOverlay)
    end
end

---------------------------------------------------------------------------
-- The grid
--
-- Ours. Snapping used to read EditModeManagerFrame.Grid, which meant it
-- only worked inside Blizzard's edit mode - open ours and there was
-- nothing to snap to.
--
-- Drawn from the middle of the screen outward, so the centre line is a
-- real centre however wide the display is, and so the two halves always
-- match. The centre pair is brighter than the rest: lining something up
-- with the middle of the screen is the one alignment worth calling out.
---------------------------------------------------------------------------

local GRID_DEFAULT_SPACING = 32
local GRID_MIN_SPACING     = 16
local GRID_MAX_SPACING     = 128

local gridFrame

local function GridSettings()
    BazUIDB = BazUIDB or {}
    BazUIDB.editMode = BazUIDB.editMode or {}
    local cfg = BazUIDB.editMode
    if cfg.grid == nil then cfg.grid = true end
    cfg.spacing = cfg.spacing or GRID_DEFAULT_SPACING
    return cfg
end

local function GridSpacing()
    return math.max(GRID_MIN_SPACING, math.min(GRID_MAX_SPACING, GridSettings().spacing))
end

local function GridActive()
    return (isEditMode and GridSettings().grid) and true or false
end

-- Where a point lands once the grid has it. The origin is the middle of
-- the screen, which is what makes a centred frame stay centred.
local function SnapPoint(cx, cy)
    local spacing = GridSpacing()
    local gx, gy = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    return gx + math.floor((cx - gx) / spacing + 0.5) * spacing,
           gy + math.floor((cy - gy) / spacing + 0.5) * spacing
end

local function GridLine(f)
    f.used = f.used + 1
    local t = f.lines[f.used]
    if not t then
        t = f:CreateTexture(nil, "BACKGROUND")
        f.lines[f.used] = t
    end
    t:ClearAllPoints()
    t:Show()
    return t
end

function BazUI:RefreshEditGrid()
    if not gridFrame then
        gridFrame = CreateFrame("Frame", "BazUIEditGrid", UIParent)
        gridFrame:SetAllPoints(UIParent)
        -- Above the world, below everything drawn on it, so the grid is
        -- never in front of the thing being lined up with it.
        gridFrame:SetFrameStrata("BACKGROUND")
        gridFrame.lines = {}
        gridFrame.used = 0
    end

    local f = gridFrame
    for _, t in ipairs(f.lines) do t:Hide() end
    f.used = 0

    if not GridActive() then
        f:Hide()
        return
    end

    local spacing = GridSpacing()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local cx, cy = w / 2, h / 2

    local function Vertical(x, centre)
        local t = GridLine(f)
        t:SetWidth(centre and 2 or 1)
        t:SetColorTexture(1, 1, 1, centre and 0.30 or 0.08)
        t:SetPoint("TOP", f, "TOPLEFT", x, 0)
        t:SetPoint("BOTTOM", f, "BOTTOMLEFT", x, 0)
    end

    local function Horizontal(y, centre)
        local t = GridLine(f)
        t:SetHeight(centre and 2 or 1)
        t:SetColorTexture(1, 1, 1, centre and 0.30 or 0.08)
        t:SetPoint("LEFT", f, "BOTTOMLEFT", 0, y)
        t:SetPoint("RIGHT", f, "BOTTOMRIGHT", 0, y)
    end

    Vertical(cx, true)
    Horizontal(cy, true)

    local x = cx + spacing
    while x < w do
        Vertical(x)
        Vertical(cx - (x - cx))
        x = x + spacing
    end

    local y = cy + spacing
    while y < h do
        Horizontal(y)
        Horizontal(cy - (y - cy))
        y = y + spacing
    end

    f:Show()
end

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
    if not GridActive() then return end

    local cx, cy = frame:GetCenter()
    local scale = frame:GetScale()
    if not (cx and cy) then return end

    local snapX, snapY = SnapPoint(cx * scale, cy * scale)

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
    if not GridActive() then return end

    local cx, cy = frame:GetCenter()
    local scale = frame:GetScale()
    if not (cx and cy) then return end

    local snapX, snapY = SnapPoint(cx * scale, cy * scale)

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

    -- A frame somebody else places gets nudged through them. Moving it
    -- here would last until their next layout pass and no longer: a
    -- docked bar is put where the dock says, so the nudge has to become
    -- part of what the dock says.
    if config.onNudge and config.onNudge(dx, dy) then return end

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

    ApplyOverlayLook(frame, overlay)

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
        BazUI:RefreshEditOverlays()
        BazUI:RefreshInspectorSide()
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

-- The inspector is a column docked to a screen edge, the way an editor
-- docks its properties panel. POPUP_WIDTH stays the width of the content
-- column every widget above is built for; the panel is that plus the
-- gutter its scroll bar lives in.
local INSPECTOR_WIDTH  = POPUP_WIDTH + 24
local INSPECTOR_TOP    = 78
local INSPECTOR_BOTTOM = 42

-- Which edge it sits on. Right by default; it moves to the left only to
-- get out of the way of whatever is selected, and a pin overrides both.
local inspectorSide   = "RIGHT"
local inspectorPinned = nil
local LABEL_WIDTH = 100
local SLIDER_WIDTH = 140
local ROW_HEIGHT = 32
local ROW_SPACING = 2
local BTN_WIDTH = POPUP_WIDTH - 30

-- Widget Builders

-- Greying out, for every kind of row
--
-- A control that does not apply right now stays where it is and goes grey.
-- It does not disappear. Hiding rearranges the panel under your cursor and
-- leaves you wondering whether a setting exists at all - the row that is
-- there and grey tells you both that it exists and that something else has
-- to change first.
--
-- `disabled` is a function so it can be asked repeatedly; the state is
-- polled rather than pushed, because a widget is usually disabled by what
-- some other widget in the same panel was just set to, and there is no
-- panel-wide refresh to hang it off. Five times a second is well under
-- what anyone notices and costs one boolean compare, and the handler is
-- only registered for rows that ask for it.
local DISABLED_POLL = 0.2

local function BindDisabled(row, widgetDef, apply)
    if not widgetDef.disabled then return end

    row.UpdateDisabled = function(self)
        local isDisabled = widgetDef.disabled() and true or false
        if isDisabled == self._lastDisabled then return end
        self._lastDisabled = isDisabled
        apply(isDisabled)
    end

    row:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < DISABLED_POLL then return end
        self._t = 0
        self:UpdateDisabled()
    end)

    row:UpdateDisabled()
end

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

    local formatFunc = widgetDef.format or function(v) return tostring(math.floor(v + 0.5)) end
    row.formatFunc = formatFunc

    local minVal = widgetDef.min or 0
    local maxVal = widgetDef.max or 100
    local step   = widgetDef.step or 1

    -- The number, which is also where you type one.
    --
    -- A slider can only land on multiples of its step, and a step exists
    -- so that dragging feels like something rather than nothing. Typing
    -- is the way to say a number the drag cannot reach, so what is typed
    -- is taken as it is - clamped to the ends, but not rounded to the
    -- step it was never using.
    local valBox = CreateFrame("EditBox", nil, row)
    valBox:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valBox:SetSize(52, ROW_HEIGHT)
    valBox:SetAutoFocus(false)
    valBox:SetFontObject("GameFontHighlightMedium")
    valBox:SetJustifyH("RIGHT")
    valBox:SetTextColor(1, 0.82, 0)
    valBox:SetTextInsets(2, 2, 0, 0)

    -- Nothing says a plain number can be typed in, so the box says so
    -- when the mouse is on it and stays lit while it has the keyboard.
    local hint = valBox:CreateTexture(nil, "BACKGROUND")
    hint:SetAllPoints()
    hint:SetColorTexture(1, 1, 1, 0.07)
    hint:Hide()

    slider.Slider:SetMinMaxValues(minVal, maxVal)
    slider.Slider:SetValueStep(step)
    slider.Slider:SetObeyStepOnDrag(true)

    -- What the row is worth, which is not always what the slider is on:
    -- a typed number sits between two of its steps.
    row._value = minVal

    local function Show(value)
        row._value = value
        valBox:SetText(formatFunc(value))
        valBox:SetCursorPosition(0)
    end

    -- Set from the keyboard, so the slider's own rounding has to be told
    -- to keep its hands off on the way past.
    local typing = false

    slider.Slider:SetScript("OnValueChanged", function(_, value)
        if typing then return end
        value = math.floor(value / step + 0.5) * step
        Show(value)
        if row.onChange then row.onChange(value) end
    end)

    -- A formatted value can carry its units with it - "50%", "12 px" -
    -- so the number is picked back out of whatever was typed over it.
    -- Percent is the one that is not what it says: the setting behind it
    -- runs nought to one.
    local isPercent = tostring(formatFunc(minVal)):find("%%") ~= nil

    local function Commit()
        local entered = valBox:GetText() or ""
        local typed = tonumber((entered:gsub("[^%-%d%.]", "")))
        if not typed then
            Show(row._value)
            return
        end
        if isPercent then typed = typed / 100 end
        typed = math.max(minVal, math.min(maxVal, typed))

        typing = true
        slider.Slider:SetValue(typed)
        typing = false

        Show(typed)
        if row.onChange then row.onChange(typed) end
    end

    valBox:SetScript("OnEnterPressed", function(self) Commit() self:ClearFocus() end)
    valBox:SetScript("OnEscapePressed", function(self)
        Show(row._value)
        self:ClearFocus()
    end)
    valBox:SetScript("OnEnter", function() hint:Show() end)
    valBox:SetScript("OnLeave", function(self)
        if not self:HasFocus() then hint:Hide() end
    end)
    valBox:SetScript("OnEditFocusGained", function(self)
        hint:Show()
        self:HighlightText()
    end)
    valBox:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        if not self:IsMouseOver() then hint:Hide() end
    end)

    row.SetValue = function(_, val)
        typing = true
        slider.Slider:SetValue(val)
        typing = false
        Show(val)
    end

    row.GetValue = function()
        return row._value
    end

    BindDisabled(row, widgetDef, function(off)
        if slider.SetEnabled then slider:SetEnabled(not off) end
        valBox:SetEnabled(not off)
        if off then
            text:SetTextColor(0.5, 0.5, 0.5)
            valBox:SetTextColor(0.5, 0.5, 0.5)
        else
            text:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
            valBox:SetTextColor(1, 1, 1)
        end
    end)

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

    BindDisabled(row, widgetDef, function(off)
        cb:SetEnabled(not off)
        if off then
            text:SetTextColor(0.5, 0.5, 0.5)
        else
            text:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
        end
    end)

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

    -- Painting the button's text is its own job, separate from choosing a
    -- value. Both the choice and the disabled state want to repaint it, and
    -- routing either through the other is what turned this into an infinite
    -- loop: SetValue re-asserted the disabled state, whose enable path
    -- called SetValue.
    local function PaintText()
        if widgetDef.disabled and widgetDef.disabled() and widgetDef.disabledLabel then
            btn:SetDefaultText(widgetDef.disabledLabel)
            return
        end
        for _, opt in ipairs(options) do
            if opt.value == row.selectedValue then
                btn:SetDefaultText(opt.label)
                return
            end
        end
        btn:SetDefaultText("Custom")
    end

    row.SetValue = function(self, val)
        self.selectedValue = val
        PaintText()
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

    BindDisabled(row, widgetDef, function(off)
        if off then
            btn:Disable()
            text:SetTextColor(0.5, 0.5, 0.5)
        else
            btn:Enable()
            text:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
        end
        PaintText()
    end)

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

    BindDisabled(row, widgetDef, function(off)
        editBox:SetEnabled(not off)
        if off then
            label:SetTextColor(0.5, 0.5, 0.5)
            editBox:SetTextColor(0.5, 0.5, 0.5)
        else
            label:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
            editBox:SetTextColor(1, 1, 1)
        end
    end)

    return row
end

local function CreateNudgeWidget(parent, config)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(POPUP_WIDTH - 30, ROW_HEIGHT)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    label:SetPoint("LEFT")
    label:SetSize(LABEL_WIDTH, ROW_HEIGHT)
    label:SetJustifyH("LEFT")
    label:SetText("Nudge")

    local NUDGE_SIZE = 26
    local function MakeNudgeBtn(anchorTo, rotation, dx, dy)
        local btn = BazUI.Skin.Theme.CreateButton(row)
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
    local b4 = MakeNudgeBtn(b3, math.pi, 0, -1)             -- Down

    -- Back to where it would have been. Only offered where that means
    -- something: a frame the dock places has a position to go back to,
    -- and a frame the player dragged anywhere they liked has not.
    local canReset = config and config.onNudgeReset
        and (not config.canNudgeReset or config.canNudgeReset())
    if canReset then
        local reset = BazUI.Skin.Theme.CreateButton(row)
        reset:SetSize(NUDGE_SIZE + 12, NUDGE_SIZE)
        reset:SetPoint("LEFT", b4, "RIGHT", 6, 0)
        reset:SetText("Reset")
        reset:SetScript("OnClick", function()
            if selectedFrame then config.onNudgeReset() end
        end)
        reset:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Clear the nudge and sit where the dock puts it.")
            GameTooltip:Show()
        end)
        reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

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
    local btn = BazUI.Skin.Theme.CreateButton(parent)
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

---------------------------------------------------------------------------
-- The inspector
--
-- One panel, docked to a screen edge for the length of an edit session,
-- holding everything: what is selected and its settings, the list of
-- everything else when nothing is, and Create and Done along the bottom.
--
-- It used to be a floating popup anchored beside whatever you had picked,
-- which meant it appeared and vanished with the selection and could land
-- anywhere. Docked, it is always in the same place, and the settings for a
-- frame arrive in a panel the eye is already on.
---------------------------------------------------------------------------

local function BuildPopup()
    local Theme = BazUI.Skin.Theme

    local f = CreateFrame("Frame", "BazUIEditInspector", UIParent)
    f:SetWidth(INSPECTOR_WIDTH)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:EnableMouse(true)

    -- Flat, and flush to the screen edge. The carved dialog border this
    -- used to wear drew a box around a panel that has no box to draw -
    -- two of its four sides are the edge of the screen. What is left is
    -- one hairline down the inner side, which DockInspector moves when
    -- the panel changes edges.
    Theme.ApplyFlatPanel(f, Theme.colors.bg, Theme.colors.edge)
    for _, edge in ipairs(f._bazFlatPanel and f._bazFlatPanel.edges or {}) do
        edge:Hide()
    end

    local seam = f:CreateTexture(nil, "BORDER", nil, 7)
    seam:SetWidth(1)
    seam:SetColorTexture(unpack(Theme.colors.edge))
    f.seam = seam

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetWidth(INSPECTOR_WIDTH - 80)
    title:SetJustifyH("CENTER")
    f.title = title

    -- Pins the panel to the side it is on, so it stops moving out of the
    -- way. Pressing it again hands the decision back.
    local pin = Theme.CreateButton(f, {
        width = 24, height = 18, text = "|cffffd700-|r",
        onClick = function(self)
            inspectorPinned = inspectorPinned and nil or inspectorSide
            BazUI:RefreshInspectorSide()
            self:SetText(inspectorPinned and "|cffffd700=|r" or "|cffffd700-|r")
        end,
    })
    pin:SetPoint("TOPLEFT", 10, -10)
    f.pin = pin

    local close = Theme.CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function()
        if selectedFrame then
            BazUI:DeselectEditFrame(selectedFrame)
        else
            BazUI:ExitEditMode()
        end
    end)

    -- Grid controls sit under the title rather than in a section, because
    -- they belong to the session and not to whatever is selected - they
    -- have to stay reachable while a frame's settings fill the body.
    local grid = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    grid:SetSize(24, 24)
    grid:SetPoint("TOPLEFT", 10, -42)
    grid:SetChecked(GridSettings().grid and true or false)
    grid:SetScript("OnClick", function(self)
        GridSettings().grid = self:GetChecked() and true or false
        BazUI:RefreshEditGrid()
    end)

    local gridLabel = Theme.FontString(f, "ARTWORK", "GameFontHighlightSmall")
    gridLabel:SetPoint("LEFT", grid, "RIGHT", 2, 0)
    gridLabel:SetText("Grid")

    local spacing = CreateFrame("Frame", nil, f, "MinimalSliderWithSteppersTemplate")
    spacing:SetPoint("LEFT", gridLabel, "RIGHT", 10, 0)
    spacing:SetSize(INSPECTOR_WIDTH - 130, 24)
    spacing.Slider:SetMinMaxValues(GRID_MIN_SPACING, GRID_MAX_SPACING)
    spacing.Slider:SetValueStep(4)
    spacing.Slider:SetObeyStepOnDrag(true)
    spacing.Slider:SetValue(GridSpacing())

    -- Its own font string, not a field written onto Blizzard's template.
    local spacingValue = Theme.FontString(f, "ARTWORK", "GameFontHighlightSmall")
    spacingValue:SetPoint("LEFT", spacing, "RIGHT", 6, 0)
    spacingValue:SetText(tostring(GridSpacing()))

    spacing.Slider:SetScript("OnValueChanged", function(_, value)
        local step = math.floor(value + 0.5)
        GridSettings().spacing = step
        spacingValue:SetText(tostring(step))
        BazUI:RefreshEditGrid()
    end)

    local create = Theme.CreateButton(f, {
        text = "Create", width = 150, height = 22, style = "primary",
        onClick = function(self) BazUI:OpenEditModeCreateMenu(self) end,
    })
    create:SetPoint("BOTTOMLEFT", 14, 12)

    local done = Theme.CreateButton(f, {
        text = "Done", width = 150, height = 22,
        onClick = function() BazUI:ExitEditMode() end,
    })
    done:SetPoint("BOTTOMRIGHT", -14, 12)

    -- A full-height panel will not always hold what goes in it, so the
    -- body scrolls. Same MinimalScrollBar pattern as the Options window.
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 8, -INSPECTOR_TOP)
    scroll:SetPoint("BOTTOMRIGHT", -30, INSPECTOR_BOTTOM)
    scroll:EnableMouseWheel(true)
    f.scroll = scroll

    local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)
        if Theme.AutoFadeScrollBar then Theme.AutoFadeScrollBar(scrollBar, scroll) end
    end
    f.scrollBar = scrollBar

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(POPUP_WIDTH - 20)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    f.content = content

    -- Sections are built with the content frame as their parent and ask
    -- it to lay out again when one is collapsed, so it answers for the
    -- panel.
    content.LayoutSections = function() f:LayoutSections() end

    local hint = Theme.FontString(content, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, -10)
    hint:SetWidth(POPUP_WIDTH - 44)
    hint:SetJustifyH("LEFT")
    hint:SetSpacing(2)
    hint:SetText("Click anything highlighted, or pick it from the list.")
    hint:Hide()
    f.hint = hint

    f.listButtons = {}

    BazUI.CloseOnEscape(f, function()
        if selectedFrame then
            BazUI:DeselectEditFrame(selectedFrame)
        else
            BazUI:ExitEditMode()
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

---------------------------------------------------------------------------
-- Which edge it sits on
--
-- Right unless what you are editing is itself mostly on the right, in
-- which case the panel goes left rather than sit on top of it. Decided on
-- selection and again when a drag ends - never while one is in progress,
-- which would have it jumping sides as you cross the middle of the screen.
---------------------------------------------------------------------------

local function SideForFrame(frame)
    if inspectorPinned then return inspectorPinned end
    if not frame then return "RIGHT" end
    local cx = frame:GetCenter()
    if not cx then return "RIGHT" end
    cx = cx * (frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    return cx > (UIParent:GetWidth() / 2) and "LEFT" or "RIGHT"
end

local function DockInspector(side)
    local f = GetOrCreatePopup()
    inspectorSide = side or inspectorSide

    -- Anchored top and bottom rather than given a height, so it fills the
    -- screen however tall that is.
    f:ClearAllPoints()
    f.seam:ClearAllPoints()
    if inspectorSide == "LEFT" then
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        f.seam:SetPoint("TOPRIGHT", f, "TOPRIGHT")
        f.seam:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
        f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
        f.seam:SetPoint("TOPLEFT", f, "TOPLEFT")
        f.seam:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
    end
end

function BazUI:RefreshInspectorSide()
    if not isEditMode then return end
    DockInspector(SideForFrame(selectedFrame))
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

-- Everything the body can hold, taken back out. One place for it, because
-- the body is filled two ways now: a frame's settings, or the list of
-- frames when nothing is selected.
local function ClearInspectorBody(popup)
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
    for _, btn in ipairs(popup.listButtons or {}) do
        btn:Hide()
        btn:SetParent(nil)
    end
    popup.sections = {}
    popup.topWidgets = {}
    popup.widgetMap = {}
    popup.listButtons = {}
    popup.hint:Hide()
end

-- Nothing selected: the panel stays up and says what there is to edit.
-- A frame tucked behind something else is reachable from here, which it
-- never was when the only way in was clicking its overlay.
local function ShowInspectorList()
    local popup = GetOrCreatePopup()
    ClearInspectorBody(popup)
    popup.title:SetText("BazUI Edit")

    local entries = {}
    for frame, config in pairs(registeredFrames) do
        entries[#entries + 1] = { frame = frame, label = config.label or "Frame" }
    end
    table.sort(entries, function(a, b) return a.label < b.label end)

    popup.hint:SetText(#entries > 0
        and "Click anything highlighted, or pick it from the list."
            .. "\n\n|cffffd100Gold|r carries other things with it. "
            .. "|cff59b3ffBlue|r is carried by something else."
        or  "Nothing to arrange yet. Create something to get started.")
    popup.hint:Show()

    -- Below the hint, whatever height it wrapped to.
    local y = -(math.max(20, popup.hint:GetStringHeight() or 20) + 24)
    for _, entry in ipairs(entries) do
        local btn = BazUI.Skin.Theme.CreateButton(popup.content, {
            text = entry.label, width = POPUP_WIDTH - 44, height = 22,
            onClick = function() BazUI:SelectEditFrame(entry.frame) end,
        })
        btn:SetPoint("TOPLEFT", popup.content, "TOPLEFT", 12, y)
        popup.listButtons[#popup.listButtons + 1] = btn
        y = y - 26
    end

    popup.content:SetHeight(math.max(1, math.abs(y) + 12))
    popup.scroll:SetVerticalScroll(0)
    DockInspector(SideForFrame(nil))
    popup:Show()
end

local function PopulatePopup(frame, config)
    local popup = GetOrCreatePopup()
    ClearInspectorBody(popup)

    popup.title:SetText(config.label or "Settings")

    local settings = config.settings or {}
    local sectionMap = {}
    local sectionOrder = {}
    local firstSection = true

    for _, widgetDef in ipairs(settings) do
        local sectionName = widgetDef.section or "General"
        if not sectionMap[sectionName] then
            local sec = CreateSection(popup.content, sectionName, firstSection)
            sectionMap[sectionName] = sec
            sectionOrder[#sectionOrder + 1] = sectionName
            firstSection = false
        end

        local widget
        if widgetDef.type == "slider" then
            widget = CreateSettingSlider(popup.content, widgetDef)
        elseif widgetDef.type == "checkbox" then
            widget = CreateSettingCheckbox(popup.content, widgetDef)
        elseif widgetDef.type == "dropdown" then
            widget = CreateSettingDropdown(popup.content, widgetDef)
        elseif widgetDef.type == "input" then
            widget = CreateSettingInput(popup.content, widgetDef)
        elseif widgetDef.type == "color" then
            widget = CreateSettingColorPicker(popup.content, widgetDef)
        elseif widgetDef.type == "nudge" then
            widget = CreateNudgeWidget(popup.content, config)
        end

        if widget then
            -- Show the current value before the widget is wired to write
            -- one. Some widgets fire their change handler when told what
            -- they are showing, and a panel being built would then write
            -- every setting back as though the user had touched them -
            -- including any that rebuild the panel, which is how a
            -- dropdown ended up rebuilding itself until the C stack ran
            -- out.
            local currentVal = GetWidgetValue(widgetDef, config)
            if currentVal ~= nil then
                widget:SetValue(currentVal)
            end

            widget.onChange = function(value)
                SetWidgetValue(widgetDef, config, value)
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
        local secActions = CreateSection(popup.content, "Actions", false)

        for _, actionDef in ipairs(actions) do
            local btn = CreateActionButton(popup.content, actionDef)

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
        local y = -8
        for _, sec in ipairs(self.sections) do
            local h = sec:Layout(y)
            y = y - h - 4
        end
        self.content:SetHeight(math.max(1, math.abs(y) + 12))
    end

    popup:LayoutSections()

    popupSavedState = {}
    for _, widgetDef in ipairs(settings) do
        if widgetDef.key then
            popupSavedState[widgetDef.key] = GetWidgetValue(widgetDef, config)
        end
    end

    popup.scroll:SetVerticalScroll(0)
    DockInspector(SideForFrame(frame))
    popup:Show()
end

-- Deselecting does not close the inspector any more - it goes back to the
-- list. Closing it is leaving the session.
local function HidePopup()
    popupSavedState = nil
    if isEditMode then
        ShowInspectorList()
    elseif settingsPopup then
        settingsPopup:Hide()
    end
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
        ApplyOverlayLook(frame, overlay)
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
        ApplyOverlayLook(frame, overlay)
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
    if isEditMode then return end
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
    BazUI:RefreshEditGrid()
    BazUI:RefreshEditOverlays()
    ShowInspectorList()
    BazUI:Fire("BAZ_EDITMODE_ENTER")
end

local function ExitEditMode()
    if not isEditMode then return end
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
    if settingsPopup then settingsPopup:Hide() end
    BazUI:RefreshEditGrid()
    BazUI:Fire("BAZ_EDITMODE_EXIT")
end

if EventRegistry then
    EventRegistry:RegisterCallback("EditMode.Enter", EnterEditMode)
    EventRegistry:RegisterCallback("EditMode.Exit", ExitEditMode)
end

---------------------------------------------------------------------------
-- Our own session
--
-- Nothing above needs Blizzard's Edit Mode to be open. The callbacks stay
-- so that opening theirs still lights ours up, but these are the way in
-- that does not involve their manager at all: the Game Menu button, the
-- slash command, and anything else that wants to arrange the interface.
--
-- Both are guarded above, so entering from both at once is not two
-- sessions - whichever arrives first opens it, and the other is a no-op.
---------------------------------------------------------------------------

function BazUI:EnterEditMode()
    if InCombatLockdown() then
        BazUI:Print("The interface cannot be rearranged during combat.")
        return false
    end
    EnterEditMode()
    return true
end

function BazUI:ExitEditMode()
    ExitEditMode()
end

function BazUI:ToggleEditMode()
    if isEditMode then
        ExitEditMode()
        return false
    end
    return BazUI:EnterEditMode()
end

-- No hook on EditModeManagerFrame:SelectSystem.
--
-- This used to deselect our own frame when Blizzard's Edit Mode selected
-- one of theirs. hooksecurefunc writes to the frame's method table, and
-- EnterEditMode is a method on that same frame - so a write here taints
-- it, and their party frame setup then errors on entering Edit Mode.
-- There is no EditMode.SelectSystem event to listen to instead, so the
-- deselect goes: our highlight may linger while one of their systems is
-- selected, which is a blemish inside Edit Mode and nothing else.
--
-- The EditMode.Enter/Exit callbacks above are on Blizzard's own
-- EventRegistry and touch nothing of theirs, so they stay.

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

---------------------------------------------------------------------------
-- The way in: a button on the Game Menu
--
-- GameMenuFrameMixin:AddButton is how Blizzard adds their own, and their
-- InitButtons rebuilds the list on every OnShow, so ours is added on each
-- show rather than once. HookScript appends a handler and touches nothing
-- else; our handler runs after theirs, so the button lands at the bottom.
--
-- The AddButton call goes through securecallfunction because it writes
-- buttonCount, nextLayoutIndex and the button list onto GameMenuFrame.
-- Made under our taint, those stores would belong to BazUI, and their own
-- menu callbacks - Log Out, Exit Game, Edit Mode - read them on the way to
-- protected calls.
---------------------------------------------------------------------------

local function AddGameMenuButton()
    local menu = _G.GameMenuFrame
    if not (menu and menu.AddButton) then return end

    local function OnClick()
        local ok = BazUI:EnterEditMode()
        if ok and menu.Hide then
            securecallfunction(menu.Hide, menu)
        end
    end

    menu:HookScript("OnShow", function(self)
        if securecallfunction then
            if self.AddSection then securecallfunction(self.AddSection, self) end
            securecallfunction(self.AddButton, self, "BazUI Edit", OnClick)
        else
            if self.AddSection then self:AddSection() end
            self:AddButton("BazUI Edit", OnClick)
        end
        if self.Layout then self:Layout() end
    end)
end

BazUI:QueueForLogin(function()
    AddGameMenuButton()
end)
