-- Lua 5.1 checks for timer bounds and styling before engine ownership.
local checks = 0
local function check(ok, label) assert(ok, label); checks = checks + 1 end
local Auras = {}
local addon = {}
BazUI = { Auras = Auras, Skin = { Theme = { FontFile = function() return 'Font.ttf' end } },
    GetModule = function() return addon end }
local file = assert(io.open('Modules/Auras/Frames.lua'))
local source = file:read('*a'); file:close()
local start = assert(source:find('function Auras.ApplyDurationStyle', 1, true))
local finish = assert(source:find('function Auras.ApplyButtonSize', start, true))
local env = setmetatable({ Auras = Auras }, { __index = _G })
setfenv(assert(loadstring(source:sub(start, finish - 1))), env)()
local function Button()
    local t = { points = {} }
    local function Accessible() assert(not t.owned, 'styled after engine ownership') end
    function t:SetFont(file, size) Accessible(); self.font, self.fontSize = file, size end
    function t:ClearAllPoints() Accessible(); self.points = {} end
    function t:SetPoint(...) Accessible(); self.points[#self.points+1] = {...} end
    function t:SetJustifyH(value) Accessible(); self.justify = value end
    function t:SetWordWrap(value) Accessible(); self.wrap = value end
    function t:SetNonSpaceWrap(value) Accessible(); self.nonspace = value end
    function t:SetMaxLines(value) Accessible(); self.lines = value end
    function t:GetText() error('protected timer text must never be read') end
    local b = { Duration = t, Icon = {} }
    function b:SetSize() end
    function b:SetIcon() end
    function b:SetDurationText(region) region.owned = true end
    return b
end
for _, size in ipairs({ 8, 12, 16, 26, 32, 48 }) do
    local b = Button()
    Auras.ApplyDurationStyle(b, size, 24)
    check(b.Duration.fontSize <= math.max(6, math.floor((size - 4)/2.5)), 'large font capped for icon width')
    check(b.Duration.wrap == false and b.Duration.nonspace == false and b.Duration.lines == 1, 'single-line timer stays bounded')
    check(b.Duration.points[1][4] == 2 and b.Duration.points[2][4] == -2, 'timer inset inside both icon edges')
end
local combat = false
function InCombatLockdown() return combat end
function CreateFrame()
    local c = {}
    for _,name in ipairs({'Hide','Show','ClearAllPoints','SetPoint','SetSize','SetUnit','SetFlowLayoutMaximumLineSize','SetEnabled'}) do c[name] = function() end end
    function c:AddAuraGroup(_,_,cfg)
        self.button = Button()
        cfg.initializeFrame(self.button)
    end
    return c
end
dofile('Modules/Auras/Container.lua')
local cfg = {size=26,across=4,rows=1,unit='player',filter='HELPFUL',showDuration=true,
    showCount=false,durationSize=24,fontFile='Font.ttf'}
local def, parent = {id='test'}, {}
local first = Auras.Container.Ensure(def,cfg,parent)
check(first and first.button.Duration.owned and first.button.Duration.fontSize == 8, 'live engine timer styled before being handed over')
check(Auras.Container.Ensure(def,cfg,parent) == first, 'unchanged timer settings reuse the container')
cfg.durationSize = 7
local second = Auras.Container.Ensure(def,cfg,parent)
check(second ~= first and second.button.Duration.fontSize == 7, 'timer font change rebuilds engine container')
cfg.fontFile='Other.ttf'
local third = Auras.Container.Ensure(def,cfg,parent)
check(third ~= second and third.button.Duration.font == 'Other.ttf', 'font face change rebuilds engine container')
combat=true;cfg.durationSize=10
check(Auras.Container.Ensure(def,cfg,parent) == third, 'combat never restyles forbidden live buttons')
combat=false;cfg.showDuration=false
local hidden = Auras.Container.Ensure(def,cfg,parent)
check(not hidden.button.Duration.owned, 'disabled row timer is not handed to the engine')
print('Aura timers: '..checks..' layout checks passed')
