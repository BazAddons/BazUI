-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Auras: headers, buttons and painting
--
-- Four SecureAuraHeaderTemplate frames (buffs and debuffs for the
-- player, buffs and debuffs for the target) are parented to the BazUI
-- unit frames so they scale, move and hide with them. Each header
-- creates BazUIAuraButtonTemplate buttons, stamps "index" and "filter"
-- (or "target-slot" for weapon enchants) on each, sorts and positions
-- them, and handles the right-click cancel securely. The target frame
-- shows and hides through a secure state driver, so its headers follow
-- the target in and out of combat.
--
-- Everything here that touches a protected frame (attributes, anchors,
-- sizes, parent) runs out of combat only; a change requested in combat
-- is applied when combat ends. Painting icons and text is unrestricted.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("Auras")
local Auras = BazUI.Auras

local TEMPLATE = "BazUIAuraButtonTemplate"
local TICK     = 0.1     -- duration text refresh interval

local BUFF_RIM = { r = 0.08, g = 0.08, b = 0.10 }
-- Used when the client has no DebuffTypeColor table; same values.
local DEBUFF_COLORS = {
    none    = { r = 0.80, g = 0.00, b = 0.00 },
    Magic   = { r = 0.20, g = 0.60, b = 1.00 },
    Curse   = { r = 0.60, g = 0.00, b = 1.00 },
    Disease = { r = 0.60, g = 0.40, b = 0.00 },
    Poison  = { r = 0.00, g = 0.60, b = 0.00 },
}

local headers = {}       -- "HELPFUL" / "HARMFUL" (player), "TARGET_HELPFUL" / "TARGET_HARMFUL"
local buttons = {}       -- set of every button the headers have created
local hiddenParent
local pendingApply  = false
local refreshQueued = false
local applyQueued   = false
local targetAnchored = false   -- the target headers sit on a BazUI target frame

-- Preview state (see "Preview" below).
local demoFrame
local demoButtons = {}
local demoActive  = false

---------------------------------------------------------------------------
-- Reading auras
---------------------------------------------------------------------------

local function ReadAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if not a then return nil end
        return a.icon, a.applications, a.dispelName, a.expirationTime
    end
    local name, icon, count, dispelType, _, expirationTime = UnitAura(unit, index, filter)
    if not name then return nil end
    return icon, count, dispelType, expirationTime
end

-- Weapon enchants come from GetWeaponEnchantInfo, with expirations in
-- milliseconds from now rather than absolute times.
local function ReadWeapon(slot)
    local hasMain, mainExp, mainCharges, _, hasOff, offExp, offCharges = GetWeaponEnchantInfo()
    local has, exp, charges
    if slot == 16 then
        has, exp, charges = hasMain, mainExp, mainCharges
    elseif slot == 17 then
        has, exp, charges = hasOff, offExp, offCharges
    end
    if not has then return nil end
    local expirationTime = (exp and exp > 0) and (GetTime() + exp / 1000) or 0
    return GetInventoryItemTexture("player", slot), charges, expirationTime
end

local function FormatDuration(remaining)
    if remaining >= 86400 then return ("%dd"):format(math.floor(remaining / 86400 + 0.5)) end
    if remaining >= 3600  then return ("%dh"):format(math.floor(remaining / 3600 + 0.5)) end
    if remaining >= 60    then return ("%dm"):format(math.floor(remaining / 60 + 0.5)) end
    return ("%d"):format(math.ceil(remaining))
end

---------------------------------------------------------------------------
-- Painting one button
---------------------------------------------------------------------------

local function SetRim(btn, c)
    btn.Border:SetColorTexture(c.r, c.g, c.b, 1)
end

local function UpdateDuration(btn, now)
    if not btn.expirationTime or addon:GetSetting("showDuration") == false then
        btn.Duration:SetText("")
        return
    end
    local remaining = btn.expirationTime - now
    if remaining <= 0 then
        btn.Duration:SetText("")
        return
    end
    btn.Duration:SetText(FormatDuration(remaining))
    if remaining < 5 then
        btn.Duration:SetTextColor(1, 0.35, 0.35)
    else
        btn.Duration:SetTextColor(1, 1, 1)
    end
end

-- The unit a button shows: its header's unit attribute.
local function ButtonUnit(btn)
    local h = btn:GetParent()
    return (h and h.GetAttribute and h:GetAttribute("unit")) or "player"
end

