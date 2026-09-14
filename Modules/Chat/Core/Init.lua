-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat
-- Chat enhancements for the Baz Suite. Hooks into Blizzard's default
-- chat frames - never replaces them - so combat log, voice, hyperlink
-- protocols, BN whisper routing, ChatThrottle and every other piece
-- of Blizzard chat infrastructure keeps working untouched.
--
-- Each feature is its own self-contained module under Modules/. They
-- Core/Modules.lua wires them up at PLAYER_LOGIN.
---------------------------------------------------------------------------

-- Chat's private namespace. Every Chat file starts with
-- `local addon = BazUI.Chat`; addon.API is the table the old BazChat
-- global used to be (module registry, RefreshAll, copy dialog, ...).
local addonName = "Chat"
local addon = { API = {}, MODULE_NAME = addonName }
BazUI.Chat = addon
local BazChat = addon.API

addon.name    = addonName
addon.VERSION = BazUI.VERSION
addon.db      = nil   -- proxied by BazUI once profiles init

---------------------------------------------------------------------------
-- Defaults - one section per module, plus a master enabled toggle.
-- Modules read their own slice via addon.db.profile.<id> so the
-- structure here mirrors the layout of the settings page.
---------------------------------------------------------------------------

local DEFAULTS = {
    enabled = true,

    -- Persistent typed-message history. Up-arrow / down-arrow in any
    -- chat edit box cycles through these. Capped at MAX_LINES inside
    -- Replica/History.lua (50 lines today). Survives /reload and game
    -- restart since this lives in BazUIDB, not in the edit box's
    -- in-session list.
    typedHistory = {},

    -- Per-container geometry. Each tab is bound to a dock container
    -- via windows[idx].dockID; the dock container's position + size
    -- live here. "dock" is the canonical main dock; popped chat
    -- windows allocate their own entry on pop-out (key like "pop:N").
    docks = {
        dock = {
            pos    = nil,
            width  = 440,
            height = 120,
        },
    },

    -- Per-window appearance + behavior. The Settings page and the
    -- Edit Mode popup both bind to this block so they stay in sync
    -- via the shared DB. Chrome settings (alpha / scale / fade modes)
    -- are read from windows[1] as the canonical source so they apply
    -- uniformly across every chat window in the dock.
    --
    -- Field reference:
    --   dockID       container the tab lives in ("dock" or "pop:N")
    --   eventGroup   default channel preset for the tab
    --                ("GENERAL" / "GUILD" / "LOOT" / "LOG")
    --   alpha        chat text + scrollbar opacity (foreground)
    --   bgAlpha      NineSlice chrome panel opacity (background)
    --   scale        whole-frame UI scale multiplier
    --   scrollbarMode    "always" / "onscroll" / "never"
    --   bgMode           "always" / "onhover" / "never"
    --   tabsMode         "always" / "onhover" / "never"
    --   chromeFadeMode   "off" = bg + tabs independent; "always" /
    --                    "onhover" / "never" = both forced to match.
    --   tabsAlpha        max opacity the tab strip fades up to
    --   fading / fadeDuration / timeVisible
    --                    chat text fade after no new messages
    --   maxLines         scrollback buffer size
    --   indentedWordWrap second + later visual lines are indented to
    --                    the body's left edge, not the timestamp gutter
    --   messageSpacing   pixel gap applied via SMF:SetSpacing
    --   customFont       BazUI's own chat face (DorisPP) instead of
    --                    Blizzard's, at Blizzard's chat font size
    --   fontScale        multiplies that size, so the game's own chat
    --                    font-size option still leads
    windows = {
        [1] = {
            label            = "General",
            dockID           = "dock",
            eventGroup       = "GENERAL",
            alpha            = 1.0,
            bgAlpha          = 0.75,
            scale            = 1.0,
            scrollbarMode    = "always",
            bgMode           = "always",
            chromeFadeMode   = "always",
            tabsMode         = "always",
            tabsAlpha        = 1.0,
            fading           = true,
            fadeDuration     = 0.5,
            timeVisible      = 120,
            maxLines         = 500,
            indentedWordWrap = true,
            messageSpacing   = 3,
            customFont       = true,
            fontScale        = 1.0,
        },
        [2] = {
            label            = "Guild",
            dockID           = "dock",
            eventGroup       = "GUILD",
            alpha            = 1.0,
            scale            = 1.0,
            scrollbarMode    = "always",
            bgMode           = "always",
            chromeFadeMode   = "always",
            tabsMode         = "always",
            tabsAlpha        = 1.0,
            fading           = true,
            fadeDuration     = 0.5,
            timeVisible      = 120,
            maxLines         = 500,
            indentedWordWrap = true,
            messageSpacing   = 3,
        },
        -- Trade tab. Input box wires to the Trade channel directly
        -- when the player is in one (falls back to SAY otherwise).
        [3] = {
            label            = "Trade",
            dockID           = "dock",
            eventGroup       = "LOOT",
            alpha            = 1.0,
            scale            = 1.0,
            scrollbarMode    = "always",
            bgMode           = "always",
            chromeFadeMode   = "always",
            tabsMode         = "always",
            tabsAlpha        = 1.0,
            fading           = true,
            fadeDuration     = 0.5,
            timeVisible      = 120,
            maxLines         = 500,
            indentedWordWrap = true,
            messageSpacing   = 3,
        },
        -- Log tab. XP / honor / faction / skill / pet
        -- info. Read-only (no edit box).
        [4] = {
            label            = "Log",
            dockID           = "dock",
            eventGroup       = "LOG",
            alpha            = 1.0,
            scale            = 1.0,
            scrollbarMode    = "always",
            bgMode           = "always",
            chromeFadeMode   = "always",
            tabsMode         = "always",
            tabsAlpha        = 1.0,
            fading           = true,
            fadeDuration     = 0.5,
            timeVisible      = 120,
            maxLines         = 500,
            indentedWordWrap = true,
            messageSpacing   = 3,
        },
    },

    -- Module: copyChat
    -- Adds a small icon to each chat frame's tab area; clicking it
    -- opens BazUI:OpenCopyDialog with the visible chat lines pre-
    -- selected so the user can Ctrl+A / Ctrl+C without WoW's normal
    -- "chat is not selectable" limitation.
    copyChat = {
        enabled  = true,
        iconSize = 16,
    },

    -- Module: channelNames
    -- Hooks ChatFrame*:AddMessage and rewrites bracketed channel
    -- prefixes to short forms. Defaults mirror the conventional
    -- shortenings used by Prat / Chatter so users coming from those
    -- addons feel at home.
    channelNames = {
        enabled = true,
        shortNames = {
            GUILD                 = "g",
            OFFICER               = "o",
            PARTY                 = "p",
            PARTY_LEADER          = "pl",
            RAID                  = "r",
            RAID_LEADER           = "rl",
            RAID_WARNING          = "rw",
            INSTANCE_CHAT         = "i",
            INSTANCE_CHAT_LEADER  = "il",
            BATTLEGROUND          = "bg",
            BATTLEGROUND_LEADER   = "bgl",
            SAY                   = "s",
            YELL                  = "y",
            WHISPER               = "w",
            WHISPER_INFORM        = "to",
            EMOTE                 = "e",
        },
        -- Strip the numeric prefix from custom channels, so
        -- "[1. General]" becomes "[General]". Pure cosmetic.
        stripChannelNumbers = true,
    },

    -- Timestamps: "HH:MM:SS - message" gutter on each line. Format
    -- string is strftime-compatible so "%H:%M" (no seconds) works
    -- too. Separator is whatever character(s) the user picks - the
    -- renderer wraps it with single spaces on each side automatically,
    -- so "-" reads as " - ", "|" reads as " | ", etc. Color is the
    -- {r,g,b,a} for the timestamp + separator; the message body stays
    -- in its native chat color. Re-rendered on replay using each
    -- line's captured time so historic stamps match the original
    -- moment, not "now".
    timestamps = {
        enabled      = true,
        format       = "%I:%M %p",
        separator    = "-",
        color        = { 0.55, 0.55, 0.55, 1 },
        -- When true, hovering the gutter timestamp pops a GameTooltip
        -- with the full readable date (weekday, month, day, year,
        -- 12-hour time). Useful for "when exactly was this sent?"
        -- without cluttering the chat row with a long format.
        hoverTooltip = true,
    },
}

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

