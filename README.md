# BazUI

The Baz Suite as one addon, built for **World of Warcraft: Forever**.

BazUI replaces a stack of separate addons (BazCore, BazWidgetDrawers, BazChat, BazBags and parts of BazBars) with a single install: one options window, one profile system, one skin.

**Updated for the WoW: Forever launch.** Two clients are supported: **WoW: Forever**, which BazUI is built for, and **retail**, which is kept working alongside it. No Classic flavour is supported. The Codex is Forever only.

## Modules

| Module | Source | Status |
| --- | --- | --- |
| Core | BazCore | Ported |
| Drawers | BazWidgetDrawers + BazWidgets + BazBrokerWidget | Ported (Minimap, Minimap Buttons, Info Bar, Zone Text, Quest Tracker, 20 pack widgets, LibDataBroker feeds as widgets; delve, Great Vault, currency and pet-journal widgets dropped) |
| Chat | BazChat | Ported (tabbed chat replacement: channels per tab, timestamps, history, copy, combat log) |
| Bags | BazBags | Ported (Classic bags plus keyring; categories, pinning, search) |
| Bars | BazBars | Ported (bars, spells, items, macros, mounts, equipment sets, flyouts, keybinds; no toys or pets) |
| Unit Frames | new (written by Codex) | Built (health, power, casting, experience and reputation as bars you create, floating or docked to an action bar or to each other; no portraits) |
| Auras | new | Built (four rows of buffs and debuffs that float or dock to any bar, left/center/right aligned, secure right-click cancel) |
| Notifications | BazNotificationCenter | Ported (toasts, history panel, bell; 15 sources, no Mythic+, Vault, rares, collections or talking head) |
| Micro Menu | new | Built (Blizzard's micro buttons on a movable bar as round ring-framed icons) |
| APS | new | Azeroth Positioning System: standalone waypoints and quest navigation, a brass-and-brown arrow, compatible /way commands, and optional TomTom/Zygor targets in one display. |
| Map | OpenMap rendering core (MIT) | Forever's default world map with continuous cursor-anchored zoom and terrain detail fading in up close. Keeps the native window and quest log; no additional map tools. Disable OpenMap before using it. |

## First run

A fresh install starts with the BazUI layout: player frame centered above the bars, target frame at the top, a 14-slot bar along the bottom with a 6-slot bar either side (Blizzard's own action bar is hidden; drag your abilities onto the BazUI bars), bags docked right in categories mode, chat bottom-left, the micro menu top center, and the minimap drawer on the right. Every piece can be moved in BazUI Edit Mode or changed in Options > AddOns > BazUI. Updating never changes existing settings.

## Commands

- `/baz` (or `/bazui`, `/bui`) opens the options window.
- `/bazmap` opens Map settings. Adjust terrain opacity, when terrain begins fading in, and maximum zoom. Set **Terrain opacity at full zoom** to 100% to fully cover the painted map at the deepest terrain blend. **Unexplored areas** can be hidden, dimmed, or revealed; exploration progress is unchanged. Settings apply immediately and are saved per profile.
- `/baz errors` opens the core developer error browser: Previous/Next, Select All and Ctrl+C, Copy all, or Clear. `/baz errors all`, `/baz errors <number>`, `/baz errors clear`, and `/baz errors status` are also available. Lua errors, startup failures and blocked actions are grouped locally, with the newest 50 reports saved across reloads in `BazUIDevDB`. No extra error addon is required.
- `/aps` opens Azeroth Positioning System settings; `/aps preview` toggles the arrow preview; `/aps status` reports connected navigation addons.
- `/way [zone or #mapID] x y [name]` (also `/aps way`, `/tway`, `/tomtomway`) accepts pasted Wowhead coordinates without TomTom. For example: `/way Elwynn Forest 42.1 65.9 Meet here`.
- `/wayb [name]` saves your position; `/cway` selects the closest saved waypoint; `/way list` and `/way local` list them; `/way reset all`, `/way reset away`, or `/way reset [not] zone` remove them.
- `/aps clear` or `/way arrow clear` clears navigation; `/way arrow remove` also removes the active saved waypoint. `/ttpaste` (or `/aps paste`) imports multiple coordinate commands, one per line. The arrow is click-through; hold Shift to drag it. Quest tracker circles select a quest's next available location.
- `/baz profile <name>`, `/baz profiles`, `/baz default <name>` manage profiles.
- `/bwd toggle|show|hide|open <name>|list` drives the drawer.
- `/bbg` (or `/bazbags`) toggles the bag panel; `/bbg sort`, `/bbg categorize`.
- `/bb` (or `/bazbars`) for bars: `create`, `delete`, `duplicate`, `export`, `import`, `scale`, `padding`, `reset`.
- `/bazframes` opens the Unit Frames options; `/bazauras` opens the Auras options (`/bazauras reset` resets the layout).
- `/bnc` toggles the notification panel; `/bnc dnd`, `/bnc clear`, `/bnc history`, `/bnc test`.
- `/bazmicro` opens the Micro Menu options; `/bazmicro reset` moves the bar back to the top center.
- `/bazchat` (or `/bc`) for chat: `copy`, `clear`, `lock`, `unlock`, `restoredefaults`; `/cc` clears the active tab.

## License

BazUI - one addon for your whole interface in World of Warcraft
Copyright (C) 2026 Baz Studios LLC

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, see <https://www.gnu.org/licenses/>.

The full text is in [LICENSE](LICENSE), and the complete source is this
repository - <https://github.com/BazAddons/BazUI>.

`Skin/Assets/DORISBR.TTF` is a bundled font and carries its own license,
separate from the addon's.
