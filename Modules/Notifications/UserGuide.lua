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
                { type = "paragraph", text = "Thirteen sources watch the game and report what they see, and a fourteenth appears if you have Zygor. Each report becomes a card, and a card can arrive in up to three places: as a toast on screen, as a line in the history panel, and as a line in your chat box." },
                { type = "paragraph", text = "The band down the left of a card is the color of the source it came from - quests yellow, loot blue, experience purple - so a panel with a dozen things in it groups by eye before you read a word. How solid that band is says how much the card wanted your attention." },
                { type = "h3", text = "The bell" },
                { type = "paragraph", text = "The bell is where the history lives, and it carries a count of what you have not read. Drag it in Edit Mode: toasts and the panel follow it and grow away from whichever screen corner it is nearest, so putting the bell somewhere sensible is the only positioning you have to do." },
                { type = "list", items = {
                    "|cffffd700Click|r it for the panel.",
                    "|cffffd700Right-click|r it to clear everything waiting there.",
                } },
                { type = "note", text = "Dragged somewhere you cannot reach, |cffffd700Reset to top left|r and |cffffd700Reset to top right|r on the General page bring it back." },
                { type = "note", text = "|cffffd700Open it with|r /bnc, or Options > AddOns > BazUI > Notifications." },
            },
        },

        {
            title = "Where each event goes",
            blocks = {
                { type = "paragraph", text = "This is the setting that matters. Every event a source reports has its own row on the Sources page, with a tick box per destination." },
                { type = "table", columns = { "Tick", "What happens" }, rows = {
                    { "Toast", "A toast on screen when it happens, and a line in the history." },
                    { "Chat", "The same thing printed in your chat box." },
                    { "Default", "Only on events that replace something the game shows. Ticking it puts the game's own version back - see below." },
                } },
                { type = "paragraph", text = "Tick either, both, or neither. |cffffd700Neither means the event is not reported at all|r, and that includes the history: a source with nothing wanted from it stops listening rather than filing into a panel nobody asked for." },
                { type = "note", text = "Turn the noisy events down rather than turning a whole source off. Losing every loot notification because gold gains were chatty is the thing this avoids." },
                { type = "h3", text = "The Default tick" },
                { type = "paragraph", text = "A few events exist because BazUI is showing something in the game's place: item loot, quest objective progress, levelling up, and the whole System set. Those rows carry a third tick labelled |cffffd700Default|r, and it reads the way it sounds - tick it and the game's own display comes back alongside this one." },
                { type = "note", text = "The level-up display is the one that takes a reload to restore, and you are asked for one when you tick it." },
                { type = "h3", text = "Per source" },
                { type = "list", items = {
                    "|cffffd700Toast duration|r - how long this source's toasts stay up, overriding the default.",
                    "|cffffd700Sound|r - a sound for this source, or the one picked by priority.",
                    "|cffffd700Blizzard UI|r - one switch lives here rather than on an event row: |cffffd700Hide the loot window|r, under Loot.",
                } },
            },
        },

        {
            title = "Toasts",
            blocks = {
                { type = "paragraph", text = "A toast stacks with the others and takes itself away after its time is up." },
                { type = "table", columns = { "You do this", "It does this" }, rows = {
                    { "Hover it", "The countdown stops while your cursor is on it, and restarts a couple of seconds after you leave. Nothing vanishes while you are reading it." },
                    { "Click it", "Does whatever that card is for - opens the thing it is about - and dismisses it. With nothing to open, it opens the history panel instead." },
                    { "Ctrl-click an item", "Opens the dressing room with it." },
                    { "Shift-click an item", "Drops its link into whatever you are typing." },
                } },
            },
        },

        {
            title = "What each source reports",
            blocks = {
                { type = "table", columns = { "Source", "Events" }, rows = {
                    { "Loot",        "Item loot, coin gains. Set a minimum quality, skip quest items, auto-loot, and hide the game's own loot window." },
                    { "Quests",      "Accepted, objective progress, completed." },
                    { "XP",          "XP gains, level up, rested experience at login." },
                    { "Reputation",  "Reputation gains and losses, and standing milestones." },
                    { "Social",      "Whispers, friends on and offline, guild members on and offline, group requests. Guild members going offline starts switched off." },
                    { "Group",       "Members joining and leaving, and pull timers." },
                    { "Instance",    "Entering an instance, and leaving one." },
                    { "Zones",       "Zones and sub-zones as you cross into them." },
                    { "Mail",        "New mail, and what was in it when you open it." },
                    { "Auction",     "Sold, expired, outbid, won." },
                    { "Inventory",   "Bags nearly full, low durability, equipment repaired. Warn when free slots reach, and when durability falls below, are both yours to set." },
                    { "Professions", "Crafts completed, and skill level ups." },
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
                    "|cffffd700Notifications|r groups by source, with a filter for one at a time, and clears a whole source from its group header.",
                    "|cffffd700History|r runs by date instead, with a separator per day, a search box, and a dropdown for today, yesterday, this week or this month.",
                    "Right-click a card to dismiss it; the X in the corner does the same.",
                    "A card that came with an item lets you ctrl-click to try it on and shift-click to link it in chat.",
                } },
                { type = "paragraph", text = "The button at the top of the panel changes with the tab: |cffffd700Clear all|r on Notifications, and |cffffd700Purge|r on History, which empties the archive for good and asks first. |cffffd700Load More|r at the foot of the history fetches the next page of it." },
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
                    { "Play sounds", "Whether a notification makes any sound at all." },
                    { "High / Normal / Low priority sound", "A sound each, for the three levels of urgency. Grayed out while sounds are off." },
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
                    { "/bnc clear", "Clears what is waiting. The history is untouched; the panel's Purge button is what empties that." },
                    { "/bnc test", "Sends one test notification." },
                    { "/bnc testall", "Sends a burst of them - zones, loot and quests - for seeing what a full panel looks like." },
                    { "/bnc scaffold <name>", "Prints a starting template for an addon of your own that reports through this center." },
                    { "/bnc settings", "Opens the settings page. Every BazUI command takes this, and |cffffd700help|r." },
                } },
            },
        },
    },
})
