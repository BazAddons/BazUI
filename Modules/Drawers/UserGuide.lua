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
                { type = "note", text = "|cffffd700Open it with|r /bwd, or Options > AddOns > BazUI > Drawers." },
            },
        },

        {
            title = "The drawer itself",
            blocks = {
                { type = "h3", text = "Opening and closing it" },
                { type = "paragraph", text = "A pull tab sits on the screen edge. Click it and the drawer slides on or off. When it is closed, an invisible strip along the edge brings the tab back when your cursor gets near - |cffffd700Reveal the tab within|r sets how near." },
                { type = "h3", text = "Layout" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Screen side", "Left or right. The tab, the direction it slides and the edge strip all follow." },
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
                    "It cannot be closed or slid away.",
                    "The chrome is hidden - the label, the widget count, the info button.",
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
                { type = "paragraph", text = "You can have several drawers, each with its own name, icon and set of widgets. They appear as tabs along the top of the drawer; click one to switch." },
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
                { type = "note", text = "A widget you have just switched on starts off in every drawer's list. It does not add itself everywhere and leave you finding it later - go and tick it where you want it." },
                { type = "h3", text = "Reordering" },
                { type = "paragraph", text = "Hold a widget's title bar for about half a second - it turns green - then drag it up or down. The order is per drawer, so the same widget can sit at the top of one and the bottom of another." },
                { type = "h3", text = "Each widget's own settings" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Floating", "Takes it out of the drawer and gives it a frame of its own you can drag anywhere. Right-click the title bar does the same." },
                    { "Collapsed", "Folded down to its title row. The chevron on the title bar toggles it, and it is remembered per drawer." },
                    { "Pin to the bottom of the drawer", "It stays at the bottom whatever else is added above it." },
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
                    { "Minimap Buttons", "Every addon's minimap button collected into one row instead of orbiting the map." },
                    { "Quest Tracker", "Your tracked quests, in the drawer instead of floating over the world." },
                    { "Zone Text", "Where you are." },
                    { "Info Bar", "The clock, the calendar and tracking, in one row." },
                    { "Tooltip", "A slot that anchors the game's tooltip, so hovering an item or a unit shows it inside the drawer. It sits at the bottom and grows upward." },
                } },
                { type = "note", text = "The Tooltip widget only catches tooltips that were going to appear at the default place. An addon that insists on its own anchor keeps it." },
            },
        },

        {
            title = "Widgets: what is happening",
            blocks = {
                { type = "h3", text = "Dungeon Finder" },
                { type = "paragraph", text = "Appears when you queue. Shows which roles are filled, an estimated wait, a live timer in the title bar, what you queued for, and a button to leave. The title turns green when the group is found." },
                { type = "h3", text = "Pull Timer" },
                { type = "paragraph", text = "Appears when you enter combat and goes when it ends, counting how long the fight has run. The title bar carries the same number, so it still reads with the body collapsed." },
                { type = "h3", text = "Hearthstone Cooldown" },
                { type = "paragraph", text = "Appears while your hearthstone is on cooldown, counting down, and goes the moment it is ready." },
                { type = "h3", text = "Reset Timers" },
                { type = "paragraph", text = "How long until the next daily and weekly reset, shifting from green through yellow to red as the deadline comes up." },
            },
        },

        {
            title = "Widgets: your character",
            blocks = {
                { type = "h3", text = "Repair" },
                { type = "paragraph", text = "Your durability: a paper doll, the damaged slots worst-first and graded green to red, and the average in the title bar. Three ways to draw the doll - an icon grid, the game's own durability figure, or none - and a switch to hide the game's version if you would rather only see this one." },
                { type = "h3", text = "Stats" },
                { type = "paragraph", text = "Item level, melee crit, spell crit taken from your lowest school the way the character pane does it, dodge and parry. Updates as you change gear." },
                { type = "h3", text = "Item Level" },
                { type = "paragraph", text = "What you are wearing, with your overall average underneath. The headline turns yellow when there is something better sitting in your bags." },
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
                { type = "paragraph", text = "What you are carrying, and what this session has cost or made you - green up, red down - with a compact figure in the title bar." },
                { type = "h3", text = "Tracked Reputation" },
                { type = "paragraph", text = "One faction of your choosing: its name, your standing, and how far through it you are. Pick it in the widget's settings, from everything your reputation pane knows about." },
                { type = "h3", text = "Coordinates" },
                { type = "paragraph", text = "Where you are standing, with the zone underneath and the numbers repeated in the title bar." },
                { type = "h3", text = "Speed Monitor" },
                { type = "paragraph", text = "How fast you are moving as a percentage, with a bar. Green above normal, white at it, red when something has slowed you." },
            },
        },

        {
            title = "Widgets: odds and ends",
            blocks = {
                { type = "table", columns = { "Widget", "What it does" }, rows = {
                    { "Note Pad", "Somewhere to write things down, saved per character." },
                    { "To-Do List", "Type and press Enter to add, tick to complete, X to remove. Per character." },
                    { "Stopwatch", "Start, pause, reset, and a minute off. The time reads in the title bar too." },
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
                { type = "paragraph", text = "|cffffd700Drawers > Broker Feeds|r has the icon and label switches, what to show before a feed has a value, and whether a newly seen feed starts on. |cffffd700/bwd feeds|r lists them in chat and |cffffd700/bwd feeds rescan|r rebuilds any that were missed." },
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
                    { "/bwd open <name>", "Switches to a particular drawer by name." },
                    { "/bwd feeds", "Lists every LibDataBroker feed in chat." },
                    { "/bwd feeds rescan", "Looks again for feeds that were missed." },
                } },
            },
        },
    },
})
