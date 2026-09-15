# BazUI - Developer Notes

BazUI is a single addon that absorbs the Baz Suite for World of Warcraft: Forever. This file explains how it is put together and how the remaining addons get ported in.

## Layout

```
BazUI/
  BazUI.toc            load order; Interface is Era until the Forever client ships
  Core/                forked from BazCore (BazUI namespace)
    Core.lua           module registry, lifecycle, login queue
    Profiles.lua       BazUIDB.profiles[name][module] = { ... }
    Widgets.lua        dockable-widget registry (was LibBazWidget-1.0)
    Options/           options window, page builders, user guide renderer
    ...                Edit Mode, popups, UI helpers, timers, formatting
  Skin/
    Skin.lua           BazUI.Skin: texture paths, ratios, brand colors
    Assets/            power-of-two PNGs
  Modules/
    Drawers/           from BazWidgetDrawers (Era file set); Widgets/ also holds the BazWidgets pack (bazdrawer_ ids) and Broker.lua (LibDataBroker feeds, bazdrawer_ldb_ ids; library not embedded)
    Chat/              from BazChat; BazUI.Chat is its private namespace, BazUI.Chat.API the old BazChat global
    Bags/              from BazBags; Classic slot template, keyring section, no currency strip
    Bars/              from BazBars; BazUI.Bars is its namespace; toys and pets dropped
    UnitFrames/        written by Codex; player and target frames, BazUIPlayerFrame root
    Auras/             new; SecureAuraHeaderTemplate headers anchored to BazUIPlayerFrame
    Notifications/     from BazNotificationCenter; BazUI.Notifications, API in BazUI.Notifications.API; Sources/ are its event modules
    MicroMenu/         new; adopts Blizzard's micro buttons onto BazUIMicroMenu and skins them with Skin.Theme
```

## The module system

`BazUI:RegisterModule(name, config)` is BazCore's `RegisterAddon` under a new name. A module's `Core.lua` looks like:

```lua
local MODULE_NAME = "Drawers"
local addon
addon = BazUI:RegisterModule(MODULE_NAME, {
    title    = "Drawers",
    profiles = true,
    defaults = { ... },
    slash    = { "/bwd" },
    commands = { ... },
    minimap  = { label = "Drawers", icon = 7416769 },
    onLoad   = function(self) end,   -- saved variables ready
    onReady  = function(self) end,   -- PLAYER_LOGIN
})
```

Other files in the module fetch the object with `BazUI:GetModule("Drawers")`. Settings go through `addon:GetSetting(key)` / `addon:SetSetting(key, value)`, which read and write the module's section of the active profile.

Differences from the old suite:

- One saved variable, `BazUIDB`. No per-module saved variables and no migration from the old addons; BazUI starts fresh.
- Module init runs on BazUI's own `ADDON_LOADED`, not a per-addon one.
- The options window is Blizzard's Settings panel: BazUI is a category, each module a subcategory, and a module's pages are tabs across its canvas. A module registers a page with `BazUI:RegisterOptionsTable(key, fn)` and `BazUI:AddToSettings(key, label, parentKey, order)`. Tabs run General, then the module's own pages (by `order`, else alphabetical), then the User Manual from `BazUI:RegisterUserGuide`. Register a stub `{ name, type = "group", args = {} }` for the module key itself; it never renders once the module has pages. There are no landing pages and no Global Settings tabs: a value that applies to every item lives in a section on General.
- There are no per-module versions.

### Options pages

`Core/Options` renders one column of rows at up to 640 px: label on the left, control on the right, an optional `desc` under the label. Row types: `toggle`, `range` (`min`/`max`/`step`, then `isPercent` or a `format` such as `"%d s"`), `select` (`values` map plus a `sorting` array), `input`, `execute` (`confirm*` fields; `style = "danger"` for destructive actions), `description` and `header`. Every option accepts `disabled` and `hidden` as a value or a function; a `set` handler that changes what other rows should show calls `BazUI:RefreshOptions(pageKey)`. The User Manual content blocks (`paragraph`, `note`, `table`, ...) also render on a page. Write labels as short sentences in sentence case and keep `desc` for what the label cannot say.

A collection of editable items is a non-inline `group` whose args are one sub-group per item. It renders as a picker row (dropdown, then Up/Down when the group has `onMoveUp`/`onMoveDown`, then buttons) with the selected item's args as the form beneath. On the group: `pickerLabel`, `emptyText`, and `itemActions`, execute-shaped entries whose `func`, `confirmText` and `disabled` receive the selected item. On an item: `toggle = { name, get, set }` draws an on/off switch on the picker row, and `source` groups the dropdown. Executes ordered before the group become buttons on the picker row. `BazUI:CreateManagedListPage` builds this shape from `getItems`/`buildDetail`; selection survives re-renders by the item's args key.

Notifications sources describe their events with `{ type = "event", show, toast, default }` option definitions (see `Modules/Notifications/API/ModuleRegistry.lua`); the Sources page turns each into an Off / History only / Toast choice.

## Starter profile

`Core/StarterProfile.lua` is the layout a fresh install starts with: `BazUI.StarterProfile[moduleName]` is deep-merged over a module's coded defaults the first time that module's section is created in a profile (fresh install, new profile, or a module added to an existing install). Existing sections are never touched. Positions in it must be screen anchors (`{ point, relPoint, x, y }`), never absolute pixels, so they hold at any resolution; Bars offsets are in the bar's own scaled units. When a module renames a setting, update its starter entry too.

