-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Dock
--
-- Bars and aura blocks attach to things. A health bar sits under an
-- action bar and takes its width; a power bar sits under the health bar;
-- a block of auras sits above one of them, aligned to an edge or centered.
-- Anything can also float, which is just being docked to nothing.
--
-- Any of a host's four sides. Below and above take the host's width;
-- left and right take its height. Same engine either way - see The four
-- edges, further down.
--
-- Two behaviors against a host, declared by the follower:
--
--   "stretch"  fill the host across the line and sit on its edge. Bars.
--   "align"    keep your own size and sit at the near end, the middle or
--              the far end of the line. Aura blocks.
--
-- Rules the suite settled on:
--
--   A chain hides as a unit. Dock a power bar to a health bar and the
--   power bar goes when the health bar does, because a reading attached
--   to something absent is noise.
--
--   A hidden follower closes the gap behind it, unless it is told to
--   hold its place. The cast bar holds its place by default: it appears
--   and vanishes several times a minute, and a layout that shuffles
--   while you are casting is worse than a little empty space.
--
--   Attaching, detaching and re-ordering happen out of combat only. The
--   caller is expected to have refused already; this simply will not
--   relayout during combat, so nothing half-moves.
--
-- Positions are resolved by walking down from the host, so a follower of
-- a follower lands in the right place however deep the chain goes.
---------------------------------------------------------------------------

BazUI.Dock = BazUI.Dock or {}
local Dock = BazUI.Dock

-- [frame] = { host, edge, mode, align, order, gap, reserve }
local links = {}
-- [host] = { follower, follower, ... }
local followers = {}

local DEFAULT_GAP = 2

-- True while the dock is showing or hiding a follower itself, so the
-- events that causes can be told apart from the ones the game causes.
local settingShown = false

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

-- Which axis an edge's stack runs along. Things docked above and below
-- something form a column; things docked to its sides form a row. Every
-- question the dock asks about arrangement comes back to this one, so
-- there is one table to answer it - EDGES below carries the same letter
-- as part of each edge's geometry, and Dock:EdgeAxis reads it from here.
local STACK_EDGES = {
    V = { TOP = true, BOTTOM = true },
    H = { LEFT = true, RIGHT = true },
}

-- What a stack on each axis is measured by, and so which of a member's
-- two opt-outs applies when walking it. A column is measured by its
-- height, a row by its width.
local COUNTS = { V = "countsHeight", H = "countsWidth" }

local function EdgeStackAxis(edge)
    return STACK_EDGES.V[edge or "BOTTOM"] and "V" or "H"
end

-- Re-fit the stack a frame has just joined or left, when something on
-- the other axis is holding that stack.
--
-- Docking is about stacks, not single bars. A power bar joining the
-- bottom of a health bar that is itself docked to the left of an action
-- bar changes the column the action bar is holding - so the action bar's
-- edge has to be laid out again, or the health bar stays at the full
-- height it was fitted to alone and the power bar hangs off the bottom.
-- The same the other way about: a portrait joining the left of a health
-- bar that sits under an action bar widens the row that action bar is
-- holding. That is exactly what "looks right until a reload" was: in a
-- session the drop re-laid the action bar; on reload the bars attached in
-- saved order and nothing came back for it.
--
-- `start` is the host the member joined or left and `edge` the edge it
-- did so on. Walking up from there, every link on the same axis is still
-- inside this stack; the first one on the other axis is what holds it.
local function RefitStackRoot(start, edge)
    local axis = EdgeStackAxis(edge)
    local link, depth = links[start], 0
    while link and depth < 16 do
        if EdgeStackAxis(link.edge) ~= axis then
            Dock:Relayout(link.host)
            return
        end
        link = links[link.host]
        depth = depth + 1
    end
end

