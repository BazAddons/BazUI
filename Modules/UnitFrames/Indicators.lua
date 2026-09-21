-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Unit Frames: indicators
--
-- The small marks a bar can wear: resting, in combat, group leader, the
-- raid target symbol, and so on. One registry rather than a function per
-- mark, because the blank bar exists precisely to carry whichever of them
-- you want, and a list you can add a line to is what makes that cheap.
--
-- The resting zZ was here first, written into UnitBars as its own code on
-- player health bars. It is one entry in this list now, and a health bar
-- asks for it through exactly the same path a blank bar does - so there
-- is one answer to "is this bar resting" rather than two that can drift.
--
-- Each entry says:
--
--   label      what it is called on the settings page
--   desc       what it means, for the tooltip
--   unit       the only unit it makes sense for, or nil for any
--   events     what changes it, so bars wearing it can be told
--   Wants      whether it should be on screen right now
--   Build      make the widget; called once per bar that wears it
--
-- Build returns a frame. Placing and sizing is the registry's job, not
-- the entry's: they sit in a row and they are all the same size, which is
-- the only arrangement that reads as a set rather than as clutter.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("UnitFrames")
if not addon then return end

local Indicators = {}
addon.Indicators = Indicators

---------------------------------------------------------------------------
-- The resting mark
--
-- Blizzard's own flipbook, which is why it moves: seven rows of six,
-- forty-two frames, a second and a half a loop, the shape the atlas is
-- drawn in. A client without the atlas gets no mark and no error.
---------------------------------------------------------------------------

local REST_ATLAS = "UI-HUD-UnitFrame-Player-Rest-Flipbook"
local REST_ROWS, REST_COLS, REST_FRAMES, REST_DURATION = 7, 6, 42, 1.5

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(name) ~= nil
end

local function BuildRest(parent)
    if not HasAtlas(REST_ATLAS) then return nil end

    local icon = CreateFrame("Frame", nil, parent)
    icon.texture = icon:CreateTexture(nil, "OVERLAY")
    icon.texture:SetAtlas(REST_ATLAS)
    icon.texture:SetAllPoints(icon)

    local group = icon:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local flip = group:CreateAnimation("FlipBook")
    flip:SetTarget(icon.texture)
    flip:SetDuration(REST_DURATION)
    flip:SetFlipBookRows(REST_ROWS)
    flip:SetFlipBookColumns(REST_COLS)
    flip:SetFlipBookFrames(REST_FRAMES)
    flip:SetFlipBookFrameWidth(0)
    flip:SetFlipBookFrameHeight(0)
    icon.anim = group

    -- Told apart from a plain texture when it is shown and hidden, so
    -- the animation is not left running behind a hidden frame.
    icon.OnShown = function(self, shown)
        if shown then self.anim:Play() else self.anim:Stop() end
    end
    return icon
end

-- A plain atlas mark. Most indicators are exactly this, so they are
-- built from one function rather than five copies of it.
local function AtlasBuilder(atlas)
    return function(parent)
        if not HasAtlas(atlas) then return nil end
        local icon = CreateFrame("Frame", nil, parent)
        icon.texture = icon:CreateTexture(nil, "OVERLAY")
        icon.texture:SetAtlas(atlas)
        icon.texture:SetAllPoints(icon)
        return icon
    end
end

-- Which mark is on a unit, as a plain number, or nothing when the answer
-- is one we may not read.
--
-- GetRaidTargetIndex is SecretReturns without a predicate - it can always
-- come back secret - and the index is no use unless it can be read: it
-- picks a corner out of a sheet of eight, which is arithmetic.
local function MarkIndex(unit)
    if not (unit and GetRaidTargetIndex) then return nil end
    return BazUI.Secret.Read(function()
        local index = GetRaidTargetIndex(unit)
        return (index and index > 0) and index or nil
    end, nil)
end

