-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("Tooltip")
local Theme = BazUI.Skin.Theme
local tracked, holder = {}, nil
local healthParent, settingOwner
local names = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }

local function Enabled() return addon:GetSetting("enabled") end
local function Suppressed() return Enabled() and addon:GetSetting("hideCombat") and InCombatLockdown() end

local function Docked(tip)
    local _, relative = tip:GetPoint(1)
    return relative and relative == _G.BazUIDrawerTooltipDock
end

function addon:Style(tip)
    local state = tracked[tip]
    if not state then return end
    if Enabled() and self:GetSetting("skin") then
        if tip.NineSlice and not state.nineParent then
            state.nineParent = tip.NineSlice:GetParent()
            tip.NineSlice:SetParent(holder)
        end
        Theme.ApplyTooltipFrame(tip, self:GetSetting("opacity"))
    else
        if state.nineParent then
            tip.NineSlice:SetParent(state.nineParent)
            state.nineParent = nil
        end
        if tip._bazTooltipArt then
            for _, texture in ipairs(tip._bazTooltipArt) do texture:Hide() end
        end
    end
end

function addon:HealthBar()
    local bar = _G.GameTooltipStatusBar
    if not bar then return end
    if Enabled() and self:GetSetting("hideHealth") then
        if not healthParent then healthParent = bar:GetParent() end
        bar:SetParent(holder)
    elseif healthParent then
        bar:SetParent(healthParent)
        healthParent = nil
    end
end

function addon:Anchor(tip)
    if not self:OverridesAnchor() then return end
    tip:ClearAllPoints()
    if self:GetSetting("anchor") == "cursor" then
        local x, y = GetCursorPosition()
        local scale = tip:GetEffectiveScale()
        tip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
            x / scale + self:GetSetting("cursorX"), y / scale + self:GetSetting("cursorY"))
    else
        local point = self:GetSetting("point")
        local factor = UIParent:GetEffectiveScale() / tip:GetEffectiveScale()
        tip:SetPoint(point, UIParent, point, self:GetSetting("x") * factor, self:GetSetting("y") * factor)
    end
end

function addon:Shown(tip)
    if Suppressed() then tip:Hide(); return end
    self:Style(tip)
    local state = tracked[tip]
    -- The drawer owns the fit scale while its dock is the active anchor.
    if Enabled() and not (tip == GameTooltip and Docked(tip) and not self:OverridesAnchor()) then
        if not state.oldScale then state.oldScale = tip:GetScale() end
        tip:SetScale(self:GetSetting("scale"))
    end
    if tip == GameTooltip then self:Anchor(tip); self:HealthBar() end
end

function addon:Scan()
    for _, name in ipairs(names) do
        local tip = _G[name]
        if tip and not tracked[tip] then
            tracked[tip] = {}
            tip:HookScript("OnShow", function(frame) self:Shown(frame) end)
            self:Style(tip)
        end
    end
end

function addon:ApplySettings()
    self:Scan()
    self:HealthBar()
    for tip, state in pairs(tracked) do
        if state.oldScale then tip:SetScale(state.oldScale); state.oldScale = nil end
        self:Style(tip)
        -- Next hover starts with its owner's original anchor and fresh content.
        tip:Hide()
    end
end

function addon:Preview()
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    GameTooltip:SetText("BazUI Tooltip", unpack(Theme.colors.goldSoft))
    GameTooltip:AddLine("A quiet frame for useful information.", 1, 1, 1)
    GameTooltip:AddLine("Move the mouse to preview cursor anchoring.", .8, .8, .8)
    GameTooltip:Show()
    C_Timer.After(5, function()
        if GameTooltip:GetOwner() == UIParent then GameTooltip:Hide() end
    end)
end

function addon:Initialize()
    if holder then return end
    holder = CreateFrame("Frame")
    holder:Hide()
    self:Scan()
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tip)
        if tip == GameTooltip then self:Anchor(tip) end
    end)
    hooksecurefunc(GameTooltip, "SetOwner", function(tip, owner)
        if settingOwner or not self:OverridesAnchor() then return end
        settingOwner = true
        tip:SetOwner(owner, "ANCHOR_NONE")
        settingOwner = false
        self:Anchor(tip)
    end)
    if _G.SharedTooltip_SetBackdropStyle then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tip) self:Style(tip) end)
    end
    local elapsedTime = 0
    GameTooltip:HookScript("OnUpdate", function(tip, elapsed)
        if not self:OverridesAnchor() or self:GetSetting("anchor") ~= "cursor" then return end
        elapsedTime = elapsedTime + elapsed
        if elapsedTime >= 1 / 30 then elapsedTime = 0; self:Anchor(tip) end
    end)
    self:On("ADDON_LOADED", function() self:Scan() end)
    self:On("PLAYER_REGEN_DISABLED", function()
        if Suppressed() then for tip in pairs(tracked) do tip:Hide() end end
    end)
    self:ApplySettings()
end
