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
                { type = "paragraph", text = "Character, Spellbook, Talents, Quest Log, Social, Guild, World Map, Game Menu and Help move onto a BazUI bar and are drawn as round icons wearing your skin's border. The Character button shows your portrait instead of a fixed icon." },
                { type = "paragraph", text = "|cffffd700They are still the game's own buttons|r, only moved and redressed. Tooltips, keybinds, the talent reminder flash and the pressed-in look of a window that is already open all keep working, because none of that is being reimplemented here." },
                { type = "paragraph", text = "That also means the game still decides when a button exists at all: Talents before level 10, Guild while you are in no guild. A button the game is hiding stays hidden here and appears when it unlocks." },
                { type = "note", text = "|cffffd700Open it with|r /bazmicro, or Options > AddOns > BazUI > Micro Menu." },
            },
        },

        {
            title = "Moving the bar",
            blocks = {
                { type = "paragraph", text = "The bar starts at the top center of the screen. Open Edit Mode and drag it anywhere; the layout settings are also on the bar's Edit Mode popup, so you can size it while you are looking at it." },
                { type = "paragraph", text = "|cffffd700Reset position|r puts it back at the top center. /bazmicro reset does the same thing without opening anything." },
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
                    { "Reset position", "Back to the top center." },
                } },
                { type = "h3", text = "Buttons" },
                { type = "paragraph", text = "One switch per button, in bar order. Turning one off takes it off the bar and closes the gap; it does not disable whatever it opened, which still has its keybind." },
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
