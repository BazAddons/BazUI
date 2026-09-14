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
                      { "|cffffd700Quests|r",          "The ones ready to hand in, and the ones you are furthest through. The rest stay in the quest log, where twenty titles belong." },
                      { "|cffffd700Open to you|r",     "Instances you are attuned or keyed for, at level, and not already saved. A row says go, or says why not." },
                      { "|cffffd700Saved instances|r", "Every raid and dungeon you are locked to, how far through it you got, and when the lock lifts. Only live lockouts appear; an expired one is gone." },
                      { "|cffffd700Goals|r",           "The long projects: the mount you are saving for, the weapon at the end of your class chain. Only the ones that belong to your class and matter at your level." },
                      { "|cffffd700Working towards|r", "Attunements and keys you have started and not finished. Hover a row for what is left." },
                      { "|cffffd700Resets|r",          "How much of the day and the week have run, and how long is left of each." },
                  }},
                { type = "note", style = "tip", text = "The server only sends lockout data when it is asked. The codex asks on login, so the list can take a moment to fill in the first time." },
                { type = "h2", text = "Where goals and attunements come from" },
                { type = "paragraph", text = "Some goals need nothing written down at all, because the client already answers them: a savings target is your purse against a number, and the row tells you how much gold is still to go. The famous ones need a number written down, and those work the same way attunements do." },
                { type = "paragraph", text = "Classic has no attunement API. Retail hands an addon a list of what you are eligible for; this client hands over nothing, because in 2004 the answer lived in the player's head. So the codex works it out from the questions the client will answer: a quest you completed, a key in your bags, a reputation standing, your level. Which of those guard which door is the one piece of knowledge in the module that did not come from the game." },
                { type = "note", text = "Written-down knowledge can be wrong, so every entry checks itself: it carries the name it believes its quest or item number has, and an entry the client disagrees with is hidden rather than shown. A mistake in that list can only ever cost you a missing door, never a false one. Type |cffffd700/codex verify|r to see whether anything is being hidden and why." },
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
                      { "|cffffd700Goals|r",      "The long projects you have finished." },
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
                { type = "paragraph", text = "Typing a |cffffd700name|r is different. No addon can search every item in the game without shipping and maintaining its own copy of the item table, so BazUI does not pretend to. Instead it quietly remembers the items this character has actually met: what you carry, wear, bank, loot, or look at on a vendor, and anything anyone links in chat. That list is what the tab shows when you open it, and typing filters it rather than searching from nothing. It starts empty and fills in as you play." },
                { type = "note", style = "tip", text = "Shift-click any row to drop the item's link into whatever you are typing. Ctrl-click to try it on." },
                { type = "h2", text = "The wishlist" },
                { type = "paragraph", text = "Shift-click an item into the box at the top of the Wishlist tab, or paste its link, and it joins the list with the date you wanted it. When one turns up in your bags the row says so. Click the |cffffd700x|r on a row to take it off." },
                { type = "note", text = "The codex does not know where anything drops and will not guess. The wishlist is your list; the only thing it works out for itself is whether you have the item yet." },
            },
        },
    },
})
