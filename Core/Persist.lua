-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: where the settings actually live
--
-- WoW: Forever 1.60 writes an addon's saved variables at every logout and
-- never reads one back. Account scope and per-character scope both, for
-- every addon on the client, which is why Core/Seed.lua exists: a settings
-- file wearing an addon file's clothes, rebaked by hand from whatever the
-- client last wrote.
--
-- There is a way out, and it is the client's own. Some of Blizzard's
-- addons declare their saved variable as `## SavedVariablesMachine`, which
-- lands in WTF/SavedVariables/ rather than under Account/ - and the client
-- reads those back. Blizzard_AddOnList is one of them:
--
--     ## SavedVariablesMachine: g_addonCategoriesCollapsed
--
-- That global is an ordinary Lua table, saved and restored by a client
-- that will not save and restore ours. Storing our tables under our own
-- keys inside it is a file we know is read back, carrying settings we know
-- are not.
--
-- Two things were measured rather than assumed, with a counter in each
-- channel that climbs once per login (BazTest, BazTestM, in the workspace
-- beside this repository - neither ships):
--
--   * Account saved variables read back 1 on the seventh login. Confirmed
--     broken, exactly as Seed.lua says.
--   * The same counter inside g_addonCategoriesCollapsed read 7. Confirmed
--     working, across full client restarts rather than only reloads.
--   * Declaring `## SavedVariablesMachine` ourselves does nothing at all:
--     the client created no file for it. The directive is honoured for
--     Blizzard's addons and ignored for everybody else, so the one-line
--     fix is not available and this is the way.
--
-- What is stored is a REFERENCE, not a copy. host[key] = BazUIDB, so every
-- later write into BazUIDB is already in the table the client will save.
-- There is nothing to flush, nothing to serialize, and no window in which
-- a change is made and not yet mirrored.
--
-- Only Blizzard's own key space is theirs: their code reads and writes
-- g_addonCategoriesCollapsed[category] for category names it knows, and
-- never walks the table. Our keys are ignored by it, and theirs by us.
---------------------------------------------------------------------------

local ADDON_NAME = ...
BazUI = BazUI or {}

local Persist = {}
BazUI.Persist = Persist

-- Blizzard_AddOnList's saved variable. Declared `## DefaultState: enabled`
-- and shipped with the game, so the table is there on every install.
local HOST        = "g_addonCategoriesCollapsed"
local ACCOUNT_KEY = "BazUI"
local CHAR_PREFIX = "BazUI@"
-- Somebody else's saved variables, rescued the same way. See "Guests".
local GUEST_PREFIX = "BazUI#"

Persist.HOST = HOST

local function HostTable()
    local host = _G[HOST]
    if type(host) ~= "table" then return nil end
    return host
end

-- Machine scope is not per-character, and it is not even per-account: one
-- file for the whole install. So the character's own table is kept under a
-- key naming the character.
local function CharKey()
    local name  = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    if not name then return nil end
    return CHAR_PREFIX .. name .. "-" .. tostring(realm or "?")
end

---------------------------------------------------------------------------
-- Which copy is newer
--
-- A stamp rather than "does it have anything in it", because a baked
-- Seed.lua puts real settings into BazUIDB before the client has had its
-- say, and a client that works puts real settings there too. Both look
-- identical to a test that only counts keys - and picking the wrong one
-- discards a session's worth of changes.
--
-- The stamp counts logins, so it is the same question asked of both
-- copies: which of you was last written by a running game. Ties go to the
-- saved variables, because on a healthy client the two are the same table
-- and there is nothing to choose.
---------------------------------------------------------------------------

local function Stamp(tbl)
    if type(tbl) ~= "table" then return -1 end
    local mark = rawget(tbl, "_persist")
    if type(mark) ~= "table" then return 0 end
    return tonumber(mark.stamp) or 0
end

local function Bump(tbl)
    if type(tbl) ~= "table" then return end
    local mark = rawget(tbl, "_persist")
    if type(mark) ~= "table" then
        mark = {}
        tbl._persist = mark
    end
    mark.stamp = (tonumber(mark.stamp) or 0) + 1
    mark.savedBy = ADDON_NAME
