# BazUI

The Baz Suite as one addon, built for **World of Warcraft: Forever**.

BazUI replaces a stack of separate addons (BazCore, BazWidgetDrawers, BazChat, BazBags and parts of BazBars) with a single install: one options window, one profile system, one skin.

**Status: in development.** Built on Classic Era while the Forever client is unreleased. Not universal - Retail keeps the existing Baz Suite addons.

## Modules

| Module | Source | Status |
| --- | --- | --- |
| Core | BazCore | Ported |
| Drawers | BazWidgetDrawers | Ported (Minimap, Minimap Buttons, Info Bar, Zone Text, Quest Tracker) |
| Chat | BazChat | Ported (tabbed chat replacement: channels per tab, timestamps, history, copy, combat log) |
| Bags | BazBags | Ported (Classic bags plus keyring; categories, pinning, search) |
| Bars | BazBars | Ported (bars, spells, items, macros, mounts, equipment sets, keybinds; no toys, pets or flyouts) |

## Commands

- `/bazui` (or `/bui`) opens the options window.
- `/bazui profile <name>`, `/bazui profiles`, `/bazui default <name>` manage profiles.
- `/bwd toggle|show|hide|open <name>|list` drives the drawer.
- `/bbg` (or `/bazbags`) toggles the bag panel; `/bbg sort`, `/bbg categorize`.
- `/bb` (or `/bazbars`) for bars: `create`, `delete`, `duplicate`, `export`, `import`, `scale`, `padding`, `reset`.
- `/bazchat` (or `/bc`) for chat: `copy`, `clear`, `lock`, `unlock`, `restoredefaults`; `/cc` clears the active tab.

## License

GPL v2. See LICENSE.
