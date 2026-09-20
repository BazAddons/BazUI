-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Nameplates User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Nameplates", {
    title = "Nameplates",
    intro = "The bar over a unit's head, in the same look as everything else "
        .. "in the addon.",

    pages = {
        {
            title = "What it does",
            blocks = {
                { type = "paragraph", text = "Every unit the game gives a nameplate gets one of ours instead: a health bar with the unit's name above it and its level on the right, wearing the suite's border and fill." },
                { type = "paragraph", text = "Color says what a unit is. Red will attack you, amber has not decided, green will not. Players take their class color, unless you would rather they matched everything else." },
                { type = "paragraph", text = "Rank is said in words on the right of the bar, in the same wording the unit bars use and worked out in the same place, so a plate and a target bar looking at one mob cannot disagree about whether it is rare." },
                { type = "note", text = "|cffffd700Open it with|r /bazplates, or Options > AddOns > BazUI > Nameplates." },
            },
        },

        {
            title = "One kind of unit at a time",
            blocks = {
                { type = "paragraph", text = "A city guard and something trying to kill you are not the same thing, and they do not have to look the same. The module sorts every plate into one of six kinds and each kind has its own switches." },
                { type = "table", columns = { "Kind", "What lands in it" }, rows = {
                    { "Tapped by someone else", "A mob somebody else got to first, which you can hit but cannot loot. Tested before the hostile kinds, because knowing it is not yours is the more useful fact. Use it to turn plates for those mobs down or off - it does not recolour them." },
                    { "Friendly players", "Other players on your side." },
                    { "Hostile players", "Players you can attack." },
                    { "Friendly NPCs", "Guards, vendors, quest givers." },
                    { "Neutral NPCs", "Mobs that leave you alone until you start something." },
                    { "Hostile NPCs", "Anything that will attack you on sight, and anything the other five could not place." },
                } },
                { type = "paragraph", text = "Each kind can turn its nameplate, health bar, name, level, rare and elite mark and class color on or off by itself. A kind with no health bar is a name and nothing else, and the plate shrinks to suit rather than leaving a gap where the bar was. A kind with its nameplate off shows nothing at all - not ours and not the game's." },
                { type = "paragraph", text = "That last one is worth a word, because it looks like a second answer to a question the game already answers. It is not. The game cannot split this as finely: Interface Options has a single switch for all enemies, so hostile players and hostile NPCs go together there, and it has nothing whatever for mobs somebody else has tagged. Here they are separate." },
                { type = "note", text = "These switches only ever take plates away. If the game is not offering a unit a plate, there is nothing here to hide - so a plate you cannot find is always explained by one page or the other, and with everything on here the game is as much in charge as it ever was." },
                { type = "note", text = "A crowded capital is what this is for: names on the friendly NPCs, bars on everything else, and you can still read the place." },
                { type = "paragraph", text = "Every kind starts as whatever the General and Size and Text switches say and keeps its own answer from the moment you touch it, so nothing changes until you want it to. Class color is greyed out on the NPC kinds and the rare and elite mark on the player kinds, because neither applies - the switch stays visible so you are not left hunting for one that moved." },
                { type = "paragraph", text = "Pets, guardians, totems and minions are not kinds of their own. The game treats them as a visibility category and colors them by whose side they are on, and so do we: a hostile warlock's felhunter is a hostile NPC. A kind that outranked friendly and hostile both would read wrong the first time one attacked you." },
            },
        },

        {
            title = "What this module does not decide",
            blocks = {
                { type = "paragraph", text = "This is worth reading before you go looking for a setting that is not here." },
                { type = "paragraph", text = "|cffffd700How many plates you see, how far away they appear, and whether friendly units get one at all|r are the game's own settings, not this module's. They live in Interface Options under Names, with console variables behind them." },
                { type = "paragraph", text = "A second set of switches here that disagreed with those would only be a way to end up with plates you cannot explain. So the module takes what the game gives it and draws that." },
                { type = "paragraph", text = "|cffffd700Replace friendly plates|r is the one place the two meet: it decides whether a friendly unit that already has a plate gets ours or keeps the game's. It cannot make one appear that the game was not going to show." },
            },
        },

        {
            title = "Settings",
            blocks = {
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Class color on players", "A player's plate takes their class color instead of the hostile/neutral/friendly colors." },
                    { "Replace friendly plates", "Friendly units get a BazUI plate too. Off leaves them with the game's own." },
                    { "Mark your target", "A gold border on the plate of whatever you have targeted - a border rather than a glow, because a glow at this size is a smudge. It is drawn on the health bar, so a kind you have set to name-only has no border to take." },
                    { "Width / Height", "The health bar. Height is the height of the fill; the border is added around it, so the plate comes out taller than this by however thick your border is." },
                    { "Show level", "The unit's level on the right of the bar. Two question marks mean it is far enough above you that the number stopped being the point." },
                    { "Mark rares and elites", "The unit's rank beside the level: an elite reads 62+, a rare elite 62 Rare+, a world boss ?? Boss. Ordinary mobs are left unmarked, which is what makes a marked one worth a second look. With the level switched off the rank is spelled out on its own." },
                    { "Name size", "The name above the bar." },
                } },
            },
        },

        {
            title = "The game's own plates",
            blocks = {
                { type = "paragraph", text = "Blizzard's plate is not deleted, it is made invisible - and it is held that way, because the game turns its own art back on whenever it feels like it. Ours is hung on the same frame, so it follows the unit exactly as the game intends, including going away when the unit does." },
                { type = "paragraph", text = "Turn the module off and Blizzard's plates come back at the next reload, which you are prompted for when you throw the switch." },
            },
        },
    },
})
