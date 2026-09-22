-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Floating Text: reading the fight
--
-- One event, and Blizzard's own reading of it. CombatFeedback.lua is what
-- draws the little number on the portrait frame, and it takes the same
-- five values this does:
--
--   UNIT_COMBAT -> unitTarget, event, flagText, amount, schoolMask
--
-- Their vocabulary, kept rather than invented, so anything true of their
-- splat is true here:
--
--   WOUND      a hit. amount is the damage. When amount is 0 the flag
--              says what happened instead - ABSORB, BLOCK, RESIST, or
--              nothing at all, which is a miss.
--   HEAL       amount healed.
--   ENERGIZE   mana, rage, energy returned.
--   everything else - MISS, DODGE, PARRY, BLOCK, RESIST, IMMUNE, EVADE,
--   DEFLECT, REFLECT, INTERRUPT - is a word rather than a number.
--
-- CRITICAL, CRUSHING and GLANCING arrive as the FLAG on a WOUND, not as
-- events of their own, which is why crits are a size rather than a
-- category here.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("FloatingText")
if not addon then return end

local Events = {}
addon.Events = Events

local watcher

---------------------------------------------------------------------------
-- Color
--
-- By school when asked for, which needs the schoolMask the event already
-- carries. The masks are a bitfield and a spell can be two schools at
-- once (Frostfire), so the first one that matches wins rather than
-- pretending there is a blend.
--
-- The numbers are the game's own school colors, the ones the combat log
-- uses, so a fire number here is the fire everybody already knows.
---------------------------------------------------------------------------

-- A named palette rather than a colour picker.
--
-- The options framework has no colour control, and that turns out to be
-- the better answer here: these are drawn over grass and snow at speed,
-- and a free picker is mostly a way to end up with dark grey on a
-- hillside. Ten that read.
local PALETTE = {
    white  = { 1.00, 1.00, 1.00 },
    red    = { 1.00, 0.25, 0.25 },
    orange = { 1.00, 0.55, 0.10 },
    yellow = { 1.00, 0.90, 0.30 },
    green  = { 0.30, 1.00, 0.30 },
    cyan   = { 0.40, 1.00, 0.90 },
    blue   = { 0.41, 0.80, 0.94 },
    purple = { 0.75, 0.50, 1.00 },
    pink   = { 1.00, 0.55, 0.85 },
    grey   = { 0.70, 0.70, 0.70 },
}
addon.PALETTE = PALETTE

local WHITE = PALETTE.white

-- The colour a setting asks for, or a sensible one if it has never been
-- set. Looked up every time rather than cached: changing a colour on the
-- options page should show on the next hit, not the next reload.
local function Color(key, fallback)
    local name = addon:GetSetting(key)
    return PALETTE[name] or PALETTE[fallback] or WHITE
end

local SCHOOLS = {
    { mask = 0x02, color = { 1.00, 0.90, 0.50 } },  -- holy
    { mask = 0x04, color = { 1.00, 0.50, 0.00 } },  -- fire
    { mask = 0x08, color = { 0.30, 1.00, 0.30 } },  -- nature
    { mask = 0x10, color = { 0.50, 1.00, 1.00 } },  -- frost
    { mask = 0x20, color = { 0.50, 0.30, 0.70 } },  -- shadow
    { mask = 0x40, color = { 1.00, 0.50, 1.00 } },  -- arcane
}

-- School beats the category colour, when it is switched on and the
-- damage is actually of a school. Physical is deliberately not listed as
-- a school colour below - a white number for every melee swing is what
-- made everything look the same in the first place - so physical falls
-- through to whatever the direction's own colour is.
local function SchoolColor(schoolMask, fallback)
    if addon:GetSetting("schoolColors") == false then return fallback end
    if type(schoolMask) ~= "number" then return fallback end
    for _, entry in ipairs(SCHOOLS) do
        -- band rather than an operator, because Lua 5.1 has no bitwise
        -- ones and the game's bit library is what everything else here
        -- uses.
        local hit = bit and bit.band and bit.band(schoolMask, entry.mask) or 0
        if hit ~= 0 then return entry.color end
    end
    return fallback
end

---------------------------------------------------------------------------
-- Merging
--
-- A window per area per kind. Everything that lands inside it is added
-- up, and the total goes out when the window closes rather than when it
-- opens - so the number that appears is the whole of what happened, not
-- the first hit of it with the rest arriving later.
--
-- Crits are never merged. The reason to want a crit on screen is that it
-- was a crit, and folding it into a running total is exactly the
-- information being thrown away.
---------------------------------------------------------------------------

local pending = {}

local function Flush(slot)
    local item = pending[slot]
    if not item then return end
    pending[slot] = nil
    addon.Areas:Show(item.area, tostring(item.total), item.color,
        item.size, addon:GetSetting("outline"))
end

local function Merge(area, kind, amount, color, size)
    local slot = area .. ":" .. kind
    local item = pending[slot]
    if item then
        item.total = item.total + amount
        return
    end

    pending[slot] = { area = area, total = amount, color = color, size = size }
    local window = tonumber(addon:GetSetting("mergeWindow")) or 0.3
    C_Timer.After(window, function() Flush(slot) end)
end

---------------------------------------------------------------------------
-- One event
---------------------------------------------------------------------------

local WORDS = {
    MISS = MISS, DODGE = DODGE, PARRY = PARRY, BLOCK = BLOCK,
    RESIST = RESIST, IMMUNE = IMMUNE, EVADE = EVADE, DEFLECT = DEFLECT,
    REFLECT = REFLECT, INTERRUPT = INTERRUPT, ABSORB = ABSORB,
}

