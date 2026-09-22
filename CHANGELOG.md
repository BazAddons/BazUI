## 019

**The quest catalog is readable, and reloading mid-fight no longer looks like
the addon fell over.**

### Fixed: the quest pages

- **Descriptions were never shown.** Every quest page fell back to nothing
  where it should have fallen back to the catalog, so **4,306 quest
  descriptions were sitting in the addon and reachable by nobody.** They are
  on the page now.
- **The header stays put.** Title, facts line and rule are pinned; only the
  quest scrolls under them. The rewards block scrolls with it instead of
  being stranded.
- **XP and coin moved up** onto the Rewards heading, right-aligned — XP
  first, because there is always XP and there is not always coin. The last
  row used to be one number sitting alone.
- **Fonts.** Several lines were quietly resolving to the game's font instead
  of yours.
- **An objective that only repeats the summary** is no longer printed twice.
- **A quest with a summary and no story** crashed the page. Ten of 4,316 rows
  were affected.
- **Profession bars read full** when they were nowhere near it.

### Fixed: reloading in combat

The game refuses almost everything an addon does to the interface while you
are fighting, so a `/reload` mid-fight comes back half-arranged. That part is
unavoidable. What was wrong was how it looked and how it recovered.

- **A notice now says so**, on the left of the screen, in words: nothing is
  wrong, nothing needs fixing, it sorts itself the moment the fight ends.
  Click to dismiss.
- **The minimap no longer leaves a piece of itself in the middle of the
  screen.** It was coming back as a bare overlay with the tracking dots on
  it. Nothing touches the minimap now until combat is clear.
- **Blizzard's action bar no longer appears when the fight ends.** It was
  absent during combat and arrived the moment you were safe, which is
  exactly backwards. BazUI was standing in the middle of Blizzard's own
  show-the-bar function when it tried to hide it, and the game refused them
  both.

### Changed: the codex tabs

- **The rail is in a sensible order.** Today, Progress, then **Quests** —
  which is the biggest page in the addon and was sixth — then the things you
  are part-way through, then your gear, then the two pages about the game
  rather than about you. Legacy, an archive of things that no longer exist,
  was third.
- **You can rearrange it.** Hold a tab for half a second, it lights green,
  drag it up or down. The same hold and drag that moves a widget inside a
  drawer. **Reset page order** in the codex settings puts it back.
- **The wishlist is a page of the Items tab**, not a tab of its own. It is a
  list of items and you read it while you are looking at items. Two buttons
  at the top of that page switch between them.

### New

- **Hide TomTom's coordinates.** Puts away the little block showing where you
  are standing. TomTom's own setting is left alone, so turning this off gives
  you the block back exactly as TomTom had it.

### The manual

- **A page for the Quests tab**, which had none: the filters, the columns,
  what a row does, and how to read **Seen in game** against **Unconfirmed**.
- **Reloading in the middle of a fight** has a page, as does **two Edit
  Modes** — the game's moves the game's frames, BazUI's moves BazUI's, and
  opening one closes the other.
- **The micro menu's manual is gone.** It is a widget now, so it is written
  up with the widgets.
- Six other guides had drifted in a week and were corrected.
