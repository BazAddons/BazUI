-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Group: Group roster changes, queue pops, role checks, and pull timers.
-- Events: GROUP_ROSTER_UPDATE, START_TIMER
-- ==========================================================================

local MODULE_ID = "group"
local MODULE_NAME = "Group"
local MODULE_ICON = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"

local ICON_MEMBER_JOIN = "Interface\\Icons\\Ability_Spy"
local ICON_MEMBER_LEAVE = "Interface\\Icons\\Ability_Rogue_TricksOfTheTrade"
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
                event = "members",
                module = MODULE_ID,
                title = name,
                message = "joined the group",
                icon = ICON_MEMBER_JOIN,
                priority = "low",
                duration = GetSetting("toastDuration") or 3,
                silent = GetSetting("memberToasts") == false,
            })
        end
    end

    for name in pairs(groupMembers) do
        if not current[name] and name ~= UnitName("player") then
            BNC:Push({
                event = "members",
                module = MODULE_ID,
                title = name,
                message = "left the group",
                icon = ICON_MEMBER_LEAVE,
                priority = "low",
                duration = GetSetting("toastDuration") or 3,
                silent = GetSetting("memberToasts") == false,
            })
        end
    end

    groupMembers = current
end

local function OnCountdown(event, initiatedBy, timeRemaining)
    if GetSetting("showCountdown") == false then return end

    BNC:Push({
        event = "countdown",
        module = MODULE_ID,
        title = "Pull Timer",
        message = (initiatedBy or "Someone") .. " started a " .. (timeRemaining or "?") .. "s countdown",
        icon = ICON_COUNTDOWN,
        priority = "high",
        duration = GetSetting("toastDuration") or 4,
        silent = GetSetting("countdownToasts") == false,
    })
end

-- Event frame
local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("START_TIMER")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        groupMembers = GetGroupMemberList()
    elseif event == "GROUP_ROSTER_UPDATE" then
        C_Timer.After(0.2, CheckGroupChanges)
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
    { type = "event", key = "members",   label = "Members joining and leaving", show = "showMemberChanges", toast = "memberToasts" },
    { type = "event", key = "countdown", label = "Pull timers",                 show = "showCountdown",     toast = "countdownToasts" },
    { key = "toastDuration",    label = "Toast duration", type = "slider", default = 5, min = 1, max = 15, step = 1 },
})
