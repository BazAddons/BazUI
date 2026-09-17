-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Skin
--
-- One place for the BazUI look. Every module draws its textures and brand
-- colors from here so the whole addon changes together. Assets live in
-- Skin\Assets. Almost nothing is shipped as a picture any more: borders,
-- rings and plates are drawn from colored textures, which cost nothing to
-- download and cannot go missing. What remains is art that could not be
-- drawn.
---------------------------------------------------------------------------

local ASSETS = "Interface\\AddOns\\BazUI\\Skin\\Assets\\"

BazUI.Skin = {
    ASSETS = ASSETS,

    -- The minimap's frame: the WoW Forever logo ring, which suits the
    -- brass the rest of the addon is built in and says where the UI comes
    -- from. The drawn border is right for a bar or a button and was never
    -- right for something this size.
    --
    -- Measured, not guessed, and measured again whenever the picture
    -- changes. The number wanted is where the brass turns solid - 756
    -- pixels across, of a 929 x 1088 canvas, centred in it to within a
    -- pixel - because that is where the map has to reach.
    --
    -- Not where the picture stops being transparent, which is a long way
    -- further in: the ring casts a shadow onto the map, and a shadow is
    -- only a shadow if there is map underneath it. Measuring to the
    -- middle of that shadow reads as a much thicker ring, sizes the map
    -- to the wrong circle and leaves the shadow falling on the
    -- background.
    --
    -- Nothing reads these off the file at run time, so a new picture
    -- needs them measured with it.
    MINIMAP_FRAME            = ASSETS .. "mapFrame.png",

    -- Zygor's mark, for the notifications forwarded from it. Shipped
    -- rather than borrowed from their addon at run time: a texture
    -- path into somebody else's folder breaks the day they rename a
    -- file, and it would be missing entirely for anyone without them.
    ZYGOR_ICON               = ASSETS .. "zygorIcon.png",

    -- What rank a unit is, as a glyph to sit in front of its name. Drawn
    -- inline in the bar's own text, which means the client scales them to
    -- the line height and nothing can tint them: whatever colour they
    -- carry is the colour they are. 51x51 as shipped.
    --
    -- Anything missing falls back to what the rank is made of, so the set
    -- still works with a file absent.
    -- How much of a bar's fill height a rank glyph takes. Measured
    -- against the bar rather than against the text in it, because the
    -- text stops growing at twelve pixels and a tall bar would otherwise
    -- carry a speck in a lot of empty height. A little under full, so it
    -- sits inside the bar instead of touching both edges of it.
    RANK_ICON_SCALE          = 0.85,

    RANK_ICON_RARE           = ASSETS .. "rareIcon.png",
    RANK_ICON_ELITE          = ASSETS .. "eliteIcon.png",
    RANK_ICON_RARE_ELITE     = ASSETS .. "eliteRareIcon.png",
    RANK_ICON_BOSS           = ASSETS .. "bossIcon.png",
    MINIMAP_FRAME_WIDTH      = 929 / 756,
    MINIMAP_FRAME_HEIGHT     = 1088 / 756,

    -- Minimap button ring. 128x128, ring centered; inner edge at 70%, the
    -- outer edge touches the texture edge.
    BUTTON_RING_INNER_RATIO  = 0.70,

    -- Blizzard's round portrait mask: clips icons to circles and, drawn as
    -- a plain texture, doubles as a solid disc.
    ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask",

    BUTTON_BACKDROP_COLOR = { 0.07, 0.07, 0.09, 1 },

    -- Brand colors (hex, for |cff.. escapes)
}

-- The fill every status bar in the suite is drawn with, as it stands: a
-- smooth built-in texture, tinted per bar, with no segmented Classic
-- artwork. Skin/Fills.lua keeps the list of the others and writes the
-- chosen one here, so this is the answer rather than the setting.
BazUI.Skin.XP_FILL = "Interface\\TargetingFrame\\UI-StatusBar"

-- Portrait casting: 256x256 RGBA procedural textures; circle + rising mask
-- intersect to confine the liquid. The mask's top 5% carries the ripple.

