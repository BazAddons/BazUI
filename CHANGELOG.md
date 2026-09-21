## 016

**Every quest in the game, in the codex.**

There is a new **Quests** tab in the codex holding all 6,600 quests WoW:
Forever ships, split into **Incomplete**, **In progress** and **Complete**.
Search it by name, by objective, by what it pays. Click one and you get
the whole thing: what it asks, the objectives, the giver's words, the
gold, the experience, and the rewards as icons you can hover for the real
tooltip.

The interesting part is that it keeps learning. Every quest you are
offered, work on, or hand in is written down as the game itself said it,
and what the game says always wins over what shipped in the file. Play
normally and the catalog fills in behind you.

### New

- **It remembers where you were standing.** Take a quest and BazUI notes
  the zone, the spot and the coordinates, along with the name of whoever
  handed it to you. Hand it in and it notes the other end. Both show up
  under **Where** on the quest, and with TomTom installed you can click
  either one to point the arrow at it.
- **Right-click a quest** for track, untrack, share with the group, link
  it in chat, set a waypoint, or abandon it. Abandon asks first.
- **Action bars can have a background.** A toggle in each bar's own
  inspector. Docked bars measure the wider edges and move with them, so
  turning it on does not shove your layout around.
- **Middle-click the minimap button** to enter BazUI Edit Mode. Left is
  still the codex, right is still the settings.
- **The codex equipment page takes drag and drop.** Drag a weapon onto
  the slot and you are wearing it; drag it off and it is in your bag. The
  slots that will take what you are holding light up while you hold it.
- **The flight map** joins the draggable windows.
- **The reputation bar** has the **Takes** and **Aligned** options the
  experience bar already had.

### Changed

- **The Action Bars options page is gone.** Everything it did lives in
  each bar's inspector in Edit Mode, where you are pointing at the bar
  you mean instead of picking its number off a list. One place to edit a
  bar, and it is the bar.
- **No enchant** on the equipment page is now a small icon rather than a
  line of text that ran into everything around it. Lit means enchanted,
  dim means not, and the tooltip says which.

### Fixed

- **Edit Mode no longer taints Blizzard's.** Selecting one of our frames
  cleared their selection by calling their code directly, which was
  enough to get their next layout pass refused with an error about
  MainActionBar, a frame BazUI has never touched. Same fix for the guild
  message of the day, which was failing outright, and for the codex
  portrait, which threw an error instead of opening the character sheet.
- **Right-clicking a flyout** opened the flyout and cast the ability on
  it. Now it only opens the flyout.
- **Flyout cooldowns** spammed the error frame. They do not.
- **Clicking a window brings it forward** again. The bag sat in a layer
  above the game's own panels, so the character sheet could never come
  out from behind it. The bag's **Frame layer** setting explains the
  trade now, and Medium is the sociable one.
- **TomTom's arrow** was being adopted as a minimap button and stuffed
  into the drawer. It is an arrow. It stays where it is.
- **A bar dragged onto another bar** kept the inspector it had while it
  was floating, missing the settings that only apply once docked. Same
  for aura rows.
