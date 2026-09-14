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
    Skin.lua           BazUI.Skin: texture paths, ratios, brand colours
    Assets/            power-of-two PNGs
  Modules/
    Drawers/           from BazWidgetDrawers (Era file set)
    Chat/              from BazChat; BazUI.Chat is its private namespace, BazUI.Chat.API the old BazChat global
    Bags/              from BazBags; Classic slot template, keyring section, no currency strip
    Bars/              from BazBars; BazUI.Bars is its namespace; toys, pets, flyouts dropped
    UnitFrames/        written by Codex; player and target frames, BazUIPlayerFrame root
    Auras/             new; SecureAuraHeaderTemplate headers anchored to BazUIPlayerFrame
```

## The module system

`BazUI:RegisterModule(name, config)` is BazCore's `RegisterAddon` under a new name (the old name stays as an alias). A module's `Core.lua` looks like:

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
- The options window shows one bottom tab per module. A module registers its pages with `BazUI:RegisterOptionsTable(key, fn)` and `BazUI:AddToSettings(key, label, parentKey)`, exactly as before.
- The BazUI landing page lists modules by title; there are no per-module versions.

## Widgets

`BazUI.Widgets` holds the dockable-widget registry with the LibBazWidget method names (`RegisterWidget`, `GetWidgets`, `RegisterCallback`, `RegisterDormantWidget`, ...). The `BazUI:RegisterDockableWidget` family forwards to it. Widgets are internal now; there is no third-party publishing path.

## Skin

Every texture and brand colour lives in `BazUI.Skin`. Modules reference `BazUI.Skin.MINIMAP_RING` and friends rather than paths. New assets go in `Skin/Assets` at power-of-two sizes; document their geometry (inner/outer ratios) next to the constant.

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
