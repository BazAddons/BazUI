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
local Theme = BazUI.Skin.Theme

local UnitBars = {}
addon.UnitBars = UnitBars

UnitBars.bars = {}          -- [id] = { def, frame, mover }

-- Edit Mode shows bars for units that are not there, so a layout can
-- be arranged while solo. See SetPreview.
local previewing = false

-- Offline is here because a placeholder bar wears it before there is a
-- unit to ask about. The rest of the unit colours live in Core/Units.lua.
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
    partypet1 = "Party 1's Pet",
    partypet2 = "Party 2's Pet",
    partypet3 = "Party 3's Pet",
    partypet4 = "Party 4's Pet",
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
    -- A bar made while absent units are being previewed joins the
    -- preview now rather than at the next time something turns it on.
    -- Made in Edit Mode for a unit who is not there, it would otherwise
    -- be invisible with only a handle to show for it.
    self:RefreshPreview()
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

-- One bar of a stack being copied. The unit is swapped if it has one
-- and a new one was asked for; everything else about it comes across
-- except what makes it a different bar.
function UnitBars:CopyBar(def, unit, hostId, edge, drop)
    if InCombatLockdown() then return nil end

    local wanted = (unit and IsUnitKind(def.kind)) and unit or def.unit
    local copy = self:Add(def.kind, wanted)
    if not copy then return nil end

    for key, value in pairs(def) do
        if key ~= "id" and key ~= "name" and key ~= "unit"
            and key ~= "dock" and key ~= "position" then
            copy[key] = value
        end
    end
    copy.name = self:DefaultName(copy.kind, copy.unit)

    if hostId then
        copy.dock = { host = hostId, edge = edge or "BOTTOM" }
    else
        -- The root of the copy floats a little below the original,
        -- rather than exactly on top of it where it would look like
        -- nothing had happened.
        copy.dock = { host = "float", edge = (def.dock and def.dock.edge) or "BOTTOM" }
        local pos = def.position or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
        copy.position = {
            point = pos.point, relPoint = pos.relPoint,
            x = pos.x or 0, y = (pos.y or 0) - (drop or 80),
        }
    end

    self:Save()
    local bar = self.bars[copy.id]
    if bar then self:Apply(bar) end
    return self:HostID(copy.id), bar and bar.frame
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
                BazUI.Dock:UnregisterCopier(bar.frame)

                -- A health or power bar does not decide for itself
                -- whether it is on screen: RegisterUnitWatch does, in
                -- the secure environment, and it goes on showing the
                -- frame whenever the unit exists. Hiding a deleted bar
                -- without canceling that is why one stayed on screen
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
end

---------------------------------------------------------------------------
-- Blizzard's own frames
--
-- One switch per frame, and nothing here reads the bars you have made.
--
-- It used to work the other way: whatever you had made a bar for, the
-- game's version of it went away. That sounds tidy and is not. A frame
-- disappears and nothing on screen says why; a frame you wanted to keep
-- cannot be kept; and a bar for one party member hid that member's frame
-- and left the other three sitting there, which is how this came up.
-- Something that changes what is on the player's screen should be a
-- thing the player can point at.
--
-- The frames a new profile's starter bars replace are hidden to begin
-- with, so a fresh install does not show two of everything. Everything
-- else starts as the game left it.
--
-- They are parked under a hidden parent rather than hidden, because the
-- game shows several of them again whenever the group changes and a
-- child of a hidden frame does not draw whatever it believes about
-- itself. Experience and reputation are not here: the game keeps both in
-- the furniture around its action bar, which the Bars module owns.
---------------------------------------------------------------------------

UnitBars.STOCK = {
    {
        key     = "hidePlayerFrame",
        label   = "Player frame",
        desc    = "The game's own portrait frame for you.",
        default = true,
        frames  = { "PlayerFrame" },
    },
    {
        key     = "hideTargetFrame",
        label   = "Target frame",
        desc    = "The game's own portrait frame for your target.",
        default = true,
        frames  = { "TargetFrame" },
    },
    {
        key     = "hidePlayerCastBar",
        label   = "Casting bar",
        desc    = "The game's own casting bar, under the middle of the screen.",
        default = true,
        -- Four names for one bar. PlayerCastingBarFrame is the managed
        -- one at the bottom, Overlay is the copy that appears over the
        -- player frame, Gamepad is its own frame again, and
        -- CastingBarFrame is what older builds called it. A name that
        -- does not exist costs nothing.
        frames  = { "PlayerCastingBarFrame", "OverlayPlayerCastingBarFrame",
                    "GamepadPlayerCastingBarFrame", "CastingBarFrame" },
    },
    {
        key    = "hidePartyFrames",
        label  = "Party frames",
        desc   = "The portrait frames down the left in a group. Make party bars first, or a group will have nothing showing it at all.",
        -- The container, because on this client there is nothing else to
        -- take hold of: the member frames come out of a pool on
        -- PartyFrame and are given parent keys rather than names, so the
        -- PartyMemberFrame1..4 globals every older build had are not
        -- there to be hidden. They are listed anyway for the builds that
        -- do have them, where a name that does not exist costs nothing.
        frames = { "PartyFrame",
                   "PartyMemberFrame1", "PartyMemberFrame2",
                   "PartyMemberFrame3", "PartyMemberFrame4" },
    },
    {
        key    = "hidePetCastBar",
        label  = "Pet casting bar",
        desc   = "The casting bar for your pet.",
        frames = { "PetCastingBarFrame" },
    },
    {
        key    = "hideRaidManager",
        label  = "Raid manager tab",
        desc   = "The tab at the left edge of the screen that slides out with the target markers, group filters and ready check on it. The game shows it whenever you are in a group.",
        frames = { "CompactRaidFrameManager" },
    },

    -- Pet frames are deliberately absent. Era hangs each one off the
    -- frame of whoever owns it, so hiding the player's or a party
    -- member's takes their pet's with it, and touching a pet frame
    -- ourselves is worse than useless: the game's Edit Mode refreshes
    -- the player's pet frame as it opens, and a frame an addon has
    -- reparented is tainted, so that refresh gets blocked and blamed on
    -- us. Not touching them is both simpler and correct.
}

