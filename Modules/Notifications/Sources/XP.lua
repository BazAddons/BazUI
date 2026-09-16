-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-XP: Experience gain batching, level-up alerts, and rested XP status.
-- Events: PLAYER_ENTERING_WORLD, PLAYER_XP_UPDATE, PLAYER_LEVEL_UP
-- ==========================================================================

local MODULE_ID = "xp"
local MODULE_NAME = "Experience"
local MODULE_ICON = "Interface\\Icons\\XP_Icon"

local ICON_XP = "Interface\\Icons\\XP_Icon"
-- Sixty, because sixty is where this game ends. The eighty on the old
-- icon is from a later expansion and reads as a mistake to anyone who
-- has just earned a level here.
local ICON_LEVEL = "Interface\\Icons\\Achievement_Level_60"
local ICON_RESTED = "Interface\\Icons\\Spell_Nature_Sleep"

local lastXP = 0
local xpAccumulator = 0
local xpFlushTimer = nil
-- Batches rapid XP gains (quest turn-ins, bonus objectives) into one toast
local XP_ACCUMULATE_TIME = 2.0

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local function FlushXPGain()
    if xpAccumulator <= 0 then return end
    if GetSetting("showXPGains") == false then
        xpAccumulator = 0
        xpFlushTimer = nil
        return
    end

    local currentXP = UnitXP("player")
    local maxXP = UnitXPMax("player")
    local pct = maxXP > 0 and math.floor((currentXP / maxXP) * 100) or 0

    BNC:Push({
        event = "gains",
        module = MODULE_ID,
        title = "+" .. xpAccumulator .. " XP",
        message = currentXP .. " / " .. maxXP .. " (" .. pct .. "%)",
        icon = ICON_XP,
        priority = "low",
        duration = GetSetting("toastDuration") or 3,
        silent = GetSetting("xpToasts") == false,
    })

    xpAccumulator = 0
    xpFlushTimer = nil
end

local function OnXPUpdate()
    if UnitLevel("player") >= GetMaxLevelForPlayerExpansion() then return end

    local currentXP = UnitXP("player")
    if lastXP > 0 and currentXP > lastXP then
        local gained = currentXP - lastXP
        xpAccumulator = xpAccumulator + gained

        -- Restart flush timer on each gain so nearby gains batch together
        if xpFlushTimer then xpFlushTimer:Cancel() end
        xpFlushTimer = C_Timer.NewTimer(XP_ACCUMULATE_TIME, FlushXPGain)
    end
    lastXP = currentXP
end

local function OnLevelUp(event, level, ...)
    if GetSetting("showLevelUp") == false then return end

    BNC:Push({
        event = "levelUp",
        module = MODULE_ID,
        title = "Level Up!",
        message = "You reached level " .. level .. "!",
        icon = ICON_LEVEL,
        priority = "high",
        duration = GetSetting("toastDuration") or 8,
        silent = GetSetting("levelToasts") == false,
    })
    lastXP = 0
end

local function CheckRestedXP()
    if GetSetting("showRested") == false then return end
    if UnitLevel("player") >= GetMaxLevelForPlayerExpansion() then return end

    local restedXP = GetXPExhaustion() or 0
    local maxXP = UnitXPMax("player")

    if restedXP > 0 then
        local pct = maxXP > 0 and math.floor((restedXP / maxXP) * 100) or 0
        BNC:Push({
            event = "rested",
            module = MODULE_ID,
            title = "Rested XP Available",
            message = restedXP .. " bonus XP (" .. pct .. "% of level)",
            icon = ICON_RESTED,
            priority = "low",
            duration = GetSetting("toastDuration") or 4,
            silent = GetSetting("restedToasts") == false,
        })
    end
end

local function SetupLevelUpSuppression()
    if GetSetting("hideDefaultLevelUp") == false then return end

    if LevelUpDisplay then
        pcall(function() LevelUpDisplay:UnregisterAllEvents() end)
        pcall(function() LevelUpDisplay:Hide() end)
    end
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        lastXP = UnitXP("player")
        SetupLevelUpSuppression()
        C_Timer.After(3, CheckRestedXP)
    elseif event == "PLAYER_XP_UPDATE" then
        OnXPUpdate()
    elseif event == "PLAYER_LEVEL_UP" then
        OnLevelUp(event, ...)
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { type = "event", key = "gains",   label = "XP gains",           show = "showXPGains", toast = "xpToasts" },
    { type = "event", key = "levelUp", label = "Level up",           show = "showLevelUp", toast = "levelToasts", blizzard = "hideDefaultLevelUp", blizzardReload = "Blizzard's level-up display" },
    { type = "event", key = "rested",  label = "Rested XP at login", show = "showRested",  toast = "restedToasts" },
    { key = "toastDuration",    label = "Toast duration", type = "slider", default = 4, min = 1, max = 15, step = 1 },
})
