## 005

**BazUI runs on retail now, as well as on World of Warcraft: Forever.** One
addon, one download, the same interface on both. Nothing about the Forever
build changes because of it.

**Settings still do not stick on Forever, and it is not BazUI.** That client
does not read an addon's settings back when you log in, so everything starts
from the built-in layout each launch. It affects addons across the board, and
the game's own settings too. There is an open bug report and nothing an addon
can do in the meantime. On retail your settings save normally.

### Fixed

- **Health and power bars are coloured from the first frame.** They came up
  black and only found their colour when you moved the mouse over one. A bar
  loses its fill when it is resized, and putting the value back used the one
  way that cannot work for health and power - so every resize emptied them.
- **Escape works after leaving Edit Mode.** Opening BazUI Edit from the Game
  Menu closed that menu the wrong way, and Escape did nothing at all for the
  rest of the session.
- **Quick Keybind Mode no longer swallows your keys.** After one use it took
  every keypress, including Escape, until you logged out.
- **Right-clicking a unit bar gives the game's own menu** - the one that knows
  about inviting, promoting and the rest. It had been falling back to a
  shortened guess since the feature was written.

### New

- **Nameplates can be set up per kind of unit.** Friendly players, friendly
  NPCs, neutral, hostile players, hostile NPCs, and mobs somebody else has
  tagged are six separate things now, each with its own switches for the
  health bar, name, level, rare and elite mark and class colour. Turn the bar
  off on friendly NPCs and a capital city becomes readable again. There is a
  new **Unit Kinds** page for it.
- **Bars and aura rows dock to the sides of things**, not just above and
  below. Dock your health to the left of a two-row action bar and your
  target's to the right, and each pair fills the height of the bar beside it.
- **Profiles can be exported and imported** as a string, to send to somebody
  else. An imported profile arrives as a new one; nothing you have is
  replaced.

### Changed

- **The Profiles page has been rebuilt.** It is grouped by what you came to do
  rather than by what kind of control each row is, the buttons say what they
  do instead of what they are, and the auto-assign switches show what they are
  set to - previously you could only find out by logging in as that character.
- **Edit Mode reads properly.** Every frame shows its name over the blue,
  sized to fit rather than spilling over its neighbours, and the frame that
  carries a stack is gold while the things it carries are blue. The panel has
  a button to move it to the other edge, and the pin beside it now actually
  unpins.
- **BazUI Edit sits under Edit Mode in the Game Menu**, rather than at the
  bottom under Return to Game.
- **The micro menu shows every button the game has.** On retail that is
  thirteen, including Professions, Achievements, Housing, the group finder,
  Collections, the adventure guide and the shop. The leftover square behind
  each round button is gone.
- **Party bars come with the starting layout**, so grouping up shows something
  without having to make them first.
