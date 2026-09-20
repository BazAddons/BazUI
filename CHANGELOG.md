## 007

**Drop a spell on the ground and you get a bar.** Drag an ability out of
your spellbook, let go anywhere over the world, and a bar appears there
holding it. Let go beside a bar you have already made and that bar grows
a slot on the side you came in on instead - a ghost of the button shows
you exactly where it will land before you commit to it. Items, macros,
mounts, equipment sets and flyouts all work the same way. Pulling
something off a bar and dropping it still just clears the slot, and
there is a switch in the Bars options if you would rather the gesture
did nothing at all.

**The bag has had a hard look at itself.** Reagent slots have stopped
pretending to be ordinary space, bags never scroll, and the bag opens
and works in combat like everything else.

### New

- **Reagent slots are their own category**, full and empty, and the count
  in the title bar ignores them. Twelve free general slots and thirty
  free reagent slots were never the same thing. The categories only
  appear if you are carrying a reagent bag.
- **Empty, empty reagent and empty keyring are three separate
  categories**, each collapsed when the bag opens, so a bag full of
  nothing stops pushing everything you own off the bottom.
- **When your bags fill up, the cheapest piece of junk is marked.** The
  slot wears a cross across the whole icon and the category heading names
  it - "drop Small Crab Claw first" - so you can see what to throw away
  without reading forty tooltips.
- **Right-clicking an item at a vendor sells it** instead of trying to
  equip it.
- **Using an ability on an item in your bag works.** Casting something
  that asks for a target and then clicking a bag slot used to be refused
  by the game outright.
- **Delete this bar** is on the bar's shift-right-click menu.
- **Draggable windows have a tab of their own** in the QoL options rather
  than sharing one, and **the quest window can be dragged** along with
  the rest of them.

### Changed

- **Bags never scroll.** A bag that would need a scrollbar grows another
  column instead.
- **The bag opens and works in combat.** Its slots are built ahead of
  time now, because the game will not let an addon make that kind of
  button mid-fight - which is why it used to come up empty.
- **The quest tracker's height cap starts at 900.** Four hundred was
  cutting most people off after three or four quests, which is the one
  thing a quest tracker must not do.
- **Notification toasts point at the bell**, from whichever corner suits
  the part of the screen the notification centre is sitting in.
- **The minimap button wears the addon remote** instead of the codex
  book.

### Fixed

- **The micro menu showed buttons the client has not got.** Both clients
  carry the code for every button either of them has, so asking whether
  one exists was the wrong question. It now takes the list and the order
  from the game itself, which means Forever gets Forever's menu -
  including its Legacy button - and retail gets retail's.
- **Item levels appeared on everything**, cloth and potions included.
  This client calls a potion's equipment slot "ignore" rather than
  leaving it blank, so the old test for "is this gear" said yes to
  everything. Only gear carries a level now.
- **The BazUI profile shipped with a second target power bar** that
  nobody asked for.
- **A settings tab that wrapped onto two rows.**