-- Saved as a real true or false once the player has touched it, so the
-- default only answers for a switch nobody has thrown. Checked against
-- nil rather than leaned on: `saved or default` would turn every
-- deliberate false back on.
function UnitBars:StockHidden(entry)
    local saved = addon:GetSetting(entry.key)
    if saved == nil then return entry.default and true or false end
    return saved and true or false
end

-- The game's own frames, by name. See Core/Compat.lua: a renamed frame
-- here means a switch that quietly stops working.
for _, entry in ipairs(UnitBars.STOCK) do
    for _, frameName in ipairs(entry.frames) do
        BazUI:RegisterDependency({
            module = "Unit Frames",
            label  = frameName,
            why    = "Hidden by the " .. entry.label .. " switch.",
            check  = function() return BazUI.Has.Frame(frameName) end,
        })
    end
end

BazUI:RegisterDependency({
    module = "Unit Frames",
    label  = "SECURE_ACTIONS.togglemenu",
    why    = "The right-click menu on a bar picks itself; without it we fall back to our own guess.",
    check  = function() return BazUI.Has.Member(_G.SECURE_ACTIONS, "togglemenu") end,
})

-- Which of the game's frames are meant to be down, held here rather than
-- on their frames. They used to be reparented to a hidden carrier, with
-- the old parent written onto the frame - both of them writes to things
-- we do not own. PlayerFrame, TargetFrame, PlayerCastingBarFrame and
-- PartyFrame are all Edit Mode systems on this client, and Edit Mode
-- walks them on the way in; anything of ours left on them taints that
-- walk. BazUI.SuppressFrame hides them through their own OnShow instead,
-- and calls Hide as Blizzard rather than as us.
local stockHidden = setmetatable({}, { __mode = "k" })
local suppressKey

