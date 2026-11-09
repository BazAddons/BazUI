-- Lua 5.1 regression checks for the Today/Instances availability mismatch.
local checks = 0
local function check(value, label) assert(value, label); checks = checks + 1 end
local level, saved = 4, nil
local queued, blocks = {}, {}
local C = { sections = {}, STATE_COLOR = { done = {} }, Gates = {} }
function C.Gates.Same(a, b) return string.lower(a) == string.lower(b) end
function C:RegisterSection(section) self.sections[section.id] = section end
function C:SyncGroupSections(_, _, value) blocks = value end
BazUI = { Codex = C, Skin = { Theme = { colors = {} } } }
function BazUI:FormatSpan() return '1h' end
function BazUI:QueueForModule(_, fn) queued[#queued + 1] = fn end
UnitLevel = function() return level end
GetNumSavedInstances = function() return saved and 1 or 0 end
GetSavedInstanceInfo = function() return saved, nil, 3600, nil, true end
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
C.Access = { entries = {}, IsRejected = function() return false end }
function C.Access.All() return {} end
function C.Access.Evaluate(entry)
    return { complete = entry.complete, underLevelled = level < entry.level,
        done = entry.complete and #entry.steps or 0, missing = {} }
end
dofile('Modules/Codex/Data/Instances.lua')
dofile('Modules/Codex/Sources/Access.lua')
dofile('Modules/Codex/Sources/Instances.lua')
local function sync() for _, fn in ipairs(queued) do fn() end end
local function count(expected, label)
    sync()
    local today = C.sections.open.GetHighlight().value
    local instances = blocks[1].GetHighlight().value
    check(today == expected and instances == expected, label .. ': both page counts')
    check(#C.sections.open.GetRows() == expected, label .. ': Today rows match count')
end
count(0, 'real catalog at level 4 does not count unknown-level dungeons')
local unknown = 0
for _, block in ipairs(blocks) do
    for _, row in ipairs(block.GetRows()) do
        if row.detail == 'level unknown' then unknown = unknown + 1 end
    end
end
check(unknown == 2, 'both missing-level dungeons explain their unknown requirements')
C.Instances.entries = {
    {name = 'Ordinary dungeon', kind = 'dungeon', level = 13},
    {name = 'Unknown dungeon', kind = 'dungeon'},
    {name = 'Gated raid', kind = 'raid', level = 60},
    {name = 'Gate level fallback', kind = 'raid'},
}
local gate = { name = 'Gated raid', level = 60, steps = {{label = 'Key'}}, complete = false }
local fallback = { name = 'Gate level fallback', level = 60, steps = {}, complete = true }
C.Access.entries = { gate, fallback }
level = 13
count(1, 'ordinary dungeon appears without an attunement catalog entry')
check(C.sections.open.GetRows()[1].label == 'Ordinary dungeon', 'Today lists the available ordinary dungeon')
saved = 'Ordinary dungeon'
count(0, 'saved dungeon is excluded on both pages')
saved = nil; level = 19
count(0, 'outgrown dungeon is excluded consistently')
level = 58; gate.complete = true
count(0, 'completed attunement still respects its minimum level')
level = 60; gate.complete = false
count(1, 'known gate level fills a missing catalog level; unfinished attunement stays blocked')
gate.complete = true
count(2, 'completed level-appropriate gates count on both pages')
saved = 'Gated raid'
count(1, 'raid lockout is excluded consistently')
print('Codex instance access: ' .. checks .. ' checks passed')
