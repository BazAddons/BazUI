-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Social: Whispers, friend online/offline, guild status, group events.
-- Events: PLAYER_ENTERING_WORLD, CHAT_MSG_WHISPER, CHAT_MSG_BN_WHISPER,
--         BN_FRIEND_INFO_CHANGED, CHAT_MSG_SYSTEM, READY_CHECK,
--         PARTY_INVITE_REQUEST, CONFIRM_SUMMON, DUEL_REQUESTED
-- ==========================================================================

local MODULE_ID = "social"
local MODULE_NAME = "Social"
local MODULE_ICON = "Interface\\Icons\\INV_Letter_15"

local ICON_WHISPER = "Interface\\Icons\\INV_Letter_15"
local ICON_FRIEND_ONLINE = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"
local ICON_FRIEND_OFFLINE = "Interface\\Icons\\Spell_Shadow_SacrificialShield"
local ICON_GUILD_MEMBER = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
local ICON_READY_CHECK = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON_SUMMON = "Interface\\Icons\\Spell_Shadow_DemonicCircleSummon"
local ICON_DUEL = "Interface\\Icons\\Ability_DualWield"
local ICON_INVITE = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"

local loginGracePeriod = true

local GetSetting = BNC:CreateGetSetting(MODULE_ID)
local whisperDedup = BNC:CreateDeduplicator(1.0)

local function OnWhisperReceived(event, msg, sender)
    if GetSetting("showWhispers") == false then return end
    if not sender or not msg then return end

    if whisperDedup:IsDuplicate(sender) then return end

    local displayName = BNC.SafeMatch(sender, "(.+)%-") or sender

    local displayMsg = msg
    if (BNC.SafeLen(displayMsg) or 0) > 80 then
        displayMsg = BNC.SafeSub(displayMsg, 1, 77) .. "..."
    end

    BNC:Push({
        module = MODULE_ID,
        title = displayName,
        message = displayMsg,
        icon = ICON_WHISPER,
        priority = "high",
        duration = GetSetting("toastDuration") or 6,
        silent = GetSetting("whisperToasts") == false,
    })
end

local function OnBNetWhisperReceived(event, msg, _, _, _, _, _, _, _, _, _, _, _, presenceID)
    if GetSetting("showWhispers") == false then return end
    if not msg then return end

    local accountInfo = C_BattleNet.GetAccountInfoByID(presenceID)
    local displayName = accountInfo and accountInfo.accountName or "BNet Friend"

    if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.characterName then
        displayName = accountInfo.gameAccountInfo.characterName .. " (" .. displayName .. ")"
    end

    local key = "bnet_" .. (presenceID or 0)
    if whisperDedup:IsDuplicate(key) then return end

    local displayMsg = msg
    if (BNC.SafeLen(displayMsg) or 0) > 80 then
        displayMsg = BNC.SafeSub(displayMsg, 1, 77) .. "..."
    end

    BNC:Push({
        module = MODULE_ID,
        title = displayName,
        message = displayMsg,
        icon = ICON_WHISPER,
        priority = "high",
        duration = GetSetting("toastDuration") or 6,
        silent = GetSetting("whisperToasts") == false,
    })
end

-- BNet friend online/offline tracking
local friendOnlineCache = {}

local function InitFriendCache()
    wipe(friendOnlineCache)
    local numFriends = BNGetNumFriends()
    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo then
            friendOnlineCache[accountInfo.bnetAccountID] = accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline
        end
    end
end

local function CheckFriendChanges()
    if loginGracePeriod then return end

    local showOnline = GetSetting("showFriendOnline") ~= false
    local showOffline = GetSetting("showFriendOffline") ~= false

    local numFriends = BNGetNumFriends()
    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo then
            local id = accountInfo.bnetAccountID
            local isOnline = accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline
            local wasOnline = friendOnlineCache[id]

            if wasOnline ~= nil and isOnline ~= wasOnline then
                local name = accountInfo.accountName or "Friend"
                local charName = accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.characterName

                if isOnline and showOnline then
                    local msg = charName and (charName .. " has come online") or "Has come online"
                    BNC:Push({
                        module = MODULE_ID,
                        title = name,
                        message = msg,
                        icon = ICON_FRIEND_ONLINE,
                        priority = "low",
                        duration = GetSetting("toastDuration") or 4,
                        silent = GetSetting("friendToasts") == false,
                    })
                elseif not isOnline and showOffline then
                    BNC:Push({
                        module = MODULE_ID,
                        title = name,
                        message = "Has gone offline",
                        icon = ICON_FRIEND_OFFLINE,
                        priority = "low",
                        duration = GetSetting("toastDuration") or 3,
                        silent = GetSetting("friendToasts") == false,
                    })
                end
            end

            friendOnlineCache[id] = isOnline
        end
    end
