-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Drawers User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Drawers", {
    title = "Drawers",
    intro = "A panel down the side of the screen holding a stack of small "
        .. "readouts, instead of a dozen little frames scattered everywhere.",

    pages = {
        {
            title = "What it does",
            blocks = {
                { type = "paragraph", text = "The drawer sits against the left or right edge of your screen and holds a column of widgets. It slides away when you are not using it and the chrome around it fades, leaving what is in it readable." },
                { type = "paragraph", text = "The minimap lives here, along with the minimap buttons every addon adds, the quest tracker, and about twenty small readouts - a clock, coordinates, your gold, durability, free bag slots, a notepad, a calculator. Anything publishing a LibDataBroker feed turns up as a widget too." },
                { type = "note", style = "tip", text = "|cffffd700You do not have to have a drawer at all.|r Turn |cffffd700Use drawers|r off on the General page and every widget you switch on sits loose on the screen instead, wherever you drag it. See |cffffd700No drawer at all|r below." },
                { type = "note", text = "|cffffd700Open it with|r /bwd, or Options > AddOns > BazUI > Drawers." },
            },
        },

        {
            title = "No drawer at all",
            blocks = {
                { type = "paragraph", text = "|cffffd700Use drawers|r, at the top of the General page, is the whole feature. On, your widgets live in a drawer at the side of the screen. Off, each one sits wherever you drag it, and the drawer, its tabs and its edge strip are not drawn." },
                { type = "paragraph", text = "It is not a separate mode with its own rules. A widget in a drawer and a widget on the screen were always two states of the same thing, and with no drawer there is simply nothing to be in - so every widget you switch on is loose, and the Widgets page is the whole of the setup." },
                { type = "h3", text = "Working that way" },
                { type = "list", items = {
                    "Switch a widget on from the |cffffd700Widgets|r page.",
                    "Open |cffffd700BazUI Edit Mode|r and drag it where you want it.",
                    "|cffffd700Scale|r, on the same panel, decides how big it draws. In a drawer that was the drawer's job, so it only applies out here.",
                } },
                { type = "note", text = "Everything about the drawer grays out while it is off, and your drawers are kept exactly as they were. Switching it back on gives you them back, widgets and all." },
                { type = "h3", text = "Size" },
                { type = "paragraph", text = "A docked widget is scaled to fill the drawer's width, which is why it never had a size of its own. Loose on the screen there is nothing to fill, so each one carries a |cffffd700Scale|r of its own - on its page under Widgets, and on its BazUI Edit Mode panel, both the same setting." },
                { type = "paragraph", text = "|cffffd700Fade when not hovered|r is the same idea for visibility. A docked widget fades with its drawer; a floating one has no drawer to fade with, so it carries its own switch and its own |cffffd700Faded opacity|r. Zero hides it completely until the cursor finds it, which is what you want for something you reach for twice an hour." },
                { type = "note", text = "Edit Mode always draws a floating widget solid, whatever its fade says. A widget you cannot see is a widget you cannot drag." },
                { type = "note", text = "The minimap is the exception, and deliberately: it has its own |cffffd700Map Scale|r, because the map has to stay concentric with the ring drawn around it, so it scales the map rather than the frame holding it. It gets that one control and not the general one." },
            },
        },

        {
            title = "The drawer itself",
            blocks = {
                { type = "h3", text = "Opening and closing it" },
                { type = "paragraph", text = "A strip of tabs runs down the inner edge of the drawer, one per drawer you have, each wearing its own icon. |cffffd700Click the tab of the drawer you are looking at|r and it slides away; click it again and it comes back." },
                { type = "paragraph", text = "While the drawer is open only that one tab is drawn, because the others would be four icons asking to be pressed for no reason. Closed, they all appear, so switching to another drawer is one click from anywhere." },
                { type = "paragraph", text = "An invisible strip along the screen edge brings a faded tab back when your cursor gets near - |cffffd700Reveal the tab within|r sets how near." },
                { type = "h3", text = "Layout" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Screen side", "Left or right. The tabs, the direction it slides and the edge strip all follow." },
                    { "Width", "How wide the column is. Every widget in it resizes to match." },
                    { "Space between widgets", "The gap between one widget and the next." },
                } },
                { type = "h3", text = "Appearance" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Background opacity", "How solid the panel behind the widgets is." },
                    { "Frame opacity", "The chrome - the border, the tab, the bottom bar." },
                } },
            },
        },

        {
            title = "Fading",
            blocks = {
                { type = "paragraph", text = "The chrome fades as one thing - backdrop, border, pull tab, bottom bar - and |cffffd700what is inside stays fully visible|r. Quest text and the minimap are readable whether or not you have the cursor anywhere near them." },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Fade when the cursor leaves", "The whole behavior, on one switch." },
                    { "Faded opacity", "How much is left when it has faded. 0 is genuinely invisible; around 30% leaves a hint of where the drawer is." },
                    { "Fade after", "How long it waits once your cursor has left." },
                    { "Fade takes", "How long the fade itself runs." },
                    { "Stay fully visible in combat", "No fading while you are fighting." },
                    { "Fade the tab while the drawer is closed", "Whether the tab itself fades away too, or stays put as something to aim at." },
                    { "Reveal the tab within", "How close the cursor has to get to the edge to bring a faded tab back. Raise it if the tab is hard to find." },
                } },
            },
        },

        {
            title = "Locking it",
            blocks = {
                { type = "paragraph", text = "The padlock on the bottom bar locks the drawer for a clean column with no chrome around it." },
                { type = "list", items = {
                    "It cannot be closed or slid away, and hovering the screen edge no longer brings it out.",
                    "The chrome is hidden - the label, the widget count, the settings button.",
                    "Widget title bars collapse out of the way so the widgets pack flush against each other.",
                    "The fade settings gray out, since there is nothing left to fade.",
                } },
                { type = "paragraph", text = "Hover anywhere on the drawer and the padlock comes back. Click it to unlock." },
                { type = "note", text = "Worth it for screenshots, and for anyone who wants the readouts without the furniture." },
            },
        },

        {
            title = "More than one drawer",
            blocks = {
                { type = "paragraph", text = "You can have several drawers, each with its own name, icon and set of widgets. They are the tabs down the drawer's inner edge; click another one to switch to it." },
                { type = "h3", text = "Making and managing them" },
                { type = "list", items = {
                    "|cffffd700Drawers|r page > |cffffd700New drawer|r.",
                    "Each has a |cffffd700Name|r and a |cffffd700Choose icon|r for its tab.",
                    "|cffffd700Widgets in this drawer|r is the list of what it holds.",
                    "Delete any of them except the last - there is always at least one.",
                } },
                { type = "note", text = "Switching drawers is something you do, not something that happens to you. There is no automatic switching by zone or content, and a drawer never changes under you mid-fight." },
            },
        },

        {
            title = "Choosing widgets",
            blocks = {
                { type = "paragraph", text = "It is two steps, and they do different jobs." },
                { type = "list", items = {
                    "|cffffd700The Widgets page|r switches a widget on at all. One that is off is gone everywhere - no drawer slot, no floating frame, and nothing running behind the scenes.",
                    "|cffffd700The Drawers page|r decides which drawers each one appears in. The same widget can be in more than one.",
                } },
                { type = "note", text = "The drawer you started with holds |cffffd700whatever is switched on|r, so a widget you have just enabled appears in it straight away. A drawer you made yourself starts empty, and you tick into it the ones you want." },
                { type = "note", style = "warning", text = "A widget that is switched on but is |cffffd700in no drawer|r has nowhere to be drawn, so it is not drawn. If one has gone missing while drawers are on, that is the first thing to check: |cffffd700Drawers|r, then |cffffd700Widgets in this drawer|r." },
                { type = "h3", text = "The buttons on a title bar" },
                { type = "paragraph", text = "Put your cursor on a widget's title bar and its status text is replaced by four controls." },
                { type = "table", columns = { "Button", "What it does" }, rows = {
                    { "Up / Down arrows", "Moves the widget one place in the drawer." },
                    { "Red cross", "Takes it off this drawer. It keeps all its settings, and the Drawers page puts it back." },
                    { "The chevron", "Shows which way the widget is folded. The fold itself is a click anywhere on the title bar." },
                } },
                { type = "paragraph", text = "The controls are hidden while the drawer is locked, and they do not appear until the cursor is on the bar, so a still drawer stays a readout rather than a row of buttons." },
                { type = "h3", text = "Reordering by dragging" },
                { type = "paragraph", text = "Hold a widget's title bar for about half a second - it turns green - then drag it up or down. The arrows above do the same thing and are easier to find. The order is per drawer, so the same widget can sit at the top of one and the bottom of another." },
                { type = "h3", text = "Each widget's own settings" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Floating", "Takes it out of the drawer and gives it a frame of its own you can drag anywhere." },
                    { "Collapsed", "Folded down to its title row. A short click on the title bar toggles it, and it is remembered per drawer." },
                    { "Pin to the bottom of the drawer", "Pinned widgets stack up from the bottom edge instead of being pushed down by whatever is added above them." },
                    { "Fade the title bar with the drawer", "Whether its title bar counts as chrome." },
                    { "Fade the background with the drawer", "The same for its background." },
                } },
                { type = "h3", text = "One setting for all of them" },
                { type = "paragraph", text = "|cffffd700All widgets|r on the General page forces a value on every widget at once, for the fade settings above. While an override is on, that setting is grayed out on each widget's own page - so it is always clear which one is deciding. Turn it off and every widget goes back to its own answer." },
            },
        },

        {
            title = "Widgets that come and go",
            blocks = {
                { type = "paragraph", text = "Some widgets only exist while there is something to say. One of these registers itself when its condition starts - you queued, you entered combat, your hearthstone is on cooldown - and disappears entirely when it stops. No slot, no title bar, no space held open for something that is not there." },
                { type = "paragraph", text = "They still appear in the Widgets list marked |cffffd700[D]|r so you can set them up while they are not showing, and they obey their per-drawer switches like anything else." },
            },
        },

        {
            title = "Widgets: the interface",
            blocks = {
                { type = "table", columns = { "Widget", "What it shows" }, rows = {
                    { "Minimap", "The minimap in a frame of its own, sized to the drawer." },
                    { "Minimap Buttons", "Every addon's minimap button gathered into a grid instead of orbiting the map." },
                    { "Quest Tracker", "Your tracked quests, in the drawer instead of floating over the world." },
                    { "Zone", "Where you are." },
                    { "Info Bar", "The clock, the calendar, tracking and your mail, in one row." },
                    { "Tooltip", "A slot that anchors the game's tooltip, so hovering an item or a unit shows it inside the drawer. It sits at the bottom and grows upward." },
                } },
                { type = "note", text = "The Tooltip widget only catches tooltips that were going to appear at the default place. An addon that insists on its own anchor keeps it." },
                { type = "h3", text = "Minimap" },
                { type = "paragraph", text = "The map itself, not a copy of it, moved into the drawer." },
                { type = "list", items = {
                    "|cffffd700The mouse wheel zooms|r, which is why the zoom buttons are hidden by default.",
                    "|cffffd700Shift and right click opens the calendar|r, which is otherwise homeless once the game's minimap cluster is gone.",
                    "Every other click does what it always did, including the ping.",
                } },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Frame Style", "BazUI is the brass ring from the WoW Forever logo, Blizzard Default keeps the game's own, and None leaves the map bare." },
                    { "Map Scale", "How much of the drawer's width the map takes. Below 100% it sits smaller and centered. For a bigger map, widen the drawer." },
                    { "Hide Day/Night Indicator", "The sun and moon button on the ring." },
                    { "Hide Zoom Buttons", "The plus and minus. The wheel still zooms." },
                } },
                { type = "h3", text = "Minimap Buttons" },
                { type = "paragraph", text = "Addon buttons are adopted at login and whenever an addon finishes loading. |cffffd700Button Order|r on its settings page moves any of them a place at a time." },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Button Frame", "BazUI puts every adopted button in the same brass ring with a round icon, so buttons from different addons match. Blizzard Default leaves each addon's own art alone." },
                    { "Icon Backdrop", "A solid dark disc behind each icon, so buttons with see-through artwork look as solid as the rest. Used with the BazUI frame only." },
                    { "Re-scan Minimap", "Adopt any button that slipped through. Worth a click after loading a new addon." },
                } },
                { type = "h3", text = "Quest Tracker" },
                { type = "table", columns = { "You do this", "It does this" }, rows = {
                    { "Left-click a quest", "Tracks it and opens the map at its details. Clicking the one already showing closes the map again." },
                    { "Right-click a quest", "Stops tracking it." },
                    { "Left or right-click an achievement or recipe", "The same two things, for that kind of thing." },
                } },
                { type = "note", text = "Clicks do nothing while you are fighting. Every one of them ends in the game refreshing its map pins, which it will not let an addon cause in combat." },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Max Height", "Caps the widget's height. Quests past that scroll on the mouse wheel." },
                    { "Hide Default Tracker", "Hides the game's own objective tracker. Off, you get both." },
                    { "TomTom Waypoint", "With TomTom installed, points its arrow at the tracked quest's next objective." },
                    { "Zygor Waypoint", "The same for Zygor's arrow." },
                } },
            },
        },

        {
            title = "Widgets: what is happening",
            blocks = {
                { type = "h3", text = "Dungeon Finder" },
                { type = "paragraph", text = "Appears when you queue. Shows which roles are filled, an estimated wait, a live timer in the title bar, what you queued for, and a button to leave. The title turns green when the group is found." },
                { type = "h3", text = "Pull Timer" },
                { type = "paragraph", text = "Appears when you enter combat and goes when it ends, counting how long the fight has run. The title bar carries the same number, so it still reads with the body collapsed." },
                { type = "h3", text = "Hearthstone CD" },
                { type = "paragraph", text = "Appears while your hearthstone is on cooldown, counting down, and goes the moment it is ready." },
                { type = "h3", text = "Reset Timers" },
                { type = "paragraph", text = "How long until the next daily and weekly reset, shifting from green through yellow to red as the deadline comes up." },
            },
        },

        {
            title = "Widgets: your character",
            blocks = {
                { type = "h3", text = "Repair" },
                { type = "paragraph", text = "Your durability: a paper doll, the damaged slots worst-first and graded green to red, and the average in the title bar. Three ways to draw the doll - |cffffd700Custom|r slot icons, |cffffd700Blizzard|r's own durability figure, or |cffffd700None|r for the list alone. Clicking the widget opens the character sheet." },
                { type = "h3", text = "Stats" },
                { type = "paragraph", text = "Item level, melee crit, spell crit taken from your lowest school the way the character pane does it, dodge and parry. Updates as you change gear." },
                { type = "h3", text = "Item Level" },
                { type = "paragraph", text = "What you are wearing, with your overall average underneath. The headline turns yellow when there is something better sitting in your bags. |cffffd700Show iLevel on Item Slots|r also writes each item's level into the corner of its slot on the character pane, colored by quality." },
                { type = "h3", text = "Trinket Tracker" },
                { type = "paragraph", text = "Both equipped trinkets side by side with their cooldowns running. Click one to use it, out of combat." },
                { type = "h3", text = "Free Bag Slots" },
                { type = "paragraph", text = "How much room you have left, green while that is comfortable and red when it is not." },
            },
        },

        {
            title = "Widgets: money and place",
            blocks = {
                { type = "h3", text = "Gold Tracker" },
                { type = "paragraph", text = "What you are carrying, and what this session has cost or made you - green up, red down - with a compact figure in the title bar. |cffffd700Show silver|r and |cffffd700Show copper|r drop those two for a cleaner line once your gold runs to five figures." },
                { type = "h3", text = "Tracked Reputation" },
                { type = "paragraph", text = "One faction of your choosing: its name, your standing, and how far through it you are. Pick it in the widget's settings, from everything your reputation pane knows about, and |cffffd700Clear Selection|r stops tracking any." },
                { type = "h3", text = "Coordinates" },
                { type = "paragraph", text = "Where you are standing, with the zone underneath and the numbers repeated in the title bar." },
                { type = "h3", text = "Speed" },
                { type = "paragraph", text = "How fast you are moving as a percentage, with a bar. Green above normal, white at it, red when something has slowed you." },
            },
        },

        {
            title = "Widgets: odds and ends",
            blocks = {
                { type = "table", columns = { "Widget", "What it does" }, rows = {
                    { "Note Pad", "Somewhere to write things down, saved per character." },
                    { "To-Do", "Type and press Enter to add, tick to complete, X to remove. Per character." },
                    { "Stopwatch", "Start, which is also the pause, then Reset and a minute off. The time reads in the title bar too." },
                    { "Calculator", "A calculator." },
                    { "Performance", "Frame rate with your home and world latency, color-coded." },
                    { "FPS", "Frame rate on its own, with a rolling low and high over the last minute." },
                } },
            },
        },

        {
            title = "Widgets from other addons",
            blocks = {
                { type = "paragraph", text = "Any addon publishing a |cffffd700LibDataBroker|r feed becomes a widget here: an icon, a label and a value. Most addons with a minimap data button qualify." },
                { type = "paragraph", text = "LibDataBroker is a shared library an addon uses to publish a number or a status without deciding how it should be shown. Display addons arrange those feeds in bars; this arranges them in the drawer." },
                { type = "list", items = {
                    "They appear on the Widgets page grouped together, named after the addon that publishes them.",
                    "Switch them on, reorder them or float them like anything else here.",
                    "Click one to do whatever the feed does - usually open its addon. Hover it for its tooltip.",
                    "A feed that registers after you have logged in is picked up as it appears, with no reload.",
                } },
                { type = "paragraph", text = "|cffffd700Drawers > Broker Feeds|r has the icon and label switches, what to show before a feed has a value, and whether a newly seen feed starts on. It also carries |cffffd700Rescan feeds|r and |cffffd700List feeds in chat|r, which are the same two things as |cffffd700/bwd feeds rescan|r and |cffffd700/bwd feeds|r." },
                { type = "note", text = "BazUI does not ship LibDataBroker. Feeds exist only when some other addon publishes them, and that addon brings the library with it." },
            },
        },

        {
            title = "Profiles",
            blocks = {
                { type = "paragraph", text = "Your drawers, what is in them, and how they behave all live in your BazUI profile. |cffffd700One profile covers every module|r, so switching it changes Drawers along with Bars, Chat, Bags and the rest together." },
                { type = "paragraph", text = "Profiles are created, switched, copied and deleted on |cffffd700BazUI > Profiles|r." },
            },
        },

        {
            title = "Slash commands",
            blocks = {
                { type = "table", columns = { "Command", "What it does" }, rows = {
                    { "/bwd", "Opens the Drawers settings." },
                    { "/bwd toggle", "Opens or closes the drawer." },
                    { "/bwd show", "Opens it." },
                    { "/bwd hide", "Closes it." },
                    { "/bwd list", "Lists your drawers and marks the one you are on." },
                    { "/bwd open <name>", "Switches to a particular drawer by name. With no name it lists the ones you can ask for." },
                    { "/bwd feeds", "Lists every LibDataBroker feed in chat." },
                    { "/bwd feeds rescan", "Looks again for feeds that were missed." },
                    { "/bwd fade", "Prints what each widget's title bar is doing about fading, for when one will not fade with the rest." },
                    { "/bwd float", "Prints where each loose widget thinks it should be against where it actually is." },
                    { "/bwd map", "Prints everything about where the minimap has got to, for when it is not where you expect." },
                    { "/bwd settings", "Opens the settings page. Every BazUI command takes this, and |cffffd700help|r." },
                } },
            },
        },
    },
})
