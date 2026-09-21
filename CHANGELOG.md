## 014

**The Codex knows every item in the game.** The Items tab used to search
only the things your character had carried, because the client cannot
search its own items - there is no call for it. So BazUI now ships the
game's own item list for WoW: Forever, generated from the game's tables
the same way the faction and instance lists already were. 17,771 items,
once the placeholders and the retired ones are dropped.

Open the tab and it is all there, in name order. Scroll it, browse it by
category, sort it, or type a name and search the lot.

### New

- **Browse by the game's own tree**, the one the auction house uses. Pick
  Weapon and a second row of tabs gives you Daggers, Staves, Swords. Pick
  Armor and it gives you Cloth, Leather, Mail, Plate; pick one of those
  and a third row gives you the slot. Cloth then Legs is every cloth leg
  piece in the game.
- **Columns, and they belong to what you are looking at.** Armor and
  weapons get Type, Slot, iLvl and Req. Consumables get Type and Req,
  because item level on a potion is a number nobody wants. Quest items
  and keys get neither. **Click a heading to sort by it**, click again to
  turn it round - so sorting cloth legs by Req shows what you can wear
  now.
- **A star on every row** adds the item to your Wishlist, and takes it
  off again. Searching for something and starring it is the way to build
  a wishlist now; the box on the Wishlist tab is still there for a link
  somebody just posted in chat.
- **A green tick** on a row means this character has met that item:
  carried, worn, banked, looted, or seen linked in chat.
- **A count under the tabs**, always, saying how many items you are
  looking at and of how many.
- **`/bwd float`** and **`/bwd map`** report where loose drawer widgets
  and the minimap think they should be, for when one is not where you
  expect.

### Fixed

- **The item list ran out at two hundred rows.** It draws only the rows
  that fit and scrolls through the rest, so the end of a search is
  reachable however long it is.
- **Opening the Codex now gives you a fresh window.** The page you were
  on, what you had typed, what you had narrowed to and what you had
  sorted by are let go when it opens. Folded blocks still stay folded.
- **Tabs were truncated with room to spare** beside them.
- **Everything is written in American English**, which it was not
  consistently.
