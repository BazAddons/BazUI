-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Achievements: Achievement earned, criteria, tracked progress, and guild notifications.
-- Events: ACHIEVEMENT_EARNED, CRITERIA_EARNED, TRACKED_ACHIEVEMENT_UPDATE, GUILD_ACHIEVEMENT_EARNED
-- ==========================================================================

local MODULE_ID = "achievements"
local MODULE_NAME = "Achievements"
local MODULE_ICON = "Interface\\Icons\\Achievement_General"

local ICON_EARNED = "Interface\\Icons\\Achievement_General"
local ICON_CRITERIA = "Interface\\Icons\\INV_Misc_StarStar"
local ICON_GUILD_ACHIEVEMENT = "Interface\\Icons\\Achievement_GuildPerk_MobileBanking"

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local function OnAchievementEarned(event, achievementID, alreadyEarned)
    if GetSetting("showEarned") == false then return end
    if not achievementID then return end
    if alreadyEarned then return end

    local _, name, _, _, _, _, _, _, _, icon =
        GetAchievementInfo(achievementID)

    if not name then return end

    BNC:Push({
        module = MODULE_ID,
        title = "Achievement Earned!",
        message = name,
        icon = icon and tostring(icon) or ICON_EARNED,
        priority = "high",
        duration = GetSetting("toastDuration") or 6,
        silent = GetSetting("earnedToasts") == false,
    })
end

-- Criteria completed (CRITERIA_UPDATE is unreliable, so we use CRITERIA_EARNED)
local function OnCriteriaEarned(event, achievementID, criteriaString)
    if GetSetting("showCriteria") == false then return end
    if not achievementID then return end

    local _, achieveName, _, _, _, _, _, _, _, achieveIcon = GetAchievementInfo(achievementID)

    local message = criteriaString or "Criteria completed"

    BNC:Push({
        module = MODULE_ID,
        title = achieveName or "Achievement Progress",
        message = message,
        icon = achieveIcon and tostring(achieveIcon) or ICON_CRITERIA,
        priority = "normal",
        duration = GetSetting("toastDuration") or 4,
        silent = GetSetting("criteriaToasts") == false,
    })
end

local function OnTrackedAchievementUpdate(event, achievementID)
    if GetSetting("showTrackedProgress") == false then return end
    if not achievementID then return end

    local _, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(achievementID)
    if not name then return end

    local numCriteria = GetAchievementNumCriteria(achievementID)
    local progressParts = {}

    for i = 1, numCriteria do
        local criteriaString, _, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, i)
        if criteriaString and reqQuantity and reqQuantity > 0 and not completed then
            table.insert(progressParts, criteriaString .. " " .. quantity .. "/" .. reqQuantity)
        end
    end

    if #progressParts == 0 then return end

    -- Show first incomplete criteria, summarize the rest
    local message = progressParts[1]
    if #progressParts > 1 then
        message = message .. " (+" .. (#progressParts - 1) .. " more)"
    end

    BNC:Push({
        module = MODULE_ID,
        title = name,
        message = message,
        icon = icon and tostring(icon) or ICON_CRITERIA,
        priority = "low",
        duration = GetSetting("toastDuration") or 3,
        silent = GetSetting("trackedToasts") == false,
    })
end

local function OnGuildAchievement(event, achievementID, playerName)
    if GetSetting("showGuildAchievements") == false then return end
    if not achievementID or not playerName then return end

    -- Skip our own achievements (already handled by OnAchievementEarned)
    local myName = UnitName("player")
    if playerName == myName then return end

    local _, name = GetAchievementInfo(achievementID)

    BNC:Push({
        module = MODULE_ID,
        title = playerName,
        message = "Earned: " .. (name or "Achievement"),
        icon = ICON_GUILD_ACHIEVEMENT,
        priority = "low",
        duration = GetSetting("toastDuration") or 3,
        silent = GetSetting("guildToasts") == false,
    })
end

-- Suppress default Blizzard achievement popups via core hook
local function SetupAchievementSuppression()
    if GetSetting("hideDefaultPopup") == false then return end

    local function shouldSuppress()
        return GetSetting("hideDefaultPopup") ~= false
    end

    BNC:HookAlertSystem(AchievementAlertSystem, shouldSuppress)
    BNC:HookAlertSystem(CriteriaAlertSystem, shouldSuppress)
end

-- Event frame
local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ACHIEVEMENT_EARNED")
eventFrame:RegisterEvent("CRITERIA_EARNED")
eventFrame:RegisterEvent("TRACKED_ACHIEVEMENT_UPDATE")

pcall(function() eventFrame:RegisterEvent("GUILD_ACHIEVEMENT_EARNED") end)
pcall(function() eventFrame:RegisterEvent("ACHIEVEMENT_EARNED_BY_GUILD_MEMBER") end)

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        SetupAchievementSuppression()
    elseif event == "ACHIEVEMENT_EARNED" then
        OnAchievementEarned(event, ...)
    elseif event == "CRITERIA_EARNED" then
        OnCriteriaEarned(event, ...)
    elseif event == "TRACKED_ACHIEVEMENT_UPDATE" then
        OnTrackedAchievementUpdate(event, ...)
    elseif event == "GUILD_ACHIEVEMENT_EARNED" then
        OnGuildAchievement(event, ...)
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { type = "event", key = "earned",   label = "Achievement earned",           show = "showEarned",            toast = "earnedToasts" },
    { type = "event", key = "criteria", label = "Criteria completed",           show = "showCriteria",          toast = "criteriaToasts" },
    { type = "event", key = "tracked",  label = "Tracked achievement progress", show = "showTrackedProgress",   toast = "trackedToasts" },
    { type = "event", key = "guild",    label = "Guild member achievements",    show = "showGuildAchievements", toast = "guildToasts" },
    { key = "toastDuration",    label = "Toast duration", type = "slider", default = 5, min = 1, max = 15, step = 1 },
    { key = "hideDefaultPopup", label = "Hide Blizzard's achievement popup", type = "toggle", default = true, section = "blizzard" },
})