local function UpdateButton(btn)
    local slot   = tonumber(btn:GetAttribute("target-slot"))
    local index  = btn:GetAttribute("index")
    local filter = btn:GetAttribute("filter")
    local icon, count, dispel, expirationTime

    if slot then
        btn.isWeapon = true
        icon, count, expirationTime = ReadWeapon(slot)
    elseif index then
        btn.isWeapon = false
        icon, count, dispel, expirationTime = ReadAura(ButtonUnit(btn), index, filter)
    end

    if not icon then
        btn.Icon:SetTexture(nil)
        btn.Count:SetText("")
        btn.Duration:SetText("")
        btn.expirationTime = nil
        return
    end

    btn.Icon:SetTexture(icon)
    if addon:GetSetting("showCount") ~= false and count and count > 1 then
        btn.Count:SetText(count)
    else
        btn.Count:SetText("")
    end
    btn.expirationTime = (expirationTime and expirationTime > 0) and expirationTime or nil

    if filter and filter:find("HARMFUL", 1, true) then
        local c
        if addon:GetSetting("debuffBorders") ~= false then
            local colors = _G.DebuffTypeColor or DEBUFF_COLORS
            c = colors[dispel or "none"] or colors.none or DEBUFF_COLORS.none
        else
            c = DEBUFF_COLORS.none
        end
        SetRim(btn, c)
    else
        SetRim(btn, BUFF_RIM)
    end
    UpdateDuration(btn, GetTime())

    if GameTooltip:IsOwned(btn) then
        Auras.OnButtonEnter(btn)
    end
end

function Auras.ApplyButtonSize(btn)
    local size = addon:GetSetting("iconSize") or 26
    if not InCombatLockdown() then
        btn:SetSize(size, size)
    end
    btn.Duration:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(size * 0.42)), "OUTLINE")
    btn.Count:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(size * 0.40)), "OUTLINE")
end

---------------------------------------------------------------------------
-- Template script handlers (called from Auras.xml)
---------------------------------------------------------------------------

function Auras.OnButtonLoad(btn)
    buttons[btn] = true
    SetRim(btn, BUFF_RIM)
    Auras.ApplyButtonSize(btn)
end

function Auras.OnButtonAttributeChanged(btn, name)
    if name == "index" or name == "filter" or name == "target-slot" then
        UpdateButton(btn)
    end
end

function Auras.OnButtonShow(btn)
    UpdateButton(btn)
end

function Auras.OnButtonHide(btn)
    if GameTooltip:IsOwned(btn) then GameTooltip:Hide() end
end

