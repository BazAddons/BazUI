## 006

**BazUI comes with three layouts now.** A fresh install has **BazUI**,
**Classic** and **Modern** sitting in the profile list, ready to switch
between. They are three real arrangements rather than three colour schemes,
so you can try one, keep what you like and change the rest. Nothing you have
already set up is touched: an existing install keeps the profile it has and
simply gains the two new ones.

**Settings still do not stick on Forever, and it is not BazUI.** That client
does not read an addon's settings back when you log in, so everything starts
from the built-in layout each launch. It affects addons across the board, and
the game's own settings too. There is an open bug report and nothing an addon
can do in the meantime. On retail your settings save normally.

### New

- **Two new kinds of bar.** A **portrait**, flat or 3D, which can be held
  square so it is never stretched; and a **blank** bar that carries text and
  small marks instead of a value. Both dock and stack like any other bar.
- **Marks you can put on a bar.** Resting, in combat, group leader, the raid
  marker and away, each switched on per bar. They used to be one hard-coded zZ
  on your own health.
- **Bar text has a proper set of controls.** Size, either following the bar or
  pinned to a number; the outline around each letter; a drop shadow; the
  colour; and which end of the bar it reads from.
- **Aura icons can be round or square**, and every skin setting now belongs to
  the profile, so two profiles can look completely different.
- **Any bar or row can be left out of its stack's size.** Height and width are
  separate switches, so a casting bar can span the width of the stack it sits
  on while adding nothing to the height something docked beside that stack has
  to match.
- **New profiles can be made from Edit Mode**, without going to the options.

### Changed

- **Docking is about stacks, not single bars.** Dock a portrait beside a health
  bar with a power bar under it and the portrait stands as tall as the pair.
  Dock something under that group and it runs as wide as the group. All four
  edges behave the same way, which was not true before.
- **The order you dock in decides the sizes.** What you docked first keeps the
  size it was given, so adding a portrait beside a health bar no longer reaches
  back and widens the power bar that joined underneath before the portrait
  existed. Layouts can be built a piece at a time and stay put.
- **The green landing line now reaches across the whole stack** you are about
  to join, rather than the one bar it happens to name.
- **A reload leaves you on the profile you were on.** A character used to get
  quietly pinned to the default the first time it logged in, which undid any
  switch the moment you reloaded.

### Fixed

- **Drops that showed the green line and then did nothing.** Letting go now
  acts on exactly what the line promised. Edit Mode's grid was also pulling the
  frame away from the dock at the last moment, and it now stays out of the way
  when something is about to dock.
- **Things docked to a target bar stayed where they were.** They were docked -
  they had simply never been put anywhere, because the bar they joined is
  hidden while you have no target.
- **Target bars getting stuck on screen, or never appearing.** The dock and the
  game were both deciding whether they were visible, and the dock now leaves
  that to the game.
- **3D portraits going black.** Asking the game for a model is a request that
  can quietly come back empty, and a failed request was being remembered as a
  success, so nothing ever asked again.
- **Bars showing the unit's name when you had not asked for it.** "Current /
  Max" read "Bazbot 69564 / 69564" for everyone on retail.
- **Errors on retail from the game's new protected values.** Health, power,
  crit, spell crit, cast names and raid markers can all come back as values an
  addon is not allowed to read, and reading one throws. Every place that does
  has been found and guarded.
- **Names in other alphabets show as names** rather than as boxes.
- **Settings that were not being saved to the profile**, including the
  notification bell's position and the tooltip's. There is a `/baz audit`
  command that reports where every module's settings actually live.
- **The resting mark animates again** instead of drawing its whole sheet at
  once.
- **The profile dropdown updates immediately** after you create a profile.
