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
    }

    followers[host] = followers[host] or {}
    followers[host][#followers[host] + 1] = frame
    self:Relayout(host)
    -- The frame has just taken its host's width; its own followers need
    -- that passed down to them in the same breath.
    self:Relayout(frame)
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
    end
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
-- and honoured when the host turns up.
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

    frame:SetShown(wanted and HostChainShown(frame))

    -- Position is a separate question, and one that has to wait: moving
    -- anything is protected too. A bar that reserves its slot is already
    -- in the right place, which is what lets a cast bar appear mid-cast.
    if not InCombatLockdown() then
        local link = links[frame]
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
    local geo = EDGES[edge or "BOTTOM"] or EDGES.BOTTOM
    return geo.stack
end

function Dock:AlignOnEdge(edge, align)
    local axis = self:EdgeAxis(edge)
    return ALIGN[axis][align or "LEFT"] or (axis == "V" and "LEFT" or "TOP")
end

local function PlaceOneEdge(host, edge)
    local geo = EDGES[edge]
    if not geo then return end

    local list = SortedFollowers(host, edge)
    if #list == 0 then return end

    local vertical = (geo.stack == "V")
    local function AlignOf(link)
        return ALIGN[geo.stack][link.align or "LEFT"]
            or (vertical and "LEFT" or "TOP")
    end

    -- How much room the host offers across a line: its width on the top
    -- and bottom edges, its height on the sides.
    --
    -- A frame reports its size in its own scale, so copying the number
    -- straight across makes a follower the wrong size whenever the host
    -- has been scaled: an action bar at 130% would leave its bars short.
    -- Convert through screen pixels, which is the space they share.
    local across = ((vertical and host:GetWidth() or host:GetHeight()) or 0)
        * (host:GetEffectiveScale() or 1)

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
        local visible = Dock:ShouldShow(frame)
        -- Ours, so nothing hears about it. The show and hide events are
        -- how a frame the secure environment revealed gets noticed, and
        -- the ones we cause here are not news.
        settingShown = true
        frame:SetShown(visible)
        settingShown = false

        -- A follower that is hidden and not holding its place is skipped
        -- entirely, and the next one moves up into its space.
        if visible or link.reserve then
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
            if link.mode == "stretch" then
                Resize(across / scale)
                point, hostPoint = geo.near, edge
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
            frame:SetPoint(point, host, hostPoint,
                (vertical and 0 or slide) + (link.offsetX or 0),
                (vertical and slide or 0) + (link.offsetY or 0))

            depth = math.max(depth,
                ((vertical and frame:GetHeight() or frame:GetWidth()) or 0))
        end

        offset = offset + depth
    end

    -- Whatever hangs off any of them moves with it.
    for _, frame in ipairs(list) do
        if followers[frame] then Dock:Relayout(frame) end
    end
end

-- Lay out one host's followers, or every host if none is named.
function Dock:Relayout(host)
    if InCombatLockdown() then return end

    if host then
        for _, edge in ipairs(EDGE_ORDER) do PlaceOneEdge(host, edge) end
        return
    end

    for h in pairs(followers) do
        for _, edge in ipairs(EDGE_ORDER) do PlaceOneEdge(h, edge) end
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
