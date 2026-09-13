-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazBars User Guide
-- Registered so it appears as the module's User Manual tab.
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

-- Screenshot helper. All Bars User Manual images live in Media/
-- as 800x450 PNGs (16:9). The image content block defaults to 2:1
-- when you don't pass a height for a texture path - we always pass
-- both so they render at the correct aspect.
--
-- Note: PNG textures in WoW addons load via SetTexture with a full
-- path INCLUDING the .png extension. Without the extension the engine
-- only finds BLP/TGA - a silent miss for our screenshots.
local IMG_W, IMG_H = 640, 360
local function Image(file, caption)
    return {
        type = "image",
        texture = "Interface\\AddOns\\BazUI\\Modules\\Bars\\Media\\" .. file .. ".png",
        width = IMG_W,
        height = IMG_H,
        caption = caption,
    }
end

-- Side-by-side image + text. Image takes half of the content width
-- (BazUI resolves values between 0 and 1 as a fraction of the page),
-- height auto-derives 16:9. blocks is any array of standard content
-- blocks (paragraph, list, note, etc.).
local function ImageRow(file, caption, blocks, side)
    return {
        type = "imageRow",
        texture = "Interface\\AddOns\\BazUI\\Modules\\Bars\\Media\\" .. file .. ".png",
        imageWidth = 0.5,
        imageSide = side or "left",
        caption = caption,
        blocks = blocks,
    }
end

