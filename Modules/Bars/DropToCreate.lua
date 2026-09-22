-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Bars: drop it anywhere
--
-- Drag a spell out of the spellbook, let go over the world, and a bar
-- appears there holding it. The same for a macro, a mount, an equipment
-- set or a flyout, because the action registry already knows how to turn
-- any of those into a button. Items are the one exception, for the
-- reason given below.
--
-- The gesture was doing nothing before. Blizzard's answer to a spell
-- dropped on the world is to put it back, which is right when there is
-- nowhere for it to go and a waste of an obvious gesture when there is.
--
-- Let go beside a bar that is already there and that bar grows a slot on
-- the side the drop came from, rather than a second bar appearing next
-- to the first. Two spells dropped in the same corner of the screen
-- should build one bar of two, because that is what it looks like they
-- are doing - and a screen of one-button bars is a layout nobody asked
-- for and has to tidy up by hand.
--
-- While the cursor is within reach of a bar, a ghost of the slot shows
-- where it would go. The ghost is binding: letting go fills exactly the
-- slot that was drawn, and never quietly makes a bar somewhere else
-- instead. That is the contract the dock's green landing line keeps, for
-- the same reason - a preview that sometimes lies is worse than no
-- preview at all.
--
-- Three things it deliberately will not do:
--
--   An item is left alone entirely. Letting go of one over the world is
--   how the game asks whether you want to destroy it, and dropping a bar
--   on top of that question meant nothing could be thrown away while
--   BazUI was loaded. An item still goes onto a bar by being dropped on
--   a slot, which is where that gesture belongs.
--
--   A drag that started on one of our own buttons is left alone. Pulling
--   a spell off a bar and dropping it on the ground is how everybody
--   clears a slot, and answering that with a new bar would mean deleting
--   one every time you tidied up. The flag is set by our own button's
--   drag handler rather than by watching Blizzard's pickup functions,
--   because hooking one of those globals taints it.
--
--   Nothing happens in combat. A bar is made of secure buttons and those
--   cannot be created, resized or moved mid-fight. The drop is refused
--   out loud rather than remembered for later, because by the time the
--   fight ends the cursor is long empty and a bar appearing then would
--   come from nowhere. The ghost stays down too, so nothing is offered
--   that cannot be delivered.
---------------------------------------------------------------------------

local MODULE_NAME = "Bars"
local addon = BazUI:GetModule(MODULE_NAME)
if not addon then return end

-- The module namespace. Every Bars file starts with this line.
local BazBars = BazUI.Bars

local floor = math.floor
local max = math.max

-- How far outside a bar still counts as "on that bar", in screen pixels.
--
-- Dropping onto a bar lands on one of its buttons and never reaches here,
-- so this is only for the gap around the edge - the padding, and the
-- space a short last row leaves. One button's width, because that is the
-- distance at which a person would say "next to it" rather than "near
-- it", and a vaguer radius is the kind of thing that ends in two drops a
-- few pixels apart behaving differently.
local NEAR_PAD = 40

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Everything here is measured in screen pixels.
--
-- A bar carries a scale of its own, and a frame reports its edges in its
-- own units - so a bar at half scale says its top is twice as high as it
-- looks. Comparing that against a cursor position converted through
-- UIParent put a drop near the top of the screen inside a bar sitting at
-- the bottom of it, which is exactly what went wrong: the ability landed
-- in the middle action bar instead of making a bar where it was dropped.
-- Screen pixels are the one space they all share.
local function ScreenEdges(frame)
    local scale = frame:GetEffectiveScale() or 1
    local left, right = frame:GetLeft(), frame:GetRight()
    local bottom, top = frame:GetBottom(), frame:GetTop()
    if not (left and right and bottom and top) then return nil end
    return left * scale, right * scale, bottom * scale, top * scale
end

---------------------------------------------------------------------------
-- Where the drag came from
---------------------------------------------------------------------------

-- What an action bar just put on the cursor.
--
-- Remembered as a thing rather than as a yes-or-no, because a flag can be
-- cleared by any stray cursor event that happens along and then the next
-- drop is treated as fresh. Comparing what is actually on the cursor now
-- against what a bar put there cannot drift: either it is the same thing
-- or it is not.
local carried = nil

