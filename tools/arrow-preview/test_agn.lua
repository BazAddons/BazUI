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
local agn={}
function agn:GetSetting(k) return settings[k] end
function agn:SetSetting(k,v) settings[k]=v end
function agn:Print(t) logs[#logs+1]=t end
function agn:OnProfileChanged(fn) self.profileChanged=fn end
local drawers={QT={C={WIDGET_ID='QuestTracker'}}}
function drawers:GetWidgetSetting(_,_,default) return default end
BazUI={Skin={Theme={FontString=function() return CreateFrame() end}}}
function BazUI:RegisterModule(_,defs) self.defs=defs;settings=defs.defaults;return agn end
function BazUI:GetModule(name) if name=='AGN' then return agn elseif name=='Drawers' then return drawers end end
function BazUI:IsModuleEnabled() return true end
function BazUI:OpenCopyDialog(opts) self.copyOpts=opts end
local root='Modules/AGN/'
for _,name in ipairs({'Core','Arrow','Navigation','Commands','Integrations'}) do dofile(root..name..'.lua') end
check(TomTom==nil and ZGV==nil,'standalone has no providers')
BazUI.defs.onReady(agn)
check(agn.navigationReady and not agn.frame:IsShown(),'standalone initializes without providers')
local p=agn:WayCommand('42.1 65.9 Test destination')
check(p and near(p.x,.421) and p.title=='Test destination','current-zone coordinates')
check(agn.frame:IsShown(),'standalone arrow visible')
check(not agn.frame.mouse and not agn.frame.scripts.OnMouseUp,'normal display is click-through without click actions')
shift=true;agn.frame.scripts.OnEvent(agn.frame,'MODIFIER_STATE_CHANGED')
check(agn.frame.mouse,'holding Shift enables dragging')
agn.frame.scripts.OnDragStart(agn.frame)
check(agn.frame._agnDragging,'Shift-drag starts movement')
shift=false;agn.frame.scripts.OnEvent(agn.frame,'MODIFIER_STATE_CHANGED')
check(not agn.frame.mouse and not agn.frame._agnDragging,'releasing Shift ends drag and restores click-through')
agn.frame.scripts.OnDragStart(agn.frame)
check(not agn.frame._agnDragging,'ordinary drag cannot start movement')
p=agn:WayCommand('/way Elwynn Forest 42.1 65.9 Wowhead destination')
check(p and p.map==37 and p.title=='Wowhead destination','copied named-zone command')
p=agn:WayCommand('#52 12,5 90,25 Decimal comma')
check(p and near(p.x,.125) and near(p.y,.9025),'decimal comma with literal map ID')
p=agn:WayCommand('12.5, 90.25 Trailing comma')
check(p and near(p.y,.9025),'coordinate separator comma')
check(agn:ResolveMap('West')==52,'partial zone match')
check(agn:ResolveMap('unknown')==nil,'invalid zone rejected')
local count=#agn:WaypointStore().points
agn:WayCommand('101 40');agn:WayCommand('-1 40');agn:WayCommand('42 nope')
check(#agn:WaypointStore().points==count,'invalid coordinates do not create targets')
local north=agn:VectorToPoint({map=37,x=.5,y=.4})
local west=agn:VectorToPoint({map=37,x=.4,y=.5})
local south=agn:VectorToPoint({map=37,x=.5,y=.6})
local east=agn:VectorToPoint({map=37,x=.6,y=.5})
check(near(north,0) and near(west,math.pi/2) and near(math.abs(south),math.pi) and near(east,-math.pi/2),'four cardinal bearings')
check(agn:VectorToPoint({map=99,x=.5,y=.4})==nil,'different continents do not produce false bearings')
agn:SaveCurrentPosition('Home');agn:SelectClosest()
check(agn:GetActiveWaypoint().title=='Home','closest selection and save-current-position')
agn:UpdateArrow(.1)
check(agn.frame.detail.text=='Arrived','arrival status')
local oldStore=agn:WaypointStore()
agn:ClearNavigation()
check(not agn.frame:IsShown() and #oldStore.points>0,'clear preserves saved waypoints')
agn:WayCommand('50 40 North');agn:UpdateArrow(.1)
check(agn.frame.arrow._agnCell==0,'north sprite')
facing=math.pi/2;agn:UpdateArrow(.016)
check(agn.frame.arrow._agnCell==81,'facing updates every frame')
facing=0
agn:TogglePreview();agn:UpdateArrow(.1)
local named=0
for _,f in ipairs(frames) do if f.name=='BazUIAGNArrow' then named=named+1 end end
check(named==1 and BazUIAGNPreview==nil,'preview reuses single navigation frame')
agn:TrackQuest(7)
check(agn.questTarget.map==37 and agn.displayTarget.title=='Quest 7','native quest destination')
agn:TrackQuest(8)
check(agn.displayTarget.status=='Location unavailable on this map','quest with no coordinates is explicit')
agn:WayCommand('reset all')
agn:PasteWaypoints('/way 30 40 First\n/tway #52 60 70 Second\n/agn way 10 20 Third\n/run error()')
check(#agn:WaypointStore().points==3,'multiline paste only executes supported navigation commands')
agn:WayCommand('reset away')
check(#agn:WaypointStore().points==2,'reset away')
agn:WayCommand('reset not Westfall')
check(#agn:WaypointStore().points==0,'reset not zone')
SlashCmdList.TOMTOM_WAY('25 50 Alias')
check(agn:GetActiveWaypoint().title=='Alias','TomTom alias handler standalone')
check(SLASH_TOMTOM_WAY1=='/way' and SLASH_TOMTOM_PASTE1=='/ttpaste','copied command aliases registered')
dofile('Modules/Drawers/Widgets/QuestTracker/Waypoints.lua')
tracked=7;drawers.QT.OnSuperTrackChanged()
check(agn:GetActiveWaypoint().title=='Alias','background quest event preserves manual coordinates')
agn:WaypointStore().active=nil
agn.navigationMuted=false
drawers.QT.OnSuperTrackChanged()
check(agn.questID==7 and agn.displayTarget.title=='Quest 7','quest tracker dispatch standalone')
agn.navigationEvents.scripts.OnEvent(nil,'QUEST_TURNED_IN',7)
check(agn.questID==nil,'quest completion clears selected quest')
local uid={37,.2,.3,title='Provider target'}
TomTom={SetCrazyArrow=function(self,u) self.uid=u;self:FireMessage('TOMTOM_ARROW_TARGET_CHANGED',u) end,
    FireMessage=function() end,GetVectorToWaypoint=function() return .3,450 end,
    private={GetCrazyArrowTarget=function() return uid,uid.title end}}
TomTomCrazyArrow=CreateFrame()
agn:ScanIntegrations()
check(TomTomCrazyArrow.alpha==0 and not TomTomCrazyArrow.mouse,'native TomTom display suppressed')
agn:ClearNavigation();TomTom:SetCrazyArrow(uid,10,uid.title)
check(agn.displayTarget and agn.displayTarget.title==uid.title,'incoming TomTom target uses AGN')
local zframe=CreateFrame()
zframe.waypoint={title='Guide destination'}
function zframe:ShowTraveling() end
function zframe:ShowText() end
function zframe:ShowSpecial() end
ZGV={Pointer={ArrowFrame=zframe,ArrowFrameCtrl=CreateFrame()}}
agn:ScanIntegrations()
zframe:ShowTraveling(.1,1.2,300)
zframe:ShowText('Guide destination',300)
check(zframe.alpha==0 and ZGV.Pointer.ArrowFrameCtrl.alpha==0,'Zygor arrow and controller suppressed')
check(agn.displayTarget.title=='Guide destination','Zygor target forwards to same display')
zframe:ShowSpecial('taxi');zframe:ShowText('Guide destination',300);agn:RefreshNavigation()
check(agn.displayTarget.status=='Take the flight path','special route instructions retained')
agn:WayCommand('50 40 Manual')
zframe:ShowTraveling(.1,.8,200)
zframe:ShowText('Guide destination',200)
check(agn.displayTarget.title=='Manual','explicit waypoint takes precedence over guide')
-- Reproduce the real order: direction with a raw coordinate title, then
-- ShowText with the instruction. No intermediate display may expose raw text.
agn:WaypointStore().active=nil
agn.questTarget=nil
zframe.waypoint={title='Elwynn Forest 49,41'}
zframe:ShowTraveling(.1,1,58)
zframe:ShowText("Turn in 'Grape Manifest'",58)
local stable=true
for i=1,30 do
    zframe:ShowTraveling(.1,1,58)
    if agn.frame.title.text~="Turn in 'Grape Manifest'" then stable=false end
    zframe:ShowText("Turn in 'Grape Manifest'",58)
    agn:UpdateArrow(.06)
    if agn.frame.title.text~="Turn in 'Grape Manifest'" then stable=false end
end
check(stable,'Zygor raw title never replaces the completed instruction between updates')
tracked=7
agn.navigationEvents.scripts.OnEvent(nil,'SUPER_TRACKING_CHANGED')
drawers.QT.OnSuperTrackChanged()
check(agn.displayTarget.source=='zygor','background quest tracking does not displace active guide navigation')
agn:TrackQuest(7)
tracked=8
agn.navigationEvents.scripts.OnEvent(nil,'SUPER_TRACKING_CHANGED')
drawers.QT.OnSuperTrackChanged()
zframe:ShowTraveling(.1,1,58);zframe:ShowText("Turn in 'Grape Manifest'",58)
check(agn.questID==7 and agn.frame.title.text=='Quest 7','explicit quest selection survives guide and supertracking updates')
agn:WayCommand('50 40 Manual')
settings.zygor=false;settings.tomtom=false;agn:ApplySettings()
check(zframe.alpha==1 and TomTomCrazyArrow.alpha==1 and TomTomCrazyArrow.mouse,'provider displays restore when integrations disabled')
settings.tomtom=true;combat=true;agn:ApplySettings()
check(TomTomCrazyArrow.alpha==1,'protected changes deferred during combat')
combat=false;agn:ScanIntegrations()
check(TomTomCrazyArrow.alpha==0,'suppression resumes after combat')
-- Simulate a numeric value marked secret by the engine. It must never
-- reach ETA/distance/heading arithmetic, even though its Lua type is number.
function issecretvalue(value) return value==12345 end
local savedSpeed=GetUnitSpeed
GetUnitSpeed=function() return 12345 end
agn:WayCommand('50 40 Secret speed')
agn:RefreshNavigation()
check(agn.frame.detail.text=='100 yards','secret speed omits ETA while preserving distance')
GetUnitSpeed=savedSpeed
agn:RefreshNavigation()
check(agn.frame.detail.text:find('0:14',1,true)~=nil,'ETA resumes with readable speed')
local providerGetter=agn.GetProviderTarget
agn.GetProviderTarget=function() return {angle=12345,distance=12345,title='Protected provider'} end
agn:WaypointStore().active=nil
agn.questTarget=nil
agn:RefreshNavigation()
check(agn.frame.detail.text=='','secret provider distance is not formatted or compared')
local oldCell=agn.frame.arrow._agnCell
agn:UpdateArrow(.016)
check(agn.frame.arrow._agnCell==oldCell,'secret provider angle preserves previous heading')
agn.GetProviderTarget=providerGetter
agn:WayCommand('50 40 Protected facing')
oldCell=agn.frame.arrow._agnCell
facing=12345
agn:UpdateArrow(.016)
check(agn.frame.arrow._agnCell==oldCell,'secret player facing preserves previous heading')
facing=0
print('AGN: '..checks..' behavioral checks passed')
