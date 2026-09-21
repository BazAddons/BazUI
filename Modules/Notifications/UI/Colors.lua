-- SPDX-License-Identifier: GPL-2.0-or-later
-- Notification colors, all drawn from the shared BazUI theme so the
-- bell, toasts and panel match the rest of the suite.
local addon = BazUI.Notifications
local T = BazUI.Skin.Theme.colors

addon.Colors = {
    -- Panel backdrop
    panelBg         = T.bg,
    panelBorder     = T.goldDim,

    -- Card colors
    cardBg          = T.bgRaised,
    cardHover       = T.bgHover,
    cardBorder      = T.edge,

    -- Text
    textPrimary     = T.text,
    textSecondary   = T.textSoft,
    textMuted       = T.textMuted,

    -- Accent (suite gold)
    accent          = T.gold,
    accentHover     = { 1.00, 0.90, 0.40, 1.0 },

    -- Badge: gold disc, dark numerals
    badge           = { 0.85, 0.65, 0.13, 1.0 },
    badgeText       = { 0.12, 0.08, 0.02, 1.0 },

    -- Priority, as how solid the band is rather than what color it is.
    -- The color says which module a card came from; this says how much
    -- it wants looking at, without spending a second color on it.
    priorityAlpha   = { high = 1.0, normal = 0.8, low = 0.45 },

    -- Dismiss button
    dismissNormal   = T.textMuted,
    dismissHover    = T.danger,

    -- Group header
    groupHeader     = T.gold,

    -- Divider
    divider         = T.divider,

    -- Toast
    toastBg         = T.bg,
    toastBorder     = T.goldDim,
}

---------------------------------------------------------------------------
-- One color per source
--
-- The band down the left of a card says where the notification came from,
-- so a panel with loot, quests and whispers in it groups by eye before it
-- is read. It pairs with the group header above, which names the same
-- module.
--
-- These are identity colors rather than skin colors, in the way class
-- colors are: a skin that repainted them would make quests and loot
-- indistinguishable, which is the one thing they exist to avoid. A source
-- can still bring its own by passing `color` to BNC:RegisterModule -
-- Zygor's is its own orange, off its icon.
---------------------------------------------------------------------------

addon.ModuleColors = {
    quests      = { 0.95, 0.78, 0.20, 1.0 },  -- the quest yellow
    loot        = { 0.45, 0.72, 0.95, 1.0 },  -- item blue
    xp          = { 0.64, 0.38, 0.86, 1.0 },  -- the experience bar's purple
    reputation  = { 0.40, 0.78, 0.45, 1.0 },  -- standing green
    mail        = { 0.85, 0.80, 0.62, 1.0 },  -- parchment
    social      = { 0.36, 0.84, 0.78, 1.0 },  -- whisper teal
    group       = { 0.95, 0.55, 0.25, 1.0 },  -- party orange
    instance    = { 0.82, 0.32, 0.32, 1.0 },  -- lockout red
    professions = { 0.76, 0.56, 0.34, 1.0 },  -- workbench tan
    auction     = { 0.78, 0.72, 0.30, 1.0 },  -- coin
    inventory   = { 0.58, 0.62, 0.72, 1.0 },  -- steel
    zones       = { 0.42, 0.68, 0.62, 1.0 },  -- map green
    system      = { 0.62, 0.60, 0.56, 1.0 },  -- the game talking
}

-- Anything that registered without one, and anything registered later by
-- somebody else.
addon.ModuleColorDefault = T.goldDim