-- The raid target symbol is one sheet of eight, indexed rather than
-- named, so it sets its texture as the mark changes rather than once.
local function BuildRaidTarget(parent)
    local icon = CreateFrame("Frame", nil, parent)
    icon.texture = icon:CreateTexture(nil, "OVERLAY")
    icon.texture:SetAllPoints(icon)
    icon.Refresh = function(self, unit)
        -- Which mark it is has to be read to pick the right corner of the
        -- sheet, and GetRaidTargetIndex always may hand back a number we
        -- are not allowed to read. Nothing to draw then, so the mark stays
        -- off rather than showing the wrong symbol.
        local index = MarkIndex(unit)
        if not index then return end
        if _G.SetRaidTargetIconTexture then
            self.texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            _G.SetRaidTargetIconTexture(self.texture, index)
        end
    end
    return icon
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

Indicators.LIST = {
    {
        key   = "rest",
        label = "Resting",
        desc  = "The zZ, while you are in an inn or a city.",
        unit  = "player",
        events = { "PLAYER_UPDATE_RESTING" },
        Build = BuildRest,
        Wants = function(unit)
            return unit == "player" and IsResting and IsResting() and true or false
        end,
    },
    {
        key   = "combat",
        label = "In combat",
        desc  = "Shown while the unit is fighting.",
        events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_FLAGS" },
        Build = AtlasBuilder("UI-HUD-UnitFrame-Player-CombatIcon"),
        Wants = function(unit)
            return unit and UnitAffectingCombat and UnitAffectingCombat(unit) and true or false
        end,
    },
    {
        key   = "leader",
        label = "Group leader",
        desc  = "The crown, when this unit leads the group.",
        events = { "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" },
        Build = AtlasBuilder("UI-HUD-UnitFrame-Player-Group-LeaderIcon"),
        Wants = function(unit)
            return unit and UnitIsGroupLeader and UnitIsGroupLeader(unit) and true or false
        end,
    },
    {
        key   = "raidTarget",
        label = "Raid marker",
        desc  = "The skull, cross, square and the rest, when one is on this unit.",
        events = { "RAID_TARGET_UPDATE" },
        Build = BuildRaidTarget,
        Wants = function(unit)
            return MarkIndex(unit) ~= nil
        end,
    },
    {
        key   = "afk",
        label = "Away",
        desc  = "Shown while the unit is marked away or busy.",
        events = { "PLAYER_FLAGS_CHANGED" },
        Build = function(parent)
            local icon = CreateFrame("Frame", nil, parent)
            icon.text = BazUI.Skin.Theme.FontString(icon, "OVERLAY", "GameFontNormalSmall")
            icon.text:SetAllPoints(icon)
            icon.Refresh = function(self, unit)
                local away = unit and UnitIsAFK and UnitIsAFK(unit)
                self.text:SetText(away and "AFK" or "DND")
            end
            return icon
        end,
        Wants = function(unit)
            if not unit then return false end
            return ((UnitIsAFK and UnitIsAFK(unit)) or (UnitIsDND and UnitIsDND(unit)))
                and true or false
        end,
    },
}

Indicators.BY_KEY = {}
for _, entry in ipairs(Indicators.LIST) do
    Indicators.BY_KEY[entry.key] = entry
end

