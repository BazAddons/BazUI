-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Auras User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Auras", {
    title = "Auras",
    intro = "Your buffs and debuffs, drawn as rounded icons on the BazUI player frame instead of in the corner by the minimap.",
    pages = {
        {
            title = "Overview",
            blocks = {
                { type = "lead", text = "Buffs sit above the health bar on the left of the player frame and debuffs above the power bar on the right. Each side holds eight icons per row, and rows keep stacking upward for as long as you have auras to show." },
                { type = "h2", text = "Highlights" },
                { type = "list", items = {
                    "Right-click an icon to cancel that buff or remove a weapon enchant, in or out of combat",
                    "Time remaining and stack counts on the icons",
                    "Debuff rims coloured by type: blue Magic, purple Curse, brown Disease, green Poison",
                    "Weapon enchants such as poisons and sharpening stones shown with your buffs",
                    "The icons follow the player frame wherever you move or scale it",
                    "Blizzard's own buff and debuff frames are parked while BazUI auras are shown",
                }},
                { type = "note", style = "tip", text = "If the BazUI player frame is turned off, the auras move above Blizzard's player frame instead, buffs on the bottom row and debuffs above them." },
            },
        },
        {
            title = "Settings",
            blocks = {
                { type = "paragraph", text = "Everything lives in |cffffd700Options > AddOns > BazUI > Auras|r, or type |cffffd700/bazauras|r." },
                { type = "table",
                  columns = { "Setting", "What it does" },
                  rows = {
                      { "|cffffd700Show BazUI auras|r",       "Turn the whole module on or off." },
                      { "|cffffd700Hide Blizzard's frames|r", "Park the stock buff and debuff frames while ours are shown. Turn off to keep both." },
                      { "|cffffd700Icons per row|r",          "How many icons fill a row before the next row starts above it. Default 8." },
                      { "|cffffd700Icon size|r / |cffffd700Spacing|r", "Size of each icon and the gap between icons and rows." },
                      { "|cffffd700Distance above the bars|r", "Space between the top of the health and power bars and the first row." },
                      { "|cffffd700Fill direction|r",         "From the portrait outward puts the first icon next to the portrait. From the outer end inward starts at the far end of each bar." },
                      { "|cffffd700Time remaining|r / |cffffd700Stack counts|r", "Text on the icons." },
                      { "|cffffd700Colour debuff rims by type|r", "Off keeps every debuff rim red." },
                      { "|cffffd700Weapon enchants|r",        "Show temporary weapon enchants among the buffs." },
                      { "|cffffd700Sort by|r",                "Order applied, time remaining or name, ascending or descending." },
                  }},
                { type = "note", style = "info", text = "Layout changes made during combat apply as soon as combat ends. Icons, counts and timers always update live." },
            },
        },
    },
})
