-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Unit Frames: bars you create
--
-- A bar here works the way an action bar does: you make one, it gets a
-- name, and it turns up in every list of things that can be docked to.
-- What it reads is a property of the bar rather than a different kind of
-- object, so health, power, casting, experience and reputation are one
-- implementation with a `kind` on it.
--
-- That also means nothing stops you making three health bars. There is
-- no reason to forbid it: people find uses for a thing you did not
-- imagine, and the only cost of allowing it is not writing the code that
-- would have prevented it.
--
-- Each bar owns where it sits: floating at a saved position, or docked
-- to an action bar or another bar, above or below. One choice, made on
-- the bar itself, rather than a grid of settings elsewhere describing
-- every combination.
--
-- Health and power bars are secure unit buttons, because clicking one
-- has to target and right-clicking has to open the unit menu. Whether
-- they are on screen belongs to RegisterUnitWatch, which does it in the
-- secure environment and so keeps working in combat.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("UnitFrames")

local UnitBars = {}
addon.UnitBars = UnitBars

UnitBars.bars = {}          -- [id] = { def, frame, mover }

local DEAD_COLOR    = { 0.45, 0.45, 0.45, 1 }
local CAST_COLOR    = { 1.00, 0.82, 0.00, 1 }
local CHANNEL_COLOR = { 0.45, 0.68, 0.85, 1 }
local FAILED_COLOR  = { 0.85, 0.30, 0.30, 1 }

-- What a bar can read. Everything else about it is the same.
UnitBars.KINDS = {
    health = "Health",
    power  = "Power",
    cast   = "Casting",
    xp     = "Experience",
    rep    = "Reputation",
}

UnitBars.UNITS = {
    player = "Player",
    target = "Target",
    pet    = "Pet",
}

local function IsUnitKind(kind)
    return kind == "health" or kind == "power" or kind == "cast"
end
UnitBars.IsUnitKind = IsUnitKind

---------------------------------------------------------------------------
-- The list of bars
---------------------------------------------------------------------------

function UnitBars:Defs()
    local defs = addon:GetSetting("statusBars")
    if type(defs) ~= "table" then
        defs = {}
        addon:SetSetting("statusBars", defs)
    end
    return defs
end

function UnitBars:Def(id)
    for _, def in ipairs(self:Defs()) do
        if def.id == id then return def end
    end
end

function UnitBars:NextID()
    local highest = 0
    for _, def in ipairs(self:Defs()) do
        if def.id > highest then highest = def.id end
    end
    return highest + 1
end

function UnitBars:DefaultName(kind, unit)
    if IsUnitKind(kind) then
        return (self.UNITS[unit] or unit) .. " " .. (self.KINDS[kind] or kind)
    end
    return self.KINDS[kind] or kind
end

function UnitBars:HostID(id)
    return "statusbar:" .. id
end

