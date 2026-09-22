## 020

**Your buffs and debuffs finally work during a fight.**

This is the big one, and it needs a word of explanation because the fix is
not what you would expect.

On WoW: Forever, the moment a fight starts the game stops telling addons
anything at all about auras. Not "some auras" — every buff and every debuff,
on you and on your target, becomes unreadable. Ask anyway and the game
answers with an error.

So BazUI's aura rows **froze**. Whatever you happened to have when the fight
began stayed on screen, unchanging, until it ended. A debuff you applied
mid-fight never appeared at all — which, for a damage-over-time spell that
expires before the fight is over, meant it was never visible once.

There is no way to read that data. There is a way to *show* it.

The game ships an aura display system meant for addons to use. BazUI now
hands it a unit, a filter and somewhere to draw, and the game fills it in.
**Nothing about your auras is ever read** — which is exactly why it works
while everything else is refused.

What that means in practice:

- **Debuffs on your target appear the moment you apply them**, and their
  timers count down properly.
- **Buffs you gain mid-fight show up**, instead of after it.
- **Stack counts keep counting.**
- **Right-click still cancels one of your own buffs**, in combat or out —
  and it now cancels *that specific aura* rather than a position in the row,
  so it can no longer cancel the wrong thing when something above it drops
  off.
- **Weapon enchants** are a proper part of the row now instead of a
  stand-in, with the game keeping their timers.

It looks identical to before. If anything misbehaves, **Let the game draw
the icons** at the top of Auras > General puts the old rows back, with no
reload needed.

One change worth knowing: the game deliberately does not tell an addon *how
many* auras there are, so a row can no longer shrink to fit its contents. It
holds the size you set it to, full or empty. Floating, you will not notice.
Docked in a drawer, an empty row now keeps its space.

### Fixed

- **Blizzard's action bar could come back with a taint on it.** Hiding one of
  the game's Edit Mode frames ran a pile of their own layout bookkeeping
  while BazUI was the one asking, and one of their fields ended up marked as
  ours. That is what was behind the blocked `SetPointBase` errors, and
  probably the cooldown errors on the override bar too. BazUI now hides
  those frames the plain way and touches none of their bookkeeping.
- **Picking an ability up off a bar made Blizzard's bar flicker.** It was
  being hidden a frame late. Now it is hidden immediately, and suppressed
  frames are made transparent as well as hidden — which also means a reload
  during a fight no longer leaves the game's frames sitting visible until
  the fight ends.
- **Out-of-range coloring did nothing with "target where you're looking."**
  It only ever checked your hard target, and soft targeting does not set
  one, so icons never dimmed for anyone playing that way.
- **The "new slot" marker appeared on slots that already existed.** Aim past
  the end of a bar whose last slot is empty and it offered to add a slot on
  top of one that was already there. It now only appears where a slot would
  genuinely be created.
- **`/baz persist` said it could not tell what an addon saves, and gave an
  example that read like a stutter.** It now says plainly which addons it
  covers. It looks after a few that have actually been tested, and does not
  guess at others — restoring the wrong table over a live one would break
  the addon it was trying to help.

### New

- **`/baz auras`** reports what the game will and will not let BazUI see
  about auras right now, and what each row is holding. Run it in combat and
  it explains, in words, why nothing is readable.

### Changed

- **A fresh install starts with an updated layout**, including the nameplate
  Focus settings added in 018, which had never made it into the starting
  arrangement. Existing setups are untouched.