local function CursorKey()
    if not GetCursorInfo then return nil end
    local kind, a, b = GetCursorInfo()
    if not kind then return nil end
    return tostring(kind) .. ":" .. tostring(a) .. ":" .. tostring(b)
end

-- Called the moment an action slot hands something to the cursor - ours
-- from Button:StartDrag, Blizzard's from the hook set up below. Read
-- straight away rather than next frame, because the pickup that started
-- the drag has already reached the cursor by the time either runs.
function addon:NoteDragFromButton()
    carried = CursorKey()
end

-- The same note, for a drag off one of Blizzard's own bars.
--
-- Asked of the cursor rather than taken from their buttons. "action" and
-- "petaction" are the game's own words for something lifted out of a bar
-- slot, and nothing but a bar slot produces them - so this covers every
-- bar they have, including the ones that only exist while you are on a
-- vehicle or in a special encounter, without knowing any of their names.
--
-- This used to be a HookScript on each of their buttons, and that is what
-- was wrong. On WoW: Forever a cooldown carries a secret number, which
-- the client will only hand to untainted code - and our script on their
-- frame was enough to make their own cooldown update count as ours. The
-- override bar threw on every swap:
--
--   ActionButton.lua:881: bad argument #1 to 'SetCooldown'
--   Secret values are only allowed during untainted execution
--
-- The lesson is the one already written down for frame method hooks: on
-- this client, do not put anything of ours on a frame of theirs that
-- handles the player's own numbers. Ask the game instead.
local BAR_CURSOR = { action = true, petaction = true }

local function NoteBlizzardBarDrag()
    if not GetCursorInfo then return end
    local kind = GetCursorInfo()
    if kind and BAR_CURSOR[kind] then carried = CursorKey() end
end

-- Whether what is on the cursor right now came off an action bar.
local function CameFromABar()
    return carried ~= nil and CursorKey() == carried
end

---------------------------------------------------------------------------
-- What is being dragged
--
-- Worked out once per drag and then remembered, because the ghost asks
-- the question many times a second and answering it means sorting the
-- whole handler registry.
---------------------------------------------------------------------------

local carriedHandler, carriedData, carriedIcon, carriedChecked

-- Whether the cursor is holding an item, which is not ours to answer.
--
-- Letting go of an item over the world is the game's delete gesture: its
-- own handler on this same frame raises the "destroy this?" question,
-- and ours ran afterwards, cleared the cursor out from under it and made
-- a bar. So an item is refused before anything else looks at it.
--
-- Asked of what the cursor is carrying rather than of where the drag
-- began, because an item can come from a bag, the bank, a loot window or
-- an equipment slot, and a list of those places is a list that will be
-- missing one - and every one it misses is something you cannot throw
-- away. This costs the gesture toys and bag items as bar makers, which
-- is a fair trade for never standing between somebody and their rubbish.
local function CarryingAnItem()
    if not GetCursorInfo then return false end
    return (GetCursorInfo()) == "item"
end

local function ForgetCarry()
    carriedHandler, carriedData, carriedIcon, carriedChecked = nil, nil, nil, false
end

-- Settled on the first frame after the pickup, not when the cursor
-- changes: the pickup raises CURSOR_CHANGED from inside Blizzard's own
-- drag handler, which is before the hook that tells us the drag came off
-- an action bar has run. A frame later, both are known.
local function Carry()
    if carriedChecked then return carriedHandler, carriedData end
    carriedChecked = true

    if CameFromABar() or CarryingAnItem() then return nil end

    carriedHandler, carriedData = BazBars.Actions:FromCursor()
    if carriedHandler and carriedHandler.getIcon then
        carriedIcon = carriedHandler.getIcon(carriedData)
    end
    return carriedHandler, carriedData
end

---------------------------------------------------------------------------
-- Reading a bar's grid
---------------------------------------------------------------------------

local function Enabled()
    local db = addon.db and addon.db.profile
    return not db or db.dropCreatesBar ~= false
end

-- How many cells the bar has along the screen's x and y.
--
-- A vertical bar swaps the two: its rows run across and its columns run
-- down, which is how LayoutButtons draws it. Everything below works in
-- screen terms - across and down - and turns that back into a row and a
-- column only where it has to touch the data.
local function Grid(barData)
    if barData.orientation == "vertical" then
        return barData.rows, barData.cols
    end
    return barData.cols, barData.rows