function UnitBars:SuppressStock()
    -- Asked on every save, and a save happens every time a bar is
    -- dragged, so nothing is touched unless an answer has changed.
    local parts = {}
    for _, entry in ipairs(self.STOCK) do
        parts[#parts + 1] = self:StockHidden(entry) and "1" or "0"
    end
    local key = table.concat(parts)
    if key == suppressKey then return end

    -- Reparenting Blizzard's frames is protected. The key is left alone
    -- so the next call after combat picks this up.
    if InCombatLockdown() then return end

    -- Whether anything was actually there to act on. Blizzard's frames
    -- may not exist yet the first time this runs, and remembering the
    -- answer before they turn up would mean never looking again.
    local found = false

    for _, entry in ipairs(self.STOCK) do
        local hide = self:StockHidden(entry)
        for _, name in ipairs(entry.frames) do
            local frame = _G[name]
            if frame then
                found = true
                stockHidden[frame] = hide or nil
                BazUI.SuppressFrame(frame, function()
                    return stockHidden[frame] and true or false
                end)
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

-- Offline and dead read as gray whatever else is true of them: a party
-- member's last known health is not worth colouring as if it were
-- current. The rule lives in Core/Units.lua so the name plates paint the
-- same unit the same way.
local function HealthColor(unit)
    return BazUI.UnitColor(unit, { classColor = addon:GetSetting("classColor") })
end

-- Read the same careful way as the health colour. UnitPowerType is not
-- documented as secret-returning, but a restricted unit hands back values
-- of every sort, and a colour built from one paints the bar black. The
-- parts are added to zero inside the read so a secret raises here rather
-- than arriving at the texture.
local function PowerColor(unit)
    return BazUI.Secret.Read(function()
        local powerType, token = UnitPowerType(unit)
        local c = PowerBarColor and (PowerBarColor[token] or PowerBarColor[powerType])
        if not c then return nil end
        return { c.r + 0, c.g + 0, c.b + 0, 1 }
    end, nil) or { 0.1, 0.3, 1, 1 }
end

-- What a bar says about itself. A health bar has more to say than an
-- experience bar, so the wording is the bar's own setting.
-- Fields in a line of bar text are separated by this, which is what the
-- experience bar has always used.
local SEP = "   •   "

-- What a bar says right now. A bar can carry two wordings - one for while
-- you are looking at it and one for the rest of the time - so which
-- applies is a question about the mouse rather than about the bar. No
-- second wording set, and there is nothing to choose between.
local function TextFormat(bar)
    local def = bar.def
    if bar.frame._hovered then
        local hovered = def.hoverFormat
        if hovered and hovered ~= "same" then return hovered end
    end
    return def.textFormat
end

-- Whether this bar says something different under the mouse, which is
-- what decides whether hovering it is worth a redraw - and, on a bar that
-- is not already a button, whether it is worth taking the mouse for at
-- all. A bar told never to show text has nothing to change into.
local function HasHoverFormat(def)
    if (def.textMode or "always") == "never" then return false end
    return def.hoverFormat ~= nil and def.hoverFormat ~= "same"
        and def.hoverFormat ~= def.textFormat
end

-- The wordings that carry the unit's level themselves. A name handed to
-- one of these stays a name: the level arrives separately rather than
-- being folded into it.
local LEVEL_WORDINGS = { level = true, nameLevel = true }

local function Format(mode, current, maximum, name, level)
    if mode == "name" then return name or "" end

    -- Before the health check, because a level is a fact about the unit
    -- rather than about its health, and is worth saying on a bar whose
    -- numbers have not arrived yet.
    if mode == "level" then return level or "" end
    if mode == "nameLevel" then
        if not (level and level ~= "") then return name or "" end
        if not (name and name ~= "") then return level end
        return name .. "  " .. level
    end

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

---------------------------------------------------------------------------
-- A bar for a unit that is not there
--
-- Shown while a layout is being arranged, so a party can be laid out
-- without a party. It used to be a grey bar at full, which answered none
-- of the questions you have while arranging: whether a name of real
-- length fits, what four class colours look like stacked, whether a
-- half-empty bar still reads at the height you chose.
--
-- So it stands in for a plausible group instead. Each slot keeps the same
-- made-up member every time, because a preview that reshuffles while you
-- drag is a preview you cannot compare against itself.
--
-- The name stays the slot's own - "Party 1" rather than an invented
-- person - so you can always tell which bar you have hold of.
---------------------------------------------------------------------------

local PREVIEW_MEMBERS = {
    party1    = { health = 0.86, power = 0.62, class = "WARRIOR", level = 60 },
    party2    = { health = 0.41, power = 0.88, class = "PRIEST",  level = 59 },
    party3    = { health = 1.00, power = 0.35, class = "MAGE",    level = 60 },
    party4    = { health = 0.68, power = 0.50, class = "ROGUE",   level = 58 },
    partypet1 = { health = 0.93, power = 0.70, class = "HUNTER",  level = 60 },
    partypet2 = { health = 0.55, power = 0.45, class = "WARLOCK", level = 59 },
    partypet3 = { health = 0.77, power = 0.80, class = "HUNTER",  level = 60 },
    partypet4 = { health = 0.34, power = 0.25, class = "WARLOCK", level = 58 },
    target    = { health = 0.62, power = 0.40, class = "DRUID",   level = 61 },
    pet       = { health = 0.90, power = 0.75, class = "HUNTER",  level = 60 },
    player    = { health = 0.74, power = 0.55, class = "PALADIN", level = 60 },
}

local PREVIEW_FALLBACK = { health = 0.72, power = 0.55, class = "WARRIOR", level = 60 }

-- Mana, as the one every class has some of.
local PREVIEW_POWER_COLOR = { 0.10, 0.30, 1.00, 1 }

local function DrawPlaceholder(bar, kind)
    local def = bar.def
    local member = PREVIEW_MEMBERS[def.unit] or PREVIEW_FALLBACK
    local label = UnitBars.UNITS[def.unit] or def.unit

    -- Nothing that made it fade still applies: there is no unit to be
    -- out of range of, and no resource to be missing.
    bar._noPower, bar._outOfRange = false, false
    bar.frame:SetAlpha(1)
    bar.frame:SetOverlay(0)

    local isPower = (kind == "power")
    local fraction = isPower and member.power or member.health

    local color
    if isPower then
        color = PREVIEW_POWER_COLOR
    elseif addon:GetSetting("classColor") then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class]
        color = c and { c.r, c.g, c.b, 1 } or BazUI.UNIT_COLORS.alive
    else
        color = BazUI.UNIT_COLORS.alive
    end

    bar.frame:SetValue(fraction)
    bar.frame:SetFillColor(color)

    -- Through the same wording the bar will really use, so the line you
    -- are judging is the line you are going to get. A round thousand of
    -- whatever it is, so the numbers read like numbers.
    local maximum = isPower and 2000 or 4000
    local current = math.floor(maximum * fraction + 0.5)
    bar.frame:SetText(Format(TextFormat(bar), current, maximum, label,
        tostring(member.level)))
end

