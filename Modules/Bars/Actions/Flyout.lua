-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Bars: Flyout action handler
--
-- A flyout slot is one button that holds several actions:
--   Left-click   casts the slot's current action.
--   Right-click  opens a popup grid holding all of them.
--
-- Cells are whole BazUI actions, not just spells, so anything the bar
-- understands can live in a flyout: spells, items, macros, mounts,
-- equipment sets. The registry does the work; a flyout is a slot that
-- points at other slots.
--
-- Which action is "current":
--   mode "lastUsed"  the cell you cast most recently from the popup.
--   mode "specific"  a cell you pinned, set by right-clicking it.
-- Either way, an unknown or missing preference falls through to the
-- first usable cell, and a flyout with nothing usable left reports
-- itself empty so the slot clears rather than showing a dead icon.
--
-- Blizzard's own spellbook flyouts (Mage teleports and the like) are a
-- second possible source, where the cells come from the client and stay
-- current as you learn ranks. That API does not exist on Classic Era,
-- so the branch is guarded and dark here; it costs nothing and is ready
-- if Forever ships flyouts.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("Bars")
local Actions = addon.Actions

local Flyout = { type = "flyout", priority = 30 }
addon.FlyoutHandler = Flyout

local DEFAULT_COLS = 3
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

---------------------------------------------------------------------------
-- Native flyouts (absent on Era; guarded for later clients)
---------------------------------------------------------------------------

local function HasNativeFlyoutAPI()
    return (C_SpellBook and C_SpellBook.GetFlyoutInfo) or GetFlyoutInfo
end

local function FlyoutNumSlots(flyoutID)
    if C_SpellBook and C_SpellBook.GetFlyoutInfo then
        local info = C_SpellBook.GetFlyoutInfo(flyoutID)
        if info and info.numSlots then return info.numSlots end
    end
    if GetFlyoutInfo then
        local _, _, numSlots = GetFlyoutInfo(flyoutID)
        return numSlots
    end
end

local function FlyoutSlot(flyoutID, slotIndex)
    if C_SpellBook and C_SpellBook.GetFlyoutSlotInfo then
        local info = C_SpellBook.GetFlyoutSlotInfo(flyoutID, slotIndex)
        if info and info.spellID then
            return info.spellID, info.isKnown ~= false
        end
    end
    if GetFlyoutSlotInfo then
        local spellID, _, isKnown = GetFlyoutSlotInfo(flyoutID, slotIndex)
        if spellID then return spellID, isKnown ~= false end
    end
end

local function FlyoutName(flyoutID)
    if C_SpellBook and C_SpellBook.GetFlyoutInfo then
        local info = C_SpellBook.GetFlyoutInfo(flyoutID)
        if info then return info.name end
    end
    if GetFlyoutInfo then return (GetFlyoutInfo(flyoutID)) end
end

---------------------------------------------------------------------------
-- Cells
--
-- Cells are sparse on purpose: dropping onto the fifth square of a grid
-- puts the action at index 5 and leaves 1 to 4 empty, because the grid
-- the user arranged is the grid they meant. Every walk over cells has to
-- respect that, which means counting with a loop to the highest index
-- rather than with the length operator, and saving with pairs rather
-- than ipairs. Getting this wrong silently eats every cell past the
-- first gap.
---------------------------------------------------------------------------

local function SpellIsKnown(spellID)
    if not spellID then return false end
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
        if C_SpellBook.IsSpellKnownOrInSpellBook(spellID) then return true end
    end
    if IsSpellKnown and IsSpellKnown(spellID) then return true end
    if C_Spell and C_Spell.GetSpellInfo then
        return C_Spell.GetSpellInfo(spellID) ~= nil
    end
    return false
end

local function MaxCellIndex(cells)
    local maximum = 0
    for k in pairs(cells or {}) do
        if type(k) == "number" and k > maximum then maximum = k end
    end
    return maximum
end

