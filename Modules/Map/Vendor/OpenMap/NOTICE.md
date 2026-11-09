# OpenMap rendering core in BazUI

Adapted from the installed OpenMap v0.8.2, https://github.com/openmap-world/openmap.
Copyright (c) 2026 OpenMap contributors. The complete MIT license is in LICENSE.txt.
The imported code and generated map metadata retain their MIT notices.

BazUI adapts Stitch.lua, WorldMap.lua, Close.lua and the essential Combat.lua
input-compatibility shim into an isolated namespace,
renames their map-frame levels, removes the OpenMap options and middle-click
shortcut, and supplies rendering settings through its own Map module.
Only continuous zoom, the stitched map and the terrain fade are enabled.
The BazUI settings page exposes maximum terrain opacity, the terrain fade's
starting zoom, maximum zoom, and hidden, dimmed or revealed unexplored areas.
The opacity limit also applies over surface cities; underground cities retain
their interior plans.
OpenMap's launcher, settings, window replacement, quest tools, POIs, travel
routes, navigation, drawing, social, news and reporting modules are not included.

The texture whitelist contains procedural masks and Blizzard-derived map layers
needed by the renderer. Those textures are not relicensed as MIT or GPL: see
../../Assets/Forever/UPSTREAM-NOTICE.md for their upstream provenance. No OpenMap
icon, contributed chart, hand-painted gap fill, contributed dungeon map or baked
MapZones atlas is included. The complete upstream texture notice describes the
upstream distribution as a whole; many of its listed assets are not shipped here.

Terrain data and assets are for WoW Forever. Retail keeps its default map.