-- Who the bar is looking at, and what rank it is. The level rides in
-- the name rather than in Format, so every wording that shows a name
-- gets it and the ones that are deliberately just a number stay just a
-- number.
-- The name, with whatever the settings ask to be said about the unit's
-- rank in front of and behind it. The icon leads because it is a mark
-- rather than a word - you look past it to read the name, the way you
-- look past a quest icon.
-- The unit's level, written the way the rest of the addon writes it: with
-- the rank on the end of it when that is switched on.
local function LevelText(unit)
    return BazUI.UnitLevelText(unit, {
        level = true,
        rank  = addon:GetSetting("rankWord") == true,
    })
end

-- The unit's name, plus whatever the level and rank settings want added
-- to it.
--
-- A wording that asks for the level itself gets a bare name, and the
-- level handed over separately - otherwise "Name and level" with the
-- level setting on would say it twice.
local function LabelFor(unit, wording)
    local name = UnitName(unit) or ""
    if LEVEL_WORDINGS[wording] then return name end

    local rank = addon:GetSetting("rankWord") == true
    local level = addon:GetSetting("showLevel") == true
    if not (rank or level) then return name end

    local extra = BazUI.UnitLevelText(unit, { level = level, rank = rank })
    if not extra then return name end
    return name ~= "" and (name .. "  " .. extra) or extra
end

-- The mark in front of the name, sized to the bar rather than to the
-- writing on it - the text stops growing at twelve pixels and a tall bar
-- has room for more than that. Never taller than the fill, and never
-- smaller than the text, which is as small as it is worth drawing.
local function ApplyRankIcon(bar, unit)
    if bar.def.kind ~= "health" then return end

    local path = (addon:GetSetting("rankIcon") ~= false)
        and unit and UnitExists(unit)
        and BazUI.UnitRankIcon(unit) or nil
    if not path then
        bar.frame:SetLeadIcon(nil)
        return
    end

    local _, fill = bar.frame:GetFillSize()
    local scale = tonumber(BazUI.Skin.RANK_ICON_SCALE) or 0.85
    local size = math.floor(math.max(bar.frame:TextSize(), fill * scale) + 0.5)
    bar.frame:SetLeadIcon(path, math.min(size, math.max(1, fill)))
end

-- The glow is the same fact as the word, drawn instead of written. Only
-- health bars wear it: a unit's rank on both its bars is the same thing
-- said twice, and twice as bright.
local function ApplyRankGlow(bar, unit)
    if bar.def.kind ~= "health" then return end
    local wanted = (addon:GetSetting("rankGlow") ~= false)
        and unit and UnitExists(unit)
        and BazUI.UnitRankColor(unit) or nil
    Theme.SetGlow(bar.frame, wanted)
end

---------------------------------------------------------------------------
-- Numbers we may not be allowed to read
--
-- Forever made unit health and power *secret*: an addon may hold one and
-- hand it to a widget, but may not compare it, divide it, or build a
-- string from it. Doing any of those raises rather than returning a
-- wrong answer, so the two helpers below ask by trying.
--
-- Trying, rather than testing what the client is: which values are
-- secret is the client's decision and can differ per power type and per
-- unit, so a rule written here would be a guess that goes stale. A pcall
-- is the honest question.
---------------------------------------------------------------------------

-- Greater than nought, as far as we can tell. A bar whose maximum we
-- cannot measure is better assumed to have some than faded away.
local function PositiveOrUnknown(value)
    return BazUI.Secret.Read(function() return (value or 0) > 0 end, true)
end

-- The wording the user picked, or the plain pair if building it needs
-- arithmetic we are not allowed to do. The font string may format a
-- secret even though we may not.
local function SetBarText(bar, wording, current, maximum, name, level)
    local ok, text = pcall(Format, wording, current, maximum, name, level)
    if ok then
        bar.frame:SetText(text)
        return
    end
    if name and name ~= "" then
        bar.frame:SetFormattedText(name:gsub("%%", "%%%%") .. "  %d / %d",
            current, maximum)
    else
        bar.frame:SetFormattedText("%d / %d", current, maximum)
    end
end

local function UpdateHealth(bar)
    local unit = bar.def.unit
    ApplyRankGlow(bar, unit)
    ApplyRankIcon(bar, unit)
    if not UnitExists(unit) then
        if previewing then DrawPlaceholder(bar, "health") end
        return
    end
    -- Straight through, unclamped and undivided. The bar hands both to
    -- the widget, which is allowed to see what this code is not.
    local maximum = UnitHealthMax(unit)
    local current = UnitHealth(unit)
    bar.frame:SetValue(current, maximum)
    bar.frame:SetFillColor(HealthColor(unit))

    local wording = TextFormat(bar)
    local name = LabelFor(unit, wording)
    if UnitIsConnected and not UnitIsConnected(unit) then
        bar.frame:SetText(name ~= "" and (name .. "  Offline") or "Offline")
    elseif UnitIsGhost(unit) then
        bar.frame:SetText(name ~= "" and (name .. "  Ghost") or "Ghost")
    elseif UnitIsDead(unit) then
        bar.frame:SetText(name ~= "" and (name .. "  Dead") or "Dead")
    else
        SetBarText(bar, wording, current, maximum, name, LevelText(unit))
    end
