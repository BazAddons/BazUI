# XP Bar

Retail-inspired continuous experience bar for Classic Era: fine gold trim,
purple normal XP, blue rested XP, a muted rested extension, and optional
10% markers. No new texture download is needed; the shared skin references
the client's status-bar texture.

Open `/bazxp`. Settings include width, height, scale, Always/On Hover/Never
text, rested overlay and maximum-level visibility. `/bazxp unlock`, `lock`
and `reset` control positioning, also available through BazUI Edit Mode.
The hover tooltip shows exact current, required, remaining and rested XP.

Disabling restores the original XP elements. Reputation and action bars
are not reparented. Stock-frame changes wait until combat ends. The bar
is hidden at maximum level by default but can be moved in Edit Mode.

Validation: Lua 5.1 mocked progress/rested/level-cap events, visibility,
profile changes, combat deferral, stock-frame restoration, and settings.
Final texture appearance and interaction require an in-game check.
