-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Animations Module
-- Reusable animation presets: pulse, bounce, flash, slide
---------------------------------------------------------------------------

-- Store animation groups to avoid duplicates (weak keys so destroyed frames get collected)
local activeAnimations = setmetatable({}, { __mode = "k" }) -- [frame][animType] = animGroup

local function GetOrCreateAG(frame, animType)
    if not activeAnimations[frame] then
        activeAnimations[frame] = {}
    end
    local ag = activeAnimations[frame][animType]
    if ag then return ag, false end

    ag = frame:CreateAnimationGroup()
    activeAnimations[frame][animType] = ag
    return ag, true -- true = newly created
end

---------------------------------------------------------------------------
-- Pulse (alpha oscillation)
---------------------------------------------------------------------------

function BazUI:Pulse(frame, opts)
    opts = opts or {}
    local duration = opts.duration or 1.0
    local minAlpha = opts.minAlpha or 0.3
    local maxAlpha = opts.maxAlpha or 1.0

    local ag, isNew = GetOrCreateAG(frame, "pulse")
    if not isNew then
        ag:Play()
        return ag
    end

    ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(maxAlpha)
    anim:SetToAlpha(minAlpha)
    anim:SetDuration(duration)
    anim:SetSmoothing("IN_OUT")
    ag:Play()
    return ag
end

function BazUI:StopPulse(frame)
    if activeAnimations[frame] and activeAnimations[frame]["pulse"] then
        activeAnimations[frame]["pulse"]:Stop()
        frame:SetAlpha(1.0)
    end
end

---------------------------------------------------------------------------
-- Bounce (scale pop)
-- Quick scale up then back to normal
---------------------------------------------------------------------------

function BazUI:Bounce(frame, opts)
    opts = opts or {}
    local scale = opts.scale or 1.2
    local duration = opts.duration or 0.3

    local ag, isNew = GetOrCreateAG(frame, "bounce")
    if not isNew then
        ag:Stop()
        ag:Play()
        return ag
    end

    local scaleUp = ag:CreateAnimation("Scale")
    scaleUp:SetScaleFrom(1, 1)
    scaleUp:SetScaleTo(scale, scale)
    scaleUp:SetDuration(duration * 0.4)
    scaleUp:SetSmoothing("OUT")
    scaleUp:SetOrder(1)

    local scaleDown = ag:CreateAnimation("Scale")
    scaleDown:SetScaleFrom(scale, scale)
    scaleDown:SetScaleTo(1, 1)
    scaleDown:SetDuration(duration * 0.6)
    scaleDown:SetSmoothing("IN")
    scaleDown:SetOrder(2)

    ag:Play()
    return ag
end

---------------------------------------------------------------------------
-- Flash (rapid alpha blink)
---------------------------------------------------------------------------

function BazUI:Flash(frame, opts)
    opts = opts or {}
    local duration = opts.duration or 0.15
    local count = opts.count or 3

    local ag, isNew = GetOrCreateAG(frame, "flash")
    if not isNew then
        ag:Stop()
        frame:SetAlpha(1.0)
        ag:Play()
        return ag
    end

    local totalAnims = count * 2
    for i = 1, totalAnims do
        local anim = ag:CreateAnimation("Alpha")
        if i % 2 == 1 then
            anim:SetFromAlpha(1.0)
            anim:SetToAlpha(0.1)
        else
            anim:SetFromAlpha(0.1)
            anim:SetToAlpha(1.0)
        end
        anim:SetDuration(duration)
        anim:SetSmoothing("NONE")
        anim:SetOrder(i)
    end

    ag:SetScript("OnFinished", function()
        frame:SetAlpha(1.0)
    end)

    ag:Play()
    return ag
end

---------------------------------------------------------------------------
-- Slide In / Out
-- Slides a frame from off-screen into its anchored position
---------------------------------------------------------------------------

local SLIDE_OFFSETS = {
    LEFT   = { -1,  0 },
    RIGHT  = {  1,  0 },
    TOP    = {  0,  1 },
    BOTTOM = {  0, -1 },
}

function BazUI:SlideIn(frame, direction, duration)
    direction = strupper(direction or "TOP")
    duration = duration or 0.3

    local offsets = SLIDE_OFFSETS[direction]
    if not offsets then return end

    local distX = frame:GetWidth() * offsets[1]
    local distY = frame:GetHeight() * offsets[2]

    local ag = frame:CreateAnimationGroup()

    -- Start displaced, then animate back to origin
    local trans = ag:CreateAnimation("Translation")
    trans:SetOffset(distX, distY)
    trans:SetDuration(0)
    trans:SetOrder(1)

    local slideIn = ag:CreateAnimation("Translation")
    slideIn:SetOffset(-distX, -distY)
    slideIn:SetDuration(duration)
    slideIn:SetSmoothing("OUT")
    slideIn:SetOrder(2)

    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(duration * 0.5)
    fadeIn:SetOrder(2)

    frame:Show()
    ag:Play()
    return ag
end

function BazUI:SlideOut(frame, direction, duration, onComplete)
    direction = strupper(direction or "TOP")
    duration = duration or 0.3

    local offsets = SLIDE_OFFSETS[direction]
    if not offsets then return end

    local distX = frame:GetWidth() * offsets[1]
    local distY = frame:GetHeight() * offsets[2]

    local ag = frame:CreateAnimationGroup()

    local slide = ag:CreateAnimation("Translation")
    slide:SetOffset(distX, distY)
    slide:SetDuration(duration)
    slide:SetSmoothing("IN")

    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(duration * 0.7)
    fadeOut:SetStartDelay(duration * 0.3)

    ag:SetScript("OnFinished", function(self)
        frame:Hide()
        frame:SetAlpha(1)
        self:Stop()
        if onComplete then onComplete() end
    end)

    ag:Play()
    return ag
end

---------------------------------------------------------------------------
-- Stop All Animations
---------------------------------------------------------------------------

function BazUI:StopAnimations(frame)
    if activeAnimations[frame] then
        for _, ag in pairs(activeAnimations[frame]) do
            ag:Stop()
        end
    end
    frame:SetAlpha(1.0)
end
