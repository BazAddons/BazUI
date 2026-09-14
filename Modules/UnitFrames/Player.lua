-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("UnitFrames")
local L = addon.Layout
local WIDTH = 640
local RATIO = WIDTH / L.width
local HEIGHT = (L.height + 50) * RATIO
local root, artLayer, portrait, model, health, power, nameText, mover, hiddenStock
local updateNameplate
local stockParent, petParent, petDetached
local active, pending, manualUnlocked = false, false, false
local hoveredAreas = {}

---------------------------------------------------------------------------
-- The health and power numbers
--
-- Both values sit on one layer so the pair fades as a unit. The text is
-- always current; only the layer's alpha says whether it shows. "Always"
-- and "Never" pin it; "On hover" eases it in and out as the cursor
-- crosses the bars. Alpha is unprotected, so this runs in combat too.
---------------------------------------------------------------------------

local VALUE_FADE_IN, VALUE_FADE_OUT = 0.15, 0.3

local valueLayer
local valueAlpha = 0

local function ValueMode()
    local mode = addon:GetSetting("showValues")
    -- Preserve existing profiles that saved the original boolean toggle.
    if mode == false then return "never" end
    if mode == "hover" or mode == "never" then return mode end
    return "always"
end

local function StepValueFade(self, elapsed)
    local current = self:GetAlpha()
    if current == valueAlpha then
        self:SetScript("OnUpdate", nil)
        return
    end
    local step = elapsed / (valueAlpha > current and VALUE_FADE_IN or VALUE_FADE_OUT)
    if valueAlpha > current then
        self:SetAlpha(math.min(valueAlpha, current + step))
    else
        self:SetAlpha(math.max(valueAlpha, current - step))
    end
end

-- animate = false snaps (a setting change, or a frame nobody can see).
function addon:ApplyValueAlpha(animate)
    if not valueLayer then return end
    local mode = ValueMode()
    if mode == "hover" then
        valueAlpha = next(hoveredAreas) ~= nil and 1 or 0
    else
        valueAlpha = mode == "always" and 1 or 0
        animate = false
    end
    if animate == false or not valueLayer:IsVisible() then
        valueLayer:SetScript("OnUpdate", nil)
        valueLayer:SetAlpha(valueAlpha)
    else
        valueLayer:SetScript("OnUpdate", StepValueFade)
    end
end


local function Place(region, box, parent)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent or root, "TOPLEFT", box.x * RATIO, -box.y * RATIO)
    region:SetSize(box.w * RATIO, box.h * RATIO)
end

