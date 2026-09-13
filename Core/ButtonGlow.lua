-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: ButtonGlow Module
-- Original spell proc overlay glow using animation groups
---------------------------------------------------------------------------

local GLOW_PADDING = 4
local GLOW_ALPHA = 0.7
local PULSE_MIN = 0.2
local PULSE_DURATION = 0.8
local SPARK_COUNT = 3

local activeGlows = {} -- [button] = glowFrame

---------------------------------------------------------------------------
-- Glow Construction
---------------------------------------------------------------------------

local function CreateGlowFrame(btn)
    local glow = CreateFrame("Frame", nil, btn)
    glow:SetPoint("TOPLEFT", -GLOW_PADDING, GLOW_PADDING)
    glow:SetPoint("BOTTOMRIGHT", GLOW_PADDING, -GLOW_PADDING)
    glow:SetFrameLevel(btn:GetFrameLevel() + 5)

    -- Main glow texture (soft radial)
    local main = glow:CreateTexture(nil, "OVERLAY")
    main:SetAllPoints()
    main:SetAtlas("loottoast-glow")
    main:SetVertexColor(1.0, 0.85, 0.2, GLOW_ALPHA)
    main:SetBlendMode("ADD")
    glow.mainTex = main

    -- Pulse animation on main glow
    local mainAG = main:CreateAnimationGroup()
    mainAG:SetLooping("BOUNCE")
    local mainPulse = mainAG:CreateAnimation("Alpha")
    mainPulse:SetFromAlpha(GLOW_ALPHA)
    mainPulse:SetToAlpha(PULSE_MIN)
    mainPulse:SetDuration(PULSE_DURATION)
    mainPulse:SetSmoothing("IN_OUT")
    glow.mainAG = mainAG

    -- Rotating spark textures for visual interest
    glow.sparks = {}
    for i = 1, SPARK_COUNT do
        local spark = glow:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetSize(glow:GetWidth() * 0.6, glow:GetHeight() * 0.6)
        spark:SetPoint("CENTER")
        spark:SetTexture("Interface\\Cooldown\\star4")
        spark:SetVertexColor(1.0, 0.9, 0.4, 0.3)
        spark:SetBlendMode("ADD")

        local sparkAG = spark:CreateAnimationGroup()
        sparkAG:SetLooping("REPEAT")

        local rot = sparkAG:CreateAnimation("Rotation")
        rot:SetDegrees(360)
        rot:SetDuration(2.0 + (i * 0.7)) -- stagger rotation speeds
        rot:SetSmoothing("NONE")

        local alpha = sparkAG:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0.3)
        alpha:SetToAlpha(0.05)
        alpha:SetDuration(1.0 + (i * 0.3))
        alpha:SetSmoothing("IN_OUT")
        -- Make alpha bounce independently
        local alphaAG = spark:CreateAnimationGroup()
        alphaAG:SetLooping("BOUNCE")
        local alphaPulse = alphaAG:CreateAnimation("Alpha")
        alphaPulse:SetFromAlpha(0.3)
        alphaPulse:SetToAlpha(0.05)
        alphaPulse:SetDuration(1.0 + (i * 0.3))
        alphaPulse:SetSmoothing("IN_OUT")

        glow.sparks[i] = { tex = spark, rotAG = sparkAG, alphaAG = alphaAG }
    end

    return glow
end

---------------------------------------------------------------------------
-- Start / Stop Animations
---------------------------------------------------------------------------

local function StartAnimations(glow)
    glow.mainAG:Play()
    for _, spark in ipairs(glow.sparks) do
        spark.rotAG:Play()
        spark.alphaAG:Play()
    end
end

local function StopAnimations(glow)
    glow.mainAG:Stop()
    for _, spark in ipairs(glow.sparks) do
        spark.rotAG:Stop()
        spark.alphaAG:Stop()
    end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function BazUI:ShowGlow(btn, r, g, b)
    if not btn then return end

    -- Reuse existing glow frame
    if activeGlows[btn] then
        local glow = activeGlows[btn]
        if r and g and b then
            glow.mainTex:SetVertexColor(r, g, b, GLOW_ALPHA)
        end
        glow:Show()
        StartAnimations(glow)
        return
    end

    local glow = CreateGlowFrame(btn)
    activeGlows[btn] = glow

    -- Optional custom color
    if r and g and b then
        glow.mainTex:SetVertexColor(r, g, b, GLOW_ALPHA)
    end

    glow:Show()
    StartAnimations(glow)
end

function BazUI:HideGlow(btn)
    if not btn then return end
    local glow = activeGlows[btn]
    if not glow then return end
    StopAnimations(glow)
    UIFrameFade(glow, {
        mode = "OUT",
        timeToFade = 0.3,
        startAlpha = glow:GetAlpha(),
        endAlpha = 0,
        finishedFunc = function() glow:Hide(); glow:SetAlpha(1) end,
    })
end

function BazUI:HasGlow(btn)
    local glow = activeGlows[btn]
    return glow and glow:IsShown() or false
end