-- opts:
--   edge     "TOP", "BOTTOM", "LEFT" or "RIGHT" - which side of the
--            host to sit on
--   mode     "stretch" (default) or "align"
--   align    for "align": "LEFT", "CENTER" or "RIGHT" on a top or bottom
--            edge, "TOP", "MIDDLE" or "BOTTOM" on a side. Either set is
--            accepted on either edge and means the matching place, so a
--            follower moved from one to the other keeps its arrangement.
--   order    lower sits nearer the host
--   gap      pixels between this and whatever it follows
--   offset   { x, y } nudged off where the dock would otherwise put it
--   reserve  true to hold its place in the stack while hidden
--   seq      the ticket this docking holds - see Dock:StackSettings. A
--            follower is measured against its host's stack as that stack
--            stood when the follower joined it, and this is what says
--            when that was.
--   countsHeight  false to leave this out of the measured height of the
--            column it is in. A casting bar sitting on top of an action
--            bar is part of that stack to the eye but should not make a
--            health bar docked beside the action bar any taller.
--   countsWidth   the same for the width of the row it is in: a portrait
--            beside a health bar should not have to make the power bar
--            under the pair any wider.
--            Two switches rather than one, because a thing can belong to
--            a stack for one purpose and not the other - that casting bar
--            still wants to span the width of the stack it sits on while
--            adding nothing to its height.
--   shown    "own" when something else decides whether this frame is on
--            screen and the dock must not. A health or power bar is shown
--            and hidden by RegisterUnitWatch, in the secure environment,
--            as its unit comes and goes; the dock calling SetShown on it
--            overrides that, and the bar is then stuck whichever way the
--            dock last left it. The dock still reads IsShown to lay out
--            around it - it just never writes.
function Dock:Attach(frame, host, opts)
    if not frame then return end
    opts = opts or {}

    self:Detach(frame, true)

    if not host then
        self:Relayout()
        return
    end

    -- Nought is a gap somebody asked for, so it cannot be treated as
    -- nothing having been asked for: `or DEFAULT_GAP` would quietly put
    -- two pixels back between bars meant to touch.
    local gap = opts.gap
    if gap == nil then gap = DEFAULT_GAP end

    links[frame] = {
        host    = host,
        edge    = opts.edge or "BOTTOM",
        mode    = opts.mode or "stretch",
        align   = opts.align or "LEFT",
        order   = opts.order or 100,
        gap     = gap,
        -- How much of the host an aligned follower takes across the
        -- line: 1 for all of it, 2 for half. Nothing means keep your own
        -- size. Width on a top or bottom edge, height on a side.
        share   = opts.share,
        -- Space left between the things sharing a line. One number for
        -- the line, so whoever asks for the most gets it.
        gutter  = opts.gutter or 0,
        -- Where the follower sits relative to where the dock would put
        -- it. The dock decides the place; this is the hand adjustment on
        -- top, and it is deliberately left out of the stack's own
        -- arithmetic - nudging one bar moves that bar, not everything
        -- hanging below it.
        offsetX = opts.offset and opts.offset.x or 0,
        offsetY = opts.offset and opts.offset.y or 0,
        reserve = opts.reserve and true or false,
        -- When this docking happened, relative to every other one.
        seq     = opts.seq,
        -- Nil is in; only an explicit false is out. One switch per
        -- measurement: a casting bar can span the width of the stack it
        -- sits on and still add nothing to the height that stack is
        -- fitted to. `column` is what the height switch was called when
        -- it was the only one, and profiles saved then still say it.
        countsHeight = not (opts.countsHeight == false or opts.column == false),
        countsWidth  = opts.countsWidth ~= false,
        ownsShown = (opts.shown == "own"),
    }

    followers[host] = followers[host] or {}
    followers[host][#followers[host] + 1] = frame
    self:Relayout(host)
    -- The frame has just taken its host's width; its own followers need
    -- that passed down to them in the same breath.
    self:Relayout(frame)
    -- And the stack it has just joined may be held by something on the
    -- other axis.
    RefitStackRoot(host, links[frame].edge)
end

function Dock:Detach(frame, quiet)
    local link = links[frame]
    if not link then return end
    local oldHost = link.host

    local list = followers[oldHost]
    if list then
        for i = #list, 1, -1 do
            if list[i] == frame then table.remove(list, i) end
        end
        if #list == 0 then followers[oldHost] = nil end
    end
    links[frame] = nil

    if not quiet then
        -- The old host closes the gap, and anything hanging off the
        -- frame we just detached has to follow it to its new size: a
        -- bar that leaves a wide action bar takes its own followers
        -- down to its own width with it.
        self:Relayout(oldHost)
        self:Relayout(frame)
        -- And the stack it left may be held by something on the other
        -- axis, which now has less to hold.
        RefitStackRoot(oldHost, link.edge)
    end
end

---------------------------------------------------------------------------
-- What a saved layout says about stacking
--
-- A bar or a row keeps its docking in the profile, and three of those
-- settings are the dock's own business: the two opt-outs and the ticket
-- saying when it was docked. Read here rather than in each module, so
-- that there is one answer to what an old profile means, and one place
-- the tickets are handed out.
---------------------------------------------------------------------------

-- `column` is what the height opt-out was called while it was the only
-- one. Profiles written then still say it, and they are read rather than
-- rewritten - a profile is the player's, and quietly editing one to suit
-- a rename is how a setting goes missing.
function Dock:CountsHeight(def)
    if def.countsHeight ~= nil then return def.countsHeight and true or false end
    return def.column ~= false
end

function Dock:CountsWidth(def)
    return def.countsWidth ~= false
end

-- The next ticket.
--
-- Kept in the saved variables rather than counted from nothing each
-- session, because the whole point of a ticket is that it still means
-- the same thing after a reload. Shared by every module, since a bar and
-- an aura row can stand in the same stack. Nil before the saved
-- variables are there, and the caller keeps what it had until they are.
function Dock:NextSequence()
    if not BazUIDB then return nil end
    local next = (BazUIDB.dockSequence or 0) + 1
    BazUIDB.dockSequence = next
    return next
end

-- The stack settings a saved layout holds, and its ticket.
--
-- The order you dock in is the order the layout settles in. A stack is
-- measured as it stood when a member joined it, so docking a portrait
-- beside a health bar does not reach back and widen the power bar that
-- joined underneath before the portrait was there. Without that, the
-- last thing you docked quietly resized everything docked before it, and
-- there was no way to build a layout a piece at a time.
--
-- The ticket is stamped afresh whenever the layout names a host or edge
-- it did not name last time, which is what docking somewhere new is, and
-- left alone otherwise - so applying settings, or logging in, does not
-- shuffle a layout that has not changed. Written down rather than
-- inferred from the order things happen to load, which is the difference
-- between a layout that comes back and one that changes on a reload.
function Dock:StackSettings(def)
    local dock   = def.dock
    local hostId = dock and dock.host
    local docked = hostId and hostId ~= "" and hostId ~= "float"
    local signature = docked
        and (tostring(hostId) .. "|" .. tostring(dock.edge or "BOTTOM"))
        or "float"

    if def.dockedAs ~= signature then
        if not docked then
            def.dockedAs = signature
        else
            local seq = self:NextSequence()
            if seq then def.dockedAs, def.dockSeq = signature, seq end
        end
    end

    return self:CountsHeight(def), self:CountsWidth(def), def.dockSeq
end

-- The hand adjustment on a docked frame, and how to change it. Nudging
-- something the dock places cannot work by moving the frame: the next
-- layout pass puts it back. It has to be the dock that knows.
function Dock:GetOffset(frame)
    local link = links[frame]
    if not link then return 0, 0 end
    return link.offsetX or 0, link.offsetY or 0
end

function Dock:SetOffset(frame, x, y)
    local link = links[frame]
    if not link then return 0, 0 end
    link.offsetX, link.offsetY = x or 0, y or 0
    self:Relayout(link.host)
    return link.offsetX, link.offsetY
end

function Dock:Nudge(frame, dx, dy)
    local x, y = self:GetOffset(frame)
    return self:SetOffset(frame, x + (dx or 0), y + (dy or 0))
end

function Dock:GetHost(frame)
    local link = links[frame]
    return link and link.host or nil
end

function Dock:IsDocked(frame)
    return links[frame] ~= nil
end

-- Whether `frame` hangs off `possibleHost` anywhere up its chain. Docking
-- something to its own follower would make a loop that resolves forever,
-- so the question has to be asked before attaching.
function Dock:Follows(frame, possibleHost)
    local link = links[frame]
    local depth = 0
    while link and depth < 16 do
        if link.host == possibleHost then return true end
        frame = link.host
        link = links[frame]
        depth = depth + 1
    end
    return false
end

---------------------------------------------------------------------------
-- Copying a stack
--
-- A chain is usually built once and then wanted again for somebody else:
-- party one's health, power and auras, arranged just so, and now the
-- same for party two. The dock is the only thing that knows the shape of
-- a chain, and it knows nothing about what is in one, so each module
-- says how to copy its own kind of thing and the dock walks the tree.
---------------------------------------------------------------------------

local copiers = {}

-- fn(unit, hostId, edge) makes a copy of this frame, docks it where it
-- is told, and returns the copy's host id and frame. A nil hostId means
-- the copy floats, which is what happens to the root of a stack.
function Dock:RegisterCopier(frame, fn)
    if frame then copiers[frame] = fn end
end

function Dock:UnregisterCopier(frame)
    if frame then copiers[frame] = nil end
end

function Dock:CanCopy(frame)
    return copiers[frame] ~= nil
end

-- Everything hanging off `frame`, worked out before anything is made.
--
-- Walking and copying at the same time is asking for trouble: every copy
-- attaches to something, attaching changes the follower lists being
-- walked, and the walk can end up copying what it has just made. Reading
-- the whole shape first and then building from that list cannot.
local function Plan(frame, parent, edge, out, seen)
    if not frame or seen[frame] then return end
    seen[frame] = true
    out[#out + 1] = { frame = frame, parent = parent, edge = edge }

    local list = followers[frame]
    if not list then return end
    for index = 1, #list do
        local follower = list[index]
        local link = links[follower]
        Plan(follower, frame, link and link.edge or "BOTTOM", out, seen)
    end
end

-- How far down to put the copy of a stack: its own height, plus a
-- little. Eighty pixels was a guess, and a guess is wrong as soon as the
-- stack is taller than the guess, which a health bar with a power bar
-- and two rows of auras under it always is. Measured in screen pixels
-- because the pieces can be at different scales, then handed back in
-- UIParent's, which is what a saved position is in.
local function StackHeight(plan)
    local top, bottom = -math.huge, math.huge
    for _, entry in ipairs(plan) do
        local frame = entry.frame
        local scale = frame:GetEffectiveScale() or 1
        local frameTop, frameBottom = frame:GetTop(), frame:GetBottom()
        if frameTop and frameBottom then
            top = math.max(top, frameTop * scale)
            bottom = math.min(bottom, frameBottom * scale)
        end
    end
    if top <= bottom then return 0 end
    return (top - bottom) / (UIParent:GetEffectiveScale() or 1)
end

function Dock:CopyStack(frame, unit, report)
    local plan = {}
    Plan(frame, nil, nil, plan, {})

    local drop = StackHeight(plan) + 16

    -- Where each original's copy ended up, so a follower's copy can be
    -- told to attach to its own parent's copy rather than to anything
    -- that happens to be lying around.
    local copies, made = {}, 0

    for _, entry in ipairs(plan) do
        local copier = copiers[entry.frame]
        if copier then
            local hostId = entry.parent and copies[entry.parent] or nil
            -- Only the root is placed; everything else is docked to the
            -- copy above it and goes wherever that goes.
            local newId, newFrame = copier(unit, hostId, entry.edge,
                (not hostId) and drop or nil)
            if newFrame then
                copies[entry.frame] = newId
                made = made + 1
                if report then
                    report[#report + 1] = {
                        id     = newId,
                        host   = hostId,
                        docked = self:IsDocked(newFrame),
                    }
                end
            end
        end
    end

    return made
end

-- The corner a follower is hung by, for anything that has to sit over
-- it and should grow the same way it does.
function Dock:FollowerPoint(frame)
    local link = links[frame]
    return link and link.point or nil
end

function Dock:GetFollowers(host)
    return followers[host]
end


---------------------------------------------------------------------------
-- Hosts you can pick from
--
-- Docking is a setting, so the thing a bar docks to has to survive a
-- reload. Frames do not, so a host registers under a name and a stable
-- id, and a follower stores the id. Anything can be a host, including
-- another follower, which is what makes a chain.
---------------------------------------------------------------------------

local hosts = {}        -- [id] = { frame, label, order }

function Dock:RegisterHost(id, frame, label, order)
    if not (id and frame) then return end
    hosts[id] = { frame = frame, label = label or id, order = order or 100 }
    self:WatchHost(frame)
    self:ResolvePending(id)
end

function Dock:UnregisterHost(id)
    hosts[id] = nil
end

function Dock:GetHostFrame(id)
    local entry = hosts[id]
    return entry and entry.frame or nil
end

-- Every host a bar could be attached to, for a settings dropdown.
function Dock:GetHosts()
    local out = {}
    for id, entry in pairs(hosts) do
        out[#out + 1] = { id = id, label = entry.label, order = entry.order }
    end
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.label < b.label
    end)
    return out
end

-- A follower can ask for a host that does not exist yet, because action
-- bars are built after the thing docking to them. The request is kept
-- and honored when the host turns up.
local waiting = {}

function Dock:AttachTo(frame, hostId, opts)
    if not frame then return end
    if not hostId or hostId == "" or hostId == "float" then
        waiting[frame] = nil
        self:Detach(frame)
        return
    end

    local host = self:GetHostFrame(hostId)
    if not host then
        waiting[frame] = { hostId = hostId, opts = opts }
        return
    end
    waiting[frame] = nil
    self:Attach(frame, host, opts)
end

function Dock:ResolvePending(hostId)
    for frame, request in pairs(waiting) do
        if request.hostId == hostId then
            waiting[frame] = nil
            self:Attach(frame, self:GetHostFrame(hostId), request.opts)
        end
    end
end

---------------------------------------------------------------------------
-- Visibility
--
-- A follower is only ever as visible as what it is attached to, all the
-- way up. Asked of the host rather than stored, so a host hidden by a
-- state driver we never see still takes its followers with it.
---------------------------------------------------------------------------

local function HostChainShown(frame)
    local link = links[frame]
    local depth = 0
    while link and depth < 16 do
        if not link.host:IsShown() then return false end
        frame = link.host
        link = links[frame]
        depth = depth + 1
    end
    return true
end

-- Whether this follower should be drawn at all: what it wants, and what
-- the chain above it allows.
function Dock:ShouldShow(frame)
    if frame._dockWanted == false then return false end
    return HostChainShown(frame)
end

local pendingShow = {}

-- A follower says whether it wants to be seen; the chain decides the
-- rest. Callers use this instead of Show and Hide so the stack can
-- reflow around them.
--
-- Showing and hiding a protected frame is itself protected, even when it
-- is already in the state you are asking for, so a secure bar is left
-- alone during combat and caught up when it ends. A bar that has to
-- appear mid-fight, which means any bar tied to whether a unit exists,
-- should be handed to RegisterUnitWatch instead: the game does it in the
-- secure environment and never needs us.
function Dock:SetShown(frame, wanted)
    wanted = wanted and true or false
    frame._dockWanted = wanted

    if frame:IsProtected() and InCombatLockdown() then
        pendingShow[frame] = true
        return
    end

    -- A frame that owns its visibility is only ever told what is wanted
    -- of it; whether it appears is the unit watch's call.
    local link = links[frame]
    if not (link and link.ownsShown) then
        frame:SetShown(wanted and HostChainShown(frame))
    end

    -- Position is a separate question, and one that has to wait: moving
    -- anything is protected too. A bar that reserves its slot is already
    -- in the right place, which is what lets a cast bar appear mid-cast.
    if not InCombatLockdown() then
        if link then self:Relayout(link.host) end
    end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function SortedFollowers(host, edge)
    local out = {}
    for _, frame in ipairs(followers[host] or {}) do
        if links[frame].edge == edge then out[#out + 1] = frame end
    end
    table.sort(out, function(a, b)
        local la, lb = links[a], links[b]
        if la.order ~= lb.order then return la.order < lb.order end
        return tostring(a) < tostring(b)
    end)
    return out
end

---------------------------------------------------------------------------
-- The four edges
--
-- TOP and BOTTOM stack their lines up and down the screen and share each
-- line left to right. LEFT and RIGHT are the same thing with the two axes
-- swapped: lines march sideways, and the things on one line sit above and
-- below each other.
--
-- That is why there is one layout pass rather than two. A second copy of
-- it for the sides would be the same arithmetic with the words changed,
-- and the first bug found in one of them would live on in the other.
--
--   stack  which way lines march away from the host, V or H
--   away   +1 or -1 along that axis, outward from the host's edge
--   near   the side of the follower that touches the host
--
-- The host's own anchor side is the edge itself, so it needs no entry.
---------------------------------------------------------------------------

local EDGES = {
    BOTTOM = { stack = "V", away = -1, near = "TOP"    },
    TOP    = { stack = "V", away =  1, near = "BOTTOM" },
    LEFT   = { stack = "H", away = -1, near = "RIGHT"  },
    RIGHT  = { stack = "H", away =  1, near = "LEFT"   },
}

local EDGE_ORDER = { "BOTTOM", "TOP", "LEFT", "RIGHT" }

-- What an alignment means on each axis.
--
-- There are only ever three places on a line - the near end, the middle,
-- the far end - and each axis has its own words for them. A follower
-- saved as aligned LEFT and then moved onto a side edge still means the
-- near end of its line, so it is translated here rather than being left
-- holding a value that axis has never heard of. Nothing saved needs
-- changing, and moving a bar from the bottom to the side keeps the
-- arrangement you had.
local ALIGN = {
    V = { LEFT = "LEFT", CENTER = "CENTER", RIGHT  = "RIGHT",
          TOP  = "LEFT", MIDDLE = "CENTER", BOTTOM = "RIGHT" },
    H = { TOP  = "TOP",  MIDDLE = "MIDDLE", BOTTOM = "BOTTOM",
          LEFT = "TOP",  CENTER = "MIDDLE", RIGHT  = "BOTTOM" },
}

-- The corner or side of a frame that an alignment picks out. The middle
-- of a line has no corner - it anchors by the middle of the near side -
-- and the two orders are only because WoW names its corners top first.
local function Anchor(geo, align, side)
    if align == "CENTER" or align == "MIDDLE" then return side end
    if geo.stack == "V" then return side .. align end
    return align .. side
end

-- Which way an edge runs, and what an alignment is called on it. Both
-- are asked by the settings panels, so the words on a dropdown and the
-- arithmetic that places the bar come from the same table rather than
-- from two that have to be kept in step.
function Dock:EdgeAxis(edge)
    return EdgeStackAxis(edge)
end

function Dock:AlignOnEdge(edge, align)
    local axis = self:EdgeAxis(edge)
    return ALIGN[axis][align or "LEFT"] or (axis == "V" and "LEFT" or "TOP")
end

-- One layout pass over a frame's followers, and theirs, and so on down.
--
-- Declared ahead of its body so that the measuring below can ask for it:
-- fitting a stack means laying it out to see where the pieces landed.
--
-- One pass, deliberately. The two passes a layout needs are taken at the
-- entry points below, each of them walking the whole tree once; taking
-- them here as well would double the work at every level of the tree
-- instead of once for the tree.
local PlaceOneEdge
local function PlaceEdges(frame)
    for _, edge in ipairs(EDGE_ORDER) do PlaceOneEdge(frame, edge) end
end

-- The stack a frame belongs to along one axis: the frame, plus whatever
-- is docked to it on the two edges that run that way, and so on down. A
-- column ("V") is the run above and below it; a row ("H") is the run to
-- either side.
--
-- Branches on the other axis are deliberately left out. Something docked
-- to the left of a health bar sits beside that health bar's column rather
-- than in it, and counting it would shrink the column to make room for a
-- neighbour.
--
-- A member that asked to be left out of this measurement is left out
-- along with everything stacked on it: it is not part of the stack being
-- measured, so neither is anything that hangs off it.
--
-- `limit` is a ticket, and with one given the stack is the one that
-- stood when that ticket was handed out: members that docked later are
-- left out, along with whatever hangs off them. That is what makes the
-- order you dock in stick. Without one the whole stack is walked, which
-- is what a stack being fitted wants - a follower always brings all of
-- its own with it, however lately any of it arrived.
local function Stack(frame, axis, out, seen, limit)
    if not frame or seen[frame] then return end
    seen[frame] = true
    out[#out + 1] = frame

    for _, follower in ipairs(followers[frame] or {}) do
        local link = links[follower]
        local edge = link and link.edge or "BOTTOM"
        local later = limit and link and link.seq and link.seq > limit
        if STACK_EDGES[axis][edge]
            and not (link and link[COUNTS[axis]] == false)
            and not later then
            Stack(follower, axis, out, seen, limit)
        end
    end
end

-- Where a frame begins and ends along an axis, in screen pixels: bottom
-- and top for a column, left and right for a row. Screen pixels because
-- two frames at different scales are only comparable there.
local function Edges(frame, axis)
    local scale = frame:GetEffectiveScale() or 1
    local lo, hi
    if axis == "V" then lo, hi = frame:GetBottom(), frame:GetTop()
    else                lo, hi = frame:GetLeft(),   frame:GetRight() end
    if not (lo and hi) then return nil end
    return lo * scale, hi * scale
end

-- How far a group of frames reaches along an axis. Anchored on one of
-- them so that a group whose other members have never been placed still
-- answers with something; nil only if that one has no place either.
local function Bounds(frames, anchor, axis)
    local lo, hi = Edges(anchor, axis)
    if not lo then return nil end
    for _, member in ipairs(frames) do
        local memberLo, memberHi = Edges(member, axis)
        if memberLo then
            lo, hi = math.min(lo, memberLo), math.max(hi, memberHi)
        end
    end
    return lo, hi
end

-- How big a host's stack is along an axis, and how far it reaches past
-- the host itself at each end.
--
-- This is what a follower on the other axis is measured against, and the
-- rule is the same whichever way round it runs: a portrait docked to the
-- left of a health bar with a power bar under it stands as tall as the
-- pair, and a bar docked under that pair runs as wide as the pair. The
-- stack is the thing the follower is beside; the host is merely the
-- member it happens to be attached to.
--
-- `before` is the overhang at the low end - below for a column, to the
-- left for a row - and `after` the one at the high end.
local function StackExtent(host, axis, limit)
    local stack = {}
    Stack(host, axis, stack, {}, limit)

    local lo, hi = Bounds(stack, host, axis)
    if not lo then return 0, 0, 0 end
    local hostLo, hostHi = Edges(host, axis)
    return math.max(0, hi - lo), math.max(0, hostLo - lo), math.max(0, hi - hostHi)
end

-- How far a host's stack reaches past the host itself, at each end of
-- the line a follower on this edge would lie along. In screen pixels:
-- `before` at the low end - below for a column, to the left for a row -
-- and `after` at the high end.
--
-- Public because the landing line drawn while you drag needs it. You
-- dock to a stack rather than to a bar, so the line has to reach as far
-- as the thing it is promising - and it leaves out whatever the stack
-- leaves out, since a member that does not count toward the size is not
-- going to widen the drop either.
function Dock:StackOverhang(host, edge)
    if not host then return 0, 0 end
    -- The axis a follower spans is the one the edge does not stack along:
    -- something docked below spans the host's row, something docked to a
    -- side spans its column.
    local axis = (EdgeStackAxis(edge) == "V") and "H" or "V"
    local _, before, after = StackExtent(host, axis)
    return before, after
end

-- How thick a frame's stack is across itself: the height of a row, the
-- width of a column, in screen pixels.
--
-- What the lines on an edge are spaced by. Two bars docked to the same
-- bottom edge sit one under the other, and the second has to clear not
-- just the first but whatever the first is carrying beside it.
local function StackThickness(frame, axis, measure)
    local stack = {}
    Stack(frame, axis, stack, {})
    local lo, hi = Bounds(stack, frame, measure)
    if not lo then return 0 end
    return math.max(0, hi - lo)
end

-- Fit a follower and everything stacked on it along an axis into the room
-- across the line, each piece keeping its share of it.
--
-- What should match an action bar is the whole column beside it, not the
-- health bar at the top of that column - stretching only the direct
-- follower left the power bar hanging past the bottom - and the whole row
-- under it, not the health bar in the middle of that row. So the stack is
-- measured, the gaps between its pieces come off the top, and what is
-- left is divided out in the proportions the pieces already had.
--
-- Settles after one pass and stays there: once the stack adds up to the
-- room available, the next pass divides that room by itself and changes
-- nothing. A stack of one is the plain old behavior exactly - it
-- stretches to the host.
--
-- Returns how much of the stack lies before the follower itself - above
-- it in a column, left of it in a row - so the caller can hang the
-- follower far enough along for the two stacks to start together.
-- Measured rather than summed: where the pieces sit depends on which
-- edges they hang from, and they are only there once they have been laid
-- out against their new sizes. Relative to the follower, they already
-- are.
local function FitStack(frame, axis, across)
    local stack = {}
    Stack(frame, axis, stack, {})

    local sizes, gaps = 0, 0
    for index, member in ipairs(stack) do
        local size = (axis == "V") and member:GetHeight() or member:GetWidth()
        sizes = sizes + ((size or 0) * (member:GetEffectiveScale() or 1))
        if index > 1 then
            local link = links[member]
            gaps = gaps + (link and link.gap or 0)
        end
    end
    if sizes <= 0 then return 0 end

    local room = math.max(1, across - gaps)
    local factor = room / sizes
    if math.abs(factor - 1) >= 0.001 then
        for _, member in ipairs(stack) do
            -- No scale conversion on the way back out: the factor has no
            -- units, so a size in the member's own scale stays in it.
            if axis == "V" then
                local want = math.max(1, (member:GetHeight() or 0) * factor)
                if member.SetOuterSize then member:SetOuterSize(nil, want)
                else member:SetHeight(want) end
            else
                local want = math.max(1, (member:GetWidth() or 0) * factor)
                if member.SetOuterSize then member:SetOuterSize(want, nil)
                else member:SetWidth(want) end
            end
        end
    end

    PlaceEdges(frame)
    local lo, hi = Bounds(stack, frame, axis)
    if not lo then return 0 end
    local frameLo, frameHi = Edges(frame, axis)
    -- A column is hung from its top, a row from its left.
    if axis == "V" then return hi - frameHi end
    return frameLo - lo
end

function PlaceOneEdge(host, edge)
    local geo = EDGES[edge]
    if not geo then return end

    local list = SortedFollowers(host, edge)
    if #list == 0 then return end

    local vertical = (geo.stack == "V")
    local function AlignOf(link)
        return ALIGN[geo.stack][link.align or "LEFT"]
            or (vertical and "LEFT" or "TOP")
    end

    -- Which way the host's own stack runs: across a top or bottom edge it
    -- is the host's row that a follower has to match, and down a side it
    -- is the host's column. One rule for both, so a bar docked under a
    -- health bar that has a portrait beside it spans the pair exactly as
    -- a portrait docked beside a health bar that has a power bar under it
    -- spans that pair.
    local hostAxis = vertical and "H" or "V"

    -- How far a follower's anchor moves so that a point on the host's own
    -- box lands on the same point of the stack's box. The low end - the
    -- bottom of a column, the left of a row - moves out by the overhang
    -- there, the high end by the one at its end, and the middle by half
    -- the difference. Along the host's axis, so the caller decides
    -- whether the answer is an x or a y.
    local low  = (hostAxis == "V") and "BOTTOM" or "LEFT"
    local high = (hostAxis == "V") and "TOP"    or "RIGHT"
    local function StackShift(hostPoint, before, after)
        if before == 0 and after == 0 then return 0 end
        if hostPoint:find(high, 1, true) then return after end
        if hostPoint:find(low, 1, true) then return -before end
        return (after - before) / 2
    end

    -- Which followers share which line.
    --
    -- Worked out before anything is placed, because a line has
    -- properties of its own now: how tall it is, and how much space to
    -- leave between the things on it. Neither can be known while still
    -- streaming through the list, and the space between two halves of a
    -- bar is one number for the line rather than one each, or setting it
    -- on one of them would give you half of what you asked for.
    --
    -- A line is open until something wants an alignment already taken on
    -- it, or until something full width turns up, which always gets a
    -- line to itself. Its distance from what is above comes from
    -- whichever follower opened it.
    local lines, current, taken = {}, nil, {}

    for _, frame in ipairs(list) do
        local link = links[frame]
        local visible
        if link.ownsShown then
            -- Not ours to decide: the unit watch shows and hides this
            -- one, and the layout simply goes around whatever it did.
            visible = frame:IsShown()
        else
            visible = Dock:ShouldShow(frame)
            -- Ours, so nothing hears about it. The show and hide events
            -- are how a frame the secure environment revealed gets
            -- noticed, and the ones we cause here are not news.
            settingShown = true
            frame:SetShown(visible)
            settingShown = false
        end

        -- A follower that is hidden and not holding its place is skipped
        -- entirely, and the next one moves up into its space.
        --
        -- Unless the whole stack is dark, which is a different thing. A
        -- bar whose own unit is missing should let the bars under it
        -- close up; one that is dark only because the thing it hangs off
        -- is dark has nothing to close up over - and skipping it meant it
        -- was never anchored at all, so it stayed wherever it last
        -- floated. That is why docking an aura row to a target bar with
        -- no target showed the landing line and then appeared to do
        -- nothing: the row was docked, it simply had not been put
        -- anywhere. It is placed like any other follower and stays
        -- hidden, so it is already in the right spot when the target
        -- turns up, and the handle in Edit Mode sits on it either way.
        local stackHidden = not HostChainShown(frame)
        if visible or link.reserve or stackHidden then
            local slot = (link.mode ~= "stretch") and AlignOf(link) or nil
            if not current or not slot or taken[slot] then
                current = { gap = link.gap, gutter = 0, members = {} }
                lines[#lines + 1] = current
                taken = {}
            end
            if slot then taken[slot] = true end

            current.members[#current.members + 1] = frame
            current.gutter = math.max(current.gutter, link.gutter or 0)

            -- Full width leaves no room beside it.
            if not slot then current, taken = nil, {} end
        end
    end

    local offset = 0        -- how far from the host's edge we have got

    for _, line in ipairs(lines) do
        offset = offset + line.gap
        local depth = 0     -- how thick this line turned out to be

        for _, frame in ipairs(line.members) do
            local link = links[frame]
            local scale = frame:GetEffectiveScale() or 1
            frame:ClearAllPoints()

            -- How much room the host offers across a line, measured on
            -- the host's stack as that stack stood when this follower
            -- joined it. Per follower rather than once for the edge,
            -- because two bars docked to the same edge at different times
            -- were each promised a different host.
            --
            -- A frame reports its size in its own scale, so copying the
            -- number straight across would make a follower the wrong size
            -- whenever the host has been scaled: an action bar at 130%
            -- would leave its bars short. StackExtent answers in screen
            -- pixels, which is the space they share.
            --
            -- The stack can reach past the host at either end, and those
            -- overhangs come back as the shift below: a follower anchored
            -- to one of the host's own corners has to be moved out to the
            -- stack's corner instead.
            local across, before, after = StackExtent(host, hostAxis, link.seq)

            -- Across the line, never along it: a bar docked below keeps
            -- its height and a bar docked to the side keeps its width.
            --
            -- By its box, too - what has to match the host is the bar's
            -- outside, not the fill inside it.
            local function Resize(extent)
                if frame.SetOuterSize then
                    if vertical then
                        frame:SetOuterSize(extent)
                    else
                        frame:SetOuterSize(nil, extent)
                    end
                elseif vertical then
                    frame:SetWidth(extent)
                else
                    frame:SetHeight(extent)
                end
            end

            local point, hostPoint
            local leadX, leadY = 0, 0
            if link.mode == "stretch" then
                -- A stretched follower brings its own stack across with
                -- it, fitted into the host's - and is hung by the corner
                -- that stack starts at rather than by its middle, pushed
                -- along by however much of it lies before the follower.
                -- The two stacks then begin together and, being the same
                -- size, end together. Hung by the middle, a health bar
                -- with a power bar under it sat centered on the host and
                -- the pair spilled out below.
                local lead = FitStack(frame, hostAxis, across) or 0
                if vertical then
                    -- Across the host's row: left corner, pushed right.
                    point     = Anchor(geo, "LEFT", geo.near)
                    hostPoint = Anchor(geo, "LEFT", edge)
                    leadX     = lead / scale
                else
                    -- Down the host's column: top corner, pushed down.
                    point     = Anchor(geo, "TOP", geo.near)
                    hostPoint = Anchor(geo, "TOP", edge)
                    leadY     = -lead / scale
                end
            else
                -- An aligned follower can still be measured from its
                -- host: half of an action bar is what two bars sharing
                -- one line want, and neither should have to be told the
                -- number. The line's gutter comes out of the host's
                -- room first, so two halves leave exactly that much
                -- between them.
                if link.share then
                    Resize((across - line.gutter) / link.share / scale)
                end

                local align = AlignOf(link)
                point     = Anchor(geo, align, geo.near)
                hostPoint = Anchor(geo, align, edge)
            end

            link.point = point
            local slide = geo.away * offset
            -- The shift runs along the host's axis, which is the one the
            -- follower is not stacking on: sideways for a top or bottom
            -- edge, up and down for a side.
            local shift = StackShift(hostPoint, before, after) / scale
            frame:SetPoint(point, host, hostPoint,
                (vertical and 0 or slide) + (link.offsetX or 0)
                    + leadX + (vertical and shift or 0),
                (vertical and slide or 0) + (link.offsetY or 0)
                    + leadY + (vertical and 0 or shift))

            -- How thick this line turned out to be, counting what the
            -- follower carries across it rather than the follower alone:
            -- a bar with a taller portrait beside it is as tall as the
            -- portrait, and the next line along has to clear both.
            depth = math.max(depth,
                StackThickness(frame, hostAxis, geo.stack) / scale,
                ((vertical and frame:GetHeight() or frame:GetWidth()) or 0))
        end

        offset = offset + depth
    end

    -- Whatever hangs off any of them moves with it.
    for _, frame in ipairs(list) do
        if followers[frame] then PlaceEdges(frame) end
    end
end

-- Lay out one host's followers, or every host if none is named.
function Dock:Relayout(host)
    if InCombatLockdown() then return end

    if host then
        -- Twice, for the reason the pass over everything below is: a
        -- follower above or below is fitted to the host's row and one at
        -- a side to its column, so whichever edges are placed first may
        -- have measured a stack the later edges had not placed yet.
        for _ = 1, 2 do PlaceEdges(host) end
        return
    end

    -- In a fixed order rather than whatever pairs hands back. Roots first
    -- - things nothing docks to - then their followers, then theirs, so
    -- a stack is placed before anything measures it. Ties broken on the
    -- frame's name, which every bar and row has, so two sessions lay out
    -- the same layout the same way.
    -- Named for what it is - the hosts in the order they will be laid out
    -- - and not `hosts`, which is the registry of everything a bar may
    -- dock to, defined at the top of this file.
    local ordered = {}
    for h in pairs(followers) do
        local depth, link = 0, links[h]
        while link and depth < 16 do
            depth = depth + 1
            link = links[link.host]
        end
        ordered[#ordered + 1] = { frame = h, depth = depth,
            name = (h.GetName and h:GetName()) or "" }
    end
    table.sort(ordered, function(a, b)
        if a.depth ~= b.depth then return a.depth < b.depth end
        return a.name < b.name
    end)

    -- Twice. The first pass may measure a stack whose members are still
    -- where the previous layout left them; by the second, everything has
    -- been placed once and the measurements are of this layout, not the
    -- last. A pass over a settled layout changes nothing, so the second
    -- one costs only time.
    for _ = 1, 2 do
        for _, entry in ipairs(ordered) do PlaceEdges(entry.frame) end
    end
end

-- A host whose size or visibility changed tells the dock, rather than
-- the dock watching every frame in the interface.
function Dock:HostChanged(host)
    if settingShown then return end

    -- Whatever hangs off it.
    if followers[host] then self:Relayout(host) end

    -- And it, if it hangs off something. A follower that is hidden is
    -- skipped by the layout entirely, so it comes back at whatever size
    -- it had when it went away - and health and power bars are shown by
    -- RegisterUnitWatch, in the secure environment, which tells us
    -- nothing. Its own show is the only notice there is, and until this
    -- it went nowhere: the bar sat at a stale width until something else
    -- happened to re-lay it, which in practice meant a reload.
    local link = links[host]
    if link and link.host then self:Relayout(link.host) end
end

-- Hosts that can change on their own get hooked once, so a bar docked to
-- an action bar follows it without the action bar knowing we exist.
function Dock:WatchHost(host)
    if not host or host._bazDockWatched then return end
    host._bazDockWatched = true
    host:HookScript("OnSizeChanged", function(self) Dock:HostChanged(self) end)
    host:HookScript("OnShow",        function(self) Dock:HostChanged(self) end)
    host:HookScript("OnHide",        function(self) Dock:HostChanged(self) end)

    -- Scaling a frame does not count as resizing it, so it raises no
    -- size event and nothing docked to it would ever hear about it.
    -- Hooking the call itself is the only notice we get.
    hooksecurefunc(host, "SetScale", function(self) Dock:HostChanged(self) end)
end

BazUI:QueueForLogin(function()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function()
        for follower in pairs(pendingShow) do
            follower:SetShown(follower._dockWanted and HostChainShown(follower))
        end
        wipe(pendingShow)
        Dock:Relayout()
    end)
end)

---------------------------------------------------------------------------
-- What the dock thinks the layout is
--
-- For when the screen and the dock disagree, which is most of what goes
-- wrong here. Read-only.
---------------------------------------------------------------------------

function Dock:PrintLayout()
    local named = {}
    for _, entry in ipairs(self:GetHosts()) do
        local frame = self:GetHostFrame(entry.id)
        if frame then named[frame] = entry.label or entry.id end
    end
    local function Name(frame)
        if not frame then return "?" end
        return named[frame]
            or (frame.GetName and frame:GetName())
            or "unnamed"
    end

    -- In ticket order, because that is the order the sizing rule reads
    -- them in: a stack is measured as it stood when each piece joined it,
    -- so nothing here is sized by anything below it.
    local rows = {}
    for frame, link in pairs(links) do
        rows[#rows + 1] = { frame = frame, link = link }
    end
    table.sort(rows, function(a, b)
        local x, y = a.link.seq or 0, b.link.seq or 0
        if x ~= y then return x < y end
        return Name(a.frame) < Name(b.frame)
    end)

    BazUI:Print(("|cffffd700Docked|r  %d of %d things that can be docked to")
        :format(#rows, #self:GetHosts()))
    print("  |cff999999ticket  what                      edge     on                        counts|r")
    for _, row in ipairs(rows) do
        local link = row.link
        local out = {}
        if link.countsHeight == false then out[#out + 1] = "not height" end
        if link.countsWidth  == false then out[#out + 1] = "not width"  end
        print(("  %-7s %-25s %-8s %-25s %s"):format(
            tostring(link.seq or "|cffff8800none|r"),
            Name(row.frame), tostring(link.edge), Name(link.host),
            #out > 0 and ("|cffff8800" .. table.concat(out, ", ") .. "|r")
                      or "|cff44ff44both|r"))
    end
    print("  |cff999999A lower ticket was docked first, and keeps the size it was" ..
        " given then. 'counts' is what this piece adds to its stack.|r")

    -- Asked for a host that is not there. This is the one way a docking
    -- goes missing without a word: the layout says where it belongs, the
    -- request is parked until the host turns up, and if it never does the
    -- thing simply floats. Worth seeing, since from the screen it looks
    -- exactly like a drop that did not take.
    local parked = {}
    for frame, request in pairs(waiting) do
        parked[#parked + 1] = ("%s -> %s"):format(Name(frame), tostring(request.hostId))
    end
    if #parked > 0 then
        table.sort(parked)
        print(("  |cffff8800Waiting on a host that is not registered: %d|r")
            :format(#parked))
        for _, line in ipairs(parked) do print("    " .. line) end
    end
end
