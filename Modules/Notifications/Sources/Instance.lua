-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Instance: Alerts for entering and leaving dungeons and raids.
-- Events: PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA
-- ==========================================================================

local MODULE_ID = "instance"
local MODULE_NAME = "Instance"
local MODULE_ICON = "Interface\\Icons\\INV_Misc_Key_10"

local ICON_DUNGEON = "Interface\\Icons\\INV_Misc_Key_10"
local ICON_RAID = "Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster"

local currentInstance = nil

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

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(0.5, CheckInstanceChange)
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
    { key = "toastDuration",    label = "Toast duration", type = "slider", default = 4, min = 1, max = 15, step = 1 },
})
