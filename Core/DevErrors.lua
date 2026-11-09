-- SPDX-License-Identifier: GPL-2.0-or-later
-- Always-on developer support, independent of profiles and module switches.
local D = { ready = false, loggedIn = false }
BazUI.DevErrors = D
local MAX_ERRORS, MAX_MESSAGE, MAX_STACK = 50, 3000, 12000
local pending = { errors = {}, nextID = 1, session = 0, dropped = 0 }
local db, index, busy = pending, {}, false
local floodStart, floodCount, lastNotice = 0, 0, -60
local previousHandler, nativeHandler
local grabberSeen = setmetatable({}, { __mode = "k" })

local function Text(value, limit)
    if issecretvalue and issecretvalue(value) then return "[protected value]" end
    if type(value) ~= "string" then
        if type(value) == "number" or type(value) == "boolean" then value = tostring(value)
        else value = "[unavailable]" end
    end
    -- Reports are plain text: remove UI escapes and control characters.
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("[%z\1-\8\11\12\14-\31]", "?")
    if #value > limit then return value:sub(1, limit) .. "\n[truncated]" end
    return value
end

local function Stack(level)
    return debugstack and Text(debugstack(level or 3, 40, 10), MAX_STACK) or "Stack unavailable"
end

local function Key(entry)
    return entry.version .. "\n" .. entry.build .. "\n" .. entry.kind .. "\n" .. entry.message .. "\n" .. entry.stack
end

local function Source(message, stack)
    local source = message:match("[Aa]dd[Oo]ns[/\\]([^/\\]+)")
    if source then return source end
    for line in stack:gmatch("[^\n]+") do
        if not line:find("Core/DevErrors.lua", 1, true) and not line:find("Core\\DevErrors.lua", 1, true) then
            source = line:match("[Aa]dd[Oo]ns[/\\]([^/\\]+)")
            if source then return source end
        end
    end
    return "Unknown / game UI"
end

