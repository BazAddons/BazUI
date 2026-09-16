-- SPDX-License-Identifier: GPL-2.0-or-later
local BNC = BazUI.Notifications.API
-- ==========================================================================
-- BNC-Zygor: Zygor's notifications, shown here instead of there.
--
-- Zygor keeps a notification centre of its own and pops a toast of its own
-- when something arrives. If somebody is running both, that is two places
-- to look and two different-looking toasts for the same class of thing.
--
-- This is an integration, not a port: nothing of Zygor's is copied or
-- reimplemented. We listen to the one call it makes when it raises a
-- notification, repeat the title and text through our own centre, and stop
-- its toast from being shown. Its own list is left intact and its own
-- settings still decide whether a notification happens at all - if Zygor
-- is switched off, or has notifications switched off, there is nothing
-- here to forward.
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

local function Forward(notiftype, title, text)
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
        Forward(notiftype, title, text)
    end)

    stockShowOne = NC.ShowOne
    NC.ShowOne = function(self, entry)
        if GetSetting("suppressZygorToast") ~= false then return end
        return stockShowOne(self, entry)
    end

    return true
end

-- Zygor builds its notification centre during its own startup, which may
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

BNC:RegisterModule({
    id   = MODULE_ID,
    name = MODULE_NAME,
    icon = MODULE_ICON,
})

BNC:RegisterModuleOptions(MODULE_ID, {
    { type = "event", key = "zygor", label = "Zygor notifications",
      show = "showZygor", toast = "zygorToasts" },
    { key = "suppressZygorToast", label = "Hide Zygor's own popup",
      type = "toggle", default = true },
    { key = "toastDuration", label = "Toast duration",
      type = "slider", default = 5, min = 1, max = 15, step = 1 },
})
