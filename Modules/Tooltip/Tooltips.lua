-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("Tooltip")
local Theme = BazUI.Skin.Theme
local tracked, holder = {}, nil
local healthParent
local anchorFrame, unlocked
local names = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "SmallTextTooltip", "WorldMapTooltip" }

local function Enabled() return addon:GetSetting("enabled") end
local function Suppressed() return Enabled() and addon:GetSetting("hideCombat") and InCombatLockdown() end

local function Docked(tip)
    local _, relative = tip:GetPoint(1)
    return relative and relative == _G.BazUIDrawerTooltipDock
end

-- Shared templates also serve tooltips created by Blizzard panels and other addons.
function addon:Track(tip)
    if not tip or not tip.NineSlice or tip.IsEmbedded then return end
    if tracked[tip] then return end
    tracked[tip] = {}
    tip:HookScript("OnShow", function(frame) self:Shown(frame) end)
end

function addon:Style(tip)
    self:Track(tip)
    local state = tracked[tip]
    if not state then return end
    if Enabled() and self:GetSetting("skin") then
        if tip.NineSlice then
            if not state.nineParent then state.nineParent = tip.NineSlice:GetParent() end
            if tip.NineSlice:GetParent() ~= holder then tip.NineSlice:SetParent(holder) end
        end
        Theme.ApplyTooltipFrame(tip, self:GetSetting("opacity"))
    else
        if state.nineParent then
            tip.NineSlice:SetParent(state.nineParent)
            state.nineParent = nil
        end
        -- The whole chrome frame, rather than the textures inside it:
        -- how many there are is the border's business now.
        if tip._bazTooltipArtFrame then tip._bazTooltipArtFrame:Hide() end
    end
end

---------------------------------------------------------------------------
-- The face
--
-- A tooltip line is made by the game, out of one of three font objects it
-- owns, so there is nothing of ours to set a font on. The objects are
-- taken over instead - see Theme.AdoptFontObject - which reaches every
-- tooltip drawn from them, including the game's own. That is the right
-- answer here: these are the tooltips this module has already skinned,
-- and a skinned tooltip still lettered in the game's face is the one
-- thing that looks wrong.
--
-- Given back whenever the module's skin is off or the suite's font
-- switch is, so nothing is left changed by an addon that is not doing
-- anything.
---------------------------------------------------------------------------

local FONT_OBJECTS = { "GameTooltipHeaderText", "GameTooltipText", "GameTooltipTextSmall" }

BazUI:RegisterDependency({
    module = "Tooltip",
    label  = "ContainerFrameItemButton_CalculateItemTooltipAnchors",
    why    = "Held back while the tooltip anchor is overridden, so the bag does not add a second anchor point the game then refuses.",
    check  = function()
        return BazUI.Has.Global("ContainerFrameItemButton_CalculateItemTooltipAnchors")
    end,
})

for _, name in ipairs(FONT_OBJECTS) do
    BazUI:RegisterDependency({
        module = "Tooltip",
        label  = name,
        why    = "The font object the game letters tooltips in.",
        check  = function() return BazUI.Has.Member(_G[name], "SetFont") end,
    })
end

function addon:Font()
    -- Only this module's own switches are asked. Whether the suite's face
    -- is wanted at all is the font switch's business, and an adopted
    -- object already answers it every time it is drawn - so flipping that
    -- switch reaches these without anything here running again.
    local wanted = Enabled() and self:GetSetting("skin")
    for _, name in ipairs(FONT_OBJECTS) do
        if wanted then
            Theme.AdoptFontObject(name)
        else
            Theme.ReleaseFontObject(name)
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
    local origin = self:GetSetting("origin")
    if origin == "auto" then origin = nil end
    tip:ClearAllPoints()
    if self:GetSetting("anchor") == "cursor" then
        local x, y = GetCursorPosition()
        local scale = tip:GetEffectiveScale()
        tip:SetPoint(origin or "BOTTOMLEFT", UIParent, "BOTTOMLEFT",
            x / scale + self:GetSetting("cursorX"), y / scale + self:GetSetting("cursorY"))
    else
        local point = self:GetSetting("point")
        tip:SetPoint(origin or point, anchorFrame, origin or point, 0, 0)
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
        if tip then self:Style(tip) end
    end
end

function addon:ApplySettings()
    self:Scan()
    self:UpdateAnchorMarker()
    self:HealthBar()
    self:Font()
    for tip, state in pairs(tracked) do
        if state.oldScale then tip:SetScale(state.oldScale); state.oldScale = nil end
        self:Style(tip)
        -- Next hover starts with its owner's original anchor and fresh content.
        tip:Hide()
    end
