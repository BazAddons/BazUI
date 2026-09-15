-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Dungeon Finder
--
-- Queue status panel showing role fills, wait time, queue timer, and
-- dungeon name. Auto-shows when queued via LFG, auto-hides when not.
-- Replaces the standalone BazDungeonFinder addon's bar with a dockable
-- BazUI Drawers widget. Includes all queue data polling inline so no
-- external addon dependency is needed.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID     = "bazdrawer_dungeonfinder"
local DESIGN_WIDTH  = 260
local DESIGN_HEIGHT = 76
local PAD           = 8
local ICON_SIZE     = 16

-- Colors
local CLR_TITLE   = { 0.9, 0.8, 0.5 }
local CLR_GREEN   = { 0.2, 1.0, 0.2 }
local CLR_DIM     = { 0.5, 0.5, 0.55 }
local CLR_ACCENT  = { 0.4, 0.8, 1.0 }
local CLR_FILLED  = { 0.3, 0.85, 0.3 }
local CLR_TANK    = { 0.2, 0.6, 1.0 }
local CLR_HEALER  = { 0.1, 0.9, 0.2 }
local CLR_DPS     = { 0.9, 0.3, 0.3 }
local ROLE_ATLASES = { tank = "roleicon-tiny-tank", healer = "roleicon-tiny-healer", dps = "roleicon-tiny-dps" }
local ROLE_COLORS  = { tank = CLR_TANK, healer = CLR_HEALER, dps = CLR_DPS }

local DFWidget = {}
addon.DungeonFinderWidget = DFWidget

---------------------------------------------------------------------------
-- Queue data (self-contained, no BazDungeonFinder dependency)
---------------------------------------------------------------------------

local LFG_CAT_LFD = 1
local LFG_CAT_RF  = 3

local Q = {
    isQueued = false, category = nil,
    queuedTime = 0, queueStartTime = 0,
    myWait = 0, averageWait = 0,
    tankNeeds = 0, healerNeeds = 0, dpsNeeds = 0,
    totalTanks = 0, totalHealers = 0, totalDPS = 0,
    dungeonName = "", proposalActive = false,
}

local function FindActiveCategory()
    for _, cat in ipairs({ LFG_CAT_LFD, LFG_CAT_RF }) do
        local mode = GetLFGMode(cat)
        if mode and mode ~= "none" then return cat end
    end
end

local function GetActiveQueueID(cat)
    local id = GetPartyLFGID and GetPartyLFGID()
    if id and id > 0 then return id end
    if GetLFGQueuedList then
        local list = GetLFGQueuedList(cat)
        if list and #list > 0 then return list[1] end
    end
end

local function UpdateQueue()
    local cat = FindActiveCategory()
    if not cat then
        Q.isQueued = false
        Q.category = nil
        Q.queuedTime = 0
        Q.queueStartTime = 0
        return
    end

    local wasQueued = Q.isQueued
    Q.category = cat
    Q.isQueued = true

    if not wasQueued then
        Q.queueStartTime = GetTime()
        Q.queuedTime = 0
        Q.myWait = 0
        Q.averageWait = 0
        Q.tankNeeds = 0
        Q.healerNeeds = 0
        Q.dpsNeeds = 0
        Q.totalTanks = 0
        Q.totalHealers = 0
        Q.totalDPS = 0
        Q.dungeonName = ""
    end

    Q.queuedTime = GetTime() - Q.queueStartTime

    local hasData, _, tankNeeds, healerNeeds, dpsNeeds,
          totalTanks, totalHealers, totalDPS, _, _,
          instanceName, averageWait, _, _, _,
          myWait = GetLFGQueueStats(cat, GetActiveQueueID(cat))

    if hasData then
        Q.myWait = myWait or 0
        Q.averageWait = averageWait or 0
        Q.tankNeeds = tankNeeds or 0
        Q.healerNeeds = healerNeeds or 0
        Q.dpsNeeds = dpsNeeds or 0
        Q.totalTanks = totalTanks or 0
        Q.totalHealers = totalHealers or 0
        Q.totalDPS = totalDPS or 0
        Q.dungeonName = instanceName or ""
    end
end


