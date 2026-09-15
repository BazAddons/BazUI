-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: dock movers
--
-- The handle you drag in Edit Mode, and the snapping that goes with it.
--
-- Anything dockable needs the same three things: something to grab that
-- is not the thing itself, a way to tell where letting go would attach
-- it, and a line showing that before you commit. None of it knows what
-- it is moving, so a status bar and a row of auras use one copy.
--
-- Why a handle at all: a bar is a secure frame, and a secure frame
-- cannot be moved in combat. The handle is an ordinary frame standing in
-- for it, which Edit Mode moves; what it stands for follows.
--
-- API:
--   local mover = BazUI.Dock:CreateMover(target, opts)
--     opts.name        frame name, for saved layouts and error messages
--     opts.label       what Edit Mode calls it
--     opts.addonName   the module it belongs to, for Edit Mode
--     opts.settings    function returning Edit Mode widgets
--     opts.actions     function returning Edit Mode actions
--     opts.onDrop      function(snap, x, y) - snap is {host, edge} or nil,
--                      x and y the screen center it was dropped at
--     opts.onOffset    function(x, y) - the nudge on a docked target
--                      changed, and wants saving alongside its dock
--     opts.minSize     function returning the size the handle should
--                      never go below, for a target that shrinks to fit
--   mover:Refresh()      size and place the handle over its target
--   mover:ShowForEdit()  show it if Edit Mode is open and combat is not
--   mover:ShowSnap(snap) draw or clear the landing line
--
--   BazUI.Dock:NearestSnap(frame, ignore)  where dropping frame would land
--   BazUI.Dock:ShowSnapLine(snap)
--   BazUI.Dock:DescribeSnap(print)         what the snap test can see
---------------------------------------------------------------------------

local Dock = BazUI.Dock

local SNAP_DISTANCE = 36

---------------------------------------------------------------------------
-- Where a drop would land
---------------------------------------------------------------------------

-- Frame coordinates are reported in the frame's own scale, so two frames
-- at different scales cannot be compared directly. Everything here is
-- converted to screen pixels first, which is the only space they share.
-- An action bar carries a scale of its own, so skipping this is why the
-- first attempt at snapping never matched anything.
local function ScreenEdges(frame)
    local scale = frame:GetEffectiveScale() or 1
    local left, right = frame:GetLeft(), frame:GetRight()
    local top, bottom = frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return nil end
    return left * scale, right * scale, top * scale, bottom * scale
end

-- The closest edge worth snapping to, or nothing.
--
-- Docking below a host means this frame's top meeting the host's bottom,
-- so the comparison is edge to edge. Measuring from the middle of the
-- dragged thing, as this first did, is half its height out before
-- anything else goes wrong.
function Dock:NearestSnap(frame, ignore)
    local left, right, top, bottom = ScreenEdges(frame)
    if not left then return nil end

    local best, bestDistance
    for _, host in ipairs(self:GetHosts()) do
        local hostFrame = self:GetHostFrame(host.id)
        -- Never onto itself, onto something there is no sign of, or
        -- onto something already hanging off it, which would be a loop.
        --
        -- A handle counts as a sign of it. A bar for a unit who is not
        -- there is hidden, and in Edit Mode its handle is all you can
        -- see: refusing to snap to it means a party layout cannot be
        -- arranged unless the party is standing there, which is the
        -- opposite of when anyone arranges one.
        local shown = hostFrame and (hostFrame:IsVisible()
            or (hostFrame._bazMover and hostFrame._bazMover:IsShown()))

        if hostFrame and shown and hostFrame ~= ignore and hostFrame ~= frame
            and not (ignore and self:Follows(hostFrame, ignore)) then

            local hLeft, hRight, hTop, hBottom = ScreenEdges(hostFrame)
            -- Any horizontal overlap at all is enough. Requiring the
            -- centers to line up meant a wide action bar and a narrow
            -- bar rarely agreed.
            if hLeft and left < hRight and right > hLeft then
                local candidates = {
                    { edge = "BOTTOM", distance = math.abs(hBottom - top) },
                    { edge = "TOP",    distance = math.abs(hTop - bottom) },
                }
                for _, candidate in ipairs(candidates) do
                    if candidate.distance < SNAP_DISTANCE
                        and (not bestDistance or candidate.distance < bestDistance) then
                        best = { host = host.id, edge = candidate.edge }
                        bestDistance = candidate.distance
                    end
                end
            end
        end
    end
    return best
end

---------------------------------------------------------------------------
-- Saying so before it happens
--
-- Drawn on the host rather than on the handle. Edit Mode puts its own
-- overlay on top of anything registered with it, so recoloring the
-- handle is invisible: the overlay is what you are looking at. Marking
-- the target edge instead is both visible and clearer about what will
-- happen, since it says where rather than whether.
---------------------------------------------------------------------------

