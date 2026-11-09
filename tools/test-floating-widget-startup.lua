-- Exercise real registry callbacks and host reflows, including late Micro Menu registration.
local checks = 0
local function check(ok, label) assert(ok, label); checks = checks + 1 end
local combat, usingDrawers = false, true
local enabled, floating, assigned = {}, {}, {}
local F = {}
local function Frame()
    return setmetatable({shown=true,scale=1,width=200,height=40,scripts={},points={}}, {__index=F})
end
function F:SetScript(key, fn) self.scripts[key]=fn end
function F:RegisterEvent() end
function F:Hide() self.shown=false end
function F:Show() self.shown=true end
function F:SetShown(value) self.shown=value end
function F:SetParent(parent) self.parent=parent end
function F:SetScale(value) self.scale=value end
function F:GetEffectiveScale() return self.scale end
function F:SetSize(w,h) self.width,self.height=w,h end
function F:GetWidth() return self.width end
function F:SetHeight(value) self.height=value end
function F:SetPoint(...) self.points[#self.points+1]={...} end
function F:ClearAllPoints() self.points={} end
function F:IsProtected() return true end
function F:SetText(value) self.text=value end
function InCombatLockdown() return combat end
UIParent=Frame()
CreateFrame=Frame
C_Timer={After=function() end}
local addon={}
function addon:GetSetting(key) if key=='width' then return 222 end; return nil end
function addon:GetWidgetScale() return 1.2 end
function addon:GetWidgetPosition() return {x=120,y=-200} end
function addon:IsWidgetEnabled(id) return enabled[id]~=false end
function addon:IsWidgetFloating(id) return not usingDrawers or floating[id]==true end
function addon:UsingDrawers() return usingDrawers end
function addon:GetSortedWidgets()
    local list={}
    for _,w in ipairs(BazUI:GetDockableWidgets()) do if assigned[w.id] then list[#list+1]=w end end
    return list
end
function addon:IsWidgetDockedToBottom() return false end
function addon:IsWidgetCollapsed() return false end
BazUI={GetModule=function() return addon end,SetAtlasOrTexture=function() end}
dofile('Core/Widgets.lua')
dofile('Modules/Drawers/WidgetHost.lua')
local host=addon.WidgetHost
host:Initialize(Frame())
local micro={id='bazdrawer_micromenu',frame=Frame(),designWidth=220,designHeight=30,undocks=0}
function micro:OnUndock() self.undocks=self.undocks+1 end
floating[micro.id]=true
BazUI:RegisterDockableWidget(micro)
check(micro._floating and micro.frame.shown,'late Micro Menu registration restores floating state without a toggle')
check(micro.frame.parent==UIParent and #micro.frame.points==1,'unassigned floating menu is parented and anchored')
check(micro.frame.points[1][4]==100 and micro.frame.points[1][5]==-200/1.2,'saved screen position restored with widget scale')
check(micro.undocks==1,'floating lifecycle callback runs on first registration')
local other={id='unassigned_docked',frame=Frame()}
BazUI:RegisterDockableWidget(other)
check(not other.frame.shown and not other._floating,'unassigned nonfloating widget stays hidden')
enabled[micro.id]=false;host:Reflow()
check(not micro.frame.shown and not micro._floating,'disabled floating widget remains hidden')
enabled[micro.id]=true;host:Reflow()
check(micro._floating and micro.frame.shown,'re-enabling outside drawer membership restores floating placement')
micro.frame:ClearAllPoints();micro.frame:Hide();micro._floating=nil
combat=true;host:Reflow()
check(not micro.frame.shown and #micro.frame.points==0 and host:IsWaitingOnCombat(),'login restoration is deferred during combat')
combat=false;host._combatWatcher.scripts.OnEvent()
check(micro.frame.shown and micro._floating and #micro.frame.points==1,'combat end completes floating startup')
assigned[micro.id]=true
local before=micro.undocks;host:Reflow()
check(micro.undocks==before+1,'floating active-drawer member is processed once')
assigned={};usingDrawers=false;host:Reflow()
check(other._floating and other.frame.shown,'without drawers all enabled widgets still float')
usingDrawers=true;enabled[micro.id]=false;enabled[other.id]=false;host:Reflow()
check(not micro.frame.shown and not other.frame.shown,'disabled widgets do not reappear on subsequent reflows')
print('Floating startup: '..checks..' behavioral checks passed')