local function Store(entry, bypassFlood)
    local key = Key(entry)
    local existing = index[key]
    if existing then
        existing.count = existing.count + entry.count
        existing.last = entry.last
        existing.lastSession = db.session
        -- Keep the most recently repeated error at the end of the browser.
        if db.errors[#db.errors] ~= existing then
            for i, item in ipairs(db.errors) do
                if item == existing then table.remove(db.errors, i); break end
            end
            db.errors[#db.errors + 1] = existing
        end
        return existing
    end
    local now = GetTime()
    if now - floodStart >= 5 then floodStart, floodCount = now, 0 end
    if not bypassFlood and floodCount >= 10 then db.dropped = db.dropped + entry.count; return end
    floodCount = floodCount + 1
    entry.id, entry.lastSession = db.nextID, db.session
    db.nextID = db.nextID + 1
    db.errors[#db.errors + 1] = entry
    index[key] = entry
    if #db.errors > MAX_ERRORS then
        local old = table.remove(db.errors, 1)
        index[Key(old)] = nil
    end
    return entry
end

function D:Notify()
    if not self.loggedIn or GetTime() - lastNotice < 30 then return end
    lastNotice = GetTime()
    C_Timer.After(0, function()
        BazUI:Print("|cffff7777An error was captured.|r Type |cff00ff00/baz errors|r to view and copy it.")
    end)
end

local function Capture(message, stack, kind, count)
    local version, build, _, interface = GetBuildInfo()
    local now = date("%Y-%m-%d %H:%M:%S")
    message, stack = Text(message, MAX_MESSAGE), Text(stack or "Stack unavailable", MAX_STACK)
    local entry = Store({ message = message, stack = stack, kind = kind or "Lua error",
        source = Source(message, stack), version = BazUI.VERSION or "?", count = count or 1,
        first = now, last = now, client = Text(version, 40), build = Text(build, 40),
        interface = Text(interface, 40), locale = GetLocale and GetLocale() or "?" })
    if entry then D:Notify() end
    return entry
end

function D:Capture(message, stack, kind, count)
    if busy then return end
    busy = true
    local ok, entry = pcall(Capture, message, stack, kind, count)
    busy = false
    if not ok then self.captureFailures = (self.captureFailures or 0) + 1; return end
    return entry
end

function D:InitializeStore()
    if self.ready then return end
    local early = pending.errors
    if type(BazUIDevDB) ~= "table" then BazUIDevDB = {} end
    db = BazUIDevDB
    if type(db.errors) ~= "table" then db.errors = {} end
    db.nextID = tonumber(db.nextID) or 1
    db.session = (tonumber(db.session) or 0) + 1
    db.dropped = tonumber(db.dropped) or 0
    index = {}
    -- Bound and validate persisted reports before using them.
    local textFields = { "message", "stack", "version", "kind", "source", "client", "build", "interface", "locale", "first", "last" }
    for i = #db.errors, 1, -1 do
        local e = db.errors[i]
        local valid = type(e) == "table" and type(e.count) == "number" and e.count >= 1 and e.count < math.huge
        if valid then
            for _, field in ipairs(textFields) do if type(e[field]) ~= "string" then valid = false; break end end
        end
        if not valid then
            table.remove(db.errors, i)
        else
            e.message, e.stack = Text(e.message, MAX_MESSAGE), Text(e.stack, MAX_STACK)
        end
    end
    while #db.errors > MAX_ERRORS do table.remove(db.errors, 1) end
    for _, e in ipairs(db.errors) do index[Key(e)] = e end
    for _, e in ipairs(early) do Store(e, true) end
    db.dropped = db.dropped + pending.dropped
    self.ready = true
end

function D:Clear()
    db.errors, db.dropped, index = {}, 0, {}
    floodStart, floodCount, lastNotice = GetTime(), 0, -60
    BazUI._loginErrors = {}
    BazUI._loginErrorsTold = nil
end

function D:Format(entry)
    return table.concat({ "BazUI developer error report", "BazUI version: " .. entry.version,
        "Client: " .. entry.client .. " (build " .. entry.build .. ", interface " .. entry.interface .. ")",
        "Locale: " .. entry.locale, "Type: " .. entry.kind, "Addon in report: " .. entry.source,
        "Occurrences: " .. entry.count, "First: " .. entry.first, "Last: " .. entry.last,
        "", "Message:", entry.message, "", "Stack:", entry.stack }, "\n")
end

function D:Show(selection)
    local total = #db.errors
    local all = selection == "all"
    local position = all and total or math.max(1, math.min(total, tonumber(selection) or total))
    local content
    if total == 0 then content = "No captured errors."
    elseif all then
        local reports = {}
        for _, entry in ipairs(db.errors) do reports[#reports + 1] = self:Format(entry) end
        content = table.concat(reports, "\n\n------------------------------\n\n")
    else content = self:Format(db.errors[position]) end
    return BazUI:OpenCopyDialog({ title = "BazUI developer errors", width = 900, height = 540,
        subtitle = "Select All, then Ctrl+C to copy the report for Codex.", content = content, editable = false,
        stats = (all and (total .. " reports") or (total > 0 and ("Error " .. position .. " of " .. total) or "No errors"))
            .. " | " .. db.dropped .. " reports omitted by flood protection | Saved across reloads",
        actions = {
            { text = "Previous", enabled = total > 0 and position > 1, func = function() self:Show(position - 1) end },
            { text = "Next", enabled = total > 0 and position < total, func = function() self:Show(position + 1) end },
            { text = "Copy all", enabled = total > 0, func = function() self:Show("all") end },
            { text = "Clear", enabled = total > 0, func = function() self:Clear(); self:Show() end },
        } })
end

function D:Command(args)
    args = (args or ""):match("^%s*(.-)%s*$"):lower()
    if args == "clear" then self:Clear(); BazUI:Print("Developer error log cleared.")
    elseif args == "status" then
        BazUI:Print(("Developer errors: %d saved; %d omitted; capture: %s."):format(#db.errors,
            db.dropped, self.grabber and "BugGrabber callback" or "native handler"))
    elseif args == "" or args == "all" or tonumber(args) then self:Show(args == "" and nil or args)
    else BazUI:Print("/baz errors [all | number | clear | status]") end
end

local function GrabberError(grabber, payload)
    local entry = payload
    if type(payload) ~= "table" and grabber.GetErrorByID then entry = grabber:GetErrorByID(payload) end
    if type(entry) ~= "table" or not entry.message then return end
    local previous = grabberSeen[entry] or 0
    local current = tonumber(entry.counter) or 1
    if current <= previous then return end
    grabberSeen[entry] = current
    D:Capture(entry.message, entry.stack, "Lua error", current - previous)
end

function D:ConnectBugGrabber()
    local grabber = _G.BugGrabber
    if not grabber or self.grabber == grabber then return end
    if grabber.setupCallbacks then pcall(grabber.setupCallbacks) end
    local connected = false
    if EventRegistry and grabber.GetErrorByID then
        EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", function(_, payload) GrabberError(grabber, payload) end, self)
        connected = true
    end
    if grabber.RegisterCallback then
        grabber.RegisterCallback(self, "BugGrabber_BugGrabbed", function(_, payload) GrabberError(grabber, payload) end)
        connected = true
    end
    if not connected then return end
    self.grabber = grabber
    if grabber.GetDB and grabber.GetSessionId then
        local session = grabber:GetSessionId()
        for _, entry in pairs(grabber:GetDB()) do
            if entry.session == session then GrabberError(grabber, entry) end
        end
    end
end

previousHandler = geterrorhandler()
nativeHandler = function(message)
    -- Another reporter may call this handler while forwarding. Never recurse
    -- into UI creation here, and leave the previous error handler intact.
    if not busy then
        if not D.grabber then D:Capture(message, Stack(2), "Lua error") end
        if previousHandler and previousHandler ~= nativeHandler then
            busy = true
            pcall(previousHandler, message)
            busy = false
        end
    end
end
seterrorhandler(nativeHandler)

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "LUA_WARNING", "ADDON_LOADED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        D:ConnectBugGrabber()
    elseif event == "LUA_WARNING" then
        D:Capture(Text(arg1, 100) .. ": " .. Text(arg2, MAX_MESSAGE), Stack(3), "Lua warning")
    else
        D:Capture(event .. ": " .. Text(arg1, 200) .. " -> " .. Text(arg2, 500), Stack(3), "Blocked action")
    end
end)
BazUI:QueueForVariables(function() D:InitializeStore() end)
BazUI:QueueForLogin(function()
    D.loggedIn = true
    D:ConnectBugGrabber()
    for _, entry in ipairs(db.errors) do
        if entry.lastSession == db.session then D:Notify(); break end
    end
end)
