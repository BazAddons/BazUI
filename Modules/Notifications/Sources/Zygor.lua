-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Zygor: Zygor's notifications, shown here instead of there.
--
-- Zygor keeps a notification center of its own and pops a toast of its own
-- when something arrives. If somebody is running both, that is two places
-- to look and two different-looking toasts for the same class of thing.
--
-- This is an integration, not a port: nothing of Zygor's is copied or
-- reimplemented. We listen to the one call it makes when it raises a
-- notification, repeat the title and text through our own center, hand on
-- whatever clicking it was going to do, and stop its toast from being
-- shown. Its own list is left intact and its own settings still decide
-- whether a notification happens at all - if Zygor is switched off, or has
-- notifications switched off, there is nothing here to forward.
--
-- Nothing happens at all unless Zygor is installed and running.
-- ==========================================================================

local MODULE_ID   = "zygor"
local MODULE_NAME = "Zygor"
local MODULE_ICON = BazUI.Skin.ZYGOR_ICON

---------------------------------------------------------------------------
-- Only where there is a Zygor to listen to.
--
-- Asked by what is installed rather than by what has loaded: this file
-- runs before Zygor does. And either way, somebody who does not run it
-- should not find a Zygor section sitting in their notification settings
-- doing nothing. The guides ship under a few folder names depending on
-- the flavour, so any of them counts.
---------------------------------------------------------------------------

local ZYGOR_ADDONS = {
    "ZygorGuidesViewerClassic",
    "ZygorGuidesViewerClassicEra",
    "ZygorGuidesViewer",
}

local function ZygorInstalled()
    local GetInfo = C_AddOns and C_AddOns.GetAddOnInfo or _G.GetAddOnInfo
    if not GetInfo then return false end
    for _, name in ipairs(ZYGOR_ADDONS) do
        -- A name comes back for anything the client knows about, whether
        -- or not it is switched on at the moment.
        local ok, title = pcall(GetInfo, name)
        if ok and title then return true end
    end
    return false
end

if not ZygorInstalled() then return end

local GetSetting = BNC:CreateGetSetting(MODULE_ID)

-- The one we replaced, kept so it can be put back and so a second pass
-- cannot wrap our own wrapper.
local stockShowOne

local function Center()
    local ZGV = _G.ZGV
    return ZGV and ZGV.NotificationCenter or nil
end

-- Zygor's own switch. Forwarding a notification it decided not to raise
-- would be putting words in its mouth.
local function ZygorWantsNotifications()
    local ZGV = _G.ZGV
    local profile = ZGV and ZGV.db and ZGV.db.profile
    if not profile then return true end
    return profile.nc_enable ~= false
end

---------------------------------------------------------------------------
-- The entry behind the words
--
-- A Zygor notification is usually also a button: "Click to see skills",
-- "Click to open in new tab". The action lives on the entry AddEntry has
-- just built, and a hook is handed the arguments rather than the entry -
-- so the entry is found where AddEntry has just put it: at the front of
-- its list, or on the separate frame used for the ones shown outside the
-- queue.
--
-- What we keep is its ident, not its function. Between a toast arriving
-- and somebody clicking it Zygor may have taken that entry back - several
-- kinds clear their own type when the next one arrives - and running a
-- function belonging to an entry it has dropped would be doing something
-- it decided not to do. Looking the ident up at click time asks afresh:
-- still there, run it; gone, nothing happens.
---------------------------------------------------------------------------

local function SpecialEntry(NC)
    return NC and NC.SpecialNotif and NC.SpecialNotif.entry or nil
end

local function NewestEntry(NC, notiftype, title)
    local newest = NC and NC.Entries and NC.Entries[1]
    if newest and newest.notiftype == notiftype and newest.title == title then
        return newest
    end
    local special = SpecialEntry(NC)
    if special and special.notiftype == notiftype and special.title == title then
        return special
    end
    return nil
end

local function EntryByIdent(ident)
    local NC = Center()
    if not NC then return nil end
    local entry = NC.GetEntry and NC:GetEntry(ident)
    if entry then return entry end
    local special = SpecialEntry(NC)
    if special and special.ident == ident then return special end
    return nil
end

-- Clicking our card does what clicking Zygor's own notification would
-- have done, including taking the entry out of its list: one notification
-- showing in two places should not have to be answered twice.
local function ClickAction(entry)
    local ident = entry and entry.ident
    if ident == nil then return nil end
    return function()
        local live = EntryByIdent(ident)
        if live and type(live.func) == "function" then
            pcall(live.func)
        end
    end
