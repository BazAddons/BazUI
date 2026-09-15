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

local function Setting(key) return addon:GetSetting(key) end

---------------------------------------------------------------------------
-- Blizzard's plate
--
-- Put away rather than hidden: its pieces are shown again by the game's
-- own code whenever it updates one, so a Hide of ours lasts until the
-- next health tick. Alpha is not protected, is not read back by anything
-- that matters, and cannot be argued with.
---------------------------------------------------------------------------

local function SuppressStock(plate)
    local frame = plate and plate.UnitFrame
    if not frame then return end
    frame:SetAlpha(0)
    if not frame._bazSuppressed then
        frame._bazSuppressed = true
        -- The pool hands these out again, so the hook is installed once
        -- and answers for every unit that frame ever carries.
        hooksecurefunc(frame, "SetAlpha", function(self, value)
            if self._bazSuppressed and value ~= 0 then self:SetAlpha(0) end
        end)
    end
end

local function RestoreStock(plate)
    local frame = plate and plate.UnitFrame
    if not frame then return end
    frame._bazSuppressed = nil
    frame:SetAlpha(1)
end

---------------------------------------------------------------------------
-- One of ours
---------------------------------------------------------------------------

local function Build()
    local Theme = BazUI.Skin.Theme

    local plate = CreateFrame("Frame", nil, UIParent)
    plate:SetFrameStrata("BACKGROUND")

    -- The panel style: one pixel of border. The screen style wears four,
    -- which is most of a bar this size.
    plate.health = BazUI.CreateStatusBar(nil, plate, {
        style    = "panel",
        height   = 10,
        width    = 110,
        textMode = "never",
    })
    plate.health:SetPoint("BOTTOMLEFT")
    plate.health:SetPoint("BOTTOMRIGHT")

    plate.name = Theme.FontString(plate, "OVERLAY", "GameFontNormal")
    plate.name:SetPoint("BOTTOM", plate.health, "TOP", 0, 2)
    plate.name:SetJustifyH("CENTER")
    plate.name:SetWordWrap(false)

    -- On the bar rather than beside it: a plate is as wide as it is and
    -- the name has already taken the width above.
    plate.level = Theme.FontString(plate.health, "OVERLAY", "GameFontNormalSmall")
    plate.level:SetPoint("RIGHT", plate.health, "RIGHT", -3, 0)

    -- The target's plate gets a border rather than a glow: a glow on
    -- something this size is a smudge, and every other selected thing in
    -- the suite is picked out with gold.
    plate.mark = plate:CreateTexture(nil, "BACKGROUND")
    plate.mark:SetPoint("TOPLEFT", plate.health, -2, 2)
    plate.mark:SetPoint("BOTTOMRIGHT", plate.health, 2, -2)
    plate.mark:SetColorTexture(unpack(Theme.colors.gold))
    plate.mark:Hide()

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

function Plates:UpdateHealth(ours)
    local unit = ours and ours.unit
    if not (unit and UnitExists(unit)) then return end

    -- The suite's bars take a fraction rather than a range: there is one
    -- SetValue and it means the same thing on every bar in the addon.
    local max = UnitHealthMax(unit) or 0
    local now = UnitHealth(unit) or 0
    ours.health:SetValue(max > 0 and (now / max) or 0)
    ours.health:SetFillColor(BazUI.UnitColor(unit, {
        classColor = Setting("classColor") ~= false,
        reaction   = true,
    }))
end

function Plates:UpdateName(ours)
    local unit = ours and ours.unit
    if not (unit and UnitExists(unit)) then return end

    ours.name:SetText(UnitName(unit) or "")
    ours.name:SetTextColor(unpack(BazUI.UnitColor(unit, {
        classColor = Setting("classColor") ~= false,
        reaction   = true,
    })))

    local level = UnitLevel(unit)
    local wanted = Setting("showLevel") ~= false and level and level > 0
    ours.level:SetShown(wanted and true or false)
    if wanted then
        -- A level the game will not name is a unit far enough above you
        -- that the number stopped being the point.
        ours.level:SetText(level == -1 and "??" or tostring(level))
        ours.level:SetTextColor(unpack(BazUI.Skin.Theme.colors.text))
    end
end

function Plates:UpdateTarget(ours)
    local unit = ours and ours.unit
    local wanted = Setting("targetMark") ~= false
        and unit and UnitIsUnit(unit, "target")
    ours.mark:SetShown(wanted and true or false)
end

-- Size and every reading, for one plate.
function Plates:Apply(ours)
    local width  = tonumber(Setting("width"))  or 110
    local height = tonumber(Setting("height")) or 10
    ours:SetSize(width, height + 14)
    ours.health:SetBarSize(width, height)
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
local function Find(unit)
    if not unit then return nil end
    local host = C_NamePlate and C_NamePlate.GetNamePlateForUnit
        and C_NamePlate.GetNamePlateForUnit(unit)
    return host and active[host] or nil
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
    ours.unit = unit

    -- A plate the game shows for a friendly unit can be left to the game
    -- by turning this off; it is still the game that decides whether
    -- there is a plate at all.
    local friendly = UnitReaction and (UnitReaction("player", unit) or 0) > 4
    if friendly and Setting("showFriendly") == false then
        RestoreStock(host)
        ours:Hide()
    else
        ours:Show()
    end

    self:Apply(ours)
end

function Plates:Removed(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local host = C_NamePlate.GetNamePlateForUnit(unit)
    if not host then return end

    local ours = active[host]
    if not ours then return end
    active[host] = nil
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
    -- A unit that changes its mind about you changes colour, and the
    -- level only arrives once the game has looked the unit up.
    addon:On("UNIT_FACTION", function(_, unit)
        local ours = Find(unit)
        if ours then self:UpdateHealth(ours) self:UpdateName(ours) end
    end)

    addon:On("PLAYER_TARGET_CHANGED", function()
        for _, ours in pairs(active) do self:UpdateTarget(ours) end
    end)
end
