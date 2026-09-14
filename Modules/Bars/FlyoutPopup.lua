-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Bars: the flyout popup
--
-- A thin adapter between a flyout slot and BazUI:CreateSecureActionPopup.
-- The popup itself knows nothing about flyouts or spells: it draws a grid
-- of secure buttons and calls back. Everything here is the translation
-- between that grid and the bar's action registry.
--
-- One popup per slot, kept for the life of the button. Frames cannot be
-- destroyed in this client, so a slot that stops being a flyout keeps
-- its popup hidden and unwired rather than orphaning it.
---------------------------------------------------------------------------

local BazBars = BazUI.Bars
local addon = BazUI:GetModule("Bars")
local Actions = addon.Actions

local FlyoutPopup = {}
addon.FlyoutPopup = FlyoutPopup
BazBars.FlyoutPopup = FlyoutPopup

-- An empty square shows its border and nothing else. Anything drawn in
-- it would read as an action that is there but broken.

---------------------------------------------------------------------------
-- Grid shape
--
-- The grid always has room for the highest cell the player has filled,
-- even if they later shrink it; a cell you cannot reach is a cell you
-- cannot take back out.
---------------------------------------------------------------------------

local function GridFor(data)
    local Flyout = addon.FlyoutHandler
    local cells = Flyout.ResolveCells(data)
    local highest = Flyout.MaxCellIndex(cells)

    local rows = math.max(1, data.rows or 1)
    local cols = math.max(1, data.cols or 3)
    if rows * cols < highest then
        cols = math.ceil(highest / rows)
    end
    return rows, cols, cells
end

---------------------------------------------------------------------------
-- Options handed to the popup
---------------------------------------------------------------------------

local function BuildOpts(button, data)
    local Flyout = addon.FlyoutHandler
    local rows, cols, cells = GridFor(data)

    return {
        parent       = button,
        toggleButton = "RightButton",
        direction    = data.direction or "UP",
        rows         = rows,
        cols         = cols,
        cells        = cells,
        hideOnCast   = true,

        -- Each cell is a real secure button, and the cell's own action
        -- handler sets its attributes, so casting from a flyout goes
        -- through exactly the same path as casting from a bar slot.
        applyCell = function(cellBtn, _, cellData)
            if not (cellData and cellData.type) then return end
            if cellData.type == "flyout" then return end    -- never nested
            if cellData.isKnown == false then return end    -- shown, but inert
            Actions:Apply(cellBtn, { type = cellData.type, data = cellData.data }, false)
        end,

        iconForCell = function(cellData)
            if not (cellData and cellData.type) then return nil end
            local handler = Actions:Get(cellData.type)
            if handler and handler.getIcon then return handler.getIcon(cellData.data) end
        end,

        onCellEnter = function(_, cellData, cellBtn)
            if not (cellData and cellData.type) then return end
            local handler = Actions:Get(cellData.type)
            if not (handler and handler.showTooltip) then return end
            GameTooltip:SetOwner(cellBtn, "ANCHOR_RIGHT")
            handler.showTooltip(cellData.data)
            if cellData.isKnown == false then
                GameTooltip:AddLine("You have not learned this.", 0.85, 0.3, 0.3)
            end
            GameTooltip:AddLine("Right-click to make this the button's action.",
                0.6, 0.55, 0.45)
            GameTooltip:Show()
        end,

        onCellClick = function(cellIndex, cellData, mouseButton)
            if mouseButton == "RightButton" then
                -- Pinning is the only thing a right-click does here;
                -- the cell has no right-click cast attributes set.
                if cellData and cellData.type then
                    Flyout:SetPinnedCell(button, cellIndex)
                end
                return
            end
            Flyout:RecordCellClick(button, cellIndex)
        end,

        -- Dropping onto a cell puts that action in the grid square.
        onCellDrag = function(cellIndex)
            if Flyout.HasPending and Flyout.HasPending() then
                return -- a flyout cannot live inside a flyout
            end
            local handler, dragData = Actions:FromCursor()
            if not (handler and dragData) then return end
            ClearCursor()
            Flyout:SetCellAction(button, cellIndex, { type = handler.type, data = dragData })
        end,

        -- Dragging a cell out takes it off the grid and onto the cursor,
        -- so it can go straight onto a bar or into another flyout.
        onCellDragStart = function(cellIndex, cellData)
            if not (cellData and cellData.type) then return end
            local handler = Actions:Get(cellData.type)
            if not (handler and handler.pickup) then return end
            handler.pickup(cellData.data)
            Flyout:SetCellAction(button, cellIndex, nil)
        end,
    }
end

---------------------------------------------------------------------------
-- Attaching and detaching
---------------------------------------------------------------------------

local waitingForCombatEnd = {}

function FlyoutPopup:AttachTo(button, data)
    if not (button and data) then return end
    if InCombatLockdown() then
        -- Wiring a popup sets secure attributes on the slot. A flyout
        -- drawn for the first time during combat waits here and is
        -- picked up when it ends, rather than quietly never working.
        waitingForCombatEnd[button] = true
        return
    end

    local opts = BuildOpts(button, data)
    if button._bazFlyoutPopup then
        button._bazFlyoutPopup:Configure(opts)
    else
        button._bazFlyoutPopup = BazUI:CreateSecureActionPopup(opts)
    end
    return button._bazFlyoutPopup
end

function FlyoutPopup:Refresh(button)
    local popup = button and button._bazFlyoutPopup
    if not popup then return end
    if not (button.action and button.action.type == "flyout") then return end
    if InCombatLockdown() then return end
    popup:Configure(BuildOpts(button, button.action.data))
end

-- The slot is no longer a flyout. Hide the popup and take the toggle
-- wiring back off the button, but keep the frame: it is reused if this
-- slot becomes a flyout again, and it cannot be destroyed either way.
function FlyoutPopup:DetachFrom(button)
    if not button then return end
    waitingForCombatEnd[button] = nil

    local popup = button._bazFlyoutPopup
    if popup then popup:SafeHide() end
    if InCombatLockdown() then return end
    if button.SetAttribute then
        button:SetAttribute("type2", nil)
        button:SetAttribute("clickbutton", nil)
        button:SetAttribute("clickbutton2", nil)
    end
end

function FlyoutPopup:HideFor(button)
    local popup = button and button._bazFlyoutPopup
    if popup then popup:SafeHide() end
end

BazUI:QueueForLogin(function()
    addon:On("PLAYER_REGEN_ENABLED", function()
        for button in pairs(waitingForCombatEnd) do
            if button.action and button.action.type == "flyout" then
                FlyoutPopup:AttachTo(button, button.action.data)
            end
        end
        wipe(waitingForCombatEnd)
    end)
end)