local function Mask(parent, box, key)
    local mask = parent:CreateMaskTexture()
    Place(mask, box)
    mask:SetTexture(addon.ASSETS .. key .. "Mask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    -- Masks use their full image; UV cropping works for artwork textures
    -- but not for MaskTexture in the client.
    return mask
end

local function CreateBar(box, key)
    local bar = CreateFrame("StatusBar", nil, root)
    Place(bar, box)
    bar:SetFrameLevel(root:GetFrameLevel() + 1)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar.mask = Mask(bar, box, key)
    bar:GetStatusBarTexture():AddMaskTexture(bar.mask)
    bar.background = bar:CreateTexture(nil, "BACKGROUND")
    bar.background:SetAllPoints(bar)
    bar.background:SetColorTexture(0.045, 0.045, 0.055, 1)
    bar.background:AddMaskTexture(bar.mask)
    return bar
end

local function ValueText(bar)
    if not valueLayer then
        valueLayer = CreateFrame("Frame", nil, artLayer)
        valueLayer:SetAllPoints(artLayer)
        valueLayer:SetFrameLevel(artLayer:GetFrameLevel() + 1)
        valueLayer:SetAlpha(0)
    end
    local text = valueLayer:CreateFontString(nil, "OVERLAY")
    text:SetFont(BazUI.Skin.Theme.FontFile(), 11, "OUTLINE")
    text:SetPoint("CENTER", bar, "CENTER")
    text:SetTextColor(1, 1, 1)
    return text
end

local function UnitMenu(frame)
    if UnitPopup_OpenMenu then
        UnitPopup_OpenMenu("SELF", { unit = "player", fromPlayerFrame = true })
    elseif ToggleDropDownMenu and PlayerFrameDropDown then
        ToggleDropDownMenu(1, nil, PlayerFrameDropDown, frame, 0, 0)
    end
end

local function ClickArea(box, suffix)
    local button = CreateFrame("Button", "BazUIPlayer" .. suffix, root, "SecureUnitButtonTemplate")
    Place(button, box)
    button:SetFrameLevel(root:GetFrameLevel() + 8)
    SecureUnitButton_OnLoad(button, "player", UnitMenu)
    button:SetScript("OnEnter", function(self)
        hoveredAreas[self] = true
        addon:UpdateValues()
        addon:ApplyValueAlpha()
        if suffix == "PortraitButton" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetUnit("player")
            GameTooltip:Show()
        end
    end)
    local function Leave(self)
        hoveredAreas[self] = nil
        addon:UpdateValues()
        addon:ApplyValueAlpha()
        if suffix == "PortraitButton" then GameTooltip_Hide() end
    end
    button:SetScript("OnLeave", Leave)
    button:SetScript("OnHide", Leave)
    return button
end

local function SetStockHidden(hide)
    if not PlayerFrame then return end
    if hide and not stockParent then
        stockParent = PlayerFrame:GetParent()
        -- The stock pet frame is a child of PlayerFrame on Era. Keep it
        -- alive at its stock anchor while replacing only the player.
        if PetFrame and PetFrame:GetParent() == PlayerFrame then
            petParent = PetFrame:GetParent()
            PetFrame:SetParent(UIParent)
            petDetached = true
        end
        PlayerFrame:SetParent(hiddenStock)
    elseif not hide and stockParent then
        PlayerFrame:SetParent(stockParent)
        if petDetached and PetFrame then PetFrame:SetParent(petParent) end
        stockParent, petParent, petDetached = nil, nil, nil
    end
end

function addon:UpdatePortrait()
    if not active then return end
    if self:GetSetting("portraitStyle") == "3d" then
        portrait:Hide()
        model:Show()
        model:ClearModel()
        model:SetUnit("player")
        model:SetPortraitZoom(1)
        model:SetCamDistanceScale(self:GetSetting("modelDistance") or 0.7)
    else
        model:Hide()
        portrait:Show()
        SetPortraitTexture(portrait, "player")
    end
end

function addon:ApplyPortraitPlacement()
    if not model then return end
    local size = math.max(0.5, math.min(2, tonumber(self:GetSetting("modelScale")) or 1))
    local side = math.min(L.portrait.w, L.portrait.h) * RATIO * 0.88 * size
    model:SetSize(side, side)
    model:ClearAllPoints()
    model:SetPoint("CENTER", portrait, "CENTER", self:GetSetting("modelX") or 0, self:GetSetting("modelY") or 0)
    model:SetFrameLevel(root:GetFrameLevel() + (self:GetSetting("modelLayer") == "below" and 2 or 6))
    model:SetCamDistanceScale(self:GetSetting("modelDistance") or 0.7)
end

function addon:PrintPortraitPlacement()
    self:Print(string.format("Player portrait: layer=%s, scale=%.2f, x=%.1f, y=%.1f, camera=%.2f", self:GetSetting("modelLayer") or "above", self:GetSetting("modelScale") or 1, self:GetSetting("modelX") or 0, self:GetSetting("modelY") or 0, self:GetSetting("modelDistance") or 0.7))
end

local function FormatValue(current, maximum)
    return string.format("%d / %d", current, maximum)
end

function addon:UpdateValues()
    if not active then return end
    local maximum = math.max(1, UnitHealthMax("player") or 1)
    local current = math.max(0, math.min(maximum, UnitHealth("player") or 0))
    health:SetMinMaxValues(0, maximum)
    health:SetValue(current)
    local r, g, b = 0.1, 0.8, 0.15
    if self:GetSetting("classColor") then
        local _, class = UnitClass("player")
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then r, g, b = color.r, color.g, color.b end
    end
    health:SetStatusBarColor(r, g, b)
    local powerType, token = UnitPowerType("player")
    local maxPower = math.max(0, UnitPowerMax("player", powerType) or 0)
    local currentPower = math.max(0, math.min(maxPower, UnitPower("player", powerType) or 0))
    power:SetMinMaxValues(0, math.max(1, maxPower))
    power:SetValue(currentPower)
    local color = PowerBarColor and (PowerBarColor[token] or PowerBarColor[powerType])
    power:SetStatusBarColor(color and color.r or 0.1, color and color.g or 0.3, color and color.b or 1)
    updateNameplate(UnitName("player") or "")
    health.text:SetText(UnitIsGhost("player") and "Ghost" or UnitIsDead("player") and "Dead" or FormatValue(current, maximum))
    power.text:SetText(maxPower > 0 and FormatValue(currentPower, maxPower) or "")
end

-- The edit mover is deliberately independent of the secure unit buttons.
-- BazUI may show its Edit Mode overlay during combat; moving this proxy
-- never moves protected frames until ApplySettings can run safely.
function addon:SavePosition()
    local cx, cy = mover:GetCenter()
    if not cx then return end
    local factor = mover:GetEffectiveScale() / UIParent:GetEffectiveScale()
    self:SetSetting("position", { point = "CENTER", relPoint = "BOTTOMLEFT", x = cx * factor, y = cy * factor })
    self:ApplySettings()
end

function addon:RefreshMover()
    local editing = manualUnlocked or BazUI:IsEditMode()
    local shown = active and editing and not InCombatLockdown()
    mover:SetShown(shown)
    if not shown then
        mover:StopMovingOrSizing()
        mover.isDragging = false
        if mover._bazEditOverlay then mover._bazEditOverlay:SetScript("OnUpdate", nil) end
    end
end

function addon:SetUnlocked(value)
    if value and InCombatLockdown() then
        self:Print("You can move the player frame after combat ends.")
        return
    end
    manualUnlocked = value
    if mover then self:RefreshMover() end
end

function addon:ApplySettings()
    if not root then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    local scale = math.max(0.5, math.min(2, tonumber(self:GetSetting("scale")) or 1))
    local pos = self:GetSetting("position") or { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 170 }
    root:SetScale(scale)
    root:ClearAllPoints()
    root:SetPoint(pos.point, UIParent, pos.relPoint, (pos.x or 0) / scale, (pos.y or 0) / scale)
    mover:ClearAllPoints()
    mover:SetSize(WIDTH * scale, HEIGHT * scale)
    mover:SetPoint(pos.point, UIParent, pos.relPoint, pos.x or 0, pos.y or 0)
    active = self:GetSetting("enabled") ~= false
    root:SetShown(active)
    SetStockHidden(active)
    self:ApplyPortraitPlacement()
    self:UpdateValues()
    self:ApplyValueAlpha(false)
    self:UpdatePortrait()
    self:RefreshMover()
    self.Casting:Apply()
end

function addon:Initialize()
    if root then return end
    -- Loading/reloading an addon in combat must not create secure buttons.
    if InCombatLockdown() then
        self:On("PLAYER_REGEN_ENABLED", function() self:Initialize() end)
        return
    end
    hiddenStock = CreateFrame("Frame")
    hiddenStock:Hide()
    root = CreateFrame("Frame", "BazUIPlayerFrame", UIParent)
    root:SetSize(WIDTH, HEIGHT)
    root:SetFrameStrata("LOW")
    root:SetFrameLevel(10)
    root:SetClampedToScreen(true)
    root:Hide()
    self.frame = root
    health = CreateBar(L.health, "health")
    -- Keep remaining health next to the portrait as it drains inward.
    health:SetReverseFill(true)
    power = CreateBar(L.power, "power")

    local portraitLayer = CreateFrame("Frame", nil, root)
    portraitLayer:SetAllPoints(root)
    portraitLayer:SetFrameLevel(root:GetFrameLevel() + 1)
    local portraitMask = Mask(portraitLayer, L.portrait, "portrait")
    local backdrop = portraitLayer:CreateTexture(nil, "BACKGROUND")
    Place(backdrop, L.portrait)
    backdrop:SetColorTexture(0.025, 0.04, 0.05, 1)
    backdrop:AddMaskTexture(portraitMask)
    -- Keep the enlarged portrait beneath the frame's metal and inner shading.
    local flatLayer = CreateFrame("Frame", nil, root)
    flatLayer:SetAllPoints(root)
    flatLayer:SetFrameLevel(root:GetFrameLevel() + 3)
    local flatBox = L.portrait
    local flatMask = flatLayer:CreateMaskTexture()
    Place(flatMask, flatBox)
    flatMask:SetTexture(addon.ASSETS .. "playerFlatPortraitMask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    portrait = flatLayer:CreateTexture(nil, "ARTWORK")
    portrait:SetPoint("CENTER", backdrop, "CENTER")
    portrait:SetSize(L.portrait.w * RATIO * 1.16, L.portrait.h * RATIO * 1.16)
    portrait:AddMaskTexture(flatMask)

    model = CreateFrame("PlayerModel", nil, root)
    model:SetFrameLevel(root:GetFrameLevel() + 2)
    -- Let the opaque outer ring cover the viewport's corners. Inscribing
    -- the viewport in the inner aperture made the head too small.
    local side = math.min(L.portrait.w, L.portrait.h) * RATIO * 0.88
    model:SetSize(side, side)
    model:SetPoint("CENTER", portrait, "CENTER")
    model:EnableMouse(false)
    model:SetScript("OnModelLoaded", function(self) self:SetPortraitZoom(1); self:SetCamDistanceScale(addon:GetSetting("modelDistance") or 0.7) end)
    model:Hide()

    artLayer = CreateFrame("Frame", nil, root)
    artLayer:SetAllPoints(root)
    artLayer:SetFrameLevel(root:GetFrameLevel() + 4)
    local artwork = artLayer:CreateTexture(nil, "ARTWORK")
    Place(artwork, { x = 0, y = 0, w = L.width, h = L.height })
    artwork:SetTexture(self.ASSETS .. "playerFrameRuntime.tga")
    artwork:SetTexCoord(0, L.width / L.textureWidth, 0, L.height / L.textureHeight)
    -- Separate overlay keeps the plate in front of either model placement.
    local nameLayer = CreateFrame("Frame", nil, root)
    nameLayer:SetAllPoints(root)
    nameLayer:SetFrameLevel(root:GetFrameLevel() + 7)
    nameText, updateNameplate = addon:CreateNameplate(nameLayer, root, L, RATIO, 14, .84)
    self.Casting:Create(root, nameText)
    health.text, power.text = ValueText(health), ValueText(power)
    -- Each value is centered in its separate left/right bar.
    ClickArea({ x = L.portrait.x - 30, y = 0, w = L.portrait.w + 60, h = L.height }, "PortraitButton")
    ClickArea({ x = 20, y = L.health.y - 24, w = L.portrait.x - 50, h = L.health.h + 48 }, "BarsButton")
    ClickArea({ x = L.portrait.x + L.portrait.w + 30, y = L.power.y - 24, w = L.width - L.portrait.x - L.portrait.w - 50, h = L.power.h + 48 }, "PowerButton")
    mover = CreateFrame("Frame", "BazUIPlayerFrameMover", UIParent)
    mover:SetFrameStrata("DIALOG")
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    local tint = mover:CreateTexture(nil, "BACKGROUND")
    tint:SetAllPoints(mover); tint:SetColorTexture(0.1, 0.45, 0.8, 0.22)
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER"); label:SetText("Player Frames - drag to move")
    mover:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:SetMovable(true); self:StartMoving() end
    end)
    mover:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); addon:SavePosition() end)
    BazUI:RegisterEditModeFrame(mover, {
        label = "Player Frames", addonName = "UnitFrames", positionKey = false,
        settings = BazUI:BuildEditModeArrayFromSpec("UnitFrames"),
        onPositionChanged = function() addon:SavePosition() end,
        onEnter = function() addon:RefreshMover() end,
        onExit = function() addon:RefreshMover() end,
    })
    self:On("BAZ_EDITMODE_EXIT", function() self:RefreshMover() end)
    self:On("PLAYER_REGEN_DISABLED", function() self:RefreshMover() end)
    self:On("PLAYER_REGEN_ENABLED", function()
        if pending then self:ApplySettings() else self:RefreshMover() end
    end)
    self:On({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_FLAGS" }, function(_, unit)
        if unit == "player" then self:UpdateValues() end
    end)
    self:On({ "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" }, function(_, unit)
        if unit == "player" then self:UpdatePortrait() end
    end)
    self:On({ "PLAYER_ENTERING_WORLD", "PLAYER_ALIVE", "PLAYER_DEAD", "PLAYER_UNGHOST" }, function()
        self:UpdateValues(); self:UpdatePortrait()
    end)
    self:ApplySettings()
end
