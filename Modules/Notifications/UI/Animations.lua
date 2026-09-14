-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications

addon.Animations = {}

-- Create a one-shot alpha animation that properly cleans up
function addon.Animations.FadeIn(frame, duration, onFinished)
    duration = duration or 0.2

    -- Stop any existing fade
    if frame._bncFadeGroup then
        frame._bncFadeGroup:Stop()
    end

    local group = frame:CreateAnimationGroup()
    frame._bncFadeGroup = group

    local anim = group:CreateAnimation("Alpha")
    anim:SetFromAlpha(0)
    anim:SetToAlpha(1)
    anim:SetDuration(duration)
    anim:SetSmoothing("IN_OUT")

    frame:SetAlpha(0)
    frame:Show()

    group:SetScript("OnFinished", function()
        frame:SetAlpha(1)
        if onFinished then onFinished() end
    end)

    group:Play()
    return group
end

function addon.Animations.FadeOut(frame, duration, onFinished)
    duration = duration or 0.15

    if frame._bncFadeGroup then
        frame._bncFadeGroup:Stop()
    end

    local group = frame:CreateAnimationGroup()
    frame._bncFadeGroup = group

    local anim = group:CreateAnimation("Alpha")
    anim:SetFromAlpha(1)
    anim:SetToAlpha(0)
    anim:SetDuration(duration)
    anim:SetSmoothing("IN_OUT")

    group:SetScript("OnFinished", function()
        frame:SetAlpha(1)
        frame:Hide()
        if onFinished then onFinished() end
    end)

    group:Play()
    return group
end

-- Stop any playing animation and reset the frame
function addon.Animations.StopAll(frame)
    if frame._bncFadeGroup then
        frame._bncFadeGroup:Stop()
        frame._bncFadeGroup = nil
    end
    frame:SetAlpha(1)
end
