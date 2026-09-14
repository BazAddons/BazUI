-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Group: Group roster changes, queue pops, role checks, and pull timers.
-- Events: GROUP_ROSTER_UPDATE, LFG_PROPOSAL_SHOW, ROLE_POLL_BEGIN, START_TIMER
-- ==========================================================================

local MODULE_ID = "group"
local MODULE_NAME = "Group"
local MODULE_ICON = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"

local ICON_LFG = "Interface\\Icons\\INV_Misc_GroupLooking"
local ICON_MEMBER_JOIN = "Interface\\Icons\\Ability_Spy"
local ICON_MEMBER_LEAVE = "Interface\\Icons\\Ability_Rogue_TricksOfTheTrade"
local ICON_ROLE = "Interface\\Icons\\Spell_Nature_Polymorph"
local ICON_COUNTDOWN = "Interface\\Icons\\Spell_Holy_BorrowedTime"

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local groupMembers = {}

local function GetGroupMemberList()
    local members = {}
    local prefix = IsInRaid() and "raid" or "party"
    local count = GetNumGroupMembers()

    if count == 0 then return members end

    if IsInRaid() then
        for i = 1, count do
            local name = UnitName(prefix .. i)
            if name then members[name] = true end
        end
    else
        for i = 1, count - 1 do
            local name = UnitName("party" .. i)
            if name then members[name] = true end
        end
        local myName = UnitName("player")
        if myName then members[myName] = true end
    end

    return members
end

local function CheckGroupChanges()
    if GetSetting("showMemberChanges") == false then return end

    local current = GetGroupMemberList()

    for name in pairs(current) do
        if not groupMembers[name] and name ~= UnitName("player") then
            BNC:Push({
                module = MODULE_ID,
                title = name,
                message = "joined the group",
                icon = ICON_MEMBER_JOIN,
                priority = "low",
                duration = GetSetting("memberDuration") or 3,
                silent = GetSetting("memberToasts") == false,
            })
        end
    end

    for name in pairs(groupMembers) do
        if not current[name] and name ~= UnitName("player") then
            BNC:Push({
                module = MODULE_ID,
                title = name,
                message = "left the group",
                icon = ICON_MEMBER_LEAVE,
                priority = "low",
                duration = GetSetting("memberDuration") or 3,
                silent = GetSetting("memberToasts") == false,
            })
        end
    end

    groupMembers = current
end

local function OnLFGProposal()
    if GetSetting("showQueuePop") == false then return end

    BNC:Push({
        module = MODULE_ID,
        title = "Queue Ready!",
        message = "A group has been found",
        icon = ICON_LFG,
        priority = "high",
        duration = GetSetting("queueDuration") or 8,
        silent = GetSetting("queueToasts") == false,
    })
end

local function OnRoleCheck()
    if GetSetting("showRoleCheck") == false then return end

    BNC:Push({
        module = MODULE_ID,
        title = "Role Check",
        message = "Confirm your role",
        icon = ICON_ROLE,
        priority = "high",
        duration = GetSetting("roleDuration") or 5,
        silent = GetSetting("roleToasts") == false,
    })
end

local function OnCountdown(event, initiatedBy, timeRemaining)
    if GetSetting("showCountdown") == false then return end

    BNC:Push({
        module = MODULE_ID,
        title = "Pull Timer",
        message = (initiatedBy or "Someone") .. " started a " .. (timeRemaining or "?") .. "s countdown",
        icon = ICON_COUNTDOWN,
        priority = "high",
        duration = GetSetting("countdownDuration") or 4,
        silent = GetSetting("countdownToasts") == false,
    })
end

-- Event frame
local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("LFG_PROPOSAL_SHOW")
eventFrame:RegisterEvent("ROLE_POLL_BEGIN")
eventFrame:RegisterEvent("START_TIMER")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        groupMembers = GetGroupMemberList()
    elseif event == "GROUP_ROSTER_UPDATE" then
        C_Timer.After(0.2, CheckGroupChanges)
    elseif event == "LFG_PROPOSAL_SHOW" then
        OnLFGProposal()
    elseif event == "ROLE_POLL_BEGIN" then
        OnRoleCheck()
    elseif event == "START_TIMER" then
        OnCountdown(event, ...)
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { key = "showQueuePop",       label = "Show Queue Pop",                type = "toggle", default = true },
    { key = "showMemberChanges",  label = "Show Member Join/Leave",        type = "toggle", default = true },
    { key = "showRoleCheck",      label = "Show Role Check",               type = "toggle", default = true },
    { key = "showCountdown",      label = "Show Pull Timer",               type = "toggle", default = true },
    { key = "queueToasts",        label = "Toast on Queue Pop",            type = "toggle", default = true },
    { key = "memberToasts",       label = "Toast on Member Changes",       type = "toggle", default = true },
    { key = "roleToasts",         label = "Toast on Role Check",           type = "toggle", default = true },
    { key = "countdownToasts",    label = "Toast on Pull Timer",           type = "toggle", default = true },
    { key = "queueDuration",      label = "Queue Toast Duration",          type = "slider", default = 8, min = 1, max = 15, step = 1 },
    { key = "memberDuration",     label = "Member Toast Duration",         type = "slider", default = 3, min = 1, max = 15, step = 1 },
    { key = "roleDuration",       label = "Role Check Toast Duration",     type = "slider", default = 5, min = 1, max = 15, step = 1 },
    { key = "countdownDuration",  label = "Countdown Toast Duration",      type = "slider", default = 4, min = 1, max = 15, step = 1 },
})
