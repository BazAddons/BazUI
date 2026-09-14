---------------------------------------------------------------------------
-- BazChat Replica: Channels (per-tab routing + right-click popup)
--
-- Owns the categorized channel list used by:
--   * Per-tab event subscription in Window:Create
--   * Right-click channel popup (built later in this module)
--   * Tabs managed list page in Options (built in Replica/TabsPage.lua)
--
-- A "category" is a user-facing checkbox: one label, one color, and
-- one or more underlying CHAT_MSG_* events. Toggling a category
-- registers/unregisters that event set on the tab's chat frame.
--
-- Public API (on addon.Channels):
--   :EventsFor(channels)     -- channels table -> array of CHAT_MSG_* names
--   :Subscribe(f, idx)       -- (re-)wire f's event registration from DB
--   :DefaultsFor(preset)     -- seed channels{} from a preset name
--   :ShowPopup(tab, idx)     -- right-click popup (added in next step)
--   .CATEGORIES              -- ordered array of category defs (read-only)
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

local Channels = {}
addon.Channels = Channels

---------------------------------------------------------------------------
-- Category definitions
--
-- Order here drives the popup order (matches Blizzard's classic Chat
-- Settings panel layout: Say/Emote/Yell, Guild, Whispers, Group/Raid,
-- Instance/BG, Channels, System events).
--
-- `color` is a ChatTypeInfo key (ChatTypeInfo[key] gives r/g/b at
-- runtime). When a key isn't in ChatTypeInfo we fall back to white.
-- `events` is the full set of CHAT_MSG_* (and a few non-CHAT_MSG)
-- events that belong to this category. Toggling the category flips
-- the entire list on/off for the tab.
---------------------------------------------------------------------------

