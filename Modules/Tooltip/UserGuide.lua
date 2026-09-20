-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Tooltip User Manual
---------------------------------------------------------------------------

if not BazUI or not BazUI.RegisterUserGuide then return end

BazUI:RegisterUserGuide("Tooltip", {
    title = "Tooltip",
    intro = "The game's tooltip, wearing the same skin and the same face as "
        .. "everything else, and appearing where you tell it to.",

    pages = {
        {
            title = "What it does",
            blocks = {
                { type = "paragraph", text = "This module changes how the tooltip looks and where it appears. |cffffd700What it says is left alone|r - the item's stats, a unit's level and faction, a spell's description are the game's to write, and anything that adds lines to a tooltip keeps adding them." },
                { type = "paragraph", text = "It covers the tooltip that follows your mouse, the ones that open from a link in chat, and the comparison tooltips that appear beside an item you are looking at." },
                { type = "note", text = "|cffffd700Open it with|r /baztooltip, or Options > AddOns > BazUI > Tooltip." },
            },
        },

        {
            title = "Appearance",
            blocks = {
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Enable Tooltip module", "Off gives you the game's tooltip back, frame, health bar, scale and all." },
                    { "Use BazUI tooltip frame", "The border and background from your skin. Off keeps the game's art but leaves the positioning settings working." },
                    { "Tooltip scale", "75% to 150%." },
                    { "Background opacity", "50% to fully solid." },
                } },
                { type = "paragraph", text = "The border and the background come from the Skin tab, not from here - change a border band there and the tooltip changes with every other edge in the addon. The text takes the addon font, so a tooltip reads the same as your bars and your bags." },
            },
        },

        {
            title = "Where it appears",
            blocks = {
                { type = "paragraph", text = "|cffffd700Tooltip anchor|r is the first choice, and the other position settings follow from it." },
                { type = "table", columns = { "Anchor", "What happens" }, rows = {
                    { "Default / Drawer dock", "Wherever the game and other addons were going to put it. If you have a tooltip dock in a drawer, this is what lets it dock." },
                    { "Follow cursor", "Attached to your mouse, with a horizontal and vertical offset of your own." },
                    { "Fixed screen position", "Always in one place. Drag the marker, or use |cffffd700Screen horizontal offset|r and |cffffd700Screen vertical offset|r." },
                } },
                { type = "h3", text = "Tooltip origin" },
                { type = "paragraph", text = "Which corner or edge of the tooltip meets the anchor - which is really a choice about |cffffd700which way it grows|r, because a tooltip's height depends on what is in it. Pick Bottom and it grows upward from the marker; pick Top left and it grows down and to the right. |cffffd700Original direction|r leaves that to whatever was going to decide it." },
                { type = "paragraph", text = "This matters most at the edges of the screen: a tooltip anchored near the bottom wants to grow up, and a long one anchored near the top wants to grow down. It applies to cursor anchoring too." },
                { type = "h3", text = "Moving the marker" },
                { type = "list", items = {
                    "Turn on |cffffd700Unlock anchor|r, or type /baztooltip unlock, and a marker appears. It also switches you to |cffffd700Fixed screen position|r, because that is the only mode with a spot to drag.",
                    "Drag it where you want the tooltip.",
                    "Turn the setting off, right-click the marker, or type /baztooltip lock to put it away.",
                } },
                { type = "note", text = "Changing the origin leaves the marker where it is - the tooltip moves around the marker rather than the marker moving." },
            },
        },

        {
            title = "Visibility",
            blocks = {
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Hide unit tooltip health bar", "Drops the green bar under a unit's name." },
                    { "Hide tooltips during combat", "Nothing appears while you are fighting." },
                    { "Preview tooltip for 5 seconds", "Raises a sample so you can see a size, an opacity or a position without hunting for something to hover. Unavailable in combat." },
                } },
                { type = "note", text = "Every one of these is a switch you can throw back. |cffffd700The profile BazUI ships hides the health bar|r, on the grounds that a unit frame is already telling you that - untick it and it returns." },
            },
        },

        {
            title = "Things worth knowing",
            blocks = {
                { type = "list", items = {
                    "|cffffd700Comparison tooltips stay beside their item.|r Sending them to your cursor or to a fixed corner would separate the comparison from the thing being compared, which is the whole point of it.",
                    "|cffffd700A docked tooltip uses the drawer's scale|r rather than the one set here, so it fits its dock. Choosing Follow cursor or Fixed screen position pauses docking.",
                    "|cffffd700Changes apply on the next hover.|r A tooltip on screen when you change a setting is taken away rather than restyled where it stands, so the next thing you point at is the first one wearing the new look.",
                    "|cffffd700Bag tooltips|r are anchored by the game in a way that argues with ours; the module settles that so a bag tooltip lands where you asked rather than throwing an anchoring error.",
                } },
            },
        },

        {
            title = "Slash commands",
            blocks = {
                { type = "table", columns = { "Command", "What it does" }, rows = {
                    { "/baztooltip", "Opens the settings." },
                    { "/baztooltip unlock", "Shows the draggable marker." },
                    { "/baztooltip lock", "Puts it away." },
                } },
            },
        },
    },
})
