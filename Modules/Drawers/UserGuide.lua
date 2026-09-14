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
        -- Widget pack (from BazWidgets)
        ---------------------------------------------------------------
        {
            title = "Widgets: Activity",
            blocks = {
                { type = "lead", text = "Twenty more widgets ship with Drawers. Turn any of them on under Drawers > Widgets; dormant ones only take a slot while they have something to show." },
                { type = "h2", text = "Dungeon Finder" },
                { type = "lead", text = "Dormant queue status panel - appears when you queue through the group finder." },
                { type = "list", items = {
                    "Role fill indicators (tank / healer / DPS) with colour-coded counts",
                    "Average wait time estimate and a live queue timer in the title bar",
                    "Dungeon name subtitle and a Leave Queue button",
                    "Title turns green on Group Found",
                }},
                { type = "h2", text = "Pull Timer" },
                { type = "lead", text = "Dormant combat-duration tracker - shows when you enter combat, disappears when it ends." },
                { type = "list", items = {
                    "Live elapsed time in a large gold display",
                    "Title-bar status mirrors the time so it reads even with the body collapsed",
                }},
                { type = "h2", text = "Hearthstone Cooldown" },
                { type = "list", items = {
                    "Dormant - appears while your Hearthstone is on cooldown",
                    "Live countdown to ready; hides the moment it clears",
                }},
                { type = "h2", text = "Reset Timers" },
                { type = "list", items = {
                    "Countdown to the next daily and weekly reset",
                    "Colour shifts from green to yellow to red as the deadline approaches",
                }},
            },
        },
        {
            title = "Widgets: Character & Gear",
            blocks = {
                { type = "h2", text = "Repair" },
                { type = "list", items = {
                    "Durability display: paper doll, damaged-slot list and durability percent",
                    "Worst-damaged slots first, colour-graded green to red; average durability in the title bar",
                    "Three paper-doll modes: icon grid, Blizzard's DurabilityFrame, or none",
                    "Optional suppression of Blizzard's default durability figure",
                }},
                { type = "h2", text = "Stats" },
                { type = "list", items = {
                    "Item level header with statue icon",
                    "Melee crit, spell crit (lowest school, as the character pane shows it), dodge and parry",
                    "Live updates on equipment and rating changes",
                }},
                { type = "h2", text = "Item Level" },
                { type = "list", items = {
                    "Headline equipped item level with your overall average as a sub-label",
                    "Headline tints yellow when better gear is sitting in your bags",
                }},
                { type = "h2", text = "Trinket Tracker" },
                { type = "list", items = {
                    "Both equipped trinkets side by side with live cooldown sweeps",
                    "Click a trinket to use it out of combat",
                }},
                { type = "h2", text = "Free Bag Slots" },
                { type = "list", items = {
                    "Empty inventory slots remaining, green when comfortable and red when nearly full",
                }},
                { type = "h2", text = "Tooltip" },
                { type = "list", items = {
                    "A docked slot that anchors the game tooltip, so item, unit and spell hovers appear inside the drawer",
                    "Sits at the drawer's bottom edge and grows upward with the tooltip",
                }},
                { type = "note", style = "info", text = "The Tooltip widget only redirects |cffffd700default-anchored|r tooltips. Addons that hardcode their own anchor keep it." },
            },
        },
        {
            title = "Widgets: Economy & Navigation",
            blocks = {
                { type = "h2", text = "Gold Tracker" },
                { type = "list", items = {
                    "Coin icon with formatted gold, silver and copper",
                    "Session change in green for gains and red for losses; compact value in the title bar",
                }},
                { type = "h2", text = "Tracked Reputation" },
                { type = "list", items = {
                    "One faction of your choice: name, standing and progress to the next level",
                    "Pick the faction in the widget's settings; the list shows every faction visible in your reputation pane",
                }},
                { type = "h2", text = "Coordinates" },
                { type = "list", items = {
                    "Live X/Y coordinates with the zone name below; compact coordinates in the title bar",
                }},
                { type = "h2", text = "Speed Monitor" },
                { type = "list", items = {
                    "Movement speed as a percentage with a progress bar",
                    "Green above 100%, white at 100%, red when slowed",
                }},
            },
        },
        {
            title = "Widgets: Utilities",
            blocks = {
                { type = "h2", text = "Note Pad" },
                { type = "list", items = { "Text area saved per character, up to 2000 characters" } },
                { type = "h2", text = "Stopwatch" },
                { type = "list", items = { "Large gold time display with Start/Pause, Reset and -1m buttons; live time in the title bar" } },
                { type = "h2", text = "To-Do List" },
                { type = "list", items = { "Type and Enter to add a task, tick to complete, X to delete; saved per character" } },
                { type = "h2", text = "Calculator" },
                { type = "list", items = { "A 5x4 calculator with colour-coded operators, equals and function keys" } },
                { type = "h2", text = "Performance and FPS" },
                { type = "list", items = {
                    "Performance: frame rate plus home and world latency, colour-coded",
                    "FPS: frame rate only, with a rolling one-minute low and high",
                }},
            },
        },
        {
            title = "Widgets: Broker Feeds",
            blocks = {
                { type = "lead", text = "Any addon that publishes a LibDataBroker feed shows up as its own drawer widget: a small icon, label and value. Bagnon, Recount, Skada, BugSack and most addons with a minimap data button qualify." },
                { type = "h2", text = "What is LibDataBroker?" },
                { type = "paragraph", text = "A shared library addons use to publish a value, a status string or an icon without deciding how it is displayed. Display addons such as Bazooka, ChocolateBar or Titan Panel arrange those feeds in bars; Drawers does the same inside the drawer." },
                { type = "h2", text = "Using feeds" },
                { type = "list", items = {
                    "Feeds appear on the Widgets page in the LibDataBroker group, named after the addon that publishes them",
                    "Enable, reorder or float them like any other widget",
                    "Click a feed widget to run the feed's own action, such as opening that addon; hover for its tooltip",
                    "Feeds that register after login are added as they appear, no reload needed",
                }},
                { type = "h2", text = "Settings" },
                { type = "paragraph", text = "|cffffd700Drawers > Broker Feeds|r has the icon and label toggles, the placeholder shown before a feed has a value, and whether newly seen feeds start enabled. |cffffd700/bwd feeds|r lists every registered feed; |cffffd700/bwd feeds rescan|r rebuilds any that were missed." },
                { type = "note", style = "info", text = "BazUI does not include LibDataBroker itself. Feeds exist only when another addon publishes them, and that addon brings the library along." },
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
