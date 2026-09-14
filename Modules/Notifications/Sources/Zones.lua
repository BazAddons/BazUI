-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Zones: Replaces Blizzard zone/subzone text with toast notifications.
-- Events: ZONE_CHANGED_NEW_AREA, ZONE_CHANGED, ZONE_CHANGED_INDOORS
-- ==========================================================================

local MODULE_ID = "zones"
local MODULE_NAME = "Zone Alerts"
local MODULE_ICON = "Interface\\Icons\\INV_Misc_Map_01"

local SUPPRESSED_FRAMES = {
    "ZoneTextFrame",
    "SubZoneTextFrame",
}

local lastZone = ""
local lastSubZone = ""

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local function OnZoneChanged()
    if GetSetting("showZones") == false then return end

    local zone = GetZoneText()
    if zone and zone ~= "" and zone ~= lastZone then
        lastZone = zone

        local subZone = GetSubZoneText()
        local message = (subZone and subZone ~= "") and subZone or ""

        BNC:Push({
            module = MODULE_ID,
            title = zone,
            message = message,
            icon = MODULE_ICON,
            priority = "normal",
            duration = GetSetting("toastDuration") or 4,
            silent = GetSetting("zoneToasts") == false,
        })
    end
end

local function OnSubZoneChanged()
    if GetSetting("showSubzones") == false then return end

    local subZone = GetSubZoneText()
    if subZone and subZone ~= "" and subZone ~= lastSubZone then
        lastSubZone = subZone

        BNC:Push({
            module = MODULE_ID,
            title = subZone,
            message = GetZoneText() or "",
            icon = MODULE_ICON,
            priority = "low",
            duration = GetSetting("toastDuration") or 3,
            silent = GetSetting("subzoneToasts") == false,
        })
    end
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")

eventFrame:SetScript("OnEvent", function(self, event)
    if event == "ZONE_CHANGED_NEW_AREA" then
        OnZoneChanged()
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        OnSubZoneChanged()
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { type = "event", key = "zones",    label = "Zone changes",    show = "showZones",    toast = "zoneToasts" },
    { type = "event", key = "subzones", label = "Subzone changes", show = "showSubzones", toast = "subzoneToasts" },
    { key = "toastDuration",    label = "Toast duration", type = "slider", default = 4, min = 1, max = 15, step = 1 },
})

for _, frameName in ipairs(SUPPRESSED_FRAMES) do
    BNC:SuppressBlizzardFrame(frameName)
end
