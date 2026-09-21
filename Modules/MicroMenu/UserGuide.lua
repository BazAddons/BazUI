-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Micro Menu User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("MicroMenu", {
    title = "Micro Menu",
    intro = "The game's micro buttons, drawn as round icons on a bar you can "
        .. "put wherever you like.",

    pages = {
        {
            title = "What it does",
            blocks = {
                { type = "paragraph", text = "The game's micro buttons move onto a BazUI bar and are drawn as round icons wearing your skin's border. The Character button shows your portrait instead of a fixed icon." },
                { type = "paragraph", text = "Which buttons those are is the client's answer, not a list written here: character, spellbook, talents, quests, social, guild, map, the game menu and help on every client, and whatever else yours has - achievements, professions, the group finder, collections, the adventure guide, the shop. On WoW: Forever that includes |cffffd700Legacy|r, which no other client has." },
                { type = "paragraph", text = "|cffffd700They are still the game's own buttons|r, only moved and redressed. Tooltips, keybinds, the talent reminder flash and the pressed-in look of a window that is already open all keep working, because none of that is being reimplemented here." },
                { type = "paragraph", text = "That also means the game still decides when a button exists at all: Talents before level 10, Guild while you are in no guild. A button the game is hiding stays hidden here and appears when it unlocks." },
                { type = "note", text = "|cffffd700Open it with|r /bazmicro, or Options > AddOns > BazUI > Micro Menu." },
            },
        },

        {
            title = "Moving the bar",
            blocks = {
                { type = "paragraph", text = "The bar starts at the top center of the screen. Open Edit Mode and drag it anywhere; the layout settings are also on the bar's Edit Mode popup, so you can size it while you are looking at it." },
                { type = "note", style = "tip", text = "|cffffd700Cannot see it at all?|r The profile BazUI ships starts the bar on mouseover fade, faded all the way to invisible. Put your cursor at the top middle of the screen and it appears. |cffffd700Show only on mouseover|r turns that off, and |cffffd700Faded opacity|r leaves it dimly visible instead of gone." },
                { type = "paragraph", text = "Where it sits is not set here. The micro menu is a |cffffd700drawer widget|r, so it can float anywhere, dock into a drawer beside the clock and the repair icon, scale with that drawer and fade on mouseover - all of which is answered once for every widget in |cffffd700/bazdrawers|r rather than separately here." },
                { type = "note", text = "It is nine fixed buttons with one right size, which is what a drawer widget is for. An action bar stretches to fill an edge and belongs on a dock instead - the two are different shapes of thing and get different homes." },
            },
        },

        {
            title = "Settings",
            blocks = {
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Hide Blizzard's micro menu", "Parks the game's own row of buttons out of the way. The buttons themselves are on the BazUI bar either way - this only decides whether the stock container is still sitting in the corner." },
                    { "Orientation", "A row or a column." },
                    { "Button size", "22 to 44 pixels." },
                    { "Spacing", "The gap between buttons, 0 to 16." },
                    { "Show only on mouseover", "The bar fades out until your cursor is over it." },
                    { "Faded opacity", "How much of it stays visible while faded, 0 to 90%. At 0 it is invisible - hover the spot and it comes back. Moving between the buttons never flickers it." },
                    { "Where it sits", "Not here - it is a drawer widget. Drag it in Edit Mode, or set it in /bazdrawers along with every other widget." },
                } },
                { type = "h3", text = "Buttons" },
                { type = "paragraph", text = "One switch per button. Turning one off takes it off the bar and closes the gap; it does not disable whatever it opened, which still has its keybind." },
                { type = "note", text = "|cffffd700Only the buttons this client has get a row.|r Forever has no Achievements, Housing or Social button, so there is no switch for them - a setting you could never act on is clutter, not honesty. Elsewhere in BazUI a setting that does not apply is grayed out in place rather than hidden, but that is for things another switch has turned off and you could turn back on." },
                { type = "note", text = "The switches are listed in a fixed order. The bar itself follows the order the game gives its buttons, so the two lists can read differently." },
                { type = "note", text = "The bar is always visible while Edit Mode is open, whatever the fade is set to - a bar you cannot see is a bar you cannot drag." },
            },
        },

        {
            title = "Turning the module off",
            blocks = {
                { type = "paragraph", text = "The switch is on |cffffd700BazUI > General|r with the rest of the module switches, not in this panel. Turning a module on or off takes a reload, and you are asked for one when you do it." },
                { type = "paragraph", text = "With the module off, the buttons go back to the game's own micro menu in the bottom right." },
            },
        },

        {
            title = "Slash commands",
            blocks = {
                { type = "table", columns = { "Command", "What it does" }, rows = {
                    { "/bazmicro", "Opens the settings." },
                    { "/bazmicro reset", "Moves the bar back to the top center." },
                    { "/bazmicro debug", "Prints what the bar currently thinks its state is - worth having in a bug report." },
                } },
            },
        },
    },
})
