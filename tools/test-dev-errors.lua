-- Lua 5.1 regression checks for the core reporter, without a WoW client.
local checks = 0
local function check(ok, label) assert(ok, label); checks = checks + 1 end
local function NewEnvironment(saved, grabber, modern)
    local e = setmetatable({ now = 100, frames = {}, timers = {}, variables = {}, login = {},
        printed = {}, forwarded = 0, BazUIDevDB = saved, BugGrabber = grabber }, { __index = _G })
    e._G = e
    e.BazUI = { VERSION = "026" }
    function e.BazUI:QueueForVariables(fn) e.variables[#e.variables + 1] = fn end
    function e.BazUI:QueueForLogin(fn) e.login[#e.login + 1] = fn end
    function e.BazUI:Print(text) e.printed[#e.printed + 1] = text end
    function e.BazUI:OpenCopyDialog(opts) e.dialog = opts; return opts end
    function e.CreateFrame()
        local f = { events = {}, scripts = {} }
        function f:RegisterEvent(name) self.events[name] = true end
        function f:SetScript(name, fn) self.scripts[name] = fn end
        e.frames[#e.frames + 1] = f
        return f
    end
    e.handler = function() e.forwarded = e.forwarded + 1 end
    function e.geterrorhandler() return e.handler end
    function e.seterrorhandler(fn) e.handler = fn end
    function e.GetTime() return e.now end
    function e.GetBuildInfo() return "1.60.1", "70862", "", 16001 end
    function e.GetLocale() return "enUS" end
    function e.date() return "2026-11-08 12:00:00" end
    function e.debugstack() return "Interface/AddOns/Example/Core.lua:42: in function 'Run'" end
    e.secret = {}
    function e.issecretvalue(value) return value == e.secret end
    e.C_Timer = { After = function(_, fn) e.timers[#e.timers + 1] = fn end }
    if modern then
        e.EventRegistry = { RegisterCallback = function(_, name, fn) e.callbackName, e.callback = name, fn end }
    end
    local chunk = assert(loadfile("Core/DevErrors.lua"))
    setfenv(chunk, e)()
    function e:Initialize()
        for _, fn in ipairs(self.variables) do fn() end
        for _, fn in ipairs(self.login) do fn() end
    end
    function e:Event(name, ...) self.frames[1].scripts.OnEvent(self.frames[1], name, ...) end
    function e:FlushTimers() local list = self.timers; self.timers = {}; for _, fn in ipairs(list) do fn() end end
    return e, e.BazUI.DevErrors
end

local e, d = NewEnvironment()
e.handler("Interface/AddOns/Example/Core.lua:42: early error")
check(e.forwarded == 1, "existing error handler still receives errors")
check(e.BazUIDevDB == nil, "early errors do not overwrite unloaded saved variables")
e:Initialize()
local db = e.BazUIDevDB
check(#db.errors == 1 and db.errors[1].source == "Example", "early errors reach persisted storage")
check(db.errors[1].stack:find("Core.lua:42", 1, true), "original error stack is retained")
check(db.session == 1 and db.errors[1].lastSession == 1, "session metadata assigned after variables load")
e:FlushTimers()
check(#e.printed == 1, "startup failures produce one deferred notice")
e.handler("Interface/AddOns/Example/Core.lua:42: early error")
check(#db.errors == 1 and db.errors[1].count == 2, "repeated errors grouped and counted")
check(e.forwarded == 2, "chaining still works on repeats")
d:Show()
check(e.dialog.content:find("BazUI version: 026", 1, true) and e.dialog.content:find("build 70862", 1, true), "copy report includes client/version context")
check(e.dialog.editable == false and #e.dialog.actions == 4, "copy browser is read-only with navigation and clear controls")
check(not e.dialog.actions[1].enabled and not e.dialog.actions[2].enabled, "single report disables navigation")
e:Event("ADDON_ACTION_BLOCKED", "BazUI", "Reload()")
check(#db.errors == 2 and db.errors[2].kind == "Blocked action", "blocked actions captured independently")
check(db.errors[2].message:find("BazUI -> Reload()", 1, true), "blocked-action context retained")
e:Event("LUA_WARNING", "ADDON_LOAD", "Dependency missing")
check(db.errors[3].kind == "Lua warning", "Lua warnings captured")
d:Show(2)
check(e.dialog.actions[1].enabled and e.dialog.actions[2].enabled, "middle report enables previous and next")
e.dialog.actions[1].func()
check(e.dialog.stats:find("Error 1 of 3", 1, true), "previous action browses reports")
e.dialog.actions[2].func()
check(e.dialog.stats:find("Error 2 of 3", 1, true), "next action browses reports")
e.dialog.actions[3].func()
check(e.dialog.content:find("early error", 1, true) and e.dialog.content:find("Reload()", 1, true), "copy all includes every report")
d:Capture(e.secret, e.secret)
check(db.errors[#db.errors].message == "[protected value]", "protected values are never inspected or converted")
d:Capture("|cffff0000colored|r\0message", "stack")
check(db.errors[#db.errors].message == "colored?message", "UI escapes and control characters removed")
d:Capture(string.rep("m", 4000), string.rep("s", 14000))
check(#db.errors[#db.errors].message < 3100 and #db.errors[#db.errors].stack < 12100, "individual reports bounded")
d:Clear()
check(#db.errors == 0 and db.dropped == 0, "clear resets local history")
d:Show()
check(e.dialog.content == "No captured errors.", "empty browser is explicit")
for i = 1, 20 do d:Capture("Flood " .. i, "stack") end
check(#db.errors == 10 and db.dropped == 10, "unique error floods are limited")
d:Capture("Flood 1", "stack")
check(db.errors[#db.errors].count == 2, "known repeats continue counting during flood protection")
e.now = e.now + 6
d:Capture("After flood", "stack")
check(#db.errors == 11, "capture recovers after flood interval")
d:Clear()
for i = 1, 65 do e.now = e.now + 6; d:Capture("Error " .. i, "stack") end
check(#db.errors == 50 and db.errors[1].message == "Error 16", "history keeps the newest 50 reports")
local e2, d2 = NewEnvironment(db)
e2:Initialize()
check(#e2.BazUIDevDB.errors == 50 and e2.BazUIDevDB.session == 2, "reports survive reload with a new session")
e2:FlushTimers()
check(#e2.printed == 0, "historical reports do not trigger new-error alerts")
d2:Command("clear")
check(#e2.BazUIDevDB.errors == 0, "clear command removes persisted reports")
d2:Command("status")
check(e2.printed[#e2.printed]:find("native handler", 1, true), "status command reports backend")
local corrupt, cd = NewEnvironment({ errors = { false, {message="broken",stack="x",version="026",kind="Lua error",count=1} } })
corrupt:Initialize(); cd:Show()
check(corrupt.dialog.content == "No captured errors.", "malformed stored entries safely discarded")

local item = { message = "Grabber error", stack = "original stack", counter = 2, session = 9 }
local g = { GetErrorByID = function() return item end, GetDB = function() return {item} end,
    GetSessionId = function() return 9 end }
local bg, bd = NewEnvironment(nil, g, true)
bg:Initialize()
check(bg.callbackName == "BugGrabber.BugGrabbed" and bd.grabber == g, "modern BugGrabber callback connected")
check(#bg.BazUIDevDB.errors == 1 and bg.BazUIDevDB.errors[1].count == 2, "current BugGrabber session imported")
bg.callback(nil, 1)
check(bg.BazUIDevDB.errors[1].count == 2, "repeated provider notification does not double count")
item.counter = 3; bg.callback(nil, 1)
check(bg.BazUIDevDB.errors[1].count == 3, "provider occurrence increments preserved")
bg.handler("Grabber error")
check(#bg.BazUIDevDB.errors == 1, "native and BugGrabber capture do not duplicate errors")
bd:Clear(); item.counter = 4; bg.callback(nil, 1)
check(#bg.BazUIDevDB.errors == 1 and bg.BazUIDevDB.errors[1].count == 1, "provider clear preserves the counter baseline")
local legacy = { RegisterCallback = function(_, name, fn) legacyCallback = fn end }
local le, ld = NewEnvironment(nil, legacy)
le:Initialize()
check(ld.grabber == legacy, "legacy BugGrabber callback supported")
legacyCallback(nil, { message="legacy error", stack="legacy stack", counter=1 })
check(le.BazUIDevDB.errors[1].message == "legacy error", "legacy error payload stored")

-- A previous handler that calls geterrorhandler() must not recurse forever.
local re, rd = NewEnvironment()
re:Initialize()
local oldForward = re.forwarded
-- Fault inside capture must be contained rather than breaking the global handler.
re.GetBuildInfo = function() error("metadata fault") end
re.handler("should forward despite capture failure")
check(re.forwarded == oldForward + 1 and rd.captureFailures == 1, "reporter failures do not break prior error handling")
print("Developer errors: " .. checks .. " behavioral checks passed")
