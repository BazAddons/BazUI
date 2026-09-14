# Unit Frames

Player and target each have independent Health and resource numbers options:
Always, On Hover, or Never. Hover covers the portrait and bars and works
during combat. Existing boolean show/hide settings retain their behavior.

The separate target frame uses `Assets/targetFrame.png`, with its portrait
hanging below the bars. It replaces the stock target frame at top center
and hides when no target is selected. Open `/bazframes` and select Target
for independent scale, flat/3D portrait, values and health-color options.
Use `/bazframes targetunlock`, `targetlock` and `targetreset` to position it.
Target health uses reaction colors, or optional class colors for players.
The stock target frame's attached elements are hidden with it; this module
currently supplies the portrait, name, health and resource bars.
`TargetLayout.lua` and the target-prefixed TGA textures follow the distinct
2166 x 704 target asset. Both original PNG files remain unchanged.

Centered player-frame replacement for BazUI on Classic Era.

Open `/bazplayer` or Settings > AddOns > BazUI > Player Frames.

- Choose a 3D animated portrait or a flat unit portrait.
- Scale the entire frame from 50% to 200%.
- Move it in BazUI Edit Mode, or use `/bazplayer unlock` and `/bazplayer lock`.
- `/bazplayer reset` restores the default centered position and scale.
- The lower bar follows the current power type (mana, rage, energy, etc.).
- Left-click targets the player; right-click opens the player menu.
- Disabling the module restores the stock player frame. Combat-sensitive changes wait until combat ends.

`Assets/playerFrame.png` is the original user-supplied artwork, unchanged.
`playerFrameRuntime.tga` is a padded power-of-two copy used in game. The
three mask textures follow the transparent openings in that specific asset.
`Layout.lua` maps the original 2089 x 678 canvas into a 640-pixel-wide frame
at 100% scale. Rebuild the runtime texture, masks and geometry if the source
artwork's dimensions or openings change.

The flat portrait uses the exact aperture mask. Mask textures fill their
entire power-of-two canvas rather than relying on UV cropping. The 3D
head uses a larger rectangular viewport beneath the outer metal ring,
with a closer camera and a dark round backing.

Validation covers Lua 5.1 loading and mocked game events, combat deferral,
profile changes, stock/pet restoration, settings and mask geometry. Actual
model framing, client texture loading and secure interactions still need
an in-game check. The stock pet frame is retained at its existing anchor.
