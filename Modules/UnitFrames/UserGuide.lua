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
                { type = "paragraph", text = "|cffffd700Height|r is the height of the fill - the colored part. The border is added around it, so the bar on screen comes out taller than this number by however thick your border is. Set a 20 and you get 20 pixels of color, whatever the skin is doing." },
                { type = "paragraph", text = "|cffffd700Width|r only appears on a bar that is not docked, or one set to keep its own width. A docked bar is measured from its host." },
                { type = "h3", text = "Fills from" },
                { type = "paragraph", text = "Which end the bar empties towards. Two bars sharing a line often want opposite ends so they drain towards each other." },
                { type = "h3", text = "Text" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Show text", "Always, on hover, or never. This is |cffffd700when|r there is text; the two settings below are |cffffd700what|r it says." },
                    { "Text says", "Everything, Current / Max, Current, Percent, Name, Name and percent, Level, or Name and level. Everything spells out the name, the values and the exact percent." },
                    { "When hovered", "A second wording, used while your cursor is on the bar. Same as usual leaves it alone." },
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
                    { "Preview units that are not there", "Party and target bars stand in for a plausible group, so a party layout can be built while you are standing alone - see the next page. Edit Mode does this on its own; the switch is for the rest of the time. It lasts until you reload." },
                    { "Tooltip on hover", "Hovering a health or power bar shows that unit's tooltip." },
                    { "Class color on player health", "Health bars for players take the class color instead of green." },
                    { "Glow around rares and elites", "A halo colored by rank - see the next page." },
                    { "Icon in front of the name", "A small mark before the name." },
                    { "Rank written beside the name", "Rare, Elite and so on, spelled out." },
                    { "Show the unit's level", "The level beside the name." },
                    { "Clicking a bar opens what it shows", "Reputation opens the reputation panel, experience opens the character panel." },
                    { "Fade units out of range", "A party member you cannot reach fades, so you know before you start casting." },
                    { "Faded opacity", "How far they fade. Only shown when fading is on." },
                } },
                { type = "note", text = "The game only answers range questions for people in your group, so fading affects nothing else." },
                { type = "h3", text = "Clicking a bar" },
                { type = "table", columns = { "Bar", "Opens" }, rows = {
                    { "Reputation", "The reputation panel." },
                    { "Experience", "The character panel." },
                } },
                { type = "paragraph", text = "Each one opens the window it is a summary of." },
                { type = "paragraph", text = "A bar with nothing to open |cffffd700ignores the mouse entirely|r rather than quietly swallowing clicks meant for the world behind it. A bar only takes the mouse when it has a reason to - something to open, or text set to appear on hover." },
                { type = "note", text = "Health and power bars are left out of this. They are already buttons: clicking one targets the unit and right-clicking opens its menu, and a third meaning for a click would be taking one of those away." },
            },
        },

        {
            title = "Rares, elites and levels",
            blocks = {
                { type = "paragraph", text = "The game sorts its NPCs into ranks and says which is which by putting a dragon around the portrait. |cffffd700These bars have no portraits|r - that is the thing that lets any bar dock to any other - so the rank has to be marked on the bar itself. There are three ways, each on its own switch, and you can have any of them, all of them, or none." },
                { type = "paragraph", text = "|cffffd700Ordinary mobs are never marked|r, whichever you pick. Marking everything would be the same as marking nothing." },
                { type = "h3", text = "A glow around the bar" },
                { type = "paragraph", text = "The default. A soft halo around the health bar, colored by rank, which costs the bar's text nothing and reads without being read. It does not pulse: a pulse says something has just happened, and a mob being rare is not news, it is a fact about the mob." },
                { type = "table", columns = { "The unit is", "The glow is" }, rows = {
                    { "An ordinary mob", "Nothing. Glowing everything would be the same as glowing nothing." },
                    { "Rare", "Blue" },
                    { "Elite", "Gold" },
                    { "Rare elite", "Purple" },
                    { "A world boss", "Red" },
                } },
                { type = "note", text = "The colors are off item quality, so blue reading rare and purple reading rarer is something you already know without being taught. |cffffd700They are yours to change|r on the Skin page under Unit ranks, and a skin can ship its own." },
                { type = "paragraph", text = "Only health bars glow. The same unit's power bar saying the same thing would be the fact twice over, and twice as bright." },
                { type = "h3", text = "An icon in front of the name" },
                { type = "paragraph", text = "A glyph in front of the unit's name, one per rank. It is sized against the |cffffd700bar|r rather than against the writing on it: the text stops growing at twelve pixels however tall you make a bar, and a mark that stopped with it would be a speck in a lot of empty height. So it fills most of the bar, and the name shifts over to keep the pair centered." },
                { type = "note", text = "The icons are files in the addon's Skin folder, so a skin can replace them by replacing the pictures. They carry their own color, so unlike the glow they do not follow the palette." },
                { type = "h3", text = "A word beside the name" },
                { type = "table", columns = { "The unit is", "The bar says" }, rows = {
                    { "An ordinary mob", "Nothing extra." },
                    { "Rare", "Rare" },
                    { "Elite", "Elite" },
                    { "Rare elite", "Rare Elite" },
                    { "A world boss", "Boss" },
                } },
                { type = "h3", text = "With the level switched on" },
                { type = "paragraph", text = "|cffffd700Show the unit's level|r adds the level to the name on every bar that shows one, and the rank shortens to the form vanilla has always used - a |cffffd700+|r for elite:" },
                { type = "table", columns = { "The unit is", "The bar says" }, rows = {
                    { "An ordinary mob", "62" },
                    { "Rare", "62 Rare" },
                    { "Elite", "62+" },
                    { "Rare elite", "62 Rare+" },
                    { "A world boss", "?? Boss" },
                } },
                { type = "note", text = "|cffffd700??|r is the game declining to put a number on it, which it does for anything far enough above you that the number stopped being the point." },
                { type = "paragraph", text = "The words appear in any wording that shows a name - Name, Name and percent, Everything. The wordings that are deliberately just a number stay just a number. The icon leads whatever the bar says, and the glow does not care which wording you use." },
                { type = "paragraph", text = "Nameplates say the same thing in the same words, worked out in the same place, so a plate and a target bar looking at one mob can never disagree about what it is. Plates say it in words only: a glow around something that small is a smudge, which is the same reason your target's plate is marked with a border rather than a glow." },
            },
        },

        {
            title = "Building a party layout",
            blocks = {
                { type = "paragraph", text = "You cannot arrange party frames with nobody in your party, and waiting until you have four people to find out the text does not fit is no way to do it. So bars for units that are not there stand in for a plausible group instead." },
                { type = "h3", text = "Making the bars" },
                { type = "paragraph", text = "Open Edit Mode, click |cffffd700Create|r, and pick |cffffd700Party frames (all four)|r. That makes a health bar and a power bar for each member, the power docked under the health, stacked down the left of the screen." },
                { type = "note", text = "Each member is a stack of their own rather than one chain of all four. Chained, deleting party one's power bar would take party two, three and four with it, and copying everything under party one would copy the entire party." },
                { type = "h3", text = "Seeing what it will look like" },
                { type = "paragraph", text = "Edit Mode turns the preview on by itself, so the four bars appear the moment you open it. Each slot stands in for the same made-up member every time - a different class color, a different amount of health - because a preview that reshuffles while you drag is one you cannot compare against itself." },
                { type = "paragraph", text = "The text runs through whatever wording that bar is set to, so what you are judging is the line you are actually going to get: whether a name of real length fits, whether a half-empty bar still reads at the height you chose, what four class colors look like stacked up." },
                { type = "note", text = "The name stays the slot's own - |cffffd700Party 1|r rather than an invented person - so you can always tell which bar you have hold of." },
                { type = "paragraph", text = "|cffffd700Preview units that are not there|r on the General page keeps it on outside Edit Mode, for judging a layout against the rest of your screen. It lasts until you reload. |cffffd700/bazframes preview|r does the same." },
            },
        },

        {
            title = "Two wordings on one bar",
            blocks = {
                { type = "paragraph", text = "A bar can say one thing while you are not looking at it and another while you are. |cffffd700Text says|r is the everyday wording; |cffffd700When hovered|r is what it changes to under the cursor." },
                { type = "paragraph", text = "The point is that a bar has two jobs and not enough room for both. At a glance you want to know who it is - a name, a level, a rough percentage. When you stop and look, you want the numbers." },
                { type = "h3", text = "A worked example" },
                { type = "table", columns = { "Setting", "Choice" }, rows = {
                    { "Show text", "Always" },
                    { "Text says", "Name and percent" },
                    { "When hovered", "Current / Max" },
                } },
                { type = "paragraph", text = "Sitting there it reads |cffffd700Old Icebeard  100%|r. Put the cursor on it and it reads |cffffd7004250 / 4250|r, and it goes back when you move away." },
                { type = "note", text = "|cffffd700Same as usual|r is the default, and means the bar says one thing all the time - which is how every bar behaved before this existed." },
                { type = "h3", text = "Level, and Name and level" },
                { type = "paragraph", text = "Two of the wordings ask for the unit's level outright, rather than leaving it to the |cffffd700Show the unit's level|r switch. They are useful as the resting half of a pair - |cffffd700Name and level|r sitting there, the numbers on hover." },
                { type = "paragraph", text = "A wording that asks for the level carries the rank with it and |cffffd700does not say it twice|r, so it reads the same whether or not that switch is on." },
                { type = "note", text = "These two are offered on health and power bars only. A reputation bar has no level at all, and an experience bar already writes your level into its name, so offering them there would be offering the same thing twice." },
                { type = "h3", text = "How it fits with Show text" },
                { type = "paragraph", text = "|cffffd700Show text|r decides when there is any text at all, and the two wordings decide what it says. Set it to |cffffd700On Hover|r and the bar is blank until you touch it, then shows the hover wording. Set it to |cffffd700Never|r and neither wording is used - and the bar does not take the mouse for it either, so it stays click-through." },
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
                { type = "paragraph", text = "Everything that is only a readout - colors, text, fading - keeps working normally." },
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
