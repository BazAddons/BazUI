-- SPDX-License-Identifier: GPL-2.0-or-later
-- QuestTracker: Challenge Mode (M+) Block
-- Dedicated frame for Mythic+ dungeon runs: timer bar, keystone level,
-- affix icons, and death counter. Completely separate rendering path
-- from the generic scenario block because the layout is fundamentally
-- different (live timer + affix ring vs. static boss list).
--
-- APIs used:
--   C_ChallengeMode.IsChallengeModeActive()
--   C_ChallengeMode.GetActiveKeystoneInfo() > level, affixIDs, wasEnergized
--   C_ChallengeMode.GetActiveChallengeMapID()
--   C_ChallengeMode.GetMapUIInfo(mapID) > name, _, timeLimit
--   C_ChallengeMode.GetDeathCount() > count, timeLost
--   C_ChallengeMode.GetAffixInfo(affixID) > name, desc, textureID
--   GetWorldElapsedTimerInfo(timerID) > returns elapsed, type
--   GetWorldElapsedTime(timerID) > elapsed seconds

local addon = BazUI:GetModule("Drawers")
if not addon then return end
local QT = addon.QT
local C  = QT.C

local cmBlock = nil      -- dedicated frame (not from block pool)
local cmTimerID = nil    -- world elapsed timer ID for the active key

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function QT.IsChallengeModeActive()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
end

local function SecondsToClock(seconds)
    if not seconds or seconds < 0 then seconds = 0 end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%d:%02d", m, s)
end

local function TimerColor(remaining, total)
    if total <= 0 then return 0.8, 0.8, 0.8 end
    local pct = remaining / total
    if pct > 0.4 then return 0.1, 0.75, 0.1 end   -- green
    if pct > 0.2 then return 1.0, 0.82, 0.0 end    -- gold/yellow
    return 1.0, 0.2, 0.2                            -- red
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

function QT.GetChallengeModeData()
    if not QT.IsChallengeModeActive() then return nil end

    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if not mapID then return nil end

    local level, affixIDs = C_ChallengeMode.GetActiveKeystoneInfo()
    local mapName, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    local deathCount, timeLost = C_ChallengeMode.GetDeathCount()

    -- Find the active timer
    local elapsed = 0
    if not cmTimerID then
        for i = 1, 5 do
            local info = GetWorldElapsedTimerInfo and GetWorldElapsedTimerInfo(i)
            if info and info.type == _G.LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE then
                cmTimerID = i
                break
            end
        end
    end
    if cmTimerID and GetWorldElapsedTime then
        local ok, e = pcall(GetWorldElapsedTime, cmTimerID)
        if ok and e then elapsed = e end
    end

    -- Affix info
    local affixes = {}
    if affixIDs then
        for _, id in ipairs(affixIDs) do
            if C_ChallengeMode.GetAffixInfo then
                local name, desc, tex = C_ChallengeMode.GetAffixInfo(id)
                if name then
                    affixes[#affixes + 1] = {
                        id      = id,
                        name    = name,
                        desc    = desc,
                        texture = tex,
                    }
                end
            end
        end
    end

    return {
        mapName    = mapName or "",
        level      = level or 0,
        timeLimit  = timeLimit or 0,
        elapsed    = elapsed,
        deathCount = deathCount or 0,
        timeLost   = timeLost or 0,
        affixes    = affixes,
    }
end

---------------------------------------------------------------------------
-- Frame creation
---------------------------------------------------------------------------

local BLOCK_WIDTH = C.DESIGN_WIDTH - C.PAD * 2
local AFFIX_SIZE  = 22
local AFFIX_GAP   = 4
local DEATH_SIZE  = 16

