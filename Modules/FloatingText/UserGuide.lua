-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Floating Text: the manual page
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("FloatingText", {
    title = "Floating Text",
    intro = "The numbers that rise off a fight.",
    pages = {
        {
            title = "What it does",
            blocks = {
                { type = "paragraph", text = "What you hit for, what hit you, what you healed, and the misses and dodges in between - drawn in BazUI's font, in two areas you place yourself." },
                { type = "paragraph", text = "It starts |cffffd700off|r. It draws over the middle of the screen, and a module that begins doing that without being asked is one you go hunting for the switch to. Turn it on at the top of its page." },
                { type = "note", text = "|cffffd700Open it with|r /bazfct, or Options > AddOns > BazUI > Floating Text." },
                { type = "h2", text = "Two areas" },
                { type = "table", columns = { "Area", "What lands in it" }, rows = {
                    { "|cffffd700Incoming|r", "What is happening to you: damage you take, heals you receive." },
                    { "|cffffd700Outgoing|r", "What you are doing: your damage, your healing." },
                } },
                { type = "paragraph", text = "Which one a number goes to is not a guess. The game tells us who |cffffd700took|r the hit, so anything landing on you is incoming and anything landing on anybody else is outgoing." },
                { type = "note", style = "tip", text = "Open |cffffd700BazUI Edit Mode|r and each area shows its bounds and its name, so you can drag it where you want. The rest of the time an area is only a space - there is nothing to see but the numbers." },
                { type = "note", text = "|cffffd700How far they travel|r is also the height of the area. The two are the same thing on purpose: what you drag in Edit Mode is the space the numbers actually use, so nothing ever rises out of the box you put it in." },
            },
        },
        {
            title = "The numbers",
            blocks = {
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Size", "An ordinary hit. Everything else is measured from this." },
                    { "Outline", "None, thin or thick. Numbers are drawn over the world rather than over a panel, so an outline is usually what makes them readable against grass." },
                    { "How long they last", "Seconds from appearing to gone. They stay solid for most of that and fade only at the end." },
                    { "How far they travel", "How high a number climbs in its lifetime, and how tall the area is." },
                    { "Crit size", "How much bigger a critical or crushing hit is drawn. At 1 they are the same as any other hit." },
                    { "Mark crits with stars", "Draws a crit as *1234*. Size alone only tells you it was a crit if there is an ordinary hit beside it to compare against." },
                    { "Color by damage school", "Fire orange, frost blue, shadow purple, nature green, holy gold, arcane pink, physical white - the game's own school colors. Off draws all damage white." },
                } },
                { type = "note", text = "A glancing blow is drawn slightly smaller, and the words - Miss, Dodge, Parry - smaller still. None of those is the thing you were watching for." },
            },
        },
        {
            title = "Adding up rapid hits",
            blocks = {
                { type = "paragraph", text = "A fight is mostly the same mob hitting you four times a second. Six numbers climbing the screen say nothing that one number does not, so |cffffd700Add up rapid hits|r collects everything inside a short window and shows the total." },
                { type = "paragraph", text = "It is off by default, because it is a friendly kind of lie: the total is true, and how many times you were hit is gone." },
                { type = "note", style = "tip", text = "|cffffd700Crits are never merged.|r The reason to want a crit on screen is that it was a crit, and folding it into a running total throws away exactly the thing you wanted to see." },
                { type = "note", text = "The total appears when the window closes rather than when it opens, so what you see is the whole of what happened rather than the first hit of it with the rest arriving behind." },
            },
        },
        {
            title = "What it can and cannot show",
            blocks = {
                { type = "paragraph", text = "It shows damage, healing, power returned, and the misses, dodges and parries - on you, on your target, and on anything with a nameplate. That covers what is happening in a fight around you." },
                { type = "paragraph", text = "It does not show |cffffd700spell names|r, and it cannot break damage down by who did it. A number tells you what landed and what kind it was, not which player or which spell it came from. If you are looking for that, a damage meter is the tool for it." },
                { type = "note", text = "This is a limit of what the game tells addons on WoW: Forever, not a setting you are missing." },
            },
        },

        {
            title = "Turning the module off",
            blocks = {
                { type = "paragraph", text = "The switch is on |cffffd700BazUI > General|r with the rest of the module switches, and there is one at the top of this module's own page as well." },
                { type = "paragraph", text = "With it off, anything still on screen is cleared straight away and the game's own floating combat text comes back." },
            },
        },
    },
})
