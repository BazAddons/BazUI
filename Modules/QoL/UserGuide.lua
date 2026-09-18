-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Quality of Life User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("QoL", {
    title = "Quality of Life",
    intro = "Small changes to how the game behaves rather than how it looks. "
        .. "Every one of them starts off, bar the draggable windows.",

    pages = {
        {
            title = "How this module works",
            blocks = {
                { type = "paragraph", text = "Each tweak is one switch and does one thing. They start off, and that is deliberate: these change what the game does rather than how it looks, and a switch you did not throw yourself is one you cannot find again when you want it back." },
                { type = "paragraph", text = "The draggable windows are the exception and start on. Making a window draggable does nothing at all until you drag it, so there is no surprise to protect you from - and a window you cannot move is a thing people go looking for a setting to fix." },
                { type = "paragraph", text = "Two kinds live here. Some set a console setting the game already has - those remember what you had before and put it back when you switch them off. The rest listen for something happening and act when it does; they ask whether they are switched on at the moment they fire, so one that is off is genuinely doing nothing." },
                { type = "note", text = "|cffffd700Open it with|r /bazqol, or Options > AddOns > BazUI > Quality of Life." },
            },
        },

        {
            title = "Quests",
            blocks = {
                { type = "h3", text = "Instant quest text" },
                { type = "paragraph", text = "Quest text appears at once instead of fading in a word at a time. The game has this setting too, under Interface, Controls - this is the same switch, put somewhere you will find it." },
            },
        },

        {
            title = "Vendors",
            blocks = {
                { type = "h3", text = "Repair automatically" },
                { type = "paragraph", text = "Repairs everything the moment you open a merchant that can. Guild funds are used first where they are available and you are allowed them, so it costs you nothing before it costs you money. What it spent is printed in chat." },
                { type = "h3", text = "Sell grey items" },
                { type = "paragraph", text = "Sells every poor quality item in your bags when you open a merchant. Only grey, and only grey that is worth something - a grey with no vendor price is a quest leftover and cannot be sold anyway." },
                { type = "note", text = "The Bags module has a button that does the same thing on demand, if you would rather decide each time than have it happen automatically." },
            },
        },

        {
            title = "Draggable windows",
            blocks = {
                { type = "paragraph", text = "The game places its own panels where it wants them, and puts them back there every time they open. Each switch here hands one of those windows back to you: drag it by its frame, and it opens where you left it from then on - across sessions, not just until you log out." },
                { type = "paragraph", text = "One switch per window, because wanting to move the character sheet says nothing about wanting to move the mailbox. A window your client does not have gets no switch at all." },
                { type = "note", text = "|cffffd700The map|r is only draggable while it is windowed. Full screen has nowhere to be dragged to." },
                { type = "paragraph", text = "The options window is on this list too - the game's settings, and BazUI's own pages inside it. Blizzard marked that one movable years ago and never wired the scripts to go with it." },
                { type = "note", text = "|cffffd700Forget where I put them|r clears every saved position at once, and the windows open where the game puts them again." },
            },
        },

        {
            title = "Convenience",
            blocks = {
                { type = "h3", text = "Screenshot when you level" },
                { type = "paragraph", text = "Takes a screenshot each time you gain a level. They land in your Screenshots folder." },
                { type = "h3", text = "Decline duels" },
                { type = "paragraph", text = "Turns down duel requests without showing you the popup. Nothing is said to whoever asked." },
                { type = "h3", text = "Zoom the camera out further" },
                { type = "paragraph", text = "Raises the furthest the camera will pull back to the most the game allows. The game resets this on its own sometimes, which is exactly why it is worth having a switch for rather than typing a console command and hoping." },
            },
        },
    },
})
