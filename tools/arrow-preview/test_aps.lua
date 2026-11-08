-- Run under Lua 5.1 from the repository root. No WoW or provider libraries.
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end
local function near(a, b) return math.abs(a - b) < .000001 end
local now, combat, facing, tracked = 100, false, 0, 0
local shift = false
local playerX, playerY = .5, .5
local frames = {}
local Frame = {}
function Frame:SetScript(k,v) self.scripts[k]=v end
function Frame:HookScript(k,v) local old=self.scripts[k]; self.scripts[k]=function(...) if old then old(...) end;v(...) end end
function Frame:Show() local was=self.shown;self.shown=true;if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
function Frame:Hide() local was=self.shown;self.shown=false;if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
function Frame:IsShown() return self.shown end
function Frame:GetAlpha() return self.alpha end
function Frame:SetAlpha(a) self.alpha=a end
function Frame:EnableMouse(b) self.mouse=b end
function Frame:IsMouseEnabled() return self.mouse end
function Frame:SetSize(w,h) self.width=w;self.height=h end
function Frame:SetText(t) self.text=t end
function Frame:SetTexCoord(...) self.uv={...} end
function Frame:SetTexture(t) self.texture=t end
function Frame:SetPoint(...) self.point={...} end
function Frame:GetPoint() return unpack(self.point) end
for _, name in ipairs({'SetFrameStrata','SetClampedToScreen','SetMovable','RegisterForDrag',
    'SetWidth','SetJustifyH','ClearAllPoints','RegisterEvent','StartMoving','StopMovingOrSizing'}) do Frame[name]=function() end end
