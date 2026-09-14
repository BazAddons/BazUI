-- SPDX-License-Identifier: GPL-2.0-or-later
BazUI:RegisterUserGuide("Tooltip", {
    title = "Tooltip",
    intro = "A subtle charcoal and muted-gold frame, with simple positioning and visibility controls.",
    pages = { { title = "Overview", blocks = {
        { type = "paragraph", text = "Open Options > AddOns > BazUI > Tooltip, or type /baztooltip. Settings apply to the main hover tooltip, linked-item tooltips and equipment comparisons. Text and item information stay unchanged." },
        { type = "list", items = {
            "Use the BazUI frame, adjust background opacity, or change the overall scale.",
            "Default anchoring respects Blizzard, other UI frames and the Drawers tooltip dock.",
            "Follow cursor and fixed screen position move the main hover tooltip. Comparisons stay attached to their item.",
            "Hide the unit health bar or hide tooltips during combat. Both are optional.",
            "A tooltip in the drawer dock uses the drawer's fit scale. Choosing another anchor pauses docking.",
            "Turn off the module to restore the original frame, health bar and scale. Hover again after changing settings.",
        } },
    } } },
})
