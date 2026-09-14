-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Codex", {
    title = "Codex",
    intro = "One window that answers two questions: what can I do today, and what have I already done.",
    pages = {
        {
            title = "Overview",
            blocks = {
                { type = "lead", text = "The codex gathers the answers scattered across the game's own windows into one page. Today holds what is still open to you this week; Achieved holds what you have collected. Items looks anything up, and the Wishlist keeps the things you are playing towards." },
                { type = "h2", text = "Opening it" },
                { type = "list", items = {
                    "Type |cffffd700/codex|r or |cffffd700/bazcodex|r",
                    "Click the Codex button on the minimap",
                    "Drag the window anywhere; it remembers where you left it",
                    "Escape closes it",
                }},
                { type = "note", style = "tip", text = "Section headings collapse. Click one to fold a block away and the codex remembers that too, so you can keep it down to the handful of lines you actually check." },
            },
        },
        {
            title = "Today",
            blocks = {
                { type = "paragraph", text = "What is still open to you." },
                { type = "table",
                  columns = { "Block", "What it shows" },
                  rows = {
                      { "|cffffd700Saved instances|r", "Every raid and dungeon you are locked to, how far through it you got, and when the lock lifts. Only live lockouts appear; an expired one is gone." },
                      { "|cffffd700Resets|r", "How long until the daily and weekly rollovers." },
                  }},
                { type = "note", style = "tip", text = "The server only sends lockout data when it is asked. The codex asks on login, so the list can take a moment to fill in the first time." },
            },
        },
        {
            title = "Achieved",
            blocks = {
                { type = "paragraph", text = "What you have already put your name to." },
                { type = "table",
                  columns = { "Block", "What it shows" },
                  rows = {
                      { "|cffffd700Titles|r",     "Every title you have earned, and how many exist." },
                      { "|cffffd700Mounts|r",     "Your mounts." },
                      { "|cffffd700Pets|r",       "Your companions." },
                      { "|cffffd700Reputation|r", "Anything standing at revered or better; exalted reads in green." },
                  }},
                { type = "note", text = "A block only shows what this client knows about. As Forever adds collections the codex gains blocks for them without needing anything relearned." },
            },
        },
        {
            title = "Items and Wishlist",
            blocks = {
                { type = "h2", text = "Looking something up" },
                { type = "paragraph", text = "Paste an item link or type an item number and you get that exact item, with its tooltip and how many you are carrying. That works for anything in the game, because the server answers the question." },
                { type = "paragraph", text = "Typing a |cffffd700name|r is different. No addon can search every item in the game without shipping and maintaining its own copy of the item table, so BazUI does not pretend to. Instead it quietly remembers the items this character has actually met: what you carry, wear, bank, loot, or look at on a vendor, and anything anyone links in chat. Name search looks through that. It starts empty and fills in as you play, and the search box always tells you how many items it is searching." },
                { type = "note", style = "tip", text = "Shift-click any row to drop the item's link into whatever you are typing. Ctrl-click to try it on." },
                { type = "h2", text = "The wishlist" },
                { type = "paragraph", text = "Shift-click an item into the box at the top of the Wishlist tab, or paste its link, and it joins the list with the date you wanted it. When one turns up in your bags the row says so. Click the |cffffd700x|r on a row to take it off." },
                { type = "note", text = "The codex does not know where anything drops and will not guess. The wishlist is your list; the only thing it works out for itself is whether you have the item yet." },
            },
        },
    },
})
