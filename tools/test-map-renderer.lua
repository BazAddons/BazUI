-- Lua 5.1 smoke checks for the isolated renderer and fixed-scope Map module.
local checks = 0
local function check(ok, label) assert(ok,label);checks=checks+1 end
local function Noop() end
local function Frame()
    return {Hide=Noop,Show=Noop,SetScript=Noop,RegisterEvent=Noop,UnregisterEvent=Noop,
        CreateTexture=function() return {SetTexture=Noop,SetColorTexture=Noop,Hide=Noop} end}
end
CreateFrame=Frame
CopyTable=function(original)
    local copy={}
    for k,v in pairs(original) do copy[k]=type(v)=='table' and CopyTable(v) or v end
    return copy
end
function wipe(t) for k in pairs(t) do t[k]=nil end end
function tContains(t,v) for _,x in ipairs(t) do if x==v then return true end end end
tinsert=table.insert
local loaded,ready,errors,notices=false,{}, {}, {}
local settings,spec={},nil
local module={Print=function(_,text) notices[#notices+1]=text end}
function module:GetSetting(key) return settings[key] end
function module:SetSetting(key,value) settings[key]=value end
function module:OnProfileChanged(fn) self.profileChanged=fn end
BazUI={IsRetail=false,VERSION='028',GetModule=function() return module end,
    RegisterModule=function(_,name,config) ready[name]=config;settings=CopyTable(config.defaults);return module end,
    RegisterSettingsSpec=function(_,_,value) spec=value end,QueueForModule=Noop,
    Print=function(_,text) notices[#notices+1]=text end}
C_AddOns={IsAddOnLoaded=function() return loaded end}
EventUtil={ContinueOnAddOnLoaded=function(name,fn) deferredName,deferredSetup=name,fn end}
C_Map={GetMapRectOnMap=function(id) if id==1415 then return .2,.5,.1,.9 end end,
    GetMapInfoAtPosition=function() return nil end}
GetTime=function() return 100 end
geterrorhandler=function() return function(err) errors[#errors+1]=err end end
local protected={}
issecretvalue=function(value) return value==protected end
for line in io.lines('BazUI.toc') do
    if line:match('^Modules\\Map\\.*%.lua') then dofile(line:gsub('\\','/')) end
end
local r=BazUI.MapRuntime
local renderer=r:GetModule('worldmap')
check(ready.Map.title=='Map' and renderer~=nil,'Map is a BazUI module with its own renderer')
check(_G.OpenMap==nil and _G.OpenMapDB==nil,'no OpenMap globals or saved variables are created')
check(r.Media.tex:find('BazUI\\Modules\\Map',1,true),'textures resolve independently of installed OpenMap')
loaded=true;ready.Map.onReady(module)
check(module.renderer==nil and deferredSetup==nil and #notices==1,'installed OpenMap prevents competing map ownership')
loaded=false;ready.Map.onReady(module)
check(module.renderer==renderer and deferredName=='Blizzard_WorldMap' and type(deferredSetup)=='function','renderer waits for the native world map to load')
for _,key in ipairs({'icons','boats','zeppelins','flight','routes','gapFills','chart','underground','gapMinimap','soften'}) do
    check(renderer.db[key]==false,'extra feature remains disabled: '..key)
end
check(renderer.db.unexplored=='hide','Blizzard exploration is preserved rather than revealing unexplored areas')
check(renderer.db.minimap==true and renderer.db.minimapMix==.45 and renderer.db.minimapDeep==.85,'terrain transition retains upstream strengths')
check(ready.Map.profiles and ready.Map.slash[1]=='/bazmap' and spec~=nil,'map controls are profile-backed and reachable through settings')
-- Install against the existing native frame without creating a map window.
local hooks,providers={},{}
local manager={InsertFrameLevelAbove=function() return true end,GetValidFrameLevel=function(_,key)
    if key=='PIN_FRAME_LEVEL_MAP_EXPLORATION' then return 10
    elseif key=='PIN_FRAME_LEVEL_BAZUI_MAP_STITCH' then return 20
    else return 120 end
end}
local canvas={CreateZoomLevels=Noop,ResetZoom=Noop,CalculateScrollExtentsAtScale=Noop,
    HookScript=function(_,event,fn) hooks[event]=fn end}
local native={ScrollContainer=canvas,GetPinFrameLevelsManager=function() return manager end,
    AddCanvasClickHandler=function() end,EnumeratePinsByTemplate=function() return function() end end,
    IsShown=function() return false end,AddDataProvider=function(_,dp) providers[#providers+1]=dp end}
WorldMapFrame=native
MapCanvasDataProviderMixin={}
CreateFromMixins=function(mixin) return CopyTable(mixin) end
hooksecurefunc=function() end
deferredSetup()
check(WorldMapFrame==native and #providers==1,'existing Blizzard map receives one rendering data provider')
check(type(hooks.OnMouseWheel)=='function' and type(hooks.OnUpdate)=='function','smooth wheel zoom is attached to the native canvas')
local x,y=r.Safe.XY({GetXY=function() return 1,2 end})
check(x==1 and y==2,'native vectors are read through the adapter')
check(r.Safe.XY(protected)==nil and r.Safe.XY({x=protected,y=2})==nil,'protected map coordinates are not exposed')
check(r.Safe.Call(function() return protected end)==nil,'protected API results are discarded')
check(r.Safe.Call(function() error('unavailable') end)==nil,'unavailable API calls remain contained')
local s=r.MapStitch
local left,right,top,bottom=s.Rect(947)
check(left==0 and right==1 and top==0 and bottom==1,'world rectangle is normalized')
left,right=s.Rect(1415)
check(left==.2 and right==.5 and s.Rect(123456)==nil,'native zone/continent geometry is resolved safely')
-- Exercise the actual close-up fade without building GPU-backed map layers.
s.closeLayers={minimap=Frame(),grain=Frame(),under=Frame()}
r.MapMinimap={}
s.SetSea=Noop;s.Cull=Noop;s.SetBlur=Noop
s.SetView(.35,.5,.01,.01,20)
local low=s.closeView.mix
s.SetView(.35,.5,.01,.01,27)
local mid=s.closeView.mix
s.SetView(.35,.5,.01,.01,48)
local high=s.closeView.mix
check(low==0 and mid>low and high>mid and high<=.85,'terrain smoothly fades in with increasing zoom')
s.SetView(.35,.5,.01,.01,10)
check(s.closeView.mix==0,'terrain fades away when zooming out')
renderer.db.minimap=false
s.SetView(.35,.5,.01,.01,48)
check(s.closeView.mix==0,'disabling terrain leaves the painted map intact')
renderer.db.minimap=true
spec.entries[1].set(nil,100)
s.SetView(.35,.5,.01,.01,48)
check(renderer.db.minimapDeep==1 and s.closeView.mix==1,'100 percent fully covers the painted map at deepest zoom')
local oldCity=s.SurfaceCityCover
s.SurfaceCityCover=function() return 1 end
s.SetView(.35,.5,.01,.01,48)
check(s.closeView.mix==1,'surface cities honor the selected maximum opacity')
s.SurfaceCityCover=oldCity
spec.entries[1].set(nil,0)
s.SetView(.35,.5,.01,.01,48)
check(s.closeView.mix==0,'zero percent disables the terrain overlay')
spec.entries[1].set(nil,60)
s.SetView(.35,.5,.01,.01,48)
check(math.abs(s.closeView.mix-.6)<.00001,'intermediate opacity remains adjustable')
local controls={}
for _,entry in ipairs(spec.entries) do controls[entry.key]=entry end
check(renderer.db.minimapFrom==20 and renderer.db.maxZoom==48,'new zoom controls preserve the original defaults')
settings.fogOfWar=false;module:ApplySettings()
check(renderer.db.unexplored=='show' and controls.unexplored.get()=='show','existing fog-off preference stays revealed')
settings.fogOfWar=true;module:ApplySettings()
check(renderer.db.unexplored=='hide','existing fog-on preference stays hidden')
for _,style in ipairs({'dim','show','hide'}) do
    controls.unexplored.set(nil,style)
    check(renderer.db.unexplored==style and controls.unexplored.get()==style,'unexplored control applies '..style)
end
controls.terrainStart.set(nil,10)
s.SetView(.35,.5,.01,.01,20)
check(s.closeView.mix>0,'earlier transition shows terrain at a lower zoom')
controls.terrainStart.set(nil,30)
s.SetView(.35,.5,.01,.01,20)
check(s.closeView.mix==0,'later transition preserves the painted map at the same zoom')
controls.maxZoom.set(nil,96)
check(renderer.db.maxZoom==96 and controls.maxZoom.get()==96,'maximum zoom updates the renderer through its zoom-level setter')
settings.maxZoom=999;settings.terrainStart=-5;module:ApplySettings()
check(renderer.db.maxZoom==192 and renderer.db.minimapFrom==1,'out-of-range zoom settings are clamped')
settings.maxZoom='invalid';settings.terrainStart='invalid';settings.unexplored='invalid';module:ApplySettings()
check(renderer.db.maxZoom==48 and renderer.db.minimapFrom==20 and renderer.db.unexplored=='hide','invalid map settings fall back to safe defaults')
settings.terrainOpacity=100;settings.fogOfWar=false
settings.unexplored='dim';settings.terrainStart=25;settings.maxZoom=80
module.profileChanged()
check(renderer.db.minimapDeep==1 and renderer.db.unexplored=='dim' and renderer.db.minimapFrom==25 and renderer.db.maxZoom==80,'switching profiles reapplies all map appearance and zoom controls')
check(#errors==0,'isolated rendering core has no missing optional dependencies')
print('Map renderer: '..checks..' checks passed')
