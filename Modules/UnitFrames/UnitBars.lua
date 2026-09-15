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

-- Edit Mode shows bars for units that are not there, so a layout can
-- be arranged while solo. See SetPreview.
local previewing = false

local DEAD_COLOR    = { 0.45, 0.45, 0.45, 1 }
local OFFLINE_COLOR = { 0.35, 0.35, 0.40, 1 }
local CAST_COLOR    = { 1.00, 0.82, 0.00, 1 }
local CHANNEL_COLOR = { 0.45, 0.68, 0.85, 1 }
local FAILED_COLOR  = { 0.85, 0.30, 0.30, 1 }

-- What a bar can read. Everything else about it is the same.
UnitBars.KINDS = {
    health = "Health",
    power  = "Power",
    cast   = "Casting",
    xp     = "XP",
    rep    = "Reputation",
}

UnitBars.UNITS = {
    player = "Player",
    target = "Target",
    pet    = "Pet",
    party1 = "Party 1",
    party2 = "Party 2",
    party3 = "Party 3",
    party4 = "Party 4",
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

-- Names are how one bar refers to another when docking, so two bars
-- called the same thing would make that list a guess. Every name carries
-- the next free number for its kind.
function UnitBars:DefaultName(kind, unit)
    local base
    if IsUnitKind(kind) then
        base = (self.UNITS[unit] or unit) .. " " .. (self.KINDS[kind] or kind)
    else
        base = (self.KINDS[kind] or kind) .. " Bar"
    end

    local taken = {}
    for _, def in ipairs(self:Defs()) do taken[def.name or ""] = true end

    local index = 1
    while taken[base .. " " .. index] do index = index + 1 end
    return base .. " " .. index
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
        -- Four pixels a side go to the outline, the rim and the line
        -- between them, so this is a sixteen pixel fill.
        height     = 24,
        textMode   = "always",
        textFormat = (kind == "xp" or kind == "rep") and "detailed"
            or ((kind == "power" or kind == "cast") and "current" or "namePercent"),
        ticks      = (kind == "xp") and 10 or 0,
        dock       = { host = "float", edge = "BOTTOM" },
        position   = { point = "CENTER", relPoint = "CENTER", x = 0, y = -160 },
    }
    def.name = self:DefaultName(kind, unit)
    defs[#defs + 1] = def
    self:Save()
    self:Build(def)
    return def
end

-- Where deleted bars go. One frame, made when the first bar is deleted.
local retiredParent

local function RetiredParent()
    if not retiredParent then
        retiredParent = CreateFrame("Frame")
        retiredParent:Hide()
    end
    return retiredParent
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

                -- A health or power bar does not decide for itself
                -- whether it is on screen: RegisterUnitWatch does, in
                -- the secure environment, and it goes on showing the
                -- frame whenever the unit exists. Hiding a deleted bar
                -- without cancelling that is why one stayed on screen
                -- with no handle to grab, until a reload.
                if _G.UnregisterUnitWatch then _G.UnregisterUnitWatch(bar.frame) end
                bar.frame:SetAttribute("unit", nil)
                bar.frame:SetScript("OnUpdate", nil)
                bar.frame:Hide()

                -- Secure frames cannot be destroyed, so it is parked out
                -- of the way rather than left loose under UIParent where
                -- something could show it again.
                bar.frame:ClearAllPoints()
                bar.frame:SetParent(RetiredParent())

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
    self:SuppressStock()
end

---------------------------------------------------------------------------
-- Blizzard's own frames
--
-- One rule, stated rather than configured: whatever you have made a bar
-- for, the game's version of it goes away, and whatever you have not is
-- left alone. Make a player health bar and the stock player frame goes;
-- delete it and the frame comes back. Nothing here is a setting, because
-- the answer is always readable from the bars you have.
--
-- Experience and reputation are the awkward pair. Era draws them inside
-- one shared container whose manager decides which it will show, so it
-- is asked about only the one we replaced; older builds give them frames
-- of their own, and both cases are handled rather than guessed at.
---------------------------------------------------------------------------

-- What each bar covers, and the frames that answer to it.
local STOCK_FRAMES = {
    xp         = { "MainMenuExpBar", "ExhaustionTick", "MainMenuBarMaxLevelBar" },
    rep        = { "ReputationWatchBar" },
    player     = { "PlayerFrame" },
    target     = { "TargetFrame" },
    pet        = { "PetFrame" },
    party1     = { "PartyMemberFrame1" },
    party2     = { "PartyMemberFrame2" },
    party3     = { "PartyMemberFrame3" },
    party4     = { "PartyMemberFrame4" },
    playercast = { "CastingBarFrame", "PlayerCastingBarFrame" },
    petcast    = { "PetCastingBarFrame" },
}

local function Covers(def)
    local kind = def.kind
    if kind == "xp" or kind == "rep" then return kind end
    if kind == "cast" then return (def.unit or "player") .. "cast" end
    if kind == "health" or kind == "power" then return def.unit or "player" end
end

local hiddenStock
local stockParents = {}
local hookedManager
local petParent
local suppressing  = {}
local suppressKey

local function HiddenStock()
    if not hiddenStock then
        hiddenStock = CreateFrame("Frame")
        hiddenStock:Hide()
    end
    return hiddenStock
end

function UnitBars:SuppressStock()
    local wanted = {}
    for _, def in ipairs(self:Defs()) do
        local covers = Covers(def)
        if covers then wanted[covers] = true end
    end

    -- Asked on every save, and a save happens every time a bar is
    -- dragged, so nothing is touched unless what we cover has changed.
    local parts = {}
    for covers in pairs(wanted) do parts[#parts + 1] = covers end
    table.sort(parts)
    local key = table.concat(parts, ",")
    if key == suppressKey then return end

    -- Reparenting Blizzard's frames is protected, and so is asking the
    -- container to lay itself out again. The key is left alone so the
    -- next call after combat picks this up.
    if InCombatLockdown() then return end
    for covers in pairs(STOCK_FRAMES) do suppressing[covers] = wanted[covers] end

    -- Whether anything was actually there to act on. Blizzard's bars
    -- may not exist yet the first time this runs, and remembering the
    -- answer before they turn up would mean never looking again.
    local found = false

    local manager, info = _G.StatusTrackingBarManager, _G.StatusTrackingBarInfo
    if manager and manager.CanShowBar and info and info.BarsEnum then
        if hookedManager ~= manager then
            hookedManager = manager
            local original = manager.CanShowBar
            -- Answering for only the bar we have replaced leaves the
            -- other one to lay out in the container as it always did.
            manager.CanShowBar = function(frame, index, ...)
                if suppressing.xp and index == info.BarsEnum.Experience then return false end
                if suppressing.rep and index == info.BarsEnum.Reputation then return false end
                return original(frame, index, ...)
            end
        end
        manager:UpdateBarsShown()
    end

    -- With both of them replaced the container has nothing left to
    -- draw, but the game's own Edit Mode still offers it as "Status Bar
    -- 1" and lays a highlight across the screen for it. Parenting it to
    -- something hidden takes it out of both, and only when we have in
    -- fact replaced both: covering one of the two leaves a container
    -- that still has the other to show.
    if manager then
        found = true
        local gone = suppressing.xp and suppressing.rep
        if gone and not stockParents[manager] then
            stockParents[manager] = manager:GetParent() or UIParent
            manager:SetParent(HiddenStock())
        elseif not gone and stockParents[manager] then
            manager:SetParent(stockParents[manager])
            stockParents[manager] = nil
            -- It was told what to show while it was off screen, so ask
            -- again now that it is back.
            manager:UpdateBarsShown()
        end
    end

    -- Era hangs the pet's frame off the player's, so hiding the player's
    -- would take a pet frame we are not replacing with it. Move it out
    -- to the screen first, and put it back when the player's returns.
    local playerFrame, petFrame = _G.PlayerFrame, _G.PetFrame
    if petFrame and playerFrame and suppressing.player and not suppressing.pet
        and petFrame:GetParent() == playerFrame then
        petParent = playerFrame
        petFrame:SetParent(UIParent)
    elseif petParent and not suppressing.player then
        petFrame:SetParent(petParent)
        petParent = nil
    end

    for covers, names in pairs(STOCK_FRAMES) do
        for _, name in ipairs(names) do
            local frame = _G[name]
            if frame then
                found = true
                if suppressing[covers] and not stockParents[frame] then
                    stockParents[frame] = frame:GetParent() or UIParent
                    frame:SetParent(HiddenStock())
                elseif not suppressing[covers] and stockParents[frame] then
                    frame:SetParent(stockParents[frame])
                    stockParents[frame] = nil
                end
            end
        end
    end

    if found then suppressKey = key end
end

---------------------------------------------------------------------------
-- Reading a unit
---------------------------------------------------------------------------

local function Number(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(math.floor(n))
end

local function HealthColor(unit)
    -- Offline reads as grey whatever else is true of them: a party
    -- member's last known health is not worth colouring as if it were
    -- current.
    if UnitIsConnected and not UnitIsConnected(unit) then return OFFLINE_COLOR end
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
-- Fields in a line of bar text are separated by this, which is what the
-- experience bar has always used.
local SEP = "   •   "

local function Format(mode, current, maximum, name)
    if mode == "name" then return name or "" end
    if maximum <= 0 then return "" end
    local percent = math.floor(current / maximum * 100 + 0.5)
    if mode == "percent" then return percent .. "%" end
    if mode == "current" then return Number(current) end
    if mode == "namePercent" then return string.format("%s  %d%%", name or "", percent) end

    -- "Everything" is the experience bar's line applied to a unit: who
    -- it is, the numbers, and the percent. It used to fall through to
    -- current-over-maximum, so a health bar asked for everything showed
    -- the same "82 / 82" as the setting above it.
    if mode == "detailed" then
        local values = string.format("%s / %s", Number(current), Number(maximum))
        if name and name ~= "" then
            return name .. SEP .. values .. SEP .. percent .. "%"
        end
        return values .. SEP .. percent .. "%"
    end

    return string.format("%s / %s", Number(current), Number(maximum))
end

---------------------------------------------------------------------------
-- Filling a bar in
---------------------------------------------------------------------------

-- A bar for a unit that is not there, while the layout is being
-- arranged: full, grey, and named after the slot it stands for.
local function DrawPlaceholder(bar, fraction)
    bar.frame:SetAlpha(1)
    bar.frame:SetValue(fraction)
    bar.frame:SetOverlay(0)
    bar.frame:SetFillColor(OFFLINE_COLOR)
    bar.frame:SetText(UnitBars.UNITS[bar.def.unit] or bar.def.unit)
end

local function UpdateHealth(bar)
    local unit = bar.def.unit
    if not UnitExists(unit) then
        if previewing then DrawPlaceholder(bar, 1) end
        return
    end
    local maximum = math.max(1, UnitHealthMax(unit) or 1)
    local current = math.max(0, math.min(maximum, UnitHealth(unit) or 0))
    bar.frame:SetValue(current / maximum)
    bar.frame:SetFillColor(HealthColor(unit))

    local name = UnitName(unit) or ""
    if UnitIsConnected and not UnitIsConnected(unit) then
        bar.frame:SetText(name ~= "" and (name .. "  Offline") or "Offline")
    elseif UnitIsGhost(unit) then
        bar.frame:SetText(name ~= "" and (name .. "  Ghost") or "Ghost")
    elseif UnitIsDead(unit) then
        bar.frame:SetText(name ~= "" and (name .. "  Dead") or "Dead")
    else
        bar.frame:SetText(Format(bar.def.textFormat, current, maximum, name))
    end
end

local function UpdatePower(bar)
    local unit = bar.def.unit
    if not UnitExists(unit) then
        if previewing then DrawPlaceholder(bar, 0.6) end
        return
    end
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
    bar.frame:SetText(Format(bar.def.textFormat, current, maximum, UnitName(unit)))
end

local function UpdateXP(bar)
    local maximum = math.max(0, UnitXPMax("player") or 0)
    local current = math.max(0, math.min(maximum, UnitXP("player") or 0))
    local rested = math.max(0, GetXPExhaustion() or 0)
    local level = UnitLevel("player") or 1

    bar.frame:SetValue(maximum > 0 and current / maximum or 0)
    bar.frame:SetOverlay(maximum > 0 and rested / maximum or 0)
    bar.frame:SetFillColor({ 0.57, 0.16, 0.85, 1 })

    -- At the cap an experience bar has nothing left to say, so unless
    -- asked otherwise it gets out of the way. Hiding it through the dock
    -- means anything under it closes the gap, the same as any other bar
    -- that goes away.
    local atMax = (maximum <= 0)
    BazUI.Dock:SetShown(bar.frame, not (atMax and bar.def.hideAtMax ~= false))

    if atMax then
        bar.frame:SetText("Level " .. level .. "  •  Maximum level")
        return
    end

    -- The full line the old XP bar wore, which said everything at once:
    -- where you are, how far through, and the exact fraction. A tenth of
    -- a percent is worth having here because a level is long.
    if (bar.def.textFormat or "detailed") == "detailed" then
        bar.frame:SetText(string.format("Level %d   •   %s / %s XP   •   %.1f%%",
            level, Number(current), Number(maximum), current / maximum * 100))
    else
        bar.frame:SetText(Format(bar.def.textFormat, current, maximum, "Level " .. level))
    end
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
    local into = (value or 0) - (min or 0)
    if (bar.def.textFormat or "detailed") == "detailed" then
        bar.frame:SetText(string.format("%s   •   %s / %s   •   %.1f%%",
            name, Number(into), Number(span), into / span * 100))
    else
        bar.frame:SetText(Format(bar.def.textFormat, into, span, name))
    end
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

-- What to call the cast.
--
-- The second return is the one to show. The first is the spell's name in
-- the client's own tables, and plenty of vanilla spells have no name
-- there: interacting with a quest object casts one of them, and the
-- table's placeholder for an empty name is the literal string "No Text",
-- which is what turned up on the bar while collecting Milly's buckets.
-- Blizzard's own cast bar shows the second return for exactly this
-- reason. If both are useless, say what is happening rather than repeat
-- the client's filler.
local function CastName(display, name, channel)
    for _, candidate in ipairs({ display, name }) do
        if candidate and candidate ~= "" and candidate ~= "No Text" then
            return candidate
        end
    end
    return channel and "Channelling" or "Casting"
end

function UnitBars:SyncCast(bar)
    if bar.def.kind ~= "cast" then return end
    local unit, frame = bar.def.unit, bar.frame

    local name, display, _, startMS, endMS = UnitCastingInfo(unit)
    local channel = false
    if not name then
        name, display, _, startMS, endMS = UnitChannelInfo(unit)
        channel = name ~= nil
    end

    if name and startMS and endMS then
        frame:SetAlpha(1)
        frame:SetFillColor(channel and CHANNEL_COLOR or CAST_COLOR)
        frame._cast = { name = CastName(display, name, channel),
            startMS = startMS, endMS = endMS, channel = channel }
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
        height   = def.height or 24,
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

    -- Bars made before names were numbered can collide, and a docking
    -- list with two identical entries is a coin toss. Repair on load.
    local seen = {}
    for _, def in ipairs(self:Defs()) do
        if not def.name or seen[def.name] then
            def.name = self:DefaultName(def.kind, def.unit)
        end
        seen[def.name] = true
    end
    self:Save()

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
        math.max(14, math.min(48, def.height or 24)))
    frame:SetTextMode(def.textMode or "always")
    frame:SetTicks(def.ticks or 0)

    -- Full width is one bar to a line; half or its own width lets two
    -- sit side by side, which is how a health bar on the left and a
    -- power bar on the right end up on the same action bar.
    local dock  = def.dock or { host = "float" }
    local takes = def.takes or "full"
    BazUI.Dock:AttachTo(frame, dock.host, {
        edge    = dock.edge or "BOTTOM",
        mode    = (takes == "full") and "stretch" or "align",
        align   = def.align or "LEFT",
        share   = (takes == "half") and 2 or nil,
        order   = def.id,
        gap     = def.gap,
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
-- The handle, the snapping and the landing line all live in
-- Core/DockMover.lua, because a row of auras wants exactly the same
-- behaviour and should not have a second copy of it. What stays here is
-- the part only a bar can answer: what a drop means for its definition.
---------------------------------------------------------------------------

-- Says what the snap test can see, for when it insists nothing is near.
function UnitBars:DescribeSnap()
    BazUI.Dock:DescribeSnap(function(text) addon:Print(text) end)
end

-- Where a bar ended up: docked to whatever it was dropped against, or
-- floating at the position it was let go.
function UnitBars:Dropped(bar, snap, x, y)
    if snap then
        bar.def.dock = { host = snap.host, edge = snap.edge }
    elseif x then
        bar.def.dock = { host = "float", edge = bar.def.dock and bar.def.dock.edge or "BOTTOM" }
        bar.def.position = { point = "CENTER", relPoint = "BOTTOMLEFT", x = x, y = y }
    end
    self:Save()
    self:Apply(bar)
end

function UnitBars:RefreshMover(bar)
    if bar and bar.mover then bar.mover:Refresh() end
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
    detailed        = "Everything",
    ["current/max"] = "Current / Max",
    current         = "Current",
    percent         = "Percent",
    name            = "Name",
    namePercent     = "Name and percent",
}
local EDGES = { BOTTOM = "Below", TOP = "Above" }

-- How much of its host a docked bar takes, and where it sits across it.
local TAKES = {
    full = "The whole width",
    half = "Half the width",
    own  = "Its own width",
}
local ALIGNS = { LEFT = "Left", CENTER = "Centre", RIGHT = "Right" }

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

    local widgets = {
        { type = "dropdown", section = "Docking", label = "Dock to",
          options = dockOptions,
          get = function() return (def.dock and def.dock.host) or "float" end,
          set = function(value)
              def.dock = { host = value, edge = (def.dock and def.dock.edge) or "BOTTOM" }
              Refresh()
              -- Floating and docked do not offer the same choices.
              UnitBars:RefreshEditSettings()
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
          min = 14, max = 48, step = 1,
          get = function() return def.height or 24 end,
          set = function(value) def.height = value Refresh() end },

        { type = "dropdown", section = "Text", label = "Show text",
          options = ValuesArray(TEXT_MODES),
          get = function() return def.textMode or "always" end,
          set = function(value) def.textMode = value Refresh() end },

        { type = "slider", section = "Text", label = "Tenth marks",
          min = 0, max = 20, step = 1,
          get = function() return def.ticks or 0 end,
          set = function(value) def.ticks = value Refresh() end },

        { type = "nudge", section = "Position" },
    }

    -- Appended rather than written inline with a condition: a nil in the
    -- middle of a table constructor ends the list for everything after
    -- it, which would have quietly cost every other bar its nudge.
    if def.dock and def.dock.host and def.dock.host ~= "float" then
        table.insert(widgets, 3, {
            type = "slider", section = "Docking", label = "Gap",
            min = 0, max = 24, step = 1,
            get = function() return def.gap or 2 end,
            set = function(value) def.gap = value Refresh() end,
        })
        table.insert(widgets, 3, {
            type = "dropdown", section = "Docking", label = "Aligned",
            options = ValuesArray(ALIGNS),
            get = function() return def.align or "LEFT" end,
            set = function(value) def.align = value Refresh() end,
        })
        table.insert(widgets, 3, {
            type = "dropdown", section = "Docking", label = "Takes",
            options = ValuesArray(TAKES),
            get = function() return def.takes or "full" end,
            set = function(value)
                def.takes = value
                Refresh()
                -- Full width has no alignment to speak of.
                UnitBars:RefreshEditSettings()
            end,
        })
    end

    -- A cast bar's text is the spell and the countdown, written as the
    -- cast runs, so it never reads a format and is not offered one.
    if def.kind ~= "cast" then
        -- Where it reads, under "Show text", rather than wherever an
        -- append happens to land.
        local at = #widgets
        for index, widget in ipairs(widgets) do
            if widget.label == "Tenth marks" then at = index break end
        end
        table.insert(widgets, at, {
            type = "dropdown", section = "Text", label = "Text says",
            options = ValuesArray(TEXT_FORMATS),
            get = function() return def.textFormat or "namePercent" end,
            set = function(value) def.textFormat = value Refresh() end,
        })
    end

    if def.kind == "xp" then
        table.insert(widgets, #widgets, {
            type = "checkbox", section = "Visibility",
            label = "Hide at maximum level",
            get = function() return def.hideAtMax ~= false end,
            set = function(value)
                def.hideAtMax = value
                Refresh()
                UnitBars:Update(bar)
            end,
        })
    end

    return widgets
end


-- What the panel can do to this bar, rather than change about it. Edit
-- Mode renders these as their own Actions section, which is where an
-- action bar keeps its delete, so the two read alike.
function UnitBars:EditActions(bar)
    local def = bar.def
    return {
        {
            label = "Duplicate",
            onClick = function()
                if InCombatLockdown() then
                    addon:Print("Create bars after combat ends.")
                    return
                end
                local copy = UnitBars:Add(def.kind, def.unit)
                if not copy then return end
                -- Everything except what makes it a different bar: its
                -- own id and name, and where it sits. Listing the fields
                -- to copy meant a new one was always a field behind.
                for key, value in pairs(def) do
                    if key ~= "id" and key ~= "name"
                        and key ~= "dock" and key ~= "position" then
                        copy[key] = value
                    end
                end
                UnitBars:Save()
                local made = UnitBars.bars[copy.id]
                if made then UnitBars:Apply(made) end
                addon:Print("Duplicated " .. (def.name or "bar"))
            end,
        },
        {
            label = "|cffff4444Delete This Bar|r",
            onClick = function()
                if not BazUI.Confirm then return end
                BazUI:Confirm({
                    title       = "Delete bar?",
                    body        = ("Delete %s? Anything docked to it goes back to floating. Can't be undone."):format(def.name or "this bar"),
                    acceptLabel = "Delete",
                    acceptStyle = "destructive",
                    onAccept    = function()
                        BazUI:DeselectEditFrame(bar.mover)
                        UnitBars:Remove(def.id)
                    end,
                })
            end,
        },
    }
end

function UnitBars:CreateMover(bar)
    if bar.mover then return bar.mover end
    local def = bar.def

    bar.mover = BazUI.Dock:CreateMover(bar.frame, {
        name      = "BazUIStatusBarMover" .. def.id,
        label     = def.name or ("Bar " .. def.id),
        addonName = "UnitFrames",
        settings  = function() return UnitBars:EditSettings(bar) end,
        actions   = function() return UnitBars:EditActions(bar) end,
        onDrop    = function(snap, x, y) UnitBars:Dropped(bar, snap, x, y) end,
    })
    return bar.mover
end

function UnitBars:ShowMover(bar)
    if bar and bar.mover then bar.mover:ShowForEdit() end
end

-- Party bars are hidden when nobody is in those slots, and a hidden
-- bar cannot be docked to: the snap test will not offer something it
-- cannot see, and nor should it. Arranging a party layout while solo was
-- therefore impossible, which is when most people would do it.
--
-- While Edit Mode is open, a bar whose unit is absent is shown with a
-- placeholder instead. Whether a health or power bar is on screen
-- belongs to RegisterUnitWatch, so the watch is handed back and forth
-- rather than fought with; both calls are out-of-combat only, which Edit
-- Mode already is.
-- Asked for by hand, as opposed to asked for by Edit Mode being open.
-- Kept apart so closing Edit Mode does not cancel a preview somebody
-- turned on deliberately.
local previewWanted = false

function UnitBars:SetPreviewWanted(on)
    previewWanted = on and true or false
    self:RefreshPreview()
end

function UnitBars:IsPreviewing()
    return previewing
end

function UnitBars:PreviewWanted()
    return previewWanted
end

-- What the preview should be right now: either somebody asked for it, or
-- Edit Mode is open and arranging is the point.
function UnitBars:RefreshPreview()
    self:SetPreview(previewWanted or BazUI:IsEditMode())
end

function UnitBars:SetPreview(on)
    if InCombatLockdown() then return end
    previewing = on and true or false

    for _, bar in pairs(self.bars) do
        local def = bar.def
        local secure = (def.kind == "health" or def.kind == "power")
        if secure and not UnitExists(def.unit) then
            if previewing then
                if _G.UnregisterUnitWatch then _G.UnregisterUnitWatch(bar.frame) end
                BazUI.Dock:SetShown(bar.frame, true)
            else
                BazUI.Dock:SetShown(bar.frame, false)
                if _G.RegisterUnitWatch then _G.RegisterUnitWatch(bar.frame) end
            end
            self:Update(bar)

        -- A cast bar is invisible between casts, which is the same
        -- problem: nothing can be docked to it and it cannot be judged
        -- against what is around it. One that is actually casting is
        -- left alone.
        elseif def.kind == "cast" and not bar.frame._cast then
            BazUI.Dock:SetShown(bar.frame, previewing)
            if previewing then
                bar.frame:SetAlpha(1)
                bar.frame:SetValue(0.55)
                bar.frame:SetFillColor(CAST_COLOR)
                bar.frame:SetText("Casting  1.4")
            end
        end
    end
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
            -- Resting changes the rested overlay without any experience
            -- being gained, and a capped or disabled bar has to notice
            -- that it is now one.
            "PLAYER_UPDATE_RESTING", "UNIT_LEVEL",
            "ENABLE_XP_GAIN", "DISABLE_XP_GAIN",
            -- Who is in the group is not a unit event: party2 becoming
            -- somebody else fires nothing about party2.
            "GROUP_ROSTER_UPDATE",
        }) do
            pcall(watchers._player.RegisterEvent, watchers._player, event)
        end
        watchers._player:SetScript("OnEvent", function()
            UnitBars:UpdateAll()
            UnitBars:SuppressStock()
        end)
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
local UNIT_ORDER = {
    "player", "target", "pet",
    "party1", "party2", "party3", "party4",
}