local function CountCells(cells)
    local n = 0
    for k, v in pairs(cells or {}) do
        if type(k) == "number" and v then n = n + 1 end
    end
    return n
end

local function ResolveCells(data)
    if not data then return {} end

    if data.flyoutID and HasNativeFlyoutAPI() then
        local out = {}
        local numSlots = FlyoutNumSlots(data.flyoutID)
        if not numSlots then return out end
        for i = 1, numSlots do
            local spellID, isKnown = FlyoutSlot(data.flyoutID, i)
            if spellID then
                out[#out + 1] = {
                    type = "spell", data = { id = spellID }, isKnown = isKnown,
                }
            end
        end
        return out
    end

    local out = {}
    for k, c in pairs(data.cells or {}) do
        if type(k) == "number" and c and c.type and c.data then
            local cell = { type = c.type, data = c.data }
            if c.type == "spell" and c.data.id then
                cell.isKnown = SpellIsKnown(c.data.id)
            else
                cell.isKnown = true
            end
            out[k] = cell
        end
    end
    return out
end

-- The action the slot casts on a left-click: the preferred cell when it
-- is there and usable, otherwise the first cell that is.
local function GetCurrentAction(data)
    local cells = ResolveCells(data)
    local maximum = MaxCellIndex(cells)
    if maximum == 0 then return nil end

    local prefer = (data.mode == "specific") and data.pinnedIndex or data.currentIndex
    local cell = prefer and cells[prefer]
    if cell and cell.isKnown then
        return { type = cell.type, data = cell.data }
    end

    for i = 1, maximum do
        local c = cells[i]
        if c and c.isKnown then
            return { type = c.type, data = c.data }
        end
    end
    return nil
end

Flyout.ResolveCells    = ResolveCells
Flyout.GetCurrentAction = GetCurrentAction
Flyout.MaxCellIndex    = MaxCellIndex
Flyout.CountCells      = CountCells

function Flyout.MakeDefault(shape)
    shape = shape or {}
    return {
        cells          = {},
        direction      = shape.direction or "UP",
        rows           = shape.rows or 1,
        cols           = shape.cols or DEFAULT_COLS,
        mode           = shape.mode or "lastUsed",
        persistCurrent = shape.persistCurrent ~= false,
    }
end

---------------------------------------------------------------------------
-- Carrying a flyout on the cursor
--
-- The game's cursor cannot hold one of ours, so moving a flyout from one
-- slot to another is carried here and drawn by a small frame that
-- follows the pointer. Anything still carried when a mouse button comes
-- up anywhere has been dropped on nothing, and is discarded; without
-- that, an abandoned flyout would land on the next slot clicked.
---------------------------------------------------------------------------

local pending
local ignoreNextCursorChange = false
local follower

local function Follower()
    if follower then return follower end
    follower = CreateFrame("Frame", nil, UIParent)
    follower:SetFrameStrata("TOOLTIP")
    follower:SetSize(36, 36)
    follower:Hide()
    follower.icon = follower:CreateTexture(nil, "ARTWORK")
    follower.icon:SetAllPoints()
    follower.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    follower:SetScript("OnUpdate", function(self)
        local scale = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + 18, y / scale - 18)
    end)
    return follower
end

local function HideFollower()
    if follower then follower:Hide() end
end

function Flyout.HasPending()
    return pending ~= nil
end

function Flyout.ClearPending()
    pending = nil
    HideFollower()
end

function Flyout.fromCursor()
    local cursorType, flyoutID = GetCursorInfo()

    -- A Blizzard spellbook flyout dragged onto the bar. Era's cursor
    -- never reports this, since the client has no flyouts to drag.
    if cursorType == "flyout" and flyoutID and HasNativeFlyoutAPI() then
        local cols = FlyoutNumSlots(flyoutID) or DEFAULT_COLS
        return {
            flyoutID = flyoutID, direction = "UP", rows = 1,
            cols = math.max(1, cols), mode = "lastUsed", persistCurrent = true,
        }
    end

    if pending then
        -- The player picked up something else mid-carry; let the real
        -- handler have the drop rather than pasting a stale flyout.
        if cursorType then
            Flyout.ClearPending()
            return nil
        end
        local data = pending
        Flyout.ClearPending()
        return data
    end
