-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: Tab Drag-to-Reorder
--
-- Hold a tab for HOLD_DURATION seconds → green additive glow appears,
-- the tab detaches and follows the cursor on the X axis only (Y is
-- locked to its original height). A transparent placeholder slips
-- into the strip at the projected drop slot so the OTHER tabs slide
-- around it live as the cursor moves. Drop → final order is the
-- placeholder's layoutIndex; the placeholder is removed and the
-- dragged tab snaps in.
--
-- Order persists in addon.db.profile.tabOrder; re-applied on /reload
-- via TabDrag:LoadOrder.
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

local TabDrag = {}
addon.TabDrag = TabDrag

local HOLD_DURATION = 2.0

-- Returns the cursor X in UIParent space.
local function CursorX()
    local x = GetCursorPosition()
    return x / UIParent:GetEffectiveScale()
end

-- Sort all currently-shown layout-eligible children of ts by their
-- current visible center X. Excludes the dragged tab.
local function GetOthersByCenter(ts, draggedTab)
    local list = {}
    for i, t in ipairs(ts.tabs) do
        if t ~= draggedTab and t:IsShown() then
            list[#list + 1] = { id = i, tab = t, center = t:GetCenter() or 0 }
        end
    end
    table.sort(list, function(a, b) return a.center < b.center end)
    return list
end

-- Compute the drop slot (1..#others+1) that cursorX falls in,
-- relative to the visible centers of the other tabs.
local function ComputeDropSlot(others, cursorX)
    for i, info in ipairs(others) do
        if cursorX < info.center then return i end
    end
    return #others + 1
end

---------------------------------------------------------------------------
-- Glow + placeholder
---------------------------------------------------------------------------

-- Resize/anchor the glow to fit the tab's visible artwork. Selected
-- tabs are taller than unselected (the active atlas is taller than
-- the unselected one), so we add a top-inset on unselected tabs to
-- avoid the glow hanging above the tab's actual top edge.
local function FitGlowToTab(tab, glow)
    glow:ClearAllPoints()
    if tab.isSelected then
        glow:SetPoint("TOPLEFT",     tab, "TOPLEFT",      3,  0)
        glow:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -5,  0)
    else
        -- Unselected tab visual sits ~4-5 px below the button's top
        -- bound (the active art reserves that space for the "pop-up"
        -- look when selected). Inset top so glow doesn't overhang.
        glow:SetPoint("TOPLEFT",     tab, "TOPLEFT",      3, -5)
        glow:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -5,  0)
    end
end

local function EnsureGlow(tab)
    if tab._bcGlow then return tab._bcGlow end
    -- Highest OVERLAY sub-level (7) so we render on top of the tab's
    -- own atlas pieces (which also live at OVERLAY at lower sub-levels).
    local glow = tab:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetColorTexture(0, 0.85, 0.25, 0.55)
    glow:SetBlendMode("ADD")
    glow:Hide()
    tab._bcGlow = glow
    return glow
end

local function EnsurePlaceholder(ts, w, h)
    local ph = ts._bcPlaceholder
    if not ph then
        ph = CreateFrame("Frame", nil, ts)
        ts._bcPlaceholder = ph
    end
    ph:SetSize(w, h)
    ph:Show()
    return ph
end

---------------------------------------------------------------------------
-- Drag lifecycle
---------------------------------------------------------------------------

