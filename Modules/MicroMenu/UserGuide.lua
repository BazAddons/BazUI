-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Micro Menu User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("MicroMenu", {
    title = "Micro Menu",
    intro = "Blizzard's micro buttons on a movable bar, drawn as round ring-framed icons that match the rest of BazUI.",
    pages = {
        {
            title = "Overview",
            blocks = {
                { type = "lead", text = "The Character, Spellbook, Talents, Quest Log, Social, Guild, World Map, Game Menu and Help buttons move onto a BazUI bar. They are still Blizzard's own buttons, so tooltips, keybinds, the talent reminder and the level gates all keep working." },
                { type = "h2", text = "Highlights" },
                { type = "list", items = {
                    "Round ring-framed icons; the Character button shows your portrait",
                    "Horizontal or vertical bar, any button size and spacing",
                    "Show or hide each button individually",
                    "Drag the bar anywhere in BazUI Edit Mode",
                    "Blizzard's stock micro menu is parked while the BazUI bar is shown",
                }},
                { type = "note", style = "tip", text = "Buttons Blizzard hides for your character, such as Talents before level 10 or Guild while unguilded, stay hidden here too and appear when they unlock." },
            },
        },
        {
            title = "Settings",
            blocks = {
                { type = "paragraph", text = "Everything lives in |cffffd700Options > AddOns > BazUI > Micro Menu|r, or type |cffffd700/bazmicro|r. Layout settings also appear in the bar's BazUI Edit Mode popup." },
                { type = "table",
                  columns = { "Setting", "What it does" },
                  rows = {
                      { "|cffffd700Show the BazUI micro menu|r", "Turn the module on or off. Off returns the buttons to Blizzard's menu." },
                      { "|cffffd700Hide Blizzard's micro menu|r", "Park the stock container in the bottom right." },
                      { "|cffffd700Orientation|r",              "Lay the buttons out in a row or a column." },
                      { "|cffffd700Button size|r / |cffffd700Spacing|r", "Size of each round button and the gap between them." },
                      { "|cffffd700Show only on mouseover|r", "Fade the bar out until the cursor is over it. Faded opacity sets how much of it stays visible; 0 hides it completely. The bar always shows while Edit Mode is open." },
                      { "|cffffd700Reset position|r",           "Move the bar back to the bottom right corner." },
                      { "|cffffd700Buttons|r",                  "One toggle per button." },
                  }},
            },
        },
    },
})