local snapLine

local function SnapLine()
    if snapLine then return snapLine end
    snapLine = CreateFrame("Frame", nil, UIParent)
    snapLine:SetFrameStrata("TOOLTIP")
    snapLine:Hide()

    snapLine.bar = snapLine:CreateTexture(nil, "OVERLAY")
    snapLine.bar:SetAllPoints()
    snapLine.bar:SetColorTexture(0.35, 1, 0.45, 0.95)

    snapLine.glow = snapLine:CreateTexture(nil, "ARTWORK")
    snapLine.glow:SetPoint("TOPLEFT", -2, 6)
    snapLine.glow:SetPoint("BOTTOMRIGHT", 2, -6)
    snapLine.glow:SetColorTexture(0.35, 1, 0.45, 0.25)

    snapLine.text = BazUI.Skin.Theme.FontString(snapLine, "OVERLAY", "GameFontNormal")
    snapLine.text:SetPoint("BOTTOM", snapLine, "TOP", 0, 4)
    snapLine.text:SetTextColor(0.5, 1, 0.55)
    return snapLine
end

function Dock:ShowSnapLine(snap)
    if not snap then
        if snapLine then snapLine:Hide() end
        return
    end
    local host = self:GetHostFrame(snap.host)
    if not host then return end

    -- Draw it on the host's handle when one is showing, not on the host
    -- itself. In Edit Mode the handle is what you can see, and it has a
    -- minimum size: a row of auras only a pixel or two tall would put
    -- the line through the middle of its own handle, which reads as
    -- landing in the middle of something rather than under it.
    if host._bazMover and host._bazMover:IsShown() then
        host = host._bazMover
    end

    local line = SnapLine()
    local label
    for _, entry in ipairs(self:GetHosts()) do
        if entry.id == snap.host then label = entry.label break end
    end

    line:ClearAllPoints()
    line:SetPoint("LEFT", host, "LEFT", 0, 0)
    line:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    line:SetHeight(3)
    if snap.edge == "BOTTOM" then
        line:SetPoint("TOP", host, "BOTTOM", 0, 1)
    else
        line:SetPoint("BOTTOM", host, "TOP", 0, -1)
    end
    line.text:SetText((snap.edge == "BOTTOM" and "Below " or "Above ") .. (label or "here"))
    line:Show()
end

