## 012

**The Codex is rebuilt, and it is the reason for this release.** It used to
be four pages of lists. It is now eleven pages built out of the game's own
window art, with a tab and a painting for each: Today, Progress, Legacy,
Events, Equipment, Instances, Reputation, Currencies, Professions, Items and
Wishlist. Open it with `/codex` or by left-clicking the BazUI button on your
minimap.

Some of what it answers, the game will not tell an addon at all - which
raids you are keyed for, which dungeon sits at which level - so that part is
written down and checked against your client before it is shown. A door it
is unsure of is left out rather than promised.

### New

- **Every page explains itself.** Hover a block's heading and it says what
  goes in it. A block with nothing in it yet tells you what would fill it,
  so an empty page reads as something to go and do.
- **Equipment** is a paper doll with your item level on each slot and the
  one thing wrong with it underneath: a missing enchant, or how worn it is.
- **Instances** is the whole map of where you can go, not only where you are
  ready for. Each row says which of the five things is true: saved, too low,
  not attuned yet, outgrown, or open to you.
- **Events** reads your calendar, leads with the holiday that is running,
  and every row opens the calendar on that day. There is a round calendar
  button on that page, and **shift and right click on the minimap** opens
  the calendar from anywhere.
- **Mirror bars.** Breath, fatigue and feign death as a bar you make
  yourself, docked where you want it, wearing your skin, coloured by which
  timer is counting. Edit Mode, Create, Bars and readouts. Making your first
  one takes the game's own timer bars off the top of the screen.
- **A manual that matches the addon.** Every page of the User Manual has
  been read against the code it describes and rewritten. Whole features had
  never been written down, and a fair number of settings had been renamed
  since.

### Fixed

- **Dropping a consumable on an action bar used it.** The click that placed
  it also drank it. Click-dropping onto a slot that already held something
  quietly did nothing at all, for the same reason.
- **The reorder arrows were invisible.** Every list you can reorder - bag
  categories, drawer widgets, minimap buttons - had working arrows with no
  picture on them.
- **Blocked actions when closing the map in combat.** BazUI made the game's
  windows draggable in a way that left its name on them, so the map's own
  work in a fight was refused and blamed on us.
- **`/bb dup`, `/bb copy`, `/bb remove` and `/bb spacing`** were listed in
  the help and did nothing. They work now.
- **A reload in combat left the minimap in the middle of the screen.**
- **Shift and right click on the minimap** no longer pings where you
  clicked while opening the calendar.
