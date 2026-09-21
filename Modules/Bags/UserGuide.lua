-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Bags User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Bags", {
    title = "Bags",
    intro = "Every bag and the keyring in one panel, arranged by what your "
        .. "items are rather than by which bag they happen to be in.",

    pages = {
        {
            title = "What it does",
            blocks = {
                { type = "paragraph", text = "One window holds your backpack, your bags and your keyring. It opens from anywhere the game's own bags opened from - the |cffffd700B|r key, the bag buttons, an addon that asks for the bags - because those routes are intercepted rather than replaced." },
                { type = "list", items = {
                    "|cffffd700Two ways of arranging it|r: grouped by category, or one section per bag.",
                    "|cffffd700Eight categories to start with|r that sort your items for you, and as many of your own as you want.",
                    "|cffffd700Pin an item|r to a category and it goes there whatever the sorter thinks.",
                    "A |cffffd700rarity glow|r around slots, and a backdrop behind the empty ones.",
                    "|cffffd700Free slot count|r in the title bar and a button that sells your grays at a merchant.",
                    "|cffffd700Search|r that filters every bag at once.",
                } },
                { type = "note", text = "|cffffd700Open it with|r /bbg or /bazbags, or find the settings at Options > AddOns > BazUI > Bags." },
            },
        },

        {
            title = "Opening it and the title bar",
            blocks = {
                { type = "table", columns = { "Action", "What it does" }, rows = {
                    { "B", "Opens and closes the panel - the game's own keybind." },
                    { "The bag buttons", "The same." },
                    { "/bbg", "The same. /bazbags is the long form." },
                    { "Escape", "Closes it." },
                } },
                { type = "h3", text = "The portrait" },
                { type = "paragraph", text = "The icon at the top left of the panel is three shortcuts in one, so the things you do most do not need a trip to the settings." },
                { type = "table", columns = { "Click", "What it does" }, rows = {
                    { "Left-click", "Sorts - runs the game's own Clean Up Bags." },
                    { "Middle-click", "Categorize mode on and off: every category visible, each with a drop slot." },
                    { "Right-click", "The bag-change popup, for equipping and unequipping bags." },
                } },
                { type = "note", text = "No middle button? |cffffd700/bbg categorize|r does the same thing, and can be put on a macro and bound to a key." },
                { type = "h3", text = "The rest of the title bar" },
                { type = "list", items = {
                    "|cffffd700Drag|r anywhere on it except the portrait to move the panel. Where you leave it is where it stays.",
                    "|cffffd700Free slots|r sit next to the name, if you have that switched on.",
                    "|cffffd700A coin button|r appears while a merchant is open and you have grays worth selling.",
                    "|cffffd700The X|r closes it.",
                } },
                { type = "h3", text = "The bag-change popup" },
                { type = "paragraph", text = "Right-clicking the portrait raises a small panel with one button per bag slot. Drag a bag from your inventory onto a slot to equip it, or drag the slot's icon off to take it out. It is the character pane's Bags tab, a click closer, and it puts itself above or below the panel depending on where there is room." },
            },
        },

        {
            title = "Two ways of arranging it",
            blocks = {
                { type = "paragraph", text = "|cffffd700Group items by|r, on the General page, is the choice. Switching is free either way - the bags themselves are untouched, only the drawing changes." },
                { type = "h3", text = "Categories" },
                { type = "paragraph", text = "The default. Items are grouped by what they are - Equipment, Consumables, Trade Goods and the rest - whatever bag they are actually in. Each group gets a thin divider with its name on it, and a divider you can click to fold the group away." },
                { type = "paragraph", text = "Pick this if you would rather find a kind of thing than remember which bag you put it in." },
                { type = "h3", text = "Bags" },
                { type = "paragraph", text = "One section per bag, in the order the slots really are. |cffffd700Separate each bag|r decides how far that goes: on, you get Backpack, Bag 1 with the bag's actual name beside it, Bag 2, and so on, each with its own collapsible header; off, every bag merges into one Bags section with the keyring on its own." },
                { type = "paragraph", text = "Pick this if the bag an item is in means something to you - a loot bag, a crafting bag - or if you just prefer the arrangement you already know." },
                { type = "note", text = "Everything you do with a slot works the same in both: click to use, drag to move, shift-click to link it in chat, right-click to sell at a merchant. The slot is the game's own item button, not a copy of one." },
            },
        },

        {
            title = "Empty slots",
            blocks = {
                { type = "paragraph", text = "|cffffd700Hide empty slots|r is on to start with, and the panel shows only what you are carrying. Turn it off to see your free space, and what you get depends on how the panel is arranged:" },
                { type = "list", items = {
                    "|cffffd700Grouped by bag|r - the gaps fill back in, each bag drawn at its full size.",
                    "|cffffd700Grouped by category|r - your free space turns up as an |cffffd700Empty Slots|r category, which you can move, rename and collapse like any other. It only appears when you have some.",
                } },
                { type = "paragraph", text = "|cffffd700Backdrop on empty slots|r puts the same slot art the action bars wear behind each one, so the grid reads as a grid rather than as holes between the things you own." },
            },
        },

        {
            title = "Categories",
            blocks = {
                { type = "paragraph", text = "A category is a name, a place in the list, and a set of rules for what belongs in it. These ship with the addon:" },
                { type = "table", columns = { "Category", "What it takes" }, rows = {
                    { "Equipment", "Weapons and armor." },
                    { "Consumables", "Potions, food, scrolls, and ammunition." },
                    { "Trade Goods", "Trade goods, reagents, recipes, gems and enhancements." },
                    { "Reagents", "What a reagent bag holds. Only offered while you are carrying one." },
                    { "Quest Items", "Quest items." },
                    { "Keys", "Keys, by what the item is. Not the same question as which bag it is in." },
                    { "Junk", "Anything gray." },
                    { "Other", "Whatever nothing else claimed. It cannot be deleted or hidden - something has to catch what is left." },
                    { "Empty Slots", "Your free space, when you have chosen to see it." },
                    { "Empty Reagent Slots", "Free space in a reagent bag, kept separate. Only while you carry one." },
                    { "Empty Keyring Slots", "Free space in the keyring, likewise. A keyring's spare slots swamped Empty Slots otherwise." },
                } },
                { type = "h3", text = "How an item finds its category" },
                { type = "paragraph", text = "Two things decide it, in this order:" },
                { type = "list", items = {
                    "|cffffd700A pin wins.|r If you have pinned that item to a category, that is where it goes, full stop.",
                    "|cffffd700Otherwise the rules decide.|r Each category is asked in |cffffd700match priority|r order - lowest number first - and the first one whose rules match takes the item. Nothing matches, it goes to Other.",
                } },
                { type = "note", text = "|cffffd700Match priority is not the same as position.|r Where a category sits in the panel is its order; when it gets asked is its priority. That separation is what lets a category you made sit at the bottom of the panel and still claim its items before Equipment does. Junk ships at priority 5 so grays group together whatever else you have set up." },
                { type = "h3", text = "Renaming is safe" },
                { type = "paragraph", text = "Categories are looked up by an internal key, not by their label. Rename Equipment to Gear and your weapons still land in it." },
            },
        },

        {
            title = "Making your own categories",
            blocks = {
                { type = "paragraph", text = "The |cffffd700Categories|r page - Options > AddOns > BazUI > Bags > Categories - is a list on the left and the selected category's settings on the right. |cffffd700Create New Category|r and |cffffd700Reset to Defaults|r sit at the top." },
                { type = "h3", text = "Identity" },
                { type = "list", items = {
                    "|cffffd700Display Name|r - what appears on the divider.",
                    "|cffffd700Hide from bag panel|r - it keeps working and keeps its items, it just is not drawn. Categorize mode surfaces hidden categories so you can still manage them.",
                    "|cffffd700Priority|r - when this category gets asked, 1 to 999.",
                } },
                { type = "note", text = "|cffffd700Where it sits is the up and down arrows|r on the category's row in the list, not a number in this panel. Move it to where you want it." },
                { type = "h3", text = "Match rules" },
                { type = "paragraph", text = "A rule is a thing to look at and a value to match. |cffffd700Match mode|r decides whether an item needs to satisfy all of them or any of them. |cffffd700Add Match Rule|r adds one, and on a shipped category |cffffd700Reset Rules to Default|r puts that category's own rules back without touching anything else." },
                { type = "table", columns = { "Rule", "Matches on" }, rows = {
                    { "Name", "The item's name - contains, equals, or a pattern." },
                    { "Item Type", "The game's own item classes, the same ones the defaults use." },
                    { "Item Subtype", "One step finer - cloth armor rather than all armor." },
                    { "Equip Slot", "Head, cloak, trinket and the rest. Good for keeping a trinket set together." },
                    { "Quality", "Poor through Heirloom, at or above or below." },
                    { "Item Level", "At or above or below a number." },
                } },
                { type = "h3", text = "Deleting" },
                { type = "paragraph", text = "The Delete section at the bottom removes the selected category. A default warns you first; items it would have claimed fall through to whatever asks next, or to Other. |cffffd700Reset to Defaults|r puts the shipped categories back to their shipped names and order, and keeps the ones you made and the items you pinned." },
                { type = "note", style = "warning", text = "It resets more than names and order: the shipped categories' |cffffd700rules and priorities|r go back to shipped as well, and the rules come back at the next load rather than instantly. If you have spent an evening tuning Equipment's rules, use |cffffd700Reset Rules to Default|r on that one category instead." },
                { type = "note", text = "Other cannot be deleted or hidden. Everything has to land somewhere." },
            },
        },

        {
            title = "Pinning items",
            blocks = {
                { type = "paragraph", text = "A pin is your answer overriding the rules: pin an Iron Bar to a Crafting category of your own and that is where it lives, whatever its item type says. There are three ways to do it and they all write to the same list." },
                { type = "h3", text = "Shift and right-click a slot" },
                { type = "paragraph", text = "The quick way for one item. A menu opens with |cffffd700Category|r at the top; every category is inside it, so the menu stays a few lines tall rather than ten. The one the item is pinned to now carries a gold check, and clicking that again unpins it. Hidden categories are in the list marked |cff888888(hidden)|r, which is how you deliberately put something out of sight. |cffffd700Unpin (auto-classify)|r hands the item back to the rules." },
                { type = "note", text = "This gesture is the game's own split-stack shortcut, so the menu carries |cffffd700Split stack...|r as well - the shortcut is not lost, just moved onto the menu that took its place. Use, link and every other click are untouched." },
                { type = "h3", text = "Categorize mode" },
                { type = "paragraph", text = "The way to do a lot at once. Middle-click the portrait, or type /bbg categorize. Every category appears - empty ones and hidden ones included - each with a gold |cffffd700+|r at the end of its row. Pick up an item, drop it on the + of the category you want, repeat. Middle-click the portrait again to leave." },
                { type = "paragraph", text = "It is a mode you turn on rather than something that happens whenever the cursor has an item in it, because the latter fights with simply moving things between slots." },
                { type = "h3", text = "From the settings page" },
                { type = "paragraph", text = "A category's detail panel lists what is pinned to it, each with a Remove button. Pinning is done in the bag itself, which is where the item is - either of the two ways above." },
            },
        },

        {
            title = "How it looks",
            blocks = {
                { type = "paragraph", text = "On the |cffffd700General|r page, under Layout. Changes apply while you watch - leave the panel open while you set them." },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Columns", "The |cffffd700narrowest|r the bag goes, 4 to 20. It takes more columns on its own when the contents would otherwise run past the row limit below." },
                    { "Rows before widening", "How tall the bag may get before it takes another column instead. Bags do not scroll: a higher number gives a taller, narrower bag and a lower one gives a shorter, wider bag." },
                    { "Background", "Marble, Rock or Flat. Flat is the skin's panel color with no grain in it at all." },
                    { "Darkness", "How far the background is taken toward black. All the way leaves no grain, which is the same as picking Flat. Hidden when Flat is chosen, because it would do nothing." },
                    { "Background opacity", "How much of the world shows through. Items and text stay solid." },
                    { "Frame layer", "Which layer of the interface the panel sits on. Dialog, the default, keeps it above the settings window." },
                } },
                { type = "h3", text = "On the slots themselves" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Rarity glow", "A colored glow around the slot, by the item's quality. Off, uncommon and better, white and better, or everything including gray. Uncommon and better is the default - gray and white on every slot is noise rather than information. It lights the slot art the game already draws rather than replacing it with a colored square." },
                    { "Backdrop on empty slots", "The action bars' slot art behind each empty slot." },
                    { "Item level on gear", "The item's level in the corner of the icon, on things you can equip only - a stack of cloth has an item level and it means nothing." },
                    { "Mark bind on equip", "A small BoE tag on anything that binds when you put it on. The difference between vendoring a thing and listing it." },
                } },
            },
        },

        {
            title = "Money, selling and the bag bar",
            blocks = {
                { type = "h3", text = "Money" },
                { type = "paragraph", text = "Your gold sits next to the search box. |cffffd700Show gold only|r drops the silver and copper, which at a few thousand gold are digits nobody reads." },
                { type = "h3", text = "Selling grays" },
                { type = "paragraph", text = "|cffffd700Sell gray items at a vendor|r puts a coin button on the title bar while a merchant is open. It sells every gray that has a price, and it is only there when there is something to sell - a button that does nothing is a button in the way." },
                { type = "note", text = "The Quality of Life module can do the same thing automatically the moment you open a merchant, if you would rather not decide each time. This button is the version that asks." },
                { type = "h3", text = "When the bags are full" },
                { type = "paragraph", text = "|cffffd700Mark what to drop first|r rings the gray stack worth the least of anything you are carrying, the moment you have no free slots left, so there is no hunting for something to make room with. Hovering it says what it is worth." },
                { type = "note", text = "Nothing with no sale value is ever picked. That is usually the one thing you must keep." },
                { type = "h3", text = "The game's bag bar" },
                { type = "paragraph", text = "|cffffd700Hide Blizzard's bag bar|r takes the backpack, bag and keyring buttons out of the bottom right corner. B, /bbg and the minimap entry all still open the panel. To equip a new bag while the bar is hidden, right-click it in your inventory and it goes into an empty bag slot." },
            },
        },

        {
            title = "Search",
            blocks = {
                { type = "paragraph", text = "The box at the top of the panel filters every bag at once. Type part of a name, a type like |cffffd700potion|r, a quality like |cffffd700epic|r, or anything else the tooltip says - what does not match dims, and clearing the box brings it back." },
                { type = "paragraph", text = "It is the game's own search box, so it behaves exactly as the one in the stock bags does, and anything that taught you a trick there still works here." },
            },
        },

        {
            title = "Things worth knowing",
            blocks = {
                { type = "h3", text = "Hiding junk without losing it" },
                { type = "paragraph", text = "Hide the Junk category and gray items stop cluttering the panel. They are still in your bags taking up real slots, and they are still there at the vendor - they are simply not drawn. The category keeps claiming them, which is what stops them scattering into Other." },
                { type = "h3", text = "Putting something out of sight" },
                { type = "paragraph", text = "Make a category called Stash, hide it, and pin anything you want out of the way to it. The item stays in your bag; it just stops appearing. Unpin it or unhide the category to get it back." },
                { type = "h3", text = "One profile for everything" },
                { type = "paragraph", text = "Bags settings travel with the rest of BazUI. A crafting alt might want categories, no junk and a tall panel while a leveling alt wants bags mode and something compact - that is two profiles, set on the |cffffd700BazUI > Profiles|r page." },
                { type = "h3", text = "Sorting" },
                { type = "paragraph", text = "|cffffd700/bbg sort|r and left-clicking the portrait both run the game's own Clean Up Bags. This module does not ship a sorter of its own." },
            },
        },

        {
            title = "Slash commands",
            blocks = {
                { type = "table", columns = { "Command", "What it does" }, rows = {
                    { "/bbg", "Opens and closes the panel. /bazbags is the same, and both take every subcommand." },
                    { "/bbg toggle", "The same as the bare command." },
                    { "/bbg sort", "Clean Up Bags." },
                    { "/bbg categorize", "Categorize mode on and off." },
                    { "/bbg rim", "Prints what the rarity glow is doing on the first few slots, for when a border looks wrong." },
                    { "/bbg settings", "Opens the settings page. Every BazUI command takes this, and |cffffd700help|r." },
                } },
                { type = "paragraph", text = "For a keybind, the game's own |cffffd700B|r already opens this panel. If you want a second one, put this on a macro and bind that:" },
                { type = "code", text = "/run BazUI:GetModule(\"Bags\").Bag:Toggle()" },
            },
        },
    },
})