end

local function CellToRowCol(barData, i, j)
    if barData.orientation == "vertical" then return i, j end
    return j, i
end

-- A slot's size, and the distance from one slot's edge to the next, both
-- in screen pixels. Button size is the same for every bar; only the gap
-- between them is a setting.
local function CellSize(frame, barData)
    local scale = frame:GetEffectiveScale() or 1
    local spacing = BazBars.GetBarSetting(barData, "spacing") or BazBars.DEFAULT_SPACING
    return BazBars.DEFAULT_BUTTON_SIZE * scale,
           (BazBars.DEFAULT_BUTTON_SIZE + spacing) * scale
end

-- Whether letting go here would reach the world at all.
--
-- The reach around a bar can lie over another window, or over one of
-- Blizzard's own buttons, and whatever the mouse is over takes the drop
-- instead of us. Offering a slot there would be offering something
-- somebody else is going to answer. It settles the slots of our own bars
-- too: a button under the cursor gets the drop directly, so the ghost
-- has nothing to say about it.
local function OverTheWorld()
    if not GetMouseFoci then return true end
    local foci = GetMouseFoci()
    local focus = foci and foci[1]
    return focus == nil or focus == WorldFrame
end

local function CellIndex(offset, stride, count)
    local index = floor(offset / stride) + 1
    if index < 1 then return 1 end
    if index > count then return count end
    return index
end

---------------------------------------------------------------------------
-- The slot a drop would land in
--
-- One table, filled by the ghost and read by the drop, so that the two
-- cannot come to different answers. The cell is held as across-and-down
-- indices rather than as a row and a column, because growing the bar
-- renumbers one of them and the cell is known before the growing is
-- done.
---------------------------------------------------------------------------

local target = {}

local function ClearTarget()
    target.frame = nil
end

-- The nearest bar the cursor is within reach of, measured from its edge.
local function NearestBar(x, y)
    local Bar = addon.Bar
    if not (Bar and Bar.GetAll) then return nil end

    local best, bestDist
    for _, frame in pairs(Bar:GetAll()) do
        if frame and frame:IsShown() and frame.barData then
            local left, right, bottom, top = ScreenEdges(frame)
            if left then
                local dx = max(left - x, x - right, 0)
                local dy = max(bottom - y, y - top, 0)
                if dx <= NEAR_PAD and dy <= NEAR_PAD then
                    local dist = dx * dx + dy * dy
                    if not bestDist or dist < bestDist then
                        best, bestDist = frame, dist
                    end
                end
            end
        end
    end
    return best
end

-- Which slot of that bar the cursor is asking for, or nil if the bar has
-- no answer and the drop should make a bar of its own.
--
-- Three outcomes, in the order they are preferred: an empty slot the
-- cursor is over, an empty slot on the edge it came in by, or a new slot
-- grown onto that edge. Filling a hole before growing matters because a
-- bar with a gap in it is a bar asking to be filled, and because an
-- empty slot can be set to draw nothing at all - growing past one of
-- those would leave an invisible hole behind the thing just dropped.
local function Resolve(x, y)
    local frame = NearestBar(x, y)
    if not frame then return nil end

    local barData = frame.barData
    local left, right, bottom, top = ScreenEdges(frame)
    local across, down = Grid(barData)
    local size, stride = CellSize(frame, barData)

    local i = CellIndex(x - left, stride, across)
    local j = CellIndex(top - y, stride, down)

    -- Which way the cursor left the bar, if it left it at all. Past a
    -- corner, the side it is further past wins - the one a person would
    -- say they were beside.
    local outLeft, outRight = left - x, x - right
    local outBottom, outTop = bottom - y, y - top
    local outAcross, outDown = max(outLeft, outRight), max(outBottom, outTop)

    local edge
    if outAcross > 0 or outDown > 0 then
        if outAcross >= outDown then
            edge = (outLeft > 0) and "LEFT" or "RIGHT"
        else
            edge = (outTop > 0) and "TOP" or "BOTTOM"
        end
    end

    -- The cell the drop is aimed at: the one under the cursor when it is
    -- over the bar, otherwise the one on the edge it came in by.
    if edge == "LEFT" then i = 1
    elseif edge == "RIGHT" then i = across
    elseif edge == "TOP" then j = 1
    elseif edge == "BOTTOM" then j = down
    end

    local row, col = CellToRowCol(barData, i, j)
    local btn = frame.buttons[row] and frame.buttons[row][col]

    if btn and not btn.action then
        edge = nil                  -- there is a slot for it already
    elseif not edge then
        return nil                  -- over a full slot: the button takes the drop
    else
        -- One past the end, on the side it came in by.
        if edge == "LEFT" then i = 0
        elseif edge == "RIGHT" then i = across + 1
        elseif edge == "TOP" then j = 0
        else j = down + 1
        end

        -- A bar has a most it can hold, and the sliders in the options
        -- say what it is. Past that, the drop makes a bar instead.
        local acrossEdge = (edge == "LEFT" or edge == "RIGHT")
        local growsRows = (acrossEdge == (barData.orientation == "vertical"))
        if growsRows then
            if barData.rows + 1 > BazBars.MAX_ROWS then return nil end
        elseif barData.cols + 1 > BazBars.MAX_COLS then
            return nil
        end
    end

    target.frame = frame
    target.barData = barData
    target.edge = edge
    target.i, target.j = i, j
    target.size = size
    target.x = left + (i - 1) * stride + size / 2
    target.y = top - (j - 1) * stride - size / 2
    return target
