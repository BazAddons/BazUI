-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("XPBar")
local root, fill, rested, edge, text, mover, hiddenStock
local stockParents, ticks = {}, {}
local unlocked, hovered, pending = false, false, false
local data, innerWidth, innerHeight
local stockSuppressed = false
local trackingManager

local function Number(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(math.floor(n))
end

local function Solid(parent, layer, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local function Editing() return unlocked or BazUI:IsEditMode() end

function addon:UpdateText()
    local mode = self:GetSetting("text")
    text:SetShown(mode == "always" or (mode == "hover" and hovered))
end

function addon:Tooltip()
    if not data then return end
    GameTooltip:SetOwner(root, "ANCHOR_TOP")
    GameTooltip:SetText("Experience • Level " .. data.level, 1, 0.82, 0.4)
    if data.capped then
        GameTooltip:AddLine("Maximum level reached", 1, 1, 1)
    else
        GameTooltip:AddDoubleLine("Experience", Number(data.current) .. " / " .. Number(data.maximum), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("To next level", Number(data.maximum - data.current), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Rested bonus XP", Number(data.rested), 0.4, 0.75, 1, 0.4, 0.75, 1)
        if data.resting then GameTooltip:AddLine("Resting — accumulating rested XP", 0.4, 0.75, 1) end
    end
    GameTooltip:AddLine("Right-click for XP Bar options", 0.65, 0.65, 0.65)
    GameTooltip:Show()
end

function addon:Update()
    if not root then return end
    data = self:ReadProgress()
    local enabled = self:GetSetting("enabled") ~= false
    local visible = enabled and (not data.capped or not self:GetSetting("hideAtMax") or Editing())
    root:SetShown(visible)
    local ratio = data.maximum > 0 and data.current / data.maximum or 0
    fill:SetValue(ratio)
    local blue = data.rested > 0
    fill:SetStatusBarColor(blue and 0.16 or 0.57, blue and 0.48 or 0.16, blue and 0.92 or 0.85)
    local extension = data.maximum > 0 and math.min(1 - ratio, data.rested / data.maximum) or 0
    rested:ClearAllPoints()
    rested:SetPoint("TOPLEFT", fill, "TOPLEFT", innerWidth * ratio, 0)
    rested:SetSize(math.max(0.01, innerWidth * extension), innerHeight)
    rested:SetShown(self:GetSetting("rested") ~= false and extension > 0 and not data.capped)
    edge:ClearAllPoints(); edge:SetPoint("LEFT", fill, "LEFT", innerWidth * ratio - 1, 0)
    edge:SetShown(ratio > 0 and ratio < 1 and not data.capped)
    if data.capped then
        text:SetText("Level " .. data.level .. " • Maximum level")
    else
        text:SetText(string.format("Level %d   •   %s / %s XP   •   %.1f%%", data.level, Number(data.current), Number(data.maximum), ratio * 100))
    end
    self:UpdateText()
    if hovered and visible then self:Tooltip() end
end

local function SuppressStock(hide)
    stockSuppressed = hide
    -- Current Era assigns XP and reputation to shared containers. Exclude only
    -- XP from that selection, allowing reputation and container art to relayout.
    local manager = _G.StatusTrackingBarManager
    local info = _G.StatusTrackingBarInfo
    if manager and manager.CanShowBar and info and info.BarsEnum then
        if trackingManager ~= manager then
            trackingManager = manager
            local original = manager.CanShowBar
            local experience = info.BarsEnum.Experience
            manager.CanShowBar = function(self, index, ...)
                if stockSuppressed and index == experience then return false end
                return original(self, index, ...)
            end
        end
        manager:UpdateBarsShown()
    end
    -- Earlier Era builds expose a standalone XP frame instead.
    for _, name in ipairs({ "MainMenuExpBar", "ExhaustionTick", "MainMenuBarMaxLevelBar" }) do
        local frame = _G[name]
        if frame then
            if hide and not stockParents[frame] then
                stockParents[frame] = frame:GetParent(); frame:SetParent(hiddenStock)
            elseif not hide and stockParents[frame] then
                frame:SetParent(stockParents[frame]); stockParents[frame] = nil
            end
        end
    end
end

function addon:RefreshMover()
    if not mover then return end
    mover:SetShown(self:GetSetting("enabled") ~= false and Editing() and not InCombatLockdown())
    self:Update()
end

function addon:SetUnlocked(value)
    if value and InCombatLockdown() then self:Print("Move the XP bar after combat ends."); return end
    unlocked = value; self:RefreshMover()
end

function addon:SavePosition()
    mover:StopMovingOrSizing()
    local x, y = mover:GetCenter()
    if not x then return end
    local factor = mover:GetEffectiveScale() / UIParent:GetEffectiveScale()
    self:SetSetting("position", { point = "CENTER", relPoint = "BOTTOMLEFT", x = x * factor, y = y * factor })
    self:ApplySettings()
end

function addon:ApplySettings()
    if not root then return end
    if InCombatLockdown() then pending = true; return end
    pending = false
    local width = math.max(240, math.min(1800, tonumber(self:GetSetting("width")) or 700))
    local height = math.max(12, math.min(32, tonumber(self:GetSetting("height")) or 18))
    local scale = math.max(0.5, math.min(2, tonumber(self:GetSetting("scale")) or 1))
    local pos = self:GetSetting("position") or { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 8 }
    root:SetSize(width, height); root:SetScale(scale); root:ClearAllPoints()
    root:SetPoint(pos.point, UIParent, pos.relPoint, pos.x / scale, pos.y / scale)
    innerWidth, innerHeight = width - 4, height - 4
    fill:SetSize(innerWidth, innerHeight)
    edge:SetSize(2, innerHeight)
    text:SetFont(STANDARD_TEXT_FONT, math.min(12, height - 2), "OUTLINE")
    text:SetWidth(innerWidth - 10)
    text:SetWordWrap(false)
    for i, tick in ipairs(ticks) do
        tick:ClearAllPoints(); tick:SetPoint("LEFT", fill, "LEFT", innerWidth * i / 10, 0)
        tick:SetSize(1, innerHeight); tick:SetShown(self:GetSetting("ticks") == true)
    end
    mover:SetSize(width * scale, math.max(26, height * scale)); mover:ClearAllPoints()
    mover:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    SuppressStock(self:GetSetting("enabled") ~= false)
    self:RefreshMover()
end

function addon:Initialize()
    if root then return end
    if InCombatLockdown() then self:On("PLAYER_REGEN_ENABLED", function() self:Initialize() end); return end
    hiddenStock = CreateFrame("Frame"); hiddenStock:Hide()
    root = CreateFrame("Button", "BazUIXPBar", UIParent)
    self.frame = root
    root:SetFrameStrata("LOW"); root:SetFrameLevel(10); root:SetClampedToScreen(true)
    local shadow = Solid(root, "BACKGROUND", 0, 0, 0, 0.75)
    shadow:SetPoint("TOPLEFT", -2, 2); shadow:SetPoint("BOTTOMRIGHT", 2, -2)
    local rim = Solid(root, "BORDER", 0.55, 0.43, 0.25, 1); rim:SetAllPoints(root)
    local track = Solid(root, "ARTWORK", 0.035, 0.04, 0.055, 1)
    track:SetPoint("TOPLEFT", 1, -1); track:SetPoint("BOTTOMRIGHT", -1, 1)
    fill = CreateFrame("StatusBar", nil, root)
    self.fill = fill
    fill:SetFrameLevel(11); fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetStatusBarTexture(BazUI.Skin.XP_FILL); fill:SetMinMaxValues(0, 1)
    rested = Solid(fill, "BACKGROUND", 0.12, 0.3, 0.52, 0.9)
    self.restedTexture = rested
    local highlight = Solid(fill, "OVERLAY", 1, 1, 1, 0.12)
    highlight:SetPoint("TOPLEFT"); highlight:SetPoint("TOPRIGHT"); highlight:SetHeight(1)
    edge = Solid(fill, "OVERLAY", 0.8, 0.9, 1, 0.8)
    for i = 1, 9 do ticks[i] = Solid(fill, "OVERLAY", 0, 0, 0, 0.22) end
    text = fill:CreateFontString(nil, "OVERLAY")
    self.text = text
    text:SetPoint("CENTER"); text:SetTextColor(1, 1, 1)
    root:SetScript("OnEnter", function() hovered = true; addon:UpdateText(); addon:Tooltip() end)
    root:SetScript("OnLeave", function() hovered = false; addon:UpdateText(); GameTooltip:Hide() end)
    root:SetScript("OnHide", function()
        if hovered then GameTooltip:Hide() end
        hovered = false
    end)
    root:RegisterForClicks("RightButtonUp")
    root:SetScript("OnClick", function() BazUI:OpenOptionsPanel("XPBar") end)
    mover = CreateFrame("Frame", "BazUIXPBarMover", UIParent)
    mover:SetFrameStrata("DIALOG"); mover:SetMovable(true); mover:SetClampedToScreen(true); mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    local tint = Solid(mover, "BACKGROUND", 0.15, 0.5, 0.8, 0.35); tint:SetAllPoints(mover)
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER"); label:SetText("XP Bar — drag to move")
    mover:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    mover:SetScript("OnDragStop", function() addon:SavePosition() end)
    BazUI:RegisterEditModeFrame(mover, { label = "XP Bar", addonName = "XPBar", positionKey = false,
        settings = BazUI:BuildEditModeArrayFromSpec("XPBar"),
        onPositionChanged = function() addon:SavePosition() end,
        onEnter = function() addon:RefreshMover() end, onExit = function() addon:RefreshMover() end })
    self:On("BAZ_EDITMODE_EXIT", function() self:RefreshMover() end)
    self:On("PLAYER_REGEN_DISABLED", function() mover:StopMovingOrSizing(); mover:Hide() end)
    self:On("PLAYER_REGEN_ENABLED", function() if pending then self:ApplySettings() else self:RefreshMover() end end)
    self:On("PLAYER_XP_UPDATE", function(_, unit) if not unit or unit == "player" then self:Update() end end)
    self:On("PLAYER_ENTERING_WORLD", function() self:ApplySettings() end)
    self:On("UNIT_LEVEL", function(_, unit) if unit == "player" then self:Update() end end)
    self:On({ "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN" }, function() self:Update() end)
    self:ApplySettings()
end
