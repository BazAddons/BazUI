-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Notifications User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Notifications", {
    title = "Notifications",
    intro = "The things worth knowing about, in one place: a toast when they "
        .. "happen and a history you can go back through.",

    pages = {
        {
            title = "How it works",
            blocks = {
                { type = "paragraph", text = "Fourteen sources watch the game and report what they see. Each report becomes a card, and a card can arrive in up to three places: as a toast on screen, as a line in the history panel, and as a line in your chat box." },
                { type = "paragraph", text = "The band down the left of a card is the color of the source it came from - quests yellow, loot blue, experience purple - so a panel with a dozen things in it groups by eye before you read a word. How solid that band is says how much the card wanted your attention." },
                { type = "h3", text = "The bell" },
                { type = "paragraph", text = "The bell is where the history lives, and it carries a count of what you have not read. Drag it in Edit Mode: toasts and the panel follow it and grow away from whichever screen corner it is nearest, so putting the bell somewhere sensible is the only positioning you have to do." },
                { type = "note", text = "|cffffd700Open it with|r /bnc, or Options > AddOns > BazUI > Notifications." },
            },
        },

        {
            title = "One choice per event",
            blocks = {
                { type = "paragraph", text = "This is the setting that matters. Every event a source reports has its own three-way choice on the Sources page:" },
                { type = "table", columns = { "Choice", "What happens" }, rows = {
                    { "Off", "Never reported at all." },
                    { "History only", "Kept in the panel, no toast. Good for anything you want a record of but not an interruption from." },
                    { "Toast", "A toast when it happens, and a line in the history." },
                } },
                { type = "paragraph", text = "Some events also offer |cffffd700Chat|r, which prints the same thing in your chat box. Turn the noisy ones down rather than turning a whole source off - losing every loot notification because gold gains were chatty is the thing this avoids." },
                { type = "h3", text = "Per source" },
                { type = "list", items = {
                    "|cffffd700Toast duration|r - how long this source's toasts stay up, overriding the default.",
                    "|cffffd700Sound|r - a sound for this source, or the one picked by priority.",
                    "|cffffd700Blizzard UI|r - where a source replaces something the game shows, its switch to hide the stock version lives here. Nothing is hidden unless you ask.",
                } },
            },
        },

        {
            title = "What each source reports",
            blocks = {
                { type = "table", columns = { "Source", "Events" }, rows = {
                    { "Loot",        "Item loot, coin gains. Set a minimum quality, skip quest items, and hide the game's own loot window." },
                    { "Quests",      "Accepted, objective progress, completed." },
                    { "XP",          "XP gains, level up, rested experience at login." },
                    { "Reputation",  "Standing gains and losses, and standing changes." },
                    { "Social",      "Whispers, friends on and offline, guild members on and offline, group requests." },
                    { "Group",       "Group and role events." },
                    { "Instance",    "Dungeon and raid entries and lockouts." },
                    { "Zones",       "Zones and sub-zones as you cross into them." },
                    { "Mail",        "New mail and returned mail." },
                    { "Auction",     "Sold, expired, outbid, won." },
                    { "Inventory",   "Bags nearly full, low durability, equipment repaired. Both thresholds are yours to set." },
                    { "Professions", "Crafting completions." },
                    { "System",      "Danger and PvP warnings, errors, info, zone and boss warnings, raid warnings, event banners." },
                    { "Zygor",       "Only present if you have Zygor installed - see the next page." },
                } },
                { type = "note", text = "A source with nothing switched on costs nothing: it stops listening rather than reporting into a void." },
            },
        },

        {
            title = "Zygor",
            blocks = {
                { type = "paragraph", text = "Zygor keeps a notification center of its own. If you run both, that is two places to look and two different-looking toasts for the same class of thing. This section only exists if Zygor is installed." },
                { type = "list", items = {
                    "Its notifications are repeated through this center, with its own mark on them.",
                    "Clicking one does what clicking Zygor's own notification would have done - opening the skills window, jumping to a guide - and takes it off Zygor's list too, so one notification in two places does not need answering twice.",
                    "|cffffd700Hide Zygor's own popup|r stops its toast, so you only see ours. Turn it off and you get Zygor's back, with no reload.",
                } },
                { type = "note", text = "Zygor's own settings still decide whether a notification happens at all. If it is switched off, or has notifications switched off, there is nothing here to forward." },
            },
        },

        {
            title = "The history panel",
            blocks = {
                { type = "paragraph", text = "Click the bell. Two tabs: |cffffd700Notifications|r is what is current, |cffffd700History|r is everything kept." },
                { type = "list", items = {
                    "Grouped by source, with a filter for one at a time.",
                    "Right-click a card to dismiss it; the X in the corner does the same.",
                    "Clear a whole source from its group header.",
                    "A card that came with an item lets you ctrl-click to try it on and shift-click to link it in chat.",
                } },
                { type = "h3", text = "How long it keeps" },
                { type = "paragraph", text = "|cffffd700Keep history for|r is 1 to 90 days, seven by default, trimmed at login. History is kept per account rather than per character, so it survives a profile change." },
            },
        },

        {
            title = "Do Not Disturb",
            blocks = {
                { type = "paragraph", text = "Silences toasts and sounds. Notifications still land in the history, so nothing is lost - you just are not interrupted." },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Do Not Disturb", "On or off, by hand. /bnc dnd toggles it." },
                    { "Turn on in combat", "Quiet while you are fighting." },
                    { "Turn on during boss encounters", "Quiet for the length of an encounter." },
                } },
            },
        },

        {
            title = "General settings",
            blocks = {
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Show toasts", "Off keeps everything in the history panel only." },
                    { "Default duration", "How long a toast stays up, for sources that do not set their own." },
                    { "Toast size", "How large the pop-ups are." },
                    { "Show a sample", "Raises a few toasts so you can size them against the real thing. They never reach your history." },
                    { "Play sounds", "The sound a notification makes, picked by how urgent it is." },
                    { "Background opacity", "How see-through the history panel is." },
                    { "Scale", "The bell and the panel." },
                    { "Keep history for", "1 to 90 days." },
                } },
            },
        },

        {
            title = "For addon authors",
            blocks = {
                { type = "paragraph", text = "Any addon can report through this center. Both calls do nothing at all if BazUI is not installed, so nothing needs guarding:" },
                { type = "code", text = "BazUI:RegisterNotificationModule(\"MyAddon\", {\n    label = \"My Addon\",\n    icon  = \"Interface\\\\Icons\\\\INV_Misc_Bell_01\",\n})\n\nBazUI:PushNotification({\n    module   = \"MyAddon\",\n    title    = \"Something happened\",\n    message  = \"The detail underneath\",\n    priority = \"high\",          -- high, normal or low\n    onClick  = function() end,  -- optional: what clicking it does\n})" },
                { type = "paragraph", text = "Registering is optional - a push from a module nobody registered registers it on the way through. A source that brings a |cffffd700color|r gets that color on its band; one that does not gets a default." },
                { type = "paragraph", text = "|cffffd700emphasis = true|r draws the message large and bright instead of small and quiet, for a card whose message is the point of it rather than a footnote to the title - an amount of coin, an amount of experience. Use it sparingly: it only means anything while most cards are not doing it." },
            },
        },

        {
            title = "Slash commands",
            blocks = {
                { type = "table", columns = { "Command", "What it does" }, rows = {
                    { "/bnc", "Opens the notification panel. /baznotify does the same." },
                    { "/bnc dnd", "Do Not Disturb on or off." },
                    { "/bnc history", "Opens the history." },
                    { "/bnc clear", "Clears every notification." },
                    { "/bnc test", "Sends one test notification." },
                    { "/bnc testall", "Sends one from every source - the quick way to see what a full panel looks like." },
                } },
            },
        },
    },
})
