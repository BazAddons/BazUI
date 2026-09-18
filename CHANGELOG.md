## 003

**Settings still do not stick on the World of Warcraft: Forever beta, and it
is not BazUI.** That client does not read an addon's settings back when you
log in, so everything starts from the built-in layout each launch. It is not
just this addon - it affects addons across the board, and the game's own
settings too. There is an open bug report for it and nothing an addon can do
in the meantime. When Blizzard fixes the client, BazUI will start remembering
again on its own, with no update needed.

Until then you get the built-in starting layout: action bars along the bottom,
health and power under them, target frames up top, buffs and debuffs sharing a
line above the main bar, bags on the right, minimap and quest tracker in the
drawer.

### Fixed

- **Health and power bars no longer go black.** They could turn black and stay
  that way until you moved the mouse over them.
- **The game's own nameplates no longer show through ours** when you are
  fighting.
- **The game's own casting bar is hidden properly.** It kept coming back the
  moment you cast anything, which is most of the time.
- **Bags close with the same key that opens them.** More than that: while any
  BazUI panel was open it quietly swallowed every keybind you pressed. Bags,
  options, Codex - all of them. That is gone.
- **Reloading during a fight no longer breaks the interface** until you reload
  a second time. It now waits for the fight to finish and then builds
  normally, and says so.
- **Nameplates no longer throw errors** when you attack something.
- **Edit mode no longer errors** if you close it while something is hitting
  you.

### Changed

- **The game's own frames are all hidden by default** - player, target,
  casting bar, party frames, pet casting bar and the raid manager tab. Each
  switch now says what ticking it does, because "Player frame" with a tick
  next to it could mean either. Untick any of them to have the game's frame
  back. If you group up, make party bars first: Edit Mode's Create menu makes
  all eight in one go.
- **Chat hides its own chrome by default.** Background and tabs appear when
  you point at the window, the scrollbar when you scroll.
- **The reagent bag slot is set apart** from the ordinary four, and every bag
  slot has a tooltip saying which one it is - including the empty ones.
- **One fewer message at login.** The note about abilities being placed on
  your bars was meant to appear once and appeared every time.

### New

- **`/baz errors`** lists anything that failed while the interface was being
  built, and a line at login tells you when there is something to see. Empty
  is the normal answer.