function Auras.OnButtonEnter(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
    if btn.isWeapon then
        local slot = tonumber(btn:GetAttribute("target-slot"))
        if slot then GameTooltip:SetInventoryItem("player", slot) end
    else
        local index = btn:GetAttribute("index")
        if index then GameTooltip:SetUnitAura(ButtonUnit(btn), index, btn:GetAttribute("filter")) end
    end
    GameTooltip:Show()
end

function Auras.OnButtonLeave()
    GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Headers
---------------------------------------------------------------------------

local function CreateHeader(key, unit, filter, name)
    local h = CreateFrame("Frame", name, UIParent, "SecureAuraHeaderTemplate")
    h:SetAttribute("unit", unit)
    h:SetAttribute("filter", filter)
    h:SetAttribute("template", TEMPLATE)
    h:SetAttribute("weaponTemplate", TEMPLATE)
    h:SetAttribute("templateType", "Button")
    h:Hide()
    headers[key] = h
    return h
end

-- side: "left" for buffs (by the health bar), "right" for debuffs (by
-- the power bar). below: rows hang under the bars and stack downward
-- (the target frame) instead of sitting above and stacking upward (the
-- player frame). Returns the header's own anchor point.
local function ConfigureHeader(h, side, below)
    local size    = addon:GetSetting("iconSize") or 26
    local spacing = addon:GetSetting("spacing") or 3
    local perRow  = addon:GetSetting("perRow") or 8
    local growth  = addon:GetSetting("growth") or "portrait"
    local step    = size + spacing

    -- "portrait" puts the first icon beside the portrait and grows away
    -- from it: buffs (left side) grow left, debuffs grow right. "edge"
    -- is the mirror image.
    local growRight = (growth == "portrait") == (side == "right")
    local vertical = below and "TOP" or "BOTTOM"
    local point = vertical .. (growRight and "LEFT" or "RIGHT")

    h:SetAttribute("point", point)
    h:SetAttribute("xOffset", growRight and step or -step)
    h:SetAttribute("yOffset", 0)
    h:SetAttribute("wrapAfter", perRow)
    h:SetAttribute("wrapXOffset", 0)
    h:SetAttribute("wrapYOffset", below and -step or step)
    h:SetAttribute("maxWraps", 0)           -- 0 = as many rows as needed
    h:SetAttribute("minWidth", perRow * step - spacing)
    h:SetAttribute("minHeight", size)
    h:SetAttribute("sortMethod", addon:GetSetting("sortMethod") or "INDEX")
    h:SetAttribute("sortDirection", addon:GetSetting("sortDirection") or "+")
    local isPlayer = h:GetAttribute("unit") == "player"
    local weapons = isPlayer and side == "left" and addon:GetSetting("showWeapons") ~= false
    h:SetAttribute("includeWeapons", weapons and 1 or nil)
    if not isPlayer and side == "right" then
        -- Changing the filter re-runs the header's update, which is fine
        -- out of combat (ApplySettings never runs in combat).
        local mine = addon:GetSetting("targetOnlyMine") == true
        h:SetAttribute("filter", mine and "HARMFUL|PLAYER" or "HARMFUL")
    end
    -- Buttons the header creates during combat still get the right size:
    -- this snippet runs in the header's secure environment.
    h:SetAttribute("initialConfigFunction", ("self:SetWidth(%d); self:SetHeight(%d)"):format(size, size))
    return point
end

-- The BazUI player frame and its layout table, when that module is
-- present and replacing the stock frame.
local function PlayerRoot()
    local root = _G.BazUIPlayerFrame
    local uf = BazUI:GetModule("UnitFrames")
    if root and uf and uf.Layout and uf.GetSetting and uf:GetSetting("enabled") ~= false then
        return root, uf.Layout
    end
end

-- The BazUI target frame and its layout table. Target auras exist only
-- with it: the stock target frame draws its own.
local function TargetRoot()
    local root = _G.BazUITargetFrame
    local uf = BazUI:GetModule("UnitFrames")
    local target = uf and uf.Target
    if root and uf and uf.TargetLayout and target and target.GetSetting and target:GetSetting("enabled") ~= false then
        return root, uf.TargetLayout
    end
end

-- Left edge or right edge of a bar, in source pixels, for a header that
-- anchors by `point`.
local function BarEdge(bar, point)
    if point:find("LEFT", 1, true) then return bar.x end
    return bar.x + bar.w
end

-- Source pixels the target auras keep clear of the name plate's edge;
-- the plate's wings reach a little past its box.
local PLATE_MARGIN = 16

local function AnchorTargetHeaders(buffPoint, debuffPoint)
    local buffs, debuffs = headers.TARGET_HELPFUL, headers.TARGET_HARMFUL
    buffs:ClearAllPoints()
    debuffs:ClearAllPoints()
    local root, L = TargetRoot()
    if not root then return false end

    local gap     = addon:GetSetting("targetGap") or 12
    local size    = addon:GetSetting("iconSize") or 26
    local spacing = addon:GetSetting("spacing") or 3
    local perRow  = addon:GetSetting("perRow") or 8
    local step    = size + spacing
    local R = root:GetWidth() / L.width
    local level = root:GetFrameLevel() + 10
    buffs:SetParent(root)
    debuffs:SetParent(root)
    buffs:SetFrameLevel(level)
    debuffs:SetFrameLevel(level)

    -- Below the bars the name plate sits between them, so the inner end
    -- of each side is the plate's edge, not the bar's. Each side runs
    -- from the bar's outer end to that edge.
    local plate = L.namePlate
    local buffInner   = math.min(L.health.x + L.health.w, plate.x - PLATE_MARGIN)
    local debuffInner = math.max(L.power.x, plate.x + plate.w + PLATE_MARGIN)
    local bx = buffPoint:find("LEFT", 1, true) and L.health.x or buffInner
    local px = debuffPoint:find("LEFT", 1, true) and debuffInner or (L.power.x + L.power.w)

    -- A row that starts at the outer end and fills inward must stop
    -- before the plate; one that starts at the plate may run off the
    -- frame's edge, which is harmless.
    local function Fit(h, point, avail)
        local fits = math.max(1, math.floor((avail * R + spacing) / step))
        local outward = (point:find("LEFT", 1, true) ~= nil) == (h == debuffs)
        local cols = outward and perRow or math.min(perRow, fits)
        h:SetAttribute("wrapAfter", cols)
        h:SetAttribute("minWidth", cols * step - spacing)
    end
    Fit(buffs, buffPoint, buffInner - L.health.x)
    Fit(debuffs, debuffPoint, (L.power.x + L.power.w) - debuffInner)

    -- First row hangs from the bottom of the bars; later rows stack down.
    buffs:SetPoint(buffPoint, root, "TOPLEFT", bx * R, -((L.health.y + L.health.h) * R) - gap)
    debuffs:SetPoint(debuffPoint, root, "TOPLEFT", px * R, -((L.power.y + L.power.h) * R) - gap)
    return true
end

local function AnchorHeaders(buffPoint, debuffPoint)
    local gap     = addon:GetSetting("gap") or 8
    local spacing = addon:GetSetting("spacing") or 3
    local buffs, debuffs = headers.HELPFUL, headers.HARMFUL
    buffs:ClearAllPoints()
    debuffs:ClearAllPoints()

    local root, L = PlayerRoot()
    if root then
        -- Layout coordinates are source pixels of the artwork; the root
        -- frame is the artwork scaled to its width.
        local R = root:GetWidth() / L.width
        local level = root:GetFrameLevel() + 6
        buffs:SetParent(root)
        debuffs:SetParent(root)
        buffs:SetFrameLevel(level)
        debuffs:SetFrameLevel(level)
        buffs:SetPoint(buffPoint, root, "TOPLEFT", BarEdge(L.health, buffPoint) * R, -(L.health.y * R) + gap)
        debuffs:SetPoint(debuffPoint, root, "TOPLEFT", BarEdge(L.power, debuffPoint) * R, -(L.power.y * R) + gap)
    else
        -- No BazUI player frame: sit above the stock one, debuffs on
        -- top of the buffs.
        local pf = _G.PlayerFrame or UIParent
        buffs:SetParent(UIParent)
        debuffs:SetParent(UIParent)
        if buffPoint == "BOTTOMLEFT" then
            buffs:SetPoint("BOTTOMLEFT", pf, "TOPLEFT", 20, gap)
        else
            buffs:SetPoint("BOTTOMRIGHT", pf, "TOPRIGHT", -20, gap)
        end
        debuffs:SetPoint(debuffPoint, buffs, debuffPoint == "BOTTOMLEFT" and "TOPLEFT" or "TOPRIGHT", 0, spacing)
    end
end

local function SetBlizzardHidden(hide)
    for _, name in ipairs({ "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" }) do
        local f = _G[name]
        if f then
            if hide and not f._bazAurasParent then
                f._bazAurasParent = f:GetParent() or UIParent
                f:SetParent(hiddenParent)
            elseif not hide and f._bazAurasParent then
                f:SetParent(f._bazAurasParent)
                f._bazAurasParent = nil
            end
        end
    end
end

---------------------------------------------------------------------------
-- Preview
--
-- A full spread of made-up auras on every side, so the layout can be
-- judged without waiting for real ones. The stand-ins are plain frames
-- laid out by the same attributes the secure headers use, anchored to
-- the headers themselves, so they land exactly where real icons would.
-- Nothing secure is touched: the preview can start and stop at any
-- time and ends by itself when combat begins. Real auras stay
-- underneath it.
---------------------------------------------------------------------------

local DEMO_ROWS = 3

local DEMO_BUFFS = {
    "Spell_Holy_WordFortitude", "Spell_Holy_PowerWordShield", "Spell_Nature_Regeneration",
    "Ability_Warrior_BattleShout", "Spell_Frost_FrostArmor", "Spell_Holy_DivineSpirit",
    "Spell_Holy_Renew", "Spell_Nature_Thorns", "Spell_Holy_SealOfMight",
    "Spell_Nature_StrengthOfEarthTotem02", "Ability_Hunter_AspectOfTheMonkey", "Spell_Fire_FireArmor",
}
-- Icon and dispel type, so the rim colours show.
local DEMO_DEBUFFS = {
    { "Spell_Shadow_CurseOfTounges", "Curse" },      { "Spell_Nature_CorrosiveBreath", "Poison" },
    { "Spell_Shadow_CallofBone", "Disease" },        { "Spell_Fire_Immolation", "Magic" },
    { "Spell_Shadow_ShadowWordPain", "Magic" },      { "Ability_Warrior_Sunder" },
    { "Spell_Frost_FrostShock", "Magic" },           { "Ability_Rogue_Garrote" },
    { "Spell_Shadow_AbominationExplosion", "Poison" }, { "Spell_Nature_NullifyDisease", "Disease" },
    { "Spell_Shadow_UnholyFrenzy", "Curse" },        { "Ability_CriticalStrike" },
}

local function DemoButton(i)
    local btn = demoButtons[i]
    if not btn then
        btn = CreateFrame("Button", nil, demoFrame, "BazUIAuraVisualTemplate")
        btn:EnableMouse(false)
        demoButtons[i] = btn
    end
    return btn
end

local function LayoutDemo()
    local size   = addon:GetSetting("iconSize") or 26
    local perRow = addon:GetSetting("perRow") or 8
    local count  = perRow * DEMO_ROWS
    local now    = GetTime()
    local used   = 0
    local sides = {
        { headers.HELPFUL,        DEMO_BUFFS,   false, false },
        { headers.HARMFUL,        DEMO_DEBUFFS, true,  false },
        { headers.TARGET_HELPFUL, DEMO_BUFFS,   false, true },
        { headers.TARGET_HARMFUL, DEMO_DEBUFFS, true,  true },
    }
    for _, side in ipairs(sides) do
        local h, icons, harmful, isTarget = side[1], side[2], side[3], side[4]
        if h and h:GetNumPoints() > 0 and (not isTarget or targetAnchored) then
            local point = h:GetAttribute("point") or "BOTTOMLEFT"
            local xOff  = h:GetAttribute("xOffset") or 0
            local yWrap = h:GetAttribute("wrapYOffset") or 0
            local wrap  = math.max(1, h:GetAttribute("wrapAfter") or perRow)
            -- The header lives in its unit frame's scale; the stand-ins
            -- live under UIParent, so offsets and sizes scale to match.
            local s = h:GetEffectiveScale() / demoFrame:GetEffectiveScale()
            local colors = _G.DebuffTypeColor or DEBUFF_COLORS
            for i = 0, count - 1 do
                used = used + 1
                local btn = DemoButton(used)
                local entry = icons[(i % #icons) + 1]
                local icon, dispel = entry, nil
                if type(entry) == "table" then icon, dispel = entry[1], entry[2] end

                local px = size * s
                btn:SetSize(px, px)
                btn.Duration:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(px * 0.42)), "OUTLINE")
                btn.Count:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(px * 0.40)), "OUTLINE")
                btn.Icon:SetTexture("Interface\\Icons\\" .. icon)
                btn.Count:SetText((i % 3 == 1 and addon:GetSetting("showCount") ~= false) and tostring((i % 5) + 2) or "")
                -- Twenty seconds to an hour, spread so the labels differ.
                btn.expirationTime = now + 20 + (i * 137) % 3600
                local rim = BUFF_RIM
                if harmful then
                    if addon:GetSetting("debuffBorders") ~= false then
                        rim = colors[dispel or "none"] or colors.none or DEBUFF_COLORS.none
                    else
                        rim = DEBUFF_COLORS.none
                    end
                end
                SetRim(btn, rim)
                UpdateDuration(btn, now)

                local col, row = i % wrap, math.floor(i / wrap)
                btn:ClearAllPoints()
                btn:SetPoint(point, h, point, col * xOff * s, row * yWrap * s)
                btn:Show()
            end
        end
    end
    for i = used + 1, #demoButtons do demoButtons[i]:Hide() end