## Widgets

`BazUI.Widgets` holds the dockable-widget registry with the LibBazWidget method names (`RegisterWidget`, `GetWidgets`, `RegisterCallback`, `RegisterDormantWidget`, ...). The `BazUI:RegisterDockableWidget` family forwards to it. Widgets are internal now; there is no third-party publishing path.

## Skin

Every texture and brand color lives in `BazUI.Skin`. Modules reference `BazUI.Skin.MINIMAP_RING` and friends rather than paths. New assets go in `Skin/Assets` at power-of-two sizes; document their geometry (inner/outer ratios) next to the constant.

`Skin/Theme.lua` holds the shared look: the color palette (`BazUI.Skin.Theme.colors`), the gold-edged panel backdrop (`Theme.ApplyPanel`), a flat inner backdrop, and the round ring-framed button treatment (`Theme.ApplyRoundButton`). New module UI should draw from it rather than define its own colors.

### Tabs

`BazUI.CreateTabStrip(name, parent, opts)` in `Core/TabStrip.lua` builds every row of tabs. It speaks the same API as Blizzard's `TabSystemTemplate`, which Classic ships in source but does not load: `AddTab`, `SetTab`, `SetTabSelectedCallback`, `SetTabVisuallySelected`, `ClearTabs`, `MarkDirty`, plus `tab.layoutIndex` so a drag placeholder can slot in. Two looks via `opts.style`: `"panel"` for tabs that sit above a page (the options canvas, the chat dock) and `"underline"` for tabs inside a panel (the notification center). Colors come from the theme.

The drawer's tab rail is deliberately not this. It is a vertical column of icon buttons on the drawer's edge whose click switches drawer or toggles the panel, and whose slots stay reserved when the drawer opens. It shares the idea of "one of these is current" and nothing else, so it stays its own component in `Modules/Drawers/Drawer.lua`.

### The shared face

`Skin/Assets/DORISBR.TTF` (DorisPP) is the suite's font. Ask for `BazUI.Skin.Theme.FontFile()` anywhere you would have written `STANDARD_TEXT_FONT`; it returns the game's font when the user turns the face off under BazUI > General or when the client can't read the file. Fonts are read at client startup, so a newly added file needs a restart, not a `/reload`. Where code sets a font object rather than a file, ask for `BazUI.Skin.Theme.FontObject("GameFontNormal")`: it mirrors that Blizzard object in our face and is edited in place, so the switch changes it live. Chat sets its own face through a font object of its own because it also carries a size slider.

## Flavour and compatibility

Development happens on Classic Era 1.15 because Forever is built by the Classic team on the same client family. Keep every API touchpoint that might differ (quest log, containers, minimap frames, chat) behind small helpers so the Forever delta is a short edit. `Modules/Drawers/Compat.lua` holds third-party shims; a top-level `Compat.lua` is the place for client-version shims once the beta shows what differs.

Not universal: Retail is served by the existing Baz Suite addons. Do not add Retail branches here.

### Templates: check the TOC, not the source tree

The `wow-ui-source` checkout contains every flavour's files, but a Classic client only loads what its `*_Vanilla.toc` (or the XML manifest it includes) lists. `TabSystemTemplate` is the cautionary example: present in `Blizzard_SharedXML/Shared/TabSystem`, never loaded on Era, and `CreateFrame` throws "Couldn't find inherited node". Before using a Blizzard template, confirm it is loaded; `Core/TabStrip.lua` exists because the TabSystem is not. Same rule for atlases (`BazUI.SetAtlasOrTexture`) and for `C_*` API members (check `Blizzard_APIDocumentationGenerated` in the Classic checkout).

## Porting the next modules

Recipe used for Drawers, apply the same to Chat, Bags and Bars:

1. Copy the addon's files into `Modules/<Name>/`, dropping Retail-only files.
2. Rename the namespace: `BazCore` becomes `BazUI`; `BazCore:GetAddon("<Old>")` becomes `BazUI:GetModule("<Name>")`; the `RegisterAddon` call becomes `RegisterModule` and loses `savedVariable`.
3. Rename global frame names to a `BazUI<Name>` prefix so nothing collides with the old addons on a dev machine that still has them installed.
4. Move textures into `Skin/Assets` and reference them through `BazUI.Skin`.
5. Strip Midnight-only machinery (secret values, forbidden-table guards) where the Classic client makes it unnecessary; keep secure-template rules for anything that clicks spells or items.
6. Add the files to `BazUI.toc`, run luacheck from the suite root, deploy to the Era AddOns folder and test with BazCore-based addons disabled.

## Testing

Copy the working tree (minus .git, .github, .pkgmeta, CHANGELOG.md, DEVELOPERS.md) to `_classic_era_\Interface\AddOns\BazUI`. Disable BazCore, BazWidgetDrawers, LibBazWidget, BazWidgets, BazChat and BazBags on that character; BazUI prints a warning at login if any of them is loaded. New texture files need a full client restart, not a reload.

## Release

Tag-triggered BigWigs packager, same as the suite. The workflow currently builds `-g classic` (Era). CurseForge has no Forever game version yet; expect the first Forever upload to be manual. `CHANGELOG.md` holds only the newest entry, written for players.
