-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Bars User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

-- Screenshots live in Media/ as 16:9 PNGs. The client only finds a PNG
-- when the path carries the extension - without it SetTexture looks for
-- BLP and TGA and misses in silence.
local IMG_W, IMG_H = 640, 360

local function Image(file, caption)
    return {
        type = "image",
        texture = "Interface\\AddOns\\BazUI\\Modules\\Bars\\Media\\" .. file .. ".png",
        width = IMG_W,
        height = IMG_H,
        caption = caption,
    }
end

-- Image beside text. A width between 0 and 1 is read as a fraction of
-- the page; the height follows from 16:9.
local function ImageRow(file, caption, blocks, side)
    return {
        type = "imageRow",
        texture = "Interface\\AddOns\\BazUI\\Modules\\Bars\\Media\\" .. file .. ".png",
        imageWidth = 0.5,
        imageSide = side or "left",
        caption = caption,
        blocks = blocks,
    }
end

BazUI:RegisterUserGuide("Bars", {
    title = "Bars",
    intro = "Action bars you build yourself, holding anything you can pick "
        .. "up, and not spending a single one of the game's own action slots.",

    pages = {
        {
            title = "What it does",
            blocks = {
                { type = "paragraph", text = "These bars sit alongside the game's own rather than replacing them, and they do not use the 120 action slots the game gives you. The same spell can be on a default bar and on one of these at the same time; you never have to move something to make room." },
                Image("one-bar", "One bar at its largest - 24 by 24 is 576 buttons. Nothing stops you having more than one."),
                { type = "list", items = {
                    "|cffffd700As many bars as you want|r, each up to 24 by 24.",
                    "|cffffd700The game's own look|r - the same art, cooldown sweeps, proc glows and range tinting.",
                    "|cffffd700Quick Keybind|r: hover a button, press a key, done.",
                    "|cffffd700Macro text per button|r, with #showtooltip.",
                    "|cffffd700Flyouts|r - one slot holding a group of actions.",
                    "|cffffd700Import and export|r a bar as a string you can share.",
                    "|cffffd700Masque|r skinning per bar, if you have Masque.",
                } },
                { type = "note", text = "|cffffd700Open it with|r /bb or /bazbars, or Options > AddOns > BazUI > Bars." },
            },
        },

        {
            title = "Making a bar",
            blocks = {
                ImageRow("bar-create-button", "The Create button sits at the bottom of the Edit Mode panel.", {
                    { type = "list", items = {
                        "Open Edit Mode.",
                        "Click |cffffd700Create|r at the bottom of the panel and pick an action bar. Every kind of thing BazUI can make is on that one menu.",
                        "The new bar appears in the middle of the screen.",
                        "Drag it where you want it, then click it to open its settings.",
                    } },
                }),
                { type = "note", text = "|cffffd700/bb create|r does the same from chat, and takes a size: |cffffd700/bb create 6 2|r for six across and two down." },
                { type = "paragraph", text = "Each bar is its own thing - its own size, position, arrangement and contents. Make as many as the screen will hold." },
            },
        },

        {
            title = "Putting things on it",
            blocks = {
                { type = "paragraph", text = "Drag almost anything onto a slot." },
                { type = "table", columns = { "What", "Notes" }, rows = {
                    { "Spells", "From your spellbook." },
                    { "Items", "From your bags. The button shows how many you have, and the number changes as you loot and use them." },
                    { "Macros", "From the macro window. The name shows under the icon." },
                    { "Equipment sets", "From the character pane." },
                    { "Mounts", "On clients with a mount journal, including Random Favorite Mount." },
                } },
                ImageRow("item-tracking", "Item buttons count what is in your bags, live.", {
                    { type = "paragraph", text = "An item button's count updates the moment your bags change - herbs and ore while you are farming, potions through a fight, reagents before you set out." },
                }, "right"),
                { type = "h3", text = "Taking things off" },
                { type = "list", items = {
                    "|cffffd700Shift and drag|r a button off the bar.",
                    "|cffffd700Shift and right-click|r clears it where it sits.",
                } },
                { type = "note", text = "With the game's |cffffd700cast on key down|r switched on, a plain click-drag fires the ability before the drag has started. Shift and drag to rearrange in that case." },
                { type = "paragraph", text = "If things come off your bars by accident, |cffffd700Drag buttons only while Shift is held|r on the General page makes a plain drag do nothing - Shift and drag still moves a button, and dropping something new onto a bar still works. A bar's own |cffffd700Lock buttons|r stops dragging on that bar entirely." },
            },
        },

        {
            title = "Filled in for you",
            blocks = {
                { type = "paragraph", text = "A new character logs in with its abilities already placed: forms, stances, auras and stealth on the first side bar, everything else on the main one. After that:" },
                { type = "list", items = {
                    "A spell you learn takes the first empty slot.",
                    "A new rank of something you already have just starts casting from the same button.",
                    "Anything you no longer know is cleared at login and after a respec.",
                } },
                { type = "paragraph", text = "The game's stance bar is hidden, since your stances are on a bar of your own. All of that has a switch on the |cffffd700General|r page, and |cffffd700Fill empty slots with my unplaced abilities|r there runs the same pass on a character that already exists." },
            },
        },

        {
            title = "Flyouts",
            blocks = {
                { type = "paragraph", text = "One slot holding several actions. Left-click casts one of them; right-click opens the rest." },
                { type = "paragraph", text = "It is for the group of things you want near at hand but not spread across six slots: portals and teleports, aspects, summons, totems, your conjured food and water. The slot shows whichever action it is set to cast, with a small arrow marking the way the grid will open." },
                { type = "h3", text = "Making one" },
                { type = "list", items = {
                    "|cffffd700Shift and right-click|r an empty slot and choose to make a flyout there.",
                    "The grid opens at once - drag spells, items or macros into its squares.",
                    "|cffffd700Right-click|r the slot any time to open or close it.",
                } },
                { type = "paragraph", text = "Anything a bar slot understands can go in a flyout. Where you drop something is where it stays, and a square left empty stays empty, so you can group things the way you think of them." },
                { type = "h3", text = "What the button casts" },
                { type = "table", columns = { "You do this", "It does this" }, rows = {
                    { "Left-click the slot", "Casts whatever it is currently set to." },
                    { "Left-click a square", "Casts that one, and the slot switches to it." },
                    { "Right-click a square", "Pins it, so the slot always casts that one." },
                    { "Right-click it again", "Unpins, back to whatever you used last." },
                    { "Drag a square out", "Takes that action off the grid." },
                } },
                { type = "h3", text = "Shape" },
                { type = "paragraph", text = "|cffffd700Shift and right-click|r the slot for its menu: which way the grid opens, how many rows and columns it has, and whether the button casts the pinned action or the last one you used. The same menu clears the slot." },
                { type = "note", text = "A flyout near the bottom of the screen wants to open upward and one near the right edge wants to open left. The arrow always shows which way it will go." },
                { type = "paragraph", text = "A spell you no longer know is dropped from the grid and the rest is left alone, so unlearning one ability never costs you the whole arrangement. If nothing usable is left, the slot clears itself." },
            },
        },

        {
            title = "Setting a bar up",
            blocks = {
                ImageRow("bar-settings-popup", "A bar's settings in Edit Mode. The selected bar is highlighted; everything about it is on this panel.", {
                    { type = "paragraph", text = "In Edit Mode, click a bar to select it, then click again for its settings. Everything about that one bar is here - the same settings as the full options page, in reach of the bar you are looking at." },
                }),
                { type = "h3", text = "Layout" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Name", "What the bar is called in the lists and menus." },
                    { "Orientation", "Across or down." },
                    { "Icons per row / Rows", "The size of the grid, up to 24 by 24." },
                } },
                { type = "h3", text = "Appearance" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Icon size", "How large the buttons are." },
                    { "Icon padding", "The gap between them." },
                    { "Bar opacity", "How solid the whole bar is." },
                    { "Side endcaps", "The art on each end of the bar, and whether there is any." },
                    { "Scale endcaps with the bar's height", "Keeps the caps in proportion as the buttons grow." },
                    { "Endcap size", "Their size, when they are not scaling themselves." },
                } },
                { type = "h3", text = "Visibility" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Always show buttons", "Empty slots stay visible instead of disappearing." },
                    { "Show slot art", "The frame behind each button." },
                    { "Fade until hovered", "The bar fades out until your cursor is on it." },
                    { "Show when", "A macro condition deciding when the bar exists at all. Empty means always." },
                } },
                { type = "code", text = "[combat] show; hide" },
                { type = "paragraph", text = "Anything the game's macro conditions understand works here - |cffffd700[stance:1]|r, |cffffd700[group]|r, |cffffd700[mod:shift]|r, |cffffd700[stealth]|r and the rest." },
                { type = "h3", text = "Behavior" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Lock buttons", "Nothing can be dragged off or swapped." },
                    { "Right-click casts on yourself", "A right-click uses a helpful spell or an item on you." },
                    { "Click-through", "The buttons ignore the mouse entirely. Cooldowns, range tinting and glows still show - it is for a bar you watch rather than press." },
                } },
                { type = "h3", text = "Actions" },
                { type = "table", columns = { "Action", "What it does" }, rows = {
                    { "Revert Changes", "Undoes everything since you selected the bar." },
                    { "Reset Position", "Back to the middle of the screen." },
                    { "Quick Keybind Mode", "Binding keys by hovering - see the next page." },
                    { "BazUI Bars Settings", "Opens the full options page." },
                    { "Export Bar Config", "The bar as a string you can share." },
                    { "Duplicate This Bar", "A copy with every button on it." },
                    { "Delete This Bar", "Gone, after it asks." },
                } },
                ImageRow("bar-editor", "The Bar Options page - the same settings with every bar in one place.", {
                    { type = "paragraph", text = "|cffffd700Options > AddOns > BazUI > Bars > Bar Options|r is the same settings laid out fully, with a dropdown at the top to pick a bar and New, Duplicate and Delete beside it." },
                }, "right"),
            },
        },

        {
            title = "Keybinds",
            blocks = {
                ImageRow("quick-keybinding", "Quick Keybind Mode: hover a button, press the key you want.", {
                    { type = "paragraph", text = "|cffffd700Quick Keybind Mode|r is on a bar's Actions list. Turn it on, hover a button, and press the key you want on it. Escape clears a binding." },
                    { type = "list", items = {
                        "Keys and modifier combinations - Shift+E, Ctrl+1, and so on.",
                        "Middle mouse, mouse 4 and mouse 5.",
                        "Left and right clicks are reserved; they press the button.",
                    } },
                }),
                { type = "note", text = "If the key you press is already bound to something of the game's, that binding is taken and you are told in chat which one. Clearing the BazUI binding later gives it back." },
                { type = "paragraph", text = "|cffffd700Show keybind text|r on the General page decides whether the key appears in the corner of the button." },
            },
        },

        {
            title = "Settings for every bar",
            blocks = {
                { type = "paragraph", text = "The |cffffd700General|r page holds what applies across the module rather than to one bar." },
                { type = "h3", text = "Blizzard UI" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Hide Blizzard's main action bar", "Once your own bars hold everything, the stock one is in the way." },
                    { "Hide only its art", "The bar's buttons stay, the frame around them goes." },
                    { "Hide Blizzard's stance bar", "On by default, since your stances are placed on a bar of your own." },
                    { "Show Blizzard's experience bar", "And the reputation bar, each on its own switch - for people who would rather keep them than use the Unit Frames versions." },
                } },
                { type = "h3", text = "Buttons" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Tint the whole button when out of range", "Rather than just the key text." },
                    { "Show keybind text", "The key in the corner." },
                    { "Show macro names", "The name under the icon." },
                    { "Drag buttons only while Shift is held", "Stops things coming off your bars by accident." },
                    { "Show tooltips", "And where they appear, on the setting below it." },
                } },
                { type = "h3", text = "All bars" },
                { type = "paragraph", text = "An override that forces one value on every bar at once - icon size, opacity, slot art and the like. A bar's own version of that setting is grayed out while the override is on, so it is always clear which one is deciding." },
                { type = "h3", text = "Abilities" },
                { type = "paragraph", text = "The switches behind |cffffd700Filled in for you|r: placing a new character's abilities, adding newly learned spells, and a button that fills empty slots on a character you already have." },
                { type = "h3", text = "Combat" },
                { type = "paragraph", text = "|cffffd700BazUI bars always cast on key release.|r |cffffd700Blizzard bars cast on key down|r is the game's own setting, put here so both are in one place rather than in two." },
            },
        },

        {
            title = "Moving bars around",
            blocks = {
                { type = "list", items = {
                    "Drag to move.",
                    "Snap to the grid.",
                    "Arrow keys nudge a pixel at a time.",
                    "A selected bar wears the same highlight the game puts on its own frames, so a screen of mixed bars reads as one thing.",
                } },
                { type = "note", text = "Positions are saved in your BazUI profile. Switch profiles and every bar moves to where that profile left it." },
            },
        },

        {
            title = "Sharing a bar",
            blocks = {
                { type = "paragraph", text = "A bar exports as a string carrying its whole arrangement: size, every button, every setting. Paste it back on any character to rebuild it." },
                { type = "h3", text = "Out" },
                { type = "list", items = {
                    "Edit Mode, click the bar, Actions, |cffffd700Export Bar Config|r.",
                    "Or |cffffd700/bb export <id>|r.",
                    "A dialog opens with the string ready to copy.",
                } },
                { type = "h3", text = "In" },
                { type = "list", items = {
                    "|cffffd700/bb import|r opens an empty box; paste and confirm.",
                    "The new bar appears in the middle of the screen. Drag it where you want it.",
                } },
                { type = "h3", text = "Copying one you have" },
                { type = "paragraph", text = "|cffffd700Duplicate|r copies a bar and everything on it, offset slightly so it is not sitting exactly on top of the original. It is on the Actions list and on |cffffd700/bb duplicate <id>|r." },
            },
        },

        {
            title = "Profiles",
            blocks = {
                { type = "paragraph", text = "A profile holds every bar's position, size, contents, keybinds, visibility conditions and settings, so switching profiles swaps the whole arrangement at once." },
                { type = "paragraph", text = "|cffffd700One profile covers every BazUI module|r - switching it moves Bars, Drawers, Chat, Bags and the rest together. Create, switch, copy and delete them on |cffffd700BazUI > Profiles|r." },
            },
        },

        {
            title = "Slash commands",
            blocks = {
                { type = "table", columns = { "Command", "What it does" }, rows = {
                    { "/bb", "Opens the Bars settings. /bazbars is the same, and both take every subcommand." },
                    { "/bb create [cols] [rows]", "A new bar, optionally at a size." },
                    { "/bb delete <id>", "Deletes one." },
                    { "/bb duplicate <id>", "Copies one with everything on it." },
                    { "/bb export <id>", "The bar as a string." },
                    { "/bb import", "Opens the paste box." },
                    { "/bb scale <id> <value>", "Sets a bar's icon size." },
                    { "/bb padding <id> <pixels>", "Sets the gap between its buttons." },
                    { "/bb reset", "Resets every bar, and reloads." },
                } },
            },
        },

        {
            title = "Things worth knowing",
            blocks = {
                { type = "list", items = {
                    "|cffffd700[combat] show; hide|r in Show when gives you a bar that only exists in a fight.",
                    "Item buttons count your bags, which makes a bar a decent readout as well as a set of buttons.",
                    "These bars spend none of the game's 120 action slots, so whatever you had before is still where you left it.",
                    "Click-through plus Fade until hovered makes a bar that watches rather than waits - cooldowns visible, nothing to misclick.",
                } },
            },
        },
    },
})
