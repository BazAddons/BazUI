-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications

local SCROLL_SPEED = 40
local LERP_SPEED = 8

function addon.CreateScrollContainer(parent, width, height)
    -- Clip frame
    local clipFrame = CreateFrame("Frame", nil, parent)
    clipFrame:SetSize(width, height)
    clipFrame:SetClipsChildren(true)

    -- Content frame (moves up/down inside clip frame)
    local content = CreateFrame("Frame", nil, clipFrame)
    content:SetWidth(width)
    content:SetHeight(1)  -- grows dynamically
    content:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", 0, 0)

    -- Scroll state
    local scroll = {
        clipFrame = clipFrame,
        content = content,
        offset = 0,
        targetOffset = 0,
        maxOffset = 0,
    }

    -- Smooth-scroll OnUpdate. Previously this ran every frame even when
    -- the scroll was settled, calling SetPoint on the content frame
    -- every tick. Now it only runs while actively lerping toward the
    -- target offset and unhooks itself once we're within 0.5 px.
    -- ScrollTo / SetContentHeight re-arm it when the target changes.
    local function Tick(self, elapsed)
        if math.abs(scroll.offset - scroll.targetOffset) < 0.5 then
            scroll.offset = scroll.targetOffset
            content:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", 0, scroll.offset)
            self:SetScript("OnUpdate", nil)  -- settled - stop ticking
        else
            scroll.offset = scroll.offset
                + (scroll.targetOffset - scroll.offset) * math.min(1, elapsed * LERP_SPEED)
            content:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", 0, scroll.offset)
        end
    end

    local function Arm()
        if scroll.offset ~= scroll.targetOffset then
            clipFrame:SetScript("OnUpdate", Tick)
        end
    end

    function scroll:UpdateMaxOffset()
        local contentHeight = self.content:GetHeight()
        local viewHeight = self.clipFrame:GetHeight()
        self.maxOffset = math.max(0, contentHeight - viewHeight)
        -- Clamp current offset
        if self.targetOffset > self.maxOffset then
            self.targetOffset = self.maxOffset
            Arm()
        end
    end

    function scroll:ScrollTo(offset)
        self.targetOffset = math.max(0, math.min(offset, self.maxOffset))
        Arm()
    end

    function scroll:ScrollToTop()
        self.targetOffset = 0
        Arm()
    end

    function scroll:SetContentHeight(contentHeight)
        self.content:SetHeight(contentHeight)
        self:UpdateMaxOffset()
    end

    -- Mouse wheel handler
    clipFrame:EnableMouseWheel(true)
    clipFrame:SetScript("OnMouseWheel", function(self, delta)
        scroll:ScrollTo(scroll.targetOffset - delta * SCROLL_SPEED)
    end)

    return scroll
end
