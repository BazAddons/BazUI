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
    -- Measured, not guessed. The hole the map sits in is 757.9 x 752.9
    -- pixels of a 929 x 1088 canvas, centred in it to within two pixels -
    -- under half a pixel at any size we draw it, so the art is simply
    -- centred on the map. The ratios are the picture's width and height
    -- against that hole, which is all anything needs to size it: give the
    -- frame a footprint and the hole in the middle follows.
    MINIMAP_FRAME            = ASSETS .. "mapFrame.png",
    MINIMAP_FRAME_WIDTH      = 929 / 755.4,
    MINIMAP_FRAME_HEIGHT     = 1088 / 755.4,

    -- The old minimap ring. Nothing frames anything with it any more, but
    -- the Codex's hero card uses a slice of it, faded almost to nothing,
    -- so the card is not a flat rectangle.
    FRAME_ART                = ASSETS .. "BazUI_Frame.png",

    -- Minimap button ring. 128x128, ring centered; inner edge at 70%, the
    -- outer edge touches the texture edge.
    BUTTON_RING_INNER_RATIO  = 0.70,

    -- Blizzard's round portrait mask: clips icons to circles and, drawn as
    -- a plain texture, doubles as a solid disc.
    ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask",

    BUTTON_BACKDROP_COLOR = { 0.07, 0.07, 0.09, 1 },

    -- Brand colors (hex, for |cff.. escapes)
}

-- Continuous XP fill: built-in texture, no segmented Classic artwork.
BazUI.Skin.XP_FILL = "Interface\\TargetingFrame\\UI-StatusBar"

-- Portrait casting: 256x256 RGBA procedural textures; circle + rising mask
-- intersect to confine the liquid. The mask's top 5% carries the ripple.

