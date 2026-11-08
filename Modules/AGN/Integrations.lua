-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("AGN")
local suppressed = setmetatable({}, { __mode = "k" })
local zygorFrames = setmetatable({}, { __mode = "k" })
local function Wants(key) return addon:GetSetting(key) ~= false end

local function CommitZygorTarget(frame, target)
    if frame ~= addon.zygorFrame or not Wants("zygor") then return end
    if addon.zygorWaypoint ~= frame.waypoint then
        addon.zygorWaypoint = frame.waypoint
        addon.navigationMuted = false
    end
    target.updated = GetTime()
    addon.zygorTarget = target
    addon:RefreshNavigation()
end

local function Suppress(frame, key)
    if not frame or InCombatLockdown() then return end
    local entry = suppressed[frame]
    if not entry then
        entry = { alpha = frame:GetAlpha(), mouse = frame:IsMouseEnabled(), key = key }
        suppressed[frame] = entry
        hooksecurefunc(frame, "SetAlpha", function(f, alpha)
            if alpha ~= 0 and Wants(key) and not InCombatLockdown() then f:SetAlpha(0) end
        end)
    end
    if Wants(key) then
        frame:SetAlpha(0)
        frame:EnableMouse(false)
    else
        frame:SetAlpha(entry.alpha)
        frame:EnableMouse(entry.mouse)
    end
end

function addon:ConnectTomTom()
    local tt = _G.TomTom
    if not tt or not tt.SetCrazyArrow then return end
    self.tomtomReady = true
    if self.tomtomObject ~= tt then
        self.tomtomObject = tt
        hooksecurefunc(tt, "SetCrazyArrow", function(_, uid, _, title)
            if not Wants("tomtom") then return end
            addon.tomtomUID, addon.tomtomTitle = uid, title
            addon.navigationMuted = false
            addon:RefreshNavigation()
        end)
        if tt.FireMessage then
            hooksecurefunc(tt, "FireMessage", function(_, event, uid)
                if event ~= "TOMTOM_ARROW_TARGET_CHANGED" or not Wants("tomtom") then return end
                if uid ~= addon.tomtomUID then addon.navigationMuted = false end
                addon.tomtomUID = uid
                addon.tomtomTitle = uid and uid.title
                addon:RefreshNavigation()
            end)
        end
    end
    if tt.private and tt.private.GetCrazyArrowTarget then
        self.tomtomUID, self.tomtomTitle = tt.private.GetCrazyArrowTarget()
    end
    Suppress(_G.TomTomCrazyArrow, "tomtom")
end

function addon:ConnectZygor()
    local zgv = _G.ZGV or _G.ZygorGuidesViewer
    local pointer = zgv and zgv.Pointer
    local frame = pointer and pointer.ArrowFrame
    if not frame or not frame.ShowTraveling then return end
    self.zygorReady, self.zygorFrame = true, frame
    if not zygorFrames[frame] then
        zygorFrames[frame] = true
        hooksecurefunc(frame, "ShowTraveling", function(f, _, angle, distance)
            if not Wants("zygor") or f ~= addon.zygorFrame then return end
            local waypoint = f.waypoint
            -- Zygor supplies direction first and formatted text later in the
            -- same update. Publish both together instead of flashing its raw
            -- waypoint title (often just zone/coordinates) on every frame.
            f._agnPendingTarget = { source = "zygor", angle = angle, distance = distance,
                title = waypoint and waypoint.title or "Zygor destination", updated = GetTime() }
            if not f.ShowText then CommitZygorTarget(f, f._agnPendingTarget) end
        end)
        if frame.ShowText then
            hooksecurefunc(frame, "ShowText", function(f, title, distance, _, status)
                if not Wants("zygor") or f ~= addon.zygorFrame then return end
                local target = f._agnPendingTarget
                if target then
                    target.title = title or target.title
                    target.distance = type(distance) == "number" and distance or target.distance
                    target.status = status or target.status
                    f._agnPendingTarget = nil
                    CommitZygorTarget(f, target)
                end
            end)
        end
        if frame.ShowSpecial then
            local labels = { here = "Arrived", waiting = "Waiting", upstairs = "Go upstairs",
                downstairs = "Go downstairs", error = "Route unavailable", instance = "Enter the instance",
                instancehide = "Enter the instance", ship = "Take the ship", taxi = "Take the flight path" }
            hooksecurefunc(frame, "ShowSpecial", function(f, state)
                if not Wants("zygor") or f ~= addon.zygorFrame then return end
                if not state then addon.zygorTarget = nil; f._agnPendingTarget = nil; return end
                f._agnPendingTarget = { source = "zygor", title = f.waypoint and f.waypoint.title or "Zygor destination",
                    status = labels[state] or state, angle = 0, updated = GetTime() }
                if not f.ShowText then CommitZygorTarget(f, f._agnPendingTarget) end
            end)
        end
    end
    -- Keep Zygor's route engine running: IsShown/IsVisible remain true.
    -- Its own visual and mouse controller are transparent, not reskinned.
    Suppress(frame, "zygor")
    Suppress(pointer.ArrowFrameCtrl, "zygor")
end

function addon:GetProviderTarget()
    local z = self.zygorTarget
    if Wants("zygor") and z and self.zygorFrame and self.zygorFrame:IsShown()
        and GetTime() - z.updated < 2 then return z end
    local tt, uid = self.tomtomObject, self.tomtomUID
    if Wants("tomtom") and tt and uid and tt.GetVectorToWaypoint then
        local bearing, distance = tt:GetVectorToWaypoint(uid)
        if bearing then return { bearing = bearing, distance = distance,
            title = self.tomtomTitle or uid.title or "TomTom waypoint" } end
    end
end

function addon:ScanIntegrations()
    self:RegisterWaypointCommands()
    if InCombatLockdown() then return end
    self:ConnectTomTom()
    self:ConnectZygor()
end

function addon:ApplySettings()
    self:ResizeArrow()
    if not InCombatLockdown() then
        for frame, entry in pairs(suppressed) do Suppress(frame, entry.key) end
    end
    self:ScanIntegrations()
    self:RefreshNavigation()
end

function addon:InitializeIntegrations()
    self:ScanIntegrations()
    self.integrationTicker = C_Timer.NewTicker(1, function() self:ScanIntegrations() end)
end