function UnitBars:Add(kind, unit)
    if InCombatLockdown() then return nil end
    kind, unit = kind or "health", unit or "player"

    local defs = self:Defs()
    local def = {
        id         = self:NextID(),
        kind       = kind,
        unit       = unit,
        width      = 240,
        height     = 20,
        textMode   = "always",
        textFormat = (kind == "power" or kind == "cast") and "current" or "namePercent",
        dock       = { host = "float", edge = "BOTTOM" },
        position   = { point = "CENTER", relPoint = "CENTER", x = 0, y = -160 },
    }
    def.name = self:DefaultName(kind, unit)
    defs[#defs + 1] = def
    self:Save()
    self:Build(def)
    return def
end

function UnitBars:Remove(id)
    if InCombatLockdown() then return false end
    local defs = self:Defs()
    for i, def in ipairs(defs) do
        if def.id == id then
            local bar = self.bars[id]
            if bar then
                BazUI.Dock:Detach(bar.frame)
                BazUI.Dock:UnregisterHost(self:HostID(id))
                bar.frame:Hide()
                if bar.mover then
                    BazUI:UnregisterEditModeFrame(bar.mover)
                    bar.mover:Hide()
                end
                self.bars[id] = nil
            end
            table.remove(defs, i)
            self:Save()
            return true
        end
    end
    return false
end

function UnitBars:Save()
    addon:SetSetting("statusBars", self:Defs())
end

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

-- What a bar says about itself. A health bar has more to say than an
-- experience bar, so the wording is the bar's own setting.
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
-- Filling a bar in
---------------------------------------------------------------------------

local function UpdateHealth(bar)
    local unit = bar.def.unit
    if not UnitExists(unit) then return end
    local maximum = math.max(1, UnitHealthMax(unit) or 1)
    local current = math.max(0, math.min(maximum, UnitHealth(unit) or 0))
    bar.frame:SetValue(current / maximum)
    bar.frame:SetFillColor(HealthColor(unit))

    local name = UnitName(unit) or ""
    if UnitIsGhost(unit) then
        bar.frame:SetText(name ~= "" and (name .. "  Ghost") or "Ghost")
    elseif UnitIsDead(unit) then
        bar.frame:SetText(name ~= "" and (name .. "  Dead") or "Dead")
    else
        bar.frame:SetText(Format(bar.def.textFormat, current, maximum, name))
    end
end

local function UpdatePower(bar)
    local unit = bar.def.unit
    if not UnitExists(unit) then return end
    local powerType = UnitPowerType(unit)
    local maximum = math.max(0, UnitPowerMax(unit, powerType) or 0)

    -- A unit with no power keeps its slot and fades. Hiding would be a
    -- protected call; alpha is not, so this still works mid-fight.
    bar.frame:SetAlpha(maximum > 0 and 1 or 0)
    if maximum <= 0 then
        bar.frame:SetText("")
        return
    end

    local current = math.max(0, math.min(maximum, UnitPower(unit, powerType) or 0))
    bar.frame:SetValue(current / maximum)
    bar.frame:SetFillColor(PowerColor(unit))
    bar.frame:SetText(Format(bar.def.textFormat, current, maximum))
end

local function UpdateXP(bar)
    local maximum = math.max(0, UnitXPMax("player") or 0)
    local current = math.max(0, math.min(maximum, UnitXP("player") or 0))
    local rested = math.max(0, GetXPExhaustion() or 0)
    bar.frame:SetValue(maximum > 0 and current / maximum or 0)
    bar.frame:SetOverlay(maximum > 0 and rested / maximum or 0)
    bar.frame:SetFillColor({ 0.57, 0.16, 0.85, 1 })
    bar.frame:SetText(maximum > 0
        and Format(bar.def.textFormat, current, maximum, "Level " .. (UnitLevel("player") or 1))
        or "Maximum level")
end

local function UpdateRep(bar)
    local name, min, max, value
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local data = C_Reputation.GetWatchedFactionData()
        if data then
            name = data.name
            min, max, value = data.currentReactionThreshold,
                data.nextReactionThreshold, data.currentStanding
        end
    elseif _G.GetWatchedFactionInfo then
        local n, _, low, high, current = _G.GetWatchedFactionInfo()
        name, min, max, value = n, low, high, current
    end

    if not name or name == "" then
        bar.frame:SetValue(0)
        bar.frame:SetText("No faction watched")
        return
    end
    local span = math.max(1, (max or 0) - (min or 0))
    bar.frame:SetValue(math.min(1, ((value or 0) - (min or 0)) / span))
    bar.frame:SetFillColor({ 0.35, 0.65, 0.35, 1 })
    bar.frame:SetText(Format(bar.def.textFormat, (value or 0) - (min or 0), span, name))
end

---------------------------------------------------------------------------
-- Casting
---------------------------------------------------------------------------

local function CastTick(frame)
    local state = frame._cast
    if not state then return end

    if state.fade then
        local left = 0.4 - (GetTime() - state.fade)
        if left <= 0 then
            frame._cast = nil
            BazUI.Dock:SetShown(frame, false)
        else
            frame:SetAlpha(left / 0.4)
        end
        return
    end

    local now = GetTime() * 1000
    local span = state.endMS - state.startMS
    if span <= 0 then return end
    local elapsed = now - state.startMS
    if elapsed >= span then
        frame._cast = { fade = GetTime() }
        return
    end

    local fraction = elapsed / span
    frame:SetValue(state.channel and (1 - fraction) or fraction)
    frame:SetText(string.format("%s  %.1f", state.name or "", (span - elapsed) / 1000))
end

function UnitBars:SyncCast(bar)
    if bar.def.kind ~= "cast" then return end
    local unit, frame = bar.def.unit, bar.frame

    local name, _, _, startMS, endMS = UnitCastingInfo(unit)
    local channel = false
    if not name then
        name, _, _, startMS, endMS = UnitChannelInfo(unit)
        channel = name ~= nil
    end

    if name and startMS and endMS then
        frame:SetAlpha(1)
        frame:SetFillColor(channel and CHANNEL_COLOR or CAST_COLOR)
        frame._cast = { name = name, startMS = startMS, endMS = endMS, channel = channel }
        BazUI.Dock:SetShown(frame, true)
        CastTick(frame)
    elseif frame._cast and not frame._cast.fade then
        frame._cast = { fade = GetTime() }
    end
end

function UnitBars:FailCast(bar)
    if bar.def.kind ~= "cast" then return end
    local frame = bar.frame
    if not frame._cast then return end
    frame:SetFillColor(FAILED_COLOR)
    frame:SetText("Interrupted")
    frame._cast = { fade = GetTime() }
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------

function UnitBars:Update(bar)
    if not (bar and bar.frame) then return end
    local kind = bar.def.kind
    if kind == "health" then UpdateHealth(bar)
    elseif kind == "power" then UpdatePower(bar)
    elseif kind == "xp" then UpdateXP(bar)
    elseif kind == "rep" then UpdateRep(bar)
    end
end

function UnitBars:UpdateAll()
    for _, bar in pairs(self.bars) do self:Update(bar) end
end

function UnitBars:ForKind(kind, unit, fn)
    for _, bar in pairs(self.bars) do
        if bar.def.kind == kind and (not unit or bar.def.unit == unit) then fn(bar) end
    end
end

---------------------------------------------------------------------------
-- Building one
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

function UnitBars:Build(def)
    if self.bars[def.id] then return self.bars[def.id] end
    if InCombatLockdown() then return nil end

    local secure = (def.kind == "health" or def.kind == "power")
    local frame = BazUI.CreateStatusBar("BazUIStatusBar" .. def.id, UIParent, {
        style    = "screen",
        width    = def.width or 240,
        height   = def.height or 20,
        textMode = def.textMode or "always",
        template = secure and "SecureUnitButtonTemplate" or nil,
    })
    frame:SetFrameStrata("LOW")

    local bar = { def = def, frame = frame }
    self.bars[def.id] = bar
    frame._bazBar = bar

    if secure then
        frame:SetAttribute("unit", def.unit)
        if _G.SecureUnitButton_OnLoad then
            _G.SecureUnitButton_OnLoad(frame, def.unit, UnitMenu)
        end
        frame:RegisterForClicks("AnyUp")
        -- The game shows and hides it as the unit comes and goes, in the
        -- secure environment, so it keeps working during a fight.
        if _G.RegisterUnitWatch then _G.RegisterUnitWatch(frame) end
        frame:SetScript("OnEnter", function(self)
            self._hovered = true
            self:_RefreshText()
            if addon:GetSetting("unitTooltips") == false then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetUnit(def.unit)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function(self)
            self._hovered = false
            self:_RefreshText()
            GameTooltip:Hide()
        end)
    end

    if def.kind == "cast" then
        frame:SetScript("OnUpdate", function(self) CastTick(self) end)
        BazUI.Dock:SetShown(frame, false)
    end

    -- Every bar is somewhere another bar can dock to.
    BazUI.Dock:RegisterHost(self:HostID(def.id), frame,
        def.name or ("Bar " .. def.id), 30)

    self:CreateMover(bar)
    self:Apply(bar)
    return bar
end

function UnitBars:BuildAll()
    if InCombatLockdown() then return end
    for _, def in ipairs(self:Defs()) do self:Build(def) end
    self:UpdateAll()
end

---------------------------------------------------------------------------
-- Applying one bar's settings
---------------------------------------------------------------------------

function UnitBars:Apply(bar)
    if not bar or InCombatLockdown() then return end
    local def, frame = bar.def, bar.frame

    -- Coming off a host, keep the width it has been wearing. A docked
    -- bar's width belongs to its host, so its own setting has been
    -- untouched and probably still says whatever it was created with;
    -- reverting to that makes the bar jump smaller for no reason the
    -- player can see.
    local wasDocked = BazUI.Dock:IsDocked(frame)
    local goingFloat = not def.dock or def.dock.host == "float"
    if wasDocked and goingFloat then
        local width = frame:GetWidth()
        if width and width > 0 then def.width = math.floor(width + 0.5) end
    end

    frame:SetBarSize(math.max(60, math.min(1200, def.width or 240)),
        math.max(8, math.min(48, def.height or 20)))
    frame:SetTextMode(def.textMode or "always")

    local dock = def.dock or { host = "float" }
    BazUI.Dock:AttachTo(frame, dock.host, {
        edge    = dock.edge or "BOTTOM",
        mode    = "stretch",
        order   = def.id,
        reserve = def.kind == "cast",
    })

    -- A docked bar is placed by its host; the saved position is only for
    -- one that floats.
    if not BazUI.Dock:IsDocked(frame) then
        local pos = def.position or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end
    BazUI.Dock:Relayout(frame)

    if bar.mover then BazUI:UpdateEditModeLabel(bar.mover, def.name) end
    -- ShowMover rather than RefreshMover: a bar made while Edit Mode is
    -- already open has missed the event that reveals handles, so without
    -- this its handle stays hidden until you leave and come back.
    self:ShowMover(bar)
    self:Update(bar)
end

function UnitBars:ApplyAll()
    for _, bar in pairs(self.bars) do self:Apply(bar) end
end

---------------------------------------------------------------------------
-- Moving one, and dropping it onto something
--
-- The bars are secure, so they cannot be dragged during combat, and Edit
-- Mode can be open in one. Each bar therefore gets an ordinary frame
-- standing in for it: that is what Edit Mode moves, and the bar follows
-- once it is safe.
--
-- Dropping a mover near the edge of another bar or an action bar docks
-- it there, which is the way anyone would expect to arrange these. Let
-- go anywhere else and it simply floats at the position it was dropped.
---------------------------------------------------------------------------

local SNAP_DISTANCE = 36

-- Frame coordinates are reported in the frame's own scale, so two frames
-- at different scales cannot be compared directly. Everything here is
-- converted to screen pixels first, which is the only space they share.
-- An action bar carries a scale of its own, so skipping this is why the
-- first attempt never matched anything.
local function ScreenEdges(frame)
    local scale = frame:GetEffectiveScale() or 1
    local left, right = frame:GetLeft(), frame:GetRight()
    local top, bottom = frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return nil end
    return left * scale, right * scale, top * scale, bottom * scale
end

-- The closest edge worth snapping to, or nothing.
--
-- Docking below a host means this bar's top meeting the host's bottom,
-- so the comparison is edge to edge. Measuring from the middle of the
-- bar, as this first did, is half a bar's height out before anything
-- else goes wrong.
local function NearestDock(mover, selfFrame)
    local left, right, top, bottom = ScreenEdges(mover)
    if not left then return nil end

    local best, bestDistance
    for _, host in ipairs(BazUI.Dock:GetHosts()) do
        local frame = BazUI.Dock:GetHostFrame(host.id)
        -- Never onto itself, onto something hidden, or onto something
        -- already hanging off it, which would be a loop.
        if frame and frame ~= selfFrame and frame:IsVisible()
            and not BazUI.Dock:Follows(frame, selfFrame) then

            local hLeft, hRight, hTop, hBottom = ScreenEdges(frame)
            -- Any horizontal overlap at all is enough. Requiring the
            -- centres to line up meant a wide action bar and a narrow
            -- bar rarely agreed.
            if hLeft and left < hRight and right > hLeft then
                local candidates = {
                    { edge = "BOTTOM", distance = math.abs(hBottom - top) },
                    { edge = "TOP",    distance = math.abs(hTop - bottom) },
                }
                for _, candidate in ipairs(candidates) do
                    if candidate.distance < SNAP_DISTANCE
                        and (not bestDistance or candidate.distance < bestDistance) then
                        best = { host = host.id, edge = candidate.edge }
                        bestDistance = candidate.distance
                    end
                end
            end
        end
    end
    return best
end

-- Where it will land, drawn on the host rather than on the handle.
--
-- Edit Mode puts its own overlay on top of anything registered with it,
-- so recolouring the handle is invisible: the overlay is what you are
-- looking at. Marking the target edge instead is both visible and
-- clearer about what is going to happen.
local snapLine

local function SnapLine()
    if snapLine then return snapLine end
    snapLine = CreateFrame("Frame", nil, UIParent)
    snapLine:SetFrameStrata("TOOLTIP")
    snapLine:Hide()

    snapLine.bar = snapLine:CreateTexture(nil, "OVERLAY")
    snapLine.bar:SetAllPoints()
    snapLine.bar:SetColorTexture(0.35, 1, 0.45, 0.95)

    snapLine.glow = snapLine:CreateTexture(nil, "ARTWORK")
    snapLine.glow:SetPoint("TOPLEFT", -2, 6)
    snapLine.glow:SetPoint("BOTTOMRIGHT", 2, -6)
    snapLine.glow:SetColorTexture(0.35, 1, 0.45, 0.25)

    snapLine.text = BazUI.Skin.Theme.FontString(snapLine, "OVERLAY", "GameFontNormal")
    snapLine.text:SetPoint("BOTTOM", snapLine, "TOP", 0, 4)
    snapLine.text:SetTextColor(0.5, 1, 0.55)
    return snapLine
end

local function ShowSnapLine(snap)
    if not snap then
        if snapLine then snapLine:Hide() end
        return
    end
    local host = BazUI.Dock:GetHostFrame(snap.host)
    if not host then return end

    local line = SnapLine()
    local label
    for _, entry in ipairs(BazUI.Dock:GetHosts()) do
        if entry.id == snap.host then label = entry.label break end
    end

    line:ClearAllPoints()
    line:SetPoint("LEFT", host, "LEFT", 0, 0)
    line:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    line:SetHeight(3)
    if snap.edge == "BOTTOM" then
        line:SetPoint("TOP", host, "BOTTOM", 0, 1)
    else
        line:SetPoint("BOTTOM", host, "TOP", 0, -1)
    end
    line.text:SetText((snap.edge == "BOTTOM" and "Below " or "Above ") .. (label or "here"))
    line:Show()
end

-- Says what the snap test can see, for when it insists nothing is near.
function UnitBars:DescribeSnap()
    local hosts = BazUI.Dock:GetHosts()
    addon:Print(("Snap targets: %d"):format(#hosts))
    for _, host in ipairs(hosts) do
        local frame = BazUI.Dock:GetHostFrame(host.id)
        local l, r, t, b
        if frame then l, r, t, b = ScreenEdges(frame) end
        addon:Print(("  %s (%s): %s"):format(host.label, host.id,
            l and ("%d..%d wide, top %d bottom %d"):format(l, r, t, b) or "no geometry"))
    end
end

function UnitBars:SavePosition(bar)
    local mover = bar.mover
    if not mover then return end
    mover:StopMovingOrSizing()

    local snap = NearestDock(mover, bar.frame)
    if snap then
        bar.def.dock = { host = snap.host, edge = snap.edge }
    else
        local x, y = mover:GetCenter()
        if x then
            local factor = mover:GetEffectiveScale() / UIParent:GetEffectiveScale()
            bar.def.dock = { host = "float", edge = bar.def.dock and bar.def.dock.edge or "BOTTOM" }
            bar.def.position = { point = "CENTER", relPoint = "BOTTOMLEFT",
                x = x * factor, y = y * factor }
        end
    end
    self:Save()
    self:Apply(bar)
end

function UnitBars:RefreshMover(bar)
    local mover = bar and bar.mover
    if not mover then return end
    mover:SetSize(math.max(60, bar.frame:GetWidth()), math.max(20, bar.frame:GetHeight()))
    mover:ClearAllPoints()
    mover:SetPoint("CENTER", bar.frame, "CENTER", 0, 0)
end


---------------------------------------------------------------------------
-- The Edit Mode panel for one bar
--
-- Selecting a bar in Edit Mode should offer the same choices its options
-- page does, since that is where you are when you want them. Edit Mode
-- takes an array of widgets with their own get and set, which suits a
-- per-bar setting exactly: there is no module-wide key to point at.
---------------------------------------------------------------------------

local function ValuesArray(map)
    local out = {}
    for value, label in pairs(map) do
        out[#out + 1] = { label = label, value = value }
    end
    table.sort(out, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return out
end

local TEXT_MODES = { always = "Always", hover = "On Hover", never = "Never" }
local TEXT_FORMATS = {
    ["current/max"] = "Current / Max",
    current         = "Current",
    percent         = "Percent",
    name            = "Name",
    namePercent     = "Name and percent",
}
local EDGES = { BOTTOM = "Below", TOP = "Above" }

function UnitBars:EditSettings(bar)
    local def = bar.def

    local function Refresh()
        UnitBars:Save()
        UnitBars:Apply(bar)
    end

    -- Rebuilt each time the panel opens, so the list of things to dock
    -- to is whatever exists right now.
    local dockOptions = { { label = "Floating", value = "float" } }
    for _, host in ipairs(BazUI.Dock:GetHosts()) do
        local frame = BazUI.Dock:GetHostFrame(host.id)
        if frame and frame ~= bar.frame
            and not BazUI.Dock:Follows(frame, bar.frame) then
            dockOptions[#dockOptions + 1] = { label = host.label, value = host.id }
        end
    end

    return {
        { type = "dropdown", section = "Docking", label = "Dock to",
          options = dockOptions,
          get = function() return (def.dock and def.dock.host) or "float" end,
          set = function(value)
              def.dock = { host = value, edge = (def.dock and def.dock.edge) or "BOTTOM" }
              Refresh()
          end },
        { type = "dropdown", section = "Docking", label = "On the",
          options = ValuesArray(EDGES),
          get = function() return (def.dock and def.dock.edge) or "BOTTOM" end,
          set = function(value)
              def.dock = { host = (def.dock and def.dock.host) or "float", edge = value }
              Refresh()
          end },

        { type = "slider", section = "Size", label = "Width",
          min = 60, max = 1200, step = 5,
          get = function() return def.width or 240 end,
          set = function(value) def.width = value Refresh() end },
        { type = "slider", section = "Size", label = "Height",
          min = 8, max = 48, step = 1,
          get = function() return def.height or 20 end,
          set = function(value) def.height = value Refresh() end },

        { type = "dropdown", section = "Text", label = "Show text",
          options = ValuesArray(TEXT_MODES),
          get = function() return def.textMode or "always" end,
          set = function(value) def.textMode = value Refresh() end },
        { type = "dropdown", section = "Text", label = "Text says",
          options = ValuesArray(TEXT_FORMATS),
          get = function() return def.textFormat or "namePercent" end,
          set = function(value) def.textFormat = value Refresh() end },

        { type = "nudge", section = "Position" },
    }
end

function UnitBars:CreateMover(bar)
    if bar.mover then return bar.mover end
    local def = bar.def

    local mover = CreateFrame("Frame", "BazUIStatusBarMover" .. def.id, UIParent)
    mover:SetFrameStrata("DIALOG")
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    local tint = mover:CreateTexture(nil, "BACKGROUND")
    tint:SetAllPoints(mover)
    tint:SetColorTexture(0.15, 0.5, 0.8, 0.35)
    mover.tint = tint

    local label = BazUI.Skin.Theme.FontString(mover, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(def.name or ("Bar " .. def.id))
    mover.label = label

    mover:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    mover:SetScript("OnDragStop", function() UnitBars:SavePosition(bar) end)

    -- While it is being dragged, say whether letting go would dock it,
    -- and to what.
    --
    -- Edit Mode drags through an overlay of its own and marks the frame
    -- isDragging, so that is the flag to watch; isMoving covers a drag
    -- by the mover's own handle. Watching the wrong one is why this
    -- never fired.
    --
    -- The signal is the border and the words, not the fill: the fill is
    -- translucent and sits over the bar itself, so a green wash over a
    -- green health bar says nothing at all.
    mover:SetScript("OnUpdate", function(self)
        if not (self.isDragging or self.isMoving) then
            if self._snapShown then self:ShowSnap(nil) end
            return
        end

        -- The bar follows the handle while it is being dragged rather
        -- than jumping to it on release. Edit Mode moves the mover, so
        -- for the drag the anchoring runs that way round; it is put back
        -- the other way when the drag ends. Moving a secure frame is
        -- protected, so none of this happens in combat.
        if not InCombatLockdown() then
            bar.frame:ClearAllPoints()
            bar.frame:SetPoint("CENTER", self, "CENTER", 0, 0)
            BazUI.Dock:Relayout(bar.frame)
        end

        self:ShowSnap(NearestDock(self, bar.frame))
    end)

    function mover:ShowSnap(snap)
        self._snapShown = snap and true or false
        ShowSnapLine(snap)
    end

    mover:HookScript("OnDragStart", function(self) self.isMoving = true end)
    mover:HookScript("OnDragStop", function(self)
        self.isMoving = false
        self:ShowSnap(nil)
    end)

    bar.mover = mover

    -- The handle is a picture of the bar, so it tracks the bar itself
    -- rather than waiting to be told. A bar resized by its host, at any
    -- depth of the chain, drags its handle along without every caller
    -- having to remember to refresh it.
    bar.frame:HookScript("OnSizeChanged", function()
        UnitBars:RefreshMover(bar)
    end)

    BazUI:RegisterEditModeFrame(mover, {
        label = def.name or ("Bar " .. def.id),
        addonName = "UnitFrames",
        positionKey = false,
        settings = UnitBars:EditSettings(bar),
        onPositionChanged = function()
            if mover.ShowSnap then mover:ShowSnap(nil) end
            UnitBars:SavePosition(bar)
        end,
        onEnter = function() UnitBars:ShowMover(bar) end,
        onExit  = function() UnitBars:ShowMover(bar) end,
    })
    return mover
end

function UnitBars:ShowMover(bar)
    local mover = bar and bar.mover
    if not mover then return end
    local editing = BazUI:IsEditMode()
    mover:SetShown(editing and not InCombatLockdown())
    if editing then self:RefreshMover(bar) end
end

function UnitBars:ShowAllMovers()
    for _, bar in pairs(self.bars) do self:ShowMover(bar) end
end

-- The list of things a bar can dock to is whatever exists at the moment
-- you look, so every bar's panel is rebuilt when Edit Mode opens and
-- whenever a bar is made or removed.
function UnitBars:RefreshEditSettings()
    for _, bar in pairs(self.bars) do
        if bar.mover then
            BazUI:UpdateEditModeSettings(bar.mover, self:EditSettings(bar))
        end
    end
end

---------------------------------------------------------------------------
-- Events
--
-- One watcher per unit, feeding every bar that reads that unit, so ten
-- health bars cost one registration rather than ten.
---------------------------------------------------------------------------

local watchers = {}

function UnitBars:Watch(unit)
    if watchers[unit] then return end
    local frame = CreateFrame("Frame")
    watchers[unit] = frame

    for _, event in ipairs({
        "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER", "UNIT_CONNECTION", "UNIT_NAME_UPDATE",
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_CHANNEL_UPDATE",
    }) do
        pcall(frame.RegisterUnitEvent, frame, event, unit)
    end
    if unit == "target" then frame:RegisterEvent("PLAYER_TARGET_CHANGED") end

    frame:SetScript("OnEvent", function(_, event)
        if event:find("SPELLCAST") then
            local failed = (event == "UNIT_SPELLCAST_FAILED"
                or event == "UNIT_SPELLCAST_INTERRUPTED")
            UnitBars:ForKind("cast", unit, function(bar)
                if failed then UnitBars:FailCast(bar) else UnitBars:SyncCast(bar) end
            end)
        else
            for _, bar in pairs(UnitBars.bars) do
                if bar.def.unit == unit then UnitBars:Update(bar) end
            end
        end
    end)
end

function UnitBars:WatchAll()
    local seen = {}
    for _, def in ipairs(self:Defs()) do
        if IsUnitKind(def.kind) and not seen[def.unit] then
            seen[def.unit] = true
            self:Watch(def.unit)
        end
    end

    if not watchers._player then
        watchers._player = CreateFrame("Frame")
        for _, event in ipairs({
            "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
            "UPDATE_FACTION", "PLAYER_ENTERING_WORLD",
        }) do
            pcall(watchers._player.RegisterEvent, watchers._player, event)
        end
        watchers._player:SetScript("OnEvent", function() UnitBars:UpdateAll() end)
    end
end

---------------------------------------------------------------------------
-- Making one from Edit Mode
--
-- Every kind this can draw, offered on the panel's Create button. The
-- unit ones open a submenu of whose health or power it should read; the
-- rest are about you and need no such question.
---------------------------------------------------------------------------

local KIND_ORDER = { "health", "power", "cast", "xp", "rep" }
local UNIT_ORDER = { "player", "target", "pet" }

function UnitBars:RegisterCreator()
    BazUI:RegisterEditModeCreator("Bars and readouts", function()
        local items = {}
        for _, kind in ipairs(KIND_ORDER) do
            local label = UnitBars.KINDS[kind]
            if IsUnitKind(kind) then
                local submenu = {}
                for _, unit in ipairs(UNIT_ORDER) do
                    submenu[#submenu + 1] = {
                        label = UnitBars.UNITS[unit],
                        onClick = function()
                            local def = UnitBars:Add(kind, unit)
                            if def then addon:Print("Created " .. def.name) end
                        end,
                    }
                end
                items[#items + 1] = { label = label .. " bar", submenu = submenu }
            else
                items[#items + 1] = {
                    label = label .. " bar",
                    onClick = function()
                        local def = UnitBars:Add(kind)
                        if def then addon:Print("Created " .. def.name) end
                    end,
                }
            end
        end
        return items
    end)
end
