-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: can you stop that cast?
--
-- One answer, shared. The nameplate cast bar and the dockable target cast
-- bar both colour themselves by it, and two copies of this would be two
-- copies that drift - one of them learning about a class's interrupt and
-- the other not.
--
-- Three states, because there are three answers:
--
--   ready    you have an interrupt and it is off cooldown
--   waiting  you have one and it is not
--   none     you have no interrupt at all
--
-- The third one matters more than it looks. Folding it into "ready" puts
-- GREEN on every ordinary cast for a hunter - the colour that means stop
-- it now, shown to somebody who cannot - and green has to mean an action
-- is available or it means nothing at all.
--
-- The other half of the question, whether the cast can be interrupted, is
-- never asked here. It is secret on every unit but you and your pet, and
-- the way it is used is not to read it: a bar hands its OWN colour pair to
-- SetVertexColorFromBoolean and the engine picks within that pair. So this
-- file decides which pair, and never learns which colour was used.
---------------------------------------------------------------------------

BazUI = BazUI or {}

local Interrupt = {}
BazUI.Interrupt = Interrupt

---------------------------------------------------------------------------
-- Which spell is yours
--
-- From the spellbook rather than from the class alone: a warrior has
-- Pummel or Shield Bash depending on what is in their hands, and a druid
-- only has Feral Charge while in bear form. Asking what you know answers
-- both without a rule about either.
--
-- Written down here, which means it is wrong eventually - a class gains an
-- interrupt, or this misses one. That is what the override is for.
---------------------------------------------------------------------------

local SPELLS = {
    WARRIOR = { 6552, 72 },      -- Pummel, Shield Bash
    ROGUE   = { 1766 },          -- Kick
    MAGE    = { 2139 },          -- Counterspell
    SHAMAN  = { 8042 },          -- Earth Shock
    DRUID   = { 16979 },         -- Feral Charge
}

local cached, cachedFor

-- An override, set by whoever owns the setting. Passed in rather than read
-- from a module, so this file does not have to know which module holds the
-- options page for it.
function Interrupt.SetOverride(spellID)
    Interrupt.override = tonumber(spellID)
    cached, cachedFor = nil, nil
end

function Interrupt.Spell()
    local override = tonumber(Interrupt.override)
    if override and override > 0 then return override end

    local _, class = UnitClass("player")
    if cachedFor == class and cached ~= nil then
        return (cached ~= false) and cached or nil
    end

    cachedFor, cached = class, false
    for _, id in ipairs(SPELLS[class or ""] or {}) do
        local ok, known = pcall(IsSpellKnown, id)
        if ok and known then cached = id break end
    end
    return (cached ~= false) and cached or nil
end

-- Learning one changes the answer, and nothing else would tell us.
local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function() cached, cachedFor = nil, nil end)
for _, event in ipairs({ "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED",
                         "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end

---------------------------------------------------------------------------
-- What you can do right now
---------------------------------------------------------------------------

function Interrupt.State()
    local id = Interrupt.Spell()
    if not id then return "none" end

    local ok, info = pcall(function()
        return C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
    end)
    if not (ok and type(info) == "table") then return "ready" end

    local start = tonumber(info.startTime) or 0
    local duration = tonumber(info.duration) or 0
    if start <= 0 or duration <= 0 then return "ready" end
    -- The global cooldown does not count. It is a second and a half, and
    -- every cast in the game would flicker amber for it.
    if duration <= 1.6 then return "ready" end
    return ((start + duration) <= GetTime()) and "ready" or "waiting"
end

---------------------------------------------------------------------------
-- The two colours to hand a bar
--
-- `colors` is optional and lets a caller use its own: keys never, now,
-- wait and none, each { r, g, b }. Anything missing falls to the defaults
-- here, so a caller that has no opinion needs none.
---------------------------------------------------------------------------

local DEFAULTS = {
    never = { 0.85, 0.20, 0.20 },
    now   = { 0.25, 0.90, 0.35 },
    wait  = { 0.95, 0.70, 0.20 },
    none  = { 0.55, 0.65, 0.80 },
}

local function Pick(colors, key)
    local c = colors and colors[key]
    if type(c) == "table" and c[1] then
        return CreateColor(c[1], c[2] or 0, c[3] or 0, 1)
    end
    local d = DEFAULTS[key]
    return CreateColor(d[1], d[2], d[3], 1)
end

-- Returns the colour for an uninterruptible cast, and the colour for
-- everything else. Handed straight to SetVertexColorFromBoolean, in that
-- order: notInterruptible true takes the first.
function Interrupt.Pair(colors)
    local never = Pick(colors, "never")
    local state = Interrupt.State()
    if state == "ready" then return never, Pick(colors, "now") end
    if state == "waiting" then return never, Pick(colors, "wait") end
    return never, Pick(colors, "none")
end

-- Paint a bar's fill from a cast's interruptible flag, whatever we are
-- allowed to know about it.
--
-- The flag may be secret, in which case SetVertexColorFromBoolean does the
-- choosing; it may also be nil, which the client is entitled to do - the
-- field is declared nilable - and then there is nothing to choose between
-- and the ordinary colour is used. Asking whether a value is nil is a
-- question about presence and is always allowed; asking what it IS is not.
function Interrupt.PaintFill(fill, notInterruptible, colors)
    if not fill then return end
    local texture = fill.GetStatusBarTexture and fill:GetStatusBarTexture()
    if not texture then return end

    local never, other = Interrupt.Pair(colors)
    if notInterruptible == nil or not texture.SetVertexColorFromBoolean then
        texture:SetVertexColor(other:GetRGBA())
        return
    end
    texture:SetVertexColorFromBoolean(notInterruptible, never, other)
end