local core = BazUI:RegisterModule(addonName, {
    title         = "Chat",
    profiles      = true,
    defaults      = DEFAULTS,

    slash = { "/bazchat", "/bc" },
    commands = {
        copy = {
            desc    = "Copy the visible chat to a popup dialog",
            handler = function()
                if BazChat.OpenCopyForActiveFrame then
                    BazChat:OpenCopyForActiveFrame()
                end
            end,
        },
        font = {
            desc    = "Report whether the BazUI chat font is loaded and in use",
            handler = function()
                local W = addon.Window
                if not (W and W.FontStatus) then
                    addon.core:Print("Chat windows are not up yet.")
                    return
                end
                local s = W:FontStatus()
                addon.core:Print("Chat font:")
                print("  setting on:", s.setting)
                print("  file:", s.file)
                print("  client can load it:", s.loadable)
                print("  size scale:", s.scale)
                print("  in use now:", tostring(s.inUse), "at", tostring(s.inUseSize))
                print("  Blizzard's:", tostring(s.blizzard))
                if s.setting and not s.loadable then
                    print("  |cffffd700The client reads fonts at startup. Quit to the desktop and start the game again; a /reload is not enough.|r")
                end
            end,
        },

        toggle = {
            desc    = "Master toggle for all BazUI Chat features",
            handler = function()
                local new = not addon.core:GetSetting("enabled")
                addon.core:SetSetting("enabled", new)
                addon.core:Print("BazUIChat is " .. (new and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
            end,
        },

        reset = {
            desc    = "Wipe ALL BazUI Chat saved settings and reload UI",
            handler = function()
                if BazUIDB and BazUIDB.profiles then
                    for _, p in pairs(BazUIDB.profiles) do
                        p.Chat = nil
                    end
                end
                if addon.core then
                    addon.core:Print(
                        "|cffffd100saved settings wiped. Reloading...|r")
                end
                C_Timer.After(0.1, ReloadUI)
            end,
        },

        clear = {
            desc    = "Clear the active chat window (and its persisted history)",
            handler = function()
                local idx = (addon.Window and addon.Window.GetActiveWindowIdx
                             and addon.Window:GetActiveWindowIdx()) or 1
                local f   = addon.Window and addon.Window:Get(idx)
                if f and f.Clear then f:Clear() end
                local p = (addon.db and addon.db.profile)
                    or (addon.core and addon.core.db and addon.core.db.profile)
                if p and p.windows and p.windows[idx] then
                    p.windows[idx].history = nil
                end
            end,
        },

        restoredefaults = {
            desc    = "Restore deleted default tabs (Guild/Trade/Log) without resetting other tabs",
            handler = function()
                local p = (addon.db and addon.db.profile)
                    or (addon.core and addon.core.db and addon.core.db.profile)
                if not p then return end
                local n = 0
                if p.deletedCanonicals then
                    for k in pairs(p.deletedCanonicals) do n = n + 1 end
                end
                p.deletedCanonicals = nil
                if addon.core then
                    addon.core:Print(string.format(
                        "|cffffd100Cleared %d dead-canonical entries. Reloading...|r", n))
                end
                C_Timer.After(0.1, ReloadUI)
            end,
        },

        lock = {
            desc    = "Lock the active chat window (disables drag/resize outside Edit Mode)",
            handler = function()
                local W = addon.Window
                if not (W and W.SetContainerLocked) then return end
                local id = W.activeContainer or "dock"
                W:SetContainerLocked(id, true)
                if addon.core then
                    addon.core:Print(string.format(
                        "Locked chat window |cffffd100%s|r", id))
                end
            end,
        },

        unlock = {
            desc    = "Unlock the active chat window (drag/resize without Edit Mode)",
            handler = function()
                local W = addon.Window
                if not (W and W.SetContainerLocked) then return end
                local id = W.activeContainer or "dock"
                W:SetContainerLocked(id, false)
                if addon.core then
                    addon.core:Print(string.format(
                        "Unlocked chat window |cffffd100%s|r - drag the chat to move, use the bottom-right grabber to resize",
                        id))
                end
            end,
        },

        histcheck = {
            desc    = "Diagnose typed-message history state",
            handler = function()
                if not addon.core then return end
                local p = (addon.db and addon.db.profile)
                    or (addon.core and addon.core.db and addon.core.db.profile)
                if not p then
                    addon.core:Print("|cffff8800histcheck:|r profile not available")
                    return
                end
                local list = p.typedHistory
                local n = list and #list or 0
                addon.core:Print(string.format(
                    "|cffffd100histcheck:|r typedHistory has %d entries", n))
                if n > 0 then
                    -- Print last 3 entries (truncated to 50 chars). Safe
                    -- because these are messages the player typed
                    -- themselves - never secret strings.
                    for i = math.max(1, n - 2), n do
                        local s = BazUI:TruncateText(list[i] or "", 50)
                        addon.core:Print(string.format("  [%d] %s", i, s))
                    end
                end
                -- Active editbox state.
                local tid = (addon.Window and addon.Window.GetActiveWindowIdx
                             and addon.Window:GetActiveWindowIdx()) or 1
                local f   = addon.Window and addon.Window:Get(tid)
                if f and f.editBox then
                    local altMode = f.editBox.GetAltArrowKeyMode
                        and f.editBox:GetAltArrowKeyMode() or "?"
                    local hasFocus = f.editBox.HasFocus
                        and f.editBox:HasFocus() or false
                    local nativeCount = f.editBox.GetHistoryLines
                        and f.editBox:GetHistoryLines() or "?"
                    addon.core:Print(string.format(
                        "  editBox tab=%d altArrowKeyMode=%s focused=%s nativeHistCount=%s",
                        tid, tostring(altMode), tostring(hasFocus),
                        tostring(nativeCount)))
                end
            end,
        },

    },

    minimap = {
        label = "Chat",
        icon  = "Interface\\AddOns\\BazUI\\Modules\\Chat\\Assets\\chat_icon.tga",
    },

    onReady = function(self)
        addon.db   = self.db
        addon.core = self           -- expose BazUI addon obj for modules
    end,
})

-- Stash the module object early so other Chat files can reach
-- :GetSetting / :Print / :db before onReady fires.
addon.core = core

-- Top-level "/clearchat" and "/cc" slash commands as shortcuts to
-- "/bc clear". Most users expect a one-word slash for clearing chat.
-- We avoid claiming "/clear" because that's commonly used by other
-- addons. The handler reuses the same logic as the /bc clear sub-cmd.
local function ClearActiveTab()
    local idx = (addon.Window and addon.Window.GetActiveWindowIdx
                 and addon.Window:GetActiveWindowIdx()) or 1
    local f   = addon.Window and addon.Window:Get(idx)
    if f and f.Clear then f:Clear() end
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    if p and p.windows and p.windows[idx] then
        p.windows[idx].history = nil
    end
end
SLASH_BAZCHATCLEAR1 = "/clearchat"
SLASH_BAZCHATCLEAR2 = "/cc"
SlashCmdList["BAZCHATCLEAR"] = ClearActiveTab