function CreateFrame(_, name)
    local f=setmetatable({scripts={},alpha=1,mouse=true,shown=true,name=name},{__index=Frame})
    frames[#frames+1]=f
    if name then _G[name]=f end
    return f
end
function Frame:CreateTexture() return CreateFrame() end
function hooksecurefunc(obj,key,callback)
    local old=obj[key]
    assert(type(old)=='function',key)
    obj[key]=function(...) local results={old(...)};callback(...);return unpack(results) end
end
function GetTime() return now end
function InCombatLockdown() return combat end
function GetPlayerFacing() return facing end
function IsShiftKeyDown() return shift end
function GetUnitSpeed() return 7 end
function GetRealmName() return 'Realm' end
function UnitName() return 'Player' end
function CreateVector2D(x,y) return {GetXY=function() return x,y end} end
C_Timer={NewTicker=function(_,fn) return {callback=fn} end,After=function(_,fn) fn() end}
SlashCmdList={}
local maps={ [947]={mapID=947,name='Azeroth',parentMapID=0},
    [37]={mapID=37,name='Elwynn Forest',parentMapID=947},
    [52]={mapID=52,name='Westfall',parentMapID=947},
    [99]={mapID=99,name='Other continent',parentMapID=947} }
C_Map={GetMapInfo=function(id) return maps[id] end,
    GetBestMapForUnit=function() return 37 end,
    GetPlayerMapPosition=function() return CreateVector2D(playerX,playerY) end,
    GetMapChildrenInfo=function(id) if id==947 then return {maps[37],maps[52],maps[99]} end end,
    GetWorldPosFromMapPos=function(map,v)
        local x,y=v:GetXY()
        return map==99 and 2 or 1,CreateVector2D((1-y)*1000,(1-x)*1000)
    end}
C_SuperTrack={GetSuperTrackedQuestID=function() return tracked end}
C_QuestLog={GetNextWaypoint=function(id) if id==7 then return 37,.42,.65 end end,
    GetTitleForQuestID=function(id) return 'Quest '..id end}
local settings, logs = {}, {}
local aps={}
function aps:GetSetting(k) return settings[k] end
function aps:SetSetting(k,v) settings[k]=v end
function aps:Print(t) logs[#logs+1]=t end
function aps:OnProfileChanged(fn) self.profileChanged=fn end
local drawers={QT={C={WIDGET_ID='QuestTracker'}}}
function drawers:GetWidgetSetting(_,_,default) return default end
BazUI={Skin={Theme={FontString=function() return CreateFrame() end}}}
function BazUI:RegisterModule(_,defs) self.defs=defs;settings=defs.defaults;return aps end
function BazUI:GetModule(name) if name=='APS' then return aps elseif name=='Drawers' then return drawers end end
function BazUI:IsModuleEnabled() return true end
function BazUI:OpenCopyDialog(opts) self.copyOpts=opts end
local root='Modules/APS/'
for _,name in ipairs({'Core','Arrow','Navigation','Commands','Integrations'}) do dofile(root..name..'.lua') end
check(TomTom==nil and ZGV==nil,'standalone has no providers')
BazUI.defs.onReady(aps)
check(aps.navigationReady and not aps.frame:IsShown(),'standalone initializes without providers')
local p=aps:WayCommand('42.1 65.9 Test destination')
check(p and near(p.x,.421) and p.title=='Test destination','current-zone coordinates')
check(aps.frame:IsShown(),'standalone arrow visible')
check(not aps.frame.mouse and not aps.frame.scripts.OnMouseUp,'normal display is click-through without click actions')
shift=true;aps.frame.scripts.OnEvent(aps.frame,'MODIFIER_STATE_CHANGED')
check(aps.frame.mouse,'holding Shift enables dragging')
aps.frame.scripts.OnDragStart(aps.frame)
check(aps.frame._apsDragging,'Shift-drag starts movement')
shift=false;aps.frame.scripts.OnEvent(aps.frame,'MODIFIER_STATE_CHANGED')
check(not aps.frame.mouse and not aps.frame._apsDragging,'releasing Shift ends drag and restores click-through')
aps.frame.scripts.OnDragStart(aps.frame)
check(not aps.frame._apsDragging,'ordinary drag cannot start movement')
p=aps:WayCommand('/way Elwynn Forest 42.1 65.9 Wowhead destination')
check(p and p.map==37 and p.title=='Wowhead destination','copied named-zone command')
p=aps:WayCommand('#52 12,5 90,25 Decimal comma')
check(p and near(p.x,.125) and near(p.y,.9025),'decimal comma with literal map ID')
p=aps:WayCommand('12.5, 90.25 Trailing comma')
check(p and near(p.y,.9025),'coordinate separator comma')
check(aps:ResolveMap('West')==52,'partial zone match')
check(aps:ResolveMap('unknown')==nil,'invalid zone rejected')
local count=#aps:WaypointStore().points
aps:WayCommand('101 40');aps:WayCommand('-1 40');aps:WayCommand('42 nope')
check(#aps:WaypointStore().points==count,'invalid coordinates do not create targets')
local north=aps:VectorToPoint({map=37,x=.5,y=.4})
local west=aps:VectorToPoint({map=37,x=.4,y=.5})
local south=aps:VectorToPoint({map=37,x=.5,y=.6})
local east=aps:VectorToPoint({map=37,x=.6,y=.5})
check(near(north,0) and near(west,math.pi/2) and near(math.abs(south),math.pi) and near(east,-math.pi/2),'four cardinal bearings')
check(aps:VectorToPoint({map=99,x=.5,y=.4})==nil,'different continents do not produce false bearings')
aps:SaveCurrentPosition('Home');aps:SelectClosest()
check(aps:GetActiveWaypoint().title=='Home','closest selection and save-current-position')
aps:UpdateArrow(.1)
check(aps.frame.detail.text=='Arrived','arrival status')
local oldStore=aps:WaypointStore()
aps:ClearNavigation()
check(not aps.frame:IsShown() and #oldStore.points>0,'clear preserves saved waypoints')
aps:WayCommand('50 40 North');aps:UpdateArrow(.1)
check(aps.frame.arrow._apsCell==0,'north sprite')
facing=math.pi/2;aps:UpdateArrow(.016)
check(aps.frame.arrow._apsCell==81,'facing updates every frame')
facing=0
aps:TogglePreview();aps:UpdateArrow(.1)
local named=0
for _,f in ipairs(frames) do if f.name=='BazUIAPSArrow' then named=named+1 end end
check(named==1 and BazUIAPSPreview==nil,'preview reuses single navigation frame')
aps:TrackQuest(7)
check(aps.questTarget.map==37 and aps.displayTarget.title=='Quest 7','native quest destination')
aps:TrackQuest(8)
check(aps.displayTarget.status=='Location unavailable on this map','quest with no coordinates is explicit')
aps:WayCommand('reset all')
aps:PasteWaypoints('/way 30 40 First\n/tway #52 60 70 Second\n/aps way 10 20 Third\n/run error()')
check(#aps:WaypointStore().points==3,'multiline paste only executes supported navigation commands')
aps:WayCommand('reset away')
check(#aps:WaypointStore().points==2,'reset away')
aps:WayCommand('reset not Westfall')
check(#aps:WaypointStore().points==0,'reset not zone')
SlashCmdList.TOMTOM_WAY('25 50 Alias')
check(aps:GetActiveWaypoint().title=='Alias','TomTom alias handler standalone')
check(SLASH_TOMTOM_WAY1=='/way' and SLASH_TOMTOM_PASTE1=='/ttpaste','copied command aliases registered')
dofile('Modules/Drawers/Widgets/QuestTracker/Waypoints.lua')
tracked=7;drawers.QT.OnSuperTrackChanged()
check(aps:GetActiveWaypoint().title=='Alias','background quest event preserves manual coordinates')
aps:WaypointStore().active=nil
aps.navigationMuted=false
drawers.QT.OnSuperTrackChanged()
check(aps.questID==7 and aps.displayTarget.title=='Quest 7','quest tracker dispatch standalone')
aps.navigationEvents.scripts.OnEvent(nil,'QUEST_TURNED_IN',7)
check(aps.questID==nil,'quest completion clears selected quest')
local uid={37,.2,.3,title='Provider target'}
TomTom={SetCrazyArrow=function(self,u) self.uid=u;self:FireMessage('TOMTOM_ARROW_TARGET_CHANGED',u) end,
    FireMessage=function() end,GetVectorToWaypoint=function() return .3,450 end,
    private={GetCrazyArrowTarget=function() return uid,uid.title end}}
TomTomCrazyArrow=CreateFrame()
aps:ScanIntegrations()
check(TomTomCrazyArrow.alpha==0 and not TomTomCrazyArrow.mouse,'native TomTom display suppressed')
aps:ClearNavigation();TomTom:SetCrazyArrow(uid,10,uid.title)
check(aps.displayTarget and aps.displayTarget.title==uid.title,'incoming TomTom target uses APS')
local zframe=CreateFrame()
zframe.waypoint={title='Guide destination'}
function zframe:ShowTraveling() end
function zframe:ShowText() end
function zframe:ShowSpecial() end
ZGV={Pointer={ArrowFrame=zframe,ArrowFrameCtrl=CreateFrame()}}
aps:ScanIntegrations()
zframe:ShowTraveling(.1,1.2,300)
zframe:ShowText('Guide destination',300)
check(zframe.alpha==0 and ZGV.Pointer.ArrowFrameCtrl.alpha==0,'Zygor arrow and controller suppressed')
check(aps.displayTarget.title=='Guide destination','Zygor target forwards to same display')
zframe:ShowSpecial('taxi');zframe:ShowText('Guide destination',300);aps:RefreshNavigation()
check(aps.displayTarget.status=='Take the flight path','special route instructions retained')
aps:WayCommand('50 40 Manual')
zframe:ShowTraveling(.1,.8,200)
zframe:ShowText('Guide destination',200)
check(aps.displayTarget.title=='Manual','explicit waypoint takes precedence over guide')
-- Reproduce the real order: direction with a raw coordinate title, then
-- ShowText with the instruction. No intermediate display may expose raw text.
aps:WaypointStore().active=nil
aps.questTarget=nil
zframe.waypoint={title='Elwynn Forest 49,41'}
zframe:ShowTraveling(.1,1,58)
zframe:ShowText("Turn in 'Grape Manifest'",58)
local stable=true
for i=1,30 do
    zframe:ShowTraveling(.1,1,58)
    if aps.frame.title.text~="Turn in 'Grape Manifest'" then stable=false end
    zframe:ShowText("Turn in 'Grape Manifest'",58)
    aps:UpdateArrow(.06)
    if aps.frame.title.text~="Turn in 'Grape Manifest'" then stable=false end
end
check(stable,'Zygor raw title never replaces the completed instruction between updates')
tracked=7
aps.navigationEvents.scripts.OnEvent(nil,'SUPER_TRACKING_CHANGED')
drawers.QT.OnSuperTrackChanged()
check(aps.displayTarget.source=='zygor','background quest tracking does not displace active guide navigation')
aps:TrackQuest(7)
tracked=8
aps.navigationEvents.scripts.OnEvent(nil,'SUPER_TRACKING_CHANGED')
drawers.QT.OnSuperTrackChanged()
zframe:ShowTraveling(.1,1,58);zframe:ShowText("Turn in 'Grape Manifest'",58)
check(aps.questID==7 and aps.frame.title.text=='Quest 7','explicit quest selection survives guide and supertracking updates')
aps:WayCommand('50 40 Manual')
settings.zygor=false;settings.tomtom=false;aps:ApplySettings()
check(zframe.alpha==1 and TomTomCrazyArrow.alpha==1 and TomTomCrazyArrow.mouse,'provider displays restore when integrations disabled')
settings.tomtom=true;combat=true;aps:ApplySettings()
check(TomTomCrazyArrow.alpha==1,'protected changes deferred during combat')
combat=false;aps:ScanIntegrations()
check(TomTomCrazyArrow.alpha==0,'suppression resumes after combat')
-- Simulate a numeric value marked secret by the engine. It must never
-- reach ETA/distance/heading arithmetic, even though its Lua type is number.
function issecretvalue(value) return value==12345 end
local savedSpeed=GetUnitSpeed
GetUnitSpeed=function() return 12345 end
aps:WayCommand('50 40 Secret speed')
aps:RefreshNavigation()
check(aps.frame.detail.text=='100 yards','secret speed omits ETA while preserving distance')
GetUnitSpeed=savedSpeed
aps:RefreshNavigation()
check(aps.frame.detail.text:find('0:14',1,true)~=nil,'ETA resumes with readable speed')
local providerGetter=aps.GetProviderTarget
aps.GetProviderTarget=function() return {angle=12345,distance=12345,title='Protected provider'} end
aps:WaypointStore().active=nil
aps.questTarget=nil
aps:RefreshNavigation()
check(aps.frame.detail.text=='','secret provider distance is not formatted or compared')
local oldCell=aps.frame.arrow._apsCell
aps:UpdateArrow(.016)
check(aps.frame.arrow._apsCell==oldCell,'secret provider angle preserves previous heading')
aps.GetProviderTarget=providerGetter
aps:WayCommand('50 40 Protected facing')
oldCell=aps.frame.arrow._apsCell
facing=12345
aps:UpdateArrow(.016)
check(aps.frame.arrow._apsCell==oldCell,'secret player facing preserves previous heading')
facing=0
print('APS: '..checks..' behavioral checks passed')