-- Says what the snap test can see, for when it insists nothing is near.
function Dock:DescribeSnap(print)
    local hosts = self:GetHosts()
    print(("Snap targets: %d"):format(#hosts))
    for _, host in ipairs(hosts) do
        local frame = self:GetHostFrame(host.id)
        local l, r, t, b
        if frame then l, r, t, b = ScreenEdges(frame) end
        print(("  %s (%s): %s"):format(host.label, host.id,
            l and ("%d..%d wide, top %d bottom %d"):format(l, r, t, b) or "no geometry"))
    end
end

---------------------------------------------------------------------------
-- The handle
---------------------------------------------------------------------------

function Dock:CreateMover(target, opts)
    opts = opts or {}

    local mover = CreateFrame("Frame", opts.name, UIParent)
    mover:SetFrameStrata("DIALOG")
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    local minWidth  = opts.minWidth  or 60
    local minHeight = opts.minHeight or 20

    -- Something whose size follows its contents can supply the size it
    -- would be when full, so its handle does not shrink to the minimum
    -- when it happens to be empty. Two handles for two rows set up the
    -- same way should look the same, whatever is in them at the moment.
    local MinSize = opts.minSize

    local tint = mover:CreateTexture(nil, "BACKGROUND")
    tint:SetAllPoints(mover)
    tint:SetColorTexture(0.15, 0.5, 0.8, 0.35)
    mover.tint = tint

    local label = BazUI.Skin.Theme.FontString(mover, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(opts.label or "")
    mover.label = label

    function mover:SetLabel(text)
        self.label:SetText(text or "")
    end

    -- Size and place the handle over what it stands for. Never while a
    -- drag is running: mid-drag the target is anchored to the handle, so
    -- anchoring the handle to the target would be circular, and it would
    -- fight the drag besides. A docked thing resizing under the cursor
    -- is exactly when this would otherwise fire.
    --
    -- A handle has a minimum size, so a small target leaves it hanging
    -- over the edges. Centered, that reads as misalignment: a row of two
    -- icons aligned to the right of an action bar looked like it was
    -- past the end of the bar, because the handle was wider than the row
    -- and centered on it. Hung by the same corner the dock hung its
    -- target by, it grows inward exactly as the row does.
    function mover:Refresh()
        if self.isDragging or self.isMoving then return end
        local floorW, floorH = minWidth, minHeight
        if MinSize then
            local w, h = MinSize()
            floorW, floorH = math.max(floorW, w or 0), math.max(floorH, h or 0)
        end
        self:SetSize(math.max(floorW, target:GetWidth() or 0),
            math.max(floorH, target:GetHeight() or 0))
        local point = Dock:FollowerPoint(target) or "CENTER"
        self:ClearAllPoints()
        self:SetPoint(point, target, point, 0, 0)
    end

    function mover:ShowForEdit()
        local editing = BazUI:IsEditMode()
        self:SetShown(editing and not InCombatLockdown())
        if editing then self:Refresh() end
    end

    function mover:ShowSnap(snap)
        self._snapShown = snap and true or false
        Dock:ShowSnapLine(snap)
    end

    -- So anything drawing over the target can find what stands for it.
    target._bazMover = mover

    -- The handle is a picture of its target, so it follows the target's
    -- size rather than waiting to be told. Something resized by its host
    -- at any depth of a chain drags its handle along without every
    -- caller having to remember.
    target:HookScript("OnSizeChanged", function() mover:Refresh() end)

    mover:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)

    -- While it is being dragged, say whether letting go would dock it,
    -- and to what.
    --
    -- Edit Mode drags through an overlay of its own and marks the frame
    -- isDragging; isMoving covers a drag by the handle itself. Watching
    -- only the second one is why this never ran at first.
    mover:SetScript("OnUpdate", function(self)
        if not (self.isDragging or self.isMoving) then
            if self._snapShown then self:ShowSnap(nil) end
            return
        end

        -- The target follows the handle live rather than jumping to it
        -- on release. Edit Mode moves the handle, so for the length of
        -- the drag the anchoring runs that way round; releasing puts it
        -- back. Moving a secure frame is protected, so not in combat.
        if not InCombatLockdown() then
            target:ClearAllPoints()
            target:SetPoint("CENTER", self, "CENTER", 0, 0)
            Dock:Relayout(target)
        end

        self:ShowSnap(Dock:NearestSnap(self, target))
    end)

    mover:HookScript("OnDragStart", function(self) self.isMoving = true end)
    mover:HookScript("OnDragStop", function(self)
        self.isMoving = false
        self:ShowSnap(nil)
    end)

    -- Letting go. Works out where it landed, hands that to the owner,
    -- and gets out of the way.
    function mover:Drop()
        self:StopMovingOrSizing()
        self:ShowSnap(nil)

        -- The target has spent the drag anchored to this handle so it
        -- could follow it. Put it back on the screen before the owner
        -- re-anchors the handle to the target, or the two depend on each
        -- other and the game refuses the second anchor outright.
        if not InCombatLockdown() then
            local cx, cy = target:GetCenter()
            if cx then
                local scale = target:GetEffectiveScale() / UIParent:GetEffectiveScale()
                target:ClearAllPoints()
                target:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * scale, cy * scale)
            end
        end

        local snap = Dock:NearestSnap(self, target)
        local x, y = self:GetCenter()
        if x then
            local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            x, y = x * scale, y * scale
        end
        if opts.onDrop then opts.onDrop(snap, x, y) end
    end

    mover:SetScript("OnDragStop", function(self) self:Drop() end)

    -- Nudging a docked target is the dock's business, not the mover's:
    -- the dock places it, so an adjustment that is not part of what the
    -- dock knows lasts exactly until the next layout pass. Answering
    -- false hands a floating target back to Edit Mode, which moves it the
    -- ordinary way.
    local function Nudge(dx, dy)
        if not Dock:IsDocked(target) then return false end
        local x, y = Dock:Nudge(target, dx, dy)
        if opts.onOffset then opts.onOffset(x, y) end
        mover:Refresh()
        return true
    end

    local function ResetNudge()
        if not Dock:IsDocked(target) then return end
        local x, y = Dock:SetOffset(target, 0, 0)
        if opts.onOffset then opts.onOffset(x, y) end
        mover:Refresh()
    end

    BazUI:RegisterEditModeFrame(mover, {
        label = opts.label,
        addonName = opts.addonName,
        positionKey = false,
        settings = opts.settings and opts.settings() or nil,
        actions  = opts.actions and opts.actions() or nil,
        onNudge = Nudge,
        onNudgeReset = ResetNudge,
        -- Asked when the panel opens rather than answered now: a target
        -- is not docked yet when its mover is made, and it docks and
        -- undocks all afternoon after that.
        canNudgeReset = function() return Dock:IsDocked(target) end,
        onPositionChanged = function() mover:Drop() end,
        onEnter = function() mover:ShowForEdit() end,
        onExit  = function() mover:ShowForEdit() end,
    })

    return mover
end
