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
                    { "Mark your target", "A gold border on the plate of whatever you have targeted - a border rather than a glow, because a glow at this size is a smudge." },
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
                { type = "paragraph", text = "Turn the module off and Blizzard's plates come straight back." },
            },
        },
    },
})
