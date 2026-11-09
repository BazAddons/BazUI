-- Lua 5.1 checks for notification layering under the fullscreen map.
local checks = 0
local function check(value, label) assert(value, label); checks = checks + 1 end
BazUI = {Notifications = {}}
local ready, registrations
registrations = 0
EventUtil = {ContinueOnAddOnLoaded=function(_, fn) registrations=registrations+1;ready=fn end}
local function frame(strata, parent)
    return {strata=strata, GetFrameStrata=function(self) return self.strata end,
        SetFrameStrata=function(self, value) self.strata=value end,
        GetParent=function() return parent end}
end
local tooltipOwner, tooltipHides = nil, 0
GameTooltip = {GetOwner=function() return tooltipOwner end,
    Hide=function() tooltipHides=tooltipHides+1 end}
hooksecurefunc = function(target, method, fn)
    local original=target[method]
    target[method]=function(self) original(self);fn() end
end
dofile('Modules/Notifications/UI/Layers.lua')
local register=BazUI.Notifications.RegisterNotificationLayer
local bell, toast, panel, menu = frame('HIGH'), frame('HIGH'), frame('HIGH'), frame('TOOLTIP')
register(bell);register(toast);register(panel);register(menu)
check(registrations==1, 'map-load hooks registered once')
check(bell.strata=='HIGH' and menu.strata=='TOOLTIP', 'normal notification strata preserved before map load')
local scripts = {}
local map = {shown=false, max=true,
    IsShown=function(self) return self.shown end,
    IsMaximized=function(self) return self.max end,
    HookScript=function(_, event, fn) scripts[event]=fn end,
    Maximize=function(self) self.max=true end,
    Minimize=function(self) self.max=false end}
WorldMapFrame=map;ready()
check(bell.strata=='HIGH', 'loading a hidden map does not cover notifications')
map.shown=true;tooltipOwner=frame('HIGH', bell);scripts.OnShow()
check(bell.strata=='BACKGROUND' and toast.strata=='BACKGROUND' and panel.strata=='BACKGROUND' and menu.strata=='BACKGROUND', 'all notification surfaces move below the fullscreen backdrop')
check(tooltipHides==1, 'existing notification tooltip closes when the map covers its owner')
local lateToast=frame('HIGH');register(lateToast)
check(lateToast.strata=='BACKGROUND', 'toasts created while fullscreen are covered immediately')
register(bell)
map:Minimize()
check(bell.strata=='HIGH' and lateToast.strata=='HIGH', 'minimizing restores original strata, including late-created toasts')
check(menu.strata=='TOOLTIP', 'dropdown restores its own original layer')
tooltipOwner=frame('HIGH');local before=tooltipHides
map:Maximize()
check(bell.strata=='BACKGROUND', 'maximizing an open map covers notifications')
check(tooltipHides==before, 'unrelated tooltips are left alone')
map.shown=false;scripts.OnHide()
check(bell.strata=='HIGH' and menu.strata=='TOOLTIP', 'closing the map restores notification layers')
map.max=false;map.shown=true;scripts.OnShow()
check(bell.strata=='HIGH', 'opening the small map keeps normal notification layering')
print('Notification layers: '..checks..' checks passed')
