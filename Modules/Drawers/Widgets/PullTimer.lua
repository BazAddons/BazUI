-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Pull Timer
--
-- Dormant widget that auto-shows when you enter combat, tracks how long
-- the fight has lasted, and disappears when combat ends.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_pulltimer"
local DESIGN_WIDTH = 200
local DESIGN_HEIGHT = 44
local PAD          = 8

local CLR_TIME   = { 1.00, 0.95, 0.85 }
local CLR_LABEL  = { 0.85, 0.85, 0.85 }
local CLR_RED    = { 1.00, 0.40, 0.40 }
local CLR_SWORDS = { 1.00, 0.82, 0.00 }

local Pull = {}
addon.PullTimerWidget = Pull

local inCombat = false
local combatStart = 0


---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local frame

function Pull:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- Crossed-swords icon (left)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(28, 28)
    f.icon:SetPoint("LEFT", PAD, 0)
    pcall(f.icon.SetAtlas, f.icon, "ui-lfg-roleicon-dps-micro-raid", false)
    if not f.icon:GetAtlas() then
        f.icon:SetTexture("Interface\\Icons\\ability_warrior_savageblow")
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    f.icon:SetVertexColor(unpack(CLR_RED))

    -- "In Combat" label
    f.label = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.label:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -2)
    f.label:SetText("In Combat")
    f.label:SetTextColor(unpack(CLR_LABEL))

    -- Large time display
    f.time = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontNormalLarge")
    f.time:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 8, 2)
    f.time:SetTextColor(unpack(CLR_TIME))

    -- Tick 10x/sec so the seconds tick visibly
    local accum = 0
    f:SetScript("OnUpdate", function(_, dt)
        accum = accum + dt
        if accum < 0.1 then return end
        accum = 0
        if inCombat then Pull:Refresh() end
    end)

    frame = f
    return f
end

function Pull:Refresh()
    if not frame then return end
    local elapsed = inCombat and (GetTime() - combatStart) or 0
    frame.time:SetText(BazUI:FormatTime(elapsed))
    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

---------------------------------------------------------------------------
-- Widget contract
---------------------------------------------------------------------------

function Pull:GetDesiredHeight() return DESIGN_HEIGHT end

function Pull:GetStatusText()
    if inCombat then
        return BazUI:FormatTime(GetTime() - combatStart), unpack(CLR_SWORDS)
    end
    return ""
end

---------------------------------------------------------------------------
-- Init - dormant: only register while in combat
---------------------------------------------------------------------------

function Pull:Init()
    local f = self:Build()

    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:HookScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
            combatStart = GetTime()
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
        else  -- PLAYER_ENTERING_WORLD
            inCombat = UnitAffectingCombat and UnitAffectingCombat("player") or false
            if inCombat and combatStart == 0 then combatStart = GetTime() end
        end
        Pull:Refresh()
    end)

    local widgetDef = {
        id           = WIDGET_ID,
        label        = "Pull Timer",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return Pull:GetDesiredHeight() end,
        GetStatusText    = function() return Pull:GetStatusText() end,
    }

    local LBW = BazUI.Widgets
    LBW:RegisterDormantWidget(widgetDef, {
        events = {
            "PLAYER_REGEN_DISABLED",
            "PLAYER_REGEN_ENABLED",
            "PLAYER_ENTERING_WORLD",
        },
        condition = function()
            return (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
        end,
    })
end

BazUI:QueueForLogin(function() Pull:Init() end)
