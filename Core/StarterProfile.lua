-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Starter Profile
--
-- The layout a fresh install starts with. Core lays these values over a
-- module's coded defaults the first time that module's section is
-- created in a profile: on a brand-new install, when a new profile is
-- made, and when a module is added to an existing install. Existing
-- sections are never touched, so nobody's settings change on update.
--
-- Positions use screen anchors (BOTTOM, TOP, RIGHT ...), never absolute
-- pixels from a corner, so the layout lands the same at any resolution
-- or UI scale. Bars store their offsets in the bar's own scaled units,
-- which is how the Bars module reads them back.
--
-- Anything tied to one player stays out: per-character bar payloads,
-- item pins, chat history, minimap button order from other addons.
---------------------------------------------------------------------------

local function Bar(id, cols, scale, x, y)
    return {
        id = id, cols = cols, rows = 1, scale = scale, alpha = 1, spacing = 3,
        endcaps = "off", endcapsAutoScale = false, endcapsScale = 1,
        mouseoverFade = false, mouseoverAlpha = 0.3,
        locked = false, rightClickSelfCast = false,
        buttons = {},
        pos = { point = "CENTER", relPoint = "BOTTOM", x = x, y = y },
    }
end

BazUI.StarterProfile = {
    UnitFrames = {
        scale = 0.8,
        showValues = "hover",
        modelLayer = "below", modelScale = 0.94, modelX = 3, modelY = 1, modelDistance = 0.86,
        position = { point = "CENTER", relPoint = "BOTTOM", x = 0, y = 190 },
        targetScale = 0.75,
        targetPortraitStyle = "flat",
        targetShowValues = "hover",
        targetPosition = { point = "CENTER", relPoint = "TOP", x = 0, y = -80 },
    },

    Auras = { iconSize = 40 },

    Bars = {
        -- A 14-slot main bar centered along the bottom and a 6-slot bar on
        -- each side of the player frame. Blizzard's own bar is hidden:
        -- BazUI's bars are the action bars, and the empty slots show
        -- where abilities go.
        hideDefaultActionBar = true,
        bars = {
            Bar(1, 14, 0.70,    0,  64.3),
            Bar(2,  6, 0.65, -219, 246.2),
            Bar(3,  6, 0.65,  219, 246.2),
        },
    },

    Bags = {
        bagMode = "categories",
        cols = 10,
        hideBagBar = true,
        position = { point = "RIGHT", relPoint = "RIGHT", x = -95, y = -47 },
    },

    Chat = {
        docks = {
            dock = {
                width = 364, height = 127, locked = true,
                pos = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 12, y = 36 },
            },
        },
        -- Window 1 (General) shows its chrome only on hover; window 3
        -- (Trade) only appears in cities. Labels and channels come from
        -- the module's own defaults.
        windows = {
            [1] = { scrollbarMode = "onscroll", bgMode = "onhover", chromeFadeMode = "onhover",
                    tabsMode = "onhover", tabsAlpha = 0.5, bgAlpha = 0.5 },
            [3] = { autoShow = "city" },
        },
    },

    Drawers = {
        locked = true,
        widgetEnableStrict = true,
        widgetEnabled = { bazdrawer_minimap_infobar = false },
        widgetSettings = {
            bazdrawer_minimap        = { frameStyle = "bazui", hideDayNight = true, hideZoomButtons = true },
            bazdrawer_minimapbuttons = { buttonStyle = "bazui" },
        },
    },

    MicroMenu = {
        buttonSize = 25,
        spacing = 4,
        mouseoverFade = true,
        position = { point = "TOP", relPoint = "TOP", x = 0, y = -4 },
    },

}
