## 008

Two fixes from 007, neither of which was worth waiting on.

### Fixed

- **You can throw things away again.** Dragging an item out of your bags
  and letting go over the world is how the game asks whether you want to
  destroy it - and 007's new "drop a spell to make a bar" was answering
  that question with a bar, so nothing could be deleted while BazUI was
  loaded. Items are left alone entirely now. Dropping one onto a bar slot
  still puts it there, and spells, macros, mounts, equipment sets and
  flyouts still make a bar wherever you let go of them.
- **The Codex said your quest log was empty.** It was reading the log
  through calls Forever does not have, so the Today tab reported nothing
  to a character carrying a dozen quests. It now reads the log the same
  way the quest tracker does, which has always worked. Quest levels show
  in the row tooltips as well, which they never did.