end

-- How solid a bar should be. A power bar for something with no power
-- at all disappears rather than sitting at nought, and a unit out of
-- range fades. Both are alpha, which is not protected, so this is one of
-- the few things that can still change mid-fight.
local function RefreshAlpha(bar)
    if bar._noPower then
        bar.frame:SetAlpha(0)
    elseif bar._outOfRange then
        bar.frame:SetAlpha(addon:GetSetting("rangeAlpha") or 0.45)
    else
        bar.frame:SetAlpha(1)
    end
end

local function UpdatePower(bar)
    local unit = bar.def.unit
    if not UnitExists(unit) then
        -- Forget that the last unit had no power. A fade left over from
        -- a critter or a totem otherwise survives into the next target,
        -- and the bar sits invisible until something happens to update
        -- it again: health appears at once, power turns up late.
        bar._noPower = false
        if previewing then DrawPlaceholder(bar, "power") end
        return
    end
    local powerType = UnitPowerType(unit)
    local maximum = UnitPowerMax(unit, powerType)

    -- A unit with no power keeps its slot and fades. Hiding would be a
    -- protected call; alpha is not, so this still works mid-fight.
    local hasPower = PositiveOrUnknown(maximum)
    bar._noPower = not hasPower
    RefreshAlpha(bar)
    if not hasPower then
        bar.frame:SetText("")
        return
    end

    local current = UnitPower(unit, powerType)
    bar.frame:SetValue(current, maximum)
    bar.frame:SetFillColor(PowerColor(unit))
    -- A bare name, not the health bar's label: the level and rank
    -- settings put their answer on the health bar, and the same unit
    -- saying it again underneath would only be saying it twice. A power
    -- bar asked outright for the level still gets it.
    local wording = TextFormat(bar)
    SetBarText(bar, wording, current, maximum, UnitName(unit), LevelText(unit))
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
    local wording = TextFormat(bar)
    if (wording or "detailed") == "detailed" then
        bar.frame:SetText(string.format("Level %d   •   %s / %s XP   •   %.1f%%",
            level, Number(current), Number(maximum), current / maximum * 100))
    else
        bar.frame:SetText(Format(wording, current, maximum, "Level " .. level))
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
    local wording = TextFormat(bar)
    if (wording or "detailed") == "detailed" then
        bar.frame:SetText(string.format("%s   •   %s / %s   •   %.1f%%",
            name, Number(into), Number(span), into / span * 100))
    else
        bar.frame:SetText(Format(wording, into, span, name))
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
-- The second return is the one to show, and Blizzard's own cast bar
-- shows it too: it carries the spell's subtext, which in this era is the
-- rank, so a bar reads "Frostbolt - Rank 3".
--
-- A spell with no subtext gets the client's placeholder for one instead
-- of nothing, and it is joined on just the same. That is why gathering
-- wood put "Opening - No Text" on the bar: interacting with a quest
-- object casts a spell with no rank, so the placeholder is all the
-- subtext there is. Cutting it off leaves "Opening", which is what the
-- player is doing.
--
-- The placeholder is spell data rather than one of the client's
-- localizable strings, so there is nothing to compare it against but
-- itself; a client in another language will say something else here and
-- fall through to the plain name, which is the same answer by a longer
-- road.
local NO_SUBTEXT = "No Text"

local function Readable(candidate)
    if type(candidate) ~= "string" then return nil end
    candidate = candidate:gsub("%s*%-%s*" .. NO_SUBTEXT .. "$", "")
    if candidate == "" or candidate == NO_SUBTEXT then return nil end
    return candidate
end

local function CastName(display, name, channel)
    return Readable(display) or Readable(name)
        or (channel and "Channeling" or "Casting")
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

    -- UnitCastingInfo is SecretWhenUnitSpellCastRestricted: for some units
    -- these come back as values we are not allowed to read, and even the
    -- truth test above would raise. A cast bar needs to work out how far
    -- through the cast is, which secret values cannot be, so a cast we are
    -- not allowed to know about counts as no cast and the bar stays down.
    local castable = BazUI.Secret.Read(function()
        return (name and startMS and endMS) and true or false
    end, false)

    if castable then
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

---------------------------------------------------------------------------
-- The right-click menu
--
-- The game keeps a menu per kind of unit and they are not interchangeable.
-- TARGET is the one for something you have targeted and know nothing else
-- about - a raid icon, set focus, add friend - while PLAYER is the one
-- with invite, whisper, inspect, trade, follow and duel on it, and PARTY
-- adds promote, uninvite and the rest. Right-clicking a player used to
-- offer no way to invite them because every unit that was not you got
-- TARGET.
--
-- Choosing between them is not our job: SECURE_ACTIONS.togglemenu does
-- it, it is the same code the game's own frames reach, and it runs in the
-- secure environment so it keeps working in a fight. Blizzard notes that
-- they keep it for exactly this - an addon setting the attribute itself.
--
-- The menu below is what happens on a client that does not have it. It is
-- the same rule, shortened to the units a bar can read.
---------------------------------------------------------------------------

