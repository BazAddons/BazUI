-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Notifications User Guide
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Notifications", {
    title = "Notifications",
    intro = "A modern notification center that captures dozens of game events and presents them as polished toasts plus a persistent history.",
    pages = {
        {
            title = "Welcome",
            blocks = {
                { type = "lead", text = "BazUI Notifications (BNC) monitors game events and surfaces them in two ways: animated toasts that slide in from the screen edge, and a scrollable history panel that retains everything for review." },
                { type = "h2", text = "What gets captured?" },
                { type = "list", items = {
                    "Loot drops with rarity colors",
                    "Reputation gains and losses",
                    "XP",
                    "Currency changes",
                    "Achievement completions",
                    "Rare spawn vignettes (with atlas-based filtering)",
                    "Guild member activity",
                    "LFG queue events",
                    "Profession crafts",
                }},
                { type = "note", style = "tip", text = "Every toast carries a |cffffd700module label|r so you instantly know which system generated it." },
            },
        },
        {
            title = "Toast Notifications",
            blocks = {
                { type = "h3", text = "Animation" },
                { type = "paragraph", text = "Toasts slide in from the configured edge and fade out after their duration expires." },
                { type = "h3", text = "Stacking" },
                { type = "paragraph", text = "Multiple toasts queue up without overlapping. Newer ones push older ones along until they expire." },
                { type = "h3", text = "Per-module toggles" },
                { type = "paragraph", text = "Each notification source has its own toggle. Disable just the noisy ones - keep the rest." },
                { type = "h3", text = "Customization" },
                { type = "list", items = {
                    "|cffffd700Duration|r - how long each toast stays on screen",
                    "|cffffd700Position|r - which edge of the screen toasts appear from",
                    "|cffffd700Stack direction|r - newer on top or newer at bottom",
                    "|cffffd700Width|r - toast width in pixels",
                }},
            },
        },
        {
            title = "Notification Panel",
            blocks = {
                { type = "lead", text = "Click the bell in the addon compartment (or use the slash command) to open the persistent history panel." },
                { type = "h3", text = "Features" },
                { type = "list", items = {
                    "Scrollable timeline grouped by day",
                    "Filter by module to find a specific notification quickly",
                    "Search box for fuzzy text matching",
                    "Click any notification for full detail",
                }},
                { type = "h3", text = "Retention" },
                { type = "paragraph", text = "Configurable from 1 to 90 days. Older notifications are automatically pruned." },
                { type = "table",
                  columns = { "Setting", "Range", "Default" },
                  rows = {
                      { "Retention",    "1-90 days", "7 days" },
                      { "Max items",    "100-10000", "2000" },
                  },
                },
            },
        },
        {
            title = "Modules",
            blocks = {
                { type = "lead", text = "BNC ships with 15 modules covering most major game events. Each can be toggled independently in Options > AddOns > BazUI > Notifications > Modules." },
                { type = "collapsible", title = "Loot", style = "h4", blocks = {
                    { type = "paragraph", text = "Item drops with rarity colors and counts. Filter by minimum rarity (white, green, blue, ...)." },
                }},
                { type = "collapsible", title = "Reputation", style = "h4", blocks = {
                    { type = "paragraph", text = "Faction standing changes and standing milestones." },
                }},
                { type = "collapsible", title = "XP", style = "h4", blocks = {
                    { type = "paragraph", text = "Experience gains. Suppressed at max level automatically." },
                }},
                { type = "collapsible", title = "Achievements", style = "h4", blocks = {
                    { type = "paragraph", text = "Achievement completions for you and (optionally) party/raid members." },
                }},
                { type = "collapsible", title = "Quests", style = "h4", blocks = {
                    { type = "paragraph", text = "Quest accept, complete, and turn-in events with quest icon and rewards." },
                }},
                { type = "collapsible", title = "Professions", style = "h4", blocks = {
                    { type = "paragraph", text = "Crafting completions with item icon and rarity." },
                }},
                { type = "collapsible", title = "Group", style = "h4", blocks = {
                    { type = "paragraph", text = "LFG / LFR / Premade-group events - queue popped, role check, ready check, role assignment." },
                }},
                { type = "collapsible", title = "Instance", style = "h4", blocks = {
                    { type = "paragraph", text = "Dungeon and raid entries, exits, and saved-instance lockouts." },
                }},
                { type = "collapsible", title = "Zones", style = "h4", blocks = {
                    { type = "paragraph", text = "Zone and sub-zone enters, contested / sanctuary / friendly / hostile status changes." },
                }},
                { type = "collapsible", title = "Mail", style = "h4", blocks = {
                    { type = "paragraph", text = "Incoming mail, returned mail, and mail-attachment notifications." },
                }},
                { type = "collapsible", title = "Auction", style = "h4", blocks = {
                    { type = "paragraph", text = "Auction house events - successful sales, expirations, and outbids." },
                }},
                { type = "collapsible", title = "Inventory", style = "h4", blocks = {
                    { type = "paragraph", text = "Bag-space warnings, currency captures, and notable inventory transitions." },
                }},
                { type = "collapsible", title = "Calendar", style = "h4", blocks = {
                    { type = "paragraph", text = "Calendar invites and event reminders." },
                }},
                { type = "collapsible", title = "Social", style = "h4", blocks = {
                    { type = "paragraph", text = "Guildmates and friends - online/offline, level-ups, achievements, BNet status." },
                }},
                { type = "collapsible", title = "System", style = "h4", blocks = {
                    { type = "paragraph", text = "Important system messages - disconnects, reconnect attempts, and error notifications." },
                }},
            },
        },
        {
            title = "Smart Handoff",
            blocks = {
                { type = "lead", text = "Other BazUI modules and outside addons can feed the notification center." },
                { type = "h3", text = "Custom sources" },
                { type = "paragraph", text = "Any addon can call BNC's push API to surface its own events:" },
                { type = "code", text = "BazUI:PushNotification({\n    module  = \"MyAddon\",\n    title   = \"Something happened\",\n    body    = \"Detail text here\",\n    icon    = \"Interface\\\\Icons\\\\INV_Misc_Bell_01\",\n    rarity  = 4,\n})" },
            },
        },
        {
            title = "Slash Commands",
            blocks = {
                { type = "table",
                  columns = { "Command", "Effect" },
                  rows = {
                      { "/bnc",        "Open the BazUI Notifications settings page" },
                      { "/bnc panel",  "Open the notification history panel" },
                      { "/bnc clear",  "Clear all notification history (asks for confirmation)" },
                  },
                },
            },
        },
    },
})