end

-- Picks between what the client gave us and what the host is holding, and
-- leaves the winner attached to the host. Returns the table to use, and
-- what happened, for /baz sv to report.
local function Resolve(globalName, key, fallback)
    local host = HostTable()
    local mine = _G[globalName]
    if type(mine) ~= "table" then mine = fallback end

    if not host or not key then
        return mine, "no host table"
    end

    local hosted = host[key]
    local how

    if type(hosted) == "table" and Stamp(hosted) > Stamp(mine) then
        -- The client did not give us our file, or gave us an older one.
        -- The host's copy is the settings.
        mine = hosted
        how = "restored from the host table"
    elseif type(hosted) == "table" then
        how = "saved variables were current"
    else
        how = "nothing stored yet"
    end

    Bump(mine)
    -- The reference, so everything written from here on is already in the
    -- table the client will save. Re-pointed every login because Blizzard's
    -- own file assigns g_addonCategoriesCollapsed = {} when it loads, and
    -- the restore replaces the table wholesale: a reference taken in an
    -- earlier session points at something nobody will save.
    host[key] = mine
    _G[globalName] = mine
    return mine, how
end

---------------------------------------------------------------------------
-- Does this client read saved variables at all?
--
-- Asked because a client that does needs none of this, and putting sixty
-- odd kilobytes of BazUI into Blizzard's machine file on retail is rude:
-- that file is one per install rather than one per account, and the copy
-- would never be read, because the saved variables always win.
--
-- The answer comes from the per-character load counter, which has been in
-- Core.lua since the day the bug was found and exists for exactly this
-- question. Seed.lua deliberately refuses to seed it - "seeding it would
-- forge the one honest signal we have" - so unlike the settings
-- themselves it cannot be faked by a bake, and unlike a key count it
-- cannot be confused by our own defaults. If it comes back with a number
-- in it, the client read the file.
--
-- Asked once and remembered, because the answer stops being true the
-- moment we act on it: ReadyVariables writes `loads` itself, right after
-- Adopt. Asked live afterwards it says "this client reads files fine" on
-- the strength of the number we just put there - which is how the guest
-- system came to do nothing at all, silently, while reporting success.
-- A reading taken after the thing it measures has been disturbed is not
-- a reading.
---------------------------------------------------------------------------

function Persist:ClientReadsVariables()
    if self.clientReads ~= nil then return self.clientReads end
    local char = _G.BazUICharDB
    return type(char) == "table" and tonumber(char.loads) ~= nil
end

---------------------------------------------------------------------------
-- The one call
--
-- Made from ReadyVariables in Core.lua, at the moment the saved variables
-- are as real as they are going to get and before anything reads a
-- setting. Later than that and a module is holding a reference to a table
-- about to be thrown away; earlier and the host has not been restored yet.
---------------------------------------------------------------------------

function Persist:Adopt()
    local report = { host = HostTable() ~= nil }

    -- Settled here, before a single write of ours, and true for the rest
    -- of the session. See ClientReadsVariables.
    self.clientReads = self:ClientReadsVariables()
    report.clientReads = self.clientReads

    -- A working client: use what it gave us, and hand back anything we
    -- left in the host table on a client that was not working. That makes
    -- this self-cleaning in both directions - a retail install carries one
    -- login's worth of our data at most, and a Forever client that gets
    -- fixed tidies up after itself the first time it reads a file.
    if self:ClientReadsVariables() then
        local dropped = self:Forget()
        report.account = "saved variables work on this client"
        report.char    = report.account
        report.dropped = dropped
        report.charKey = CharKey()
        self.report = report
        return _G.BazUIDB, _G.BazUICharDB
    end

    local account, accountHow = Resolve("BazUIDB", ACCOUNT_KEY, {})
    report.account = accountHow

    local charKey = CharKey()
    local char, charHow = Resolve("BazUICharDB", charKey, {})
    report.char = charHow
    report.charKey = charKey

    self.report = report
    return account, char
