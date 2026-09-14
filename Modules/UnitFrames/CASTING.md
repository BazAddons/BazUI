# Portrait casting

Player Frames > Portrait Casting controls the liquid overlay. Enabled by
default: 42% base opacity, 75% swirl intensity, gold, and spell text.
The Preview button runs a five-second cast when the player is not casting.
Casting fills upward; channels drain downward. Completion fades over 0.45s,
interruptions tint red, and cancelled casts fade quietly. Instant spells do
not show an overlay. Spell text temporarily replaces the character name.

Casting.lua owns a dedicated event receiver so it does not replace the
player frame's world-entry/death handlers in BazUI's per-module registry.
Animation runs at up to 30 updates per second only while visible/active.
Stock cast bars retain their events beneath a hidden parent and are restored
when portrait casting or the player frame is disabled. Reparenting happens
only through the player frame's combat-deferred settings application.

The effect is anchored to Layout.portrait (the artwork opening), rather than
to the adjustable model viewport. Its frame level is player +7: above both
supported model positions, below the secure click regions. Two masks
intersect the circular opening with a rising ripple; the overlay never needs
to cover the metal outside that opening. Portrait placement is unchanged.

Skin/Assets/castSwirl.tga, castLiquidMask.tga, and castCrest.tga are 256x256
32-bit RGBA mathematical textures, referenced through BazUI.Skin. New texture
files require a full game restart on initial installation. Final rendering
with the actual 3D model must be checked in game.

Validated in Lua 5.1 with the real player and settings code: casts, channels,
delay updates, stale cast IDs, interruptions, completion, previews, masks,
text restoration, combat-deferred toggles, and Blizzard bar restoration.

Motion refinement: contrasting counter-rotating currents, animated surface wavelength,
phase, bobbing and crest shimmer. Untouched original opacity/swirl defaults upgrade
once; custom values are preserved. No new textures are needed for this refinement.
