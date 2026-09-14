-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazBars Constants and Defaults

-- Module namespace. Every Bars file starts with `local BazBars = BazUI.Bars`.
local BazBars = BazUI.Bars or {}
BazUI.Bars = BazBars

BazBars.ADDON_NAME = "Bars"
BazBars.VERSION = BazUI.VERSION

-- Button defaults
BazBars.DEFAULT_BUTTON_SIZE = 45
BazBars.DEFAULT_SPACING = 2
BazBars.DEFAULT_SCALE = 1.0
BazBars.DEFAULT_COLS = 6
BazBars.DEFAULT_ROWS = 1
BazBars.MAX_COLS = 24
BazBars.MAX_ROWS = 24
BazBars.MIN_SCALE = 0.5
BazBars.MAX_SCALE = 2.5

-- Visual
BazBars.BAR_BG_COLOR = { r = 0.1, g = 0.1, b = 0.1, a = 0.6 }
BazBars.BAR_BORDER_COLOR = { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }
BazBars.BAR_BG_UNLOCKED = { r = 0.15, g = 0.15, b = 0.3, a = 0.7 }

---------------------------------------------------------------------------
-- Global Override Helpers
---------------------------------------------------------------------------

-- Read a per-bar setting, respecting global overrides
function BazBars.GetBarSetting(barData, key)
    local bbAddon = BazUI:GetModule("Bars")
    if bbAddon and bbAddon.db then
        local overrides = bbAddon.db.profile.globalOverrides
        if overrides then
            local override = overrides[key]
            if override and override.enabled then
                return override.value
            end
        end
    end
    return barData[key]
end

-- Check if a global override is active for a given key
function BazBars.IsGlobalOverrideActive(key)
    local bbAddon = BazUI:GetModule("Bars")
    if not bbAddon or not bbAddon.db then return false end
    local overrides = bbAddon.db.profile.globalOverrides
    if not overrides then return false end
    return overrides[key] and overrides[key].enabled or false
end

---------------------------------------------------------------------------
-- Defaults for new bar saved data
---------------------------------------------------------------------------

-- Defaults for new bar saved data
function BazBars.DefaultBarData(id)
    return {
        id = id,
        cols = BazBars.DEFAULT_COLS,
        rows = BazBars.DEFAULT_ROWS,
        spacing = BazBars.DEFAULT_SPACING,
        scale = BazBars.DEFAULT_SCALE,
        alpha = 1.0,
        locked = false,
        buttons = {},
        pos = nil,
        customName = nil,
        mouseoverFade = false,
        mouseoverAlpha = 0.3,
        rightClickSelfCast = false,
        endcaps = "off",   -- "off" / "alliance" / "horde"
        -- false: endcaps are sized to a single button row regardless
        -- of how many rows the bar has (Blizzard MainActionBar look).
        -- true: endcaps scale with the full bar height (oversize for
        -- multi-row bars).
        endcapsAutoScale = false,
        -- Endcap size multiplier (applied to fixed-size mode only).
        -- 1.0 = default size; user-adjustable via the slider in the
        -- bar's edit-mode popup.
        endcapsScale = 1.0,
    }
end

---------------------------------------------------------------------------
-- Endcap atlas tables (Alliance gryphons, Horde wyverns) - same atlases
-- Blizzard's MainActionBar uses for its native endcaps.
---------------------------------------------------------------------------

BazBars.ENDCAP_ATLASES = {
    alliance = {
        left  = "UI-HUD-ActionBar-Gryphon-Left",
        right = "UI-HUD-ActionBar-Gryphon-Right",
    },
    horde = {
        left  = "UI-HUD-ActionBar-Wyvern-Left",
        right = "UI-HUD-ActionBar-Wyvern-Right",
    },
}
