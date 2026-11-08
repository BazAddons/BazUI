-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("APS")
local function ValidNumber(n) return addon:ReadableNumber(n) ~= nil end

function addon:WaypointStore()
    local sets = self:GetSetting("waypointSets")
    if not sets then sets = {}; self:SetSetting("waypointSets", sets) end
    local key = (GetRealmName() or "") .. ":" .. (UnitName("player") or "")
    if not sets[key] then sets[key] = { points = {}, nextID = 1 } end
    return sets[key]
end

function addon:CurrentPosition()
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if pos then
        local x, y = pos:GetXY()
        if ValidNumber(x) and ValidNumber(y) then return map, x, y end
    end
end

function addon:AddWaypoint(map, x, y, title, activate)
    if not (tonumber(map) and C_Map.GetMapInfo(map) and ValidNumber(x) and ValidNumber(y)
        and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
        self:Print("A waypoint needs a valid map and coordinates between 0 and 100.")
        return
    end
    local store = self:WaypointStore()
    local id = store.nextID
    store.nextID = id + 1
    local point = { id = id, map = map, x = x, y = y, title = title and title ~= "" and title or "Waypoint" }
    store.points[#store.points + 1] = point
    if activate ~= false then
        store.active = id
        self.questID, self.questTarget, self.navigationMuted, self.previewing = nil, nil, false, false
        self.questExplicit = nil
    end
    self:RefreshNavigation()
    return point
end

function addon:GetActiveWaypoint()
    local store = self:WaypointStore()
    for _, p in ipairs(store.points) do if p.id == store.active then return p end end
end

function addon:RemoveWaypoint(point)
    local store = self:WaypointStore()
    for i = #store.points, 1, -1 do
        if store.points[i] == point then table.remove(store.points, i) end
    end
    if point and store.active == point.id then store.active = nil end
    self:RefreshNavigation()
end

function addon:ClearNavigation(remove)
    local point = self:GetActiveWaypoint()
    self:WaypointStore().active = nil
    if remove and point then self:RemoveWaypoint(point) end
    self.questID, self.questTarget, self.previewing = nil, nil, false
    self.questExplicit = nil
    self.navigationMuted = true
    self:RefreshNavigation()
end

function addon:VectorToPoint(point)
    local map, x, y = self:CurrentPosition()
    if not map then return end
    local instance, origin = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y))
    local destInstance, destination = C_Map.GetWorldPosFromMapPos(point.map, CreateVector2D(point.x, point.y))
    if not origin or not destination or instance ~= destInstance then return end
    -- C_Map world coordinates are north and west; facing is zero north.
    local north, west = origin:GetXY()
    local destNorth, destWest = destination:GetXY()
    if not (ValidNumber(north) and ValidNumber(west) and ValidNumber(destNorth) and ValidNumber(destWest)) then return end
    local dx, dy = destNorth - north, destWest - west
    return math.atan2(dy, dx), math.sqrt(dx * dx + dy * dy)
end

function addon:SelectClosest()
    local closest, distance
    for _, point in ipairs(self:WaypointStore().points) do
        local _, d = self:VectorToPoint(point)
        if d and (not distance or d < distance) then closest, distance = point, d end
    end
    if not closest then self:Print("No saved waypoint is reachable on this continent."); return end
    self:WaypointStore().active = closest.id
    self.questID, self.questTarget, self.navigationMuted, self.previewing = nil, nil, false, false
    self.questExplicit = nil
    self:RefreshNavigation()
end

function addon:SaveCurrentPosition(title)
    local map, x, y = self:CurrentPosition()
    if not map then self:Print("Your map position is not available here."); return end
    return self:AddWaypoint(map, x, y, title and title ~= "" and title or "Wayback")
end

function addon:ResolveQuestWaypoint(questID)
    if not questID or questID == 0 then return end
    if C_QuestLog.GetNextWaypoint then
        local m, x, y = C_QuestLog.GetNextWaypoint(questID)
        if m and x and y and m > 0 then return m, x, y end
    end
    local map = GetQuestUiMapID and GetQuestUiMapID(questID)
    if map and map > 0 and C_QuestLog.GetQuestsOnMap then
        for _, info in ipairs(C_QuestLog.GetQuestsOnMap(map) or {}) do
            if info.questID == questID and info.x and info.y then return map, info.x, info.y end
        end
    end
end

function addon:TrackQuest(questID, explicit)
    self.questID = questID and questID > 0 and questID or nil
    self.questExplicit = self.questID and explicit ~= false or nil
    self.questTarget = nil
    self:WaypointStore().active = nil
    self.navigationMuted, self.previewing = false, false
    self:UpdateQuestTarget()
    self:RefreshNavigation()
end

function addon:FollowSuperTrackedQuest(questID)
    -- Automatic selection changes from the game or guide cannot replace an
    -- explicit quest-circle click or a coordinate command.
    if self:GetActiveWaypoint() or self.questExplicit or self.navigationMuted then return end
    self:TrackQuest(questID, false)
end

function addon:UpdateQuestTarget()
    if not self.questID then return end
    local map, x, y = self:ResolveQuestWaypoint(self.questID)
    self.questTarget = { map = map, x = x, y = y,
        title = C_QuestLog.GetTitleForQuestID(self.questID) or "Quest" }
end

function addon:RefreshNavigation()
    local f = self.frame
    if not f then return end
    if self.previewing then f.source:SetText(""); f:Show(); return end
    local point = self:GetActiveWaypoint() or (self.questExplicit and self.questTarget)
    local target
    if not self.navigationMuted then
        if not point then
            target = self:GetProviderTarget()
            if not target then point = self.questTarget end
        end
        if point then
            local bearing, distance
            if point.map then bearing, distance = self:VectorToPoint(point) end
            target = { title = point.title, bearing = bearing, distance = distance,
                status = not bearing and "Location unavailable on this map" or nil }
        end
    end
    self.displayTarget = target
    if not target then f:Hide(); return end
    f:Show()
    f.title:SetText(target.title or "Waypoint")
    f.source:SetText(target.source == "zygor" and "|cffb8a58aZygor|r" or "")
    local status = target.status
    local distance = self:ReadableNumber(target.distance)
    if not status then
        if distance and distance <= 10 then status = "Arrived"
        elseif distance then
            status = string.format("%d yards", math.floor(distance + .5))
            local speed = self:ReadableNumber(GetUnitSpeed("player"))
            if speed and speed > .5 then
                local seconds = math.floor(distance / speed)
                status = status .. string.format("  %d:%02d", math.floor(seconds / 60), seconds % 60)
            end
        else status = "" end
    end
    f.detail:SetText(status)
end

function addon:InitializeNavigation()
    self.navigationReady = true
    self:CreateNavigationFrame()
    self:RegisterWaypointCommands()
    local events = CreateFrame("Frame")
    self.navigationEvents = events
    for _, event in ipairs({ "SUPER_TRACKING_CHANGED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, id)
        if event == "SUPER_TRACKING_CHANGED" then
            local q = C_SuperTrack.GetSuperTrackedQuestID()
            self:FollowSuperTrackedQuest(q)
        elseif (event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED") and id == self.questID then
            self:TrackQuest(nil)
        else self:UpdateQuestTarget() end
    end)
    local quest = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID()
    if not self:GetActiveWaypoint() and quest and quest > 0 then self:TrackQuest(quest, false) end
    self:RefreshNavigation()
end
