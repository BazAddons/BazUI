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
-- unit to ask about. The rest of the unit colors live in Core/Units.lua.
local CAST_COLOR    = { 1.00, 0.82, 0.00, 1 }

-- The game's mirror timers, by the name it calls each one. Blizzard
-- draws all of them in the casting bar's own art, which is fine until
-- you are drowning and fatigued at once and the two bars look alike.
-- A color each, and the bar says which it is in words as well.
local MIRROR_COLORS = {
    BREATH     = { 0.25, 0.55, 0.95, 1 },
    EXHAUSTION = { 0.95, 0.55, 0.15, 1 },
    FEIGNDEATH = { 0.60, 0.60, 0.65, 1 },
    DEATH      = { 0.80, 0.20, 0.20, 1 },
}
local MIRROR_FALLBACK_COLOR = { 0.40, 0.60, 0.90, 1 }

-- Which one a single bar shows when more than one is running. Drowning
-- kills you sooner than tiredness does.
local MIRROR_ORDER = { "BREATH", "DEATH", "EXHAUSTION", "FEIGNDEATH" }
local CHANNEL_COLOR = { 0.45, 0.68, 0.85, 1 }
local FAILED_COLOR  = { 0.85, 0.30, 0.30, 1 }

-- What a bar can read. Everything else about it is the same.
UnitBars.KINDS = {
    health   = "Health",
    power    = "Power",
    cast     = "Casting",
    -- The game's own name for the breath, fatigue and feign death bars,
    -- and the one most players already know them by.
    mirror   = "Mirror",
    xp       = "XP",
    rep      = "Reputation",
    -- Two that show no value at all. They are bars in every other sense:
    -- the same size, the same docking, the same handle in Edit Mode, so
    -- a portrait docks to the left of a health bar and a blank one holds
    -- the marks underneath it without any of that being written twice.
    portrait = "Portrait",
    blank    = "Blank",
}

-- Kinds with nothing to fill. The fill is hidden and the text, the
-- marks and - for a portrait - the picture are all there is.
local NO_FILL = { portrait = true, blank = true }
UnitBars.NO_FILL = NO_FILL

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

-- The kinds whose frames RegisterUnitWatch shows and hides. One answer,
-- because two things depend on it agreeing: the frame is made secure, and
-- the dock is told to keep its hands off the frame's visibility.
local function UnitWatched(def)
    return def.kind == "health" or def.kind == "power"