end

-- Turn the preview on or off; no argument toggles it.
function addon:SetPreview(on)
    if on == nil then on = not demoActive end
    demoActive = on and true or false
    if demoActive then
        if not demoFrame then
            demoFrame = CreateFrame("Frame", "BazUIAurasPreview", UIParent)
            demoFrame:SetFrameStrata("MEDIUM")
            demoFrame:SetSize(1, 1)
            demoFrame:SetPoint("CENTER")
        end
        LayoutDemo()
        demoFrame:Show()
        BazUI:Print("Auras preview on. It turns off when combat starts, or type /bazauras preview.")
    elseif demoFrame then
        demoFrame:Hide()
    end
    if BazUI.RefreshOptions then BazUI:RefreshOptions(self.MODULE_NAME .. "-Settings") end
end

function addon:IsPreviewing()
    return demoActive
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function addon:RefreshAll()
    for btn in pairs(buttons) do
        if btn:IsShown() then UpdateButton(btn) end
    end
end

function addon:QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        addon:RefreshAll()
    end)
end

function addon:ApplySettings()
    if not headers.HELPFUL then return end
    if InCombatLockdown() then
        pendingApply = true
        return
    end
    pendingApply = false
    local enabled = self:GetSetting("enabled") ~= false
    local buffPoint   = ConfigureHeader(headers.HELPFUL, "left")
    local debuffPoint = ConfigureHeader(headers.HARMFUL, "right")
    AnchorHeaders(buffPoint, debuffPoint)

    local tBuffPoint   = ConfigureHeader(headers.TARGET_HELPFUL, "left", true)
    local tDebuffPoint = ConfigureHeader(headers.TARGET_HARMFUL, "right", true)
    targetAnchored = AnchorTargetHeaders(tBuffPoint, tDebuffPoint)
    local targetOn = enabled and targetAnchored and self:GetSetting("targetEnabled") ~= false

    for btn in pairs(buttons) do
        Auras.ApplyButtonSize(btn)
    end
    headers.HELPFUL:SetShown(enabled)
    headers.HARMFUL:SetShown(enabled)
    headers.TARGET_HELPFUL:SetShown(targetOn)
    headers.TARGET_HARMFUL:SetShown(targetOn)
    SetBlizzardHidden(enabled and self:GetSetting("hideBlizzard") ~= false)
    self:RefreshAll()
    if demoActive then LayoutDemo() end
