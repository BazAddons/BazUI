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

---------------------------------------------------------------------------
-- Not snapping
--
-- Snapping is right nearly all of the time, which is the problem with it:
-- the one time you want two things a few pixels apart and not joined,
-- there is no way to say so. Two ways to say so, then.
--
-- A held key is the momentary one, and the one worth reaching for: you
-- want snapping back the moment you let go. Asked at the instant it
-- matters rather than remembered from when the drag started, so you can
-- decide part way through a drag and see the landing line go out.
--
-- The switch is the other one, for somebody who would rather place
-- everything by hand and never be grabbed at.
---------------------------------------------------------------------------

local FREE_MODIFIERS = {
    ALT   = function() return IsAltKeyDown and IsAltKeyDown() end,
    SHIFT = function() return IsShiftKeyDown and IsShiftKeyDown() end,
    CTRL  = function() return IsControlKeyDown and IsControlKeyDown() end,
}

function Dock:SnappingSuppressed()
    if BazUIDB and BazUIDB.snapping == false then return true end

    local key = (BazUIDB and BazUIDB.snapFreeModifier) or "ALT"
    local held = FREE_MODIFIERS[key]
    return held and held() or false
end

-- The closest edge worth snapping to, or nothing.
--
-- Docking below a host means this frame's top meeting the host's bottom,
-- so the comparison is edge to edge. Measuring from the middle of the
-- dragged thing, as this first did, is half its height out before
-- anything else goes wrong. The sides work the same way: docking to the
-- left means this frame's right meeting the host's left.
function Dock:NearestSnap(frame, ignore)
    -- One gate, because everything that snaps asks this: the landing line
    -- drawn while you drag and the drop that acts on it are the same
    -- question asked twice, and answering nil here is already what "there
    -- is nothing to dock to" looks like.
    if self:SnappingSuppressed() then return nil end

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

            -- Any overlap at all is enough. Requiring the centers to
            -- line up meant a wide action bar and a narrow bar rarely
            -- agreed.
            --
            -- The overlap has to be on the other axis from the edge, and
            -- that is what keeps a corner from being a coin toss: near
            -- the top left of a host, above is only offered while you
            -- still overlap it horizontally, and to the left only while
            -- you still overlap it vertically. Let both through on
            -- distance alone and a drop near the corner lands wherever
            -- the arithmetic happened to be a pixel kinder.
            local overlapsX = hLeft and left < hRight and right > hLeft
            local overlapsY = hTop  and bottom < hTop and top > hBottom

            local candidates = {}
            if overlapsX then
                candidates[#candidates + 1] =
                    { edge = "BOTTOM", distance = math.abs(hBottom - top) }
                candidates[#candidates + 1] =
                    { edge = "TOP",    distance = math.abs(hTop - bottom) }
            end
            if overlapsY then
                candidates[#candidates + 1] =
                    { edge = "LEFT",   distance = math.abs(hLeft - right) }
                candidates[#candidates + 1] =
                    { edge = "RIGHT",  distance = math.abs(hRight - left) }
            end

            for _, candidate in ipairs(candidates) do
                if candidate.distance < SNAP_DISTANCE
                    and (not bestDistance or candidate.distance < bestDistance) then
                    best = { host = host.id, edge = candidate.edge }
                    bestDistance = candidate.distance
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

    -- Anchored when the line is placed rather than here: the soft part
    -- has to spread away from the line, and which way that is depends on
    -- whether the line is lying down or standing up.
    snapLine.glow = snapLine:CreateTexture(nil, "ARTWORK")
    snapLine.glow:SetColorTexture(0.35, 1, 0.45, 0.25)

    snapLine.text = BazUI.Skin.Theme.FontString(snapLine, "OVERLAY", "GameFontNormal")
    snapLine.text:SetTextColor(0.5, 1, 0.55)
    return snapLine
end

-- Which way round the line is drawn, and what it says.
--
--   along      the two sides the line is stretched between
--   near/far   the follower's edge meeting the host's
--   spread     how far the soft glow reaches either way, as x and y
--   label      what the drop will do, in the player's words
local SNAP_LOOK = {
    BOTTOM = { along = { "LEFT", "RIGHT" }, near = "TOP",   far = "BOTTOM",
               nudge = 1,  spread = { 2, 6 }, label = "Below " },
    TOP    = { along = { "LEFT", "RIGHT" }, near = "BOTTOM", far = "TOP",
               nudge = -1, spread = { 2, 6 }, label = "Above " },
    LEFT   = { along = { "TOP", "BOTTOM" }, near = "RIGHT", far = "LEFT",
               nudge = 1,  spread = { 6, 2 }, label = "Left of " },
    RIGHT  = { along = { "TOP", "BOTTOM" }, near = "LEFT",  far = "RIGHT",
               nudge = -1, spread = { 6, 2 }, label = "Right of " },
}

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

    local look = SNAP_LOOK[snap.edge] or SNAP_LOOK.BOTTOM
    local sideways = (snap.edge == "LEFT" or snap.edge == "RIGHT")

    line:ClearAllPoints()
    line:SetPoint(look.along[1], host, look.along[1], 0, 0)
    line:SetPoint(look.along[2], host, look.along[2], 0, 0)
    if sideways then
        line:SetWidth(3)
        line:SetPoint(look.near, host, look.far, look.nudge, 0)
    else
        line:SetHeight(3)
        line:SetPoint(look.near, host, look.far, 0, look.nudge)
    end

    line.glow:ClearAllPoints()
    line.glow:SetPoint("TOPLEFT", -look.spread[1], look.spread[2])
    line.glow:SetPoint("BOTTOMRIGHT", look.spread[1], -look.spread[2])

    -- The label goes above a line lying down and beside one standing up,
    -- so it never sits on top of the host it is naming.
    line.text:ClearAllPoints()
    if sideways then
        line.text:SetPoint(look.near, line, look.far, look.nudge * 4, 0)
    else
        line.text:SetPoint("BOTTOM", line, "TOP", 0, 4)
    end

    line.text:SetText(look.label .. (label or "here"))
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

    -- The name sits on a frame of its own, above everything drawn on the
    -- handle.
    --
    -- Draw layers only order regions inside one frame. Edit Mode puts its
    -- selection overlay on the handle as a CHILD at ten frame levels up,
    -- and a child frame draws over every region of its parent whatever
    -- layer that region is on - so the label was under the blue, however
    -- high its layer went. Twenty levels up is above the overlay, and the
    -- name reads.
    local labelHost = CreateFrame("Frame", nil, mover)
    labelHost:SetAllPoints(mover)
    labelHost:SetFrameLevel((mover:GetFrameLevel() or 0) + 20)
    mover.labelHost = labelHost

    local label = BazUI.Skin.Theme.FontString(labelHost, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    mover.label = label

    -- As big as it can be and still fit.
    --
    -- A fixed size cannot work here: the handles are whatever size the
    -- things they stand for are, from a two-pixel power bar to a full
    -- width action bar, and the names are whatever the player called them.
    -- One size either swims in the big ones or hangs off the small ones.
    --
    -- So it is measured rather than assumed. Start at whatever the height
    -- allows and step down until the text fits the width, which is the
    -- only way to get the largest size that does - GetStringWidth answers
    -- for the font as it is set, so it has to be asked once per size.
    --
    -- Nothing is truncated and no width is set: a name cut off mid-word is
    -- no use for telling two party bars apart, which is the whole job.
    -- Below the floor it is allowed to overhang instead, which is rare and
    -- still readable.
    local LABEL_MIN, LABEL_MAX = 10, 18

    function mover:FitLabel()
        local text = self.label:GetText() or ""
        if text == "" then return end

        local font = BazUI.Skin.Theme.FontFile()
        if not font then return end

        local room = (self:GetWidth() or 0) - 10
        local tall = math.floor((self:GetHeight() or 0) - 4)

        local size = math.min(LABEL_MAX, math.max(LABEL_MIN, tall))
        while size > LABEL_MIN do
            self.label:SetFont(font, size, "OUTLINE")
            if (self.label:GetStringWidth() or 0) <= room then break end
            size = size - 1
        end
        if size <= LABEL_MIN then
            self.label:SetFont(font, LABEL_MIN, "OUTLINE")
        end
    end

    function mover:SetLabel(text)
        self.label:SetText(text or "")
        self:FitLabel()
    end

    mover:SetLabel(opts.label or "")

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
        -- The handle has just taken the target's size, and the label is
        -- measured against that - so it is refitted here rather than only
        -- when the text changes. A bar resized while the handle is up
        -- would otherwise keep the size it was first fitted for.
        self:FitLabel()
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

    -- Both directions. The target points at its handle so anything drawing
    -- over the target can find it - and the handle points back, because
    -- Edit Mode registers the HANDLE, so everything asked about "this
    -- frame" from in there is asked about the wrong object unless it can
    -- get to the target. The overlay tint was reading as free on every
    -- docked bar for exactly that reason.
    target._bazMover = mover
    mover.target = target

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