function QT.CreateChallengeModeBlock()
    if cmBlock then return cmBlock end

    local f = CreateFrame("Frame", nil, QT.scrollChild or QT.frame)
    f:SetWidth(BLOCK_WIDTH)

    -- Keystone level (top-right corner)
    f.level = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.level:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.level:SetTextColor(1.0, 0.82, 0.0)

    -- Dungeon name (top-left, to the left of level)
    f.name = f:CreateFontString(nil, "OVERLAY")
    if _G[C.TITLE_FONT] then
        f.name:SetFontObject(_G[C.TITLE_FONT])
    else
        f.name:SetFontObject("GameFontNormal")
    end
    f.name:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.name:SetPoint("RIGHT", f.level, "LEFT", -8, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetTextColor(QT.GetTitleColor())

    -- Timer bar (below name)
    f.timerBar = CreateFrame("StatusBar", nil, f)
    f.timerBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -22)
    f.timerBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -22)
    f.timerBar:SetHeight(14)
    f.timerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.timerBar:SetStatusBarColor(0.0, 0.33, 0.61, 1)
    f.timerBar:SetMinMaxValues(0, 1)
    f.timerBar:SetValue(1)

    f.timerBar.bg = f.timerBar:CreateTexture(nil, "BACKGROUND")
    f.timerBar.bg:SetAllPoints()
    f.timerBar.bg:SetColorTexture(0.08, 0.08, 0.10, 0.7)

    f.timerBar.text = f.timerBar:CreateFontString(nil, "OVERLAY")
    if _G[C.OBJECTIVE_FONT] then
        f.timerBar.text:SetFontObject(_G[C.OBJECTIVE_FONT])
    else
        f.timerBar.text:SetFontObject("GameFontHighlightSmall")
    end
    f.timerBar.text:SetPoint("CENTER")
    f.timerBar.text:SetTextColor(1, 1, 1)

    -- Affix icons row (below timer)
    f.affixIcons = {}
    for i = 1, 4 do
        local icon = CreateFrame("Frame", nil, f)
        icon:SetSize(AFFIX_SIZE, AFFIX_SIZE)
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints()
        icon.tex:SetMask("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        icon:Hide()

        icon:SetScript("OnEnter", function(self)
            if self._affixName then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self._affixName, 1, 1, 1)
                if self._affixDesc then
                    GameTooltip:AddLine(self._affixDesc, nil, nil, nil, true)
                end
                GameTooltip:Show()
            end
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        icon:EnableMouse(true)

        f.affixIcons[i] = icon
    end

    -- Death counter (right of affixes)
    f.deathFrame = CreateFrame("Frame", nil, f)
    f.deathFrame:SetSize(60, DEATH_SIZE)

    f.deathFrame.icon = f.deathFrame:CreateTexture(nil, "ARTWORK")
    f.deathFrame.icon:SetSize(DEATH_SIZE, DEATH_SIZE)
    f.deathFrame.icon:SetPoint("LEFT", 0, 0)
    f.deathFrame.icon:SetAtlas("poi-graveyard-neutral", false)

    f.deathFrame.text = f.deathFrame:CreateFontString(nil, "OVERLAY")
    if _G[C.OBJECTIVE_FONT] then
        f.deathFrame.text:SetFontObject(_G[C.OBJECTIVE_FONT])
    else
        f.deathFrame.text:SetFontObject("GameFontHighlightSmall")
    end
    f.deathFrame.text:SetPoint("LEFT", f.deathFrame.icon, "RIGHT", 4, 0)
    f.deathFrame.text:SetTextColor(1, 0.3, 0.3)

    f.deathFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Deaths", 1, 1, 1)
        if self._timeLost and self._timeLost > 0 then
            GameTooltip:AddLine("Time lost: " .. SecondsToClock(self._timeLost), 1, 0.3, 0.3)
        end
        GameTooltip:Show()
    end)
    f.deathFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.deathFrame:EnableMouse(true)

    -- OnUpdate for live timer
    local timerElapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        timerElapsed = timerElapsed + dt
        if timerElapsed < 0.1 then return end
        timerElapsed = 0
        QT.UpdateChallengeTimer()
    end)

    f:Hide()
    cmBlock = f
    return f
end

---------------------------------------------------------------------------
-- Populate / Update
---------------------------------------------------------------------------

function QT.PopulateChallengeModeBlock(data)
    local f = QT.CreateChallengeModeBlock()
    if not data then f:Hide(); return 0 end

    -- Name + level
    f.name:SetText(data.mapName)
    f.level:SetText("+" .. data.level)

    -- Affixes
    for i = 1, 4 do
        local icon = f.affixIcons[i]
        local affix = data.affixes[i]
        if affix then
            icon.tex:SetTexture(affix.texture)
            icon._affixName = affix.name
            icon._affixDesc = affix.desc
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", f, "TOPLEFT",
                (i - 1) * (AFFIX_SIZE + AFFIX_GAP), -40)
            icon:Show()
        else
            icon:Hide()
        end
    end

    -- Death counter (right-aligned on the affix row)
    f.deathFrame:ClearAllPoints()
    f.deathFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -40)
    f.deathFrame.text:SetText(tostring(data.deathCount))
    f.deathFrame._timeLost = data.timeLost
    f.deathFrame:Show()

    -- Timer
    QT.UpdateChallengeTimer()

    local totalH = 40 + AFFIX_SIZE + 8  -- name+timer + affix row + padding
    f:SetHeight(totalH)
    f:Show()
    return totalH
end

function QT.UpdateChallengeTimer()
    if not cmBlock or not cmBlock:IsShown() then return end
    if not cmTimerID then return end

    local elapsed = 0
    if GetWorldElapsedTime then
        local ok, e = pcall(GetWorldElapsedTime, cmTimerID)
        if ok and e then elapsed = e end
    end

    local data = QT._cmData
    if not data then return end

    local remaining = data.timeLimit - elapsed
    local pct = data.timeLimit > 0 and (remaining / data.timeLimit) or 0
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end

    cmBlock.timerBar:SetValue(pct)
    local r, g, b = TimerColor(remaining, data.timeLimit)
    cmBlock.timerBar:SetStatusBarColor(r, g, b, 1)

    if remaining >= 0 then
        cmBlock.timerBar.text:SetText(SecondsToClock(remaining))
    else
        cmBlock.timerBar.text:SetText("+" .. SecondsToClock(-remaining))
        cmBlock.timerBar.text:SetTextColor(1, 0.2, 0.2)
    end
end

---------------------------------------------------------------------------
-- Reset on key end
---------------------------------------------------------------------------

function QT.ResetChallengeMode()
    cmTimerID = nil
    QT._cmData = nil
    if cmBlock then cmBlock:Hide() end
end