end

-- Out of combat, rebuild the target headers straight away when the
-- target changes; the header also refreshes itself on the target's
-- UNIT_AURA, which covers combat.
function addon:RefreshTarget()
    if InCombatLockdown() or not _G.SecureAuraHeader_Update then return end
    for _, key in ipairs({ "TARGET_HELPFUL", "TARGET_HARMFUL" }) do
        local h = headers[key]
        if h and h:IsVisible() then _G.SecureAuraHeader_Update(h) end
    end
end

function addon:QueueApply()
    if applyQueued then return end
    applyQueued = true
    C_Timer.After(0, function()
        applyQueued = false
        addon:ApplySettings()
    end)
end

function addon:Initialize()
    if headers.HELPFUL then return end
    -- Secure frames must not be created in combat.
    if InCombatLockdown() then
        self:On("PLAYER_REGEN_ENABLED", function()
            if not headers.HELPFUL then self:Initialize() end
        end)
        return
    end

    hiddenParent = CreateFrame("Frame")
    hiddenParent:Hide()
    CreateHeader("HELPFUL", "player", "HELPFUL", "BazUIAurasBuffs")
    CreateHeader("HARMFUL", "player", "HARMFUL", "BazUIAurasDebuffs")
    CreateHeader("TARGET_HELPFUL", "target", "HELPFUL", "BazUIAurasTargetBuffs")
    CreateHeader("TARGET_HARMFUL", "target", "HARMFUL", "BazUIAurasTargetDebuffs")

    -- One ticker for every duration label.
    local ticker = CreateFrame("Frame")
    ticker.elapsed = 0
    ticker:SetScript("OnUpdate", function(f, elapsed)
        f.elapsed = f.elapsed + elapsed
        if f.elapsed < TICK then return end
        f.elapsed = 0
        local now = GetTime()
        for btn in pairs(buttons) do
            if btn.expirationTime and btn:IsVisible() then
                UpdateDuration(btn, now)
            end
        end
        if demoActive then
            for _, btn in ipairs(demoButtons) do
                if btn.expirationTime and btn:IsVisible() then
                    UpdateDuration(btn, now)
                end
            end
        end
    end)

    self:On("UNIT_AURA", function(_, unit)
        if unit == "player" or unit == "target" then self:QueueRefresh() end
    end)
    self:On("PLAYER_TARGET_CHANGED", function()
        self:RefreshTarget()
        self:QueueRefresh()
    end)
    self:On("UNIT_INVENTORY_CHANGED", function(_, unit)
        if unit == "player" then self:QueueRefresh() end
    end)
    self:On("PLAYER_ENTERING_WORLD", function() self:QueueRefresh() end)
    self:On("PLAYER_REGEN_ENABLED", function()
        if pendingApply then self:ApplySettings() end
    end)
    self:On("PLAYER_REGEN_DISABLED", function()
        if demoActive then self:SetPreview(false) end
    end)
    self:OnProfileChanged(function() self:ApplySettings() end)

    -- Follow the unit frames: whenever Unit Frames re-applies either
    -- frame (enable, disable, scale, position), re-anchor after it.
    local uf = BazUI:GetModule("UnitFrames")
    if uf and uf.ApplySettings then
        hooksecurefunc(uf, "ApplySettings", function() addon:QueueApply() end)
    end
    if uf and uf.Target and uf.Target.ApplySettings then
        hooksecurefunc(uf.Target, "ApplySettings", function() addon:QueueApply() end)
    end

    self:ApplySettings()
end