end

function Flyout.pickup(data)
    -- Our own clear will raise CURSOR_CHANGED; the watcher below must not
    -- read that as the player abandoning the carry we are about to start.
    ignoreNextCursorChange = true
    ClearCursor()
    if not data then return end
    pending = data
    local f = Follower()
    f.icon:SetTexture(Flyout.getIcon(data) or FALLBACK_ICON)
    f:Show()
end

BazUI:QueueForModule("Bars", function()
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("GLOBAL_MOUSE_UP")
    -- CURSOR_CHANGED rather than a hook on ClearCursor: hooking a global
    -- marks it tainted for every Blizzard call that reads it afterwards,
    -- and ClearCursor is read from 34 of their files.
    watcher:RegisterEvent("CURSOR_CHANGED")
    watcher:SetScript("OnEvent", function(_, event)
        if event == "CURSOR_CHANGED" then
            if ignoreNextCursorChange then
                ignoreNextCursorChange = false
                return
            end
            -- The cursor moved on without us - either the player picked
            -- something else up or dropped what they had.
            if pending then Flyout.ClearPending() end
            return
        end
        -- Frame-level drop handlers run before GLOBAL_MOUSE_UP fires, so
        -- anything still here was released over nothing.
        if pending then Flyout.ClearPending() end
    end)
end)

---------------------------------------------------------------------------
-- The slot
---------------------------------------------------------------------------

function Flyout.apply(button, data)
    local current = GetCurrentAction(data)
    if current then
        -- The current cell's own handler sets the cast attributes, so a
        -- flyout left-click behaves exactly like that action on a plain
        -- slot. Self-cast is off: right-click belongs to the popup.
        Actions:Apply(button, current, false)
    else
        Actions:ClearButtonAttributes(button)
    end

    if addon.FlyoutPopup then
        addon.FlyoutPopup:AttachTo(button, data)
    end
end

-- No applySelfCast on purpose: right-click opens the popup.

local function CurrentHandler(data)
    local current = GetCurrentAction(data)
    if not current then return nil end
    return Actions:Get(current.type), current.data
end

function Flyout.getIcon(data)
    local handler, cellData = CurrentHandler(data)
    if handler and handler.getIcon then
        local icon = handler.getIcon(cellData)
        if icon then return icon end
    end
    -- Nothing usable: show the first cell there is, so the slot still
    -- looks like the thing the player built.
    local cells = ResolveCells(data)
    for i = 1, MaxCellIndex(cells) do
        local c = cells[i]
        local h = c and Actions:Get(c.type)
        if h and h.getIcon then
            local icon = h.getIcon(c.data)
            if icon then return icon end
        end
    end
    return FALLBACK_ICON
end

function Flyout.getName(data)
    local handler, cellData = CurrentHandler(data)
    if handler and handler.getName then
        local name = handler.getName(cellData)
        if name then return name end
    end
    if data.flyoutID and HasNativeFlyoutAPI() then
        local name = FlyoutName(data.flyoutID)
        if name then return name end
    end
    return "Flyout"
end

function Flyout.getCount(data)
    local handler, cellData = CurrentHandler(data)
    if handler and handler.getCount then return handler.getCount(cellData) end
    return ""
end

function Flyout.getCooldown(data)
    local handler, cellData = CurrentHandler(data)
    if handler and handler.getCooldown then return handler.getCooldown(cellData) end
end

function Flyout.applyCooldown(data, cooldownFrame)
    local handler, cellData = CurrentHandler(data)
    if handler and handler.applyCooldown then
        return handler.applyCooldown(cellData, cooldownFrame)
    end
    if handler and handler.getCooldown and cooldownFrame then
        local start, duration, enable = handler.getCooldown(cellData)
        if start and duration then
            cooldownFrame:SetCooldown(start, duration, enable)
            return true
        end
    end
    if cooldownFrame and cooldownFrame.Clear then cooldownFrame:Clear() end
    return true
