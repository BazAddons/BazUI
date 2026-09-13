-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: Channel Names
--
-- Rewrites the bracketed channel prefix in chat lines before they
-- render:
--   [Guild]                 -> [g]
--   [Party Leader]          -> [pl]
--   [2. Trade - Stormwind]  -> [Trade]   (when stripChannelNumbers is on)
--
-- Implementation: hooks the per-frame AddMessage chain in
-- Replica/Window.lua via :Rewrite(text). Persistence stores RAW text
-- (without the rewrite applied), so toggling the feature off later
-- doesn't leave fossilized shortenings in saved history. Replay
-- re-applies the current rewrite settings on the way back into the
-- chat frame, matching the live-render behavior.
--
-- Public API (on addon.ChannelNames):
--   :Rewrite(text)             -- text -> rewritten text
--   :Refresh()                 -- rebuild pattern map from current cfg
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

local ChannelNames = {}
addon.ChannelNames = ChannelNames

local function GetCfg()
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    return p and p.channelNames or nil
end

---------------------------------------------------------------------------
-- Long-bracket lookup
--
-- Each chat type (GUILD, PARTY, etc.) has a localized "[Channel] %s:"
-- format string in a global like CHAT_GUILD_GET. The bracket portion
-- is the literal we need to swap. We ask Blizzard for the localized
-- template instead of hardcoding English so the rewrite works on any
-- client locale.
---------------------------------------------------------------------------

local TEMPLATE_NAMES = {
    GUILD                = "CHAT_GUILD_GET",
    OFFICER              = "CHAT_OFFICER_GET",
    PARTY                = "CHAT_PARTY_GET",
    PARTY_LEADER         = "CHAT_PARTY_LEADER_GET",
    RAID                 = "CHAT_RAID_GET",
    RAID_LEADER          = "CHAT_RAID_LEADER_GET",
    RAID_WARNING         = "CHAT_RAID_WARNING_GET",
    INSTANCE_CHAT        = "CHAT_INSTANCE_CHAT_GET",
    INSTANCE_CHAT_LEADER = "CHAT_INSTANCE_CHAT_LEADER_GET",
    BATTLEGROUND         = "CHAT_BATTLEGROUND_GET",
    BATTLEGROUND_LEADER  = "CHAT_BATTLEGROUND_LEADER_GET",
    SAY                  = "CHAT_SAY_GET",
    YELL                 = "CHAT_YELL_GET",
    EMOTE                = "CHAT_EMOTE_GET",
    -- Whispers don't have a [bracket] prefix in the default render
    -- (they show "Player whispers: text" or "To Player: text"), so
    -- WHISPER / WHISPER_INFORM keys aren't included here.
}

local function GetLongBracketFor(key)
    local templateName = TEMPLATE_NAMES[key]
    if not templateName then return nil end
    local template = _G[templateName]
    if type(template) ~= "string" then return nil end
    -- Format: "[Guild] %s: " or "[%s] %s: " (locale dependent). We
    -- just want the literal "[...]" portion at the start.
    return template:match("^(%b[])")
end

---------------------------------------------------------------------------
-- Pattern cache — rebuilt on Refresh; hot path reads from `active`
---------------------------------------------------------------------------

local active = {
    bracketRewrites = {},   -- [longBracket] = "[short]"
    stripNumbers    = false,
    enabled         = true,
}

function ChannelNames:Refresh()
    local cfg = GetCfg()
    if not cfg then
        active.enabled = false
        return
    end
    active.enabled      = cfg.enabled ~= false
    active.stripNumbers = cfg.stripChannelNumbers ~= false

    wipe(active.bracketRewrites)
    for key, short in pairs(cfg.shortNames or {}) do
        local longBracket = GetLongBracketFor(key)
        if longBracket and type(short) == "string" and short ~= "" then
            active.bracketRewrites[longBracket] = "[" .. short .. "]"
        end
    end
end

---------------------------------------------------------------------------
-- :Rewrite — apply the current settings to a single chat line.
--
-- Called from Window.lua's HookAddMessage on every line going through
-- the chat frame, and from Persistence:Replay on every replayed
-- historic line. Returns the rewritten text (or text unchanged when
-- the feature is off / no patterns matched).
---------------------------------------------------------------------------

function ChannelNames:Rewrite(text)
    if not active.enabled then return text end
    if type(text) ~= "string" or text == "" then return text end

    -- Static bracket replacements (Guild, Party, etc.). Most lines
    -- carry at most one prefix; bail after the first hit.
    for long, short in pairs(active.bracketRewrites) do
        if text:find(long, 1, true) then
            text = text:gsub(long, short, 1)
            break
        end
    end

    -- Custom channels: numeric prefixes + zone suffixes get stripped.
    --   "[1. General - Stormwind]" -> "[General]"
    --   "[5. Trade (Services) - City]" -> "[Trade (Services)]"
    --   "[2. WorldDefense]"        -> "[WorldDefense]"   (no zone suffix)
    if active.stripNumbers then
        -- First pattern: numbered + zoned. Match "[N. Name - Zone]".
        text = text:gsub("%[%d+%.%s*([^%]:]-)%s*%-[^%]]+%]", "[%1]")
        -- Second pattern: numbered without zone suffix.
        text = text:gsub("%[%d+%.%s*([^%]]-)%]", "[%1]")
    end

    return text
end

---------------------------------------------------------------------------
-- Init: rebuild patterns once at file-load. Refresh() can be called
-- later by the Settings page when the user toggles enable/strip.
---------------------------------------------------------------------------

ChannelNames:Refresh()