-- The four party slots, as the group fills them. A bar for one of these
-- shows itself when that slot is occupied and hides when it is not, and
-- the game does the showing: RegisterUnitWatch is already how every
-- health and power bar decides, so a party bar needs nothing extra to
-- appear when somebody joins mid-fight.
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }

-- Health and power for each of the four slots, power docked under
-- health and each pair under the last, in a column. Made in one go
-- because the shape is the same every time and nobody wants to place
-- eight bars to find out whether they like it.
function UnitBars:AddPartySet()
    if InCombatLockdown() then return nil end

    local previous, made = nil, 0
    for index, unit in ipairs(PARTY_UNITS) do
        local health = self:Add("health", unit)
        if health then
            made = made + 1
            health.width = 180
            if previous then
                -- Under the pair above, so the column stays a column
                -- however it is moved afterwards.
                health.dock = { host = self:HostID(previous.id), edge = "BOTTOM" }
                health.gap = 8
            else
                health.position = { point = "LEFT", relPoint = "LEFT", x = 20, y = 120 }
            end

            local power = self:Add("power", unit)
            if power then
                made = made + 1
                power.width = 180
                power.height = 16
                power.dock = { host = self:HostID(health.id), edge = "BOTTOM" }
                power.gap = 1
                previous = power
            else
                previous = health
            end
        end
        if index == #PARTY_UNITS then break end
    end

    self:Save()
    self:ApplyAll()
    return made
end

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
        items[#items + 1] = {
            label = "Party frames (all four)",
            onClick = function()
                local made = UnitBars:AddPartySet()
                if made then
                    addon:Print(("Created %d party bars"):format(made))
                end
            end,
        }
        return items
    end)
end
