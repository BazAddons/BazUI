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
--
-- Put away rather than hidden: its pieces are shown again by the game's
-- own code whenever it updates one, so a Hide of ours lasts until the
-- next health tick. Reapply transparency from our own visible frame's
-- OnUpdate because the game can reset the stock frame's alpha too.
---------------------------------------------------------------------------

local function SuppressStock(plate)
    local frame = plate and plate.UnitFrame
    if not frame then return end
    frame:SetAlpha(0)
end

local function RestoreStock(plate)
    local frame = plate and plate.UnitFrame
    if not frame then return end
    frame:SetAlpha(1)
end

-- Keep the handler on our frame. Hooking the stock frame's SetAlpha
-- previously caused errors in Blizzard's code on Forever.
local function KeepStockSuppressed(ours)
    SuppressStock(ours.host)
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
    plate:SetScript("OnUpdate", KeepStockSuppressed)

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
    ours.host = host
    ours:SetParent(host)
    ours:ClearAllPoints()
    ours:SetPoint("CENTER", host, "CENTER", 0, 0)
    ours:Show()
    return ours
end

local function Release(ours)
    ours:Hide()
    RestoreStock(ours.host)
    ours.host = nil
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

    -- Value and maximum, handed straight to the bar rather than divided
    -- into a fraction here. Unit health is a secret value on clients that
    -- have them - one this code may pass along but never compare or
    -- divide - so the widget does the measuring. See Core\StatusBar.lua.
    ours.health:SetValue(UnitHealth(unit), UnitHealthMax(unit))
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

    -- The level and the rank are one field, written the same way the
    -- unit bars write them - a plate and a target bar looking at the
    -- same mob should not disagree about what it is.
    local text = BazUI.UnitLevelText(unit, {
        level = Setting("showLevel") ~= false,
        rank  = Setting("showRank")  ~= false,
    })
    ours.level:SetShown(text and true or false)
    if text then
        ours.level:SetText(text)
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

    -- The width and height are the health bar's, the way every other bar
    -- in the suite reads them: what is set is the fill, and the border is
    -- added around it. The plate is sized to hold that, plus room above
    -- for the name.
    local chrome = ours.health:GetInset() * 2
    ours:SetSize(width + chrome, height + chrome + NAME_ROOM)
    ours.health:SetBarSize(width, height)

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

-- Unit events also carry aliases such as "targettarget", which this
-- client's nameplate lookup rejects. Only look up nameplate slots.
local function GetHost(unit)
    if type(unit) ~= "string" or not unit:match("^nameplate%d+$") then return nil end
    return C_NamePlate and C_NamePlate.GetNamePlateForUnit
        and C_NamePlate.GetNamePlateForUnit(unit)
end

-- Whoever is carrying this unit right now, or nobody.
local function Find(unit)
    local host = GetHost(unit)
    return host and active[host] or nil
end

---------------------------------------------------------------------------
-- Coming and going
---------------------------------------------------------------------------

function Plates:Added(unit)
    local host = GetHost(unit)
    if not host then return end

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
        SuppressStock(host)
        ours:Show()
    end

    self:Apply(ours)
end

function Plates:Removed(unit)
    local host = GetHost(unit)
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
