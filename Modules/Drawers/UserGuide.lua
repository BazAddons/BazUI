-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Drawers User Guide
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Drawers", {
    title = "Drawers",
    intro = "A full-height slide-out drawer that hosts a vertical stack of dockable widgets and fades out of the way when you're not using it. Run multiple drawer presets and switch between them by hand or automatically based on game context.",
    pages = {
        ---------------------------------------------------------------
        -- Welcome
        ---------------------------------------------------------------
        {
            title = "Welcome",
            blocks = {
                { type = "lead", text = "The Drawers module docks to either edge of your screen and holds a stack of widgets. Instead of scattering a dozen small frames around your UI, it gathers everything into one tidy column flush against the edge." },
                { type = "h2", text = "What can dock here?" },
                { type = "list", items = {
                    "Quest Tracker",
                    "Minimap",
                    "Minimap Buttons",
                    "Zone Text",
                    "Info Bar (clock, calendar, tracking)",
                }},
                { type = "note", style = "tip", text = "Widget content stays at full opacity even when the drawer chrome is faded — quest text and minimap remain readable at all times." },
                { type = "h2", text = "Slash commands" },
                { type = "table",
                  columns = { "Command", "Effect" },
                  rows = {
                      { "/bwd",           "Open the BazUI Drawers settings page" },
                      { "/bwd toggle",    "Open or close the drawer" },
                      { "/bwd show",      "Open the drawer" },
                      { "/bwd hide",      "Close the drawer" },
                  },
                },
            },
        },

        ---------------------------------------------------------------
        -- The Drawer
        ---------------------------------------------------------------
        {
            title = "The Drawer",
            blocks = {
                { type = "paragraph", text = "The drawer is a slide-out side panel with chrome that fades when you're not interacting with it." },
                { type = "h3", text = "Pull tab" },
                { type = "paragraph", text = "A metal pull-tab handle sits on the screen edge. Click to slide the drawer on or off screen." },
                { type = "h3", text = "Side & width" },
                { type = "list", items = {
                    "|cffffd700Side|r — Left or Right; tab, slide direction, and edge hot zone all flip automatically",
                    "|cffffd700Width|r — 120–400 px; every docked widget rescales uniformly when you change this",
                    "|cffffd700Edge hot zone|r — invisible strip along the screen edge that re-reveals the tab when collapsed",
                }},
                { type = "note", style = "tip", text = "If the tab feels hard to find, widen the edge hot zone in Settings → BazUI Drawers → General Settings." },
            },
        },

        ---------------------------------------------------------------
        -- Multiple Drawers
        ---------------------------------------------------------------
        {
            title = "Multiple Drawers",
            blocks = {
                { type = "lead", text = "You can run more than one drawer at a time, each with its own preset of widgets, side, width, fade, and lock state." },
                { type = "h2", text = "Tabs at the top" },
                { type = "paragraph", text = "Each drawer appears as a tab along the top of the drawer area. Click a tab to switch which drawer is currently visible. Each tab has its own icon (configurable per drawer)." },
                { type = "h2", text = "Common patterns" },
                { type = "table",
                  columns = { "Use case", "Suggested widgets" },
                  rows = {
                      { "Questing",  "Quest Tracker, Minimap, Coordinates, Zone Text" },
                      { "M+",        "Quest Tracker (Challenge Mode block), Pull Timer, Cooldowns, Trinket Tracker" },
                      { "PvP",       "Speed Monitor, Trinket Tracker, Performance" },
                      { "Crafting",  "Currency Bar, Note Pad, Calculator, Free Bag Slots" },
                  },
                },
                { type = "h2", text = "Creating + managing drawers" },
                { type = "list", items = {
                    "|cffffd700Settings → BazUI Drawers → Drawers|r → Create New Drawer",
                    "Each drawer has its own Name, Icon, Auto-switch trigger, and widget list",
                    "Delete any drawer except the last one (you always have at least one)",
                }},
            },
        },

        ---------------------------------------------------------------
        -- Auto-Switch
        ---------------------------------------------------------------
        {
            title = "Auto-Switch",
            blocks = {
                { type = "lead", text = "Each drawer can be set to activate automatically when you enter a specific game context. Useful for swapping your widget loadout the moment you queue up or take a portal." },
                { type = "h2", text = "Available triggers" },
                { type = "table",
                  columns = { "Trigger", "Activates when..." },
                  rows = {
                      { "None (manual only)",     "(default) — only when you click the tab" },
                      { "Open World / Questing",  "you're not in any instance" },
                      { "Dungeon (5-man)",        "you enter a 5-man dungeon" },
                      { "Raid",                   "you enter a raid instance" },
                      { "Mythic+ (Challenge Mode)", "a Mythic+ key is active" },
                      { "Delve",                  "you enter a Delve" },
                      { "Battleground",           "you enter a battleground" },
                      { "Arena",                  "you enter an arena match" },
                  },
                },
                { type = "note", style = "info", text = "Two drawers can claim the same trigger — the first one wins. Tabs at the top still let you flip between them by hand." },
                { type = "h2", text = "Setting it up" },
                { type = "list", ordered = true, items = {
                    "Open |cffffd700Settings → BazUI Drawers → Drawers|r and select the drawer you want to auto-switch to",
                    "Toggle |cffffd700Auto-Switch|r on",
                    "Pick the |cffffd700Trigger|r from the dropdown",
                }},
            },
        },

        ---------------------------------------------------------------
        -- Per-drawer widget assignment
        ---------------------------------------------------------------
        {
            title = "Choosing Widgets per Drawer",
            blocks = {
                { type = "lead", text = "Each drawer has its own widget list. Use the Widgets page to enable widgets globally, then use the Drawers page to pick which widgets show up in which drawer." },
                { type = "h2", text = "Two-step workflow" },
                { type = "list", ordered = true, items = {
                    "|cffffd700Widgets page|r — toggle the Enabled switch on each widget you ever want to use. Disabled widgets are hidden everywhere — no drawer slot, no floating frame.",
                    "|cffffd700Drawers page|r — for each drawer, tick the box next to widgets you want to appear in that drawer. The same widget can live in multiple drawers.",
                }},
                { type = "note", style = "info", text = "Newly enabled widgets default to OFF in every drawer's checklist. Head to the Drawers page and tick them on for whichever drawers you want them in — they don't auto-add everywhere." },
                { type = "h2", text = "Drag-to-reorder" },
                { type = "paragraph", text = "Inside a drawer, hold any widget's title bar for ~half a second (it turns green) then drag up or down to reorder. The order is saved per drawer, so the same widget can sit at the top of one drawer and the bottom of another." },
                { type = "h2", text = "Floating widgets" },
                { type = "paragraph", text = "Toggle |cffffd700Floating|r on a widget's settings page (or right-click its title bar → Float) to detach it from the drawer. Floating widgets get their own Edit Mode frame you can drag anywhere on screen." },
                { type = "h2", text = "Collapsing widgets" },
                { type = "paragraph", text = "Click the chevron on a widget's title bar to collapse it down to just the title row. Click again to expand. Collapse state is saved per widget per drawer." },
            },
        },

        ---------------------------------------------------------------
        -- Smart Fade
        ---------------------------------------------------------------
        {
            title = "Smart Fade",
            blocks = {
                { type = "paragraph", text = "Drawer chrome (backdrop, border, pull-tab, bottom bar) fades together as a unit. Widget content stays fully visible, so quest text and the minimap are always readable." },
                { type = "table",
                  columns = { "Setting", "Range", "Default" },
                  rows = {
                      { "Fade Delay",     "0–5 s",       "1 s" },
                      { "Fade Duration",  "0.05–2 s",    "0.4 s" },
                      { "Faded Opacity",  "0–1",         "0 (invisible)" },
                      { "Combat Lock",    "on / off",    "off" },
                  },
                },
                { type = "note", style = "tip", text = "Set Faded Opacity to 0 for a truly invisible drawer. Set it to 0.3 if you'd rather have a hint of where the drawer lives." },
            },
        },

        ---------------------------------------------------------------
        -- Lock Mode
        ---------------------------------------------------------------
        {
            title = "Lock Mode",
            blocks = {
                { type = "lead", text = "Click the padlock icon on the bottom bar to lock the drawer for a perfectly clean column with no chrome." },
                { type = "h2", text = "What locking does" },
                { type = "list", items = {
                    "Drawer cannot collapse",
                    "All chrome is hidden (label, widget count, info button)",
                    "Widget title-bar space collapses so widgets pack flush",
                    "Fade settings are greyed out in the options panel",
                }},
                { type = "h2", text = "Unlocking" },
                { type = "paragraph", text = "Hover anywhere on the drawer — the lock icon reappears. Click it to unlock and restore chrome." },
                { type = "note", style = "tip", text = "Lock mode is ideal for screenshots or minimalist UIs." },
            },
        },

        ---------------------------------------------------------------
        -- Dormant Widgets
        ---------------------------------------------------------------
        {
            title = "Dormant Widgets",
            blocks = {
                { type = "lead", text = "Some widgets only show up when something interesting is happening." },
                { type = "paragraph", text = "A dormant widget registers itself only while its condition holds - queued for a dungeon, in combat - and disappears entirely otherwise: no slot, no title bar, no wasted space." },
                { type = "note", style = "info", text = "Dormant widgets still appear in the Widgets settings list marked with |cffffd700[D]|r so you can configure them while they're not visible. They obey their per-drawer toggles too — pick which drawer they show up in when their condition triggers." },
            },
        },

        ---------------------------------------------------------------
        -- Global Options
        ---------------------------------------------------------------
        {
            title = "Global Widget Options",
            blocks = {
                { type = "paragraph", text = "The |cffffd700Global Options|r sub-category lets you set a value once and have it cascade to every widget at the same time." },
                { type = "list", items = {
                    "|cffffd700Fade Title Bar|r — fade every widget's title bar with the drawer chrome",
                    "|cffffd700Fade Background|r — fade every widget's background with the drawer chrome",
                }},
                { type = "note", style = "tip", text = "Enable a global override to force its value across all widgets, regardless of each widget's individual setting. Disable the override to return each widget to its own setting." },
            },
        },

        ---------------------------------------------------------------
        -- Profiles
        ---------------------------------------------------------------
        {
            title = "Profiles",
            blocks = {
                { type = "paragraph", text = "Drawers uses BazUI's profile system. Each character can have its own profile — different drawers, different widget loadouts, different fade behaviours." },
                { type = "paragraph", text = "Open |cffffd700Settings → BazUI → Profiles|r to create, switch, copy from, reset, or delete profiles." },
                { type = "note", style = "tip", text = "One profile covers every BazUI module, so switching profiles changes Drawers, Chat and Bags together." },
            },
        },
    },
})