end

-- Guild member online/offline via system messages
local function OnSystemMessage(event, msg)
    if not msg then return end

    local playerLink, status = BNC.SafeMatch(msg, "|Hplayer:.-|h%[(.-)%]|h has (.+)%.")

    if playerLink and status then
        if status == "come online" and GetSetting("showGuildOnline") ~= false then
            BNC:Push({
                module = MODULE_ID,
                title = playerLink,
                message = "Has come online (Guild)",
                icon = ICON_GUILD_MEMBER,
                priority = "low",
                duration = GetSetting("toastDuration") or 3,
                silent = GetSetting("guildToasts") == false,
            })
        elseif status == "gone offline" and GetSetting("showGuildOffline") ~= false then
            BNC:Push({
                module = MODULE_ID,
                title = playerLink,
                message = "Has gone offline (Guild)",
                icon = ICON_GUILD_MEMBER,
                priority = "low",
                duration = GetSetting("toastDuration") or 3,
                silent = GetSetting("guildOfflineToasts") == false,
            })
        end
    end
end

local function OnReadyCheck(event, initiator)
    if GetSetting("showReadyCheck") == false then return end

    BNC:Push({
        module = MODULE_ID,
        title = "Ready Check",
        message = (initiator or "Leader") .. " started a ready check!",
        icon = ICON_READY_CHECK,
        priority = "high",
        duration = GetSetting("toastDuration") or 5,
        silent = GetSetting("groupToasts") == false,
    })
end

local function OnGroupInvite(event, sender)
    if GetSetting("showInvites") == false then return end

    BNC:Push({
        module = MODULE_ID,
        title = "Group Invite",
        message = (sender or "Someone") .. " has invited you to a group",
        icon = ICON_INVITE,
        priority = "high",
        duration = GetSetting("toastDuration") or 6,
        silent = GetSetting("groupToasts") == false,
    })
end

local function OnSummonConfirm(event)
    if GetSetting("showSummon") == false then return end

    local summoner = C_SummonInfo.GetSummonConfirmSummoner()
    local area = C_SummonInfo.GetSummonConfirmAreaName()

    BNC:Push({
        module = MODULE_ID,
        title = "Summon Request",
        message = (summoner or "Someone") .. " is summoning you" .. (area and (" to " .. area) or ""),
        icon = ICON_SUMMON,
        priority = "high",
        duration = GetSetting("toastDuration") or 8,
        silent = GetSetting("groupToasts") == false,
    })
end

local function OnDuelRequest(event, sender)
    if GetSetting("showDuels") == false then return end

    BNC:Push({
        module = MODULE_ID,
        title = "Duel Request",
        message = (sender or "Someone") .. " has challenged you to a duel",
        icon = ICON_DUEL,
        priority = "normal",
        duration = GetSetting("toastDuration") or 5,
        silent = GetSetting("groupToasts") == false,
    })
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
eventFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
eventFrame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("READY_CHECK")
eventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
eventFrame:RegisterEvent("CONFIRM_SUMMON")
eventFrame:RegisterEvent("DUEL_REQUESTED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(5, function()
            InitFriendCache()
            loginGracePeriod = false
        end)
    elseif event == "CHAT_MSG_WHISPER" then
        OnWhisperReceived(event, ...)
    elseif event == "CHAT_MSG_BN_WHISPER" then
        OnBNetWhisperReceived(event, ...)
    elseif event == "BN_FRIEND_INFO_CHANGED" then
        CheckFriendChanges()
    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage(event, ...)
    elseif event == "READY_CHECK" then
        OnReadyCheck(event, ...)
    elseif event == "PARTY_INVITE_REQUEST" then
        OnGroupInvite(event, ...)
    elseif event == "CONFIRM_SUMMON" then
        OnSummonConfirm(event)
    elseif event == "DUEL_REQUESTED" then
        OnDuelRequest(event, ...)
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { type = "event", key = "whispers",     label = "Whispers",                    show = "showWhispers",     toast = "whisperToasts" },
    { type = "event", key = "friends",      label = "Friends online and offline",  show = { "showFriendOnline", "showFriendOffline" }, toast = "friendToasts" },
    { type = "event", key = "guildOnline",  label = "Guild members coming online", show = "showGuildOnline",  toast = "guildToasts" },
    { type = "event", key = "guildOffline", label = "Guild members going offline", show = "showGuildOffline", toast = "guildOfflineToasts", default = "off" },
    { type = "event", key = "requests",     label = "Group requests", desc = "Ready checks, invites, summons and duels.",
      show = { "showReadyCheck", "showInvites", "showSummon", "showDuels" }, toast = "groupToasts" },
    { key = "toastDuration",    label = "Toast duration", type = "slider", default = 5, min = 1, max = 15, step = 1 },
})