end

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
        -- A portrait starts square, because a face stretched across a
        -- bar's width is a smeared face and nobody wants to discover
        -- that by making one. Everything else starts bar-shaped.
        width      = (kind == "portrait") and 40 or 240,
        -- Four pixels a side go to the outline, the rim and the line
        -- between them, so this is a sixteen pixel fill.
        height     = (kind == "portrait") and 40 or 24,
        -- A portrait says nothing - whose face it is, is the picture.
        textMode   = (kind == "portrait") and "never" or "always",
        -- And it keeps its shape: whichever side the dock sets, the other
        -- follows, so a face is never stretched across a bar.
        square     = (kind == "portrait") or nil,
        -- A blank bar says who it is about, since a bar of marks with no
        -- name on it is a puzzle.
        textFormat = (kind == "blank") and "name"
            or (kind == "xp" or kind == "rep") and "detailed"
            or ((kind == "power" or kind == "cast" or kind == "mirror")
                and "current" or "namePercent"),
        ticks      = (kind == "xp") and 10 or 0,
        dock       = { host = "float", edge = "BOTTOM" },
        position   = { point = "CENTER", relPoint = "CENTER", x = 0, y = -160 },
    }
    def.name = self:DefaultName(kind, unit)
    defs[#defs + 1] = def
    self:Save()

    -- Making a mirror bar is asking for the game's own breath and
    -- fatigue bars to be replaced, so the first one takes them down.
    -- Only where the switch has never been touched: somebody who has
    -- turned it on or off has said what they want, and this is not a
    -- second opinion.
    if kind == "mirror" and addon:GetSetting("hideMirrorTimers") == nil then
        addon:SetSetting("hideMirrorTimers", true)
        self:SuppressStock()
        addon:Print("The game's own timer bars are hidden now. "
            .. "Blizzard's Frames has the switch.")
    end

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
        -- Not the dock's ticket either. A copy is a new docking, even
        -- when it lands on the same edge as the bar it came from, and it
        -- goes to the back of the queue: whatever was already docked
        -- there keeps the size it was given before the copy existed.
        if key ~= "id" and key ~= "name" and key ~= "unit"
            and key ~= "dock" and key ~= "position"
            and key ~= "dockSeq" and key ~= "dockedAs" then
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

-- Take a bar down, without touching the list it came from. Deleting one
-- and switching to a profile that never had it are the same teardown;
-- only the bookkeeping around it differs.
function UnitBars:TearDown(id)
    local bar = self.bars[id]
    if not bar then return end

    BazUI.Dock:Detach(bar.frame)
    BazUI.Dock:UnregisterHost(self:HostID(id))
    BazUI.Dock:UnregisterCopier(bar.frame)

    -- A health or power bar does not decide for itself whether it is on
    -- screen: RegisterUnitWatch does, in the secure environment, and it
    -- goes on showing the frame whenever the unit exists. Hiding a
    -- deleted bar without canceling that is why one stayed on screen
    -- with no handle to grab, until a reload.
    if _G.UnregisterUnitWatch then _G.UnregisterUnitWatch(bar.frame) end
    bar.frame:SetAttribute("unit", nil)
    bar.frame:SetScript("OnUpdate", nil)
    bar.frame:Hide()

    -- Secure frames cannot be destroyed, so it is parked out of the way
    -- rather than left loose under UIParent where something could show
    -- it again.
    bar.frame:ClearAllPoints()
    bar.frame:SetParent(RetiredParent())

    if bar.mover then
        BazUI:UnregisterEditModeFrame(bar.mover)
        bar.mover:Hide()
    end
    self.bars[id] = nil
end

function UnitBars:Remove(id)
    if InCombatLockdown() then return false end
    local defs = self:Defs()
    for i, def in ipairs(defs) do
        if def.id == id then
            self:TearDown(id)
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
        label   = "Hide the player frame",
        desc    = "The game's own portrait frame for you.",
        default = true,
        frames  = { "PlayerFrame" },
    },
    {
        key     = "hideTargetFrame",
        label   = "Hide the target frame",
        desc    = "The game's own portrait frame for your target.",
        default = true,
        frames  = { "TargetFrame" },
    },
    {
        key     = "hidePlayerCastBar",
        label   = "Hide the casting bar",
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
        key     = "hidePartyFrames",
        label   = "Hide the party frames",
        desc    = "The portrait frames down the left in a group. Make party bars first, or a group will have nothing showing it at all.",
        default = true,
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
        key     = "hidePetCastBar",
        label   = "Hide the pet casting bar",
        desc    = "The casting bar for your pet.",
        default = true,
        frames = { "PetCastingBarFrame" },
    },
    {
        key     = "hideMirrorTimers",
        label   = "Hide the game's timer bars",
        desc    = "The breath, fatigue and feign death bars the game floats at the top of the screen. Left alone until you make a mirror bar of your own - with neither of them you would drown without warning - and turned on for you the first time you make one.",
        default = false,
        -- The container on clients that pool them, and the three old
        -- globals for the ones that do not. A name that is not there
        -- costs nothing.
        frames  = { "MirrorTimerContainer",
                    "MirrorTimer1", "MirrorTimer2", "MirrorTimer3" },
    },
    {
        key     = "hideRaidManager",
        label   = "Hide the raid manager tab",
        desc    = "The tab at the left edge of the screen that slides out with the target markers, group filters and ready check on it. The game shows it whenever you are in a group.",
        default = true,
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
-- One entry, not one name. Several of these list alternative spellings on
-- purpose - four names for the casting bar, the pooled party frames that
-- only older clients gave globals to - and asking after each separately
-- reported half of them missing on a client where the switch works
-- perfectly. The switch works if any one of its frames is there.
for _, entry in ipairs(UnitBars.STOCK) do
    BazUI:RegisterAnyDependency({
        module = "Unit Frames",
        label  = table.concat(entry.frames, " or "),
        why    = "Hidden by the " .. entry.label .. " switch.",
        names  = entry.frames,
    })
end

-- No dependency is declared for the right-click menu.
--
-- There was one, on SECURE_ACTIONS.togglemenu, and it reported missing on
-- every client because SECURE_ACTIONS is a file local in Blizzard's
-- SecureTemplates.lua and never a global. A check that cannot pass
-- anywhere is worse than no check: it trains you to read past the word
-- MISSING. What the attribute does is only observable from inside the
-- secure environment, so there is nothing here to honestly ask.

-- Which of the game's frames are meant to be down, held here rather than
-- on their frames. They used to be reparented to a hidden carrier, with
-- the old parent written onto the frame - both of them writes to things
-- we do not own. PlayerFrame, TargetFrame, PlayerCastingBarFrame and
-- PartyFrame are all Edit Mode systems on this client, and Edit Mode
-- walks them on the way in; anything of ours left on them taints that
-- walk. BazUI.SuppressFrame hides them through their own OnShow instead,
-- and calls Hide as Blizzard rather than as us.
local stockHidden = setmetatable({}, { __mode = "k" })

-- Which of the names in STOCK we have actually taken hold of, by name
-- rather than by frame, so it survives the frame itself being collected
-- and can be read back by /bazframes stock.
local stockHooked = {}
UnitBars.stockHooked = stockHooked

local suppressKey

function UnitBars:SuppressStock()
    -- Asked on every save, and a save happens every time a bar is
    -- dragged, so nothing is touched unless an answer has changed.
    local parts = {}
    for _, entry in ipairs(self.STOCK) do
        parts[#parts + 1] = self:StockHidden(entry) and "1" or "0"
    end
    local key = table.concat(parts)

    -- The other reason to do the work: a frame that was not there last
    -- time is there now.
    --
    -- Not every frame in this list exists at login. The raid manager is
    -- the one that matters: Blizzard build it hidden and only show it
    -- once you are in a group, and several of the others belong to
    -- add-ons of Blizzard's own that load later than we do. Keying the
    -- skip on the settings alone meant the first pass found five frames,
    -- decided nothing had changed since, and never looked for the sixth.
    -- So a switch that reads as on did nothing.
    local fresh = false
    for _, entry in ipairs(self.STOCK) do
        for _, name in ipairs(entry.frames) do
            if _G[name] and not stockHooked[name] then fresh = true break end
        end
        if fresh then break end
    end

    if key == suppressKey and not fresh then return end

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
                stockHooked[name] = true
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
-- Why is that bar black
--
-- A bar draws nothing when it has no color, when it has no value, or when
-- it has no texture, and all three look identical on screen: the dark
-- track showing through. Guessing between them has cost two wrong fixes,
-- so this asks the bar.
--
-- Everything is read through pcall, twice over, and the second one is the
-- one that matters.
--
-- A value handed to a widget may be one of Forever's secret numbers,
-- which this code may pass along and may not look at. Calling the getter
-- does not raise - it hands back the secret quite happily. Neither does
-- tostring, which returns a *secret string*. What raises is the first
-- thing that tries to make ordinary text of it, which here is the concat
-- at the end - so the concat is what has to be guarded. The first version
-- of this guarded the tostring instead and the secret walked straight
-- through it.
--
-- "secret" is an answer worth printing. A bar holding a secret value has
-- been given a value; the question is only whether it can draw it.
---------------------------------------------------------------------------

local function Safe(fn, ...)
    local packed = { pcall(fn, ...) }
    if not packed[1] then return "refused" end
    if #packed == 1 then return "nil" end

    local ok, text = pcall(function()
        local out = {}
        for index = 2, #packed do
            out[#out + 1] = tostring(packed[index]) .. ""
        end
        return table.concat(out, ", ")
    end)
    return ok and text or "secret"
end

function UnitBars:PaintReport()
    local lines = {}
    for _, bar in pairs(self.bars or {}) do
        local def   = bar.def
        local frame = bar.frame
        local fill  = frame and frame.fill
        if fill then
            lines[#lines + 1] = ("|cffffd100%s %s|r  shown %s  alpha %s"):format(
                tostring(def.kind), tostring(def.unit),
                tostring(frame:IsShown()), Safe(frame.GetAlpha, frame))

            lines[#lines + 1] = ("    value %s of %s"):format(
                Safe(fill.GetValue, fill), Safe(fill.GetMinMaxValues, fill))

            local asked = "nothing yet"
            if frame._fillColor then
                asked = Safe(function(c)
                    return c[1], c[2], c[3]
                end, frame._fillColor)
            end
            lines[#lines + 1] = ("    bar color %s   asked for %s"):format(
                Safe(fill.GetStatusBarColor, fill), asked)

            local texture = fill:GetStatusBarTexture()
            if not texture then
                lines[#lines + 1] = "    |cffff6666no status bar texture at all|r"
            else
                lines[#lines + 1] = ("    texture %s  atlas %s  vertex %s"):format(
                    Safe(texture.GetTexture, texture),
                    texture.GetAtlas and Safe(texture.GetAtlas, texture) or "n/a",
                    Safe(texture.GetVertexColor, texture))
                lines[#lines + 1] = ("    texture size %s x %s  shown %s"):format(
                    Safe(texture.GetWidth, texture), Safe(texture.GetHeight, texture),
                    Safe(texture.IsShown, texture))
            end

            -- Which of the two SetValue paths last ran. A raw pair means
            -- the secret path - value and maximum handed to the widget
            -- untouched. A fraction means the ordinary one. A bar that
            -- took the fraction path with nothing to measure sits at
            -- zero, which looks exactly like a bar with no color.
            lines[#lines + 1] = ("    last set: raw %s / %s   fraction %s"):format(
                Safe(function() return frame._rawValue end),
                Safe(function() return frame._rawMax end),
                Safe(function() return frame._value end))

            lines[#lines + 1] = ("    atlas fill %s   fill size %s x %s"):format(
                tostring(frame._fillAtlas and true or false),
                Safe(fill.GetWidth, fill), Safe(fill.GetHeight, fill))
        end
    end
    if #lines == 0 then lines[1] = "No bars." end
    return lines
end

-- What actually happened to each of Blizzard's frames, for /bazframes
-- stock. A switch that reads as on and a frame still on screen has four
-- possible explanations and this tells them apart: the frame does not
-- exist under that name, we never took hold of it, we took hold of it and
-- something showed it again, or the frame is protected and we are in
-- combat.
function UnitBars:StockReport()
    local lines = {}
    for _, entry in ipairs(self.STOCK) do
        local hide = self:StockHidden(entry)
        lines[#lines + 1] = ("|cffffd100%s|r switch: %s"):format(
            entry.label, hide and "hide" or "leave alone")
        for _, name in ipairs(entry.frames) do
            local frame = _G[name]
            if not frame then
                lines[#lines + 1] = ("    %s: no such frame"):format(name)
            else
                lines[#lines + 1] = ("    %s: hooked %s, shown %s, visible %s, protected %s"):format(
                    name,
                    tostring(stockHooked[name] and true or false),
                    tostring(frame:IsShown() and true or false),
                    tostring(frame:IsVisible() and true or false),
                    tostring(frame.IsProtected and frame:IsProtected() and true or false))
            end
        end
    end
    lines[#lines + 1] = ("in combat: %s"):format(tostring(InCombatLockdown()))
    return lines
end

---------------------------------------------------------------------------
-- Reading a unit
---------------------------------------------------------------------------

local function Number(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(math.floor(n))
end

-- Offline and dead read as gray whatever else is true of them: a party
-- member's last known health is not worth coloring as if it were
-- current. The rule lives in Core/Units.lua so the name plates paint the
-- same unit the same way.
local function HealthColor(unit)
    return BazUI.UnitColor(unit, { classColor = addon:GetSetting("classColor") })
end

-- Read the same careful way as the health color. UnitPowerType is not
-- documented as secret-returning, but a restricted unit hands back values
-- of every sort, and a color built from one paints the bar black. The
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
-- without a party. It used to be a gray bar at full, which answered none
-- of the questions you have while arranging: whether a name of real
-- length fits, what four class colors look like stacked, whether a
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
    -- Through the shared helper: UnitName drops the surname on this
    -- client, because it returns it separately. See BazUI.UnitDisplayName.
    local name = BazUI.UnitDisplayName(unit)
    if LEVEL_WORDINGS[wording] then return name end

    local rank = addon:GetSetting("rankWord") == true
    local level = addon:GetSetting("showLevel") == true
    if not (rank or level) then return name end

    local extra = BazUI.UnitLevelText(unit, { level = level, rank = rank })
    if not extra then return name end
    -- A name can be a secret string, and one of those cannot be joined to
    -- anything or even compared with the empty string. When that is
    -- refused the name goes back on its own: which unit this is matters
    -- more than its level, and the level is never the part worth keeping.
    return BazUI.Secret.Read(function()
        return name ~= "" and (name .. "  " .. extra) or extra
    end, name)
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

---------------------------------------------------------------------------
-- Resting, and the rest of the marks
--
-- The zZ used to be written out here, on player health bars only. It is
-- one entry in Indicators.lua now, and a health bar asks for it through
-- the same path a blank bar does - so there is one answer to "is this
-- bar resting" rather than two that can drift apart.
--
-- These two stay because the Edit Mode panel and the settings page ask
-- them by name. They are the registry's answers, spelled the old way.
---------------------------------------------------------------------------

function UnitBars:RestIconWanted(def)
    return addon.Indicators and addon.Indicators:Wanted(def, "rest") or false
end

function UnitBars:CanWearRestIcon(def)
    return addon.Indicators and addon.Indicators:CanWear(def, "rest") or false
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

-- Which wordings put the unit's name in the line. Only these may have
-- one when the wording has to be approximated below.
local NAMED_WORDINGS = {
    name = true, nameLevel = true, namePercent = true, detailed = true,
}

-- The wording the user picked, or as near as can be got to it without
-- arithmetic we are not allowed to do.
--
-- Health and power are secret numbers on some clients: they can be handed
-- to a widget, which may print them, but not compared or divided by us.
-- So any wording that needs a percentage has no answer here, and the
-- nearest honest thing is the pair of numbers.
--
-- What it must not do is put a name in that the wording never asked for.
-- It used to prepend one unconditionally, so a bar set to "Current / Max"
-- read "Bazbot  69564 / 69564" - the wording was being decided by whether
-- the numbers happened to be secret rather than by the setting, and on a
-- client where they always are, half the choices on the panel did the
-- same thing.
local function SetBarText(bar, wording, current, maximum, name, level)
    local ok, text = pcall(Format, wording, current, maximum, name, level)
    if ok then
        bar.frame:SetText(text)
        return
    end

    -- The name goes in as an argument, never baked into the format. It
    -- can be a secret string, which may be printed but not read - and a
    -- player's name in a format string is a per-cent sign away from
    -- garbage anyway.
    local named = NAMED_WORDINGS[wording] and name ~= nil
        and BazUI.Secret.Read(function() return name ~= "" end, true)

    -- "current" is the one wording that approximates to a single number
    -- rather than to the pair. Everything else lands on the pair, which
    -- says as much as can be said without reading the values.
    if wording == "current" then
        if named then bar.frame:SetFormattedText("%s  %d", name, current)
        else          bar.frame:SetFormattedText("%d", current) end
    elseif named then
        bar.frame:SetFormattedText("%s  %d / %d", name, current, maximum)
    else
        bar.frame:SetFormattedText("%d / %d", current, maximum)
    end
end

local function UpdateHealth(bar)
    local unit = bar.def.unit
    ApplyRankGlow(bar, unit)
    ApplyRankIcon(bar, unit)
    if addon.Indicators then addon.Indicators:Apply(bar, unit) end
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
    -- A word instead of numbers. The name is handed to the font string
    -- rather than joined on here, and whether there is one is decided
    -- inside a guarded read: a secret name may be printed but not
    -- compared with the empty string. A name we may not look at is
    -- certainly not empty, so the benefit of the doubt goes to showing it.
    local function Status(word)
        local named = name ~= nil
            and BazUI.Secret.Read(function() return name ~= "" end, true)
        if named then bar.frame:SetFormattedText("%s  " .. word, name)
        else          bar.frame:SetText(word) end
    end

    if UnitIsConnected and not UnitIsConnected(unit) then
        Status("Offline")
    elseif UnitIsGhost(unit) then
        Status("Ghost")
    elseif UnitIsDead(unit) then
        Status("Dead")
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
    SetBarText(bar, wording, current, maximum,
        BazUI.UnitDisplayName(unit), LevelText(unit))
end

-- A portrait, which is the one bar kind whose content is a picture.
--
-- Square and centered: stretched across a wide bar it is a smeared face,
-- so the picture takes the bar's height and the bar keeps whatever width
-- it was given. That also means a portrait docked beside a health bar
-- comes out the same height as it without being told.
-- Asking a model frame for a unit, and knowing whether the asking took.
--
-- SetUnit is a request, not a result. The model turns up a moment later,
-- or it never does: the data is not loaded yet, the frame had no size to
-- draw into, the unit is somewhere the client has not bothered to model.
-- A frame that asked and got nothing draws a solid black square, and the
-- only way out of that is to ask again.
--
-- So what is remembered is what arrived, not what was asked for. There
-- has to be some guard, because SetUnit reloads the model every single
-- time and this runs on every health tick - but the old guard recorded
-- the request, which meant one request that fell through was remembered
-- as a success and the square stayed black until something unrelated
-- happened to change the unit. Remembering the arrival instead makes a
-- failed request simply a request that has not been answered yet.
--
-- Held at arm's length twice over, so a unit the client has no model for
-- does not sit there reloading: a wait between tries, and a few tries and
-- then no more. Anything that means the answer might have changed -
-- being shown again, a loading screen, the game saying portrait data has
-- arrived - clears the count and it starts asking afresh.
local MODEL_RETRY_WAIT  = 0.5
local MODEL_RETRY_LIMIT = 10

local function RequestModel(model)
    local unit, want = model._bazUnit, model._bazWant
    if not unit then return end
    if model._bazLoaded == want then return end

    -- A different unit than the one being waited on starts the count
    -- over: this is a new question, not another go at the old one.
    if model._bazAsked ~= want then
        model._bazAsked, model._bazTries, model._bazAskedAt = want, 0, nil
    end
    if (model._bazTries or 0) >= MODEL_RETRY_LIMIT then return end

    local now = GetTime and GetTime() or 0
    -- Too soon. The follow-up below is already booked, so there is
    -- nothing to arrange here.
    if model._bazAskedAt and now - model._bazAskedAt < MODEL_RETRY_WAIT then
        return
    end

    model._bazTries   = model._bazTries + 1
    model._bazAskedAt = now
    model:SetUnit(unit)

    -- Booking its own next try rather than waiting to be asked again.
    -- Updates arrive on health ticks, and a player standing still at full
    -- health gets none - so a portrait that came up black while nothing
    -- was happening would go on being black for exactly as long as
    -- nothing went on happening.
    if model._bazPending then return end
    model._bazPending = true
    C_Timer.After(MODEL_RETRY_WAIT, function()
        model._bazPending = nil
        if model:IsShown() then RequestModel(model) end
    end)
end

-- Forget what the 3D portraits are holding, so the next update asks
-- again. For the moments the game tells us the answer may have changed.
function UnitBars:InvalidatePortraits()
    for _, bar in pairs(self.bars or {}) do
        local model = bar.frame and bar.frame.model
        if model then
            model._bazLoaded, model._bazAsked, model._bazTries = nil, nil, 0
        end
    end
end

local function UpdatePortrait(bar)
    local unit   = bar.def.unit
    local frame  = bar.frame
    local threeD = bar.def.portrait3d == true

    if not frame.portrait then
        frame.portrait = frame:CreateTexture(nil, "ARTWORK")
        frame.portrait:SetPoint("CENTER")
    end
    -- Made only when asked for. A model frame is a renderer rather than a
    -- texture, and most portraits will never turn it on.
    if threeD and not frame.model then
        local model = CreateFrame("PlayerModel", nil, frame)
        model:SetFrameLevel(frame:GetFrameLevel() + 1)
        model:SetPoint("CENTER")

        -- A model frame that is hidden drops its model, and comes back
        -- blank when shown again - drawn as a solid black square, which
        -- is what a target portrait became the second time the same
        -- target was picked: the unit had not changed, so nothing asked
        -- for the model again. What it was holding is gone, so what it
        -- loaded is forgotten here and asked for from scratch.
        model:SetScript("OnShow", function(self)
            self._bazLoaded, self._bazAsked, self._bazTries = nil, nil, 0
            RequestModel(self)
        end)
        -- Framing has to be applied to a model that has actually loaded;
        -- asked of an empty frame it is quietly ignored. So it is done
        -- here, once the model is there, rather than beside SetUnit.
        --
        -- And this is where a request is marked as answered. An empty
        -- model raises this too, so the file is checked first: taking
        -- that for the model we wanted is exactly how a black square
        -- becomes permanent. A client with no way to ask is taken at its
        -- word.
        model:SetScript("OnModelLoaded", function(self)
            local arrived = (not self.GetModelFileID) or self:GetModelFileID()
            if arrived then self._bazLoaded = self._bazAsked end
            if self.SetPortraitZoom then self:SetPortraitZoom(1) end
            self:SetPosition(0, 0, 0)
        end)
        frame.model = model
    end

    local shown = (unit and UnitExists(unit)) and true or false
    -- The whole bar, not only the picture: an empty box where a target's
    -- face should be reads as a portrait that will not go away. Not a
    -- secure frame, so this is the dock's to do - but only when the
    -- answer changes. This runs on every health tick, and Dock:SetShown
    -- re-lays the host out each time it is called.
    if frame._dockWanted ~= shown then
        BazUI.Dock:SetShown(frame, shown)
    end
    frame.portrait:SetShown(shown and not threeD)
    if frame.model then frame.model:SetShown(shown and threeD) end
    if not shown then return end

    -- Square, centered, the fill's height: the same box either way, so
    -- flipping between flat and 3D moves nothing around it.
    local _, fill = frame:GetFillSize()
    local size = math.max(8, fill or 16)

    if threeD then
        local model = frame.model
        -- Sized before it is asked for anything: a model frame with no
        -- size has nowhere to draw, and what it loads into nowhere is
        -- black.
        model:SetSize(size, size)
        model._bazUnit = unit
        model._bazWant = UnitGUID and UnitGUID(unit) or unit
        RequestModel(model)
    else
        frame.portrait:SetSize(size, size)
        if SetPortraitTexture then SetPortraitTexture(frame.portrait, unit) end
    end
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
    -- Formatted by the font string, not here. The name of a cast can be a
    -- secret string, and building one into a string is a read - so the
    -- pieces are handed over separately and the widget puts them together,
    -- which it is allowed to do.
    frame:SetFormattedText("%s  %.1f", state.name, (span - elapsed) / 1000)
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

-- Whether there is a name worth showing, and what it is.
--
-- Two returns rather than one, because the name of a cast can be a
-- secret string. A font string may print one, but this code may not read
-- it - not index it for gsub, not compare it, and not even test it for
-- truth, which is what an `or` chain between two of them would do. So the
-- deciding is done here, inside the guarded read, and what comes back out
-- is a plain boolean to branch on and a value only fit to be passed along.
--
-- A name we are not allowed to look at is still a name worth showing, and
-- much better than the word "Casting" - so when the tidying is refused,
-- the candidate goes through untouched.
local function Readable(candidate)
    if candidate == nil then return false, nil end

    local ok, usable, text = BazUI.Secret.Try(function()
        if type(candidate) ~= "string" then return false, nil end
        local clean = candidate:gsub("%s*%-%s*" .. NO_SUBTEXT .. "$", "")
        if clean == "" or clean == NO_SUBTEXT then return false, nil end
        return true, clean
    end)
    if not ok then return true, candidate end
    return usable, text
end

local function CastName(display, name, channel)
    local found, text = Readable(display)
    if not found then found, text = Readable(name) end
    if not found then return channel and "Channeling" or "Casting" end
    return text
end

---------------------------------------------------------------------------
-- Mirror timers
--
-- Breath, fatigue and feign death. The game hands them over as one
-- event each, in milliseconds, and keeps the count itself - we ask it
-- how much is left rather than counting down ourselves, so a timer
-- that pauses (a breath bar does, the moment your head is above water)
-- stays where the game left it without any arithmetic of our own.
--
-- What is running is kept here rather than on the bar, because it is
-- one fact about the player and any number of bars may be showing it.
---------------------------------------------------------------------------

local mirrorActive = {}

local function MirrorClock(seconds)
    if seconds >= 60 then
        return ("%d:%02d"):format(seconds / 60, seconds % 60)
    end
    return ("%d"):format(seconds)
end

-- The timer a bar should be showing, or nil when there is nothing to
-- show. Priority order, so drowning beats being tired.
local function MirrorShowing()
    for _, name in ipairs(MIRROR_ORDER) do
        if mirrorActive[name] then return name, mirrorActive[name] end
    end
    -- Anything the client has that this list does not.
    return next(mirrorActive)
end

local function MirrorTick(frame)
    local name, state = MirrorShowing()
    if not (name and state) then
        if frame._mirror then
            frame._mirror = nil
            if not previewing then BazUI.Dock:SetShown(frame, false) end
        end
        return
    end

    -- Asked every frame, the same way the game asks itself. A paused
    -- timer simply keeps answering the same number.
    local left = BazUI.Secret.Read(function()
        local ms = _G.GetMirrorTimerProgress and _G.GetMirrorTimerProgress(name)
        return (type(ms) == "number") and ms or nil
    end, nil)
    if not left then left = state.value end
    if not left or left < 0 then left = 0 end

    if frame._mirror ~= name then
        frame._mirror = name
        frame:SetFillColor(MIRROR_COLORS[name] or MIRROR_FALLBACK_COLOR)
        frame:SetAlpha(1)
        BazUI.Dock:SetShown(frame, true)
    end

    local span = state.max or 0
    frame:SetValue(span > 0 and (left / span) or 0)
    frame:SetFormattedText("%s  %s", state.label or "Timer",
        MirrorClock(left / 1000))
end

-- One event for all of them, so the bars themselves hold no state.
function UnitBars:MirrorStart(name, value, maxvalue, paused, label)
    if not name or name == "UNKNOWN" then return end
    mirrorActive[name] = {
        value = value, max = maxvalue, label = label or name,
        paused = paused and true or false,
    }
end

function UnitBars:MirrorStop(name)
    if not name then return end
    mirrorActive[name] = nil
end

function UnitBars:MirrorPause(name, paused)
    local state = name and mirrorActive[name]
    if state then state.paused = paused and true or false end
end

-- Show or hide every mirror bar for what is running now.
--
-- This has to be driven by the events, not by the tick. A frame that is
-- hidden is not given an OnUpdate at all, so a bar waiting for a breath
-- timer would have waited for ever: the only thing that could have
-- shown it was the tick that only runs once it is shown. It appeared
-- solely if you happened to be underwater while Edit Mode had it up.
function UnitBars:ShowMirrors()
    local running = MirrorShowing()
    self:ForKind("mirror", nil, function(bar)
        local frame = bar.frame
        if running then
            -- Cleared so the tick treats this as a new timer and puts
            -- the right color and label on before the first frame.
            frame._mirror = nil
            frame:SetAlpha(1)
            BazUI.Dock:SetShown(frame, true)
            MirrorTick(frame)
        elseif not previewing then
            frame._mirror = nil
            BazUI.Dock:SetShown(frame, false)
        end
    end)
end

-- What the game is already counting, which is how a bar made mid-dive,
-- or one arriving with a reload, finds the breath timer already running.
function UnitBars:MirrorSync()
    if not _G.GetMirrorTimerInfo then return end
    for index = 1, 3 do
        BazUI.Secret.Read(function()
            local name, value, maxvalue, _, paused, label =
                _G.GetMirrorTimerInfo(index)
            if name and name ~= "UNKNOWN" then
                UnitBars:MirrorStart(name, value, maxvalue, paused, label)
            end
            return true
        end, nil)
    end
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
    elseif kind == "portrait" then UpdatePortrait(bar)
    elseif kind == "blank" then
        -- Nothing to read; it holds whatever marks it was given, and its
        -- text, which the shared text pass already set.
        if addon.Indicators then addon.Indicators:Apply(bar, bar.def.unit) end
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
    if BazUI.Secret.IsUnit(unit, "player") then return "SELF" end
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
        BazUI.OpenCharacterSheet(tab)
    end
end

-- `secureTo` names one of Blizzard's buttons to forward the click to, so
-- their panel opens without our taint on the stack - see
-- BazUI.SecureForward. Only the experience bar has one: the character
-- micro button opens the sheet on whichever tab it was last on, which is
-- exactly right for a bar that wants the sheet and wrong for one that
-- wants the reputation tab. Reputation keeps the direct call, and keeps
-- the one error that comes with it, rather than quietly opening
-- somewhere else.
local KIND_OPENS = {
    rep = { open = OpenCharacterTab("ReputationFrame") },
    xp  = { open = OpenCharacterTab("PaperDollFrame"),
            secureTo = "CharacterMicroButton" },
}

-- Whether a bar needs the mouse at all, and what it does with it.
--
-- Asked again whenever something that could change the answer changes,
-- because a bar that takes the mouse is a bar the world cannot be clicked
-- through: it should only do that while it has a reason to.
local function ApplyBarMouse(bar)
    local frame, def = bar.frame, bar.def
    -- A secure unit button handles its own mouse.
    if UnitWatched(def) then return end

    local opens = KIND_OPENS[def.kind]
    local clickable = opens and addon:GetSetting("barClicks") ~= false
    -- "On Hover" is offered for every bar, and a bar that never hears the
    -- mouse can never honor it. Nor can it change what it says under the
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

    -- Built once per bar. The overlay covers the bar and hands hover
    -- back to it, so the bar still changes what it says under the mouse.
    if clickable and opens.secureTo and not bar._secureClick then
        bar._secureClick = BazUI.SecureForward(frame, opens.secureTo,
            { parent = frame, relayMotion = frame }) or false
    end
    if bar._secureClick then
        bar._secureClick:SetShown(clickable and true or false)
    end

    frame:SetScript("OnMouseUp", (clickable and not bar._secureClick) and function(_, button)
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
    local existing = self.bars[def.id]
    if existing then
        -- Switching profile hands the module a whole new settings table,
        -- and the definitions in it are new tables even when they say
        -- exactly the same thing. The bars stay, so without this every
        -- one of them would go on reading - and writing - the definition
        -- belonging to whichever profile was worn when it was made.
        -- Dropping a bar somewhere would then save to a profile nobody
        -- is wearing, and the next layout pass would put it back.
        existing.def = def
        return existing
    end
    if InCombatLockdown() then return nil end

    local secure = UnitWatched(def)
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
        -- that suits the unit.
        --
        -- Set unconditionally, and that is the fix rather than the risk.
        -- This used to be guarded by `if _G.SECURE_ACTIONS` - but
        -- SECURE_ACTIONS is a file local inside Blizzard's
        -- SecureTemplates.lua on every client, never a global, so the
        -- guard was always false and the attribute was never set. Right
        -- clicking a bar has been falling back to the menu below this
        -- whole time.
        --
        -- We do not need to see it. The attribute is read inside the
        -- secure environment, where it is in scope; asking from out here
        -- was the mistake. A client that does not understand the
        -- attribute ignores it, and the fallback menu is still attached.
        frame:SetAttribute("*type2", "togglemenu")
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
    elseif def.kind == "mirror" then
        frame:SetScript("OnUpdate", function(self) MirrorTick(self) end)
        BazUI.Dock:SetShown(frame, false)
        -- Made mid-dive, it should come up holding the timer that is
        -- already counting rather than waiting for the next one.
        C_Timer.After(0, function() UnitBars:ShowMirrors() end)
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

    -- Bars left behind by the profile before this one. A switch replaces
    -- the settings, not the frames, so a bar the new profile has never
    -- heard of would sit on screen answering to nothing.
    local live = {}
    for _, def in ipairs(self:Defs()) do live[def.id] = true end
    for id in pairs(self.bars) do
        if not live[id] then self:TearDown(id) end
    end

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
    -- A bar docked above or below something takes that thing's width; one
    -- docked to its side takes its height. Either way the dock sets that
    -- measurement below, after this, so what is written here is only
    -- what a floating bar keeps.
    local wasDocked = BazUI.Dock:IsDocked(frame)
    local goingFloat = not def.dock or def.dock.host == "float"

    if wasDocked and goingFloat then
        -- The fill's size, not the frame's: the number kept here is the
        -- one handed back to SetBarSize, and the frame is that plus the
        -- border. Reading the frame would grow the bar every time it was
        -- undocked.
        --
        -- Both measurements, because either one of them can have been
        -- the dock's to set. Keeping only the width is why a bar that
        -- had been stretched down the side of an action bar snapped back
        -- to a thin line the moment it came off.
        local width, height = frame:GetFillSize()
        if width and width > 0 then def.width = math.floor(width + 0.5) end
        if height and height > 0 then def.height = math.floor(height + 0.5) end
    end

    -- A bar as tall as a two-row action bar is eighty pixels, so the old
    -- ceiling of forty-eight cut one in half. The cap is there to stop a
    -- typo making a bar the size of the screen, which a sane number
    -- still does.
    -- Told before the size, so the size lands square. A floating square
    -- bar takes its height as its side; a docked one takes whichever side
    -- the dock hands it, further down.
    frame:SetSquare(def.square)
    local height = math.max(1, math.min(400, def.height or 24))
    local width  = def.square and height or math.max(1, math.min(1200, def.width or 240))
    frame:SetBarSize(width, height)
    frame:SetTextMode(def.textMode or "always")
    -- How the writing looks, in one call: the bar owns the drawing and
    -- the layout owns the choices.
    frame:SetTextStyle({
        size    = def.textSize,
        outline = def.textOutline,
        shadow  = def.textShadow,
        color   = def.textColor,
        align   = def.textAlign,
    })
    -- A portrait or a blank bar keeps the chrome and loses the color.
    frame:SetFillShown(not NO_FILL[def.kind])
    ApplyBarMouse(bar)
    frame:SetTicks(def.ticks or 0)
    frame:SetFillDirection(def.fillFrom or "LEFT")

    -- Full width is one bar to a line; half or its own width lets two
    -- sit side by side, which is how a health bar on the left and a
    -- power bar on the right end up on the same action bar.
    local dock  = def.dock or { host = "float" }
    local takes = def.takes or "full"
    -- The dock reads its own settings out of the layout and hands back a
    -- ticket, so that what an old profile means and when this bar was
    -- docked are each answered in one place rather than per module.
    local countsHeight, countsWidth, seq = BazUI.Dock:StackSettings(def)
    BazUI.Dock:AttachTo(frame, dock.host, {
        edge    = dock.edge or "BOTTOM",
        mode    = (takes == "full") and "stretch" or "align",
        -- Whether this bar counts toward the size of the stack it is in,
        -- for anything docked to that stack on the other axis. Height and
        -- width answered separately: a casting bar can span the width of
        -- the stack it sits on and add nothing to its height.
        countsHeight = countsHeight,
        countsWidth  = countsWidth,
        -- And when it joined, so that whatever was docked before it keeps
        -- the size it was given then.
        seq          = seq,
        -- A health or power bar appears and vanishes with its unit, by the
        -- unit watch in the secure environment. Docked, the dock was also
        -- setting it shown on every layout pass - so a target bar docked
        -- to an action bar was forced visible with no target, and the
        -- watch could not get it back.
        shown   = UnitWatched(def) and "own" or nil,
        align   = def.align or "LEFT",
        share   = (takes == "half") and 2 or nil,
        gutter  = def.gutter,
        order   = def.id,
        gap     = def.gap,
        offset  = dock.offset,
        -- A bar that is invisible most of the time still holds its
        -- place in the stack, or everything under it jumps the moment
        -- you go underwater.
        reserve = def.kind == "cast" or def.kind == "mirror",
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
    -- Everything is attached now, so lay it all out in the dock's own
    -- order. Attaching one bar at a time could only ever see the stacks
    -- as they stood at that moment, which is why a layout came back
    -- different from a reload than it had been left.
    BazUI.Dock:Relayout()
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
    -- Docked and floating do not offer the same settings, and the panel
    -- builds its list once. Without this, a bar dragged onto a host keeps
    -- the inspector it had while floating - no Takes, no Aligned, no Gap -
    -- while the Dock to dropdown, which asks for a rebuild itself, gives
    -- the full set. Two ways to do the same thing, disagreeing.
    self:RefreshEditSettings()
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
local EDGES = {
    BOTTOM = "Below", TOP = "Above", LEFT = "Left of", RIGHT = "Right of",
}

-- How much of its host a docked bar takes, and where it sits across it.
--
-- Three choices either way; only the words change. Below an action bar a
-- bar takes the host's width and sits left, center or right along it.
-- Beside one it takes the host's height and sits top, middle or bottom
-- down it - the same thing turned ninety degrees, and "Left" is not a
-- place to be on a line that runs up and down.
--
-- Relabeled rather than swapped in and out: nothing appears or
-- disappears as you move a bar from one edge to another, so the row you
-- were about to click is still there.
local TAKES = {
    V = { full = "The whole width",  half = "Half the width",  own = "Its own width"  },
    H = { full = "The whole height", half = "Half the height", own = "Its own height" },
}
local ALIGNS = {
    V = { LEFT = "Left", CENTER = "Center", RIGHT  = "Right"  },
    H = { TOP  = "Top",  MIDDLE = "Middle", BOTTOM = "Bottom" },
}

-- Which set this bar is using right now. A bar that floats has no edge
-- and never shows these rows, so the fallback only has to be harmless.
local function DockAxis(def)
    return BazUI.Dock:EdgeAxis(def.dock and def.dock.edge or "BOTTOM")
end
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
              -- Takes and Aligned are named after the edge, so their
              -- wording has just changed under the player.
              UnitBars:RefreshEditSettings()
          end },

        -- Offered on every bar and grayed where it is not a portrait: a
        -- square health bar is a shape nobody has asked for, and a switch
        -- you can see is grayed says more than one that is not there.
        { type = "checkbox", section = "Size", label = "3D portrait",
          desc = "The unit's model, framed head and shoulders the way the game's "
              .. "own portraits are, instead of the flat picture.",
          disabled = function() return def.kind ~= "portrait" end,
          get = function() return def.portrait3d == true end,
          set = function(value)
              def.portrait3d = value and true or nil
              Refresh()
              UnitBars:Update(bar)
          end },
        { type = "checkbox", section = "Size", label = "Keep square",
          desc = "Whichever side the dock sets, the other follows, so the "
              .. "portrait is never stretched. Floating, the height is its size.",
          disabled = function() return def.kind ~= "portrait" end,
          get = function() return def.square == true end,
          set = function(value)
              def.square = value and true or nil
              Refresh()
          end },
        { type = "slider", section = "Size", label = "Width",
          min = 60, max = 1200, step = 5,
          -- Follows the height while the bar is square, so there is
          -- nothing here to set.
          disabled = function() return def.square == true end,
          get = function() return def.width or 240 end,
          set = function(value) def.width = value Refresh() end },
        { type = "slider", section = "Size", label = "Height",
          -- The same ceiling Apply allows. It used to stop at forty-eight
          -- here while Apply allowed more, so a bar stretched down a
          -- two-row action bar could not be given that height by hand.
          min = 1, max = 400, step = 1,
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

        -- Left alone, the writing follows the bar: drag a bar taller and
        -- the text grows with it. Switched off, it is whatever you set -
        -- which is what two bars side by side want, since they are rarely
        -- the same height and the writing on them should still match.
        { type = "checkbox", section = "Text", label = "Size text to the bar",
          desc = "The text grows and shrinks with the bar. Off, it stays at the "
              .. "size below however tall the bar is.",
          get = function() return def.textSize == nil end,
          set = function(value)
              def.textSize = value and nil or (def.textSize or 12)
              Refresh()
          end },

        { type = "slider", section = "Text", label = "Text size",
          min = 6, max = 36, step = 1,
          disabled = function() return def.textSize == nil end,
          get = function() return def.textSize or bar.frame:TextSize() end,
          set = function(value) def.textSize = value Refresh() end },

        { type = "dropdown", section = "Text", label = "Edge",
          options = BazUI.BarTextOutlines,
          desc = "The outline drawn around each letter, which is what keeps "
              .. "writing readable over a bar that changes color under it.",
          get = function() return def.textOutline or "THIN" end,
          set = function(value) def.textOutline = value Refresh() end },

        { type = "checkbox", section = "Text", label = "Drop shadow",
          desc = "A soft shadow behind the text. Reads gentler than an outline, "
              .. "and the two can be worn together.",
          get = function() return def.textShadow == true end,
          set = function(value) def.textShadow = value or nil Refresh() end },

        { type = "color", section = "Text", label = "Text color",
          get = function() return def.textColor or { r = 1, g = 1, b = 1, a = 1 } end,
          set = function(value)
              def.textColor = value and { r = value.r, g = value.g,
                  b = value.b, a = value.a or 1 } or nil
              Refresh()
          end },

        { type = "dropdown", section = "Text", label = "Sits",
          options = BazUI.BarTextAligns,
          desc = "Which end of the bar the writing reads from.",
          get = function() return def.textAlign or "CENTER" end,
          set = function(value) def.textAlign = value Refresh() end },

        { type = "slider", section = "Text", label = "Tenth marks",
          min = 0, max = 20, step = 1,
          get = function() return def.ticks or 0 end,
          set = function(value) def.ticks = value Refresh() end },

        { type = "nudge", section = "Position" },
    }

    -- Appended rather than written inline with a condition: a nil in the
    -- middle of a table constructor ends the list for everything after
    -- it, which would have quietly cost every other bar its nudge.
    -- Always on the panel, grayed where it does not apply: a floating bar
    -- is in no stack at all. A switch you can see is grayed says more
    -- than one that is not there.
    --
    -- Two of them, because the two measurements are separate questions.
    -- Inserted in reverse, since each goes in ahead of the last.
    local function Floating()
        local d = def.dock
        return not (d and d.host and d.host ~= "float")
    end

    table.insert(widgets, 3, {
        type = "checkbox", section = "Docking", label = "Counts toward stack width",
        desc = "Whatever docks above or below this stack sizes itself to the stack's "
            .. "width. Off, this bar is left out of that measurement - so a mark "
            .. "beside a health bar does not make the power bar under it any wider.",
        disabled = Floating,
        get = function() return BazUI.Dock:CountsWidth(def) end,
        set = function(value)
            def.countsWidth = value and nil or false
            Refresh()
        end,
    })

    table.insert(widgets, 3, {
        type = "checkbox", section = "Docking", label = "Counts toward stack height",
        desc = "Whatever docks to the side of this stack sizes itself to the stack's "
            .. "height. Off, this bar is left out of that measurement - so a casting "
            .. "bar on top of an action bar does not make a health bar docked beside "
            .. "the action bar any taller.",
        disabled = Floating,
        get = function() return BazUI.Dock:CountsHeight(def) end,
        set = function(value)
            def.countsHeight = value and true or false
            Refresh()
        end,
    })

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
            options = ValuesArray(ALIGNS[DockAxis(def)]),
            -- Through the dock, so a bar aligned left and then moved to
            -- a side reads as aligned top rather than as nothing at all.
            get = function()
                return BazUI.Dock:AlignOnEdge(
                    def.dock and def.dock.edge, def.align)
            end,
            set = function(value) def.align = value Refresh() end,
        })
        table.insert(widgets, 3, {
            type = "dropdown", section = "Docking", label = "Takes",
            options = ValuesArray(TAKES[DockAxis(def)]),
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

    -- One switch per mark, from the registry rather than written out
    -- here - a new indicator then arrives on every bar's panel without
    -- this file hearing about it.
    --
    -- Offered on every bar and grayed out where it cannot apply, rather
    -- than appearing on one bar and not another: a switch you cannot find
    -- is worse than one you can see is not for this bar.
    for _, entry in ipairs(addon.Indicators and addon.Indicators.LIST or {}) do
        local key = entry.key
        table.insert(widgets, #widgets, {
            type = "checkbox", section = "Marks",
            label = entry.label,
            desc  = entry.desc,
            disabled = function()
                return not addon.Indicators:CanWear(def, key)
            end,
            get = function() return addon.Indicators:Wanted(def, key) end,
            set = function(value)
                addon.Indicators:SetWanted(def, key, value)
                -- The resting mark had its own field before the registry
                -- existed, and a profile written by an older build still
                -- holds it. Kept in step so neither reading wins twice.
                if key == "rest" then def.restIcon = value and true or false end
                Refresh()
                UnitBars:Update(bar)
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
        local secure = UnitWatched(def)
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

        -- And a mirror bar is invisible until you are drowning, which
        -- is not a state to have to get into to arrange your interface.
        elseif def.kind == "mirror" and not bar.frame._mirror then
            BazUI.Dock:SetShown(bar.frame, previewing)
            if previewing then
                bar.frame:SetAlpha(1)
                bar.frame:SetValue(0.62)
                bar.frame:SetFillColor(MIRROR_COLORS.BREATH)
                bar.frame:SetText("Breath  0:42")
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
        if UnitWatched(def) then
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

    -- The mirror timers are one player fact rather than a unit's, so
    -- they get their own watcher rather than a place in the unit list.
    if not watchers._mirror then
        watchers._mirror = CreateFrame("Frame")
        for _, event in ipairs({
            "MIRROR_TIMER_START", "MIRROR_TIMER_STOP", "MIRROR_TIMER_PAUSE",
            "PLAYER_ENTERING_WORLD",
        }) do
            pcall(watchers._mirror.RegisterEvent, watchers._mirror, event)
        end
        watchers._mirror:SetScript("OnEvent", function(_, event, ...)
            if event == "MIRROR_TIMER_START" then
                local name, value, maxvalue, _, paused, label = ...
                UnitBars:MirrorStart(name, value, maxvalue, paused, label)
            elseif event == "MIRROR_TIMER_STOP" then
                UnitBars:MirrorStop(...)
            elseif event == "MIRROR_TIMER_PAUSE" then
                local name, paused = ...
                UnitBars:MirrorPause(name, paused)
            else
                wipe(mirrorActive)
                UnitBars:MirrorSync()
            end
            UnitBars:ShowMirrors()
        end)
        UnitBars:MirrorSync()
        UnitBars:ShowMirrors()
    end

    if not watchers._player then
        watchers._player = CreateFrame("Frame")
        for _, event in ipairs({
            "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
            "UPDATE_FACTION", "PLAYER_ENTERING_WORLD",
            -- A 3D portrait holds nothing across a loading screen, and
            -- these two are the game saying portrait data has arrived or
            -- changed. Without them a model that came up empty stayed
            -- empty, because nothing ever told it to try again.
            "UNIT_PORTRAIT_UPDATE", "PORTRAITS_UPDATED",
            -- Resting changes the rested overlay without any experience
            -- being gained, and a capped or disabled bar has to notice
            -- that it is now one.
            "PLAYER_UPDATE_RESTING", "UNIT_LEVEL",
            "ENABLE_XP_GAIN", "DISABLE_XP_GAIN",
            -- Who is in the group is not a unit event: party2 becoming
            -- somebody else fires nothing about party2.
            "GROUP_ROSTER_UPDATE",
            -- And whatever the marks care about. Asked of the registry
            -- rather than listed here, so adding an indicator does not
            -- mean remembering to come back and add its event too.
            unpack(addon.Indicators and addon.Indicators:Events() or {}),
        }) do
            pcall(watchers._player.RegisterEvent, watchers._player, event)
        end
        local PORTRAITS_CHANGED = {
            UNIT_PORTRAIT_UPDATE  = true,
            PORTRAITS_UPDATED     = true,
            PLAYER_ENTERING_WORLD = true,
        }
        watchers._player:SetScript("OnEvent", function(_, event)
            if PORTRAITS_CHANGED[event] then UnitBars:InvalidatePortraits() end
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

local KIND_ORDER = { "health", "power", "cast", "mirror", "portrait", "blank", "xp", "rep" }
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
            if IsUnitKind(kind) or kind == "portrait" or kind == "blank" then
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
