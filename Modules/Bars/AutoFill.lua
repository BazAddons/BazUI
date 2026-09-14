-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Bars: a character's abilities on its bars
--
-- Buttons are per character, so a new character would otherwise log in
-- to empty bars. On its first login the spellbook is read and every
-- usable class ability is placed: forms, stances, auras and stealth on
-- the first side bar so they sit together, everything else on the main
-- bar and then the remaining bars. From then on each newly learned
-- spell goes to the first empty slot, as Blizzard's own bars do. Both
-- have switches under Bars > General, and "Fill empty slots" runs the
-- same pass by hand for a character that already has bars.
--
-- Buttons cast by name, so a new rank of a spell already on a bar needs
-- nothing: the existing button casts it.
--
-- The bars only ever hold what the character knows: once the world is
-- entered, and again whenever the spellbook changes (a respec), spell
-- buttons the character doesn't know are cleared.
---------------------------------------------------------------------------

local BazBars = BazUI.Bars
local addon = BazUI:GetModule("Bars")
local AutoFill = {}
addon.AutoFill = AutoFill

-- The General tab is mostly professions, tracking, languages and
-- riding; only these two belong on a bar.
local GENERAL_TAB_SPELLS = { [6603] = true, [5019] = true }   -- Attack, Shoot

local BOOK = _G.BOOKTYPE_SPELL or "spell"
local SPELL_KIND = _G.Enum and _G.Enum.SpellBookItemType and _G.Enum.SpellBookItemType.Spell or 1

local pending = {}   -- spellIDs learned in combat, placed when it ends
local prunePending = false
local pruneQueued  = false

---------------------------------------------------------------------------
-- Reading the spellbook
---------------------------------------------------------------------------

local function SpellName(spellID)
    local info = C_Spell.GetSpellInfo(spellID)
    return info and info.name
end

