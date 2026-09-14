-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: SettingsSpec
--
-- Single source of truth for every chrome / behavior / timestamps
-- setting BazChat exposes. Both the Options page (Options/Settings.lua)
-- and the Edit Mode popup (Replica/Window.lua's CreateDock) read this
-- spec via BazUI:BuildOptionsTableFromSpec and
-- :BuildEditModeArrayFromSpec - so the two panels can't drift apart.
--
-- Design rules:
--   * Every entry that appears in BOTH panels has matching label, type,
--     and binding. Differences are surface-specific (Edit Mode hides
--     conf-heavy stuff like "History buffer" because you wouldn't tweak
--     it while repositioning the dock).
--   * All chrome settings live on windows[1] (the canonical block;
--     Window:ApplySettings reads from there and applies to every tab).
--   * `surfaces = { options = true, editMode = true }` means BOTH panels.
--   * `surfaces = { options = true }` (or omitted) means options-only.
--   * Live-application: every set() calls Window:ApplySettings(1) so
--     changes show up immediately in the chat without a /reload.
--
-- Section layout (rendered top-to-bottom by `order`):
--   appearance  - opacity/scale/visibility (in BOTH panels)
--   behavior    - fade/wrap/spacing/history (Options only)
--   timestamps  - format/enable (Options only)
--   layout      - position nudge (Edit Mode only - inserted via spec)
---------------------------------------------------------------------------

local addon     = BazUI.Chat          -- Chat's private namespace
local BazChat   = addon.API           -- module API (the old BazChat global)
local addonName = addon.MODULE_NAME

-- Profile accessors used by every entry's get/set. Wrapped here so we
-- don't repeat the addon.db / addon.core.db fallback chain in 30 places.
local function Profile()
    return (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
end

local function Win(idx)
    local p = Profile()
    return p and p.windows and p.windows[idx]
end

-- Chrome canonical block lives on windows[1]; every chat window in the
-- dock reads its visuals from there in Window:ApplySettings.
local function W() return Win(1) end

-- Apply chrome changes to every live window so the user sees the result
-- immediately on slider/toggle changes. Called from set() on every entry.
local function ApplyAll()
    if addon.Window and addon.Window.ApplyAll then
        addon.Window:ApplyAll()
    end
end

-- Force the timestamp overlay system to re-measure + re-render. Used
-- by the Timestamps section setters so toggles + format changes apply
-- without waiting for the next chat message.
local function ApplyTimestamps()
    if not (addon.Window and addon.Window.list) then return end
    if addon.Timestamps and addon.Timestamps.InvalidateLayout then
        for _, win in pairs(addon.Window.list) do
            addon.Timestamps:InvalidateLayout(win)
        end
    end
    ApplyAll()
    for _, win in pairs(addon.Window.list) do
        if win.MarkLayoutDirty  then win:MarkLayoutDirty()  end
        if win.MarkDisplayDirty then win:MarkDisplayDirty() end
        if win.RefreshLayout    then win:RefreshLayout()    end
        if win.RefreshDisplay   then win:RefreshDisplay()   end
    end
end

---------------------------------------------------------------------------
-- The spec
---------------------------------------------------------------------------

local SPEC = {
    sections = {
        master     = { label = "",               order = 1  },   -- options only
        appearance = { label = "Appearance",     order = 10 },
        behavior   = { label = "Behavior",       order = 20 },
        timestamps = { label = "Timestamps",     order = 30 },
        channelNm  = { label = "Channel Names",  order = 35 },   -- options only
        layout     = { label = "Layout",         order = 40 },   -- editMode only
    },

    entries = {
        -----------------------------------------------------------------
        -- Master enable (Options only - addon-level on/off)
        -----------------------------------------------------------------

        { key = "enabled", label = "Enable BazUI Chat", section = "master",
          type = "toggle", order = 1,
          desc = "Master switch. When off, the replica is shut down and Blizzard's default chat is restored on /reload.",
          get = function() return addon.core and addon.core:GetSetting("enabled") end,
          set = function(_, v)
              if not addon.core then return end
              addon.core:SetSetting("enabled", v)
              if BazChat.RefreshAll then BazChat:RefreshAll() end
          end },

        -----------------------------------------------------------------
        -- Appearance: opacity + sizing (BOTH panels)
        -----------------------------------------------------------------

        { key = "alpha", label = "Text opacity", section = "appearance",
          type = "slider", order = 10,
          desc = "Opacity of the chat text and scrollbar (the foreground content). 100% is fully opaque.",
          surfaces = { options = true, editMode = true },
          min = 0, max = 1, step = 0.05, format = "percent",
          get = function() local s = W() return s and s.alpha or 1.0 end,
          set = function(_, v) local s = W() if s then s.alpha = v end; ApplyAll() end },

        { key = "bgAlpha", label = "Background opacity", section = "appearance",
          type = "slider", order = 11,
          desc = "Opacity of the dark gold panel behind the chat (the background chrome), independent of the text. Drop this to make the panel fade away while leaving text fully readable.",
          surfaces = { options = true, editMode = true },
          min = 0, max = 1, step = 0.05, format = "percent",
          get = function() local s = W() return s and s.bgAlpha or 1.0 end,
          set = function(_, v) local s = W() if s then s.bgAlpha = v end; ApplyAll() end },

        { key = "tabsAlpha", label = "Tabs opacity", section = "appearance",
          type = "slider", order = 12,
          desc = "Opacity of the tab strip when shown. Onhover mode fades from 0 up to this value; always-mode pins to it.",
          surfaces = { options = true, editMode = true },
          min = 0, max = 1, step = 0.05, format = "percent",
          get = function() local s = W() return s and s.tabsAlpha or 1.0 end,
          set = function(_, v) local s = W() if s then s.tabsAlpha = v end; ApplyAll() end },

        { key = "customFont", label = "Use the BazUI chat font", section = "appearance",
          type = "toggle", order = 9,
          desc = "DorisPP, the face BazUI ships, at the chat font size set in the game's own chat options. Off uses Blizzard's font.",
          surfaces = { options = true, editMode = true },
          get = function() local s = W() return not s or s.customFont ~= false end,
          set = function(_, v) local s = W() if s then s.customFont = v end; ApplyAll() end },

        { key = "fontScale", label = "Text size", section = "appearance",
          type = "slider", order = 9.5,
          desc = "Scales the chat text relative to the size set in the game's own chat options. Affects the text only, not the window.",
          surfaces = { options = true, editMode = true },
          min = 0.5, max = 2, step = 0.05, format = "percent",
          get = function() local s = W() return s and s.fontScale or 1.0 end,
          set = function(_, v) local s = W() if s then s.fontScale = v end; ApplyAll() end },

        { key = "scale", label = "Window scale", section = "appearance",
          type = "slider", order = 13,
          desc = "Visual scale of the entire chat window (UI scale multiplier).",
          surfaces = { options = true, editMode = true },
          min = 0.5, max = 2.0, step = 0.05, format = "percent",
          get = function() local s = W() return s and s.scale or 1.0 end,
          set = function(_, v) local s = W() if s then s.scale = v end; ApplyAll() end },

        -----------------------------------------------------------------
        -- Appearance: visibility modes (BOTH panels)
        -----------------------------------------------------------------

        { key = "bgMode", label = "Background visibility", section = "appearance",
          type = "select", order = 20,
          desc = "When the dark panel behind the chat is visible.",
          surfaces = { options = true, editMode = true },
          values = {
              always  = "Always visible",
              onhover = "On hover (auto-hide)",
              never   = "Never",
          },
          get = function()
              local s = W()
              if s and s.chromeFadeMode and s.chromeFadeMode ~= "off" then
                  return s.chromeFadeMode
              end
              return (s and s.bgMode) or "always"
          end,
          set = function(_, v) local s = W() if s then s.bgMode = v end; ApplyAll() end,
          disabled = function()
              local s = W()
              return s and s.chromeFadeMode and s.chromeFadeMode ~= "off"
          end,
          disabledLabel = "Unified",
        },

        { key = "tabsMode", label = "Tabs visibility", section = "appearance",
          type = "select", order = 21,
          desc = "When the chat tab strip is visible.",
          surfaces = { options = true, editMode = true },
          values = {
              always  = "Always visible",
              onhover = "On hover (auto-hide)",
              never   = "Never",
          },
          get = function()
              local s = W()
              if s and s.chromeFadeMode and s.chromeFadeMode ~= "off" then
                  return s.chromeFadeMode
              end
              return (s and s.tabsMode) or "always"
          end,
          set = function(_, v) local s = W() if s then s.tabsMode = v end; ApplyAll() end,
          disabled = function()
              local s = W()
              return s and s.chromeFadeMode and s.chromeFadeMode ~= "off"
          end,
          disabledLabel = "Unified",
        },

        { key = "scrollbarMode", label = "Scrollbar visibility", section = "appearance",
          type = "select", order = 22,
          desc = "When the scrollbar appears on the right edge. Mouse wheel always scrolls regardless of this setting.\n\nAlways: visible at all times.\nOn scroll: fades in when you scroll or hover the chat, fades out a couple seconds later.\nNever: hidden entirely.",
          surfaces = { options = true, editMode = true },
          values = {
              always   = "Always visible",
              onscroll = "On scroll (auto-hide)",
              never    = "Never",
          },
          get = function()
              local s = W()
              return (s and s.scrollbarMode) or "always"
          end,
          set = function(_, v) local s = W() if s then s.scrollbarMode = v end; ApplyAll() end },

        { key = "chromeFadeMode", label = "Unified background + tabs", section = "appearance",
          type = "select", order = 23,
          desc = "Force background and tabs to share a fade mode.\n\nIndependent: each is controlled separately.\nAlways / On hover / Never: both forced to that mode (the individual dropdowns above grey out).",
          surfaces = { options = true, editMode = true },
          values = {
              off     = "Independent",
              always  = "Always visible",
              onhover = "On hover (auto-hide)",
              never   = "Never",
          },
          get = function() local s = W() return (s and s.chromeFadeMode) or "off" end,
          set = function(_, v)
              local s = W()
              if s then
                  s.chromeFadeMode = v
                  if v ~= "off" then
                      s.bgMode   = v
                      s.tabsMode = v
                  end
              end
              ApplyAll()
          end },

        -----------------------------------------------------------------
        -- Behavior (Options only - configuration, not visual tweak)
        -----------------------------------------------------------------

        { key = "fading", label = "Fade old messages", section = "behavior",
          type = "toggle", order = 10,
          desc = "When on, messages fade out after the visible-for window expires. When off, they stay visible until pushed off by new lines.",
          get = function() local s = W() return s and s.fading ~= false end,
          set = function(_, v) local s = W() if s then s.fading = v end; ApplyAll() end },

        { key = "timeVisible", label = "Visible for (seconds)", section = "behavior",
          type = "slider", order = 11,
          desc = "How long a message is fully visible before it begins fading.",
          min = 10, max = 600, step = 10, format = "integer",
          get = function() local s = W() return s and s.timeVisible or 120 end,
          set = function(_, v) local s = W() if s then s.timeVisible = v end; ApplyAll() end,
          disabled = function() local s = W() return s and s.fading == false end },

        { key = "fadeDuration", label = "Fade duration (seconds)", section = "behavior",
          type = "slider", order = 12,
          desc = "How long the fade-out animation takes once a message starts fading.",
          min = 0, max = 5, step = 0.1, format = "seconds",
          get = function() local s = W() return s and s.fadeDuration or 0.5 end,
          set = function(_, v) local s = W() if s then s.fadeDuration = v end; ApplyAll() end,
          disabled = function() local s = W() return s and s.fading == false end },

        { key = "indentedWordWrap", label = "Indent wrapped lines", section = "behavior",
          type = "toggle", order = 20,
          desc = "When a line wraps, indent the continuation under the first character of the message body. Honored only when timestamps are off; with timestamps on, the gutter handles wrap alignment automatically.",
          get = function() local s = W() return s and s.indentedWordWrap ~= false end,
          set = function(_, v) local s = W() if s then s.indentedWordWrap = v end; ApplyAll() end },

        { key = "messageSpacing", label = "Line spacing (pixels)", section = "behavior",
          type = "slider", order = 21,
          desc = "Extra vertical pixels between rendered chat lines. Affects all line boundaries including wrapped continuations - keep small (1-3 px) for a subtle gap, or 0 for tight default behavior.",
          min = 0, max = 8, step = 1, format = "px",
          get = function() local s = W() return s and s.messageSpacing or 0 end,
          set = function(_, v) local s = W() if s then s.messageSpacing = v end; ApplyAll() end },

        { key = "maxLines", label = "History buffer (lines)", section = "behavior",
          type = "slider", order = 30,
          desc = "Maximum number of past lines kept in scrollback. Higher uses more memory; 500 matches Blizzard's default.",
          min = 100, max = 2000, step = 50, format = "integer",
          get = function() local s = W() return s and s.maxLines or 500 end,
          set = function(_, v) local s = W() if s then s.maxLines = v end; ApplyAll() end },

        -----------------------------------------------------------------
        -- Timestamps (Options only)
        -----------------------------------------------------------------

        { key = "tsEnabled", label = "Show timestamps", section = "timestamps",
          type = "toggle", order = 10,
          desc = "Show a timestamp in a left gutter alongside every chat line, with a vertical bar tinted to the message's chat color.",
          get = function()
              local p = Profile()
              return p and p.timestamps and p.timestamps.enabled or false
          end,
          set = function(_, v)
              local p = Profile()
              if p and p.timestamps then p.timestamps.enabled = v end
              ApplyTimestamps()
          end },

        { key = "tsFormat", label = "Format", section = "timestamps",
          type = "select", order = 11,
          desc = "Pick a clock format. Power users can hand-edit the strftime string in the saved variable for locale-specific formats.",
          values = {
              ["%H:%M"]       = "24-hour (14:32)",
              ["%H:%M:%S"]    = "24-hour with seconds (14:32:09)",
              ["%I:%M %p"]    = "12-hour (2:32 PM)",
              ["%I:%M:%S %p"] = "12-hour with seconds (2:32:09 PM)",
          },
          get = function()
              local p = Profile()
              return (p and p.timestamps and p.timestamps.format) or "%H:%M:%S"
          end,
          set = function(_, v)
              local p = Profile()
              if p and p.timestamps then
                  p.timestamps.format = (v ~= "" and v) or "%H:%M:%S"
              end
              ApplyTimestamps()
          end,
          disabled = function()
              local p = Profile()
              return not (p and p.timestamps and p.timestamps.enabled)
          end },

        { key = "tsHoverTooltip", label = "Show date tooltip on hover", section = "timestamps",
          type = "toggle", order = 12,
          desc = "Hover any timestamp in the chat gutter to see a tooltip with the full date the message was received (weekday, month, day, year, 12-hour time). Useful for 'when exactly was this sent?' without cluttering the chat row.",
          get = function()
              local p = Profile()
              return p and p.timestamps and p.timestamps.hoverTooltip ~= false or false
          end,
          set = function(_, v)
              local p = Profile()
              if p and p.timestamps then p.timestamps.hoverTooltip = v end
          end,
          disabled = function()
              local p = Profile()
              return not (p and p.timestamps and p.timestamps.enabled)
          end },

        -----------------------------------------------------------------
        -- Channel Names (Options only - chat-line bracket shortening)
        -----------------------------------------------------------------

        { key = "cnEnabled", label = "Shorten channel prefixes", section = "channelNm",
          type = "toggle", order = 10,
          desc = "Replace bracketed prefixes in chat lines with their short forms: [Guild] becomes [g], [Party Leader] becomes [pl], etc. The default mappings mirror what Prat / Chatter use. Hand-edit BazUIDB.profiles.<active>.Chat.channelNames.shortNames to customize.",
          get = function()
              local p = Profile()
              return p and p.channelNames and p.channelNames.enabled ~= false or false
          end,
          set = function(_, v)
              local p = Profile()
              if p and p.channelNames then p.channelNames.enabled = v end
              if addon.ChannelNames and addon.ChannelNames.Refresh then
                  addon.ChannelNames:Refresh()
              end
              ApplyAll()
          end },

        { key = "cnStripNumbers", label = "Strip channel numbers", section = "channelNm",
          type = "toggle", order = 11,
          desc = "Remove the numeric prefix and zone suffix from custom-channel brackets: [1. General - Stormwind] becomes [General], [5. Trade (Services) - City] becomes [Trade (Services)]. Independent of the short-prefixes toggle above.",
          get = function()
              local p = Profile()
              return p and p.channelNames and p.channelNames.stripChannelNumbers ~= false or false
          end,
          set = function(_, v)
              local p = Profile()
              if p and p.channelNames then p.channelNames.stripChannelNumbers = v end
              if addon.ChannelNames and addon.ChannelNames.Refresh then
                  addon.ChannelNames:Refresh()
              end
              ApplyAll()
          end },

        -----------------------------------------------------------------
        -- Layout (Edit Mode only - position nudge)
        -----------------------------------------------------------------

        { key = "_nudge", section = "layout", type = "nudge",
          order = 10, surfaces = { editMode = true } },
    },
}

addon.SettingsSpec = SPEC

-- Register at file load. The core loads before every module, so
-- RegisterSettingsSpec is safe to call directly here. The spec's get/set callbacks
-- are deferred (lazy) so they don't run until the consumers actually
-- read values - by then addon.db is populated.
if BazUI and BazUI.RegisterSettingsSpec then
    BazUI:RegisterSettingsSpec(addonName, SPEC)
end
