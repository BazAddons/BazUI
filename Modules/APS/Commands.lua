-- SPDX-License-Identifier: GPL-2.0-or-later
-- Independently implemented compatibility syntax; no TomTom dependency.
local addon = BazUI:GetModule("APS")
local function Trim(s) return (s or ""):match("^%s*(.-)%s*$") end
local function NameKey(s) return s:lower():gsub("%s+", "") end

function addon:ResolveMap(name)
    name = Trim(name)
    if name == "" then return C_Map.GetBestMapForUnit("player") end
    local id = tonumber(name:match("^#(%d+)$"))
    if id then
        if C_Map.GetMapInfo(id) then return id end
        return nil, "Unknown map: " .. name
    end
    local maps, seen = {}, {}
    local function Visit(map)
        if not map or seen[map] then return end
        seen[map] = true
        local info = C_Map.GetMapInfo(map)
        if info then maps[map] = info end
        for _, child in ipairs(C_Map.GetMapChildrenInfo(map) or {}) do Visit(child.mapID) end
    end
    local current = C_Map.GetBestMapForUnit("player")
    local root = current
    local parents = {}
    while root and not parents[root] do
        parents[root] = true
        local info = C_Map.GetMapInfo(root)
        if not info or not info.parentMapID or info.parentMapID == 0 then break end
        root = info.parentMapID
    end
    Visit(root)
    for _, world in ipairs({ 946, 947, 1414, 1415 }) do Visit(world) end
    local key, exact, partial = NameKey(name), {}, {}
    for map, info in pairs(maps) do
        local candidate = NameKey(info.name)
        if candidate == key then exact[#exact + 1] = map
        elseif candidate:find(key, 1, true) then partial[#partial + 1] = map end
    end
    local matches = #exact > 0 and exact or partial
    for _, map in ipairs(exact) do if map == current then return map end end
    if #matches == 1 then return matches[1] end
    if #matches == 0 then return nil, "Unknown zone. Try its map ID, for example /way #37 42 65." end
    local names = {}
    for _, map in ipairs(matches) do names[#names + 1] = maps[map].name .. " (#" .. map .. ")" end
    table.sort(names)
    return nil, "Be more specific: " .. table.concat(names, ", ")
end

function addon:CommandHelp()
    self:Print("/way [zone or #mapID] x y [name] | /aps way uses the same syntax.")
    self:Print("/wayb [name] saves your position; /cway selects the closest waypoint.")
    self:Print("/way list | /way local | /way reset all/away/[not] zone")
    self:Print("/way arrow clear/remove | /ttpaste pastes multiple commands.")
end

function addon:ListWaypoints(localOnly)
    local map = C_Map.GetBestMapForUnit("player")
    local count = 0
    for _, p in ipairs(self:WaypointStore().points) do
        if not localOnly or p.map == map then
            count = count + 1
            local info = C_Map.GetMapInfo(p.map)
            self:Print(string.format("%s: %s %.2f, %.2f (#%d)", p.title,
                info and info.name or "Map", p.x * 100, p.y * 100, p.map))
        end
    end
    if count == 0 then self:Print("No saved waypoints.") end
end

function addon:WayCommand(message)
    local msg = Trim(message)
    -- Accept complete copied lines as well as slash-handler arguments.
    msg = msg:gsub("^/[Tt]omtomway%s+", ""):gsub("^/[Tt]way%s+", ""):gsub("^/[Ww]ay%s+", "")
    local first, rest = msg:match("^(%S+)%s*(.-)$")
    first = first and first:lower()
    if first == "list" or first == "local" then return self:ListWaypoints(first == "local") end
    if first == "arrow" then
        local action = rest:lower()
        if action == "clear" or action == "remove" then return self:ClearNavigation(action == "remove") end
        local p = self:GetActiveWaypoint() or self.questTarget or self:GetProviderTarget()
        self:Print(p and ("Navigating to " .. (p.title or "waypoint")) or "No active waypoint.")
        return
    end
    if first == "block" then
        local m, x, y = self:CurrentPosition()
        self:Print(m and string.format("Current position: #%d %.2f, %.2f", m, x * 100, y * 100)
            or "Your position is unavailable.")
        return
    end
    if first == "reset" then
        local action = rest:lower()
        local map, invert, err
        if action == "away" then map = C_Map.GetBestMapForUnit("player"); invert = true
        elseif action ~= "all" then
            local zone = rest
            if action:match("^not%s") then invert = true; zone = rest:sub(5) end
            if Trim(zone) == "" then return self:CommandHelp() end
            map, err = self:ResolveMap(zone)
        end
        if action ~= "all" and not map then self:Print(err or "Your current map is unavailable."); return end
        local store, removed = self:WaypointStore(), 0
        for i = #store.points, 1, -1 do
            local p = store.points[i]
            if action == "all" or (invert and p.map ~= map) or (not invert and p.map == map) then
                if store.active == p.id then store.active = nil end
                table.remove(store.points, i); removed = removed + 1
            end
        end
        self:Print("Removed " .. removed .. " waypoint(s).")
        self:RefreshNavigation()
        return
    end
    -- Decimal commas and the trailing comma in '42.1, 65.9' both work.
    msg = msg:gsub("(%d),%s+", "%1 "):gsub("(%d),(%d)", "%1.%2")
    local tokens = {}
    for token in msg:gmatch("%S+") do tokens[#tokens + 1] = token end
    local index
    for i, token in ipairs(tokens) do if tonumber(token) then index = i; break end end
    if not index or not tonumber(tokens[index + 1]) then return self:CommandHelp() end
    local map, err = self:ResolveMap(table.concat(tokens, " ", 1, index - 1))
    if not map then self:Print(err or "Your current map is unavailable."); return end
    local x, y = tonumber(tokens[index]), tonumber(tokens[index + 1])
    local p = self:AddWaypoint(map, x / 100, y / 100, table.concat(tokens, " ", index + 2))
    if p then self:Print(string.format("%s: %.2f, %.2f", p.title, x, y)) end
    return p
end

function addon:PasteWaypoints(text)
    for line in (text .. "\n"):gmatch("([^\r\n]+)") do
        line = Trim(line)
        local command, rest = line:match("^/(%S+)%s*(.-)$")
        command = command and command:lower()
        if not command or command == "way" or command == "tway" or command == "tomtomway" then
            self:WayCommand(rest or line)
        elseif command == "aps" and rest:lower():match("^way%s") then self:WayCommand(rest:sub(5))
        elseif command == "wayb" or command == "wayback" then self:SaveCurrentPosition(rest)
        elseif command == "cway" or command == "closestway" then self:SelectClosest()
        else self:Print("Skipped unsupported command: /" .. command) end
    end
end

function addon:OpenWaypointPaste()
    BazUI:OpenCopyDialog({ title = "APS waypoints", subtitle = "Paste /way commands, one per line.",
        editable = true, acceptText = "Add waypoints", onAccept = function(text) self:PasteWaypoints(text) end })
end

function addon:RegisterWaypointCommands()
    if not self.commandHandlers then
        self.commandHandlers = {
            TOMTOM_WAY = function(msg) self:WayCommand(msg) end,
            TOMTOM_CLOSEST_WAYPOINT = function() self:SelectClosest() end,
            TOMTOM_WAYBACK = function(msg) self:SaveCurrentPosition(msg) end,
            TOMTOM_PASTE = function() self:OpenWaypointPaste() end,
            TOMTOM = function(msg)
                if Trim(msg):lower() == "help" then self:CommandHelp()
                else BazUI:OpenOptionsPanel("APS") end
            end,
        }
    end
    local aliases = {
        TOMTOM_WAY = { "/way", "/tway", "/tomtomway" },
        TOMTOM_CLOSEST_WAYPOINT = { "/cway", "/closestway" },
        TOMTOM_WAYBACK = { "/wayb", "/wayback" },
        TOMTOM_PASTE = { "/ttpaste", "/tomtompaste", "/ttp" },
    }
    -- Use the existing groups when TomTom is installed so cached slash
    -- dispatch and copied Wowhead lines both resolve to the same parser.
    for group, list in pairs(aliases) do
        for i, alias in ipairs(list) do _G["SLASH_" .. group .. i] = alias end
        SlashCmdList[group] = self.commandHandlers[group]
    end
    if not _G.TomTom then
        _G.SLASH_TOMTOM1 = "/tomtom"
        SlashCmdList.TOMTOM = self.commandHandlers.TOMTOM
    end
end