end

function Flyout.isUsable(data)
    local handler, cellData = CurrentHandler(data)
    if handler and handler.isUsable then return handler.isUsable(cellData) end
    return true
end

function Flyout.isInRange(data, unit)
    local handler, cellData = CurrentHandler(data)
    if handler and handler.isInRange then return handler.isInRange(cellData, unit) end
end

function Flyout.hasProcGlow(data)
    local handler, cellData = CurrentHandler(data)
    if handler and handler.hasProcGlow then return handler.hasProcGlow(cellData) end
    return false
end

function Flyout.isCurrent(data)
    local handler, cellData = CurrentHandler(data)
    if handler and handler.isCurrent then return handler.isCurrent(cellData) end
    return false
end

function Flyout.showTooltip(data)
    local handler, cellData = CurrentHandler(data)
    if handler and handler.showTooltip then
        handler.showTooltip(cellData)
    else
        GameTooltip:SetText(Flyout.getName(data))
    end
    local count = CountCells(ResolveCells(data))
    GameTooltip:AddLine(count == 1 and "Flyout, 1 action" or
        ("Flyout, " .. count .. " actions"), 0.6, 0.55, 0.45)
    GameTooltip:AddLine("Right-click to open", 0.6, 0.55, 0.45)
end

---------------------------------------------------------------------------
-- Persistence
--
-- Cells are written with pairs and their indices kept, because they are
-- positions in a grid rather than a list. The obvious ipairs here is a
-- bug: it stops at the first empty square and throws away everything
-- after it.
---------------------------------------------------------------------------

function Flyout.serialize(data)
    if not data then return nil end
    local out = {
        flyoutID       = data.flyoutID,
        direction      = data.direction or "UP",
        rows           = data.rows or 1,
        cols           = data.cols or DEFAULT_COLS,
        mode           = data.mode or "lastUsed",
        pinnedIndex    = data.pinnedIndex,
        persistCurrent = data.persistCurrent ~= false,
    }
    if out.persistCurrent then out.currentIndex = data.currentIndex end

    if data.cells then
        local cells = {}
        for k, c in pairs(data.cells) do
            if type(k) == "number" and c and c.type and c.data then
                local handler = Actions:Get(c.type)
                local cellData = c.data
                if handler and handler.serialize then
                    cellData = handler.serialize(c.data)
                end
                cells[k] = { type = c.type, data = cellData }
            end
        end
        out.cells = cells
    end
    return out
end

function Flyout.deserialize(saved)
    if not saved then return nil end
    if not (saved.flyoutID or saved.cells) then return nil end

    local data = {
        flyoutID       = saved.flyoutID,
        direction      = saved.direction or "UP",
        rows           = saved.rows or 1,
        cols           = saved.cols or DEFAULT_COLS,
        mode           = saved.mode or "lastUsed",
        pinnedIndex    = saved.pinnedIndex,
        currentIndex   = saved.currentIndex,
        persistCurrent = saved.persistCurrent ~= false,
    }

    if saved.cells then
        local cells = {}
        for k, c in pairs(saved.cells) do
            if type(k) == "number" and c and c.type then
                local handler = Actions:Get(c.type)
                local cellData = c.data
                if handler and handler.deserialize then
                    cellData = handler.deserialize(c.data)
                end
                -- A cell whose handler rejects it (a spell that no
                -- longer exists) is dropped; the rest of the flyout
                -- survives, keeping its arrangement.
                if cellData then
                    cells[k] = { type = c.type, data = cellData }
                end
            end
        end
        data.cells = cells
    end

    -- A flyout that had cells and lost every one of them is dead, and
    -- the slot clears rather than keeping a question mark forever. A
    -- flyout that never had any is one the player just made and has not
    -- filled in yet, which must survive a reload. Counting, never the
    -- length operator: these indices have holes.
    if not data.flyoutID then
        local savedCount = CountCells(saved.cells)
        if savedCount > 0 and CountCells(data.cells) == 0 then return nil end
    end
    return data