end

---------------------------------------------------------------------------
-- The ghost
---------------------------------------------------------------------------

local ghost

local function Ghost()
    if ghost then return ghost end

    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:Hide()

    -- The dock's landing green, because this is the same promise being
    -- made about a different thing, and one color for "it goes here" is
    -- one thing to learn instead of two.
    local rim = ghost:CreateTexture(nil, "BACKGROUND")
    rim:SetAllPoints()
    rim:SetColorTexture(0.35, 1, 0.45, 0.95)

    local back = ghost:CreateTexture(nil, "BORDER")
    back:SetPoint("TOPLEFT", 2, -2)
    back:SetPoint("BOTTOMRIGHT", -2, 2)
    back:SetColorTexture(0, 0, 0, 0.7)

    -- The thing being dragged, faint: a ghost of the button it is about
    -- to become says which slot and what goes in it at once, and the
    -- slot is the size of a real one so there is nothing to hunt for.
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetPoint("TOPLEFT", 2, -2)
    ghost.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    ghost.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ghost.icon:SetAlpha(0.6)

    return ghost
end

local function HideGhost()
    if ghost then ghost:Hide() end
    ClearTarget()
end

local function ShowGhost(slot)
    local frame = Ghost()

    -- Drawn on UIParent, so its size and its offsets are in UIParent's
    -- units while everything above is in screen pixels.
    local ui = UIParent:GetEffectiveScale() or 1
    frame:SetSize(slot.size / ui, slot.size / ui)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", slot.x / ui, slot.y / ui)
    frame.icon:SetTexture(carriedIcon or QUESTION_MARK)
    frame:Show()
end

-- Only runs while something is on the cursor, started and stopped by the
-- cursor changing rather than left ticking over for the whole session.
local TRACK_INTERVAL = 0.03
local driver

local function StopTracking()
    if driver then driver:Hide() end
    HideGhost()
end

local function Track()
    if not driver then
        driver = CreateFrame("Frame")
        driver:Hide()
        driver:SetScript("OnUpdate", function(self, elapsed)
            self.wait = (self.wait or 0) - elapsed
            if self.wait > 0 then return end
            self.wait = TRACK_INTERVAL

            if not (GetCursorInfo and GetCursorInfo()) then
                StopTracking()
                return
            end

            -- Offering a slot in combat would be offering what the drop
            -- cannot deliver: the bar cannot grow until the fight ends.
            if InCombatLockdown() or not Carry() then
                HideGhost()
                return
            end

            local slot = OverTheWorld() and Resolve(GetCursorPosition())

            -- Only where the drop would make something that is not
            -- there yet.
            --
            -- Resolve answers with an existing empty slot whenever there
            -- is one to answer with - that is the point of it, a bar with
            -- a hole in it should be filled before it is grown - and the
            -- ghost was drawn on that slot too. Which reads as an offer to
            -- add a slot, on a slot, and the likeliest way to meet it is
            -- to aim just past the end of a bar whose last slot is empty:
            -- the cell index clamps to that last slot and the ghost lands
            -- squarely on top of it, question mark and all.
            --
            -- A slot that is already drawn is its own preview. The ghost
            -- has nothing to add there, and saying it twice says something
            -- untrue. slot.edge is exactly the distinction: set when the
            -- bar would grow, nil when the drop is going somewhere that
            -- already exists.
            if slot and slot.edge then ShowGhost(slot) else HideGhost() end
        end)
    end
    driver.wait = 0
    driver:Show()
