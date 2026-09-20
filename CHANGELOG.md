## 009

**The bag works in a fight.** It opens, closes, gets dragged around and
rearranges itself while you are in combat, the way every other window
does. Before this it refused - and on 008 it refused loudly, with an
error, which is the worst way to say no.

The cause was ours. A bag slot was built as a secure button so that
clicking one could use what was in it. That made every frame around it
protected, and the game does not let an addon open, close, move or lay
out a protected frame during combat. It turns out the game's own bag slot
already does all of that from an ordinary button - using, selling at a
vendor, picking up, splitting, linking, and putting a waiting spell onto
an item. Ours now leaves that alone instead of reinventing it, and about
a hundred and twenty lines of working around the problem went with it.

Nothing you do with a bag slot has changed. If anything it should be a
little more like the bag you already know.

### Changed

- **An item you run out of clears its own bar slot.** Drink the last
  water and the button empties, rather than leaving an icon that cannot
  be clicked and reads zero. A trinket you are wearing does not count as
  gone, and neither does a wand with charges left. Putting the last of
  something in the bank does clear it - it is not in your bags any more,
  and a slot you cannot use until your next bank visit is worse than one
  you refill by dragging.
