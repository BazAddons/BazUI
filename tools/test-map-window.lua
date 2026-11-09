-- Lua 5.1 checks for the native map's optional widescreen sizing.
local checks = 0
local function check(value, label) assert(value, label); checks = checks + 1 end
local combat, wide, ready, eventHandler, showHandler, pending = false, true
local changes = 0
local addon = {GetSetting=function() return wide end}
BazUI = {GetModule=function() return addon end}
InCombatLockdown = function() return combat end
EventUtil = {ContinueOnAddOnLoaded=function(_, fn) ready=fn end}
CreateFrame = function()
    return {SetScript=function(_, _, fn) eventHandler=fn end,
        RegisterEvent=function(_, event) pending=event end,
        UnregisterEvent=function() pending=nil end}
end
local parent = {GetWidth=function() return 1920 end, GetEffectiveScale=function() return 1 end}
local map = {width=1400, height=1080, scale=1, max=true}
function map:GetParent() return parent end
function map:GetWidth() return self.width end
function map:GetEffectiveScale() return self.scale end
function map:IsMaximized() return self.max end
function map:SetWidth(width) assert(not combat);self.width=width end
function map:OnFrameSizeChanged() changes=changes+1 end
function map:UpdateMaximizedSize() assert(not combat);self.width=1400;self.height=1080 end
function map:HookScript(_, fn) showHandler=fn end
WorldMapFrame=map
hooksecurefunc=function(target, method, fn)
    local original=target[method]
    target[method]=function(self, ...) original(self, ...);fn(self, ...) end
end
dofile('Modules/Map/Window.lua')
addon:ApplyWindowSettings()
check(map.width==1400, 'settings are safe before the map addon loads')
addon:InitializeWindow();ready()
check(map.width==1890 and map.height==1080, 'maximized map fills available width without changing height')
check(changes==1, 'canvas receives a size-change notification')
map:UpdateMaximizedSize()
check(map.width==1890, 'native display-size updates retain widescreen layout')
wide=false;addon:ApplyWindowSettings()
check(map.width==1400, 'disabling restores the native aspect ratio immediately')
map.max=false;map.width=702;map.height=534;wide=true
addon:ApplyWindowSettings();showHandler()
check(map.width==702 and map.height==534, 'normal map window keeps its original dimensions')
map.max=true;combat=true
addon:ApplyWindowSettings()
check(map.width==702 and pending=='PLAYER_REGEN_ENABLED', 'resizing waits through combat')
combat=false;eventHandler({UnregisterEvent=function() pending=nil end})
check(map.width==1890 and pending==nil, 'deferred resize applies when combat ends')
map.scale=.5;addon:ApplyWindowSettings()
check(map.width==3810, 'screen width accounts for a different map effective scale')
wide=false;combat=true;addon:ApplyWindowSettings()
check(map.width==3810 and pending~=nil, 'disabling in combat is deferred too')
combat=false;eventHandler({UnregisterEvent=function() pending=nil end})
check(map.width==1400, 'deferred disable restores native sizing')
wide=true;showHandler()
check(map.width==3810, 'reopening reapplies the saved widescreen preference')
print('Map window: '..checks..' checks passed')