local function MenuFor(unit)
    if UnitIsUnit(unit, "player") then return "SELF" end
    if unit:match("^partypet") or UnitIsOtherPlayersPet(unit) then return "OTHERPET" end
    if unit:match("^party") then return "PARTY" end
    if UnitIsPlayer(unit) then
        if UnitInRaid(unit) then return "RAID_PLAYER" end
        if UnitInParty(unit) then return "PARTY" end
        return "PLAYER"
    end
    return "TARGET"
end

---------------------------------------------------------------------------
-- What a bar opens when you click it
--
-- A bar that shows a thing the game already has a window for should be a
-- way into that window: reputation opens the reputation panel, experience
-- opens the character panel it is a summary of.
--
-- Health and power bars are left out of this on purpose: they are secure
-- buttons whose clicks target the unit and open its menu, and a third
-- meaning for a click there would be taking one away.
---------------------------------------------------------------------------

local function OpenCharacterTab(tab)
    return function()
        if _G.ToggleCharacter then _G.ToggleCharacter(tab) end
    end
end

local KIND_OPENS = {
    rep = { open = OpenCharacterTab("ReputationFrame") },
    xp  = { open = OpenCharacterTab("PaperDollFrame")  },
}

-- Whether a bar needs the mouse at all, and what it does with it.
--
-- Asked again whenever something that could change the answer changes,
-- because a bar that takes the mouse is a bar the world cannot be clicked
-- through: it should only do that while it has a reason to.
local function ApplyBarMouse(bar)
    local frame, def = bar.frame, bar.def
    if def.kind == "health" or def.kind == "power" then return end

    local opens = KIND_OPENS[def.kind]
    local clickable = opens and addon:GetSetting("barClicks") ~= false
    -- "On Hover" is offered for every bar, and a bar that never hears the
    -- mouse can never honour it. Nor can it change what it says under the
    -- mouse if it never knows the mouse is there.
    local hovers = (def.textMode or "always") == "hover" or HasHoverFormat(def)

    frame:EnableMouse((clickable or hovers) and true or false)

    frame:SetScript("OnEnter", function(self)
        self._hovered = true
        self:_RefreshText()
        if HasHoverFormat(def) then UnitBars:Update(bar) end
    end)
    frame:SetScript("OnLeave", function(self)
        self._hovered = false
        self:_RefreshText()
        if HasHoverFormat(def) then UnitBars:Update(bar) end
    end)

    frame:SetScript("OnMouseUp", clickable and function(_, button)
        if button == "LeftButton" then opens.open() end
    end or nil)
end

local function UnitMenu(frame)
    local unit = frame:GetAttribute("unit") or "player"
    if _G.UnitPopup_OpenMenu then
        _G.UnitPopup_OpenMenu(MenuFor(unit),
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

        -- SecureUnitButton_OnLoad hands the right button to a function of
        -- ours; hand it back to the game instead, where it picks the menu
        -- that suits the unit. The function above stays as the answer for
        -- a client without it.
        if _G.SECURE_ACTIONS and _G.SECURE_ACTIONS.togglemenu then
            frame:SetAttribute("*type2", "togglemenu")
        end
        frame:RegisterForClicks("AnyUp")
        -- The game shows and hides it as the unit comes and goes, in the
        -- secure environment, so it keeps working during a fight.
        if _G.RegisterUnitWatch then _G.RegisterUnitWatch(frame) end
        frame:SetScript("OnEnter", function(self)
            self._hovered = true
            self:_RefreshText()
            if HasHoverFormat(def) then UnitBars:Update(bar) end
            if addon:GetSetting("unitTooltips") == false then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetUnit(def.unit)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function(self)
            self._hovered = false
            self:_RefreshText()
            if HasHoverFormat(def) then UnitBars:Update(bar) end
            GameTooltip:Hide()
        end)
    end

    ApplyBarMouse(bar)

    if def.kind == "cast" then
        frame:SetScript("OnUpdate", function(self) CastTick(self) end)
        BazUI.Dock:SetShown(frame, false)
    end

    -- Every bar is somewhere another bar can dock to.
    BazUI.Dock:RegisterHost(self:HostID(def.id), frame,
        def.name or ("Bar " .. def.id), 30)

    -- And every bar knows how to make another of itself, which is what
    -- lets a whole stack be copied for another unit.
    BazUI.Dock:RegisterCopier(frame, function(unit, hostId, edge, drop)
        return UnitBars:CopyBar(def, unit, hostId, edge, drop)
    end)

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
        -- The fill's width, not the frame's: the number kept here is the
        -- one handed back to SetBarSize, and the frame is that plus the
        -- border. Reading the frame would grow the bar every time it was
        -- undocked.
        local width = frame.GetFillSize and frame:GetFillSize() or frame:GetWidth()
        if width and width > 0 then def.width = math.floor(width + 0.5) end
    end

    frame:SetBarSize(math.max(1, math.min(1200, def.width or 240)),
        math.max(1, math.min(48, def.height or 24)))
    frame:SetTextMode(def.textMode or "always")
    ApplyBarMouse(bar)
    frame:SetTicks(def.ticks or 0)
    frame:SetFillDirection(def.fillFrom or "LEFT")

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
        gutter  = def.gutter,
        order   = def.id,
        gap     = def.gap,
        offset  = dock.offset,
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
-- behavior and should not have a second copy of it. What stays here is
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
    level           = "Level",
    nameLevel       = "Name and level",
}

