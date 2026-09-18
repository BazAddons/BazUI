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
-- or UI scale.
--
-- Anything tied to one player stays out: per-character bar payloads,
-- item pins, chat history, minimap button order from other addons.
--
-- Bags, Bars, MicroMenu and UnitFrames were arranged in game and
-- exported with /baz export, which is also what worked out their screen
-- anchors. Chat, Drawers and Auras are still written by hand: those
-- modules were switched off at the time, and an export only knows about
-- what was loaded. tools/bake-starter.py does
-- the same job straight from the saved variables, without the paste.
---------------------------------------------------------------------------

BazUI.StarterProfile = {
    UnitFrames = {
        scale = 0.8,
        showValues = "hover",
        classColor = true,
        barClicks = true,
        showLevel = false,
        rankGlow = true,
        rankIcon = true,
        rankWord = false,
        rangeFade = true,
        rangeAlpha = 0.5,
        unitTooltips = true,
        -- The game's own player frame and cast bar are hidden; these bars
        -- are what replaces them. The target frame is left alone.
        hidePlayerFrame = true,
        hidePlayerCastBar = true,
        modelLayer = "below", modelScale = 0.9, modelX = 3, modelY = 1, modelDistance = 0.9,
        position = { point = "CENTER", relPoint = "BOTTOM", x = 0, y = 190 },
        targetScale = 0.8,
        targetPortraitStyle = "flat",
        targetShowValues = "hover",
        targetPosition = { point = "CENTER", relPoint = "TOP", x = 0, y = -80 },

        -- Player health and power stacked under the player frame, the cast
        -- bar above it, and the same pair for the target. Docked rather than
        -- placed: the host carries its followers, so moving one moves the
        -- stack. The positions are where each lands when nothing docks it.
        --
        -- Health bars are 24 high and read as the main thing; power, cast
        -- and experience are 10, so a glance finds health first.
        statusBars = {
            {
                id = 1, kind = "health", unit = "player", name = "Player Health 1",
                width = 240, height = 24, ticks = 0,
                textFormat = "nameLevel", hoverFormat = "current/max", textMode = "always",
                dock = { host = "bar:2", edge = "BOTTOM" },
                position = { point = "CENTER", relPoint = "BOTTOM", x = -256, y = 220 },
            },
            {
                id = 2, kind = "power", unit = "player", name = "Player Power 1",
                width = 240, height = 10, ticks = 0,
                textFormat = "current", textMode = "always",
                dock = { host = "statusbar:1", edge = "BOTTOM" },
                position = { point = "CENTER", relPoint = "CENTER", x = 0, y = -160 },
            },
            {
                id = 3, kind = "cast", unit = "player", name = "Player Casting 1",
                width = 240, height = 10, ticks = 0,
                textFormat = "current", textMode = "always",
                dock = { host = "bar:2", edge = "TOP" },
                position = { point = "CENTER", relPoint = "CENTER", x = -96, y = 96 },
            },
            {
                id = 4, kind = "health", unit = "target", name = "Target Health 1",
                width = 240, height = 24, ticks = 0,
                textFormat = "namePercent", textMode = "always",
                dock = { host = "float", edge = "BOTTOM" },
                position = { point = "CENTER", relPoint = "TOP", x = -240, y = -362 },
            },
            {
                id = 5, kind = "power", unit = "target", name = "Target Power 1",
                width = 240, height = 10, ticks = 0,
                textFormat = "current", textMode = "always",
                dock = { host = "statusbar:4", edge = "BOTTOM" },
                position = { point = "CENTER", relPoint = "CENTER", x = 0, y = -160 },
            },
            -- Experience under the main action bar, centred and taking its
            -- full width: a docked bar with takes = "full" stretches to its
            -- host, so it lines up with the buttons whatever size the bar is.
            -- Blizzard's own is hidden by stockXP above, so this is the
            -- experience bar. It takes itself out of the dock at maximum
            -- level and anything under it closes the gap.
            {
                id = 6, kind = "xp", unit = "player", name = "XP Bar 1",
                width = 240, height = 10, ticks = 10,
                textFormat = "detailed", textMode = "hover",
                align = "CENTER", gap = 6,
                dock = { host = "bar:1", edge = "BOTTOM" },
                position = { point = "CENTER", relPoint = "CENTER", x = 0, y = -160 },
            },
        },
    },

    Auras = { iconSize = 40 },

    Bars = {
        -- A 14-slot main bar along the bottom and an 8-slot double row
        -- above it, which is what the player health and cast bars dock
        -- against. Blizzard's own bar is hidden: BazUI's bars are the action
        -- bars, and the empty slots show where abilities go.
        hideDefaultActionBar = true,
        hideDefaultActionBarArt = false,
        hideStanceBar = true,
        stockXP = false,
        stockRep = false,
        autoFill = true,
        autoPlaceNew = true,
        dragRequiresShift = false,
        fullRangeColor = true,
        showKeybindText = true,
        showMacroNames = true,
        showTooltips = true,
        tooltipAnchor = "default",
        bars = {
            {
                id = 1, cols = 14, rows = 1, scale = 0.7, alpha = 1, spacing = 3,
                endcaps = "off", endcapsAutoScale = false, endcapsScale = 1,
                mouseoverFade = false, mouseoverAlpha = 0.3,
                locked = false, rightClickSelfCast = false,
                buttons = {},
                pos = { point = "CENTER", relPoint = "BOTTOM", x = 0, y = 85.7 },
            },
            {
                id = 2, cols = 8, rows = 2, scale = 0.7, alpha = 1, spacing = 3,
                endcaps = "off", endcapsAutoScale = false, endcapsScale = 1,
                mouseoverFade = false, mouseoverAlpha = 0.3,
                locked = false, rightClickSelfCast = false,
                buttons = {},
                pos = { point = "CENTER", relPoint = "BOTTOM", x = 0, y = 451.4 },
            },
        },
    },

    Bags = {
        bagMode = "categories",
        cols = 10,
        maxRows = 15,
        hideBagBar = true,
        hideEmpty = true,
        emptyBackdrop = true,
        perBagSections = true,
        sellJunkButton = true,
        titleCount = true,
        goldOnly = false,
        showBindType = false,
        showItemLevel = false,
        rarityRims = "uncommon",
        strata = "DIALOG",
        bgTexture = "marble",
        bgAlpha = 1,
        bgDarken = 0.4,
        position = { point = "RIGHT", relPoint = "RIGHT", x = -285, y = -18 },
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
        enabled = true,
        buttonSize = 26,
        spacing = 4,
        orientation = "horizontal",
        hideBlizzard = true,
        mouseoverFade = true,
        fadeAlpha = 0,
        position = { point = "TOP", relPoint = "TOP", x = 0, y = -4 },
    },
}
