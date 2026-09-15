-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Dock
--
-- Bars and aura blocks attach to things. A health bar sits under an
-- action bar and takes its width; a power bar sits under the health bar;
-- a block of auras sits above one of them, aligned to an edge or centered.
-- Anything can also float, which is just being docked to nothing.
--
-- Two behaviors against a host, declared by the follower:
--
--   "stretch"  take the host's width and sit on its edge. Bars.
--   "align"    keep your own width and sit left, right or center within
--              the host's. Aura blocks.
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

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

-- opts:
--   edge     "TOP" or "BOTTOM", which side of the host to sit on
--   mode     "stretch" (default) or "align"
--   align    for "align": "LEFT", "RIGHT" or "CENTER"
--   order    lower sits nearer the host
--   gap      pixels between this and whatever it follows
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
        -- How much of the host's width an aligned follower takes: 1 for
        -- all of it, 2 for half. Nothing means keep your own width.
        share   = opts.share,
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

function Dock:CopyStack(frame, unit, hostId, edge, report)
    local copier = copiers[frame]
    if not copier then return nil, 0 end

    local newId, newFrame = copier(unit, hostId, edge)
    if not newFrame then return nil, 0 end
    local made = 1

    -- Say what each piece was asked to attach to and whether it did.
    -- A copy that comes out loose when a host was named is the only
    -- interesting failure here, and it is invisible from the screen:
    -- a loose bar looks exactly like one that was never told.
    if report then
        report[#report + 1] = {
            id     = newId,
            host   = hostId,
            docked = self:IsDocked(newFrame),
        }
    end

    -- A snapshot: every copy attaches to the copy above it, which adds
    -- to the follower lists as we go.
    local list = followers[frame]
    if list then
        local snapshot = {}
        for index = 1, #list do snapshot[index] = list[index] end
        for _, follower in ipairs(snapshot) do
            local link = links[follower]
            local _, count = Dock:CopyStack(follower, unit, newId,
                link and link.edge or "BOTTOM", report)
            made = made + (count or 0)
        end
    end
    return newId, made
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

local function PlaceOneEdge(host, edge)
    local list = SortedFollowers(host, edge)
    if #list == 0 then return end

    -- A frame reports its width in its own scale, so copying the number
    -- straight across makes a follower the wrong size whenever the host
    -- has been scaled: an action bar at 130% would leave its bars short.
    -- Convert through screen pixels, which is the space they share.
    local hostWidth = (host:GetWidth() or 0) * (host:GetEffectiveScale() or 1)
    local offset = 0        -- how far from the host's edge we have got
    local down = (edge == "BOTTOM")

    -- Followers stack, except that aligned ones sharing no ground share a
    -- line: buffs on the left of a bar and debuffs on the right belong
    -- beside each other, not one under the other. A line is open until
    -- something wants an alignment already taken on it, or until
    -- something full width turns up, which always gets a line of its own.
    -- The line's distance from what is above it comes from whichever
    -- follower opened it.
    local taken = {}
    local lineHeight, lineOpen = 0, false

    local function CloseLine()
        if not lineOpen then return end
        offset = offset + lineHeight
        taken = {}
        lineHeight, lineOpen = 0, false
    end

    for _, frame in ipairs(list) do
        local link = links[frame]
        local visible = Dock:ShouldShow(frame)
        frame:SetShown(visible)

        -- A follower that is hidden and not holding its place is skipped
        -- entirely, and the next one moves up into its space.
        if visible or link.reserve then
            local slot = (link.mode ~= "stretch") and (link.align or "LEFT") or nil
            if not slot or taken[slot] then CloseLine() end
            if not lineOpen then
                offset = offset + link.gap
                lineOpen = true
            end
            if slot then taken[slot] = true end

            frame:ClearAllPoints()
            if link.mode == "stretch" then
                local width = hostWidth / (frame:GetEffectiveScale() or 1)
                if frame.SetBarSize then
                    frame:SetBarSize(width, frame:GetHeight())
                else
                    frame:SetWidth(width)
                end
                local point = down and "TOP" or "BOTTOM"
                link.point = point
                frame:SetPoint(point, host, down and "BOTTOM" or "TOP",
                    0, down and -offset or offset)
            else
                -- An aligned follower can still be measured from its
                -- host: half of an action bar is what two bars sharing
                -- one line want, and neither should have to be told the
                -- number.
                if link.share then
                    local width = hostWidth / link.share / (frame:GetEffectiveScale() or 1)
                    if frame.SetBarSize then
                        frame:SetBarSize(width, frame:GetHeight())
                    else
                        frame:SetWidth(width)
                    end
                end

                local point, hostPoint
                if link.align == "CENTER" then
                    point     = down and "TOP" or "BOTTOM"
                    hostPoint = down and "BOTTOM" or "TOP"
                else
                    point     = (down and "TOP" or "BOTTOM") .. link.align
                    hostPoint = (down and "BOTTOM" or "TOP") .. link.align
                end
                link.point = point
                frame:SetPoint(point, host, hostPoint, 0, down and -offset or offset)
            end

            lineHeight = math.max(lineHeight, frame:GetHeight() or 0)
            -- Full width leaves no room beside it.
            if not slot then CloseLine() end
        end

        -- Whatever hangs off this follower moves with it.
        if followers[frame] then Dock:Relayout(frame) end
    end
end

-- Lay out one host's followers, or every host if none is named.
function Dock:Relayout(host)
    if InCombatLockdown() then return end

    if host then
        PlaceOneEdge(host, "BOTTOM")
        PlaceOneEdge(host, "TOP")
        return
    end

    for h in pairs(followers) do
        PlaceOneEdge(h, "BOTTOM")
        PlaceOneEdge(h, "TOP")
    end
end

-- A host whose size or visibility changed tells the dock, rather than
-- the dock watching every frame in the interface.
function Dock:HostChanged(host)
    if not followers[host] then return end
    self:Relayout(host)
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