local CATEGORIES = {
    { key = "say",            label = "Say",                color = "SAY",
      events = { "CHAT_MSG_SAY", "CHAT_MSG_MONSTER_SAY" } },

    { key = "emote",          label = "Emote",              color = "EMOTE",
      events = { "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
                 "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_MONSTER_BOSS_EMOTE",
                 "CHAT_MSG_RAID_BOSS_EMOTE" } },

    { key = "yell",           label = "Yell",               color = "YELL",
      events = { "CHAT_MSG_YELL", "CHAT_MSG_MONSTER_YELL" } },

    -- GUILD_MOTD belongs to the GUILD ChatTypeGroup in Blizzard's
    -- ChatTypeInfoConstants.lua. The mixin's SystemEventHandler
    -- formats it as a guild-colored "Guild Message of the Day: ..."
    -- line. Without this in the guild category, the MOTD wouldn't
    -- appear on tabs that show guild chat. Live MOTD changes fire
    -- the GUILD_MOTD event; the /reload + relog case is handled by
    -- a manual fetch (see addon.Channels:DisplayInitialMOTD) since
    -- the live event has already been dispatched before our chat
    -- frames register for it.
    { key = "guild",          label = "Guild Chat",         color = "GUILD",
      events = { "CHAT_MSG_GUILD", "GUILD_MOTD" } },

    { key = "officer",        label = "Officer Chat",       color = "OFFICER",
      events = { "CHAT_MSG_OFFICER" } },

    { key = "guildAchieve",   label = "Guild Achievements", color = "GUILD_ACHIEVEMENT",
      events = { "CHAT_MSG_GUILD_ACHIEVEMENT" } },

    { key = "achievement",    label = "Achievements",       color = "ACHIEVEMENT",
      events = { "CHAT_MSG_ACHIEVEMENT" } },

    { key = "whisper",        label = "Whispers",           color = "WHISPER",
      events = { "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
                 "CHAT_MSG_AFK", "CHAT_MSG_DND",
                 "CHAT_MSG_RAID_BOSS_WHISPER", "CHAT_MSG_MONSTER_WHISPER" } },

    { key = "bnWhisper",      label = "Battle.net Whispers", color = "BN_WHISPER",
      events = { "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
                 "CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE",
                 "CHAT_MSG_BN_INLINE_TOAST_ALERT",
                 "CHAT_MSG_BN_INLINE_TOAST_BROADCAST",
                 "CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM" } },

    { key = "party",          label = "Party",              color = "PARTY",
      events = { "CHAT_MSG_PARTY", "CHAT_MSG_MONSTER_PARTY" } },

    { key = "partyLeader",    label = "Party Leader",       color = "PARTY_LEADER",
      events = { "CHAT_MSG_PARTY_LEADER" } },

    { key = "raid",           label = "Raid",               color = "RAID",
      events = { "CHAT_MSG_RAID" } },

    { key = "raidLeader",     label = "Raid Leader",        color = "RAID_LEADER",
      events = { "CHAT_MSG_RAID_LEADER" } },

    { key = "raidWarning",    label = "Raid Warning",       color = "RAID_WARNING",
      events = { "CHAT_MSG_RAID_WARNING" } },

    { key = "instance",       label = "Instance",           color = "INSTANCE_CHAT",
      events = { "CHAT_MSG_INSTANCE_CHAT" } },

    { key = "instanceLeader", label = "Instance Leader",    color = "INSTANCE_CHAT_LEADER",
      events = { "CHAT_MSG_INSTANCE_CHAT_LEADER" } },

    { key = "battleground",   label = "Battleground",       color = "BATTLEGROUND",
      events = { "CHAT_MSG_BATTLEGROUND",
                 "CHAT_MSG_BG_SYSTEM_ALLIANCE",
                 "CHAT_MSG_BG_SYSTEM_HORDE",
                 "CHAT_MSG_BG_SYSTEM_NEUTRAL" } },

    { key = "bgLeader",       label = "Battleground Leader", color = "BATTLEGROUND_LEADER",
      events = { "CHAT_MSG_BATTLEGROUND_LEADER" } },

    -- "Channels" is no longer one master category. Currently-joined
    -- channels (General, Trade, LocalDefense, etc.) appear as their
    -- own rows in the popup, and each one toggles independently. The
    -- per-channel rows are appended dynamically below the static
    -- CATEGORIES list - see BuildPopupSpecs / EventsFor below.
    --
    -- Why split: the ChatFrameMixin filters channel notices and
    -- messages against f.channelList. With one master toggle and an
    -- empty channelList, every "Joined/Left/Changed Channel: X" notice
    -- silently drops. Per-channel toggles let us populate channelList
    -- from the user's exact picks - no missed notices, and the user
    -- can mute LocalDefense (etc.) without losing General + Trade.

    -- System messages. CHAT_MSG_SYSTEM covers most "you have entered..." /
    -- "you receive..." spam. The non-CHAT_MSG events (TIME_PLAYED_MSG,
    -- PLAYER_LEVEL_CHANGED, etc.) are dispatched via the
    -- ChatFrameMixin's SystemEventHandler instead of MessageEventHandler;
    -- we still need to register them on the chat frame for the mixin
    -- to ever see them. GUILD_MOTD is intentionally NOT in this
    -- category - it belongs to "guild" (matches Blizzard's grouping).
    { key = "system",         label = "System",             color = "SYSTEM",
      events = { "CHAT_MSG_SYSTEM", "CHAT_MSG_FILTERED",
                 "CHAT_MSG_RESTRICTED", "CHAT_MSG_IGNORED",
                 "CAUTIONARY_CHAT_MESSAGE",
                 -- System events handled by ChatFrameMixin:SystemEventHandler:
                 "TIME_PLAYED_MSG",          -- "/played" + login playtime
                 "PLAYER_LEVEL_CHANGED",     -- Ding! you reached level X
                 "UPDATE_INSTANCE_INFO",     -- raid lockouts
                 "CHAT_SERVER_DISCONNECTED",
                 "CHAT_SERVER_RECONNECTED",
                 "BN_CONNECTED",
                 "BN_DISCONNECTED",
                 "CHAT_REGIONAL_STATUS_CHANGED",
                 "CHAT_REGIONAL_SEND_FAILED",
                 "NOTIFY_CHAT_SUPPRESSED",
                 "PLAYER_REPORT_SUBMITTED",
      } },

    { key = "errors",         label = "Errors",             color = "SYSTEM",
      events = { "UI_ERROR_MESSAGE", "UI_INFO_MESSAGE" } },

    { key = "combat",         label = "Combat (XP / Honor / Faction)",
                                                            color = "COMBAT_FACTION_CHANGE",
      events = { "CHAT_MSG_COMBAT_FACTION_CHANGE",
                 "CHAT_MSG_COMBAT_GUILD_XP_GAIN",
                 "CHAT_MSG_COMBAT_HONOR_GAIN",
                 "CHAT_MSG_COMBAT_MISC_INFO",
                 "CHAT_MSG_COMBAT_XP_GAIN" } },

    { key = "loot",           label = "Loot",               color = "LOOT",
      events = { "CHAT_MSG_LOOT", "CHAT_MSG_MONEY",
                 "CHAT_MSG_CURRENCY", "CHAT_MSG_OPENING" } },

    { key = "skill",          label = "Skill",              color = "SKILL",
      events = { "CHAT_MSG_SKILL", "CHAT_MSG_TRADESKILLS",
                 "CHAT_MSG_PET_INFO" } },

    { key = "targetIcons",    label = "Target Markers",     color = "SYSTEM",
      events = { "CHAT_MSG_TARGETICONS" } },
}

Channels.CATEGORIES = CATEGORIES

---------------------------------------------------------------------------
-- Per-channel helpers
--
-- Currently-joined chat channels (General, Trade, LocalDefense, etc.)
-- are listed in the popup as their own checkbox rows. State is saved
-- under ws.channels["channel:<base>"] = true, where <base> is the
-- channel's zone-independent name (we strip the " - <Zone>" suffix
-- so the toggle survives zone crossings - "Trade - Stormwind" and
-- "Trade - Orgrimmar" both share the "Trade" base).
---------------------------------------------------------------------------