local function FormatEstimate(seconds)
    if not seconds or seconds <= 0 then return "N/A" end
    local m = math.floor(seconds / 60)
    if m < 1 then return "< 1 Min" end
    if m >= 60 then
        return string.format("%d Hr %d Min", math.floor(m / 60), m % 60)
    end
    return string.format("%d Min", m)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local frame

function DFWidget:Build()
    if frame then return frame end

    local f = CreateFrame("Frame", "BazUIDrawerDungeonFinderWidget", UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)
    frame = f

    -- Title: "Dungeon Finder" / "Group Found!"
    f.title = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "TOP", 0, -PAD)
    f.title:SetJustifyH("CENTER")
    f.title:SetTextColor(unpack(CLR_TITLE))
    f.title:SetText("Dungeon Finder")

    -- Dungeon name subtitle
    f.dungeon = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.dungeon:SetPoint("TOP", f.title, "BOTTOM", 0, -2)
    f.dungeon:SetJustifyH("CENTER")
    f.dungeon:SetTextColor(unpack(CLR_DIM))

    -- Leave queue button (top right)
    f.leaveBtn = CreateFrame("Button", nil, f)
    f.leaveBtn:SetSize(14, 14)
    f.leaveBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD)
    f.leaveBtn.tex = f.leaveBtn:CreateTexture(nil, "ARTWORK")
    f.leaveBtn.tex:SetAllPoints()
    f.leaveBtn.tex:SetAtlas("common-icon-redx")
    f.leaveBtn.tex:SetVertexColor(0.7, 0.3, 0.3)
    f.leaveBtn:SetScript("OnClick", function()
        if Q.category then LeaveLFG(Q.category) end
    end)
    f.leaveBtn:SetScript("OnEnter", function(self)
        self.tex:SetVertexColor(1, 0.4, 0.4)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Leave Queue")
        GameTooltip:Show()
    end)
    f.leaveBtn:SetScript("OnLeave", function(self)
        self.tex:SetVertexColor(0.7, 0.3, 0.3)
        GameTooltip:Hide()
    end)

    -- Role slots row
    f.roles = {}
    local rolesY = -32
    local roleX = PAD
    for _, def in ipairs({ "tank", "healer", "dps" }) do
        local slot = {}
        slot.icon = f:CreateTexture(nil, "ARTWORK")
        slot.icon:SetSize(ICON_SIZE, ICON_SIZE)
        slot.icon:SetPoint("TOPLEFT", f, "TOPLEFT", roleX, rolesY)
        slot.icon:SetAtlas(ROLE_ATLASES[def])

        slot.text = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
        slot.text:SetPoint("LEFT", slot.icon, "RIGHT", 3, 0)
        slot.text:SetText("0/0")

        slot.role = def
        f.roles[def] = slot
        roleX = roleX + ICON_SIZE + 3 + 22 + 8
    end

    -- Avg Wait (right side of role row)
    f.avgWaitLabel = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.avgWaitLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, rolesY + 2)
    f.avgWaitLabel:SetJustifyH("RIGHT")
    f.avgWaitLabel:SetTextColor(unpack(CLR_DIM))

    -- In Queue timer (bottom center)
    f.queueLabel = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.queueLabel:SetPoint("TOP", f, "TOP", 0, rolesY - ICON_SIZE - 6)
    f.queueLabel:SetJustifyH("CENTER")
    f.queueLabel:SetTextColor(unpack(CLR_DIM))

    -- (No "Not queued" state needed - dormant widget disappears entirely)

    -- 1-second timer for live updates
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        if Q.isQueued and Q.queueStartTime > 0 then
            Q.queuedTime = GetTime() - Q.queueStartTime
            UpdateQueue()
            DFWidget:Refresh()
        end
    end)

    self._desiredHeight = DESIGN_HEIGHT
    return f
end

---------------------------------------------------------------------------
-- Refresh display
---------------------------------------------------------------------------

