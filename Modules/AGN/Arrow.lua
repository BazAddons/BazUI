-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("AGN")
local ATLAS = "Interface\\AddOns\\BazUI\\Modules\\AGN\\Assets\\ForeverPointerMapGold.tga"
local COUNT, COLS, ROWS = 108, 9, 12
local TAU = math.pi * 2

-- Check accessibility before any comparison, arithmetic or formatting.
-- Protected values cannot be converted back into ordinary Lua numbers.
function addon:ReadableNumber(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return nil end
    return value
end

function addon:ArrowSize()
    return math.max(48, math.min(192, tonumber(self:GetSetting("size")) or 96))
end

function addon:PaintDirection(texture, angle)
    angle = self:ReadableNumber(angle)
    if not angle then return end
    local cell = math.floor(angle / TAU * COUNT + 0.5) % COUNT
    if texture._agnCell == cell then return end
    texture._agnCell = cell
    local column, row = cell % COLS, math.floor(cell / COLS)
    texture:SetTexCoord(column / COLS, (column + 1) / COLS, row / ROWS, (row + 1) / ROWS)
end

function addon:CreateNavigationFrame()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "BazUIAGNArrow", UIParent)
    self.frame = frame
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    local pos = self:GetSetting("position")
    frame:SetPoint(pos and pos.point or "TOP", UIParent, pos and pos.point or "TOP",
        pos and pos.x or 0, pos and pos.y or -160)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f)
        if not IsShiftKeyDown() then return end
        f._agnDragging = true
        f:StartMoving()
    end)
    local function StopDragging(f)
        if not f._agnDragging then return end
        f._agnDragging = nil
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        addon:SetSetting("position", { point = point, x = x, y = y })
    end
    local function UpdateMouse(f)
        local shift = f:IsShown() and IsShiftKeyDown()
        if not shift then StopDragging(f) end
        f:EnableMouse(shift)
    end
    frame:SetScript("OnDragStop", StopDragging)
    frame:RegisterEvent("MODIFIER_STATE_CHANGED")
    frame:SetScript("OnEvent", UpdateMouse)
    frame:SetScript("OnShow", UpdateMouse)
    frame:SetScript("OnHide", function(f)
        StopDragging(f)
        f:EnableMouse(false)
    end)
    frame.arrow = frame:CreateTexture(nil, "ARTWORK")
    frame.arrow:SetTexture(ATLAS)
    self:PaintDirection(frame.arrow, 0)
    frame.arrow:SetPoint("CENTER")
    frame.title = BazUI.Skin.Theme.FontString(frame, "OVERLAY", "GameFontNormal")
    frame.title:SetWidth(280)
    frame.title:SetJustifyH("CENTER")
    frame.detail = BazUI.Skin.Theme.FontString(frame, "OVERLAY", "GameFontHighlightSmall")
    frame.detail:SetWidth(280)
    frame.detail:SetJustifyH("CENTER")
    frame.detail:SetPoint("TOP", frame.title, "BOTTOM", 0, -3)
    frame.source = BazUI.Skin.Theme.FontString(frame, "OVERLAY", "GameFontHighlightSmall")
    frame.source:SetPoint("TOP", frame.detail, "BOTTOM", 0, -4)
    frame:SetScript("OnUpdate", function(_, elapsed) addon:UpdateArrow(elapsed) end)
    self:ResizeArrow()
    frame:Hide()
    return frame
end

function addon:ResizeArrow()
    local f = self.frame
    if not f then return end
    local size = self:ArrowSize()
    f:SetSize(size, size * .78)
    f.arrow:SetSize(size, size)
    f.title:ClearAllPoints()
    f.title:SetPoint("TOP", f, "CENTER", 0, -size * .27 - 10)
end

function addon:TogglePreview()
    self.previewing = not self.previewing
    self:RefreshNavigation()
end

function addon:UpdateArrow(elapsed)
    self.updateElapsed = (self.updateElapsed or 0) + elapsed
    if self.previewing then
        self.previewAngle = (self.previewAngle or 0) + elapsed * .8
        self:PaintDirection(self.frame.arrow, self.previewAngle)
        self.frame.title:SetText("AGN preview")
        self.frame.detail:SetText("Shift-drag to move | /agn preview to close")
        return
    end
    if self.updateElapsed >= .05 then
        self.updateElapsed = 0
        self:RefreshNavigation()
    end
    local target = self.displayTarget
    if target then
        local angle = self:ReadableNumber(target.angle)
        local bearing = self:ReadableNumber(target.bearing)
        local facing = self:ReadableNumber(GetPlayerFacing())
        if bearing and facing then angle = bearing - facing end
        self:PaintDirection(self.frame.arrow, angle)
    end
end
