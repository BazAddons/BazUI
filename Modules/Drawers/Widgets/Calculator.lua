-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Calculator
--
-- Basic 4-function calculator with display and number pad.
-- Click buttons or use keyboard input via the display when focused.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_calculator"
local DESIGN_WIDTH = 220
local PAD          = 8
local DISPLAY_H    = 28
local BTN_GAP      = 3
local BTN_ROWS     = 5
local BTN_COLS     = 4

-- Compute height from layout
local BTN_W = (DESIGN_WIDTH - PAD * 2 - BTN_GAP * (BTN_COLS - 1)) / BTN_COLS
local BTN_H = 24
local DESIGN_HEIGHT = PAD * 2 + DISPLAY_H + 6 + BTN_ROWS * BTN_H + (BTN_ROWS - 1) * BTN_GAP

local CalcWidget = {}
local frame
local state = {
    display = "0",
    accumulator = nil,
    op = nil,
    awaitingInput = false,
}

local function FormatDisplay(value)
    if type(value) == "number" then
        if value == math.huge or value ~= value then return "Error" end
        if value == math.floor(value) and math.abs(value) < 1e15 then
            return tostring(math.floor(value))
        end
        return string.format("%.6g", value)
    end
    return tostring(value)
end

local function CurrentValue()
    return tonumber(state.display) or 0
end

local function ApplyOp(op, a, b)
    if op == "+" then return a + b
    elseif op == "-" then return a - b
    elseif op == "*" then return a * b
    elseif op == "/" then if b == 0 then return math.huge end; return a / b
    end
    return b
end

local function PressDigit(d)
    if state.awaitingInput then
        state.display = d
        state.awaitingInput = false
    else
        if state.display == "0" then state.display = d
        else state.display = state.display .. d end
    end
end

local function PressDot()
    if state.awaitingInput then
        state.display = "0."
        state.awaitingInput = false
    elseif not state.display:find("%.", 1) then
        state.display = state.display .. "."
    end
end

local function PressOp(op)
    local current = CurrentValue()
    if state.accumulator and state.op and not state.awaitingInput then
        local result = ApplyOp(state.op, state.accumulator, current)
        state.display = FormatDisplay(result)
        state.accumulator = result
    else
        state.accumulator = current
    end
    state.op = op
    state.awaitingInput = true
end

local function PressEquals()
    if state.accumulator and state.op then
        local result = ApplyOp(state.op, state.accumulator, CurrentValue())
        state.display = FormatDisplay(result)
        state.accumulator = nil
        state.op = nil
        state.awaitingInput = true
    end
end

local function PressClear()
    state.display = "0"
    state.accumulator = nil
    state.op = nil
    state.awaitingInput = false
end

local function PressBackspace()
    if state.awaitingInput then return end
    if #state.display <= 1 or (state.display:sub(1,1) == "-" and #state.display == 2) then
        state.display = "0"
    else
        state.display = state.display:sub(1, -2)
    end
end

local function PressNegate()
    if state.display == "0" then return end
    if state.display:sub(1,1) == "-" then
        state.display = state.display:sub(2)
    else
        state.display = "-" .. state.display
    end
end

-- Button layout (5 rows x 4 cols)
-- Row 1: AC,  +/-, ⌫,    /
-- Row 2: 7,   8,   9,    *
-- Row 3: 4,   5,   6,    -
-- Row 4: 1,   2,   3,    +
-- Row 5: 0,   ., (skip), =
local LAYOUT = {
    { { label = "AC", action = PressClear, accent = "fn" },
      { label = "+/-", action = PressNegate, accent = "fn" },
      { label = "<-", action = PressBackspace, accent = "fn" },
      { label = "/", action = function() PressOp("/") end, accent = "op" } },
    { { label = "7", action = function() PressDigit("7") end },
      { label = "8", action = function() PressDigit("8") end },
      { label = "9", action = function() PressDigit("9") end },
      { label = "*", action = function() PressOp("*") end, accent = "op" } },
    { { label = "4", action = function() PressDigit("4") end },
      { label = "5", action = function() PressDigit("5") end },
      { label = "6", action = function() PressDigit("6") end },
      { label = "-", action = function() PressOp("-") end, accent = "op" } },
    { { label = "1", action = function() PressDigit("1") end },
      { label = "2", action = function() PressDigit("2") end },
      { label = "3", action = function() PressDigit("3") end },
      { label = "+", action = function() PressOp("+") end, accent = "op" } },
    { { label = "0", action = function() PressDigit("0") end, span = 2 },
      nil,
      { label = ".", action = PressDot },
      { label = "=", action = PressEquals, accent = "eq" } },
}

-- What a key does, in its color: gold for an operator, green for
-- equals, muted red for a function key. Digits keep the face's own.
local ACCENT_COLORS = {
    op = { 1.00, 0.82, 0.00 },
    eq = { 0.40, 1.00, 0.40 },
    fn = { 0.80, 0.60, 0.60 },
}

local function MakeButton(parent, label, action, accent, width, height)
    local btn = BazUI.Skin.Theme.CreateButton(parent, {
        font  = "GameFontNormal",
        color = ACCENT_COLORS[accent],
    })
    btn:SetSize(width, height)
    btn:SetText(label)
    btn:SetScript("OnClick", function()
        action()
        CalcWidget:UpdateDisplay()
    end)
    return btn
end

function CalcWidget:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", "BazUIDrawerCalculator", UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- Display panel
    f.displayBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.displayBg:SetPoint("TOPLEFT", PAD, -PAD)
    f.displayBg:SetPoint("TOPRIGHT", -PAD, -PAD)
    f.displayBg:SetHeight(DISPLAY_H)
    BazUI.Skin.Theme.ApplyFlatPanel(f.displayBg, BazUI.Skin.Theme.colors.bg,
        BazUI.Skin.Theme.colors.edge)

    f.display = BazUI.Skin.Theme.FontString(f.displayBg, "OVERLAY", "GameFontNormalLarge")
    f.display:SetPoint("RIGHT", -8, 0)
    f.display:SetTextColor(1, 0.82, 0)
    f.display:SetText("0")

    -- Button grid
    local startY = -(PAD + DISPLAY_H + 6)
    for r, row in ipairs(LAYOUT) do
        local x = PAD
        local c = 1
        while c <= BTN_COLS do
            local btnDef = row[c]
            if btnDef then
                local span = btnDef.span or 1
                local w = BTN_W * span + BTN_GAP * (span - 1)
                local btn = MakeButton(f, btnDef.label, btnDef.action, btnDef.accent, w, BTN_H)
                btn:SetPoint("TOPLEFT", x, startY - (r - 1) * (BTN_H + BTN_GAP))
                x = x + w + BTN_GAP
                c = c + span
            else
                c = c + 1
            end
        end
    end

    frame = f
    return f
end

function CalcWidget:UpdateDisplay()
    if not frame then return end
    frame.display:SetText(state.display or "0")
    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

function CalcWidget:GetStatusText()
    return state.display or "0", 1, 0.82, 0
end

function CalcWidget:GetDesiredHeight() return DESIGN_HEIGHT end

function CalcWidget:Init()
    local f = self:Build()
    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Calculator",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return CalcWidget:GetDesiredHeight() end,
        GetStatusText    = function() return CalcWidget:GetStatusText() end,
    })
end

BazUI:QueueForModule("Drawers", function() CalcWidget:Init() end)
