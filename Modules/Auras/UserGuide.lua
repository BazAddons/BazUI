-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Auras User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Auras", {
    title = "Auras",
    intro = "Buffs and debuffs drawn as rounded icons in rows you place yourself, instead of in the corner by the minimap.",
    pages = {
        {
            title = "Overview",
            blocks = {
                { type = "lead", text = "You make rows, the way you make bars: a row shows buffs or debuffs, of the player, your target or your pet, and there can be as many as you like. Each floats where you put it or docks to a bar or an action bar, above or below it. Eight icons per row by default, and as many rows as there are auras." },
                { type = "h2", text = "Highlights" },
                { type = "list", items = {
                    "Right-click an icon to cancel that buff or remove a weapon enchant, in or out of combat",
                    "Time remaining and stack counts on the icons",
                    "Debuff rims coloured by type: blue Magic, purple Curse, brown Disease, green Poison",
                    "Weapon enchants such as poisons and sharpening stones shown with your buffs",
                    "The target's auras appear and vanish with the BazUI target frame, and can be limited to the debuffs you applied",
                    "A docked row takes its host's alignment and hides when its host hides",
                    "Blizzard's own buff and debuff frames are parked while BazUI auras are shown",
                }},
                { type = "note", style = "tip", text = "Drag a row in Edit Mode and drop it near the edge of a bar to dock it there. A centred row stays centred as icons come and go, including in combat, because what moves is the row's frame rather than anything the game protects." },
            },
        },
        {
            title = "Settings",
            blocks = {
                { type = "paragraph", text = "Everything lives in |cffffd700Options > AddOns > BazUI > Auras|r, or type |cffffd700/bazauras|r. How the icons look is on |cffffd700General|r and applies to all four rows; where each row sits is on |cffffd700Rows|r, one form per row." },
                { type = "table",
                  columns = { "Setting", "What it does" },
                  rows = {
                      { "|cffffd700Show BazUI auras|r",       "Turn the whole module on or off." },
                      { "|cffffd700Hide Blizzard's frames|r", "Park the stock buff and debuff frames while ours are shown. Turn off to keep both." },
                      { "|cffffd700Icons per row|r",          "What a new row starts with; each row can be set on its own from the Rows page." },
                      { "|cffffd700Icon size|r / |cffffd700Spacing|r", "Size of each icon and the gap between icons and rows." },
                                                                                        { "|cffffd700Preview a full spread of auras|r", "Three rows of made-up icons on every side of both frames, so you can judge size and spacing. Also |cffffd700/bazauras preview|r. Ends when combat starts." },
                      { "|cffffd700Time remaining|r / |cffffd700Stack counts|r", "Text on the icons." },
                      { "|cffffd700Colour debuff rims by type|r", "Off keeps every debuff rim red." },
                      { "|cffffd700Weapon enchants|r",        "Show temporary weapon enchants among the buffs." },
                      { "|cffffd700Sort by|r",                "Order applied, time remaining or name, ascending or descending." },
                      { "|cffffd700Shows|r / |cffffd700Of|r",         "On the Rows page: buffs or debuffs, and whose. Any number of rows, in any combination." },
                      { "|cffffd700Dock to|r / |cffffd700On the|r",   "What this row attaches to, and which edge of it. Floating leaves it where you dropped it." },
                      { "|cffffd700Only mine|r",               "On a row for someone else: hide auras other players applied." },
                      { "|cffffd700Aligned|r",                "Which end of its host a docked row starts from: left, centre or right." },
                      { "|cffffd700Gap|r",                    "Pixels between a docked row and what it is docked to." },
                  }},
                { type = "note", style = "info", text = "Layout changes made during combat apply as soon as combat ends. Icons, counts and timers always update live." },
            },
        },
    },
})