end

---------------------------------------------------------------------------
-- Making room
---------------------------------------------------------------------------

local function PlaceOn(btn, handler, data)
    addon.Button:SetActionFromHandler(btn, handler, data)
end

-- Move every action on the bar one slot along, to clear the first one.
--
-- Growing on the left or the top means the new slot is slot one and
-- everything already there is renumbered, since a bar's slots are laid
-- out in order and there is no room before the first. The keybind travels
-- with the action rather than staying on the slot: a key is remembered as
-- the spell it casts, and a bar that grew by one on the left should not
-- silently re-point every key on it.
local function ShiftActions(frame, barData, dRow, dCol)
    local Button = addon.Button
    local binds = addon.db.profile.keybinds
    local moves = {}

    for r = 1, barData.rows do
        local row = frame.buttons[r]
        if row then
            for c = 1, barData.cols do
                local btn = row[c]
                if btn and btn.action then
                    moves[#moves + 1] = {
                        btn = btn, row = r, col = c,
                        type = btn.action.type, data = btn.action.data,
                        key = binds and binds[btn:GetName()] or nil,
                    }
                end
            end
        end
    end

    -- Emptied first, all of them, so an action landing where another one
    -- is still sitting cannot overwrite it.
    for _, move in ipairs(moves) do
        if move.key then addon.Keybinds:ClearBinding(move.btn:GetName()) end
        Button:ClearAction(move.btn)
    end

    for _, move in ipairs(moves) do
        local row = frame.buttons[move.row + dRow]
        local btn = row and row[move.col + dCol]
        local handler = BazBars.Actions:Get(move.type)
        if btn and handler then
            PlaceOn(btn, handler, move.data)
            if move.key then addon.Keybinds:SetBinding(btn:GetName(), move.key) end
        end
    end
end

-- Grow the bar by one slot on the edge the drop came in by, and hand
-- back the slot that appeared.
--
-- A bar's buttons hang off its center, so a grid one slot wider grows
-- half a slot in each direction and everything already on the bar slides
-- half a slot away from where it was - the drop would move the thing it
-- was aimed beside. So the bar is put back by whatever its far edge
-- moved: grow on the right and the left edge is held still, grow on the
-- top and the bottom edge is. Measured rather than worked out from the
-- numbers, because a bar can be anchored by any of its corners and only
-- the edges say the same thing in every case.
local function Grow(slot)
    local frame, barData = slot.frame, slot.barData
    local edge = slot.edge
    local acrossEdge = (edge == "LEFT" or edge == "RIGHT")
    local growsRows = (acrossEdge == (barData.orientation == "vertical"))
    local before = (edge == "LEFT" or edge == "TOP")

    local left0, right0, bottom0, top0 = ScreenEdges(frame)

    addon.Bar:Resize(frame,
        growsRows and (barData.rows + 1) or barData.rows,
        growsRows and barData.cols or (barData.cols + 1),
        BazBars.GetBarSetting(barData, "spacing"))

    if before then
        ShiftActions(frame, barData, growsRows and 1 or 0, growsRows and 0 or 1)
    end

    -- A docked bar is positioned by the dock, and moving it here would
    -- only be undone - it lays itself out again around the new size.
    local Dock = BazUI.Dock
    if left0 and not (Dock and Dock:IsDocked(frame)) then
        local left1, right1, bottom1, top1 = ScreenEdges(frame)
        local scale = frame:GetEffectiveScale() or 1
        local dx = ((edge == "LEFT") and (right0 - right1) or (left0 - left1)) / scale
        local dy = ((edge == "TOP") and (bottom0 - bottom1) or (top0 - top1)) / scale
        local point, _, relPoint, px, py = frame:GetPoint()
        if point then
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, relPoint, px + dx, py + dy)
            addon.Bar:SavePosition(frame)
        end
    end

    -- The new slot arrives bare: whether empty slots are drawn at all,
    -- whether they take clicks and whether they wear the slot art are
    -- all bar-wide settings nothing has told it about.
    addon.Bar:UpdateButtonVisibility(frame)
    addon.Bar:ApplyClickThrough(frame)
    addon.Bar:UpdateSlotArt(frame)
    if Dock then Dock:HostChanged(frame) end

    local i, j = slot.i, slot.j
    if before then
        if acrossEdge then i = 1 else j = 1 end
    end

    local row, col = CellToRowCol(barData, i, j)
    return frame.buttons[row] and frame.buttons[row][col]