end

-- Flyouts had no representation in the old bbCommand format, so there
-- is nothing to migrate.

---------------------------------------------------------------------------
-- Mutation, called by the popup
---------------------------------------------------------------------------

local pendingApply = {}

-- Remember which cell was cast, so "last used" means something.
function Flyout:RecordCellClick(button, cellIndex)
    local data = button and button.action and button.action.data
    if not data then return end
    if data.mode ~= "lastUsed" then return end
    if data.currentIndex == cellIndex then return end

    data.currentIndex = cellIndex
    if InCombatLockdown() then
        -- Re-pointing the slot sets secure attributes, so it waits.
        pendingApply[button] = true
        return
    end
    Flyout.apply(button, data)
    addon.Button:UpdateButton(button)
    addon.Button:SaveButton(button)
end

-- Pin a cell as the slot's left-click, or unpin back to last-used.
function Flyout:SetPinnedCell(button, cellIndex)
    if InCombatLockdown() then return end
    local data = button and button.action and button.action.data
    if not data then return end

    if cellIndex and data.mode == "specific" and data.pinnedIndex == cellIndex then
        data.mode = "lastUsed"
        data.pinnedIndex = nil
    else
        data.mode = "specific"
        data.pinnedIndex = cellIndex
    end
    Flyout.apply(button, data)
    addon.Button:UpdateButton(button)
    addon.Button:SaveButton(button)
end

function Flyout:SetCellAction(button, cellIndex, action)
    if InCombatLockdown() then return end
    local data = button and button.action and button.action.data
    if not data then return end
    -- A flyout inside a flyout would have the slot ask itself what it
    -- casts, forever. There is no sensible meaning for it either.
    if action and action.type == "flyout" then return end

    -- Editing a native flyout turns it into one of your own: take a
    -- snapshot of what the client currently offers and carry on from
    -- there, rather than silently discarding the edit.
    if data.flyoutID then
        local snapshot = {}
        for i, c in pairs(ResolveCells(data)) do
            if type(i) == "number" and c.type and c.data then
                snapshot[i] = { type = c.type, data = c.data }
            end
        end
        data.flyoutID = nil
        data.cells = snapshot
    end

    data.cells = data.cells or {}
    if action and action.type and action.data then
        data.cells[cellIndex] = { type = action.type, data = action.data }
    else
        data.cells[cellIndex] = nil
        if data.pinnedIndex == cellIndex then
            data.pinnedIndex = nil
            data.mode = "lastUsed"
        end
        if data.currentIndex == cellIndex then data.currentIndex = nil end
    end

    Flyout.apply(button, data)
    addon.Button:UpdateButton(button)
    addon.Button:SaveButton(button)
    if addon.FlyoutPopup then addon.FlyoutPopup:Refresh(button) end
end

-- Change the shape of the grid or where it opens.
function Flyout:SetShape(button, key, value)
    if InCombatLockdown() then return end
    local data = button and button.action and button.action.data
    if not data then return end
    data[key] = value
    Flyout.apply(button, data)
    addon.Button:UpdateButton(button)
    addon.Button:SaveButton(button)
    if addon.FlyoutPopup then addon.FlyoutPopup:Refresh(button) end
end

-- Anything the popup could not re-point during combat catches up here.
BazUI:QueueForModule("Bars", function()
    addon:On("PLAYER_REGEN_ENABLED", function()
        for button in pairs(pendingApply) do
            if button.action and button.action.type == "flyout" then
                Flyout.apply(button, button.action.data)
                addon.Button:UpdateButton(button)
                addon.Button:SaveButton(button)
            end
        end
        wipe(pendingApply)
    end)
end)

Actions:Register(Flyout)