local function IsKnown(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
        return C_SpellBook.IsSpellKnownOrInSpellBook(spellID)
    end
    return IsSpellKnown(spellID)
end

local function IsPassive(spellID)
    if C_Spell.IsSpellPassive then return C_Spell.IsSpellPassive(spellID) end
    if _G.IsPassiveSpell then return _G.IsPassiveSpell(spellID) end
    return false
end

-- Forms, stances, auras and stealth in Blizzard's order. Returns the list
-- and a set for quick membership.
local function FormSpells()
    local list, isForm = {}, {}
    for i = 1, (GetNumShapeshiftForms() or 0) do
        local _, _, _, spellID = GetShapeshiftFormInfo(i)
        if spellID and not isForm[spellID] then
            isForm[spellID] = true
            list[#list + 1] = spellID
        end
    end
    return list, isForm
end

-- Every learned, active spell in the class tabs (plus Attack and Shoot
-- from General), in spellbook order.
local function BookSpells()
    local list, seen = {}, {}
    for tab = 1, (GetNumSpellTabs() or 0) do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        for i = (offset or 0) + 1, (offset or 0) + (numSpells or 0) do
            local kind, id = GetSpellBookItemInfo(i, BOOK)
            local isSpell = kind == "SPELL" or kind == SPELL_KIND
            if isSpell and id and not seen[id] and (tab > 1 or GENERAL_TAB_SPELLS[id]) and not IsPassive(id) then
                seen[id] = true
                list[#list + 1] = id
            end
        end
    end
    return list, seen
end

---------------------------------------------------------------------------
-- Bars and slots
---------------------------------------------------------------------------

-- Names already on any bar, so nothing is placed twice.
local function PlacedNames()
    local names = {}
    for _, frame in pairs(addon.Bar:GetAll()) do
        for _, row in pairs(frame.buttons or {}) do
            for _, btn in pairs(row) do
                local a = btn.action
                if a and a.type == "spell" and a.data and a.data.id then
                    local n = SpellName(a.data.id)
                    if n then names[n] = true end
                end
            end
        end
    end
    return names
end

-- The main bar is the largest; the others follow in id order.
local function SortedBars()
    local list = {}
    for id, frame in pairs(addon.Bar:GetAll()) do
        local bd = frame.barData or {}
        list[#list + 1] = { id = id, frame = frame, size = (bd.rows or 1) * (bd.cols or 1) }
    end
    if #list == 0 then return nil, {} end
    table.sort(list, function(a, b) return a.id < b.id end)
    local mainIdx = 1
    for i, e in ipairs(list) do
        if e.size > list[mainIdx].size then mainIdx = i end
    end
    local main = table.remove(list, mainIdx)
    return main, list
end

-- Empty buttons of a bar in reading order.
local function EmptySlots(frame, into)
    local slots = into or {}
    local bd = frame.barData or {}
    for r = 1, bd.rows or 1 do
        for c = 1, bd.cols or 1 do
            local btn = frame.buttons and frame.buttons[r] and frame.buttons[r][c]
            if btn and not btn.action then slots[#slots + 1] = btn end
        end
    end
    return slots
end

local function Place(btn, spellID)
    local handler = BazBars.Actions:Get("spell")
    if not handler then return false end
    addon.Button:SetActionFromHandler(btn, handler, { id = spellID })
    return true
end

-- Places the given spells (forms first onto the first side bar, the rest
-- onto the main bar then the side bars), skipping names already on a
-- bar. Returns how many were placed.
local function PlaceSpells(spellIDs)
    if InCombatLockdown() then return 0 end
    local main, sides = SortedBars()
    if not main then return 0 end
    local placed = PlacedNames()
    local _, isForm = FormSpells()
    local count = 0

    local function Take(queue, spellID)
        local name = SpellName(spellID)
        if not name or placed[name] then return true end
        local btn = table.remove(queue, 1)
        if not btn then return false end
        if Place(btn, spellID) then
            placed[name] = true
            count = count + 1
        end
        return true
    end

    local formQueue = EmptySlots(sides[1] and sides[1].frame or main.frame)
    local leftover = {}
    for _, id in ipairs(spellIDs) do
        if isForm[id] and not Take(formQueue, id) then leftover[#leftover + 1] = id end
    end

    local rest = EmptySlots(main.frame)
    for _, side in ipairs(sides) do EmptySlots(side.frame, rest) end
    for _, id in ipairs(leftover) do Take(rest, id) end
    for _, id in ipairs(spellIDs) do
        if not isForm[id] then Take(rest, id) end
    end
    return count
end

---------------------------------------------------------------------------
-- Passes
---------------------------------------------------------------------------

-- Clears spell buttons the character doesn't know. Skipped while the
-- spellbook is empty (a loading screen) or if it would clear every
-- spell on the bars, which means the book isn't readable yet rather
-- than that the character knows nothing.
function AutoFill:PruneUnknown()
    if InCombatLockdown() then
        prunePending = true
        return 0
    end
    prunePending = false
    if (GetNumSpellTabs() or 0) == 0 then return 0 end

    local stale, total = {}, 0
    for _, frame in pairs(addon.Bar:GetAll()) do
        for _, row in pairs(frame.buttons or {}) do
            for _, btn in pairs(row) do
                local a = btn.action
                if a and a.type == "spell" and a.data and a.data.id then
                    total = total + 1
                    if not IsKnown(a.data.id) then stale[#stale + 1] = btn end
                end
            end
        end
    end
    if #stale == 0 or (#stale == total and total > 1) then return 0 end
    for _, btn in ipairs(stale) do addon.Button:ClearAction(btn) end
    return #stale
end

function AutoFill:QueuePrune()
    if pruneQueued then return end
    pruneQueued = true
    C_Timer.After(0.5, function()
        pruneQueued = false
        AutoFill:PruneUnknown()
    end)
end

function AutoFill:PruneIfPending()
    if prunePending then self:PruneUnknown() end
end

-- First time in the world this session: clear what isn't known, then
-- fill a new character's bars.
function AutoFill:OnWorldEntered()
    local cleared = self:PruneUnknown()
    if cleared > 0 then
        addon:Print(("Removed %d abilities this character doesn't know from the bars."):format(cleared))
    end
    self:OnFirstLogin()
end

-- Every unplaced ability into the empty slots. Used by the first login
-- and by the button on the General page.
function AutoFill:Fill()
    local forms, isForm = FormSpells()
    local book = BookSpells()
    local list = {}
    for _, id in ipairs(forms) do list[#list + 1] = id end
    for _, id in ipairs(book) do
        if not isForm[id] then list[#list + 1] = id end
    end
    return PlaceSpells(list)
end

-- First login of a character that has nothing on any bar yet.
function AutoFill:OnFirstLogin()
    if addon.db.profile.autoFill == false then return end
    local state = addon:GetCharBarState(true)
    if not state or state.filled then return end
    if addon:HasAnyButtons() then
        state.filled = true
        return
    end
    if InCombatLockdown() then return end   -- try again next login
    local n = self:Fill()
    state.filled = true
    if n > 0 then
        addon:Print(("Your %d abilities are on the bars. Move them as you like; new spells will take the first empty slot."):format(n))
    end
end

-- A newly learned spell. Ranks of something already placed are skipped
-- by name inside PlaceSpells.
function AutoFill:OnLearned(spellID)
    if addon.db.profile.autoPlaceNew == false then return end
    if type(spellID) ~= "number" or IsPassive(spellID) then return end
    local _, inBook = BookSpells()
    local _, isForm = FormSpells()
    if not inBook[spellID] and not isForm[spellID] then return end
    if InCombatLockdown() then
        pending[spellID] = true
        return
    end
    PlaceSpells({ spellID })
end

function AutoFill:PlacePending()
    if InCombatLockdown() or not next(pending) then return end
    local list = {}
    for id in pairs(pending) do list[#list + 1] = id end
    table.sort(list)
    wipe(pending)
    PlaceSpells(list)
end