local function EnterDragMode(tab, tabID, ts)
    tab._bcDragging = true
    tab._bcHoldTimer = nil
    tab._bcOldLevel  = tab:GetFrameLevel()

    -- Remember original Y so we can lock vertical movement to it.
    -- Also capture the X offset between cursor and tab center, so
    -- the tab doesn't "jump" sideways when drag mode kicks in - we
    -- preserve wherever the user clicked on the tab as the grab
    -- point and the tab follows the cursor relative to that.
    local origCx, origY = tab:GetCenter()
    tab._bcDragOrigY    = origY or 0
    tab._bcDragOffsetX  = CursorX() - (origCx or 0)

    -- Float the dragged tab above other tabs.
    tab:SetFrameLevel((ts:GetFrameLevel() or 0) + 50)

    -- Ignore from layout - we'll position it manually each frame.
    tab.ignoreInLayout = true

    -- Spawn a placeholder the same size as the tab. Its layoutIndex
    -- swaps in for the dragged tab's, so the strip leaves a visible
    -- slot where the drop will land. Other tabs reflow around it.
    local placeholder = EnsurePlaceholder(ts, tab:GetWidth(), tab:GetHeight())
    placeholder.layoutIndex = tab.layoutIndex or tabID
    tab._bcPlaceholder = placeholder

    -- Anchor the tab at its CURRENT center X (using the captured
    -- offset so cursor stays at the same point on the tab) and
    -- locked Y. Same anchoring scheme as the OnUpdate loop, so the
    -- handoff is seamless and the tab doesn't visibly jump when
    -- drag mode kicks in - it just becomes draggable in place.
    local startCx = CursorX() - tab._bcDragOffsetX
    tab:ClearAllPoints()
    tab:SetPoint("CENTER", UIParent, "BOTTOMLEFT", startCx, tab._bcDragOrigY)

    -- Glow on, after the snap so it's drawn at the new position.
    -- Re-fit each time so it matches selected/unselected tab heights.
    local glow = EnsureGlow(tab)
    FitGlowToTab(tab, glow)
    glow:Show()

    -- Per-frame: track cursor (X only), update placeholder slot,
    -- cascade other tabs' layoutIndex to keep continuity.
    tab:SetScript("OnUpdate", function(self)
        -- Subtract the captured grab-offset so the cursor stays at
        -- the same point on the tab while moving (no jump on
        -- entering drag mode).
        local cx = CursorX() - (self._bcDragOffsetX or 0)

        -- Clamp X to the chat window's horizontal bounds so the tab
        -- can't be dragged off the side of the chat. Use the dock
        -- since that's the canonical chat-window rectangle.
        local dock = addon.Window and addon.Window.dock
        if dock then
            local left   = dock:GetLeft()
            local right  = dock:GetRight()
            local halfW  = (self:GetWidth() or 0) / 2
            if left and right then
                local minX = left  + halfW
                local maxX = right - halfW
                if cx < minX then cx = minX
                elseif cx > maxX then cx = maxX end
            end
        end

        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, self._bcDragOrigY)

        -- Find drop slot among others. Use the *raw* cursor X for
        -- slot detection (not the offset-adjusted X used for
        -- positioning) - the slot should reflect where the cursor
        -- actually is, not where the tab body is.
        local rawCx = CursorX()
        local others = GetOthersByCenter(ts, self)
        local slot   = ComputeDropSlot(others, rawCx)
        if placeholder.layoutIndex ~= slot then
            placeholder.layoutIndex = slot
            -- Reassign others so they pack 1..slot-1 then slot+1..end.
            for i, info in ipairs(others) do
                local target = (i < slot) and i or (i + 1)
                if info.tab.layoutIndex ~= target then
                    info.tab.layoutIndex = target
                end
            end
            if ts.MarkDirty then ts:MarkDirty() end
        end
    end)

    if ts.MarkDirty then ts:MarkDirty() end
end

local function ExitDragMode(tab, tabID, ts)
    if not tab._bcDragging then return end
    tab._bcDragging = false

    tab:SetScript("OnUpdate", nil)
    if tab._bcGlow then tab._bcGlow:Hide() end
    tab:SetFrameLevel(tab._bcOldLevel or ts:GetFrameLevel())

    tab._bcDragOffsetX = nil

    -- Settle into the placeholder's slot, then retire the placeholder.
    local placeholder = tab._bcPlaceholder
    local slot = placeholder and placeholder.layoutIndex or tab.layoutIndex
    if placeholder then
        placeholder:Hide()
        placeholder.layoutIndex = nil   -- so layout ignores it
    end
    tab._bcPlaceholder = nil

    tab.ignoreInLayout = false
    tab.layoutIndex    = slot
    if ts.MarkDirty then ts:MarkDirty() end

    -- Persist the new order.
    local order = {}
    for i, t in ipairs(ts.tabs) do
        order[t.layoutIndex or i] = i
    end
    local clean = {}
    for _, id in ipairs(order) do
        if id then clean[#clean + 1] = id end
    end
    TabDrag:Save(clean)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function TabDrag:Setup(tab, tabID, ts)
    if tab._bcDragHooked then return end
    tab._bcDragHooked = true

    tab:HookScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or self._bcDragging then return end
        if self._bcHoldTimer then self._bcHoldTimer:Cancel() end
        self._bcHoldTimer = C_Timer.NewTimer(HOLD_DURATION, function()
            EnterDragMode(self, tabID, ts)
        end)
    end)

    tab:HookScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if self._bcHoldTimer then
            self._bcHoldTimer:Cancel()
            self._bcHoldTimer = nil
        end
        if self._bcDragging then
            ExitDragMode(self, tabID, ts)
        end
    end)

    tab:HookScript("OnLeave", function(self)
        if self._bcHoldTimer and not self._bcDragging then
            self._bcHoldTimer:Cancel()
            self._bcHoldTimer = nil
        end
    end)
end

function TabDrag:ApplyOrder(order, ts)
    if not ts or not ts.tabs then return end
    for visualPos, tabID in ipairs(order) do
        local tab = ts.tabs[tabID]
        if tab then tab.layoutIndex = visualPos end
    end
    if ts.MarkDirty then ts:MarkDirty() end
end

function TabDrag:Save(order)
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    if not p then return end
    p.tabOrder = order
end

function TabDrag:LoadOrder(ts)
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    if not p or not p.tabOrder then return end
    local valid, seen = {}, {}
    for _, id in ipairs(p.tabOrder) do
        if ts.tabs[id] then valid[#valid + 1] = id; seen[id] = true end
    end
    for i in ipairs(ts.tabs) do
        if not seen[i] then valid[#valid + 1] = i end
    end
    TabDrag:ApplyOrder(valid, ts)
end
