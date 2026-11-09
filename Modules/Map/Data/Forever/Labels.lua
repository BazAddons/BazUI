-- SPDX-License-Identifier: MIT
-- Adapted from OpenMap v0.8.2, Copyright (c) 2026 OpenMap contributors.
-- See Modules/Map/Vendor/OpenMap/LICENSE.txt and NOTICE.md.
-- The continents' and seas' names, lettered live where Blizzard's map art had them (the
-- art itself is hand-cleaned: art/edits/). Measured from that art. One of each,
-- fixed on the world, so a name stays put as you zoom: the continents' as the world map
-- sets them, the seas' as the continent maps do (both continent maps name the Great Sea
-- between them: Eastern Kingdoms' only, the nearer the middle).
--
--   map    the map whose art the lines are measured on (its pixels, 1002 x 668)
--   name   the client's own name for it: a map's (C_Map.GetMapInfo) or an area's
--          (C_Map.GetAreaInfo, AreaTable); `text` if the client has none
--   fade   land: from the world's zoom until the zones come in; sea: the same, staying a
--          little longer (Stitch.lua)
--   ink, glow  the lettering's colour and its halo's, from the art { r, g, b } (0-255);
--          glowA the halo's strength
--   lines  one per word, as the art sets them: { left, right, baseline, cap height }
--          (the capitals' height: under the art's blur, about a pixel less than its ink),
--          and `true` fifth for a line set all in small capitals (the art's "THE")

local ns = BazUI.MapRuntime

local LAND_INK, LAND_GLOW = { 78, 44, 12 }, { 243, 189, 81 }
local SEA_INK, SEA_GLOW = { 66, 60, 44 }, { 168, 172, 152 }

ns.MapLabels = {
	{ map = 947, name = { map = 1414, text = "Kalimdor" }, fade = "land", ink = LAND_INK, glow = LAND_GLOW, glowA = 0.7,
		lines = { { 112, 332, 330, 20 } } },
	{ map = 947, name = { map = 1415, text = "Eastern Kingdoms" }, fade = "land", ink = LAND_INK, glow = LAND_GLOW, glowA = 0.7,
		lines = { { 660, 800, 387, 14 }, { 641, 816, 411.5, 14.5 } } },

	{ map = 1414, name = { area = 457, text = "The Veiled Sea" }, fade = "sea", ink = SEA_INK, glow = SEA_GLOW, glowA = 0.35,
		lines = { { 251, 287, 161, 11.5, true }, { 225, 314, 185, 17 }, { 246, 293, 209, 17 } } },

	{ map = 1415, name = { area = 214, text = "The Great Sea" }, fade = "sea", ink = SEA_INK, glow = SEA_GLOW, glowA = 0.35,
		lines = { { 229, 271, 279, 13, true }, { 209, 293, 303, 17 }, { 227, 274, 327, 17 } } },
	{ map = 1415, name = { area = 308, text = "The Forbidding Sea" }, fade = "sea", ink = SEA_INK, glow = SEA_GLOW, glowA = 0.35,
		lines = { { 730, 770, 243, 12.5, true }, { 677, 822, 269, 17 }, { 728, 771, 290, 17 } } },
}
