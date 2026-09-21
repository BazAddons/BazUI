-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Nameplates
--
-- The bar over a unit's head, in the suite's own look: a health bar, the
-- name, the level, and a mark for the one you are targeting.
--
-- The game makes and moves the plates. It keeps a pool of them, hands one
-- to a unit when it comes into view and takes it back when it goes, and
-- positions every one of them in the world every frame - none of which an
-- addon can do, and all of which is the hard part. What this module does
-- is take over what a plate looks like: Blizzard's own is put away and
-- ours is hung on the same frame, so it inherits the position, the
-- fading, the clicking and the stacking for nothing.
--
-- "Nameplate" was already taken, by a panel with a name on it that the
-- zone text uses (Skin\Nameplate.lua). This module is the plural, and
-- they are unrelated.
---------------------------------------------------------------------------

local addon
addon = BazUI:RegisterModule("Nameplates", {
    title = "Nameplates",
    icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
    minimap = { label = "Nameplates", icon = "Interface\\Icons\\Ability_Hunter_SniperShot" },
    profiles = true,
    defaults = {
        width        = 110,
        height       = 10,
        nameSize     = 9,
        -- Surnames are a Forever thing and are part of somebody's
        -- name, so they show unless asked otherwise. Guild tags are a
        -- second line on every plate and stay off until wanted.
        showSurname  = true,
        showGuild    = false,

        -- Focus. All four start as "do nothing", so the module looks
        -- exactly as it did before these existed until somebody asks for
        -- something. A percentage rather than a fraction because that is
        -- what the slider shows and a setting should hold the number the
        -- player read.
        -- The one exception to "everything here starts off". Whether a
        -- mob is on you is the question threat exists to answer and is
        -- worth knowing before you are asked.
        aggroMark      = true,
        threatColor    = false,
        nonTargetAlpha = 100,
        targetScale    = 100,
        offsetY        = 0,
        combatOnly     = false,
        showLevel    = true,
        -- Rare and elite said in words beside the level, the same way
        -- the unit bars say it.
        showRank     = true,
        classColor   = true,
        -- The answer for a kind that has not been given its own. See
        -- Kinds.lua.
        showPlate    = true,
        showBar      = true,
        showName     = true,
        -- Every unit that gets a plate from the game gets one of ours.
        -- Which units those are is the game's own setting, not ours:
        -- there are checkboxes for it in Interface Options and CVars
        -- behind them, and a second set here that disagreed would only
        -- be a way to have plates you cannot explain.
        showFriendly = true,
        targetMark   = true,
    },
    slash = { "/bazplates" },
    defaultHandler = function() BazUI:OpenOptionsPanel("Nameplates") end,
    onReady = function(self)
        self.Plates:Initialize()
        self:OnProfileChanged(function() self:ApplySettings() end)
    end,
})

function addon:ApplySettings()
    if self.Plates then self.Plates:ApplyAll() end
end
