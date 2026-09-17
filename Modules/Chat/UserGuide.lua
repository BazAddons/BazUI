-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Chat User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Chat", {
    title = "Chat",
    intro = "A chat window of our own, with tabs you decide the contents of, "
        .. "timestamps in a gutter, history that survives a reload, and text "
        .. "you can copy out.",

    pages = {
        {
            title = "What it does",
            blocks = {
                { type = "paragraph", text = "This module builds its own chat windows rather than redressing Blizzard's. What comes out looks familiar - the same colors, the same gold names, the same clickable links - because the game still writes the messages and still resolves the links. What changes is everything around them." },
                { type = "list", items = {
                    "|cffffd700Tabs|r you create, rename, reorder and delete, each subscribing to its own set of channels.",
                    "|cffffd700The combat log as a real tab|r, with the game's own filter buttons on it instead of stranded off screen.",
                    "|cffffd700Timestamps in a left gutter|r, with a colored bar tying a wrapped line back to its stamp.",
                    "|cffffd700History that survives|r a reload and a relog, replayed with the times the messages actually arrived.",
                    "|cffffd700Copy chat|r, which the game does not let you do at all.",
                    "|cffffd700Up and Down|r in the chat box to step back through what you have typed.",
                    "|cffffd700Shorter channel prefixes|r, if you would rather read [g] than [Guild].",
                } },
                { type = "note", text = "|cffffd700Open it with|r /bazchat or /bc, or Options > AddOns > BazUI > Chat." },
            },
        },

        {
            title = "Tabs",
            blocks = {
                { type = "paragraph", text = "You start with four - |cffffd700General, Guild, Trade|r and |cffffd700Log|r - and can add as many more as you want." },
                { type = "h3", text = "Making and naming" },
                { type = "list", items = {
                    "The |cffffd700+|r at the right end of the tab strip makes a new one.",
                    "Right-click a tab for its menu: Rename, Channels, Clear, Lock, Move to, Delete. The Channels popup has a Name field too.",
                    "The |cffffd700Tabs|r page lists every tab with the same name field and an Edit Channels button.",
                } },
                { type = "h3", text = "Deleting and reordering" },
                { type = "list", items = {
                    "Right-click, then Delete tab. No reload needed.",
                    "|cffffd700General cannot be deleted.|r It owns the default chat target - the thing that decides where Enter sends a message and where an addon's printed line lands.",
                    "Click and hold a tab for about two seconds to pick it up, then drop it either side of another to reorder.",
                } },
                { type = "h3", text = "Auto-show" },
                { type = "paragraph", text = "Each tab has an auto-show mode on the Tabs page. The default is |cffffd700Always|r; the rest keep the tab out of the way until it is relevant." },
                { type = "table", columns = { "Mode", "The tab is there when" }, rows = {
                    { "Always", "At all times. The default." },
                    { "In a city", "You are in a sanctuary zone - the default for Trade." },
                    { "In a guild", "You are in one - the default for Guild, so the tab is not there on a character who has not joined yet." },
                    { "In a party", "You are in a party and not a raid." },
                    { "In a raid", "You are in a raid." },
                    { "In combat", "You are fighting." },
                    { "In a battleground or arena", "You are in either." },
                    { "In a dungeon or raid", "You are in any instance." },
                } },
                { type = "note", text = "If the tab you are looking at goes away - you leave the raid while the Raid tab is up - the window falls back to General rather than leaving you staring at nothing." },
                { type = "h3", text = "Starting over" },
                { type = "paragraph", text = "|cffffd700Reset Tabs to Defaults|r on the Tabs page throws away the tabs you made and puts the original four back with their channels. Your appearance settings are left alone - only the tab structure resets." },
            },
        },

        {
            title = "Channels",
            blocks = {
                { type = "paragraph", text = "Every tab has its own subscription. Right-click a tab and pick |cffffd700Channels|r for a two-column popup that decides exactly what flows into it." },
                { type = "list", items = {
                    "|cffffd700Categories|r - the game's own groupings: Say, Emote, Guild, Whispers, Party, Raid, Battleground, System, Errors, Loot, Skill and the rest. One switch each.",
                    "|cffffd700Named channels|r - a row for each channel you have joined, including custom ones. Switch them one at a time, so a Trade-only tab or a tab with LocalDefense muted is a matter of ticking boxes.",
                } },
                { type = "h3", text = "Shorter prefixes" },
                { type = "paragraph", text = "On the |cffffd700Channel Names|r page:" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Shorten channel prefixes", "[Guild] becomes [g], [Party Leader] becomes [pl], and so on." },
                    { "Strip channel numbers", "[1. General - Stormwind] becomes [General]. Independent of the setting above - you can have one without the other." },
                } },
                { type = "h3", text = "Guild message of the day" },
                { type = "paragraph", text = "Shown once a session, on a cold login and after a reload, rather than every time something makes the game re-send it. A genuine change to it while you are playing comes through as guild chat, as it should." },
            },
        },

        {
            title = "The combat log",
            blocks = {
                { type = "paragraph", text = "The combat log lands on the |cffffd700Log|r tab instead of on a chat frame you cannot see. The game's own row of filter buttons - My Actions, What Happened to Me, and the Additional Filters dropdown - is moved onto that tab and follows it when you resize the window." },
                { type = "paragraph", text = "|cffffd700The parsing and filtering are still the game's.|r This module only decides where the output goes, so every filter you have set up, custom ones included, keeps working exactly as it did." },
                { type = "paragraph", text = "The Log tab can be deleted like any other, and stays deleted. |cffffd700Reset Tabs to Defaults|r is how you get it back." },
            },
        },

        {
            title = "Timestamps",
            blocks = {
                { type = "paragraph", text = "Timestamps go in a gutter down the left rather than in front of the message. That is what keeps a wrapped line flush with the line above it instead of tucked under the clock, and it is why a long message still reads as one block." },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Show timestamps", "The gutter, with a vertical bar in the message's own chat color." },
                    { "Format", "24-hour (14:32), 24-hour with seconds (14:32:09), 12-hour (2:32 PM), or 12-hour with seconds (2:32:09 PM)." },
                    { "Show date tooltip on hover", "Hover a stamp for the full date - weekday, month, day, year - for when the exact day matters." },
                } },
                { type = "h3", text = "The colored bar" },
                { type = "paragraph", text = "The bar takes the message's chat color - green for guild, pink for whispers, a custom channel's own color - and runs the full height of the message, wrapped lines included. Colors come from the game's own chat color table, so changing one there changes it here with no reload." },
                { type = "note", text = "Replayed history keeps its |cffffd700original|r times. A line from nine in the morning still reads 09:00:00 when you log back in at noon - the time is stored with the text rather than worked out at replay." },
            },
        },

        {
            title = "Appearance",
            blocks = {
                { type = "paragraph", text = "These are on the |cffffd700Appearance|r page and on the window's Edit Mode popup, so you can set them while you are looking at the window." },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Use the BazUI chat font", "DorisPP, the face the addon ships. Off goes back to the game's font." },
                    { "Text size", "Scales the text against the size set in the game's own chat options. The text only, not the window." },
                    { "Text opacity", "The foreground - text and scrollbar." },
                    { "Background opacity", "The panel behind it, separately. Drop this for a panel that fades away under text that stays readable." },
                    { "Tabs opacity", "The tab strip when it is shown." },
                    { "Window scale", "The whole window." },
                } },
                { type = "h3", text = "What is visible, and when" },
                { type = "paragraph", text = "The background, the tab strip and the scrollbar each have their own mode." },
                { type = "table", columns = { "Mode", "What happens" }, rows = {
                    { "Always visible", "The default for all three." },
                    { "On hover", "Fades in when your cursor is over the chat or the strip, holds a moment, then fades out. Background and tabs." },
                    { "On scroll", "Scrollbar only: appears when you scroll or hover, gone a couple of seconds later." },
                    { "Never", "Not drawn at all. The mouse wheel still scrolls." },
                } },
                { type = "paragraph", text = "|cffffd700Unified background + tabs|r ties the first two together: set it to anything other than Independent and both follow it, with their own dropdowns grayed out to say so." },
                { type = "note", text = "Edit Mode forces all of it visible while you are laying the window out, so a chat set to fade away is still something you can find and drag." },
            },
        },

        {
            title = "Behavior",
            blocks = {
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Fade old messages", "Off keeps every message visible until new ones push it off the top." },
                    { "Visible for", "How long a message stays fully visible before it starts to fade, 10 to 600 seconds." },
                    { "Fade duration", "How long the fade itself takes, up to 5 seconds." },
                    { "Indent wrapped lines", "A wrapped line is indented under the start of the message. Only applies with timestamps off - with them on, the gutter already handles it." },
                    { "Line spacing", "Extra pixels between lines, 0 to 8. One to three is a gap; more is a list." },
                    { "History buffer", "How many past lines are kept, 100 to 2000. 500 is the game's own default and what this starts at." },
                } },
            },
        },

        {
            title = "History that survives",
            blocks = {
                { type = "paragraph", text = "Chat comes back after a reload and after a relog. What is kept is replayed into each tab, with a |cff8ce0ff--- end of history ---|r line marking where the past stops and the present starts." },
                { type = "paragraph", text = "How much is kept is the |cffffd700History buffer|r setting. More lines means more memory and a slightly slower reload while they replay." },
                { type = "h3", text = "What is stored" },
                { type = "list", items = {
                    "The message text itself, without a timestamp - the gutter draws that fresh.",
                    "Which chat type it was, so the gutter bar comes back the right color.",
                    "When it actually arrived, so the timestamp is honest.",
                } },
                { type = "h3", text = "Clearing it" },
                { type = "list", items = {
                    "|cffffd700/clearchat|r or |cffffd700/cc|r clears the tab you are on and its stored history with it.",
                    "|cffffd700/bc reset|r throws away every Chat setting in every profile and reloads. It is the big one.",
                } },
            },
        },

        {
            title = "Copying and retyping",
            blocks = {
                { type = "h3", text = "Copy chat" },
                { type = "paragraph", text = "The game gives you no way to select chat text. The small icon at the top right of the chat window opens a dialog holding the tab's lines; Select All and Ctrl+C gets them out. |cffffd700/bc copy|r opens the same dialog, which is worth a keybind if you do it often." },
                { type = "paragraph", text = "Color codes are stripped on the way out, so what you paste into a bug report or a forum post is plain readable text. Item, spell and quest links keep their names." },
                { type = "h3", text = "Up and Down" },
                { type = "paragraph", text = "Press |cffffd700Up|r in the chat box to bring back the last thing you typed, and again to go further back; |cffffd700Down|r walks forward again. It covers slash commands too, which is the usual reason to want it. The list lasts the session." },
            },
        },

        {
            title = "Profiles and turning it off",
            blocks = {
                { type = "paragraph", text = "|cffffd700One profile covers the whole addon.|r Chat's tabs, colors and fade settings travel with the rest of BazUI when you switch profiles - there is no separate chat profile to keep in step." },
                { type = "paragraph", text = "The Profiles page is under |cffffd700BazUI|r itself, not in this panel, and that is where profiles are created, copied, switched and deleted." },
                { type = "h3", text = "Turning it off" },
                { type = "paragraph", text = "|cffffd700Enable BazUI Chat|r at the top of the module's settings is the master switch, and |cffffd700/bc toggle|r is the same switch from the chat box. Off, the replica shuts down and the game's own chat comes back at the next reload." },
            },
        },

        {
            title = "Slash commands",
            blocks = {
                { type = "table", columns = { "Command", "What it does" }, rows = {
                    { "/bazchat", "Opens the Chat settings. /bc is the short one." },
                    { "/bc copy", "Opens the copy dialog for the tab you are on." },
                    { "/bc clear", "Clears the active tab and its stored history." },
                    { "/clearchat", "The same, as a top-level command. /cc is shorter still." },
                    { "/bc font", "Reports whether the chat font is loaded and in use - the first thing to try if the text looks wrong." },
                    { "/bc toggle", "Master on and off." },
                    { "/bc reset", "Wipes every Chat setting and reloads." },
                } },
                { type = "note", text = "A font the client cannot load needs the game restarted rather than reloaded - the client reads its fonts once, at startup. /bc font says so plainly when that is what has happened." },
            },
        },
    },
})
