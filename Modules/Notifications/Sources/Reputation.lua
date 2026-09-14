-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Reputation: Reputation gains/losses, standing milestones.
-- Events: PLAYER_ENTERING_WORLD, CHAT_MSG_COMBAT_FACTION_CHANGE,
--         UPDATE_FACTION
-- ==========================================================================

local MODULE_ID = "reputation"
local MODULE_NAME = "Reputation"
local MODULE_ICON = "Interface\\Icons\\Achievement_Reputation_08"

local ICON_REP_GAIN = "Interface\\Icons\\Achievement_Reputation_08"
local ICON_REP_LOSS = "Interface\\Icons\\Ability_Creature_Cursed_01"
local ICON_MILESTONE = "Interface\\Icons\\Achievement_Reputation_01"

local STANDING_LABELS = {
    [1] = "Hated",
    [2] = "Hostile",
    [3] = "Unfriendly",
    [4] = "Neutral",
    [5] = "Friendly",
    [6] = "Honored",
    [7] = "Revered",
    [8] = "Exalted",
}

local standingCache = {}

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local repAccumulator = BNC:CreateAccumulator(1.5, function(data)
    for factionName, amount in pairs(data) do
        if GetSetting("showGains") ~= false then
            local sign = amount > 0 and "+" or ""
            BNC:Push({
                module = MODULE_ID,
                title = factionName,
                message = sign .. amount .. " reputation",
                icon = amount > 0 and ICON_REP_GAIN or ICON_REP_LOSS,
                priority = "low",
                duration = GetSetting("toastDuration") or 3,
                silent = GetSetting("gainToasts") == false,
            })
        end
    end
end)

local function OnFactionChange(event, msg)
    if not msg then return end

    local faction, amount = BNC.SafeMatch(msg, "Reputation with (.+) increased by (%d+)")
    if faction and amount then
        amount = tonumber(amount)
        repAccumulator:Add(faction, amount)
        return
    end

    faction, amount = BNC.SafeMatch(msg, "Reputation with (.+) decreased by (%d+)")
    if faction and amount then
        if GetSetting("showLosses") == false then return end
        amount = tonumber(amount)
        repAccumulator:Add(faction, -amount)
    end
end

-- Classic clients expose factions through GetFactionInfo; shape the result
-- like Retail's C_Reputation.GetFactionDataByIndex so the code below
-- reads the same on both.
local function NumFactions()
    if C_Reputation and C_Reputation.GetNumFactions then return C_Reputation.GetNumFactions() end
    return GetNumFactions()
end

local function FactionByIndex(i)
    if C_Reputation and C_Reputation.GetFactionDataByIndex then
        return C_Reputation.GetFactionDataByIndex(i)
    end
    local name, _, standingID, _, _, _, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i)
    if not name then return nil end
    return { name = name, reaction = standingID, isHeader = isHeader, factionID = factionID }
end

local function CheckStandingMilestones()
    if GetSetting("showMilestones") == false then return end

    local numFactions = NumFactions()
    for i = 1, numFactions do
        local factionData = FactionByIndex(i)
        if factionData and not factionData.isHeader and factionData.factionID then
            local name = factionData.name
            local standingID = factionData.reaction
            local factionID = factionData.factionID

            if name and standingID then
                local cached = standingCache[factionID]

                if cached and cached ~= standingID and standingID > cached then
                    local standingName = STANDING_LABELS[standingID] or ("Standing " .. standingID)

                    BNC:Push({
                        module = MODULE_ID,
                        title = name,
                        message = "Now " .. standingName .. "!",
                        icon = ICON_MILESTONE,
                        priority = "high",
                        duration = GetSetting("toastDuration") or 6,
                        silent = GetSetting("milestoneToasts") == false,
                    })
                end

                standingCache[factionID] = standingID
            end
        end
    end
end

local function InitStandingCache()
    wipe(standingCache)
    local numFactions = NumFactions()
    for i = 1, numFactions do
        local factionData = FactionByIndex(i)
        if factionData and not factionData.isHeader and factionData.factionID and factionData.reaction then
            standingCache[factionData.factionID] = factionData.reaction
        end
    end
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
eventFrame:RegisterEvent("UPDATE_FACTION")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, InitStandingCache)
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        OnFactionChange(event, ...)
    elseif event == "UPDATE_FACTION" then
        CheckStandingMilestones()
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { type = "event", key = "changes",    label = "Reputation gains and losses", show = { "showGains", "showLosses" }, toast = "gainToasts" },
    { type = "event", key = "milestones", label = "Standing milestones",         show = "showMilestones",              toast = "milestoneToasts" },
    { key = "toastDuration",    label = "Toast duration", type = "slider", default = 4, min = 1, max = 15, step = 1 },
})
