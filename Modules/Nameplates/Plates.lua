-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Nameplates: the plates
--
-- One of ours per plate the game is showing, hung on the game's own
-- frame so it moves, fades and stacks with it.
--
-- Two rules worth stating, because both are easy to get wrong:
--
-- Never keep a plate by its unit token. "nameplate3" is a slot, not a
-- unit: the game hands the same token to somebody else the moment the
-- first one dies. The frames are kept against the game's plate, which
-- does not change hands while it is in use, and the token is read fresh
-- every time it is needed.
--
-- Never destroy one. This client cannot, and the game recycles plates
-- constantly, so ours are recycled too - hidden, put back in a pool and
-- handed out again with a new unit on them.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("Nameplates")

local Plates = {}
addon.Plates = Plates

-- [Blizzard's plate] = ours, for every plate on screen.
local active = {}
local pool   = {}

-- Room above the bar for the name, which sits outside it.
local NAME_ROOM = 14

local function Setting(key) return addon:GetSetting(key) end

-- What this module is holding on to. See Core/Compat.lua.
BazUI:RegisterDependency({
    module = "Nameplates",
    label  = "C_NamePlate.GetNamePlateForUnit",
    why    = "Finding the frame the game handed a unit. Without it no plate is ever ours.",
    check  = function() return BazUI.Has.Member(C_NamePlate, "GetNamePlateForUnit") end,
})

---------------------------------------------------------------------------
-- Blizzard's plate
---------------------------------------------------------------------------

-- Hidden, not faded, and through the suite's own suppression rather than
-- a second copy of it here.
--
-- Alpha was the wrong tool twice over. This client guards the alpha aspect,
-- so an addon setting it on a frame it does not own is refused and nothing
-- happens - no error to notice, the game's plate simply stays visible on
-- top of ours. And the frame was never protected to begin with:
-- BaseNamePlateUnitFrameTemplate is a plain Button with disableMouse set,
-- no protected flag and no secure template behind it, so Hide works on it
-- at any time, fight or no fight.
--
-- BazUI.SuppressFrame does the rest: it hooks OnShow once and puts the
-- frame away again every time the game shows it, which is what a pooled
-- nameplate does on being handed to the next unit. It also refuses only
-- where the frame really is protected, so combat does not stop it here.
local suppressed = setmetatable({}, { __mode = "k" })

local function SuppressStock(plate)
    local frame = plate and plate.UnitFrame
    if not frame then return end
    suppressed[frame] = true
    BazUI.SuppressFrame(frame, function() return suppressed[frame] == true end)
end

local function RestoreStock(plate)
    local frame = plate and plate.UnitFrame
    if not frame then return end
    suppressed[frame] = nil
    -- Same call with the answer reversed: SuppressFrame only ever shows
    -- again what it took down itself.
    BazUI.SuppressFrame(frame, function() return false end)
end

---------------------------------------------------------------------------
-- One of ours
---------------------------------------------------------------------------

-- A plate's size is worked out from the border, and the bar inside it is
-- pinned to the plate's own edges - so a change of border has to re-lay
-- the plate, not just repaint the bar. One function rather than one per
-- plate: everything it needs is the plate it is handed.
local function RelayoutPlate(plate) Plates:Apply(plate) end

local function Build()
    local Theme = BazUI.Skin.Theme

    local plate = CreateFrame("Frame", nil, UIParent)
    plate:SetFrameStrata("BACKGROUND")

    -- The suite's border and the suite's fill, the same as every other
    -- bar. It used to wear the flat one-pixel treatment instead, because
    -- four pixels of chrome was most of a bar this size - but the border
    -- is drawn around the fill now rather than out of it, so a plate can
    -- follow the skin and keep the health bar it was given. No spark:
    -- twenty of them at once is a lot of sparkle.
    plate.health = BazUI.CreateStatusBar(nil, plate, {
        height   = 10,
        width    = 110,
        textMode = "never",
        spark    = false,
    })
    plate.health:SetPoint("BOTTOMLEFT")
    plate.health:SetPoint("BOTTOMRIGHT")

    plate.name = Theme.FontString(plate, "OVERLAY", "GameFontNormal")
    plate.name:SetPoint("BOTTOM", plate.health, "TOP", 0, 2)
    plate.name:SetJustifyH("CENTER")
    plate.name:SetWordWrap(false)

    -- On the bar rather than beside it: a plate is as wide as it is and
    -- the name has already taken the width above.
    -- Against the fill rather than the frame, so it stays inside the bar
    -- however thick the border round it is.
    plate.level = Theme.FontString(plate.health, "OVERLAY", "GameFontNormalSmall")
    plate.level:SetPoint("RIGHT", plate.health.fill, "RIGHT", -3, 0)

    -- The target's plate gets a border rather than a glow: a glow on
    -- something this size is a smudge, and every other selected thing in
    -- the suite is picked out with gold.
    plate.mark = plate:CreateTexture(nil, "BACKGROUND")
    plate.mark:SetPoint("TOPLEFT", plate.health, -2, 2)
    plate.mark:SetPoint("BOTTOMRIGHT", plate.health, 2, -2)
    plate.mark:Hide()

    Theme.TrackBorder(plate, RelayoutPlate)

    return plate
end

local function Acquire(host)
    local ours = table.remove(pool) or Build()
    ours:SetParent(host)
    ours:ClearAllPoints()
    ours:SetPoint("CENTER", host, "CENTER", 0, 0)
    ours:Show()
    return ours
end

local function Release(ours)
    ours:Hide()
    ours:SetParent(UIParent)
    ours.unit = nil
    pool[#pool + 1] = ours
end

---------------------------------------------------------------------------
-- What a plate says
---------------------------------------------------------------------------

-- Everything a plate is allowed to show, answered once for the unit
-- standing there. See Kinds.lua: a friendly NPC and a hostile one are
-- different kinds and can be told apart here.
local function Wants(unit)
    return {
        bar        = addon:UnitWants(unit, "showBar"),
        name       = addon:UnitWants(unit, "showName"),
        level      = addon:UnitWants(unit, "showLevel"),
        rank       = addon:UnitWants(unit, "showRank"),
        classColor = addon:UnitWants(unit, "classColor"),
    }
end

function Plates:UpdateHealth(ours)
    local unit = ours and ours.unit
    if not (unit and UnitExists(unit)) then return end
    local wants = Wants(unit)

    ours.health:SetShown(wants.bar)
    if not wants.bar then return end

    -- Value and maximum, handed straight to the bar rather than divided
    -- into a fraction here. Unit health is a secret value on clients that
    -- have them - one this code may pass along but never compare or
    -- divide - so the widget does the measuring. See Core\StatusBar.lua.
    ours.health:SetValue(UnitHealth(unit), UnitHealthMax(unit))
    ours.health:SetFillColor(BazUI.UnitColor(unit, {
        classColor = wants.classColor,
        reaction   = true,
    }))
end

function Plates:UpdateName(ours)
    local unit = ours and ours.unit
    if not (unit and UnitExists(unit)) then return end
    local wants = Wants(unit)

    ours.name:SetShown(wants.name)
    BazUI.Skin.Theme.SetText(ours.name, UnitName(unit) or "")
    ours.name:SetTextColor(unpack(BazUI.UnitColor(unit, {
        classColor = wants.classColor,
        reaction   = true,
    })))

    -- The level and the rank are one field, written the same way the
    -- unit bars write them - a plate and a target bar looking at the
    -- same mob should not disagree about what it is.
    local text = BazUI.UnitLevelText(unit, {
        level = wants.level,
        rank  = wants.rank,
    })
    ours.level:SetShown(text and true or false)
    if text then
        ours.level:SetText(text)
        ours.level:SetTextColor(unpack(BazUI.Skin.Theme.colors.text))
    end
end

function Plates:UpdateTarget(ours)
    local unit = ours and ours.unit
    -- The mark is drawn around the health bar, so a kind showing only a
    -- name has nothing to put it around. Its name still takes the target
    -- color from the theme, which is what marks it there.
    local wanted = Setting("targetMark") ~= false
        and unit and BazUI.Secret.IsUnit(unit, "target")
        and addon:UnitWants(unit, "showBar")
    ours.mark:SetShown(wanted and true or false)
end

-- Whose plate shows: ours, the game's, or neither.
--
-- Three answers rather than two, and the order matters.
--
--   A kind switched off gets nothing. The game's plate stays suppressed
--   and ours stays hidden, so the unit is silent whichever of the two
--   would otherwise have drawn it.
--
--   A friendly unit with "Replace friendly plates" off gets the game's
--   back, which is what that switch has always meant.
--
--   Everything else gets ours.
--
-- The host is read off the plate rather than looked up, because
-- C_NamePlate.GetNamePlateForUnit raises on some unit tokens - see Find,
-- below - and the parent is the same frame the game handed us.
function Plates:Decide(ours)
    local unit = ours and ours.unit
    local host = ours and ours:GetParent()
    if not (unit and host) then return end

    if not addon:UnitWants(unit, "showPlate") then
        SuppressStock(host)
        ours:Hide()
        return
    end

    local friendly = UnitReaction and (UnitReaction("player", unit) or 0) > 4
    if friendly and Setting("showFriendly") == false then
        RestoreStock(host)
        ours:Hide()
        return
    end

    SuppressStock(host)
    ours:Show()
end

-- Size and every reading, for one plate.
function Plates:Apply(ours)
    local width  = tonumber(Setting("width"))  or 110
    local height = tonumber(Setting("height")) or 10

    local unit = ours.unit
    local hasBar = unit and addon:UnitWants(unit, "showBar") or false

    -- Whether this unit gets a plate from us at all, which its kind can
    -- refuse. Decided here rather than when the plate arrived, because a
    -- unit changes kind in ordinary play: somebody else tags the mob you
    -- were fighting, a player flags for PvP. The plate has to answer
    -- again each time it is painted or it keeps the old unit's answer.
    self:Decide(ours)

    -- The width and height are the health bar's, the way every other bar
    -- in the suite reads them: what is set is the fill, and the border is
    -- added around it. The plate is sized to hold that, plus room above
    -- for the name.
    --
    -- A kind with its bar switched off is a name and nothing else, so the
    -- plate shrinks to the name rather than leaving a bar-shaped hole
    -- where the bar would have been. The name and the level move down
    -- onto the plate itself, since there is no longer a bar for them to
    -- sit above and inside.
    local chrome = ours.health:GetInset() * 2
    if hasBar then
        ours:SetSize(width + chrome, height + chrome + NAME_ROOM)
        ours.health:SetBarSize(width, height)
        ours.name:ClearAllPoints()
        ours.name:SetPoint("BOTTOM", ours.health, "TOP", 0, 2)
        ours.level:ClearAllPoints()
        ours.level:SetPoint("RIGHT", ours.health.fill, "RIGHT", -3, 0)
    else
        ours:SetSize(width + chrome, NAME_ROOM)
        ours.name:ClearAllPoints()
        ours.name:SetPoint("CENTER")
        -- Beside the name rather than inside a bar that is not there.
        ours.level:ClearAllPoints()
        ours.level:SetPoint("LEFT", ours.name, "RIGHT", 3, 0)
    end

    -- Painted on every apply rather than once when the plate was built,
    -- so a change of palette reaches plates already pooled.
    ours.mark:SetColorTexture(unpack(BazUI.Skin.Theme.colors.gold))
    ours.name:SetFont(BazUI.Skin.Theme.FontFile(),
        tonumber(Setting("nameSize")) or 9, "OUTLINE")
    ours.level:SetFont(BazUI.Skin.Theme.FontFile(),
        math.max(7, (tonumber(Setting("nameSize")) or 9) - 1), "OUTLINE")

    self:UpdateHealth(ours)
    self:UpdateName(ours)
    self:UpdateTarget(ours)
end

function Plates:ApplyAll()
    for _, ours in pairs(active) do self:Apply(ours) end
end

-- Whoever is carrying this unit right now, or nobody.
--
-- Answered from our own map rather than by asking the game. The unit
-- events this feeds - UNIT_HEALTH and its neighbours - fire for every
-- token the client has an opinion about, including "targettarget" and the
-- other compound ones, and C_NamePlate.GetNamePlateForUnit raises on
-- those rather than returning nothing:
--
--   Target-of-target unit tokens are not allowed for this call
--
-- Filtering by token name would mean keeping a list of what is allowed and
-- being wrong the moment the client adds one. We already know which unit
-- is on which plate, because the game told us when it added it, so look it
-- up here and let anything we were never told about miss.
local byUnit = {}

local function Find(unit)
    return unit and byUnit[unit] or nil
end

---------------------------------------------------------------------------
-- Coming and going
---------------------------------------------------------------------------

function Plates:Added(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local host = C_NamePlate.GetNamePlateForUnit(unit)
    if not host then return end

    SuppressStock(host)

    local ours = active[host] or Acquire(host)
    active[host] = ours
    -- A plate frame gets reused for whoever stands there next, so let go
    -- of the token it was carrying before claiming the new one.
    if ours.unit and ours.unit ~= unit and byUnit[ours.unit] == ours then
        byUnit[ours.unit] = nil
    end
    ours.unit = unit
    byUnit[unit] = ours

    -- Whose plate shows is worked out in one place, and Apply asks it.
    self:Apply(ours)
end

function Plates:Removed(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local host = C_NamePlate.GetNamePlateForUnit(unit)
    if not host then return end

    local ours = active[host]
    if not ours then return end
    active[host] = nil
    if byUnit[unit] == ours then byUnit[unit] = nil end
    if ours.unit and byUnit[ours.unit] == ours then byUnit[ours.unit] = nil end
    Release(ours)
end

function Plates:Initialize()
    addon:On("NAME_PLATE_UNIT_ADDED",   function(_, unit) self:Added(unit) end)
    addon:On("NAME_PLATE_UNIT_REMOVED", function(_, unit) self:Removed(unit) end)

    addon:On("UNIT_HEALTH", function(_, unit)
        local ours = Find(unit)
        if ours then self:UpdateHealth(ours) end
    end)
    addon:On("UNIT_MAXHEALTH", function(_, unit)
        local ours = Find(unit)
        if ours then self:UpdateHealth(ours) end
    end)
    addon:On("UNIT_NAME_UPDATE", function(_, unit)
        local ours = Find(unit)
        if ours then self:UpdateName(ours) end
    end)
    -- A unit that changes its mind about you changes color, and the
    -- level only arrives once the game has looked the unit up.
    -- Both of these can move a unit from one kind to another - a player
    -- flagging for PvP, a mob being tagged by somebody else - and a kind
    -- decides whether there is a plate at all, so the whole plate is
    -- re-applied rather than just repainted.
    addon:On("UNIT_FACTION", function(_, unit)
        local ours = Find(unit)
        if ours then self:Apply(ours) end
    end)
    addon:On("UNIT_FLAGS", function(_, unit)
        local ours = Find(unit)
        if ours then self:Apply(ours) end
    end)

    addon:On("PLAYER_TARGET_CHANGED", function()
        for _, ours in pairs(active) do self:UpdateTarget(ours) end
    end)
end