end

-- The slot the ghost was drawing, made real if it does not exist yet.
local function SlotFor(slot)
    if slot.edge then return Grow(slot) end
    local row, col = CellToRowCol(slot.barData, slot.i, slot.j)
    return slot.frame.buttons[row] and slot.frame.buttons[row][col]
end

---------------------------------------------------------------------------
-- Making the bar
---------------------------------------------------------------------------

-- A bar of one, centered where it was dropped.
--
-- The position is worked out after the bar exists, because the offset in
-- a SetPoint is read in the coordinate space of the frame being placed -
-- so it depends on that bar's own scale, and there is no bar to ask until
-- there is one.
local function MakeBarAt(x, y, handler, data)
    local id = addon:CreateNewBar(1, 1)
    if not id then return false end

    local frame = addon.Bar:Get(id)
    if not frame then return false end

    local scale = frame:GetEffectiveScale() or 1
    local barData = addon.db.profile.bars[id]
    barData.pos = {
        point = "CENTER", relPoint = "BOTTOMLEFT",
        x = x / scale, y = y / scale,
    }
    addon.Bar:RestorePosition(frame, barData)

    local btn = frame.buttons[1] and frame.buttons[1][1]
    if btn then PlaceOn(btn, handler, data) end
    return true
end

---------------------------------------------------------------------------
-- The drop
---------------------------------------------------------------------------

local function OnWorldClick()
    if not Enabled() then return end

    -- Nothing on the cursor is every other click in the game, so this
    -- gets out of the way first.
    if not (GetCursorInfo and GetCursorInfo()) then return end

    -- Off a bar to begin with: this is somebody clearing a slot, which is
    -- what dropping on the ground has always meant. Ours and Blizzard's
    -- alike - a spell pulled off either is being put away, not asking for
    -- somewhere new to live. Carry answers nil for those.
    local handler, data = Carry()
    if not handler then return end

    if InCombatLockdown() then
        addon:Print("A new bar has to wait until you are out of combat.")
        return
    end

    -- Whatever the ghost was showing when the button went down, rather
    -- than a fresh answer: the promise on screen is the one that gets
    -- kept. Nothing falls through to making a bar from here either - a
    -- slot was offered on that bar, and a bar appearing somewhere else
    -- because the offer could not be met would be the wrong apology.
    if ghost and ghost:IsShown() and target.frame then
        local btn = SlotFor(target)
        HideGhost()
        if btn then
            ClearCursor()
            PlaceOn(btn, handler, data)
        end
        return
    end

    -- Left in screen pixels: see ScreenEdges above.
    local x, y = GetCursorPosition()
    if MakeBarAt(x, y, handler, data) then
        ClearCursor()
    end
end

BazUI:QueueForLogin(function()
    if not (WorldFrame and WorldFrame.HookScript) then return end

    -- HookScript rather than a hook on one of Blizzard's functions: this
    -- adds a listener to their frame and takes nothing over, so their own
    -- handling of the click still runs and nothing is tainted by it.
    WorldFrame:HookScript("OnMouseDown", OnWorldClick)

    -- The cursor emptying is the end of that drag however it ended, so
    -- what it was carrying is forgotten. Without this, a spell put back
    -- where it came from would leave the note standing and the next drag
    -- of the same spell out of the spellbook would be mistaken for it.
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("CURSOR_CHANGED")
    watcher:SetScript("OnEvent", function()
        ForgetCarry()
        if GetCursorInfo and GetCursorInfo() then
            NoteBlizzardBarDrag()
            if Enabled() then Track() end
        else
            carried = nil
            StopTracking()
        end
    end)

end)
