-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Instance: Alerts for dungeons, raids, boss encounters, M+, and LFG.
-- Events: PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA, ENCOUNTER_START,
--         ENCOUNTER_END, CHALLENGE_MODE_COMPLETED, LFG_PROPOSAL_SHOW
-- ==========================================================================

local MODULE_ID = "instance"
local MODULE_NAME = "Instance"
local MODULE_ICON = "Interface\\Icons\\INV_Misc_Key_10"

local ICON_DUNGEON = "Interface\\Icons\\INV_Misc_Key_10"
local ICON_RAID = "Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster"
local ICON_BOSS_KILL = "Interface\\Icons\\Achievement_Boss_KilJaeden"
local ICON_WIPE = "Interface\\Icons\\Spell_Shadow_SoulGem"
local ICON_QUEUE = "Interface\\Icons\\Spell_Holy_BorrowedTime"

local currentInstance = nil
local encounterStartTime = nil

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local function CheckInstanceChange()
    local inInstance, instanceType = IsInInstance()
    local instanceName = GetInstanceInfo()

    if inInstance and instanceName and instanceName ~= currentInstance then
        if GetSetting("showEntered") ~= false then
            local icon = ICON_DUNGEON
            local title = "Dungeon"
            if instanceType == "raid" then
                icon = ICON_RAID
                title = "Raid"
            elseif instanceType == "arena" then
                title = "Arena"
            elseif instanceType == "pvp" then
                title = "Battleground"
            end

            BNC:Push({
                event = "entered",
                module = MODULE_ID,
                title = title,
                message = instanceName,
                icon = icon,
                priority = "normal",
                duration = GetSetting("toastDuration") or 4,
                silent = GetSetting("enteredToasts") == false,
            })
        end
        currentInstance = instanceName

    elseif not inInstance and currentInstance then
        if GetSetting("showLeft") ~= false then
            BNC:Push({
                event = "left",
                module = MODULE_ID,
                title = "Left Instance",
                message = currentInstance,
                icon = ICON_DUNGEON,
                priority = "low",
                duration = GetSetting("toastDuration") or 3,
                silent = GetSetting("leftToasts") == false,
            })
        end
        currentInstance = nil
    end
end

local function OnEncounterStart(event, encounterID, encounterName, difficultyID, groupSize)
    if GetSetting("showEncounters") == false then return end
    encounterStartTime = GetTime()

    BNC:Push({
        event = "encounters",
        module = MODULE_ID,
        title = "Encounter Started",
        message = encounterName or "Boss",
        icon = ICON_BOSS_KILL,
        priority = "normal",
        duration = GetSetting("toastDuration") or 3,
        silent = GetSetting("encounterToasts") == false,
    })
end

local function OnEncounterEnd(event, encounterID, encounterName, difficultyID, groupSize, success)
    if GetSetting("showEncounters") == false then return end

    local elapsed = ""
    if encounterStartTime then
        local secs = math.floor(GetTime() - encounterStartTime)
        local mins = math.floor(secs / 60)
        secs = secs % 60
        elapsed = string.format(" (%d:%02d)", mins, secs)
        encounterStartTime = nil
    end

    if success == 1 then
        BNC:Push({
            event = "encounters",
            module = MODULE_ID,
            title = "Boss Defeated!",
            message = (encounterName or "Boss") .. elapsed,
            icon = ICON_BOSS_KILL,
            priority = "high",
            duration = GetSetting("toastDuration") or 5,
            silent = GetSetting("encounterToasts") == false,
        })
    else
        BNC:Push({
            event = "encounters",
            module = MODULE_ID,
            title = "Encounter Failed",
            message = (encounterName or "Boss") .. elapsed,
            icon = ICON_WIPE,
            priority = "normal",
            duration = GetSetting("toastDuration") or 4,
            silent = GetSetting("encounterToasts") == false,
        })
    end
end

local function OnLFGProposalShow()
    if GetSetting("showQueuePop") == false then return end

    BNC:Push({
        event = "queue",
        module = MODULE_ID,
        title = "Queue Ready!",
        message = "Your group has been found",
        icon = ICON_QUEUE,
        priority = "high",
        duration = GetSetting("toastDuration") or 8,
        silent = GetSetting("queueToasts") == false,
    })
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("LFG_PROPOSAL_SHOW")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(0.5, CheckInstanceChange)
    elseif event == "ENCOUNTER_START" then
        OnEncounterStart(event, ...)
    elseif event == "ENCOUNTER_END" then
        OnEncounterEnd(event, ...)
    elseif event == "LFG_PROPOSAL_SHOW" then
        OnLFGProposalShow()
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { type = "event", key = "entered",    label = "Entering an instance", show = "showEntered",    toast = "enteredToasts" },
    { type = "event", key = "left",       label = "Leaving an instance",  show = "showLeft",       toast = "leftToasts" },
    { type = "event", key = "encounters", label = "Boss encounters",      show = "showEncounters", toast = "encounterToasts" },
    { type = "event", key = "queue",      label = "Queue pop",            show = "showQueuePop",   toast = "queueToasts" },
    { key = "toastDuration",    label = "Toast duration", type = "slider", default = 4, min = 1, max = 15, step = 1 },
})
