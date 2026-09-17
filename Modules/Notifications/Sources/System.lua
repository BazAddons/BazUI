-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-System: UI error/info messages, boss emotes, raid warnings, event toasts.
-- Events: PLAYER_ENTERING_WORLD, RAID_BOSS_EMOTE, RAID_BOSS_WHISPER
-- ==========================================================================

local MODULE_ID = "system"
local MODULE_NAME = "System Messages"
local MODULE_ICON = "Interface\\Icons\\INV_Misc_Note_01"

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

local CATEGORY_PATTERNS = {
    danger = {
        "guard", "territory", "attacked", "hostile", "pvp",
        "duel", "sanctuary", "contested",
    },
    errors = {
        "can't do that", "not enough", "requires", "must be",
        "too far", "invalid", "no target", "out of range",
        "interrupted", "failed", "cooldown", "not ready",
        "inventory is full", "bags are full",
    },
    info = {
        "discovered", "entered", "reputation", "skill",
        "you are now", "has been added", "joined", "left",
        "rested", "logout",
    },
}

local function CategorizeMessage(msg)
    local lowerMsg = BNC.SafeLower(msg)
    if not lowerMsg then return "info" end
    for category, patterns in pairs(CATEGORY_PATTERNS) do
        for _, pattern in ipairs(patterns) do
            if BNC.SafeFind(lowerMsg, pattern, 1, true) then
                return category
            end
        end
    end
    return "info"
end

local function GetPriorityForCategory(category)
    if category == "danger" then return "high" end
    if category == "errors" then return "normal" end
    return "low"
end

local function GetIconForCategory(category)
    if category == "danger" then
        return "Interface\\Icons\\Ability_Rogue_Sprint"
    elseif category == "errors" then
        return "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    return MODULE_ICON
end

local msgDedup = BNC:CreateDeduplicator(2)

-- Hook UIErrorsFrame, RaidBossEmoteFrame, RaidWarningFrame, EventToastManagerFrame
local hooked = false

local function SetupHook()
    if hooked then return end
    hooked = true

    local function InterceptMessage(origFunc, self, msg, r, g, b, ...)
        if not msg or msg == "" then
            return origFunc(self, msg, r, g, b, ...)
        end

        -- Skip quest progress messages (BNC-Quests handles these)
        if BNC.SafeMatch(msg, "%d+/%d+") then
            if GetSetting("hideDefaultText") ~= false then
                return
            end
            return origFunc(self, msg, r, g, b, ...)
        end

        -- Two separate questions, which used to be one.
        --
        -- Whether we raise a notification of our own is the Toast
        -- switch. Whether Blizzard's red text still appears in the
        -- middle of the screen is the Default switch. Deciding both from
        -- the first meant turning a category's toast off handed the
        -- message back to Blizzard, so "You have no target" came up in
        -- the middle of the screen with all three switches unticked -
        -- the one arrangement that plainly means show me nothing.
        local category = CategorizeMessage(msg)
        local raise = true

        if category == "danger" and GetSetting("showDanger") == false then
            raise = false
        elseif category == "errors" and GetSetting("showErrors") == false then
            raise = false
        elseif category == "info" and GetSetting("showInfo") == false then
            raise = false
        end

        if raise then
            -- A repeat inside the dedup window gets no second card, but
            -- it must still be hidden: letting it fall through here is
            -- how "Spell is not ready yet" showed up in red after the
            -- first press had already been captured.
            if not msgDedup:IsDuplicate(msg) then
                BNC:Push({
                    event = "info",
                    module = MODULE_ID,
                    title = msg,
                    message = "",
                    icon = GetIconForCategory(category),
                    priority = GetPriorityForCategory(category),
                    duration = GetSetting("toastDuration") or 4,
                    silent = GetSetting("toastsEnabled") == false,
                })
            end
        end

        -- Blizzard's own display, asked once, whatever we did above.
        if GetSetting("hideDefaultText") ~= false then
            return
        end

        return origFunc(self, msg, r, g, b, ...)
    end

    local origUIErrors = UIErrorsFrame.AddMessage
    UIErrorsFrame.AddMessage = function(self, msg, r, g, b, ...)
        return InterceptMessage(origUIErrors, self, msg, r, g, b, ...)
    end

    if RaidBossEmoteFrame then
        local origRaidBoss = RaidBossEmoteFrame.AddMessage
        if origRaidBoss then
            RaidBossEmoteFrame.AddMessage = function(self, msg, r, g, b, ...)
                return InterceptMessage(origRaidBoss, self, msg, r, g, b, ...)
            end
        end

        BazUI.SuppressFrame(RaidBossEmoteFrame, function()
            return GetSetting("hideDefaultText") ~= false
        end)
    end

    if RaidWarningFrame then
        local origRaidWarn = RaidWarningFrame.AddMessage
        if origRaidWarn then
            RaidWarningFrame.AddMessage = function(self, msg, r, g, b, ...)
                return InterceptMessage(origRaidWarn, self, msg, r, g, b, ...)
            end
        end
    end

    if EventToastManagerFrame then
        -- Watched through the event, not by hooking their method.
        --
        -- This used to hooksecurefunc EventToastManagerFrame:DisplayToast.
        -- That writes to the frame's method table, and on Forever their
        -- own OnEvent then found DisplayToast nil. DISPLAY_EVENT_TOASTS is
        -- the same event that makes them call it, so we listen for it and
        -- read the toast they put up, touching nothing of theirs.
        --
        -- A tick later, because the toast is chosen inside their handler:
        -- currentDisplayingToast is not set yet when the event arrives.
        local toastWatcher = CreateFrame("Frame")
        toastWatcher:RegisterEvent("DISPLAY_EVENT_TOASTS")
        toastWatcher:SetScript("OnEvent", function()
            C_Timer.After(0, function()
            local self = EventToastManagerFrame
            if GetSetting("showEventToasts") == false then return end

            local title = ""
            local message = ""

            local toast = self.currentDisplayingToast
            local hasDetails = false
            if toast then
                local texts = {}
                for _, region in ipairs({toast:GetRegions()}) do
                    if region.GetText then
                        local text = region:GetText()
                        if text and text ~= "" then
                            local lowerText = BNC.SafeLower(text)
                            if lowerText and BNC.SafeFind(lowerText, "click") and BNC.SafeFind(lowerText, "detail") then
                                hasDetails = true
                            else
                                table.insert(texts, text)
                            end
                        end
                    end
                end
                if texts[1] then title = texts[1] end
                if texts[2] then message = texts[2] end
            end

            title = BNC.StripEscapes(title)
            message = BNC.StripEscapes(message)

            if title == "" and message == "" then
                title = "Event"
            end

            if not msgDedup:IsDuplicate(title .. message) then
                BNC:Push({
                    event = "banners",
                    module = MODULE_ID,
                    title = title,
                    message = message,
                    icon = "Interface\\Icons\\Achievement_General",
                    priority = "normal",
                    duration = GetSetting("toastDuration") or 5,
                    silent = GetSetting("toastsEnabled") == false,
                })
            end

            -- Only suppress simple toasts; leave interactive ones visible
            if not hasDetails and GetSetting("hideDefaultText") ~= false then
                if self.currentDisplayingToast then
                    self.currentDisplayingToast:Hide()
                end
                self:Hide()
                C_Timer.After(0.05, function()
                    if self.currentDisplayingToast then
                        self.currentDisplayingToast:Hide()
                    end
                    self:Hide()
                end)
                C_Timer.After(0.2, function()
                    if self.currentDisplayingToast then
                        self.currentDisplayingToast:Hide()
                    end
                    self:Hide()
                end)
            end
            end)
        end)
    end
