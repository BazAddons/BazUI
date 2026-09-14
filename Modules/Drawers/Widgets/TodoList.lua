-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: To-Do List
--
-- Persistent task list with checkboxes. Click a check to mark complete,
-- type in the input box and press Enter to add a new task.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_todo"
local DESIGN_WIDTH = 220
local PAD          = 8
local ROW_HEIGHT   = 18
local INPUT_HEIGHT = 22
local MAX_DISPLAY  = 8

local TodoWidget = {}
local frame

local function GetTasks()
    return addon:GetWidgetSetting(WIDGET_ID, "tasks", {}) or {}
end

local function SaveTasks(tasks)
    addon:SetWidgetSetting(WIDGET_ID, "tasks", tasks)
end

local function CountIncomplete()
    local n = 0
    for _, t in ipairs(GetTasks()) do
        if not t.done then n = n + 1 end
    end
    return n
end

function TodoWidget:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", "BazUIDrawerTodoList", UIParent)
    f:SetSize(DESIGN_WIDTH, PAD * 2 + INPUT_HEIGHT + ROW_HEIGHT)

    -- Input box at top
    f.input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.input:SetSize(DESIGN_WIDTH - PAD * 2 - 8, INPUT_HEIGHT)
    f.input:SetPoint("TOPLEFT", PAD + 4, -PAD)
    f.input:SetPoint("TOPRIGHT", -PAD - 4, -PAD)
    f.input:SetAutoFocus(false)
    f.input:SetMaxLetters(80)
    f.input:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            local tasks = GetTasks()
            table.insert(tasks, { text = text, done = false })
            SaveTasks(tasks)
            self:SetText("")
            TodoWidget:Update()
        end
        self:ClearFocus()
    end)
    f.input:SetScript("OnEscapePressed", function(self)
        self:SetText(""); self:ClearFocus()
    end)

    f.rows = {}
    frame = f
    return f
end

function TodoWidget:Update()
    if not frame then return end

    for _, row in ipairs(frame.rows) do row:Hide() end

    local tasks = GetTasks()
    local visible = math.min(#tasks, MAX_DISPLAY)
    local y = -(PAD + INPUT_HEIGHT + 4)

    for i = 1, visible do
        local task = tasks[i]
        local row = frame.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, frame)
            row:SetSize(DESIGN_WIDTH - PAD * 2, ROW_HEIGHT)

            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetSize(18, 18)
            row.check:SetPoint("LEFT", -2, 0)

            row.text = BazUI.Skin.Theme.FontString(row, "OVERLAY", "GameFontHighlight")
            row.text:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
            row.text:SetPoint("RIGHT", -16, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)

            row.delete = CreateFrame("Button", nil, row)
            row.delete:SetSize(12, 12)
            row.delete:SetPoint("RIGHT", 0, 0)
            row.delete.x = row.delete:CreateTexture(nil, "ARTWORK")
            row.delete.x:SetAllPoints()
            row.delete.x:SetAtlas("common-icon-redx")
            row.delete.x:SetVertexColor(0.6, 0.3, 0.3)
            row.delete:SetScript("OnEnter", function(self)
                self.x:SetVertexColor(1, 0.4, 0.4)
            end)
            row.delete:SetScript("OnLeave", function(self)
                self.x:SetVertexColor(0.6, 0.3, 0.3)
            end)

            frame.rows[i] = row
        end

        local idx = i
        row.check:SetChecked(task.done and true or false)
        row.check:SetScript("OnClick", function(self)
            local t = GetTasks()
            if t[idx] then
                t[idx].done = self:GetChecked() and true or nil
                SaveTasks(t)
                TodoWidget:Update()
            end
        end)

        row.text:SetText(task.text or "")
        if task.done then
            row.text:SetTextColor(0.5, 0.5, 0.5)
        else
            row.text:SetTextColor(0.95, 0.95, 0.95)
        end

        row.delete:SetScript("OnClick", function()
            local t = GetTasks()
            table.remove(t, idx)
            SaveTasks(t)
            TodoWidget:Update()
        end)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD + 2, y)
        row:SetPoint("TOPRIGHT", -PAD - 2, y)
        row:Show()
        y = y - ROW_HEIGHT
    end

    local needHeight = PAD + INPUT_HEIGHT + 4 + math.max(visible, 1) * ROW_HEIGHT + PAD
    frame:SetHeight(needHeight)

    if addon.WidgetHost then
        if addon.WidgetHost.UpdateWidgetStatus then
            addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
        end
        if addon.WidgetHost.Reflow then addon.WidgetHost:Reflow() end
    end
end

function TodoWidget:GetDesiredHeight()
    if frame then return frame:GetHeight() end
    return PAD * 2 + INPUT_HEIGHT + ROW_HEIGHT
end

function TodoWidget:GetStatusText()
    local n = CountIncomplete()
    if n == 0 then return "all done", 0.5, 1, 0.5 end
    return n .. " open", 1, 0.82, 0
end

function TodoWidget:Init()
    local f = self:Build()
    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "To-Do",
        designWidth  = DESIGN_WIDTH,
        designHeight = self:GetDesiredHeight(),
        frame        = f,
        GetDesiredHeight = function() return TodoWidget:GetDesiredHeight() end,
        GetStatusText    = function() return TodoWidget:GetStatusText() end,
    })
    self:Update()
end

BazUI:QueueForLogin(function() TodoWidget:Init() end)
