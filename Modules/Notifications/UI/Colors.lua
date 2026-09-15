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

    -- Priority accents
    priorityHigh    = T.warn,
    priorityLow     = { 0.50, 0.45, 0.35, 1.0 },

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