local function Handle(unitTarget, event, flagText, amount, schoolMask)
    if addon:GetSetting("enabled") ~= true then return end

    -- Which way it went. The event fires on whoever TOOK it, so anything
    -- that is not you is something you did - or at least something
    -- happening to somebody else, which is the same area either way.
    local area = (unitTarget == "player") and "incoming" or "outgoing"
    local mine = (area == "outgoing")

    local size = tonumber(addon:GetSetting("fontSize")) or 22
    local crit = (flagText == "CRITICAL" or flagText == "CRUSHING")
    local outline = addon:GetSetting("outline")

    if event == "WOUND" and (amount or 0) > 0 then
        if addon:GetSetting("showDamage") == false then return end

        -- Direction first, school second. Which way it went is the thing
        -- you are actually asking the screen, and it is the thing that
        -- was impossible to see when every number came out white.
        local base = mine and Color("colorOutDamage", "yellow")
            or Color("colorInDamage", "red")
        local color = SchoolColor(schoolMask, base)
        local text = tostring(amount)
        local shown = size

        if crit then
            shown = size * (tonumber(addon:GetSetting("critScale")) or 1.5)
            if addon:GetSetting("critPrefix") ~= false then
                text = "*" .. text .. "*"
            end
        elseif flagText == "GLANCING" then
            shown = size * 0.8
        end

        -- Merged only when it is an ordinary hit. See above.
        if addon:GetSetting("merge") == true and not crit then
            Merge(area, "damage" .. tostring(schoolMask or 0), amount, color, shown)
        else
            addon.Areas:Show(area, text, color, shown, outline)
        end
        return
    end

    if event == "HEAL" and (amount or 0) > 0 then
        if addon:GetSetting("showHeals") == false then return end
        local healColor = mine and Color("colorOutHeal", "cyan")
            or Color("colorInHeal", "green")
        local shown = crit and (size * (tonumber(addon:GetSetting("critScale")) or 1.5)) or size
        local text = tostring(amount)
        if crit and addon:GetSetting("critPrefix") ~= false then
            text = "*" .. text .. "*"
        end
        if addon:GetSetting("merge") == true and not crit then
            Merge(area, "heal", amount, healColor, shown)
        else
            addon.Areas:Show(area, text, healColor, shown, outline)
        end
        return
    end

    if event == "ENERGIZE" and (amount or 0) > 0 then
        if addon:GetSetting("showEnergize") ~= true then return end
        addon.Areas:Show(area, tostring(amount), Color("colorEnergize", "blue"),
            size, outline)
        return
    end

    -- Everything left is a word. A WOUND of zero is one of these too: the
    -- flag says which, and nothing at all means it simply missed.
    if addon:GetSetting("showMisses") == false then return end

    local word
    if event == "WOUND" then
        word = WORDS[flagText or ""] or WORDS.MISS
    else
        word = WORDS[event]
    end
    if not word then return end

    addon.Areas:Show(area, word, Color("colorMiss", "grey"), size * 0.8, outline)
end

---------------------------------------------------------------------------
-- Blizzard's own
--
-- A CVar rather than a frame, so this is asking the game to stop rather
-- than hiding something. Which also means it is the game's setting we are
-- writing: turning our module off puts it back.
---------------------------------------------------------------------------

-- The numbers over the mob's head are NOT the scrolling text.
--
-- Measured rather than assumed, and the assumption was wrong:
-- enableFloatingCombatText was already 0 while the game was still
-- drawing damage over everything. That switch governs the scrolling
-- text; each category of number over a unit has a variable of its own,
-- and they were all still 1.
--
-- classicStyleWorldText is 0 on this client, so these are the modern
-- ones. Listed rather than guessed at - /baz cvars floatingcombattext
-- is where this came from.
local WORLD_NUMBERS = {
    "floatingCombatTextCombatDamage_v2",
    "floatingCombatTextCombatDamageAllAutos_v2",
    "floatingCombatTextCombatHealing_v2",
    "floatingCombatTextCombatHealingAbsorbSelf_v2",
    "floatingCombatTextCombatHealingAbsorbTarget_v2",
    "floatingCombatTextCombatLogPeriodicSpells_v2",
    "floatingCombatTextPetMeleeDamage_v2",
    "floatingCombatTextPetSpellDamage_v2",
}

-- What each was set to before we touched it, so turning the module off
-- gives back what the player had rather than what we think is tidy.
local restore = {}

local function ApplyBlizzard()
    local on = addon:GetSetting("enabled") == true

    -- The scrolling text.
    local hideScroll = on and addon:GetSetting("hideBlizzard") ~= false
    pcall(SetCVar, "enableFloatingCombatText", hideScroll and "0" or "1")

    -- The numbers over the unit.
    local hideWorld = on and addon:GetSetting("hideBlizzardWorld") == true
    for _, name in ipairs(WORLD_NUMBERS) do
        if hideWorld then
            if restore[name] == nil then
                local ok, was = pcall(GetCVar, name)
                restore[name] = (ok and was) or "1"
            end
            pcall(SetCVar, name, "0")
        elseif restore[name] ~= nil then
            pcall(SetCVar, name, restore[name])
            restore[name] = nil
        end
    end
end

function Events:ApplySettings()
    ApplyBlizzard()
    if addon:GetSetting("enabled") ~= true and addon.Areas then
        addon.Areas:Clear()
    end
end

function Events:Initialize()
    if watcher then return end
    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", function(_, _, unitTarget, event, flagText, amount, schoolMask)
        -- Wrapped, because this runs several times a second in a fight
        -- and this client stops reporting errors after a hundred in a
        -- session. One bad number must not cost somebody else's error.
        pcall(Handle, unitTarget, event, flagText, amount, schoolMask)
    end)
    pcall(watcher.RegisterEvent, watcher, "UNIT_COMBAT")
end