function DFWidget:Refresh()
    if not frame then return end

    -- Widget is dormant when not queued, so if we're here we're queued
    frame.title:Show()
    frame.dungeon:Show()
    frame.leaveBtn:Show()
    frame.queueLabel:Show()
    frame.avgWaitLabel:Show()

    -- Title
    if Q.proposalActive then
        frame.title:SetTextColor(unpack(CLR_GREEN))
        frame.title:SetText("Group Found!")
    else
        frame.title:SetTextColor(unpack(CLR_TITLE))
        frame.title:SetText("Dungeon Finder")
    end

    -- Dungeon name
    frame.dungeon:SetText(Q.dungeonName ~= "" and Q.dungeonName or "")

    -- Role slots
    for _, def in ipairs({ "tank", "healer", "dps" }) do
        local slot = frame.roles[def]
        local total, needs
        if def == "tank" then total, needs = Q.totalTanks, Q.tankNeeds
        elseif def == "healer" then total, needs = Q.totalHealers, Q.healerNeeds
        else total, needs = Q.totalDPS, Q.dpsNeeds end

        local max = total or 0
        local found = max - (needs or 0)
        slot.text:SetText(max > 0 and (found .. "/" .. max) or "0/0")

        if max > 0 and found >= max then
            slot.text:SetTextColor(unpack(CLR_FILLED))
            slot.icon:SetAlpha(1)
        else
            slot.text:SetTextColor(unpack(ROLE_COLORS[def]))
            slot.icon:SetAlpha(0.5)
        end
        slot.icon:Show()
        slot.text:Show()
    end

    -- Avg wait
    local waitTime = Q.myWait > 0 and Q.myWait or Q.averageWait
    frame.avgWaitLabel:SetText("Avg Wait: |cffffffff" .. FormatEstimate(waitTime) .. "|r")

    -- Queue time
    frame.queueLabel:SetText("In Queue: |cff66ccff" .. BazUI:FormatTime(Q.queuedTime) .. "|r")

    self._desiredHeight = DESIGN_HEIGHT
end

---------------------------------------------------------------------------
-- Widget interface
---------------------------------------------------------------------------

function DFWidget:GetDesiredHeight()
    return self._desiredHeight or DESIGN_HEIGHT
end

function DFWidget:GetStatusText()
    return BazUI:FormatTime(Q.queuedTime), unpack(CLR_ACCENT)
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function DFWidget:Init()
    local f = self:Build()

    local widgetDef = {
        id           = WIDGET_ID,
        label        = "Dungeon Finder",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return DFWidget:GetDesiredHeight() end,
        GetStatusText    = function() return DFWidget:GetStatusText() end,
    }

    -- Dormant widget: only registers when actively queued for a dungeon.
    -- When not queued the widget has no slot, no title bar, no space.
    local LBW = BazUI.Widgets
    LBW:RegisterDormantWidget(widgetDef, {
        events = {
            "LFG_UPDATE",
            "LFG_QUEUE_STATUS_UPDATE",
            "LFG_PROPOSAL_SHOW",
            "LFG_PROPOSAL_DONE",
            "LFG_PROPOSAL_FAILED",
            "LFG_PROPOSAL_SUCCEEDED",
            "LFG_COMPLETION_REWARD",
            "UPDATE_BATTLEFIELD_STATUS",
            "PLAYER_ENTERING_WORLD",
        },
        condition = function()
            UpdateQueue()
            return Q.isQueued
        end,
    })

    -- Separate event listener for refresh/proposal state (runs even
    -- while the widget is active and registered)
    f:RegisterEvent("LFG_UPDATE")
    f:RegisterEvent("LFG_QUEUE_STATUS_UPDATE")
    f:RegisterEvent("LFG_PROPOSAL_SHOW")
    f:RegisterEvent("LFG_PROPOSAL_DONE")
    f:RegisterEvent("LFG_PROPOSAL_FAILED")
    f:RegisterEvent("LFG_PROPOSAL_SUCCEEDED")
    f:RegisterEvent("LFG_COMPLETION_REWARD")
    f:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")

    f:HookScript("OnEvent", function(_, event)
        if event == "LFG_PROPOSAL_SHOW" then
            Q.proposalActive = true
        elseif event == "LFG_PROPOSAL_SUCCEEDED" or event == "LFG_PROPOSAL_FAILED"
            or event == "LFG_PROPOSAL_DONE" or event == "LFG_COMPLETION_REWARD" then
            Q.proposalActive = false
        end

        UpdateQueue()
        DFWidget:Refresh()

        if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
            addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
        end
        if addon.WidgetHost and addon.WidgetHost.Reflow then
            addon.WidgetHost:Reflow()
        end
    end)

    -- Initial check
    UpdateQueue()
    self:Refresh()
end

BazUI:QueueForModule("Drawers", function()
    C_Timer.After(0.3, function() DFWidget:Init() end)
end)
