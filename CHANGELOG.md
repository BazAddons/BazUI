## 001

The first release of BazUI: the Baz Suite rebuilt as a single addon, with one options window, one profile system and one look across every part of it.

**Your interface**

- **Action bars** you create, holding spells, items, macros, mounts, equipment sets and flyouts, with quick keybinds and import/export. A new character's abilities are placed for you on first login, newly learned spells take the first empty slot, and the active stance or form lights up.
- **Unit frames** as bars you make yourself: health, power, casting, experience and reputation, floating or docked to an action bar or to each other. There are no portraits, which is what lets any bar dock to anything else. Party bars, party pets, range fading, and a way to copy a whole docked stack onto another unit.
- **Nameplates** over each unit's head in the same look, coloured by whether it will attack you, with the one you have targeted picked out.
- **Auras** in rows that dock to any bar, each with its own icon size, spacing, growth direction, sorting and limits. Right-click still cancels a buff.
- **Bags**: one panel for every bag and the keyring, grouped by bag or by category, with pinning, search and gold. Free space is a category you can move and collapse, rarity borders on slots, the free count in the title bar, and a button that sells your greys when a merchant is open.
- **Chat**: a tabbed replacement with per-tab channels, timestamps, persistent history, copy, and the combat log on its own tab.
- **Minimap and drawers**: the minimap in its own frame, every addon's minimap button collected into one row, and a slide-out drawer of widgets - clock, coordinates, gold, durability, free slots, quest tracker, notepad, calculator, performance and twenty more. Anything publishing a LibDataBroker feed becomes a widget too.
- **Notifications**: toasts and a browsable history for loot, quests, reputation, mail, experience, zones, instances, groups, professions, the auction house, friends and guild, with a movable bell and Do Not Disturb. Each card carries a band in its source's colour. If you run Zygor, its notifications can come through here too, clicks and all.
- **Codex**: one window for what you have done and what is left - today's quests and lockouts, reputations, goals, items and a wishlist.
- **Micro menu** on a movable bar as round icons, with your portrait on the character button.
- **Tooltip** in the same skin and the same face, anchored where you want it.
- **Quality of life**: instant quest text, repairing and selling greys at a vendor, a screenshot when you level, declining duels. All off until you turn them on.

**Make it look how you like**

Nearly everything BazUI draws is a plain texture tinted by a handful of colours, so the whole look is a list of numbers rather than a folder of art. The Skin tab lets you change any of it:

- **Colours** - fifteen of them, grouped by what they are for, each with a colour picker.
- **Borders** - a list of bands running outward from the fill. Change a colour or a thickness, add as many as you like, or take them all off for a bare edge. Every edge in the addon follows: bars, panels, nameplates, round buttons, tooltips.
- **Bar fill** - gloss, marble, flat, or a gradient worked out from each bar's own colour. If you have LibSharedMedia, everything it knows about is in the list too.

Changes are applied as you make them. Skins can be exported and imported as a string, and another addon can ship one.

**How it behaves**

- A fresh install lays itself out at any resolution: frames, bars, bags, chat, micro menu and drawer all placed.
- Every module has an off switch, per profile. Turn one off and the game's own version comes back.
- Blizzard's own frames are only hidden where you ask, on a switch per frame.
- Everything can be moved in BazUI's Edit Mode, docked to anything else, and nudged a pixel at a time.
- A **User Manual** sits at the foot of the settings list, with a page per module.
- `/bazui` opens the options. `/bazui check` reports anything the addon expects from the game's own interface and cannot find - useful for telling a real bug from a client that has moved something.

Built for World of Warcraft: Forever, and still in development - bug reports and suggestions are welcome.
