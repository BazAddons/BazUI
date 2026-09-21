-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Codex", {
    title = "Codex",
    intro = "One window that answers two questions: what can I do today, and "
        .. "what have I already done.",
    pages = {
        {
            title = "Overview",
            blocks = {
                { type = "lead", text = "The codex gathers what the game scatters across a dozen windows and puts it on one page. Eleven pages, a tab each down the left, each one a set of blocks you can fold away." },
                { type = "h2", text = "Opening it" },
                { type = "list", items = {
                    "Type |cffffd700/codex|r or |cffffd700/bazcodex|r",
                    "Left-click the |cffffd700BazUI button on the minimap|r. Right-clicking that button opens the settings instead",
                    "Drag it by the |cffffd700title bar|r; it remembers where you left it",
                    "Escape closes it",
                }},
                { type = "h2", text = "What is on every page" },
                { type = "table", columns = { "Part", "What it is" }, rows = {
                    { "The header", "Your name in your class color, your realm, level, class, where you are and what you are carrying. Clicking the portrait opens the character sheet." },
                    { "The tiles", "A row of figures across the top, chosen for the page you are on: the number still wanted, the number already yours, your average item level." },
                    { "The blocks", "The page itself, in two columns. A block that runs long scrolls inside itself rather than pushing the page about." },
                } },
                { type = "note", style = "tip", text = "|cffffd700Hover a block's heading|r and it tells you what it is for, in a sentence. Click the heading to fold the block away, and the codex remembers which ones you folded - so you can keep a page down to the handful of lines you actually check." },
                { type = "note", text = "Rows are not just text. One about an item shows the real item tooltip; one about anything else explains itself in words. Many of them do something when clicked - open the calendar on that day, open the character sheet at that slot." },
            },
        },

        {
            title = "The pages",
            blocks = {
                { type = "table", columns = { "Page", "What it answers" }, rows = {
                    { "|cffffd700Today|r",       "What is still open to you: quests, lockouts, what you can walk into, what resets when." },
                    { "|cffffd700Progress|r",    "What you have already put your name to." },
                    { "|cffffd700Legacy|r",      "Forever's own account-wide points and where this character spent them." },
                    { "|cffffd700Events|r",      "What the calendar has on, today and the rest of the month." },
                    { "|cffffd700Equipment|r",   "What you are wearing, and the one thing wrong with each piece." },
                    { "|cffffd700Instances|r",   "Every dungeon, raid and world boss, and whether you can go." },
                    { "|cffffd700Reputation|r",  "Everyone you have standing with." },
                    { "|cffffd700Currencies|r",  "Your purse, and everything else the game counts." },
                    { "|cffffd700Professions|r", "Your trades and every other skill you have." },
                    { "|cffffd700Items|r",       "Look anything up." },
                    { "|cffffd700Wishlist|r",    "The things you are playing toward." },
                } },
                { type = "note", text = "A page only ever shows what this client can answer. Where a system is not open yet - Legacy, on a build that has not switched it on - the page says so rather than showing an empty frame." },
            },
        },

        {
            title = "Today",
            blocks = {
                { type = "paragraph", text = "What is still open to you." },
                { type = "table",
                  columns = { "Block", "What it shows" },
                  rows = {
                      { "|cffffd700Quests|r",              "Everything in your quest log, the ones ready to hand in first." },
                      { "|cffffd700For your level|r",      "Dungeons tuned for where you are now, give or take a couple of levels." },
                      { "|cffffd700Ready to run|r",        "Raids and dungeons you are attuned for, old enough for, and not already saved to. If it is here, you can walk in today." },
                      { "|cffffd700Saved instances|r",     "Every raid and dungeon you are locked to, how many of its bosses you have killed, and when the lock lifts." },
                      { "|cffffd700Goals|r",               "The long things worth chasing: your first mount, the epic one, a class reward. Only the ones that belong to your class and are within reach." },
                      { "|cffffd700Attunements started|r", "Keys and attunements you have begun and not finished, with how many steps are done. Hover a row for what is left." },
                      { "|cffffd700Resets|r",              "When the game's own timers roll over. The daily one clears daily quests; the weekly one clears raid lockouts." },
                  }},
                { type = "note", style = "tip", text = "The server only sends lockout data when it is asked. The codex asks on login, so the list can take a moment to fill in the first time." },
                { type = "note", text = "The Quests block reads the same data the |cffffd700Drawers|r quest tracker does. With the Drawers module switched off it has nothing to show." },
                { type = "h2", text = "Where goals and attunements come from" },
                { type = "paragraph", text = "Some goals need nothing written down at all, because the client already answers them: a savings target is your purse against a number, and the row tells you how much gold is still to go. The famous ones need a number written down, and those work the same way attunements do." },
                { type = "paragraph", text = "Classic has no attunement API. Retail hands an addon a list of what you are eligible for; this client hands over nothing, because in 2004 the answer lived in the player's head. So the codex works it out from the questions the client will answer: a quest you completed, a key in your bags, a reputation standing, your level. Which of those guard which door is the one piece of knowledge in the module that did not come from the game." },
                { type = "note", text = "Written-down knowledge can be wrong, so every entry checks itself: it carries the name it believes its quest or item number has, and an entry the client disagrees with is hidden rather than shown. A mistake in that list can only ever cost you a missing door, never a false one. Type |cffffd700/codex verify|r to see whether anything is being hidden and why." },
            },
        },

        {
            title = "Progress",
            blocks = {
                { type = "paragraph", text = "What you have already put your name to." },
                { type = "table",
                  columns = { "Block", "What it shows" },
                  rows = {
                      { "|cffffd700Titles|r", "Every title this character has earned the right to wear, and how many exist." },
                      { "|cffffd700Mounts|r", "Mounts you own, and how many there are to own in all." },
                      { "|cffffd700Pets|r",   "The small companions that follow you about." },
                      { "|cffffd700Goals|r",  "The long things you have finished." },
                  }},
                { type = "note", text = "A block only shows what this client knows about. As Forever adds collections the codex gains blocks for them without needing anything relearned." },
            },
        },

        {
            title = "Legacy",
            blocks = {
                { type = "paragraph", text = "Forever's own system, and the one thing in the codex that is about the whole account rather than this character." },
                { type = "table", columns = { "Block", "What it shows" }, rows = {
                    { "|cffffd700Legacy points|r", "Points the whole account earns once, from challenges, and that every character then spends separately across the three trees." },
                    { "|cffffd700Trees|r",         "Where this character has put its points. Another character may spend the very same points quite differently." },
                    { "|cffffd700Challenges|r",    "What earns them." },
                } },
                { type = "note", text = "On a build where Legacy is not open yet the page says so and nothing else. It fills in on its own when the system arrives; there is nothing to switch on." },
            },
        },

        {
            title = "Events",
            blocks = {
                { type = "paragraph", text = "What the game's calendar has on. The holiday that is running gets the top of the page with its own artwork and the game's own description of it; under that is what else is on today, and then the rest of the month." },
                { type = "paragraph", text = "Every row opens the calendar on that day when you click it." },
                { type = "note", style = "tip", text = "The |cffffd700round calendar button|r beside the page's name opens the game's calendar. It is on this page and no other, because a button that does the same thing everywhere is a button nobody reads after the first time. |cffffd700Shift and right click the minimap|r opens it too." },
            },
        },

        {
            title = "Equipment",
            blocks = {
                { type = "paragraph", text = "A paper doll: one card per slot down either side, each showing what is in it, its item level, and the one thing wrong with it - a missing enchant, or how worn it is." },
                { type = "paragraph", text = "Hover a card for the item's own tooltip. Click any of them to open the character sheet." },
                { type = "table", columns = { "Tile", "What it counts" }, rows = {
                    { "Item level",  "The average across what you are wearing." },
                    { "Enchants",    "How many slots could take one and have not got one." },
                    { "Durability",  "The worst piece you are wearing." },
                } },
                { type = "note", text = "The ranged slot is asked for by name, because this client has one and retail does not." },
            },
        },

        {
            title = "Instances",
            blocks = {
                { type = "paragraph", text = "The whole map of where you can go: every dungeon, raid and world boss the game has, not only the ones you are ready for. A row reads one of five ways, worst first: saved to it, too low for it, not yet attuned, outgrown it, or open to you." },
                { type = "table", columns = { "Block", "What it holds" }, rows = {
                    { "|cffffd700Dungeons|r",     "Five-player instances, by level." },
                    { "|cffffd700Raids|r",        "The larger ones, with how many bosses each has." },
                    { "|cffffd700World bosses|r", "The ones standing out in the world." },
                    { "|cffffd700Also saved to|r", "Lockouts the catalog does not recognize, so a lock is never invisible just because the list has not heard of the place." },
                } },
            },
        },

        {
            title = "Reputation and Currencies",
            blocks = {
                { type = "h2", text = "Reputation" },
                { type = "paragraph", text = "Everyone you have standing with, grouped the way the game's own reputation pane groups them, one bar per row. Groups you have collapsed in the game's pane are gathered into a |cffffd700Not shown|r block rather than dropped." },
                { type = "h2", text = "Currencies" },
                { type = "paragraph", text = "Your |cffffd700purse|r first, then everything else the game counts, in its own groups, with caps and weekly limits written out in words rather than left as numbers you have to know the meaning of." },
            },
        },

        {
            title = "Professions",
            blocks = {
                { type = "paragraph", text = "A card per profession, wearing that profession's own book art, with a rank bar under it. Then everything else you have learned - class skills, weapon skills, armor, languages - grouped the way the game's own skills sheet groups them." },
                { type = "note", text = "With nothing learned the page says so and tells you where to start: a trainer in any capital will teach you two." },
            },
        },

        {
            title = "Items and Wishlist",
            blocks = {
                { type = "h2", text = "Looking something up" },
                { type = "paragraph", text = "Paste an item link or type an item number and you get that exact item, with its tooltip and how many you are carrying. That works for anything in the game, because the server answers the question." },
                { type = "paragraph", text = "The tab lists |cffffd700every item in the game|r. The client cannot search its own items - there is no such call - so BazUI ships the game's own item list for WoW: Forever, generated from the game's tables. Open the tab and scroll, or pick a category and scroll that; type |cffffd700elixir|r and you get every elixir there is, not the ones you have happened to carry." },
                { type = "paragraph", text = "A |cffffd700green tick|r on a row means this character has actually met the item: carried, worn, banked, looted, looked at on a vendor, or linked by anyone in chat. Hover it and it says so. Those ticks start absent and appear as you play, and on a client with no shipped list the ticked items are the whole tab." },
                { type = "note", text = "On retail there is no shipped list yet, so a name searches the met list instead. A link or an item number reaches anything on either client." },
                { type = "note", style = "tip", text = "On the Items tab, |cffffd700shift-click|r any row to drop the item's link into whatever you are typing, and |cffffd700ctrl-click|r to try it on." },
                { type = "paragraph", text = "The tabs above the list are the |cffffd700game's own tree|r, the one the auction house browses by. Pick a class and a second row appears with its types: Weapon gives you Daggers, Staves, Swords; Armor gives you Cloth, Leather, Mail, Plate. Pick an armor type and a third row appears for the slot, so Cloth then Legs is every cloth leg piece in the game. The line under the tabs always says how many items you are looking at, and of how many." },
                { type = "h2", text = "The wishlist" },
                { type = "paragraph", text = "Every row on the Items tab ends in a |cffffd700star|r. Hollow, the item is not wanted; click it and it fills, and the item joins the Wishlist. Click again to take it off. So the way to build a wishlist is to search for things and star them." },
                { type = "paragraph", text = "The Wishlist tab itself takes an item link dropped into the box at its top, for something somebody has just linked in chat. Either way a row says how long ago you wanted it, and when one turns up in your bags the row says so. The |cffffd700x|r on a row takes it off, and shift-clicking a row links it in chat." },
                { type = "note", text = "The codex does not know where anything drops and will not guess. The wishlist is your list; the only thing it works out for itself is whether you have the item yet." },
            },
        },

        {
            title = "Settings",
            blocks = {
                { type = "h2", text = "Window" },
                { type = "table",
                  columns = { "Setting", "What it does" },
                  rows = {
                      { "|cffffd700Scale|r",              "How large the window is." },
                      { "|cffffd700Background opacity|r", "How see-through it is." },
                      { "|cffffd700Reset position|r",     "Back to the middle of the screen, for a window dragged somewhere you cannot reach." },
                      { "|cffffd700Open the codex|r",     "Opens it from the settings page." },
                  }},
                { type = "h2", text = "Item Lookup" },
                { type = "table",
                  columns = { "Setting", "What it does" },
                  rows = {
                      { "|cffffd700Remember items this character meets|r", "Whether the Items tab keeps its list. Off and it stops adding to it; what is already there stays until you clear it, and looking an item up by link or number still works." },
                      { "|cffffd700Forget remembered items|r",            "Empties the list and starts again. It asks first, and says how many it forgot." },
                  }},
                { type = "note", text = "The remembered list is this character's own, and it is a list of numbers and names - nothing about where anything came from or what it is worth." },
            },
        },

        {
            title = "Slash commands",
            blocks = {
                { type = "table",
                  columns = { "Command", "What it does" },
                  rows = {
                      { "/codex",          "Opens and closes it. /bazcodex does the same." },
                      { "/codex show",     "Opens it." },
                      { "/codex hide",     "Closes it." },
                      { "/codex reset",    "Moves the window back to the middle of the screen." },
                      { "/codex verify",   "Checks the written-down attunements and goals against the client, and says what is being hidden and why." },
                      { "/codex factions", "Lists every faction this client knows, in a box you can copy out of. For reporting a faction the Reputation page has grouped oddly." },
                      { "/codex settings", "Opens the settings page. Every BazUI command takes this, and |cffffd700help|r." },
                  }},
            },
        },
    },
})
