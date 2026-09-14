-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Skin
--
-- One place for the BazUI look. Every module draws its textures and brand
-- colours from here so the whole addon changes together. Assets live in
-- Skin\Assets as power-of-two PNGs (the client rejects other sizes).
---------------------------------------------------------------------------

local ASSETS = "Interface\\AddOns\\BazUI\\Skin\\Assets\\"

BazUI.Skin = {
    ASSETS = ASSETS,

    -- Minimap ring. 1024x1024, ring centred; inner edge at 75% of the
    -- texture, outer edge at 92%, N tag and studs reach ~94%.
    MINIMAP_RING             = ASSETS .. "BazUI_Frame.png",
    MINIMAP_RING_INNER_RATIO = 0.75,

    -- Minimap button ring. 128x128, ring centred; inner edge at 70%, the
    -- outer edge touches the texture edge.
    BUTTON_RING              = ASSETS .. "minimapButtonFrame.png",
    BUTTON_RING_INNER_RATIO  = 0.70,

    -- Blizzard's round portrait mask: clips icons to circles and, drawn as
    -- a plain texture, doubles as a solid disc.
    ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask",

    BUTTON_BACKDROP_COLOR = { 0.07, 0.07, 0.09, 1 },

    -- Brand colours (hex, for |cff.. escapes)
    BRAND = "3399ff",
    GOLD  = "ffd700",
}

-- Continuous XP fill: built-in texture, no segmented Classic artwork.
BazUI.Skin.XP_FILL = "Interface\\TargetingFrame\\UI-StatusBar"

-- Portrait casting: 256x256 RGBA procedural textures; circle + rising mask
-- intersect to confine the liquid. The mask's top 5% carries the ripple.
BazUI.Skin.CAST_SWIRL = "Interface\\AddOns\\BazUI\\Skin\\Assets\\castSwirl.tga"
BazUI.Skin.CAST_LIQUID_MASK = "Interface\\AddOns\\BazUI\\Skin\\Assets\\castLiquidMask.tga"
BazUI.Skin.CAST_CREST = "Interface\\AddOns\\BazUI\\Skin\\Assets\\castCrest.tga"

-- User's 2110x309 RGBA nameplate, padded without resampling to 4096x512.
BazUI.Skin.PLAYER_NAMEPLATE = "Interface\\AddOns\\BazUI\\Modules\\UnitFrames\\Assets\\namePlateRuntime.tga"
