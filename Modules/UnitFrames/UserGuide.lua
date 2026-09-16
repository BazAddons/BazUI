-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Unit Frames User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("UnitFrames", {
    title = "Unit Frames",
    intro = "Health, power, casting, experience and reputation, as bars you "
        .. "make yourself and put where you want them. There are no portraits, "
        .. "and that is what lets any bar dock to any other.",

    pages = {
        {
            title = "What you get",
            blocks = {
                { type = "paragraph", text = "A new profile starts with five bars: your health, power and casting stacked on the left, and your target's health and power on the right. Nothing else exists until you make it. The game's own player frame, target frame and casting bar are hidden to make room - you can have any of them back, one switch each." },
                { type = "paragraph", text = "A bar is one reading of one unit. That is the whole model, and everything else follows from it: a health bar and a power bar are two bars that happen to sit together, not one frame with two parts. Because they are separate, anything can dock to anything - a power bar under a health bar, a cast bar under that, the whole stack under an action bar." },
                { type = "note", text = "|cffffd700Open it with|r /bazframes, or Options > AddOns > BazUI > Unit Frames." },
            },
        },

        {
            title = "Making a bar",
            blocks = {
                { type = "paragraph", text = "Three ways, all the same underneath:" },
                { type = "list", items = {
                    "|cffffd700The Bars page.|r Options > AddOns > BazUI > Unit Frames > Bars, then New bar. It arrives as a player health bar in the middle of the screen; change what it reads afterwards.",
                    "|cffffd700Edit Mode.|r Right-click an empty patch of screen in Edit Mode and pick Bars and readouts. You choose the reading and the unit up front, so the bar arrives as the thing you wanted.",
                    "|cffffd700Party frames (all four).|r In that same Edit Mode menu. Makes eight bars in one go - health and power for each of the four party slots, power docked under health, each pair docked under the last. The shape is the same every time and nobody wants to place eight bars to find out whether they like it.",
                } },
                { type = "h3", text = "Reads / Of" },
                { type = "paragraph", text = "|cffffd700Reads|r is what the bar shows: Health, Power, Casting, XP or Reputation. |cffffd700Of|r is whose - Player, Target, Pet, any of Party 1 to 4, or any of their pets. XP and Reputation are always yours, so they have no Of." },
                { type = "h3", text = "Copying a whole stack" },
                { type = "paragraph", text = "Set up Party 1 the way you want it, then in Edit Mode select its bottom bar and use |cffffd700Copy this and everything under it|r. Pick which unit the copy should read, and you get the same arrangement pointed at somebody else. Anything that was meant to dock and came out loose is named in chat, because on screen a broken copy looks exactly like a working one." },
                { type = "paragraph", text = "|cffffd700Duplicate|r, in the same place, copies one bar rather than a stack." },
            },
        },

        {
            title = "Docking",
            blocks = {
                { type = "paragraph", text = "A floating bar stays where you put it. A docked bar attaches to something else and takes its width, which is how a row of bars stays a row when you resize the thing above it." },
                { type = "paragraph", text = "Drag a bar near the edge of an action bar or another bar in Edit Mode and it docks there. Or set it on the bar's page:" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Dock to", "Floating, or the name of an action bar or another bar." },
                    { "On the", "Above or below its host." },
                    { "Takes", "The whole width, half the width, or its own width. Half lets two bars share one line." },
                    { "Aligned", "Which end of its host it sits at - only asked when it is not taking the whole width." },
                    { "Space beside", "Pixels between two bars sharing a line. One number for the line, so setting it on either of the two is enough." },
                    { "Gap", "Pixels between this bar and the one it is docked to. Each bar owns the space above it, so a chain is spaced by setting each bar in turn." },
                } },
                { type = "note", text = "A health bar aligned left and a power bar aligned right, both taking half the width of the same action bar, is the arrangement most people end up with. It is two bars, not a special mode." },
                { type = "paragraph", text = "Delete a bar and anything docked to it goes back to floating rather than disappearing with it." },
            },
        },

        {
            title = "Size and text",
            blocks = {
                { type = "h3", text = "Width and height" },
                { type = "paragraph", text = "|cffffd700Height|r is the height of the fill - the coloured part. The border is added around it, so the bar on screen comes out taller than this number by however thick your border is. Set a 20 and you get 20 pixels of colour, whatever the skin is doing." },
                { type = "paragraph", text = "|cffffd700Width|r only appears on a bar that is not docked, or one set to keep its own width. A docked bar is measured from its host." },
                { type = "h3", text = "Fills from" },
                { type = "paragraph", text = "Which end the bar empties towards. Two bars sharing a line often want opposite ends so they drain towards each other." },
                { type = "h3", text = "Text" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Show text", "Always, on hover, or never." },
                    { "Text says", "Everything, Current / Max, Current, Percent, Name, or Name and percent. Everything spells out the name, the values and the exact percent." },
                    { "Tenth marks", "Divider lines across the fill. Ten of them marks the tenths of a level, which is what an experience bar usually wants." },
                } },
                { type = "h3", text = "Experience bars" },
                { type = "paragraph", text = "|cffffd700Hide at maximum level|r is on by default: an experience bar has nothing to show once you stop earning any. Rested experience is drawn as a second, lighter segment beyond the fill." },
            },
        },

        {
            title = "General settings",
            blocks = {
                { type = "paragraph", text = "These are true of every bar at once. Everything about a particular bar lives on that bar." },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Preview units that are not there", "Party and target bars are hidden when there is nobody in them. This shows them as placeholders so a party layout can be built while you are standing alone. Edit Mode does this on its own; the switch is for the rest of the time. It lasts until you reload." },
                    { "Tooltip on hover", "Hovering a health or power bar shows that unit's tooltip." },
                    { "Class color on player health", "Health bars for players take the class colour instead of green." },
                    { "Fade units out of range", "A party member you cannot reach fades, so you know before you start casting." },
                    { "Faded opacity", "How far they fade. Only shown when fading is on." },
                } },
                { type = "note", text = "The game only answers range questions for people in your group, so fading affects nothing else." },
            },
        },

        {
            title = "Blizzard's frames",
            blocks = {
                { type = "paragraph", text = "One switch per frame, on the General Settings page. Nothing is hidden that you did not ask to hide, and nothing replaces these but the bars you make - so turning one off hides the game's frame whether or not you have built something to take its place." },
                { type = "table", columns = { "Frame", "Off by default?" }, rows = {
                    { "Player frame", "Yes - the starter bars replace it." },
                    { "Target frame", "Yes - the starter bars replace it." },
                    { "Casting bar", "Yes - the starter bars replace it." },
                    { "Party frames", "No. Make party bars first, or a group will have nothing showing it at all." },
                    { "Pet casting bar", "No." },
                    { "Raid manager tab", "No. The tab at the left edge that slides out with target markers, group filters and ready check." },
                } },
                { type = "note", text = "Hiding a frame is protected by the game, so a switch thrown during a fight is answered when the fight ends. Nothing is lost; it just waits." },
            },
        },

        {
            title = "In combat",
            blocks = {
                { type = "paragraph", text = "The game will not let an addon create, move or resize frames that can target something while you are fighting. So while you are in combat:" },
                { type = "list", items = {
                    "New bars, duplicates, copies and deletes wait. You are told in chat rather than left wondering.",
                    "Docking changes wait for the same reason.",
                    "Hiding or restoring one of the game's frames waits, and happens when the fight ends.",
                    "Preview is unavailable.",
                } },
                { type = "paragraph", text = "Everything that is only a readout - colours, text, fading - keeps working normally." },
            },
        },

        {
            title = "Slash commands",
            blocks = {
                { type = "table", columns = { "Command", "What it does" }, rows = {
                    { "/bazframes", "Opens this module's settings. /bazplayer does the same." },
                    { "/bazframes preview", "Turns the placeholder bars on or off." },
                    { "/bazframes stacks", "Prints every bar and what it is docked to. Worth running when a layout is not coming out the way you expect." },
                    { "/bazframes reset", "Deletes every bar and starts again with the usual five. Asks first." },
                } },
                { type = "note", text = "Aura rows are a separate module: /bazauras reset does those." },
            },
        },
    },
})