BazUI:RegisterUserGuide("Bars", {
    title = "Bars",
    intro = "Custom action bars that don't consume Blizzard's 1–120 action slot IDs. Create as many bars as you want, place them anywhere, and configure them through Blizzard's native Edit Mode.",
    pages = {
        ----------------------------------------------------------------
        -- Welcome
        ----------------------------------------------------------------
        {
            title = "Welcome",
            blocks = {
                { type = "lead", text = "BazUIBars lets you build action bars that live alongside Blizzard's defaults without conflicting. The same spell can sit on both your default bar and a BazBar simultaneously — buttons are independent of WoW's 1–120 action slot system, so you never have to swap things around to make room." },
                Image("one-bar", "One BazBar at full size — 24×24 = 576 buttons. And nothing stops you from having more bars."),
                { type = "h2", text = "What you get" },
                { type = "list", items = {
                    "Up to 24×24 button grids per bar (576 buttons each)",
                    "Unlimited number of bars",
                    "Native Blizzard look — same atlases, cooldown sweeps, proc glow, range tinting",
                    "Full Edit Mode integration with grid snap and pixel-precise nudge",
                    "Quick Keybind mode — hover a button and press a key (or any mouse button) to bind",
                    "Per-button macrotext editor with /cast conditionals + #showtooltip",
                    "Import / Export bar configs as shareable strings",
                    "Optional Masque skinning per bar",
                }},
                { type = "note", style = "tip", text = "Drag-and-drop accepts spells, items, macros, mounts and equipment sets. Items show live bag counts." },
            },
        },

        ----------------------------------------------------------------
        -- Creating a Bar
        ----------------------------------------------------------------
        {
            title = "Creating a Bar",
            blocks = {
                { type = "paragraph", text = "Open Blizzard's |cffffd700Edit Mode|r (default key Shift+F11)." },
                ImageRow("bar-create-button", "The Create New BazBar button sits at the bottom of the Edit Mode panel.", {
                    { type = "list", ordered = true, items = {
                        "Scroll to the bottom of the Edit Mode panel",
                        "Click the |cffffd700Create New BazBar|r button",
                        "A new bar spawns at the centre of your screen",
                        "Drag it where you want, then click it again to open settings",
                    }},
                }),
                { type = "note", style = "info", text = "Repeat as many times as you want. Each bar is independent — its own size, position, layout, and contents." },
                { type = "note", style = "tip", text = "Slash alternative: |cff00ff00/bb create|r spawns a fresh bar from chat, with optional col/row arguments (e.g. |cff00ff00/bb create 6 2|r for a 6×2 bar)." },
            },
        },

        ----------------------------------------------------------------
        -- Placing Buttons
        ----------------------------------------------------------------
        {
            title = "Placing Buttons",
            blocks = {
                { type = "lead", text = "Drag almost anything onto a button slot." },
                { type = "h2", text = "Drag sources" },
                { type = "table",
                  columns = { "Source", "Behaviour" },
                  rows = {
                      { "Spells",          "From your spellbook" },
                      { "Items",           "From your bags — shows live stack counts" },
                      { "Macros",          "From the macro window — name displays under icon" },
                      { "Mounts",          "From the mount journal, including Random Favourite" },
                      { "Equipment Sets",  "From the character pane" },
                  },
                },
                { type = "h2", text = "Live item tracking" },
                ImageRow("item-tracking", "Items show live stack counts as your bag changes — useful for tracking herbs, ore, raw fish while farming.", {
                    { type = "paragraph", text = "Item buttons display their bag count live. The number updates instantly as you loot, craft, or use the item." },
                    { type = "list", items = {
                        "Track herb / ore stacks while farming",
                        "Watch consumable counts during a raid pull",
                        "See repair-vendor reagents at a glance",
                    }},
                }, "right"),
                { type = "h2", text = "Removing buttons" },
                { type = "list", items = {
                    "|cffffd700Shift+Drag|r off the button to remove it",
                    "|cffffd700Shift+Right-Click|r to clear it in place",
                }},
                { type = "note", style = "warning", text = "If you have Blizzard's |cffffd700Cast on Key Down|r option enabled, plain click-drag will fire the ability before the drag starts. Use |cffffd700Shift+drag|r to rearrange buttons in that mode." },
            },
        },

        ----------------------------------------------------------------
        -- Editing a Bar
        ----------------------------------------------------------------
        {
            title = "Editing a Bar",
            blocks = {
                ImageRow("bar-settings-popup", "Per-bar settings popup. Selected bar highlighted yellow; everything you can configure for the bar is here.", {
                    { type = "paragraph", text = "While in Edit Mode, click any BazBar to select it (yellow highlight). Click again to open its settings popup." },
                    { type = "paragraph", text = "Every per-bar option lives here: layout, visibility, keybinds, appearance, behaviour, and actions like duplicate / export / delete." },
                }),
                { type = "h2", text = "Layout" },
                { type = "list", items = {
                    "|cffffd700Bar Name|r — custom display name",
                    "|cffffd700Orientation|r — horizontal or vertical",
                    "|cffffd700Rows / Icons|r — resize the button grid (up to 24×24)",
                    "|cffffd700Icon Size|r — scale from 50% to 250%",
                    "|cffffd700Icon Padding|r — spacing between buttons",
                }},
                { type = "h2", text = "Visibility" },
                { type = "paragraph", text = "Use Blizzard macro conditionals to control when the bar appears." },
                { type = "code", text = "[combat] show; hide" },
                { type = "paragraph", text = "Examples: |cffffd700[stance:1]|r, |cffffd700[vehicleui]|r, |cffffd700[group]|r, |cffffd700[mod:shift]|r." },
                { type = "note", style = "tip", text = "Or use the |cffffd700Bar Visibility|r preset dropdown in Appearance for common cases (always visible, in combat, etc.) without writing macros." },
                { type = "h2", text = "Keybinds" },
                ImageRow("quick-keybinding", "Quick Keybind Mode active — hover any button, press the key you want, done.", {
                    { type = "paragraph", text = "|cffffd700Quick Keybind Mode|r lets you bind keys directly to buttons. Open it from the Keybinds section, then hover a button and press the key (or mouse button) you want bound. Esc clears a binding." },
                    { type = "list", items = {
                        "Keyboard keys, modifier combos (Shift+E, Ctrl+1, etc.)",
                        "Middle mouse, mouse4, mouse5",
                        "Left and right mouse clicks are reserved (they interact with the button)",
                    }},
                }),
                { type = "note", style = "info", text = "If the key you press is already bound to a Blizzard action, BazUI Bars will evict the old binding and tell you in chat. The Blizzard side is preserved if you ever clear the BazUI Bars binding." },
                { type = "h2", text = "Appearance" },
                { type = "list", items = {
                    "|cffffd700Always Show Buttons|r — toggle empty-slot visibility",
                    "|cffffd700Show Slot Art|r — toggle the background slot texture under each button",
                    "|cffffd700Bar Opacity|r — overall transparency from 0–100%",
                    "|cffffd700Mouseover Fade|r — fade out when not hovered, fade back on hover",
                    "|cffffd700Bar Visibility|r — preset visibility states without writing macros",
                    "|cffffd700Masque skinning|r — per-bar Masque support (when Masque is installed)",
                    "Cooldown sweep + hotkey text visibility",
                }},
                { type = "h2", text = "Behaviour" },
                { type = "list", items = {
                    "|cffffd700Right-Click Self-Cast|r — cast helpful spells / use items on yourself with right-click on any button",
                    "|cffffd700Edit Button Macrotext|r — write a custom |cff00ff00/cast|r conditional macro per button. Supports |cff00ff00#showtooltip SpellName|r so the icon and tooltip update to whichever spell the macro will cast.",
                }},
                { type = "h2", text = "Actions" },
                { type = "table",
                  columns = { "Action", "What it does" },
                  rows = {
                      { "|cffffd700Revert Changes|r",      "Undo every change made since selecting the bar" },
                      { "|cffffd700Reset Position|r",      "Snap the bar back to the centre of the screen" },
                      { "|cffffd700BazUI Bars Settings|r",    "Jump to the full options panel for global settings" },
                      { "|cffffd700Export Bar Config|r",   "Copy the bar's complete layout + buttons + settings as a shareable string" },
                      { "|cffffd700Duplicate This Bar|r",  "Clone the bar with all its assignments in one click" },
                      { "|cffffd700Delete This Bar|r",     "Remove the bar permanently (asks for confirmation)" },
                  }},
                { type = "h2", text = "The full Bar Customizer" },
                ImageRow("bar-editor", "The Bar Customizer page. Same per-bar settings as the Edit Mode popup, just with all your bars visible at once.", {
                    { type = "paragraph", text = "Same settings, fuller layout. Open via |cff00ff00/bb|r or |cffffd700Options > AddOns > BazUI > Bars > Bar Options|r — every bar listed in a sidebar so you can switch between them without leaving the page." },
                }, "right"),
            },
        },

        ----------------------------------------------------------------
        -- Edit Mode Tools
        ----------------------------------------------------------------
        {
            title = "Edit Mode Tools",
            blocks = {
                { type = "paragraph", text = "Bars play by Edit Mode's rules:" },
                { type = "list", items = {
                    "Drag to move",
                    "Snap to the grid",
                    "Nudge with arrow keys for pixel-precise placement",
                    "Selection states use Blizzard's native cyan/yellow highlight art",
                }},
                { type = "note", style = "info", text = "Bar positions save to your active Edit Mode layout. Switching layouts in Edit Mode loads the matching bar positions." },
            },
        },

        ----------------------------------------------------------------
        -- Import / Export
        ----------------------------------------------------------------
        {
            title = "Import / Export",
            blocks = {
                { type = "lead", text = "BazUIBars exports any bar's complete configuration as a shareable string — layout, every button, every setting. Paste a string back to recreate the bar on any character." },
                { type = "h2", text = "Exporting" },
                { type = "list", items = {
                    "Edit Mode > click a bar > Settings popup > Actions > |cffffd700Export Bar Config|r",
                    "Or via slash: |cff00ff00/bb export <id>|r",
                    "A copy-paste dialog opens with the encoded string — copy it, share it, save it for later",
                }},
                { type = "h2", text = "Importing" },
                { type = "list", items = {
                    "|cff00ff00/bb import|r opens an empty paste dialog",
                    "Paste the shared string and confirm — a new bar with the imported config spawns at the centre of your screen",
                    "Drag it where you want and you're done",
                }},
                { type = "h2", text = "Duplicating" },
                { type = "paragraph", text = "Duplicate copies a bar plus every button assignment, position-shifted slightly so it doesn't sit directly on top of the original. Use Edit Mode > Actions > Duplicate This Bar, or |cff00ff00/bb duplicate <id>|r." },
            },
        },

        ----------------------------------------------------------------
        -- Profiles
        ----------------------------------------------------------------
        {
            title = "Profiles",
            blocks = {
                { type = "lead", text = "Switch between named profiles to keep different bar setups for different content — PvE, PvP, Raid, Mythic+, alt-specific layouts." },
                { type = "paragraph", text = "Each profile stores the complete BazUI Bars state: every bar's position, layout, button assignments, keybinds, visibility macros, and per-bar settings. Switching profiles swaps the entire UI in one go." },
                { type = "paragraph", text = "Open |cffffd700Options > AddOns > BazUI > Profiles|r (Create, Switch, Copy From, Reset, Delete)." },
                { type = "note", style = "tip", text = "One profile covers every BazUI module, so switching it changes Bars, Drawers, Chat and Bags together." },
            },
        },

        ----------------------------------------------------------------
        -- Slash Commands
        ----------------------------------------------------------------
        {
            title = "Slash Commands",
            blocks = {
                { type = "table",
                  columns = { "Command", "Effect" },
                  rows = {
                      { "/bb",                          "Open the BazUI Bars settings page" },
                      { "/bb create [cols] [rows]",     "Create a new bar (optional grid size)" },
                      { "/bb delete <id>",              "Delete a bar by ID" },
                      { "/bb duplicate <id>",           "Duplicate a bar with all its button assignments" },
                      { "/bb export <id>",              "Export a bar's config as a shareable string" },
                      { "/bb import",                   "Open the import dialog" },
                      { "/bb scale <id> <value>",       "Set a bar's scale" },
                      { "/bb padding <id> <pixels>",    "Set button spacing" },
                      { "/bb reset",                    "Reset all bars (reloads UI)" },
                      { "/bb help",                     "Print every command" },
                      { "/bazbars",                     "Alias for /bb — every subcommand works on either form" },
                  },
                },
            },
        },

        ----------------------------------------------------------------
        -- Tips
        ----------------------------------------------------------------
        {
            title = "Tips",
            blocks = {
                { type = "list", items = {
                    "Use a visibility macro like |cffffd700[combat] show; hide|r to make a bar appear only in combat",
                    "Items show live bag counts — handy for tracking herbs, ore, or potion stacks while farming",
                    "Random Favourite Mount works as a button — one click to roll a random mount",
                    "Bars don't take action slots, so all 120 default slots stay free",
                    "Combine Bars with the Drawers module for a fully customised UI without Blizzard slot constraints",
                }},
            },
        },
    },
})