end

function addon:UpdateAnchorMarker()
    if not anchorFrame then return end
    anchorFrame:ClearAllPoints()
    anchorFrame:SetPoint("CENTER", UIParent, self:GetSetting("point"), self:GetSetting("x"), self:GetSetting("y"))
    anchorFrame:EnableMouse(unlocked and true or false)
    -- Keep the anchor frame shown so a locked tooltip can still anchor to it.
    anchorFrame.marker:SetShown(unlocked and Enabled() and self:GetSetting("anchor") == "fixed")
end

function addon:IsUnlocked()
    return unlocked == true and Enabled() and self:GetSetting("anchor") == "fixed"
end

function addon:SetUnlocked(value)
    unlocked = value
    if value then self:SetSetting("anchor", "fixed") end
    if anchorFrame then anchorFrame:StopMovingOrSizing() end
    self:ApplySettings()
end

function addon:SaveAnchor()
    local x, y = anchorFrame:GetCenter()
    local factor = anchorFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local point = self:GetSetting("point")
    local referenceX = UIParent:GetLeft() + (point:find("RIGHT") and UIParent:GetWidth() or 0)
    local referenceY = UIParent:GetBottom() + (point:find("TOP") and UIParent:GetHeight() or 0)
    self:SetSetting("x", x * factor - referenceX)
    self:SetSetting("y", y * factor - referenceY)
    self:UpdateAnchorMarker()
end

function addon:CreateAnchor()
    anchorFrame = CreateFrame("Frame", "BazUITooltipAnchor", UIParent)
    anchorFrame:SetSize(170, 38)
    anchorFrame:SetFrameStrata("DIALOG")
    anchorFrame:SetMovable(true)
    anchorFrame:SetClampedToScreen(true)
    anchorFrame:RegisterForDrag("LeftButton")
    local marker = CreateFrame("Frame", nil, anchorFrame, "BackdropTemplate")
    marker:SetAllPoints(anchorFrame)
    Theme.ApplyFlatPanel(marker)
    marker:EnableMouse(false)
    local label = BazUI.Skin.Theme.FontString(marker, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText("Tooltip anchor\nDrag | Right-click to lock")
    anchorFrame.marker = marker
    anchorFrame:SetScript("OnDragStart", function(frame) if unlocked then frame:StartMoving() end end)
    anchorFrame:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing(); self:SaveAnchor() end)
    anchorFrame:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then self:SetUnlocked(false) end end)
    self:UpdateAnchorMarker()
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
    self:CreateAnchor()
    self:Scan()
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tip)
        if tip == GameTooltip then self:Anchor(tip) end
    end)
    -- No hook on GameTooltip:SetOwner.
    --
    -- Writing to a Blizzard frame's method table is what broke the
    -- objective tracker and the nameplates on Forever, and GameTooltip
    -- is no different: their GameTooltip_SetDefaultAnchor then found a
    -- nil SetOwner. The hook above, on the global function rather than
    -- on the frame, already re-anchors every default-anchored tooltip,
    -- which is the case this was for. A tooltip that sets its own owner
    -- without going through that path keeps the owner it asked for.
    -- The bag's own idea of where a tooltip goes
    --
    -- Hovering a bag slot, the game calls
    -- ContainerFrameItemButton_CalculateItemTooltipAnchors, which does
    -- GameTooltip:SetPoint against the slot - without clearing first. If
    -- this module has already anchored the tooltip somewhere the player
    -- chose, the tooltip then holds two points, to two frames in two
    -- different anchor families, and the game refuses the second one
    -- outright with an error rather than picking a winner.
    --
    -- So when we are overriding the anchor, that call is answered with
    -- "nothing to do". Its return says only whether a comparison tooltip
    -- needs re-anchoring, and false is the same answer it gives whenever
    -- there is no comparison showing.
    --
    -- Left entirely alone when we are not overriding: the bag then
    -- positions its tooltips exactly as the game intends.
    if _G.ContainerFrameItemButton_CalculateItemTooltipAnchors then
        local stock = _G.ContainerFrameItemButton_CalculateItemTooltipAnchors
        _G.ContainerFrameItemButton_CalculateItemTooltipAnchors =
            function(button, mainTooltip, secondaryTooltip)
                if self:OverridesAnchor() then return false end
                return stock(button, mainTooltip, secondaryTooltip)
            end
    end

    if _G.SharedTooltip_OnLoad then
        hooksecurefunc("SharedTooltip_OnLoad", function(tip) self:Style(tip) end)
    end
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
