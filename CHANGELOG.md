## 015

**Your settings stay put on WoW: Forever.**

The client writes every addon's saved variables at logout and never reads
one back. Not BazUI's, not anybody's. It is why your bars, your layout and
half your interface have been forgetting themselves on every reload since
the day Forever launched, and there has never been anything an addon could
do about it from the inside.

There is now. Some of the game's own saved files are read back, and BazUI
keeps its settings in one of those. Your layout, your bars, your profiles,
your window positions and everything else come back through a reload, a
logout and a full restart. Nothing to switch on, nothing to set up, no
file to edit.

If you have been baking a settings file by hand to work around this, you
can stop.

### New

- **BazUI can carry other addons' settings too.** The bug is not ours and
  neither is the damage, so **Quality of Life > Other addons' settings**
  has a switch for each addon you have installed that we know how to
  help. TomTom keeps its arrow where you put it and stays quiet about the
  coordinates. For anything not on the list, `/baz persist add <AddOn>
  <Globals>`.
- **Four more draggable windows**: the spellbook, which carries your
  talents with it, the guild and communities window, the group finder,
  and appearances.
- **Draggable Windows opens with the two controls that act on the whole
  page**, and they stay put while the list scrolls. **All windows
  draggable** throws every switch at once, and **Reset window positions**
  replaces the old Forget where I put them.

### Fixed

- **Window positions come back.** The bag panel and the codex were
  reading their saved position before the settings had arrived, so they
  centered themselves and never looked again. Invisible until now, for
  the obvious reason.
- **A greyed switch** in that addon list is one that loads before BazUI.
  Its settings are already read by the time we could put them back, so it
  says so rather than pretending.

### Notes

- On a client that reads saved variables properly, BazUI uses those
  instead and tidies away anything it left behind. The day Forever is
  fixed, all of this stops mattering on its own, with nothing to undo.
