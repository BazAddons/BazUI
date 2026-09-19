-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Auras User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Auras", {
    title = "Auras",
    intro = "Buffs and debuffs in rows you make and place yourself, instead "
        .. "of in the corner by the minimap.",

    pages = {
        {
            title = "What you get",
            blocks = {
                { type = "paragraph", text = "A row shows buffs or debuffs, of one unit. You can have as many rows as you like, and each one floats where you put it or docks to a bar or an action bar. A new profile starts with four: your buffs and debuffs on the left, your target's on the right." },
                { type = "paragraph", text = "Icons are square, and a row's icons touch when spacing is set to nought - the button is exactly what you can see of it, with nothing hanging outside its box. Each icon is trimmed a little at the edges, because every icon in the game's art has a dark border painted into it that would otherwise sit on top of ours." },
                { type = "list", items = {
                    "Right-click an icon to cancel that buff, or to remove a weapon enchant - in combat as well as out of it.",
                    "Time remaining and stack counts on the icons.",
                    "Debuff rims colored by type: blue Magic, purple Curse, brown Disease, green Poison, red for everything else.",
                    "Weapon enchants - poisons, sharpening stones - shown among your buffs.",
                    "A row for somebody else can be limited to the auras you applied.",
                    "A docked row follows its host, takes its alignment, and hides when the host hides.",
                } },
                { type = "note", text = "|cffffd700Open it with|r /bazauras, or Options > AddOns > BazUI > Auras." },
            },
        },

        {
            title = "Making a row",
            blocks = {
                { type = "list", items = {
                    "|cffffd700The Rows page.|r Options > AddOns > BazUI > Auras > Rows, then New row.",
                    "|cffffd700Edit Mode.|r Right-click empty screen and pick Aura rows, then Buffs or Debuffs, then whose.",
                } },
                { type = "paragraph", text = "|cffffd700Shows|r is Buffs or Debuffs. |cffffd700Of|r is Player, Target, Pet or any of Party 1 to 4. |cffffd700Only mine|r hides auras other players applied, which is what makes a target debuff row useful rather than a wall of everybody's." },
            },
        },

        {
            title = "Docking",
            blocks = {
                { type = "paragraph", text = "Drag a row in Edit Mode and drop it near the edge of a bar or an action bar to dock it there, or set it on the row's page." },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Dock to", "Floating, or the name of a bar or action bar. Docked, it follows its host and hides when the host hides." },
                    { "On the", "Which side of the host: above, below, left of or right of it." },
                    { "Takes", "How much of its host's width the row uses. All of it spans the whole thing and sizes the icons to suit, so icons per row decides how big they come out. Half of it does the same across half the width, which is how two rows share one line - buffs on the left of an action bar and debuffs on the right, aligned to opposite ends. Its own width keeps the icons the size you chose." },
                    { "Aligned", "Which end of its host the row starts from: left, center or right above and below it, top, middle or bottom beside it." },
                    { "Gap", "Pixels between this row and what it is docked to." },
                } },
                { type = "note", text = "A centered row stays centered as icons come and go, including in combat, because what moves is the row's frame rather than anything the game protects." },
                { type = "note", text = "A row docked to the left or right of something always keeps its own width. A row works its icon size out from its width, and a side has only height to give it - so Takes is greyed out there rather than offering a choice the row would ignore." },
            },
        },

        {
            title = "Shape of a row",
            blocks = {
                { type = "paragraph", text = "These are per row, on the Rows page. Leave them alone and the row follows the General page instead, so you can set a size once and have every row take it." },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Icon size", "This row only." },
                    { "Spacing", "Pixels between icons, and between rows of them. Nought means they touch." },
                    { "Icons per row", "How many fill a row before the next one starts." },
                    { "Show at most", "The most icons this row will ever show; nought for no limit." },
                    { "Rows at most", "Nought means as many rows as there are auras." },
                    { "Icons run", "Left to right, or right to left, from the row's anchored end." },
                    { "Rows stack", "Where a second row goes: away from the dock, downward or upward." },
                } },
                { type = "h3", text = "Two ways to cap a row" },
                { type = "paragraph", text = "|cffffd700Show at most|r spreads what it keeps evenly rather than filling rows and overshooting - ten icons at eight across comes out as two rows of five, not a row of eight and a row of two. |cffffd700Rows at most|r caps the number of rows instead; one row is the usual choice for somebody else's debuffs, since sixteen of them is a legal state of affairs and a tower of icons is not what showing them meant. Set both and whichever bites first wins." },
                { type = "h3", text = "Timers" },
                { type = "paragraph", text = "|cffffd700Show timers|r is per row. |cffffd700Timer size|r at nought sizes the text from the icon, which has a floor of eight points - and on a row of small icons eight points is most of the icon. That is the reason the setting exists: give it a number, or turn the timers off for that row." },
            },
        },

        {
            title = "General settings",
            blocks = {
                { type = "paragraph", text = "These apply to every row that has not been given a value of its own." },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Hide Blizzard's buff and debuff frames", "Parks the stock frames by the minimap while ours are shown. Turn it off to keep both. On by default." },
                    { "Icons per row / Icon size / Spacing", "The defaults a row uses when it has none of its own." },
                    { "Time remaining on icons", "Timer text." },
                    { "Stack counts", "The number in the corner." },
                    { "Color debuff rims by type", "Off keeps every debuff rim red." },
                    { "Weapon enchants with the buffs", "Poisons, sharpening stones and the like, shown as buff icons. Right-click removes them." },
                    { "Sort by / Direction", "Order applied, time remaining or name; ascending or descending." },
                } },
                { type = "h3", text = "Preview" },
                { type = "paragraph", text = "|cffffd700Preview a full spread of auras|r fills every row with stand-in icons so you can judge size and spacing without waiting to be buffed. It ends when combat starts. Edit Mode turns it on by itself, so you always see what you are arranging." },
                { type = "h3", text = "Reset" },
                { type = "paragraph", text = "|cffffd700Reset layout|r puts the rows back to the four a new profile starts with. Unit frame bars are separate: /bazframes reset does those." },
            },
        },

        {
            title = "Slash commands",
            blocks = {
                { type = "table", columns = { "Command", "What it does" }, rows = {
                    { "/bazauras", "Opens this module's settings." },
                    { "/bazauras preview", "Shows or hides the stand-in icons." },
                    { "/bazauras reset", "Puts the rows back to the starting four." },
                } },
                { type = "note", text = "Layout changes made during combat apply the moment combat ends. Icons, counts and timers always update live." },
            },
        },
    },
})
