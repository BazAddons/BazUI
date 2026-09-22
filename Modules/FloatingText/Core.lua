-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Floating Text
--
-- The numbers that rise off a fight: what you hit for, what hit you, what
-- you healed, and the misses and dodges in between.
--
-- Where the numbers come from, and why that is worth saying: on this
-- client the combat log is closed to addons. C_CombatLogSecure is
-- Environment = "SecureOnly", COMBAT_LOG_EVENT_UNFILTERED carries
-- HasRestrictions, and C_CombatText.GetCurrentEventInfo is declared
-- SecretReturns - which is fatal on its own, because a secret number
-- cannot be put into a font string. Text is a secret aspect and only the
-- engine may write one.
--
-- UNIT_COMBAT is open. No restriction markers, `amount` really is a plain
-- number, and it was measured in game rather than taken from the
-- documentation: compared, formatted with %d and drawn, while in combat -
-- the same state in which every aura on the same client is refused. It
-- also fires for nameplate units, not only target and player, so what
-- happens to everything around you is reachable.
--
--   UNIT_COMBAT -> unitTarget, event, flagText, amount, schoolMask
--
-- The vocabulary is Blizzard's own, from CombatFeedback.lua: WOUND for a
-- hit, HEAL, ENERGIZE, and MISS / DODGE / PARRY / BLOCK / RESIST / ABSORB
-- / IMMUNE / EVADE / DEFLECT / REFLECT / INTERRUPT for the rest, with
-- CRITICAL, CRUSHING and GLANCING arriving as flags rather than events.
-- We read the same fields their portrait splat does.
--
-- The event fires on the unit TAKING the damage, which is what splits
-- incoming from outgoing: "player" is something happening to you, any
-- other token is something happening to somebody else, which in practice
-- means you did it.
---------------------------------------------------------------------------

local addon
addon = BazUI:RegisterModule("FloatingText", {
    title = "Floating Text",
    icon = "Interface\\Icons\\Spell_Fire_FlameBolt",
    minimap = { label = "Floating Text", icon = "Interface\\Icons\\Spell_Fire_FlameBolt" },
    profiles = true,
    defaults = {
        -- Off until asked for. It draws over the middle of the screen and
        -- a module that starts doing that unannounced is a module people
        -- go looking for the switch to.
        enabled = false,

        -- Blizzard's own, parked when ours is on. Theirs is a CVar rather
        -- than a frame, so this is a setting we hand to the game, not
        -- something we suppress.
        hideBlizzard = true,

        -- How long a number lives, and how far it travels in that time.
        duration = 1.8,
        travel   = 140,

        -- The look. Size is the ordinary hit; a crit is multiplied.
        fontSize   = 22,
        outline    = "OUTLINE",
        critScale  = 1.5,
        critPrefix = true,

        -- What is worth showing. Damage and healing are the point of the
        -- thing; the rest is noise to some people and the whole reason
        -- others install one of these.
        showDamage   = true,
        showHeals    = true,
        showEnergize = false,
        showMisses   = true,

        -- One number instead of six.
        --
        -- A fight is mostly the same mob hitting you four times a second,
        -- and six numbers climbing the screen says nothing that one
        -- number does not. Off by default because it is a lie of a
        -- friendly kind - the total is true, the number of hits is gone -
        -- and that should be a choice.
        merge       = false,
        mergeWindow = 0.3,

        -- Which way it went, said in colour. This is the thing a screen
        -- full of white numbers cannot tell you, and it matters more
        -- than the school does.
        colorInDamage  = "red",
        colorOutDamage = "yellow",
        colorInHeal    = "green",
        colorOutHeal   = "cyan",
        colorEnergize  = "blue",
        colorMiss      = "grey",

        -- School beats the direction colour where a spell has one.
        -- Physical is not a school colour here on purpose: a white
        -- number for every melee swing is what made everything look the
        -- same, so physical keeps the direction's colour.
        schoolColors = true,

        -- How far apart two numbers landing at once are pushed.
        --
        -- Some scatter is needed or simultaneous hits draw exactly on
        -- top of each other; too much and they look like they are
        -- arriving from nowhere in particular, which was the first
        -- version's mistake.
        scatter = 30,

        -- Blizzard's own, in pieces. The scrolling text and the numbers
        -- over a mob's head are two different systems on this client -
        -- see Events.lua - and the experience gain is a third.
        hideBlizzardWorld = false,
        hideBlizzardXP    = false,
    },
    slash = { "/bazfct" },
    defaultHandler = function() BazUI:OpenOptionsPanel("FloatingText") end,
    onReady = function(self)
        self.Areas:Initialize()
        self.Events:Initialize()
        self:OnProfileChanged(function() self:ApplySettings() end)
        self:ApplySettings()
    end,
})

addon.MODULE_NAME = "FloatingText"

-- The two places text goes.
--
-- Named rather than numbered, because the name is what the event routing
-- asks for and what the options page shows. Two is the useful minimum:
-- what is happening to you and what you are doing. More areas are a later
-- feature and the shape here does not prevent them - Areas.lua builds one
-- frame per entry in this list.
addon.AREAS = {
    {
        key   = "incoming",
        label = "Incoming",
        desc  = "What is happening to you: damage you take, heals you receive.",
        -- Left of centre, which is where every addon of this kind has put
        -- it for twenty years. Worth keeping: it is where people look.
        x = -260, y = -40,
    },
    {
        key   = "outgoing",
        label = "Outgoing",
        desc  = "What you are doing: your damage, your healing.",
        x = 260, y = -40,
    },
}

function addon:ApplySettings()
    if self.Areas then self.Areas:ApplyAll() end
    if self.Events then self.Events:ApplySettings() end
end
