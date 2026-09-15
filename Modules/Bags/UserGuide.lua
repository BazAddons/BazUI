-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Bags User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Bags", {
    title = "Bags",
    intro = "A unified bag panel that merges all your bags and your keyring into one window, with two display modes, seven auto-classified categories, custom categories, and three ways to pin items.",
    pages = {

        ---------------------------------------------------------------
        -- 1. Welcome
        ---------------------------------------------------------------
        {
            title = "Welcome",
            blocks = {
                { type = "lead", text = "BazUI Bags replaces Blizzard's combined bag with a single panel that's friendlier to read and a lot more flexible. The B key, the minimap bag icon, and any addon that calls the standard bag-toggle hooks all open BazUI Bags now." },
                { type = "h2", text = "Highlights" },
                { type = "list", items = {
                    "All bags plus the keyring in one panel",
                    "Two display modes: per-bag sections (Blizzard-style) or grouped by category",
                    "Six default categories that auto-classify your items by type and quality",
                    "Pin individual items to specific categories - three different ways to do it",
                    "Hide categories you don't want to see (Junk, Quest Items, anything)",
                    "Custom categories for any organisation scheme you want",
                    "Inline gold display",
                    "Search box that filters every bag at once",
                    "Configurable columns, max rows, background opacity, frame strata",
                    "Per-character profiles - settings travel with each toon",
                }},
                { type = "h2", text = "Where to start" },
                { type = "paragraph", text = "Pick a topic on the left - the manual is ordered roughly from \"how do I open the bag?\" through \"how do I deeply customize it?\" Display Modes and Categories are the two big-picture concepts; the rest is tuning." },
                { type = "note", style = "tip", text = "If you've used Bagnon, Baganator, or ArkInventory before, BazUI Bags will feel familiar. BazUI Bags opens in Categories mode; switch to Bags mode in the settings for a per-bag layout closer to Blizzard's. Pinning is opt-in either way." },
            },
        },

        ---------------------------------------------------------------
        -- 2. Opening the Bag
        ---------------------------------------------------------------
        {
            title = "Opening the Bag",
            blocks = {
                { type = "lead", text = "BazUI Bags intercepts every standard bag-open path, so any way you've ever opened your bags still works - it just opens BazUI Bags instead of Blizzard's combined bag." },
                { type = "h2", text = "Quick toggles" },
                { type = "table",
                  columns = { "Action", "What it does" },
                  rows = {
                      { "|cffffd700B|r key",            "Toggle the panel (Blizzard's default keybind)" },
                      { "Minimap bag icon",             "Same as B" },
                      { "|cff00ff00/bbg|r",             "Toggle the panel" },
                      { "|cff00ff00/bazbags|r",         "Alias for /bbg" },
                      { "BazUI minimap button",          "Right-click menu lists every module; Bags toggles the panel" },
                      { "|cffffd700Esc|r",              "Close the panel (registered with UISpecialFrames)" },
                  }},
                { type = "h2", text = "Portrait icon (top-left)" },
                { type = "paragraph", text = "The bag's portrait icon is a three-action shortcut. Each mouse button does something different so you don't have to leave the panel to perform common tasks." },
                { type = "table",
                  columns = { "Click", "Action" },
                  rows = {
                      { "|cffffd700Left-click|r",   "|cffffd700Sort|r - runs Blizzard's Clean Up Bags" },
                      { "|cffffd700Middle-click|r", "Toggle |cffffd700Categorize mode|r (drop slots + every category visible)" },
                      { "|cffffd700Right-click|r",  "Open the |cffffd700Bag-change popup|r (equip/unequip bags)" },
                  }},
                { type = "note", style = "tip", text = "If your mouse doesn't have a middle button, |cff00ff00/bbg categorize|r is the slash equivalent." },
                { type = "h2", text = "Other title-bar actions" },
                { type = "list", items = {
                    "|cffffd700Drag|r the title bar (anywhere except the portrait icon) to move the panel - position is saved when you release",
                    "|cffffd700Click|r the X in the top-right corner to close",
                }},
                { type = "h2", text = "Bag-change popup" },
                { type = "paragraph", text = "Right-clicking the portrait opens a small floating panel with one button per equipped bag slot. Drag any bag from your inventory onto a slot to equip it, or drag the slot's icon off to unequip. Mirrors Blizzard's character-pane Bags tab, just one click closer." },
                { type = "note", style = "info", text = "The popup positions itself above the panel when there's screen room, below it when the panel is near the top of the screen. It hides when you click the portrait again or click anywhere else." },
            },
        },

        ---------------------------------------------------------------
        -- 3. Display Modes (parent)
        ---------------------------------------------------------------
        {
            title = "Display Modes",
            blocks = {
                { type = "lead", text = "BazUI Bags has two ways of arranging your items: per-bag sections (Blizzard-style) or grouped by category (item-type-style). Switch any time in |cffffd700Options > AddOns > BazUI > Bags > General Settings > Grouping > Mode|r." },
                { type = "h2", text = "Picking a mode" },
                { type = "paragraph", text = "|cffffd700Categories mode|r is the default - items regroup by what they are (Equipment, Consumables, etc.) regardless of which bag holds them. |cffffd700Bags mode|r is the conservative alternative - one collapsible section per bag type, with item slots arranged in their actual bag order." },
                { type = "paragraph", text = "Pick whichever fits your inventory style. Switching modes is non-destructive - the underlying bag data is unchanged, only the rendering differs. You can switch back any time." },
                { type = "note", style = "tip", text = "Drag-and-drop, click-to-use, shift-click to link in chat, and every other standard item interaction works identically in both modes. The slot button is the same Blizzard ContainerFrameItemButton template." },
            },
            children = {
                {
                    title = "Bags Mode",
                    blocks = {
                        { type = "lead", text = "Items render in the order of their bag positions, grouped under collapsible section headers per bag type." },
                        { type = "h2", text = "What you see" },
                        { type = "list", items = {
                            "|cffffd700Bags|r - your backpack and the four equippable bag containers, all merged into one grid",
                            "|cffffd700Keyring|r - your keys, once you own any",
                        }},
                        { type = "paragraph", text = "Each section has a header showing its name and a slot count (used / total). Click the header - anywhere on it - to fold or expand the section's grid. The collapse state is saved per profile, so your preference sticks across reloads." },
                        { type = "h2", text = "When to use Bags mode" },
                        { type = "list", items = {
                            "You're used to the default Blizzard combined-bag look",
                            "You want to keep the keyring folded away",
                            "Your physical bag positions matter (e.g., a specific bag is your \"loot bag\" or \"crafting bag\")",
                            "You don't care about item-type grouping",
                        }},
                        { type = "h2", text = "Hide Empty Slots" },
                        { type = "paragraph", text = "In |cffffd700Options > AddOns > BazUI > Bags > General > Grouping|r, the Hide empty slots toggle compacts the grid to show only slots that currently hold items. Handy if your bags are mostly empty and you'd rather the panel shrink to fit." },
                        { type = "note", style = "info", text = "Hide Empty Slots only applies in Bags mode. Categories mode never renders empty slots - the grid is built from the items themselves, so empty slots are never visible regardless of this setting." },
                        { type = "h2", text = "Separate Each Bag" },
                        { type = "paragraph", text = "By default, Bags mode renders one thin-divider section per equipped bag. Each divider shows the bag's slot label plus the equipped bag's actual item name, like:" },
                        { type = "list", items = {
                            "|cffffd700Backpack|r",
                            "|cffffd700Bag 1|r |cff888888(Traveler's Backpack)|r",
                            "|cffffd700Bag 2|r |cff888888(Mooncloth Bag)|r",
                            "|cffffd700Keyring|r",
                        }},
                        { type = "paragraph", text = "Same divider style Categories mode uses, with click-to-collapse on each per-bag header. Useful when bag positions matter (a specific bag is your loot bag, another is your crafting bag, etc.) - separating them visually keeps each bag's contents distinct." },
                        { type = "paragraph", text = "Toggle |cffffd700Separate Each Bag|r off in |cffffd700Layout|r to fall back to the chunky two-section layout (Bags plus Keyring)." },
                        { type = "note", style = "tip", text = "Hide Empty Slots and Separate Each Bag combine cleanly. Leave both on for the most compact, fully-separated bags-mode view." },
                    },
                },
                {
                    title = "Categories Mode",
                    blocks = {
                        { type = "lead", text = "Items regroup by what they are - Equipment, Consumables, Trade Goods, Quest Items, Keys, Junk, Other - regardless of which bag holds them. Each category gets a thin divider row separating its grid block." },
                        { type = "h2", text = "What you see" },
                        { type = "paragraph", text = "Seven default category dividers, each followed by the items belonging to that category in a wrap-friendly grid. Categories appear in display order; the divider rule on the right of each title fades into the category's content." },
                        { type = "paragraph", text = "Empty categories are hidden - only categories with at least one item show their dividers. Toggle Categorize mode (left-click the portrait) to surface every category, including hidden ones, for management." },
                        { type = "h2", text = "How items are grouped" },
                        { type = "paragraph", text = "An auto-classifier inspects each item's class and quality to route it to a category. You can override the classifier on a per-item basis by pinning items - see the |cffffd700Categories > Pinning Items|r page." },
                        { type = "h2", text = "When to use Categories mode" },
                        { type = "list", items = {
                            "You want to find a specific item type quickly without scanning bag by bag",
                            "You like \"by type\" mental grouping - all your consumables together, all your trade goods together",
                            "You want to surface, hide, or rename certain item types (e.g., hide Junk so it doesn't clutter your view)",
                        }},
                    },
                },
            },
        },

        ---------------------------------------------------------------
        -- 4. The Categories System (parent)
        ---------------------------------------------------------------
        {
            title = "The Categories System",
            blocks = {
                { type = "lead", text = "Categories are the organising units for the bag panel's Categories mode. Each category has a name, an order, a hidden flag, and a list of pinned items. Default categories auto-classify items by type; custom categories collect whatever you pin to them." },
                { type = "h2", text = "What categories give you" },
                { type = "list", items = {
                    "A clean, top-down view of your inventory grouped by item type",
                    "Per-category control over rendering - rename, reorder, hide, delete",
                    "Custom categories for any organisation scheme",
                    "Item pins that override the auto-classifier (e.g., \"this Iron Bar always goes in my Crafting category\")",
                    "Hidden categories that visually hide entire item types from the bag panel",
                }},
                { type = "h2", text = "Where to manage them" },
                { type = "paragraph", text = "All category management lives in |cffffd700Options > AddOns > BazUI > Bags > Categories|r. Pick a category from the list on the left to edit its display name, order, hide state, or pinned items. The buttons at the top of the list create new categories or restore the defaults." },
                { type = "note", style = "tip", text = "You don't have to be in Categories mode to manage categories. Categories live in saved data regardless of the active display mode - they only render in the bag panel when Categories mode is active." },
            },
            children = {
                {
                    title = "Auto-Classifier & Defaults",
                    blocks = {
                        { type = "lead", text = "Seven default categories ship with BazUI Bags. Each one auto-claims a slice of your inventory based on item class and quality." },
                        { type = "h2", text = "The defaults" },
                        { type = "table",
                          columns = { "Category", "What it auto-claims" },
                          rows = {
                              { "|cffffd700Equipment|r",   "Items in the Weapons or Armor item classes" },
                              { "|cffffd700Consumables|r", "Consumables (potions, food, scrolls) and ammunition" },
                              { "|cffffd700Trade Goods|r", "Trade Goods, Reagents, Recipes, Gems, and Item Enhancements" },
                              { "|cffffd700Quest Items|r", "Items in the Quest Items class" },
                              { "|cffffd700Keys|r",        "Items in the Key class (your keyring)" },
                              { "|cffffd700Junk|r",        "Anything with quality |cff9d9d9dPoor|r (gray)" },
                              { "|cffffd700Other|r",       "Catch-all — anything no other default category claimed" },
                          }},
                        { type = "h2", text = "Custom rule types" },
                        { type = "paragraph", text = "Custom categories support several rule types so you can build sub-buckets that the defaults don't cover. Edit a custom category from the Categories settings page → Rules:" },
                        { type = "list", items = {
                            "|cffffd700Item Class|r — match the same Blizzard item-class buckets the defaults use",
                            "|cffffd700Quality|r — match by item quality (Poor, Common, Uncommon, Rare, Epic, Legendary, Artifact)",
                            "|cffffd700Equip Slot|r — match by inventory slot (Head, Cloak, Trinket, etc.) — useful for separating cosmetic gear or trinket sets",
                            "|cffffd700Trade Skill / Reagent|r — match crafting reagent classes",
                        }},
                        { type = "h2", text = "How the classifier picks" },
                        { type = "paragraph", text = "For each item the classifier walks a fixed lookup chain:" },
                        { type = "list", ordered = true, items = {
                            "If you've pinned this item to a category, that pin wins. (See Pinning Items.)",
                            "If the item's quality is Poor (gray), it lands in Junk.",
                            "If the item's class is Weapon or Armor, it lands in Equipment.",
                            "If the item's class is Consumable, it lands in Consumables.",
                            "If the class is Trade Goods, Recipes, Gems, or Item Enhancements, it lands in Trade Goods.",
                            "If the class is Quest Items, it lands in Quest Items.",
                            "If the class is Key, it lands in Keys.",
                            "Otherwise, it lands in Other.",
                        }},
                        { type = "h2", text = "Renaming doesn't break it" },
                        { type = "paragraph", text = "The classifier looks up categories by their internal |cffffd700key|r (\"equipment\", \"consumables\", etc.) - not by their displayed name. So renaming \"Equipment\" to \"Gear\" or \"Armor & Weapons\" doesn't affect the classifier; weapons still go where the renamed category is." },
                        { type = "note", style = "info", text = "Deleting a default category lets it fall through. Items that would have landed in the deleted category drop to the next surviving category by display order, or ultimately to \"Other\" if it still exists. Use Reset to Defaults at the top of the Categories settings page to restore deleted defaults at any time." },
                    },
                },
                {
                    title = "Managing Categories",
                    blocks = {
                        { type = "lead", text = "The Categories settings page lets you rename, reorder, hide, delete, and create categories - and edit their pinned-item lists. Get there via |cffffd700Options > AddOns > BazUI > Bags > Categories|r." },
                        { type = "h2", text = "The page layout" },
                        { type = "list", items = {
                            "|cffffd700Create New Category|r and |cffffd700Reset to Defaults|r at the top of the list, on the left",
                            "|cffffd700Category list|r below those - one row per category, in display order",
                            "|cffffd700Detail panel|r on the right showing the selected category's editable settings",
                        }},
                        { type = "h2", text = "Identity: name and order" },
                        { type = "paragraph", text = "Each category has a |cffffd700Display Name|r (the label shown on its divider in the bag panel) and an |cffffd700Order|r (a number from 1 to 200 that controls vertical position; lower numbers appear first). Default categories use orders 10/20/30/40/50/60, so any value between 10 and 60 slots a custom category in between two defaults." },
                        { type = "h3", text = "Hide from bag panel" },
                        { type = "paragraph", text = "Toggle |cffffd700Hide from bag panel|r to suppress a category from the normal Categories-mode display. Hidden categories don't show their divider, items, or drop slot. The category still exists in the data - items can still be classified or pinned to it, they just don't render. Reactivate by toggling Hide off, or surface them temporarily via Categorize mode." },
                        { type = "note", style = "tip", text = "Hide is great for Junk - keep gray items grouped behind the scenes (so they don't get auto-classified back to \"Other\") without cluttering your bag view." },
                        { type = "h2", text = "Pinned items" },
                        { type = "paragraph", text = "The middle of the detail panel is a list of items currently pinned to this category. Each pin gets a |cffffd700Remove|r button. To add a pin from this page, type or paste an item ID into the |cffffd700Pin Item ID or Link|r box, or shift-click an item link from chat into it. (For most users, the in-bag pinning workflows are easier - see the next page.)" },
                        { type = "h2", text = "Delete" },
                        { type = "paragraph", text = "The Delete section at the bottom of the detail panel removes the selected category. Default categories warn you (the auto-classifier falls through to Other or whichever default still exists). Custom categories warn you in red - delete is permanent for the category itself, but pinned items just fall back to whatever the auto-classifier would pick." },
                    },
                },
                {
                    title = "Pinning Items",
                    blocks = {
                        { type = "lead", text = "Pins are per-item overrides that win over the auto-classifier - pin an Iron Bar to your custom \"Crafting\" category and that's where it always goes, regardless of its item class." },
                        { type = "h2", text = "Three ways to pin" },
                        { type = "paragraph", text = "Pick whichever feels best for the situation. All three update the same shared list of pins, so you can mix and match." },
                        { type = "h3", text = "1. Shift+right-click on a bag item" },
                        { type = "paragraph", text = "The fastest way for a single item. Shift+right-click any bag slot to open a context menu listing every category. The currently-pinned category (if any) shows a check mark in gold; click it again to unpin. Hidden categories appear with a gray \"(hidden)\" tag - you can deliberately pin to a hidden category to stash the item out of view." },
                        { type = "note", style = "info", text = "Shift+right-click is unbound by default in WoW for bag items, so this doesn't conflict with use-item, link-in-chat, or split-stack." },
                        { type = "h3", text = "2. Categorize mode (drag-and-drop)" },
                        { type = "paragraph", text = "Best for batch-pinning - pin many items in a row without opening menus. Left-click the bag's portrait icon to enter Categorize mode. Every category divider appears (including empty and hidden ones) with a gold |cffffd700+|r drop slot at the end of its grid. Pick up an item, drop it on the |cffffd700+|r > pinned. Pick up another item, drop on a different |cffffd700+|r > pinned. Toggle the portrait again to exit." },
                        { type = "h3", text = "3. From the Categories settings page" },
                        { type = "paragraph", text = "Useful when you know the exact item ID. Open the category's detail and use the |cffffd700Pin Item ID or Link|r input - type a numeric ID, paste an item link, or shift-click a link from chat. Each existing pin gets a Remove button so you can unpin from there too." },
                        { type = "h2", text = "Unpinning" },
                        { type = "list", items = {
                            "From shift+right-click menu: click the category that's already pinned (it has the gold check). The menu also has an explicit |cffffd700Unpin (auto-classify)|r entry below the categories.",
                            "From Categorize mode: there's no direct unpin from the drop slots - use shift+right-click or the settings page.",
                            "From the settings page: each pinned item has a |cffffd700Remove|r button.",
                        }},
                    },
                },
                {
                    title = "Categorize Mode",
                    blocks = {
                        { type = "lead", text = "Categorize mode is an explicit \"I want to manage categories now\" toggle. |cffffd700Middle-click|r the bag's portrait icon to enter; middle-click again to exit. State is in-memory only - every fresh /reload starts in normal mode." },
                        { type = "h2", text = "What changes when it's on" },
                        { type = "list", items = {
                            "Every category divider shows up - including categories with zero items currently",
                            "Hidden categories appear, marked with a gray \"(hidden)\" tag",
                            "Each category gets an extra empty slot at the end of its grid with a gold |cffffd700+|r centered in it",
                            "The bag panel grows to fit the extra dividers and drop slots",
                        }},
                        { type = "h2", text = "How to pin in Categorize mode" },
                        { type = "list", ordered = true, items = {
                            "Pick up an item from any bag slot (left-click the slot - cursor now holds the item)",
                            "Click the gold |cffffd700+|r drop slot at the end of the category you want - pin saved, cursor cleared",
                            "Repeat for any other items",
                            "Middle-click the portrait again to exit Categorize mode",
                        }},
                        { type = "h2", text = "Toggling without a middle button" },
                        { type = "paragraph", text = "If your mouse doesn't have a clickable middle button, run |cff00ff00/bbg categorize|r to toggle. Bind it to any keybind through Blizzard's macro UI for fast access." },
                        { type = "h2", text = "Why it's a mode" },
                        { type = "paragraph", text = "Earlier versions surfaced drop slots automatically whenever the cursor held an item. That competed with normal item-moving (drag from one bag slot to another to swap), so we made it explicit instead - drop slots only appear when you've opted in." },
                        { type = "note", style = "tip", text = "Shift+right-click on items still works in Categorize mode and out of it - use whichever feels natural for the task." },
                    },
                },
            },
        },

        ---------------------------------------------------------------
        -- 5. Customisation
        ---------------------------------------------------------------
        {
            title = "Customizing the Panel",
            blocks = {
                { type = "lead", text = "Most settings live under |cffffd700Options > AddOns > BazUI > Bags > General|r. Changes apply live - you can leave the bag panel open while you tweak and watch the panel reflow." },
                { type = "h2", text = "Layout" },
                { type = "table",
                  columns = { "Setting", "What it does" },
                  rows = {
                      { "|cffffd700Columns|r",          "How many slots wide the panel is. 4 to 20. The window resizes around it; rows are added or removed automatically." },
                      { "|cffffd700Hide Empty Slots|r", "Bags-mode only - skip empty slots so the panel shrinks to fit only occupied positions" },
                      { "|cffffd700Max Rows|r",         "Soft cap on the panel's content area, in rows of slots. The panel grows up to this many rows; anything past scrolls. Crank to ~30 to effectively disable the cap." },
                      { "|cffffd700Background Opacity|r", "0-100% slider. 100 is solid; lower lets the world show through. Items, text, and chrome stay fully opaque." },
                      { "|cffffd700Frame Strata|r",     "Z-order layer. Dialog (default) keeps the bag above the settings panel; lower strata tucks it under more UI." },
                  }},
                { type = "h2", text = "Money" },
                { type = "paragraph", text = "BazUI Bags shows your gold next to the search bar." },
                { type = "list", items = {
                    "|cffffd700Gold Only|r - hide silver and copper next to the search bar; useful at high gold totals where the silver/copper digits are visual noise",
                }},
                { type = "h2", text = "Blizzard UI" },
                { type = "list", items = {
                    "|cffffd700Hide Blizzard's Bag Bar|r - remove the backpack, bag slot and keyring buttons from the bottom-right corner. B, /bbg and the minimap entry still open the panel. To equip a new bag while the bar is hidden, right-click it in your inventory and it goes into an empty bag slot",
                }},
                { type = "h2", text = "Search" },
                { type = "paragraph", text = "The search box at the top-left of the panel filters every bag at once. Type a partial name, an item type (\"potion\"), a quality (\"epic\"), or any other tooltip-text fragment — items that don't match dim. Clear the box to restore the full view. The search reuses Blizzard's BagSearchBoxTemplate, so it behaves identically to the search box in the default UI." },
            },
        },

        ---------------------------------------------------------------
        -- 6. Tips & Tricks
        ---------------------------------------------------------------
        {
            title = "Tips & Tricks",
            blocks = {
                { type = "lead", text = "Patterns that aren't obvious from any single setting." },
                { type = "h2", text = "Hide Junk without losing it" },
                { type = "paragraph", text = "If gray items clutter your bag view but you still want to see them when you sell to a vendor, switch to Categories mode and toggle |cffffd700Hide|r on the Junk category. Gray items still take up real bag slots (they're not deleted) - they just don't render in BazUI Bags. They reappear in Blizzard's vendor UI as normal." },
                { type = "h2", text = "Stash an item out of view" },
                { type = "paragraph", text = "Make a custom category named \"Stash\" or \"Hidden\", toggle |cffffd700Hide|r on, then shift+right-click any item you want out of sight and pick the Stash category from the menu. The item stays in your bag (still occupies a real slot) but is invisible in BazUI Bags. Unpin or unhide to bring it back." },
                { type = "h2", text = "Two profiles for two playstyles" },
                { type = "paragraph", text = "Use a per-character BazUI Bags profile to pick different defaults per character. A crafter alt might want |cffffd700Categories mode + Hide Junk + tall Max Rows|r; a leveling alt might want |cffffd700Bags mode + Hide Empty + compact Max Rows|r. Profiles live under |cffffd700Options > AddOns > BazUI > Profiles|r; one profile covers every BazUI module." },
                { type = "h2", text = "Move the panel out of the way" },
                { type = "paragraph", text = "Drag the title bar (anywhere except the portrait) to reposition. The panel snaps to its top-left corner so a future settings change (toggling Categorize mode, switching display modes) grows the panel downward instead of from the center - your title bar stays put." },
                { type = "h2", text = "Quick sort" },
                { type = "paragraph", text = "|cff00ff00/bbg sort|r runs Blizzard's |cffffd700Clean Up Bags|r - the same sort the stock bags offer. BazUI Bags doesn't ship its own sorter." },
                { type = "h2", text = "Custom categories that survive Reset" },
                { type = "paragraph", text = "|cffffd700Reset to Defaults|r in the Categories settings page restores the default category labels and orders. It |cffffd700keeps|r your custom categories and item pins - only the defaults snap back. Use it when you've customized the defaults heavily and want to start fresh on those without losing your custom work." },
                { type = "note", style = "warning", text = "There's no \"Wipe Customs\" button right now - if you want to nuke every custom category in one shot, you'd need to delete them one-by-one through the settings page." },
            },
        },

        ---------------------------------------------------------------
        -- 7. Slash Commands & Keybinds
        ---------------------------------------------------------------
        {
            title = "Slash Commands",
            blocks = {
                { type = "lead", text = "Quick reference for every BazUI Bags slash command." },
                { type = "table",
                  columns = { "Command", "What it does" },
                  rows = {
                      { "|cff00ff00/bbg|r",            "Toggle the BazUI Bags panel" },
                      { "|cff00ff00/bbg toggle|r",     "Same as bare /bbg" },
                      { "|cff00ff00/bbg sort|r",       "Run Blizzard's Clean Up Bags (same as left-click on the portrait)" },
                      { "|cff00ff00/bbg categorize|r", "Toggle Categorize mode (same as middle-click on the portrait)" },
                      { "|cff00ff00/bazbags|r",        "Alias for /bbg - every subcommand works on either form" },
                  }},
                { type = "h2", text = "Keybinds" },
                { type = "paragraph", text = "BazUI Bags hooks Blizzard's bag toggles, so the standard |cffffd700B|r key opens BazUI Bags. You can also bind |cffffd700/bbg|r to any custom keybind via Blizzard's Keybindings UI or a macro." },
                { type = "code", text = "/run BazUI:GetModule(\"Bags\").Bag:Toggle()" },
                { type = "paragraph", text = "Above macro is equivalent to /bbg if you ever need the script form." },
                { type = "h2", text = "Profile commands" },
                { type = "paragraph", text = "Profiles are shared by every BazUI module. See the BazUI page of this manual for the full list. Quick reference:" },
                { type = "code", text = "/bazui profiles      -- list profiles" },
            },
        },
    },
})
