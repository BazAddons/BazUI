-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat User Manual
--
-- Registered with BazUI so it appears as a "User Manual" sub-tab
-- under BazChat's bottom tab in the standalone Options window.
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Chat", {
    title = "Chat",
    intro = "BazUIChat is a full chat replacement for the Baz Suite. It owns its own chat windows but layers Blizzard's message formatter, hyperlinks, and combat log on top, so you keep every feature you'd expect while gaining tabs, channel filtering, copy-paste, persistent history, and timestamps.",
    pages = {
        ----------------------------------------------------------------
        -- Welcome
        ----------------------------------------------------------------
        {
            title = "Welcome",
            blocks = {
                { type = "lead",
                  text = "BazUIChat replaces the default Blizzard chat with its own windows. The look is the same — gold names, hyperlinks, system colours — but you get per-tab channel filtering, configurable timestamps, history that survives /reload, click-to-copy, and the combat log embedded as a real tab." },

                { type = "note", style = "info",
                  text = "Open settings via |cffffd700/bazchat|r or |cffffd700/bc|r, or find Chat under BazUI in Options > AddOns." },

                { type = "h2", text = "What you get" },
                { type = "list", items = {
                    "|cffffd700Tabs|r — create, rename, delete, and drag-to-reorder; right-click a tab for its menu (rename, channels, move, delete).",
                    "|cffffd700Combat Log|r as a real tab — Blizzard's filter buttons (My Actions, What Happened to Me, Additional Filters) live inside BazUI Chat instead of floating off-screen.",
                    "|cffffd700Channel filtering|r per-tab for Say, Guild, Whispers, Trade, custom channels, and so on.",
                    "|cffffd700Timestamps|r in a left-side gutter so wrapped lines stay aligned with the message body.",
                    "|cffffd700Persistent history|r — chat survives /reload and full relog. The last 500 lines per tab replay when you log back in.",
                    "|cffffd700Copy chat|r — small icon on every chat frame opens a copy dialog with the visible text pre-selected.",
                    "|cffffd700Auto-show tabs|r — hide tabs unless a context applies (in a city, in a raid, in combat, etc.).",
                    "|cffffd700Up/Down history|r in the chat box — scroll through your typed messages, not just the most recent one.",
                    "|cffffd700The BazUI chat face|r (DorisPP), with a text size slider. Both live under Appearance; turn the face off to go back to Blizzard's font.",
                }},

                { type = "h2", text = "Slash commands" },
                { type = "table",
                  columns = { "Command", "Effect" },
                  rows = {
                      { "/bazchat",      "Open the Chat settings" },
                      { "/bc",           "Same; short alias" },
                      { "/bc copy",      "Open the copy dialog for the active tab" },
                      { "/bc clear",     "Clear the active tab + its persisted history" },
                      { "/clearchat",    "Same as /bc clear (top-level alias)" },
                      { "/cc",           "Same as /clearchat (short)" },
                      { "/bc toggle",    "Master on/off for BazUI Chat" },
                      { "/bc reset",     "Wipe all BazUI Chat saved settings (reloads to confirm)" },
                  },
                },
            },
        },

        ----------------------------------------------------------------
        -- Tabs
        ----------------------------------------------------------------
        {
            title = "Tabs",
            blocks = {
                { type = "lead",
                  text = "BazUIChat starts with four tabs — General, Guild, Trade, Log — and you can add as many more as you want. Each tab subscribes to its own set of channels." },

                { type = "h2", text = "Creating + renaming" },
                { type = "list", items = {
                    "Click the |cffffd700+|r button at the right end of the tab strip to create a new tab.",
                    "Right-click any tab for its menu: |cffffd700Rename...|r, |cffffd700Channels...|r (a popup whose Name field also renames the tab), Clear, Lock, Move to and Delete.",
                    "|cffffd700BazUI > Chat > Tabs|r in Options > AddOns shows every tab as a list with the same name field plus an Edit Channels button.",
                }},

                { type = "h2", text = "Deleting + reordering" },
                { type = "list", items = {
                    "Right-click a tab → |cffffd700Delete tab|r removes it. No /reload needed.",
                    "The |cffffd700General|r tab can't be deleted — it owns the default chat target that drives Enter-to-chat and addon /print messages.",
                    "Click and HOLD a tab for ~2 seconds to start dragging. Drop it left or right of another tab to reorder.",
                }},

                { type = "h2", text = "Auto-show" },
                { type = "paragraph",
                  text = "Each tab has an Auto-show setting (BazUI Chat → Tabs page). The default is |cffffd700Always|r. The other modes hide the tab unless a condition holds:" },
                { type = "table",
                  columns = { "Mode", "Tab visible when..." },
                  rows = {
                      { "Always",                  "(default) at all times" },
                      { "In a city",               "you're in a sanctuary zone — the default for the Trade tab" },
                      { "In a party",              "you're in a party (but not a raid)" },
                      { "In a raid",               "you're in a raid" },
                      { "In combat",               "combat lockdown is active" },
                      { "In a battleground/arena", "instance type is PvP or arena" },
                      { "In a dungeon/raid",       "any instance condition is true" },
                  },
                },
                { type = "note", style = "tip",
                  text = "If the active tab gets hidden (e.g. you leave a raid with the Raid tab focused), BazUI Chat falls back to General automatically." },

                { type = "h2", text = "Reset" },
                { type = "paragraph",
                  text = "BazUIChat → Tabs has a |cffffd700Reset Tabs to Defaults|r button that wipes user-created tabs and restores the canonical four (General/Guild/Trade/Log) with their preset channels. Your chrome settings (alpha, scale, fade modes) are preserved — only tab structure resets." },
            },
        },

        ----------------------------------------------------------------
        -- Channels
        ----------------------------------------------------------------
        {
            title = "Channels",
            blocks = {
                { type = "lead",
                  text = "Every tab has its own channel subscription. Right-click any tab and pick |cffffd700Channels...|r for a 2-column popup that controls exactly what flows in." },

                { type = "h2", text = "Categories vs. named channels" },
                { type = "paragraph",
                  text = "The popup splits into two halves:" },
                { type = "list", items = {
                    "|cffffd700Categories|r — the Blizzard-grouped chat types (Say, Emote, Guild, Whispers, Party, Raid, Battleground, System, Errors, Loot, Skill, Pet Battle, etc.). One toggle each.",
                    "|cffffd700Named channels|r — one row per joined channel (General, Trade, LocalDefense, custom channels). Toggle individually so you can have a Trade-only tab or mute LocalDefense globally.",
                }},

                { type = "h2", text = "Channel-coloured gutter bar" },
                { type = "paragraph",
                  text = "When timestamps are on, every chat line gets a thin vertical bar in the left gutter coloured to match the message's chat-type colour (green for guild, pink for whispers, yellow for system, the channel's custom colour for numbered channels). The bar spans the full height of the message including wrapped lines, so multi-line entries stay anchored to their timestamp." },
                { type = "note", style = "info",
                  text = "Bar colours come from Blizzard's chat-type table and update live when you change a channel's colour via the |cffffd700/chat|r config — no /reload needed." },

                { type = "h2", text = "Guild MOTD" },
                { type = "paragraph",
                  text = "BazUIChat surfaces the Guild Message of the Day on cold login and on /reload, exactly once per session. Live MOTD changes from /gmotd come through normally as guild chat." },
            },
        },

        ----------------------------------------------------------------
        -- Combat Log tab
        ----------------------------------------------------------------
        {
            title = "Combat Log Tab",
            blocks = {
                { type = "lead",
                  text = "BazUIChat hijacks Blizzard's combat log into its own |cffffd700Log|r tab. The formatted output, filter presets (My Actions, What Happened to Me), and the Additional Filters dropdown all surface inside BazUI Chat instead of being stuck on Blizzard's hidden default chat frame." },

                { type = "h2", text = "Filter buttons" },
                { type = "paragraph",
                  text = "Blizzard's QuickButton bar — the little row of preset filters above the log — is reparented onto the Log tab. The bar tracks the tab when you resize the chat window, so the filter buttons always sit just above the log's text area." },
                { type = "note", style = "info",
                  text = "Blizzard's combat-log driver does the actual parsing and filtering. BazUI Chat just redirects the output to the Log tab — you still get every existing combat-log feature (custom filters, fight summaries, etc.)." },

                { type = "h2", text = "Removing the Log tab" },
                { type = "paragraph",
                  text = "Right-click → Delete tab works on the Log tab too. Deleted canonical tabs stay deleted across /reload. Add a new tab and it'll show up as a blank tab; you can re-create the Log tab via |cffffd700BazUI Chat → Tabs → Reset Tabs to Defaults|r." },
            },
        },

        ----------------------------------------------------------------
        -- Timestamps
        ----------------------------------------------------------------
        {
            title = "Timestamps",
            blocks = {
                { type = "lead",
                  text = "BazUIChat puts timestamps in a left-side gutter rather than as an inline prefix. Wrapped lines stay flush with the message body, with the channel-coloured bar tying them visually to the timestamp." },

                { type = "h2", text = "Format" },
                { type = "paragraph",
                  text = "The Format dropdown in BazUI Chat → Settings → Timestamps offers four presets:" },
                { type = "table",
                  columns = { "Preset", "Example" },
                  rows = {
                      { "24-hour",                "14:32" },
                      { "24-hour with seconds",   "14:32:09" },
                      { "12-hour",                "2:32 PM" },
                      { "12-hour with seconds",   "2:32:09 PM" },
                  },
                },

                { type = "h2", text = "Historic timestamps" },
                { type = "paragraph",
                  text = "Replayed history (after /reload) re-renders each line with its ORIGINAL capture time, not \"now.\" A message logged at 9 AM still reads |cffffd70009:00:00|r when you log back in at noon — persistence stores the unix time alongside the text." },
            },
        },

        ----------------------------------------------------------------
        -- Persistent history
        ----------------------------------------------------------------
        {
            title = "Persistent History",
            blocks = {
                { type = "lead",
                  text = "Chat survives /reload and full relog. When you come back, BazUI Chat replays the last 500 lines per tab into the chat with a clear |cff8ce0ff--- end of history ---|r separator before live messages start." },

                { type = "h2", text = "Capacity" },
                { type = "paragraph",
                  text = "Persistence is capped by the |cffffd700History buffer|r slider in BazUI Chat → Settings → Behavior. Default is 500 lines per tab; the slider goes 100–2000. Higher numbers use more memory and slow /reload slightly while history replays." },

                { type = "h2", text = "What's saved" },
                { type = "list", items = {
                    "Message text (raw, without timestamp prefix — the gutter renders fresh)",
                    "Chat-type colour (so the gutter bar reproduces correctly)",
                    "Original unix capture time (used to re-render historic timestamps)",
                }},

                { type = "h2", text = "Wiping history" },
                { type = "list", items = {
                    "|cffffd700/clearchat|r or |cffffd700/cc|r clears the active tab's screen AND its persisted history.",
                    "|cffffd700/bc reset|r wipes ALL BazUI Chat saved settings (full nuke; reloads).",
                }},
            },
        },

        ----------------------------------------------------------------
        -- Chat input history
        ----------------------------------------------------------------
        {
            title = "Chat Input History",
            blocks = {
                { type = "lead",
                  text = "Press Up in the chat input box to scroll back through messages you've typed. Press Down to scroll forward toward your most recent." },

                { type = "h2", text = "How it works" },
                { type = "list", items = {
                    "|cffffd700Up|r — pulls in your most recent message first; press again to step further back.",
                    "|cffffd700Down|r — steps forward toward the line you started typing.",
                    "Persists per session — history clears on /reload.",
                }},
                { type = "note", style = "tip",
                  text = "Useful for re-issuing a command, or for editing a message you sent then immediately wanted to fix." },
            },
        },

        ----------------------------------------------------------------
        -- Copy chat
        ----------------------------------------------------------------
        {
            title = "Copy Chat",
            blocks = {
                { type = "lead",
                  text = "WoW's chat doesn't let you select text natively — this fixes it." },

                { type = "paragraph",
                  text = "BazUIChat puts a small icon at the top-right corner of every chat frame. Click it to open a popup with the last 500 lines from that tab. Inside the popup, click |cffffd700Select All|r and press |cffffd700Ctrl+C|r to copy out." },

                { type = "note", style = "tip",
                  text = "The same dialog is reachable via |cffffd700/bc copy|r — bind it to a key if you copy chat often." },

                { type = "h2", text = "What's stripped" },
                { type = "paragraph",
                  text = "Copies always strip Blizzard's colour escapes so the result pastes cleanly into Discord, a bug report, or a forum post. Hyperlinks (item / spell / quest) keep their human-readable text." },
            },
        },

        ----------------------------------------------------------------
        -- Auto-hide / fade
        ----------------------------------------------------------------
        {
            title = "Auto-Hide & Fade",
            blocks = {
                { type = "lead",
                  text = "Background panel, tab strip, and scrollbar each have their own visibility mode. Mix and match for the chrome look you want." },

                { type = "table",
                  columns = { "Mode", "Behaviour" },
                  rows = {
                      { "Always",    "Visible at all times. (Default for everything.)" },
                      { "On hover",  "Faded in when the cursor is over the chat or tab strip; held for 2 seconds after the last hover; then faded out." },
                      { "On scroll", "Scrollbar-only. Faded in when you scroll or hover the chat, faded out a couple seconds later." },
                      { "Never",     "Element never renders. (Mouse wheel still scrolls.)" },
                  },
                },

                { type = "h2", text = "Unified background + tabs" },
                { type = "paragraph",
                  text = "The |cffffd700Unified|r dropdown overrides Background and Tabs visibility together. Set it to |cffffd700On hover|r and both elements fade in lockstep — a common preference for a minimal look. The individual dropdowns grey out while Unified is active." },

                { type = "note", style = "info",
                  text = "Edit Mode forces all elements visible while you're laying out the dock — so you don't lose the chat in the fog while positioning it." },
            },
        },

        ----------------------------------------------------------------
        -- Profiles
        ----------------------------------------------------------------
        {
            title = "Profiles",
            blocks = {
                { type = "paragraph",
                  text = "BazUIChat uses BazUI's profile system. Create per-character or per-spec profiles to keep different tab setups, colour schemes, fade behaviours, and more." },
                { type = "paragraph",
                  text = "Open |cffffd700Settings → BazUI Chat → Profiles|r to create, switch, copy, reset, or delete profiles. Profiles are per-addon — switching your BazUI Chat profile doesn't affect any other Baz addon." },
            },
        },
    },
})