-- All chat events tied to the channel system. Registered if ANY
-- channel:* key is set - the mixin's filter then routes per-channel
-- via f.channelList (populated in :RefreshChannelList below).
local CHANNEL_EVENTS = {
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_CHANNEL_NOTICE",
    "CHAT_MSG_CHANNEL_NOTICE_USER",
    "CHAT_MSG_CHANNEL_LIST",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
}

-- Strip the "[ - <Zone>]" suffix off a channel name, leaving the
-- stable base name. "Trade - Stormwind" -> "Trade".
-- "Trade (Services) - City" -> "Trade (Services)". "World" -> "World".
--
-- v191 bug: this used find(" %- ", 1, true) which is plain-mode +
-- literal "%-". Plain mode treats every char literally so it was
-- looking for the four-char string " %- " (space-percent-dash-space)
-- which never appears in real channel names. v192 drops the % since
-- plain mode means the - is already literal.
local function ChannelBaseName(fullName)
    if not fullName or fullName == "" then return fullName end
    local sep = fullName:find(" - ", 1, true)
    if sep then return fullName:sub(1, sep - 1) end
    return fullName
end

-- Returns an array of { id, name, base } for every currently-joined
-- channel. Empty if GetChannelList isn't available yet (early boot).
local function GetCurrentChannels()
    local out = {}
    if not GetChannelList then return out end
    local raw = { GetChannelList() }
    for i = 1, #raw, 3 do
        local id, name = raw[i], raw[i + 1]
        if id and id > 0 and name and name ~= "" then
            out[#out + 1] = { id = id, name = name, base = ChannelBaseName(name) }
        end
    end
    return out
end

local function HasAnyChannelSelected(channels)
    if not channels then return false end
    for k, v in pairs(channels) do
        if v and type(k) == "string" and k:sub(1, 8) == "channel:" then
            return true
        end
    end
    return false
end

Channels.ChannelBaseName    = ChannelBaseName
Channels.GetCurrentChannels = GetCurrentChannels

---------------------------------------------------------------------------
-- Default channel presets, applied to a freshly grafted canonical tab
-- in Window:CreateAll. Preset names match Window.lua's CANONICAL_WINDOWS
-- entries: GENERAL / GUILD / LOOT / LOG.
---------------------------------------------------------------------------

local PRESETS = {
    GENERAL = {
        say=true, emote=true, yell=true, whisper=true, bnWhisper=true,
        party=true, partyLeader=true, raid=true, raidLeader=true,
        raidWarning=true, instance=true, instanceLeader=true,
        battleground=true, bgLeader=true, achievement=true,
        channel=true, system=true, errors=true, targetIcons=true,
    },
    GUILD = {
        guild=true, officer=true, guildAchieve=true,
    },
    LOOT  = {   -- Trade tab; loot/money + the channel events that
                -- carry the actual /trade messages
        loot=true, channel=true,
    },
    LOG   = {
        combat=true, skill=true, achievement=true,
    },
    -- Default for a brand-new user-created tab: just Say (minimum
    -- viable; user toggles more on after creation).
    BLANK = {
        say=true,
    },
}

function Channels:DefaultsFor(preset)
    local p = PRESETS[preset] or PRESETS.BLANK
    local out = {}
    for k, v in pairs(p) do out[k] = v end
    return out
end

---------------------------------------------------------------------------
-- :EventsFor — channels table -> deduped array of CHAT_MSG_* names.
---------------------------------------------------------------------------

function Channels:EventsFor(channels)
    if not channels then return {} end
    local out, seen = {}, {}
    for _, cat in ipairs(CATEGORIES) do
        if channels[cat.key] then
            for _, evt in ipairs(cat.events) do
                if not seen[evt] then
                    seen[evt] = true
                    out[#out + 1] = evt
                end
            end
        end
    end
    -- Channel events are added once if ANY channel:<base> key is set.
    -- Per-channel filtering happens via f.channelList in Subscribe;
    -- this just makes sure CHAT_MSG_CHANNEL_* events are subscribed at
    -- all when the user has picked any individual channel.
    if HasAnyChannelSelected(channels) then
        for _, evt in ipairs(CHANNEL_EVENTS) do
            if not seen[evt] then
                seen[evt] = true
                out[#out + 1] = evt
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- :Subscribe — (re-)register a chat frame's events from its channels.
--
-- Called once during Window:Create AND any time the user toggles a
-- channel (the popup setter and the options page setter both call
-- this so the tab's event subscription stays in sync with the DB).
--
-- We UnregisterAllEvents and re-register the current set. The chat
-- frame doesn't subscribe to anything outside the categories list,
-- so this is safe.
---------------------------------------------------------------------------

local function GetWindowDB(idx)
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    return p and p.windows and p.windows[idx] or nil
end

-- Always-on events: registered on every chat frame regardless of the
-- per-tab category subscription. Required so the ChatFrameMixin's
-- ConfigEventHandler can react to live chat-config changes (color
-- pickers, per-class name coloring, etc.) - without these registered,
-- the mixin never runs UpdateColorByID and the channel colors on our
-- bars / messages stay stale until /reload.
local ALWAYS_ON_EVENTS = {
    "UPDATE_CHAT_COLOR",                -- user changed a channel color
    "UPDATE_CHAT_COLOR_NAME_BY_CLASS",  -- toggled "color names by class"
    -- Blizzard's ConfigEventHandler sets self.defaultLanguage /
    -- alternativeDefaultLanguage on these. They must be written by
    -- Blizzard (secure) rather than by us: the message formatter reads
    -- them before its protected work, and an addon-written field would
    -- taint the dispatch. Without them SAY/YELL would show a language tag.
    "PLAYER_ENTERING_WORLD",
    "NEUTRAL_FACTION_SELECT_RESULT",
    "ALTERNATIVE_DEFAULT_LANGUAGE_CHANGED",
}

function Channels:Subscribe(f, idx)
    if not f then return end
    local ws = GetWindowDB(idx)
    if not ws or not ws.channels then return end

    if f.UnregisterAllEvents then f:UnregisterAllEvents() end
    for _, evt in ipairs(self:EventsFor(ws.channels)) do
        pcall(f.RegisterEvent, f, evt)
    end
    -- Re-register the always-on events after the wipe so live chat-
    -- config changes propagate to our bars and message body colors.
    for _, evt in ipairs(ALWAYS_ON_EVENTS) do
        pcall(f.RegisterEvent, f, evt)
    end

    -- Populate f.channelList from the user's per-channel selections so
    -- the ChatFrameMixin's notice/message filter passes for those
    -- channels. Without this, every "Joined/Left/Changed Channel: X"
    -- silently drops because the mixin's tContains(channelList, name)
    -- check fails on an empty list.
    self:RefreshChannelList(f, ws)
end

---------------------------------------------------------------------------
-- :RefreshChannelList — re-populate f.channelList from the user's
-- per-channel selections.
--
-- Called from :Subscribe AND from Window.lua's zone watcher whenever
-- the player joins / leaves a channel or crosses a zone (channel names
-- carry zone suffixes - "Trade - Stormwind" vs "Trade - Orgrimmar" -
-- so the full name in channelList changes even when the toggle stays
-- on the same base name).
--
-- The mixin reads channelList by full name. We map base -> full name
-- by walking GetChannelList() and keeping any whose base is selected.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- :DisplayInitialMOTD — show the Guild MOTD on /reload or relog.
--
-- The GUILD_MOTD event fires during initial PLAYER_ENTERING_WORLD,
-- BEFORE our addon loads and creates chat frames. By the time we
-- register for the event the original dispatch is gone - so we miss
-- it on every /reload. Live MOTD changes (officer typing /gmotd) DO
-- still fire the event, which our subscribed frame catches.
--
-- Fix: after Subscribe, call ChatFrameUtil.DisplayGMOTD with the
-- cached MOTD from C_GuildInfo.GetMOTD(). Mirrors the recovery path
-- Blizzard uses inside ChatFrameMixin:ConfigEventHandler when it
-- handles UPDATE_CHAT_WINDOWS for late-registered frames. May need
-- to defer if GetMOTD() returns "" (guild data still loading); the
-- live GUILD_MOTD event will fire when ready and the chat frame
-- catches it via the normal mixin path, so deferring isn't strictly
-- required - we just attempt now and let the live event handle the
-- async case if needed.
-- Module-scoped MOTD listener. Created once, runs through the session
-- until it successfully displays the cached/initial Guild MOTD on
-- window 1, then tears itself down. Listens for three events to cover
-- cold login, /reload, and zone changes:
--   * GUILD_MOTD            - server pushes the MOTD (cold login or
--                             /gmotd change). arg1 is the text.
--   * PLAYER_GUILD_UPDATE   - guild membership data finalised; we can
--                             re-fetch C_GuildInfo.GetMOTD().
--   * PLAYER_ENTERING_WORLD - belt-and-braces fallback in case neither
--                             of the above fires (e.g. silent retail
--                             builds where the GUILD_MOTD event isn't
--                             dispatched on a /reload that already has
--                             warm cache).
--
-- Resolves window 1 lazily inside the event handler so the listener
-- can outlast Window:CreateAll if the events fire early.
--
-- Frame is named + global so we reuse the same instance across /reload.
-- Without this, the local variable on file-scope reset to nil on each
-- /reload, we'd CreateFrame a new listener every time, and the OLD
-- listener from the previous session - which is still registered for
-- GUILD_MOTD because frames persist for the session even after their
-- addon Lua state resets - kept firing alongside the new one. Result
-- before this fix: MOTD rendered TWICE on the next /reload (once from
-- each generation of listener), three times after two /reloads, etc.
local LISTENER_NAME = "BazUIChatGuildMOTDListener"
local motdListener = _G[LISTENER_NAME] or CreateFrame("Frame", LISTENER_NAME)
motdListener:UnregisterAllEvents()
motdListener:RegisterEvent("GUILD_MOTD")
motdListener:RegisterEvent("GUILD_ROSTER_UPDATE")
motdListener:RegisterEvent("PLAYER_GUILD_UPDATE")
motdListener:RegisterEvent("PLAYER_ENTERING_WORLD")
motdListener._displayed = false

local function RenderMOTDOnFrame(f, text)
    if not f or not f.AddMessage then return false end
    if not text or text == "" then return false end
    local info = ChatTypeInfo and ChatTypeInfo["GUILD"]
    local r = (info and info.r) or 0.25
    local g = (info and info.g) or 1.00
    local b = (info and info.b) or 0.25
    local template = _G.GUILD_MOTD_TEMPLATE or "Guild Message of the Day: %s"
    f:AddMessage(string.format(template, text), r, g, b)
    return true
end

local function RenderMOTDOnWindow1(text)
    local f = addon.Window and addon.Window.Get and addon.Window:Get(1)
    return RenderMOTDOnFrame(f, text)
end

motdListener:SetScript("OnEvent", function(self, event, arg1)
    if self._displayed then return end

    local motd
    if event == "GUILD_MOTD" then
        motd = arg1
    else
        if IsInGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GetMOTD then
            motd = C_GuildInfo.GetMOTD()
        end
    end

    if RenderMOTDOnWindow1(motd) then
        self._displayed = true
        self:UnregisterAllEvents()
    end
end)

-- Initial MOTD render. Called from Window:CreateAll's tail after all
-- windows are registered, and again as a backwards-compat shim from
-- Window:Create.
--
-- The hard part is /reload: GUILD_MOTD doesn't re-fire (server only
-- pushes on changes), and GetMOTD() may return "" for a beat or two
-- while guild data settles even though the cache is technically warm.
-- So we:
--   1) Try once immediately (works for the common case).
--   2) Kick C_GuildInfo.GuildRoster() to ask the server for a refresh,
--      which makes it dispatch GUILD_ROSTER_UPDATE / GUILD_MOTD that
--      our listener catches.
--   3) Poll every 0.5s for ~10s as a belt-and-suspenders fallback in
--      case neither event fires (some classic-era / private server
--      builds drop GUILD_MOTD entirely on /reload).
-- All three paths share `_displayed`, so whichever wins first stops
-- the others.
function Channels:TryRenderInitialMOTD()
    if motdListener._displayed then return end
    if not (C_GuildInfo and C_GuildInfo.GetMOTD) then return end

    local function attempt()
        if motdListener._displayed then return true end
        local motd = C_GuildInfo.GetMOTD()
        if RenderMOTDOnWindow1(motd) then
            motdListener._displayed = true
            motdListener:UnregisterAllEvents()
            return true
        end
        return false
    end

    -- Immediate try. Done if it lands.
    if attempt() then return end

    -- Ask the server to re-send guild data. The reply triggers
    -- GUILD_ROSTER_UPDATE (and on cold login, GUILD_MOTD), both of
    -- which our listener handles.
    if C_GuildInfo.GuildRoster then
        pcall(C_GuildInfo.GuildRoster)
    end

    -- Polling fallback: try every 0.5s for up to 10s. Stops as soon
    -- as anything else (event listener, another retry) flips _displayed.
    local tries = 0
    local function retry()
        if motdListener._displayed then return end
        tries = tries + 1
        if attempt() then return end
        if tries < 20 then
            C_Timer.After(0.5, retry)
        end
    end
    C_Timer.After(0.5, retry)
