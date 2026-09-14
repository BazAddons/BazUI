-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Professions: Craft completions and skill level-up notifications.
-- Events: PLAYER_ENTERING_WORLD, SKILL_LINES_CHANGED, CHAT_MSG_LOOT,
--         TRADE_SKILL_CRAFT_BEGIN, TRADE_SKILL_CRAFT_COMPLETED
-- ==========================================================================

local MODULE_ID = "professions"
local MODULE_NAME = "Professions"
local MODULE_ICON = "Interface\\Icons\\INV_Misc_Wrench_01"

local ICON_CRAFT = "Interface\\Icons\\INV_Misc_Wrench_01"
local ICON_SKILL = "Interface\\Icons\\INV_Scroll_02"

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local isCrafting = false

local function OnCraftBegin(event)
    isCrafting = true
end

local function OnCraftEnd(event)
    if not isCrafting then return end
    isCrafting = false
end

local lastSkillLevels = {}

local function CacheSkillLevels()
    wipe(lastSkillLevels)
    local professions = { GetProfessions() }
    for _, idx in pairs(professions) do
        if idx then
            local name, icon, skillLevel, maxLevel, _, _, skillLine = GetProfessionInfo(idx)
            if name and skillLine then
                lastSkillLevels[skillLine] = { name = name, icon = icon, level = skillLevel, max = maxLevel }
            end
        end
    end
end

local function CheckSkillUps()
    if GetSetting("showSkillUps") == false then return end

    local professions = { GetProfessions() }
    for _, idx in pairs(professions) do
        if idx then
            local name, icon, skillLevel, maxLevel, _, _, skillLine = GetProfessionInfo(idx)
            if name and skillLine then
                local cached = lastSkillLevels[skillLine]
                if cached and skillLevel > cached.level then
                    BNC:Push({
                        module = MODULE_ID,
                        title = name .. " Skill Up!",
                        message = cached.level .. " -> " .. skillLevel .. " / " .. maxLevel,
                        icon = icon and tostring(icon) or ICON_SKILL,
                        priority = "normal",
                        duration = GetSetting("skillUpDuration") or 4,
                        silent = GetSetting("skillUpToasts") == false,
                    })
                end
                lastSkillLevels[skillLine] = { name = name, icon = icon, level = skillLevel, max = maxLevel }
            end
        end
    end
end

local function OnChatMsgLoot(event, msg)
    if GetSetting("showCrafts") == false then return end

    local itemLink = BNC.SafeMatch(msg, "You create: (|c%x+|Hitem.-%|h%[.-%]|h|r)")
    if not itemLink then return end

    local itemName = BNC.SafeMatch(itemLink, "%[(.-)%]") or "Item"
    local _, _, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemLink)

    BNC:Push({
        module = MODULE_ID,
        title = "Crafted",
        message = itemName,
        icon = itemTexture or ICON_CRAFT,
        priority = "low",
        duration = GetSetting("craftDuration") or 3,
        silent = GetSetting("craftToasts") == false,
        itemLink = itemLink,
    })
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("SKILL_LINES_CHANGED")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")

pcall(function() eventFrame:RegisterEvent("TRADE_SKILL_CRAFT_BEGIN") end)
pcall(function() eventFrame:RegisterEvent("TRADE_SKILL_CRAFT_COMPLETED") end)

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, CacheSkillLevels)
    elseif event == "SKILL_LINES_CHANGED" then
        CheckSkillUps()
    elseif event == "CHAT_MSG_LOOT" then
        local msg = ...
        if msg and BNC.SafeMatch(msg, "You create") then
            OnChatMsgLoot(event, msg)
        end
    elseif event == "TRADE_SKILL_CRAFT_BEGIN" then
        OnCraftBegin(event)
    elseif event == "TRADE_SKILL_CRAFT_COMPLETED" then
        OnCraftEnd(event)
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { key = "showCrafts",       label = "Show Craft Completed",       type = "toggle", default = true },
    { key = "showSkillUps",     label = "Show Skill Level Ups",       type = "toggle", default = true },
    { key = "craftToasts",      label = "Toast on Craft",             type = "toggle", default = true },
    { key = "skillUpToasts",    label = "Toast on Skill Up",          type = "toggle", default = true },
    { key = "craftDuration",    label = "Craft Toast Duration",       type = "slider", default = 3, min = 1, max = 15, step = 1 },
    { key = "skillUpDuration",  label = "Skill Up Toast Duration",    type = "slider", default = 4, min = 1, max = 15, step = 1 },
})
