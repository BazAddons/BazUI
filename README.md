# BazUI

The Baz Suite as one addon, built for **World of Warcraft: Forever**.

BazUI replaces a stack of separate addons (BazCore, BazWidgetDrawers, BazChat, BazBags and parts of BazBars) with a single install: one options window, one profile system, one skin.

**Status: in development.** Built on Classic Era while the Forever client is unreleased. Not universal - Retail keeps the existing Baz Suite addons.

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

## First run

A fresh install starts with the BazUI layout: player frame centered above the bars, target frame at the top, a 14-slot bar along the bottom with a 6-slot bar either side (Blizzard's own action bar is hidden; drag your abilities onto the BazUI bars), bags docked right in categories mode, chat bottom-left, the micro menu top center, and the minimap drawer on the right. Every piece can be moved in BazUI Edit Mode or changed in Options > AddOns > BazUI. Updating never changes existing settings.

## Commands

- `/bazui` (or `/bui`) opens the options window.
- `/bazui profile <name>`, `/bazui profiles`, `/bazui default <name>` manage profiles.
- `/bwd toggle|show|hide|open <name>|list` drives the drawer.
- `/bbg` (or `/bazbags`) toggles the bag panel; `/bbg sort`, `/bbg categorize`.
- `/bb` (or `/bazbars`) for bars: `create`, `delete`, `duplicate`, `export`, `import`, `scale`, `padding`, `reset`.
- `/bazframes` opens the Unit Frames options; `/bazauras` opens the Auras options (`/bazauras reset` resets the layout).
- `/bnc` toggles the notification panel; `/bnc dnd`, `/bnc clear`, `/bnc history`, `/bnc test`.
- `/bazmicro` opens the Micro Menu options; `/bazmicro reset` moves the bar back to the top center.
- `/bazchat` (or `/bc`) for chat: `copy`, `clear`, `lock`, `unlock`, `restoredefaults`; `/cc` clears the active tab.

## License

GPL v2. See LICENSE.