end

local function OnRaidBossEmote(event, msg, ...)
    if GetSetting("showBossEmotes") == false then return end
    if not msg or msg == "" then return end

    local cleanMsg = BNC.StripEscapes(msg)
    cleanMsg = BNC.SafeGsub(cleanMsg, "%%s", "") or cleanMsg
    cleanMsg = BNC.SafeGsub(cleanMsg, "  +", " ") or cleanMsg
    cleanMsg = BNC.SafeGsub(cleanMsg, "^%s+", "") or cleanMsg
    cleanMsg = BNC.SafeGsub(cleanMsg, "%s+$", "") or cleanMsg
    if cleanMsg == "" then return end

    if msgDedup:IsDuplicate(cleanMsg) then return end

    BNC:Push({
        event = "emotes",
        module = MODULE_ID,
        title = cleanMsg,
        message = "",
        icon = "Interface\\Icons\\Ability_Rogue_Sprint",
        priority = "high",
        duration = GetSetting("toastDuration") or 4,
        silent = GetSetting("toastsEnabled") == false,
    })
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("RAID_BOSS_EMOTE")
eventFrame:RegisterEvent("RAID_BOSS_WHISPER")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        SetupHook()
    elseif event == "RAID_BOSS_EMOTE" or event == "RAID_BOSS_WHISPER" then
        OnRaidBossEmote(event, ...)
    end
end)

BNC:RegisterModule({
    id = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { type = "event", key = "danger",  label = "Danger and PvP warnings", show = "showDanger", blizzard = "hideDefaultText" },
    { type = "event", key = "errors",  label = "Error messages",          show = "showErrors", blizzard = "hideDefaultText" },
    { type = "event", key = "info",    label = "Info messages",           show = "showInfo", blizzard = "hideDefaultText" },
    { type = "event", key = "emotes",  label = "Zone and boss warnings",  show = "showBossEmotes", blizzard = "hideDefaultText" },
    { type = "event", key = "raid",    label = "Raid warnings",           show = "showRaidWarnings", blizzard = "hideDefaultText" },
    { type = "event", key = "banners", label = "Event banners",           show = "showEventToasts", blizzard = "hideDefaultText" },
    { key = "toastDuration",    label = "Toast duration", type = "slider", default = 4, min = 1, max = 15, step = 1 },
})
