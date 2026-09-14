-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Unit Frames: a unit as bars
--
-- A unit is not a picture with bars on it. It is a few readings, and
-- each one is a bar that can sit wherever you want it: floating, under
-- an action bar, or under another bar. This builds those readings for
-- any unit, so the player and the target are the same code with the
-- unit as a parameter, and pet, target of target and party cost almost
-- nothing later.
--
-- Health and power are secure unit buttons, because clicking a unit's
-- health bar has to target it and right-clicking has to open its menu.
-- That was the portrait's hidden job and it is the one part of this that
-- has to be built secure from the start rather than added afterwards.
--
-- Everything about where a bar sits belongs to Core/Dock.lua. Nothing
-- here positions anything except by asking the dock to.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("UnitFrames")

local UnitBars = {}
addon.UnitBars = UnitBars

UnitBars.sets = {}      -- [unit] = { health = bar, power = bar, cast = bar }

local DEAD_COLOR = { 0.45, 0.45, 0.45, 1 }

---------------------------------------------------------------------------
-- Reading a unit
---------------------------------------------------------------------------

local function Number(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(math.floor(n))
end

local function HealthColor(unit)
    if addon:GetSetting("classColor") and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then return { color.r, color.g, color.b, 1 } end
    end
    if UnitIsDeadOrGhost(unit) then return DEAD_COLOR end
    return { 0.1, 0.8, 0.15, 1 }
end

local function PowerColor(unit)
    local powerType, token = UnitPowerType(unit)
    local color = PowerBarColor and (PowerBarColor[token] or PowerBarColor[powerType])
    if color then return { color.r, color.g, color.b, 1 } end
    return { 0.1, 0.3, 1, 1 }
end

-- What a bar says about itself. A health bar has more to say than an XP
-- bar, so the wording is a setting rather than a fixed format.
local function Format(mode, current, maximum, name)
    if mode == "name" then return name or "" end
    if maximum <= 0 then return "" end
    local percent = math.floor(current / maximum * 100 + 0.5)
    if mode == "percent" then return percent .. "%" end
    if mode == "current" then return Number(current) end
    if mode == "namePercent" then return string.format("%s  %d%%", name or "", percent) end
    return string.format("%s / %s", Number(current), Number(maximum))
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------

function UnitBars:UpdateHealth(unit)
    local set = self.sets[unit]
    if not (set and set.health) then return end
    local bar = set.health

    if not UnitExists(unit) then
        BazUI.Dock:SetShown(bar, false)
        return
    end
    BazUI.Dock:SetShown(bar, true)

    local maximum = math.max(1, UnitHealthMax(unit) or 1)
    local current = math.max(0, math.min(maximum, UnitHealth(unit) or 0))
    bar:SetValue(current / maximum)
    bar:SetFillColor(HealthColor(unit))

    local name = UnitName(unit) or ""
    if UnitIsGhost(unit) then
        bar:SetText(name ~= "" and (name .. "  Ghost") or "Ghost")
    elseif UnitIsDead(unit) then
        bar:SetText(name ~= "" and (name .. "  Dead") or "Dead")
    else
        bar:SetText(Format(addon:GetSetting("healthText") or "namePercent",
            current, maximum, name))
    end
end

function UnitBars:UpdatePower(unit)
    local set = self.sets[unit]
    if not (set and set.power) then return end
    local bar = set.power

    local powerType = UnitPowerType(unit)
    local maximum = math.max(0, UnitPowerMax(unit, powerType) or 0)
    if not UnitExists(unit) or maximum <= 0 then
        BazUI.Dock:SetShown(bar, false)
        return
    end
    BazUI.Dock:SetShown(bar, true)

    local current = math.max(0, math.min(maximum, UnitPower(unit, powerType) or 0))
    bar:SetValue(current / maximum)
    bar:SetFillColor(PowerColor(unit))
    bar:SetText(Format(addon:GetSetting("powerText") or "current", current, maximum))
end

function UnitBars:Update(unit)
    self:UpdateHealth(unit)
    self:UpdatePower(unit)
end

---------------------------------------------------------------------------
-- The cast bar
--
-- Its own bar now rather than a liquid inside a portrait. It fills as
-- the cast runs and empties as a channel does, and it holds its place in
-- a docked stack by default, since it appears and vanishes many times a
-- minute and a layout that shuffles mid-cast is worse than a gap.
---------------------------------------------------------------------------

local CAST_COLOR    = { 1.00, 0.82, 0.00, 1 }
local CHANNEL_COLOR = { 0.45, 0.68, 0.85, 1 }
local FAILED_COLOR  = { 0.85, 0.30, 0.30, 1 }

local function CastTick(bar)
    local state = bar._cast
    if not state then return end
    local now = GetTime() * 1000

    if state.fade then
        local left = 0.4 - (now / 1000 - state.fade)
        if left <= 0 then
            bar._cast = nil
            BazUI.Dock:SetShown(bar, false)
        else
            bar:SetAlpha(left / 0.4)
        end
        return
    end

    local span = state.endMS - state.startMS
    if span <= 0 then return end
    local elapsed = now - state.startMS
    if elapsed >= span then
        bar._cast = { fade = GetTime() }
        return
    end

    local fraction = elapsed / span
    bar:SetValue(state.channel and (1 - fraction) or fraction)
    bar:SetText(string.format("%s  %.1f", state.name or "", (span - elapsed) / 1000))
end

function UnitBars:StartCast(unit, name, startMS, endMS, channel, failed)
    local set = self.sets[unit]
    if not (set and set.cast) then return end
    local bar = set.cast

    if failed then
        bar._cast = { fade = GetTime(), name = name }
        bar:SetFillColor(FAILED_COLOR)
        bar:SetValue(1)
        bar:SetText(name or "Interrupted")
        return
    end

    bar:SetAlpha(1)
    bar:SetFillColor(channel and CHANNEL_COLOR or CAST_COLOR)
    bar._cast = { name = name, startMS = startMS, endMS = endMS, channel = channel }
    BazUI.Dock:SetShown(bar, true)
    CastTick(bar)
end

function UnitBars:StopCast(unit, interrupted)
    local set = self.sets[unit]
    if not (set and set.cast and set.cast._cast) then return end
    local bar = set.cast
    if interrupted then
        bar:SetFillColor(FAILED_COLOR)
        bar:SetText("Interrupted")
    end
    bar._cast = { fade = GetTime() }
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function UnitMenu(frame)
    local unit = frame:GetAttribute("unit") or "player"
    if _G.UnitPopup_OpenMenu then
        _G.UnitPopup_OpenMenu(unit == "player" and "SELF" or "TARGET",
            { unit = unit, fromPlayerFrame = unit == "player" })
    elseif _G.ToggleDropDownMenu then
        local menu = unit == "player" and _G.PlayerFrameDropDown or _G.TargetFrameDropDown
        if menu then _G.ToggleDropDownMenu(1, nil, menu, frame, 0, 0) end
    end
end

local function MakeBar(unit, key, opts)
    local name = "BazUI" .. unit:gsub("^%l", string.upper) .. key:gsub("^%l", string.upper) .. "Bar"
    local bar = BazUI.CreateStatusBar(name, UIParent, {
        style    = "screen",
        width    = opts.width,
        height   = opts.height,
        template = opts.secure and "SecureUnitButtonTemplate" or nil,
        textMode = opts.textMode,
    })
    bar:SetFrameStrata("LOW")

    if opts.secure then
        -- Left targets, right opens the unit's menu. Set once, out of
        -- combat, and never touched again.
        bar:SetAttribute("unit", unit)
        if _G.SecureUnitButton_OnLoad then
            _G.SecureUnitButton_OnLoad(bar, unit, UnitMenu)
        end
        bar:RegisterForClicks("AnyUp")
        bar:SetScript("OnEnter", function(self)
            self._hovered = true
            self:_RefreshText()
            if addon:GetSetting("unitTooltips") == false then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end)
        bar:SetScript("OnLeave", function(self)
            self._hovered = false
            self:_RefreshText()
            GameTooltip:Hide()
        end)
    end
    return bar
end

function UnitBars:Create(unit)
    if self.sets[unit] then return self.sets[unit] end
    if InCombatLockdown() then return nil end

    local width  = addon:GetSetting("barWidth") or 240
    local height = addon:GetSetting("barHeight") or 20
    local textMode = addon:GetSetting("barText") or "always"

    local set = {
        health = MakeBar(unit, "health", {
            width = width, height = height, secure = true, textMode = textMode }),
        power = MakeBar(unit, "power", {
            width = width, height = math.max(8, math.floor(height * 0.6)),
            secure = true, textMode = textMode }),
        cast = MakeBar(unit, "cast", {
            width = width, height = math.max(10, math.floor(height * 0.7)),
            textMode = "always" }),
    }
    self.sets[unit] = set

    -- Power follows health, cast follows power: a chain, so losing the
    -- unit takes the whole stack rather than leaving orphans behind.
    BazUI.Dock:Attach(set.power, set.health, { edge = "BOTTOM", order = 10 })
    BazUI.Dock:Attach(set.cast,  set.power,  { edge = "BOTTOM", order = 10, reserve = true })

    set.cast:SetScript("OnUpdate", function(self) CastTick(self) end)
    BazUI.Dock:SetShown(set.cast, false)
    return set
end


---------------------------------------------------------------------------
-- Moving them
--
-- The bars are secure, so they cannot be dragged in combat, and Edit
-- Mode can be open during one. Each stack therefore gets an ordinary
-- frame standing in for it: that is what Edit Mode moves, and the real
-- bars follow once it is safe. The same trick the XP bar uses, and the
-- reason nothing here ever touches a protected frame at the wrong time.
--
-- Only the head of a chain gets a mover. Power and cast follow their
-- host through the dock, so moving them individually would be a lie.
---------------------------------------------------------------------------

local LABELS = { player = "Player Bars", target = "Target Bars" }

function UnitBars:PositionKey(unit)
    return unit == "target" and "targetBarPos" or "playerBarPos"
end

function UnitBars:ApplyPosition(unit)
    local set = self.sets[unit]
    if not set or InCombatLockdown() then return end
    local pos = addon:GetSetting(self:PositionKey(unit))
        or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    set.health:ClearAllPoints()
    set.health:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    BazUI.Dock:Relayout(set.health)
end

function UnitBars:SavePosition(unit)
    local mover = self.movers and self.movers[unit]
    if not mover then return end
    mover:StopMovingOrSizing()
    local x, y = mover:GetCenter()
    if not x then return end
    local factor = mover:GetEffectiveScale() / UIParent:GetEffectiveScale()
    addon:SetSetting(self:PositionKey(unit), {
        point = "CENTER", relPoint = "BOTTOMLEFT", x = x * factor, y = y * factor })
    self:ApplyPosition(unit)
end

function UnitBars:RefreshMover(unit)
    local mover = self.movers and self.movers[unit]
    local set = self.sets[unit]
    if not (mover and set) then return end

    -- The mover covers the whole stack, so what you grab is what moves.
    local height = 0
    for _, key in ipairs({ "health", "power", "cast" }) do
        local bar = set[key]
        if bar and bar:IsShown() then height = height + bar:GetHeight() + 2 end
    end
    mover:SetSize(set.health:GetWidth(), math.max(24, height))
    mover:ClearAllPoints()
    mover:SetPoint("TOP", set.health, "TOP", 0, 0)
end

function UnitBars:CreateMover(unit)
    self.movers = self.movers or {}
    if self.movers[unit] then return self.movers[unit] end

    local mover = CreateFrame("Frame", "BazUI" .. unit .. "BarsMover", UIParent)
    mover:SetFrameStrata("DIALOG")
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    local tint = mover:CreateTexture(nil, "BACKGROUND")
    tint:SetAllPoints(mover)
    tint:SetColorTexture(0.15, 0.5, 0.8, 0.35)

    local label = BazUI.Skin.Theme.FontString(mover, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(LABELS[unit] or unit)

    mover:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    mover:SetScript("OnDragStop", function() UnitBars:SavePosition(unit) end)

    self.movers[unit] = mover

    BazUI:RegisterEditModeFrame(mover, {
        label = LABELS[unit] or unit,
        addonName = "UnitFrames",
        positionKey = false,
        settings = BazUI:BuildEditModeArrayFromSpec("UnitFrames"),
        onPositionChanged = function() UnitBars:SavePosition(unit) end,
        onEnter = function() UnitBars:ShowMover(unit) end,
        onExit  = function() UnitBars:ShowMover(unit) end,
    })
    return mover
end

function UnitBars:ShowMover(unit)
    local mover = self.movers and self.movers[unit]
    if not mover then return end
    local editing = BazUI:IsEditMode()
    mover:SetShown(editing and not InCombatLockdown())
    if editing then self:RefreshMover(unit) end
end

---------------------------------------------------------------------------
-- Size and text, applied to a stack that already exists
---------------------------------------------------------------------------

function UnitBars:ApplySettings(unit)
    local set = self.sets[unit]
    if not set or InCombatLockdown() then return end

    local width  = math.max(80, math.min(900, addon:GetSetting("barWidth") or 240))
    local height = math.max(10, math.min(40, addon:GetSetting("barHeight") or 20))
    local mode   = addon:GetSetting("barText") or "always"

    set.health:SetBarSize(width, height)
    set.power:SetBarSize(width, math.max(8, math.floor(height * 0.6)))
    set.cast:SetBarSize(width, math.max(10, math.floor(height * 0.7)))
    for _, key in ipairs({ "health", "power", "cast" }) do
        set[key]:SetTextMode(mode)
    end

    self:ApplyPosition(unit)
    self:Update(unit)
    self:RefreshMover(unit)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local watchers = {}

function UnitBars:Watch(unit)
    if watchers[unit] then return end
    local frame = CreateFrame("Frame")
    watchers[unit] = frame

    for _, event in ipairs({
        "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER", "UNIT_CONNECTION", "UNIT_NAME_UPDATE",
    }) do
        pcall(frame.RegisterUnitEvent, frame, event, unit)
    end
    for _, event in ipairs({
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_CHANNEL_UPDATE",
    }) do
        pcall(frame.RegisterUnitEvent, frame, event, unit)
    end
    if unit == "target" then frame:RegisterEvent("PLAYER_TARGET_CHANGED") end
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    frame:SetScript("OnEvent", function(_, event)
        if event:find("SPELLCAST") then
            UnitBars:SyncCast(unit, event)
        else
            UnitBars:Update(unit)
        end
    end)
end

function UnitBars:SyncCast(unit, event)
    if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        self:StopCast(unit, false)
        return
    end
    if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        self:StopCast(unit, true)
        return
    end

    local name, _, _, startMS, endMS = UnitCastingInfo(unit)
    local channel = false
    if not name then
        name, _, _, startMS, endMS = UnitChannelInfo(unit)
        channel = name ~= nil
    end
    if name and startMS and endMS then
        self:StartCast(unit, name, startMS, endMS, channel)
    else
        self:StopCast(unit, false)
    end
end