-- Only a unit has a level worth naming. A reputation bar has none at all,
-- and an experience bar already writes the player's level into its name,
-- so offering these there would be offering the same thing twice.
local LEVEL_KINDS = { health = true, power = true }

local function FormatOptions(kind)
    if LEVEL_KINDS[kind] then return ValuesArray(TEXT_FORMATS) end

    local without = {}
    for key, label in pairs(TEXT_FORMATS) do
        if not LEVEL_WORDINGS[key] then without[key] = label end
    end
    return ValuesArray(without)
end
local EDGES = { BOTTOM = "Below", TOP = "Above" }

-- How much of its host a docked bar takes, and where it sits across it.
local TAKES = {
    full = "The whole width",
    half = "Half the width",
    own  = "Its own width",
}
local ALIGNS = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
local FILL_FROM = { LEFT = "The left", RIGHT = "The right" }

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
          min = 1, max = 48, step = 1,
          get = function() return def.height or 24 end,
          set = function(value) def.height = value Refresh() end },

        { type = "dropdown", section = "Text", label = "Show text",
          options = ValuesArray(TEXT_MODES),
          get = function() return def.textMode or "always" end,
          set = function(value) def.textMode = value Refresh() end },

        { type = "dropdown", section = "Size", label = "Fills from",
          options = ValuesArray(FILL_FROM),
          get = function() return def.fillFrom or "LEFT" end,
          set = function(value) def.fillFrom = value Refresh() end },

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
            type = "slider", section = "Docking", label = "Space beside",
            min = 0, max = 40, step = 1,
            get = function() return def.gutter or 0 end,
            set = function(value) def.gutter = value Refresh() end,
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
            options = FormatOptions(def.kind),
            get = function() return def.textFormat or "namePercent" end,
            set = function(value) def.textFormat = value Refresh() end,
        })

        -- A second wording for while the mouse is on it. Below the first,
        -- because it only makes sense once you have read that one.
        local hoverOptions = FormatOptions(def.kind)
        table.insert(hoverOptions, 1, { label = "Same as usual", value = "same" })
        table.insert(widgets, at + 1, {
            type = "dropdown", section = "Text", label = "When hovered",
            options = hoverOptions,
            get = function() return def.hoverFormat or "same" end,
            set = function(value)
                def.hoverFormat = (value ~= "same") and value or nil
                Refresh()
            end,
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
            label = "Copy this and everything under it...",
            onClick = function(mover)
                BazUI:OpenCopyStackMenu(bar.frame, mover)
            end,
        },
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
        onOffset  = function(x, y)
            -- Kept with the dock it belongs to, so undocking takes the
            -- nudge with it rather than leaving it to surprise whoever
            -- docks the bar somewhere else later.
            def.dock = def.dock or { host = "float" }
            def.dock.offset = (x ~= 0 or y ~= 0) and { x = x, y = y } or nil
            UnitBars:Save()
        end,
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
-- Never on the spot: a widget's setter asks for this when the choices
-- change, and rebuilding there tears down the widget that is mid-call,
-- whose replacement sets its value, which calls the setter again. A
-- frame's delay lets the callback finish, and the flag coalesces a
-- burst of changes into one rebuild.
local refreshQueuedEdit = false

function UnitBars:RefreshEditSettings()
    if refreshQueuedEdit then return end
    refreshQueuedEdit = true
    C_Timer.After(0, function()
        refreshQueuedEdit = false
        for _, bar in pairs(UnitBars.bars) do
            if bar.mover then
                BazUI:UpdateEditModeSettings(bar.mover, UnitBars:EditSettings(bar))
            end
        end
    end)
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
        "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED",
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_CHANNEL_UPDATE",
    }) do
        pcall(frame.RegisterUnitEvent, frame, event, unit)
    end
    if unit == "target" then frame:RegisterEvent("PLAYER_TARGET_CHANGED") end

    frame:SetScript("OnEvent", function(_, event)
        -- A unit's power and auras can arrive a moment after the game
        -- says the unit exists, so a target change is read twice: now,
        -- and again on the next frame for whatever was not there yet.
        if event == "PLAYER_TARGET_CHANGED" then
            C_Timer.After(0, function()
                for _, bar in pairs(UnitBars.bars) do
                    if bar.def.unit == unit then UnitBars:Update(bar) end
                end
            end)
        end

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

---------------------------------------------------------------------------
-- Range
--
-- A party member you cannot reach is worth knowing about before you
-- start casting at them, so their bars fade. UnitInRange answers only
-- for people in your group, which is the right restriction rather than a
-- limitation: "in range" of a target you are fighting means nothing, and
-- the second return says whether the question applied at all.
--
-- Fading is alpha, so unlike almost everything else here it keeps
-- working in combat, which is the only time it matters.
---------------------------------------------------------------------------

local RANGE_INTERVAL = 0.2
local rangeTicker

-- Whether this client will let us read a unit's range at all. Set false
-- the first time it refuses, and never asked again: the check runs on a
-- ticker, so asking per bar per tick means thousands of thrown errors.
local rangeReadable = true

function UnitBars:CheckRange()
    local fade = addon:GetSetting("rangeFade") ~= false
    for _, bar in pairs(self.bars) do
        local def = bar.def
        if def.kind == "health" or def.kind == "power" then
            local out = false
            if fade and def.unit ~= "player" and UnitExists(def.unit) then
                -- Both of these can be secret, and `checked and ...` is a
                -- truth test, which is a read. A unit whose range we are
                -- not allowed to know is treated as in range: a bar faded
                -- for no reason is worse than one that never fades.
                --
                -- Asked once, not once per bar per tick. On a client that
                -- keeps range secret every call raises and is caught, and
                -- this runs on a ticker: it was 1130 thrown-and-caught
                -- errors in one session before the answer was remembered.
                if rangeReadable then
                    local inRange, checked = UnitInRange(def.unit)
                    local ok, value = pcall(function()
                        return (checked and not inRange) or false
                    end)
                    if ok then
                        out = value
                    else
                        rangeReadable = false
                    end
                end
            end
            if out ~= bar._outOfRange then
                bar._outOfRange = out
                RefreshAlpha(bar)
            end
        end
    end
end

function UnitBars:WatchRange()
    if rangeTicker then return end
    rangeTicker = CreateFrame("Frame")
    rangeTicker.elapsed = 0
    rangeTicker:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < RANGE_INTERVAL then return end
        self.elapsed = 0
        UnitBars:CheckRange()
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

    self:WatchRange()

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
    "partypet1", "partypet2", "partypet3", "partypet4",
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

    local made = 0
    for index, unit in ipairs(PARTY_UNITS) do
        local health = self:Add("health", unit)
        if health then
            made = made + 1
            health.width = 180
            -- Each member is a stack of their own, placed under the last
            -- rather than docked to it. Chaining them together made one
            -- tree of the whole party, which reads the same on screen and
            -- is not the same thing at all: deleting party one's power
            -- would take party two, three and four with it, and copying
            -- everything under party one copies the entire party.
            health.position = {
                point = "LEFT", relPoint = "LEFT",
                x = 20, y = 120 - (index - 1) * 56,
            }

            local power = self:Add("power", unit)
            if power then
                made = made + 1
                power.width = 180
                power.height = 16
                power.dock = { host = self:HostID(health.id), edge = "BOTTOM" }
                power.gap = 1
            end
        end
    end

    self:Save()
    self:ApplyAll()
    return made
end

---------------------------------------------------------------------------
-- Copying a stack, and what to point it at
--
-- Set up party one exactly as you want it and the same arrangement is
-- wanted three more times. The dock does the walking; this is the list
-- of units to point the copy at, which lives here because this is where
-- the units are named.
---------------------------------------------------------------------------

-- Copy, then say what happened to each piece. Anything that was given a
-- host and came out loose is called out: on screen it looks the same as
-- something that was never told where to go, which is exactly how a
-- broken copy passes for a working one.
function UnitBars:RunCopy(frame, unit)
    local report = {}
    local made = BazUI.Dock:CopyStack(frame, unit, report)
    addon:Print(("Copied %d%s."):format(made or 0,
        unit and (" for " .. (UnitBars.UNITS[unit] or unit)) or ""))

    for _, entry in ipairs(report) do
        if entry.host and not entry.docked then
            addon:Print(("  %s was told to dock to %s and did not."):format(
                entry.id or "?", entry.host))
        end
    end
end

function UnitBars:RegisterCopyMenu()
    BazUI:RegisterContextMenuSection("bazui-copystack", "Copy for", function(frame)
        local items = {}
        if not frame then return items end

        items[#items + 1] = {
            label = "The same units",
            onClick = function() UnitBars:RunCopy(frame, nil) end,
        }
        for _, unit in ipairs(UNIT_ORDER) do
            items[#items + 1] = {
                label = UnitBars.UNITS[unit],
                onClick = function() UnitBars:RunCopy(frame, unit) end,
            }
        end
        return items
    end)
end

-- Opened from an Actions button, which is handed the handle rather than
-- the thing itself, so that is what the menu hangs off.
function BazUI:OpenCopyStackMenu(frame, anchor)
    if InCombatLockdown() then
        BazUI:Print("Copy things after combat ends.")
        return
    end
    BazUI:OpenContextMenu("bazui-copystack", anchor or UIParent, frame,
        { title = "Copy for" })
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
