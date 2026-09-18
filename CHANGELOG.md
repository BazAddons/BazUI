## 004

**Settings still do not stick on the World of Warcraft: Forever beta, and it
is not BazUI.** That client does not read an addon's settings back when you
log in, so everything starts from the built-in layout each launch. It affects
addons across the board, and the game's own settings too. There is an open bug
report for it and nothing an addon can do in the meantime. When Blizzard fix
the client, BazUI will start remembering again on its own, with no update
needed.

### New

- **Bars are drawn with the game's own artwork now**, and that is what a fresh
  install starts with. It is the same bar the player frame uses - soft top and
  bottom edges, the shape you already know - coloured by BazUI rather than
  fixed, so class colours, mana, rage and energy all still read as themselves.
  It is on the Skin page as **HUD**, with a flatter **HUD Party** cut beside it
  that suits thin bars. Every fill that was there before still is; pick one of
  those to go back.

### Fixed

- **The raid manager tab hides when you tell it to.** The switch for it had
  never worked: that tab only exists once you are in a group, and BazUI stopped
  looking for the game's frames before you ever joined one. It looks again when
  the group changes now.

### Changed

- **Draggable windows start on.** All of them - character sheet, quest log,
  vendor, bank, the options window itself. Everything else on the Quality of
  Life page starts off on purpose, because those change how the game behaves;
  making a window draggable does nothing at all until you drag it. Switch off
  any you would rather the game kept placing.
- **This is a Forever addon.** Earlier versions also published a Classic Era
  build. That has stopped - one client, properly, rather than two halfway.