-- Every event any indicator cares about, so the module can register the
-- set once instead of each bar asking for its own.
function Indicators:Events()
    local seen, out = {}, {}
    for _, entry in ipairs(self.LIST) do
        for _, event in ipairs(entry.events or {}) do
            if not seen[event] then
                seen[event] = true
                out[#out + 1] = event
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Which of them a bar wears
---------------------------------------------------------------------------

-- Whether this kind of bar may carry this mark at all.
--
-- Resting is a fact about you, so a target's bar saying it would be
-- saying it about the wrong person - the entry names the only unit it
-- suits and this enforces it. Otherwise it is the blank bar's whole job
-- to carry these, and a health bar may carry them too.
function Indicators:CanWear(def, key)
    local entry = self.BY_KEY[key]
    if not (entry and def) then return false end
    if entry.unit and def.unit ~= entry.unit then return false end
    return def.kind == "blank" or def.kind == "health"
end

-- Whether this bar is asked to carry it: the bar's own answer once
-- somebody has given it one, and the module's until then.
--
-- Per bar because two health bars for yourself is a normal thing to
-- have, and the mark belongs on whichever of them you look at rather
-- than on both. Checked against nil rather than leaned on - `or setting`
-- would turn a bar you deliberately switched off back on.
function Indicators:Wanted(def, key)
    if not self:CanWear(def, key) then return false end
    local own = def.indicators and def.indicators[key]
    if own ~= nil then return own and true or false end

    -- Before this registry the resting mark had a field of its own, and
    -- profiles written by older builds still carry it. Honored rather
    -- than migrated: a profile is the player's, and quietly rewriting one
    -- to suit a refactor is how a setting goes missing.
    if key == "rest" and def.restIcon ~= nil then
        return def.restIcon and true or false
    end
    -- A blank bar with nothing on it is a blank bar, so its marks start
    -- off. A health bar keeps the resting zZ it has always had.
    if def.kind == "health" then
        return key == "rest" and addon:GetSetting("restIcon") ~= false
    end
    return false
end

function Indicators:SetWanted(def, key, value)
    if not def then return end
    def.indicators = def.indicators or {}
    def.indicators[key] = value and true or false
end

---------------------------------------------------------------------------
-- Putting them on a bar
---------------------------------------------------------------------------

-- Weak, so a bar taken down takes its marks with it.
local worn = setmetatable({}, { __mode = "k" })

local function Widget(bar, entry)
    local set = worn[bar.frame]
    if not set then
        set = {}
        worn[bar.frame] = set
    end
    if set[entry.key] == nil then
        -- false rather than nil for a mark this client cannot draw, so
        -- the attempt is made once rather than on every update.
        local icon = entry.Build(bar.frame) or false
        -- Hidden the moment it exists. A new frame is shown by default,
        -- so without this the first Show below sees nothing to change,
        -- returns early, and never runs OnShown - which is what starts
        -- the resting flipbook. The whole sheet then sits there
        -- un-animated, forty-two frames drawn on top of each other.
        if icon then icon:Hide() end
        set[entry.key] = icon
    end
    return set[entry.key] or nil
end

local function Show(icon, shown)
    if not icon then return end
    if icon:IsShown() == shown then return end
    icon:SetShown(shown)
    if icon.OnShown then icon:OnShown(shown) end
end

-- Lay out whichever marks this bar is wearing right now.
--
-- Sized to the fill rather than to the frame, so they sit inside the
-- colored part at any height, and never smaller than they can be read -
-- which is the rule the resting mark already followed.
--
-- Right to left from the end of the bar, in list order, so a mark coming
-- and going does not shuffle the ones beside it more than it has to.
function Indicators:Apply(bar, unit)
    if not (bar and bar.frame) then return end
    local def = bar.def

    local _, fill = bar.frame:GetFillSize()
    local size = math.max(12, math.floor((fill or 16) * 1.1 + 0.5))

    local x = -4
    for _, entry in ipairs(self.LIST) do
        local wanted = self:Wanted(def, entry.key)
            and unit and UnitExists(unit)
            and entry.Wants(unit, def) and true or false

        local icon = wanted and Widget(bar, entry) or (worn[bar.frame] or {})[entry.key]
        if icon then
            if wanted then
                icon:SetSize(size, size)
                icon:ClearAllPoints()
                icon:SetPoint("RIGHT", bar.frame, "RIGHT", x, 0)
                icon:SetFrameLevel(bar.frame:GetFrameLevel() + 3)
                if icon.Refresh then icon:Refresh(unit) end
                x = x - size - 2
            end
            Show(icon, wanted)
        end
    end
end
