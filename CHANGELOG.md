## 002

**Settings do not stick on the World of Warcraft: Forever beta, and that is
not BazUI.** That client writes every addon's settings when you log out and
never reads them back when you log in, so everything starts from defaults each
launch. It is not just this addon - it affects every addon on the beta, and
Blizzard's own settings too. Nothing an addon can do about it. When Blizzard
fixes the client, BazUI will simply start remembering again with no update
needed.

Until then, what you get on every launch is the built-in starting layout, which
has been rebuilt this release to be a real arrangement rather than a stub:
action bars along the bottom, health and power under them, target frames up
top, buffs and debuffs sharing a line above the main bar, bags on the right,
and the minimap and quest tracker in the drawer.

**Chat is back on Forever.** It was held out of the first release over a
conflict with the game's Edit Mode. That turned out to be narrower than
feared, and chat now loads on both clients again - tabs, channels, history,
timestamps, copy and the combat log tab.

### Fixed

- **Health and power bars no longer flick to black.** On the beta the game
  sometimes will not tell an addon what class someone is. Bars now get the
  right colour anyway instead of turning black for a few seconds.
- **Auras work again on the beta.** Buff and debuff rows could not be built at
  all on that client. They are rebuilt on BazUI's own rows now, and
  right-clicking a buff still cancels it.
- **The quest tracker shows your quests.** It was switched on but always
  empty on the beta. It now also handles scenarios, dungeon timers, bonus
  objectives, world quests, achievements and tracked recipes where the client
  has them.
- **No more errors while fighting** from the nameplates, which tripped over
  units like your target's target.
- **Bars stop erroring when you close the editor mid-fight.** Closing BazUI's
  edit mode while something was attacking you could fail; the change is now
  applied the moment combat ends.

### New

- **Aura rows can take half the width of what they are docked to**, so two
  rows share one line - buffs on the left of your action bar and debuffs on
  the right. Set it under Takes, with a Space beside slider for the gap.
- **Settings that do not apply right now are greyed out instead of
  disappearing.** A row that vanishes leaves you wondering whether the setting
  exists at all; now it stays put and tells you something else has to change
  first.
- **More of the game's windows can be made draggable** - the quest log,
  professions and the auction house were missing on the beta because they go
  by different names there.
- **`/baz check`** lists everything BazUI takes hold of in the game's own
  interface and says what is missing. Worth running first on a new client
  build.