end

-- What happened, in words, for /baz sv.
function Persist:Describe()
    local r = self.report
    if not r then return "not run yet" end
    if not r.host then
        return HOST .. " is not there - settings are in the saved variables only"
    end
    if r.dropped then
        return ("%s%s"):format(tostring(r.account),
            (r.dropped > 0) and (", and " .. r.dropped .. " table"
                .. ((r.dropped == 1) and " was" or "s were") .. " handed back") or "")
    end
    return ("account: %s; character (%s): %s")
        :format(tostring(r.account), tostring(r.charKey or "unknown"), tostring(r.char))
end

-- Everything of ours the host is carrying, for the diagnostic command and
-- for a player who wants it gone.
function Persist:Keys()
    local host = HostTable()
    if not host then return {} end
    local keys = {}
    for key in pairs(host) do
        if type(key) == "string"
            and (key == ACCOUNT_KEY
                 or key:sub(1, #CHAR_PREFIX) == CHAR_PREFIX
                 or key:sub(1, #GUEST_PREFIX) == GUEST_PREFIX) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

-- Hands the host table back to Blizzard. The settings in memory are
-- untouched; they simply stop being saved anywhere the client will read.
function Persist:Forget()
    local host = HostTable()
    if not host then return 0 end
    local n = 0
    for _, key in ipairs(self:Keys()) do
        host[key] = nil
        n = n + 1
    end
    return n
end

---------------------------------------------------------------------------
-- Guests: somebody else's saved variables
--
-- The bug is not ours and neither is the damage. Every addon on this
-- client loses its settings at logout, and an addon that does not know
-- about the host table has no way to keep them. BazUI does know, and a
-- table is a table, so it can carry somebody else's as easily as its own.
--
-- Turned on per addon and never guessed at. BazUI quietly taking charge
-- of another addon's settings is a surprise nobody asked for, and the
-- addon itself has no idea we are doing it - so this is something you
-- switch on for a named addon, and can switch off again.
--
-- The timing is the whole trick. BazUI adopts its own tables at
-- PLAYER_LOGIN, which is far too late for a guest: by then the guest has
-- read its globals at its own ADDON_LOADED and built from what it found.
-- But event handlers run in the order they were registered, and BazUI's
-- files run before any addon later in the alphabet, so our ADDON_LOADED
-- handler for "TomTom" runs before TomTom's own. The client loads an
-- addon's saved variables immediately before firing that event, so the
-- moment we see it is the moment after the client has had its go and
-- before the guest has had its.
--
-- An addon that loads before BazUI cannot be rescued this way, and is
-- refused rather than half-handled.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Recipes
--
-- What each addon saves, because the client will not say. An addon's own
-- .toc names its globals on the `## SavedVariables` line and that is
-- where every one of these came from; none is guessed. Only addons the
-- player actually has turn into switches, so this list being longer than
-- anybody's install costs nothing.
--
-- Anything not here is still reachable with /baz persist add <AddOn>
-- <Globals>, which is what the switches call underneath.
---------------------------------------------------------------------------

Persist.RECIPES = {
    TomTom       = { "TomTomDB", "TomTomWaypoints", "TomTomWaypointsM" },
    BugSack      = { "BugSackDB", "BugSackLDBIconDB" },
    ForeverMeter = { "ForeverMeterDB" },
    -- Both of these load before BazUI, so their switches will be greyed
    -- out rather than missing: a switch that is not there is a question
    -- with no answer, and "why can this one not be helped" deserves one.
    ["!BugGrabber"] = { "BugGrabberDB" },
    Auctionator  = {
        "AUCTIONATOR_CONFIG", "AUCTIONATOR_SAVEDVARS",
        "AUCTIONATOR_SHOPPING_LISTS", "AUCTIONATOR_PRICE_DATABASE",
        "AUCTIONATOR_POSTING_HISTORY", "AUCTIONATOR_VENDOR_PRICE_CACHE",
        "AUCTIONATOR_RECENT_SEARCHES", "AUCTIONATOR_SELLING_GROUPS",
    },
}

-- Every addon whose ADDON_LOADED we were in time to see.
--
-- This is the whole test for whether an addon can be helped. Our handler
-- is registered while BazUI's own files run, so we see every addon that
-- loads after us and none that loaded before - which is exactly the set
-- whose saved variables we can put back before they read them. Asking
-- the question this way rather than comparing names alphabetically means
-- it stays right whatever the client decides its load order is.
Persist.seen = {}

function Persist:CanHelp(addOnName)
    return self.seen[addOnName] and true or false
end

-- The switches worth showing: a recipe we have, for an addon this player
-- has installed. Whether it can be helped is a separate question, asked
-- above, and answered by grey rather than by absence.
function Persist:Known()
    local out = {}
    local info = C_AddOns and C_AddOns.GetAddOnInfo
    for addOnName in pairs(self.RECIPES) do
        local ok = info and select(1, pcall(info, addOnName))
        if ok then out[#out + 1] = addOnName end
    end
    table.sort(out)
    return out
end

-- What the client will admit to when asked. Some fields are readable and
-- some are not, and SavedVariables is not documented either way, so it is
-- tried and the answer is used only if it looks like one.
local function DeclaredGlobals(addOnName)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
    if not get then return nil end
    local ok, value = pcall(get, addOnName, "SavedVariables")
    if not ok or type(value) ~= "string" or value == "" then return nil end
    local names = {}
    for word in value:gmatch("[%w_]+") do names[#names + 1] = word end
    return (#names > 0) and names or nil
end

-- The list lives in the host table rather than in BazUIDB, because it has
-- to be readable at a guest's ADDON_LOADED and BazUIDB is not adopted
-- until login. One table, read early, replaced late.
local function GuestList()
    local host = HostTable()
    local mine = host and host[ACCOUNT_KEY]
    if type(mine) ~= "table" then return {} end
    local list = rawget(mine, "persistGuests")
    if type(list) ~= "table" then return {} end
    return list
end

local function GuestKey(addOnName, global)
    return GUEST_PREFIX .. addOnName .. "#" .. global
end

-- Which globals we look after for this addon: what was written down when
-- it was added, or what the client says it declares.
local function GuestGlobals(addOnName)
    local entry = GuestList()[addOnName]
    if type(entry) == "table" and #entry > 0 then return entry end
    return Persist.RECIPES[addOnName] or DeclaredGlobals(addOnName)
end

-- Loads a guest's globals out of the host table, then points the host at
-- whatever the guest ends up using. Called from ADDON_LOADED, before the
-- guest's own handler for the same event.
function Persist:RestoreGuest(addOnName)
    local host = HostTable()
    if not host or self:ClientReadsVariables() then return end

    local globals = GuestGlobals(addOnName)
    if not globals then return end

    local restored = 0
    for _, global in ipairs(globals) do
        local key = GuestKey(addOnName, global)
        local hosted = host[key]
        -- Only when the client gave the guest nothing. A client that
        -- handed over a real file has told us this is not needed, and
        -- overwriting it would be us losing somebody's settings rather
        -- than saving them.
        if type(hosted) == "table" and _G[global] == nil then
            _G[global] = hosted
            restored = restored + 1
        end
        if type(_G[global]) == "table" then host[key] = _G[global] end
    end

    self.guestReport = self.guestReport or {}
    self.guestReport[addOnName] = ("%d of %d restored"):format(restored, #globals)
end

-- Points the host at whatever every guest is holding right now.
--
-- The reference taken at ADDON_LOADED is usually the one the addon keeps,
-- but an addon is free to throw its table away and make another, and one
-- that does would be saving nothing. Asked again at logout, when what the
-- global holds is final.
function Persist:ReattachGuests()
    local host = HostTable()
    if not host or self:ClientReadsVariables() then return end
    for addOnName in pairs(GuestList()) do
        local globals = GuestGlobals(addOnName)
        for _, global in ipairs(globals or {}) do
            if type(_G[global]) == "table" then
                host[GuestKey(addOnName, global)] = _G[global]
            end
        end
    end
end

-- Adding one. `globals` is optional: without it the client is asked what
-- the addon declares, which works when the client will say and not when
-- it will not.
function Persist:AddGuest(addOnName, globals)
    local host = HostTable()
    if not host then return false, "there is no host table on this client" end
    local mine = host[ACCOUNT_KEY]
    if type(mine) ~= "table" then return false, "BazUI's own settings are not in the host table yet" end

    local loaded = C_AddOns and C_AddOns.GetAddOnInfo and C_AddOns.GetAddOnInfo(addOnName)
    if not loaded then return false, "no addon called " .. addOnName end

    globals = globals or Persist.RECIPES[addOnName] or DeclaredGlobals(addOnName)
    if not globals then
        return false, "cannot tell what " .. addOnName
            .. " saves - name its globals, as in: /baz persist add "
            .. addOnName .. " " .. addOnName .. "DB"
    end

    mine.persistGuests = rawget(mine, "persistGuests") or {}
    mine.persistGuests[addOnName] = globals
    -- Capture what it is holding now, so the first logout already has it
    -- rather than waiting for a second one.
    self:ReattachGuests()
    return true, globals
end

function Persist:RemoveGuest(addOnName)
    local host = HostTable()
    local mine = host and host[ACCOUNT_KEY]
    local list = (type(mine) == "table") and rawget(mine, "persistGuests")
    if type(list) ~= "table" or not list[addOnName] then return false end
    local globals = list[addOnName]
    list[addOnName] = nil
    if host then
        for _, global in ipairs((type(globals) == "table") and globals or {}) do
            host[GuestKey(addOnName, global)] = nil
        end
    end
    return true
end

function Persist:IsGuest(addOnName)
    return GuestList()[addOnName] ~= nil
end

function Persist:Guests()
    local names = {}
    for addOnName in pairs(GuestList()) do names[#names + 1] = addOnName end
    table.sort(names)
    return names
end

function Persist:GuestGlobals(addOnName)
    return GuestGlobals(addOnName)
end

---------------------------------------------------------------------------
-- Wiring
--
-- Registered here, at file load, so this handler is in the queue before
-- any addon that loads after BazUI has registered its own.
---------------------------------------------------------------------------

-- When does the host table actually arrive?
--
-- The whole guest idea rests on it being there at a guest's
-- ADDON_LOADED, and this client is late with saved variables in a way no
-- other client is - so it is written down rather than assumed. Every
-- ADDON_LOADED notes whether the table existed and how much was in it,
-- and /baz sv prints the first few. If it is empty until PLAYER_LOGIN,
-- guests cannot work this way and the trace says so plainly.
Persist.hostTrace = {}

local function NoteHost(when)
    local trace = Persist.hostTrace
    if #trace >= 8 then return end
    local host = HostTable()
    local n = 0
    if host then for _ in pairs(host) do n = n + 1 end end
    trace[#trace + 1] = ("%s: %s"):format(when,
        host and (n .. " keys") or "|cffff4444absent|r")
end

NoteHost("BazUI file load")

local guestFrame = CreateFrame("Frame")
guestFrame:RegisterEvent("ADDON_LOADED")
guestFrame:RegisterEvent("PLAYER_LOGIN")
guestFrame:RegisterEvent("PLAYER_LOGOUT")
guestFrame:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        NoteHost("PLAYER_LOGIN")
        return
    end
    if event == "ADDON_LOADED" then
        NoteHost("ADDON_LOADED " .. tostring(name))
        if name then Persist.seen[name] = true end
        if name and GuestList()[name] then
            -- Never let a guest's trouble become ours. This runs inside
            -- somebody else's load, and an error here would take the rest
            -- of their ADDON_LOADED handlers with it.
            pcall(Persist.RestoreGuest, Persist, name)
        end
    else
        pcall(Persist.ReattachGuests, Persist)
    end
end)
