-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Dock
--
-- Bars and aura blocks attach to things. A health bar sits under an
-- action bar and takes its width; a power bar sits under the health bar;
-- a block of auras sits above one of them, aligned to an edge or centred.
-- Anything can also float, which is just being docked to nothing.
--
-- Two behaviours against a host, declared by the follower:
--
--   "stretch"  take the host's width and sit on its edge. Bars.
--   "align"    keep your own width and sit left, right or centre within
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

    links[frame] = {
        host    = host,
        edge    = opts.edge or "BOTTOM",
        mode    = opts.mode or "stretch",
        align   = opts.align or "LEFT",
        order   = opts.order or 100,
        gap     = opts.gap or DEFAULT_GAP,
        reserve = opts.reserve and true or false,
    }

    followers[host] = followers[host] or {}
    followers[host][#followers[host] + 1] = frame
    self:Relayout(host)
end

function Dock:Detach(frame, quiet)
    local link = links[frame]
    if not link then return end
    local list = followers[link.host]
    if list then
        for i = #list, 1, -1 do
            if list[i] == frame then table.remove(list, i) end
        end
        if #list == 0 then followers[link.host] = nil end
    end
    links[frame] = nil
    if not quiet then self:Relayout() end
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

    local hostWidth = host:GetWidth() or 0
    local offset = 0        -- how far from the host's edge we have got
    local down = (edge == "BOTTOM")

    for _, frame in ipairs(list) do
        local link = links[frame]
        local visible = Dock:ShouldShow(frame)
        frame:SetShown(visible)

        -- A follower that is hidden and not holding its place is skipped
        -- entirely, and the next one moves up into its space.
        if visible or link.reserve then
            offset = offset + link.gap

            frame:ClearAllPoints()
            if link.mode == "stretch" then
                if frame.SetBarSize then
                    frame:SetBarSize(hostWidth, frame:GetHeight())
                else
                    frame:SetWidth(hostWidth)
                end
                frame:SetPoint(down and "TOP" or "BOTTOM", host,
                    down and "BOTTOM" or "TOP", 0, down and -offset or offset)
            else
                local point, hostPoint
                if link.align == "CENTER" then
                    point     = down and "TOP" or "BOTTOM"
                    hostPoint = down and "BOTTOM" or "TOP"
                    frame:SetPoint(point, host, hostPoint, 0, down and -offset or offset)
                else
                    point     = (down and "TOP" or "BOTTOM") .. link.align
                    hostPoint = (down and "BOTTOM" or "TOP") .. link.align
                    frame:SetPoint(point, host, hostPoint, 0, down and -offset or offset)
                end
            end

            offset = offset + (frame:GetHeight() or 0)
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
