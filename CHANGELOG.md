## 018

**The quest catalog more than doubled: 5,014 quests, with where to find them.**

Version 016 shipped a catalog of 2,113 quests — every one the server would
name when asked for it by ID. It would not name the rest, so three
thousand quests were simply missing rather than uncertain.

They are in now, and so is something the catalog never had at all: **where
a quest lives and who gives it**. Open one you have never met and it tells
you the zone, the quest giver's name, the minimum level and which side it
belongs to. **124 zones, 3,956 named quest givers.**

There is a new **Side** column too, so a glance says whether a quest is
yours before you read anything else.

### Where the words come from, and why we say so

None of this pretends to be first-hand. A quest's own words never reach
your client until somebody is offered it, so for a quest nobody has met
the addon is repeating what a public database says — and the page tells
you that, on the quest's own facts line:

- **Seen in game** — somebody was offered this and the game laid the whole
  record out. A blank means the quest genuinely has none.
- **Unconfirmed** — borrowed. Good enough to walk towards, not good enough
  to plan around, and replaced outright the first time the quest is
  offered to you.

The rewards block is marked separately, because the words and the figures
can come from different places and the figures are the half you act on.

### New

- **Nameplates: Focus.** Fade everything that is not your target, enlarge
  the one that is, move plates up or down off the unit, and show them only
  in combat. On top of that, **anything actually attacking you gets a red
  rim** — the question threat is really being asked, given a mark of its
  own rather than a shade of the health bar. **Color by threat** is there
  for the full gradient.
- **Nameplates: names.** **Last names** can be turned off, leaving the
  first name only. **Guild name** puts the guild in angle brackets above
  the name, and an NPC's title comes through the same way, so a bartender
  reads <Bartender>.
- **Floating widgets can fade when you are not pointing at them.** A docked
  widget fades with its drawer; one loose on the screen had nothing to fade
  with. Every floating widget gets the switch and its own faded opacity.
- **The quest timer is back.** It is a child of Blizzard's tracker, which
  BazUI hides — so a timed quest counted down where nobody could see it.
  It has been rescued onto its own draggable frame.

### Changed

- **The micro menu is a drawer widget.** It can float anywhere, dock into a
  drawer beside the clock and the repair icon, scale with that drawer and
  fade on mouseover. It also gained **rows** — ten buttons in two rows of
  five — and a switch to **leave Blizzard's button art alone** if you would
  rather not have the round icons.
- **You will need to place it once.** Its old position setting is gone,
  along with the page it used to live on: its settings are with every other
  widget's now, in Drawers > Widgets.
- **Blizzard's Edit Mode and BazUI's are separate.** Opening theirs closes
  ours rather than putting two grids and two panels on the screen arguing
  over frames that answer to only one of them. BazUI's inspector opens
  pinned on the left.
- **Only the buttons this client has** get a row in the micro menu
  settings. There is no Achievements button on WoW: Forever, so there is no
  longer a switch for one.

### Fixed

- **Surnames.** Players have two names on this client and the addon was
  showing one. Nameplates and unit frames both.
- **Dragging a floating widget** could snap it back while you were still
  holding it.
- **A quest timer's position** was never restored, and what looked like it
  drifting was it starting from scratch every reload.

### Notes

- Quests that share a title - every race's copy of the same starting
  quest, every class's version of the same trainer chain - are told apart
  by zone, by who gives them, or failing both by their id. 521 titles in
  this catalog belong to more than one quest.