end

local function Forward(notiftype, title, text, onClick)
    if GetSetting("showZygor") == false then return end
    if not ZygorWantsNotifications() then return end
    if type(title) ~= "string" or title == "" then return end

    BNC:Push({
        event    = "zygor",
        module   = MODULE_ID,
        title    = title,
        message  = (type(text) == "string" and text ~= "") and text or nil,
        icon     = MODULE_ICON,
        priority = "normal",
        duration = GetSetting("toastDuration") or 5,
        silent   = GetSetting("zygorToasts") == false,
        onClick  = onClick,
        -- Which kind of notification Zygor called it, kept for the history
        -- even though nothing reads it yet.
        tag      = notiftype,
    })
end

---------------------------------------------------------------------------
-- Hooking on
--
-- AddEntry is hooked rather than replaced, so Zygor's own list still
-- gets its entry and its notification button still counts it. ShowOne is
-- the toast, and that one has to be replaced rather than hooked: a hook
-- runs after the thing it hooks, and by then the toast is already on
-- screen. The original is called whenever the switch is off, so turning
-- this off gives Zygor its toast back without a reload.
---------------------------------------------------------------------------

local function Install()
    local NC = Center()
    if not NC or stockShowOne then return true end

    hooksecurefunc(NC, "AddEntry", function(_, notiftype, title, text)
        Forward(notiftype, title, text,
            ClickAction(NewestEntry(NC, notiftype, title)))
    end)

    stockShowOne = NC.ShowOne
    NC.ShowOne = function(self, entry)
        if GetSetting("suppressZygorToast") ~= false then return end
        return stockShowOne(self, entry)
    end

    return true
end

-- Zygor builds its notification center during its own startup, which may
-- be after ours. Try at login and give it a few seconds to appear before
-- giving up quietly - an addon that is not installed is not a problem to
-- report.
local function InstallWhenReady(attempt)
    attempt = attempt or 1
    if Install() then return end
    if attempt > 10 then return end
    C_Timer.After(1, function() InstallWhenReady(attempt + 1) end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    InstallWhenReady()
end)

---------------------------------------------------------------------------
-- What we are leaning on
--
-- Another addon's furniture rather than the game's, which makes it more
-- likely to move, not less. Declared so /baz check says so plainly
-- instead of leaving a notification that quietly never arrives or a card
-- that quietly does nothing.
---------------------------------------------------------------------------

local ZYGOR_HOLDS = {
    { label = "ZGV.NotificationCenter",
      why   = "Everything else here hangs off it.",
      check = function() return Center() ~= nil end },
    { label = "NotificationCenter:AddEntry",
      why   = "Hooked to hear a notification being raised.",
      check = function() return BazUI.Has.Member(Center(), "AddEntry") end },
    { label = "NotificationCenter:ShowOne",
      why   = "Replaced to hold Zygor's own popup back.",
      check = function() return BazUI.Has.Member(Center(), "ShowOne") end },
    { label = "NotificationCenter:GetEntry and .Entries",
      why   = "Finding the entry again, so clicking ours does what clicking theirs did.",
      check = function()
          local NC = Center()
          return BazUI.Has.Member(NC, "GetEntry") and BazUI.Has.Member(NC, "Entries")
      end },
}

-- Only asked when Zygor is actually loaded. Without that these four read
-- as MISSING on every machine that does not have it, which is most of
-- them - and a report with four permanent red lines in it is a report
-- people stop reading.
local function ZygorLoaded()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    return loaded and loaded("ZygorGuidesViewer") and true or false
end

for _, hold in ipairs(ZYGOR_HOLDS) do
    BazUI:RegisterDependency({
        module   = "Notifications (Zygor)",
        label    = hold.label,
        why      = hold.why,
        check    = hold.check,
        when     = ZygorLoaded,
        whenNote = "Zygor is not loaded, so nothing here applies.",
    })
end

BNC:RegisterModule({
    id    = MODULE_ID,
    name  = MODULE_NAME,
    icon  = MODULE_ICON,
    -- The orange off their own mark, so a forwarded notification is
    -- recognizably theirs in a panel full of ours.
    color = { 0.95, 0.45, 0.15, 1.0 },
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { type = "event", key = "zygor", label = "Zygor notifications",
      show = "showZygor", toast = "zygorToasts" },
    { key = "suppressZygorToast", label = "Hide Zygor's own popup",
      type = "toggle", default = true },
    { key = "toastDuration", label = "Toast duration",
      type = "slider", default = 5, min = 1, max = 15, step = 1 },
})