end

-- Backwards-compat shim for the old call site inside Window:Create.
-- The real entry point is now Window:CreateAll's tail.
function Channels:DisplayInitialMOTD(_f, _ws)
    self:TryRenderInitialMOTD()
end

function Channels:RefreshChannelList(f, ws)
    if not f then return end
    if not ws then ws = GetWindowDB(f._bcWindowIndex) end
    if not ws or not ws.channels then return end
    f.channelList     = f.channelList     or {}
    f.zoneChannelList = f.zoneChannelList or {}
    wipe(f.channelList)
    wipe(f.zoneChannelList)
    for _, ch in ipairs(GetCurrentChannels()) do
        if ws.channels["channel:" .. ch.base] then
            f.channelList[#f.channelList + 1]     = ch.name
            f.zoneChannelList[#f.zoneChannelList + 1] = false
        end
    end
end

---------------------------------------------------------------------------
-- :InstallFilters — register global chat filters
--
-- CHAT_MSG_TRADESKILLS and CHAT_MSG_OPENING are proximity broadcasts
-- now: every nearby player's crafts/herb-pickups land in your chat by
-- default. That floods the Loot tab in any populated zone with stuff
-- like "Minphoria creates Bright Linen Bolt" repeated ad nauseam.
--
-- Default chat addons like Chatinator silently filter these to show
-- ONLY the local player's own crafts. We do the same. The filter runs
-- once globally and suppresses messages whose sender isn't the player.
--
-- Called once from Replica:Start.
---------------------------------------------------------------------------

function Channels:InstallFilters()
    if self._filtersInstalled then return end
    self._filtersInstalled = true

    -- KEY FINDING from v180 diag: CHAT_MSG_TRADESKILLS/OPENING have an
    -- EMPTY sender field for proximity broadcasts of OTHER players'
    -- crafting. The player name is embedded in the message text:
    --   * Your own:           "You create %s." (no s on "create")
    --   * Others same-realm:  "Yaria creates %s."
    --   * Others cross-realm: "Yaria-Malfurion creates %s."
    --
    -- The reliable distinction is the verb: "creates" (with s) for
    -- third-person broadcasts vs "create" (no s) for first-person.
    -- v181 only matched the cross-realm hyphen pattern so same-realm
    -- crafts kept leaking through. v183 matches "%S+ creates " which
    -- catches both same-realm "Name creates" and cross-realm
    -- "Name-Realm creates" without misfiring on "You create".
    --
    -- v225: secret-string guard. If the engine has flagged this msg
    -- (cross-realm broadcasts in some contexts produce protected
    -- strings), pattern-matching it would error / taint the dispatch
    -- context. pcall a probe; if it errors, return false (let the
    -- message through unfiltered) instead of poisoning Blizzard's
    -- secure follow-on code in MessageEventHandler.
    local function suppressOthers(_, _, msg)
        if type(msg) ~= "string" then return false end
        local probeOk = pcall(function() return msg == "" end)
        if not probeOk then return false end
        if msg:match("^%S+ creates ") then
            return true   -- third-person "X creates Y" -> not us
        end
        return false
    end

    local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
        or ChatFrame_AddMessageEventFilter
    if not addFilter then return end

    addFilter("CHAT_MSG_TRADESKILLS", suppressOthers)
    addFilter("CHAT_MSG_OPENING",     suppressOthers)
end

---------------------------------------------------------------------------
-- Right-click channel popup
--
-- Mimics Blizzard's classic Chat Settings panel: a vertical column of
-- color-coded checkboxes anchored below the right-clicked tab. Click
-- a checkbox -> the tab's channels{} flips that key + re-subscribes
-- the chat frame's events live (no /reload needed).
---------------------------------------------------------------------------

-- Two-column channel grid. Width and column geometry derived from
-- POPUP_WIDTH so changing the popup width auto-rebalances columns.
local POPUP_WIDTH    = 440
local NUM_COLS       = 2
local COL_GAP        = 18
local ROW_HEIGHT     = 22
local HEADER_HEIGHT  = 36
local FOOTER_HEIGHT  = 12
local LEFT_PAD       = 14
local NAME_BLOCK_H   = 36   -- "Name" label + EditBox
local DIVIDER_H      = 14
local DELETE_BLOCK_H = 36

local function ColWidth()
    return (POPUP_WIDTH - LEFT_PAD * 2 - COL_GAP * (NUM_COLS - 1)) / NUM_COLS
end

-- Delete-tab confirmation now uses BazUI:Confirm (native popup
-- primitive that matches the rest of the BazUI UI - same fonts,
-- buttons, backdrop). Replaces the old StaticPopupDialogs entry.

-- Read a (r, g, b) tuple from ChatTypeInfo for a given key. Falls back
-- to white when ChatTypeInfo doesn't have an entry. ChatTypeInfo is a
-- standard Blizzard global populated at login.
local function ColorFor(colorKey)
    if ChatTypeInfo and colorKey and ChatTypeInfo[colorKey] then
        local c = ChatTypeInfo[colorKey]
        return c.r or 1, c.g or 1, c.b or 1
    end
    return 1, 1, 1
end

-- Build (or reuse) the singleton popup frame. Allocated once on first
-- ShowPopup; subsequent shows just refresh its title + checkboxes.
local function EnsurePopup()
    if Channels._popup then return Channels._popup end

    local popup = CreateFrame("Frame", "BazUIChatChannelPopup", UIParent,
        "BackdropTemplate")
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    -- Visual size only - everything inside (backdrop, title, rows) scales
    -- proportionally. 0.85 reads as "compact" without sacrificing
    -- readability; matches the 0.8 tab strip scale closely enough that
    -- the popup feels visually attached to the tab.
    popup:SetScale(0.85)
    BazUI.Skin.Theme.ApplyFlatPanel(popup)
    popup:EnableMouse(true)
    popup:Hide()

    -- Title (gold, top-left). Refreshed per-show to the tab's name.
    local title = BazUI.Skin.Theme.FontString(popup, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", LEFT_PAD, -10)
    title:SetTextColor(1, 0.82, 0)
    popup.title = title

    -- Close button (top-right).
    local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() popup:Hide() end)

    -- "Name" label + rename EditBox below the title. Enter saves;
    -- Escape reverts. Renaming updates the tab button live and
    -- refreshes the BazUI Tabs options page if open.
    local nameLabel = BazUI.Skin.Theme.FontString(popup, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", LEFT_PAD, -HEADER_HEIGHT)
    nameLabel:SetText("Name")
    nameLabel:SetTextColor(0.82, 0.82, 0.82)

    local edit = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    edit:SetSize(POPUP_WIDTH - LEFT_PAD * 2 - 50, 20)
    edit:SetPoint("TOPLEFT", nameLabel, "TOPRIGHT", 8, 4)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEnterPressed", function(self)
        local newLabel = self:GetText()
        local idx = popup.tabIdx
        if not idx then return end
        local p = (addon.db and addon.db.profile)
            or (addon.core and addon.core.db and addon.core.db.profile)
        local ws = p and p.windows and p.windows[idx]
        if ws and newLabel and newLabel ~= "" then
            ws.label = newLabel
            -- Refresh the tab button label. Tab may live on the main
            -- dock's strip or on a popped container's strip; GetTabFor
            -- scans every dock instance.
            if addon.Tabs and addon.Tabs.GetTabFor then
                local tab = addon.Tabs:GetTabFor(idx)
                if tab and tab.Init then tab:Init(idx, newLabel) end
            end
            -- Refresh options page if it's open.
            if BazUI.RefreshOptions then
                BazUI:RefreshOptions("BazUIChat-Tabs")
            end
            popup.title:SetText(newLabel)
        end
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        local idx = popup.tabIdx
        local p = (addon.db and addon.db.profile)
            or (addon.core and addon.core.db and addon.core.db.profile)
        local ws = p and p.windows and p.windows[idx]
        self:SetText(ws and ws.label or "")
    end)
    popup.nameEdit = edit

    -- Delete button (anchored to the bottom of the popup at show-time
    -- since the popup height varies with the channel count). Disabled
    -- for General (idx 1) which owns the DEFAULT_CHAT_FRAME claim.
    local del = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    del:SetSize(POPUP_WIDTH - LEFT_PAD * 2, 24)
    del:SetText("Delete Tab")
    del:SetScript("OnClick", function()
        if not popup.tabIdx or popup.tabIdx == 1 then return end
        local p = (addon.db and addon.db.profile)
            or (addon.core and addon.core.db and addon.core.db.profile)
        local ws    = p and p.windows and p.windows[popup.tabIdx]
        local label = ws and ws.label or ("Tab " .. popup.tabIdx)
        local idx   = popup.tabIdx
        if BazUI.Confirm then
            BazUI:Confirm({
                title       = "Delete tab?",
                body        = "Delete the \"" .. label .. "\" tab? This can't be undone.",
                acceptLabel = "Delete",
                acceptStyle = "destructive",
                onAccept    = function()
                    if addon.Tabs and addon.Tabs.DeleteTab then
                        addon.Tabs:DeleteTab(idx)
                    end
                end,
            })
        end
    end)
    popup.deleteBtn = del

    -- Hide on Escape (only when this popup has focus).
    popup:EnableKeyboard(true)
    popup:SetPropagateKeyboardInput(true)
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    popup.rows = {}
    Channels._popup = popup
    return popup
end

-- Build (or reuse) the row at index `i`. Each row is a CheckButton with
-- a FontString label to its right. The CheckButton's hit rect extends
-- across the full popup width so clicking anywhere on the row toggles
-- the channel — feels right for a long list of options.
local function EnsureRow(popup, i)
    local row = popup.rows[i]
    if row then return row end

    row = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
    row:SetSize(20, 20)
    -- Hit rect: extend right edge across the column width so clicking
    -- anywhere in the row toggles. Negative = outward.
    row:SetHitRectInsets(0, -(ColWidth() - 24), 0, 0)

    row.label = BazUI.Skin.Theme.FontString(row, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", row, "RIGHT", 4, 1)

    -- Click handler is set freshly per-show because it captures the
    -- current tab index. Bind here as a no-op so OnClick is defined.
    row:SetScript("OnClick", function() end)

    popup.rows[i] = row
    return row
end

-- Build the list of row specs the popup renders. Static categories
-- come first, then one row per currently-joined channel. Each spec is
-- a flat { key, label, color } so the row renderer doesn't need to
-- branch on category-vs-channel - the persistence key just happens to
-- be either "say" / "guild" / etc. or "channel:General" / "channel:Trade".
local function BuildPopupSpecs()
    local specs = {}
    for _, cat in ipairs(CATEGORIES) do
        specs[#specs + 1] = {
            key   = cat.key,
            label = cat.label,
            color = cat.color,
        }
    end
    for _, ch in ipairs(GetCurrentChannels()) do
        specs[#specs + 1] = {
            key   = "channel:" .. ch.base,
            label = ch.base,
            color = "CHANNEL",
        }
    end
    return specs
end

function Channels:ShowPopup(tabFrame, tabIdx)
    if not tabFrame or not tabIdx then return end

    local popup = EnsurePopup()
    popup.tabIdx = tabIdx

    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    local ws = p and p.windows and p.windows[tabIdx]
    if not ws then return end
    ws.channels = ws.channels or {}

    -- Title + name input
    local label = ws.label or ("Tab " .. tabIdx)
    popup.title:SetText(label)
    popup.nameEdit:SetText(label)

    -- Build the unified spec list (static categories + dynamic channels)
    -- and lay it out in a 2-column grid. The split point is dynamic
    -- (ceil(N/2)) so adding/removing channels reflows automatically.
    local specs = BuildPopupSpecs()
    local rowsTop = HEADER_HEIGHT + NAME_BLOCK_H + DIVIDER_H
    local rowsPerCol = math.ceil(#specs / NUM_COLS)
    local colW = ColWidth()
    for i, spec in ipairs(specs) do
        local col       = math.floor((i - 1) / rowsPerCol) + 1   -- 1-based
        local rowInCol  = ((i - 1) % rowsPerCol) + 1             -- 1-based
        local x         = LEFT_PAD + (col - 1) * (colW + COL_GAP)
        local y         = -rowsTop - (rowInCol - 1) * ROW_HEIGHT

        local row = EnsureRow(popup, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", x, y)
        row.label:SetText(spec.label)
        row.label:SetTextColor(ColorFor(spec.color))
        row:SetChecked(ws.channels[spec.key] == true)
        local capturedKey = spec.key
        row:SetScript("OnClick", function(self)
            local checked = self:GetChecked() and true or nil
            ws.channels[capturedKey] = checked
            local f = addon.Window and addon.Window:Get(tabIdx)
            if f then Channels:Subscribe(f, tabIdx) end
        end)
        row:Show()
    end
    for i = #specs + 1, #popup.rows do
        popup.rows[i]:Hide()
    end

    -- Position the delete button below the tallest column.
    local rowsBottom = rowsTop + (rowsPerCol * ROW_HEIGHT) + DIVIDER_H
    popup.deleteBtn:ClearAllPoints()
    popup.deleteBtn:SetPoint("TOPLEFT", LEFT_PAD, -rowsBottom)
    popup.deleteBtn:SetWidth(POPUP_WIDTH - LEFT_PAD * 2)
    if tabIdx == 1 then
        popup.deleteBtn:Disable()
    else
        popup.deleteBtn:Enable()
    end

    -- Total popup height: header + name + divider + tallest-column +
    -- divider + delete button + footer.
    popup:SetSize(POPUP_WIDTH, rowsBottom + DELETE_BLOCK_H + FOOTER_HEIGHT)

    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", tabFrame, "BOTTOMLEFT", 0, -2)
    popup:Show()
    popup:Raise()
end

function Channels:HidePopup()
    if Channels._popup then Channels._popup:Hide() end
end
