-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazBars Actions Registry
-- Central registry for action handlers. Each handler knows everything about
-- one action type (spell, item, macro, mount, etc.) in a self-contained module.
--
-- See the handler interface comment at the bottom of this file for the contract.
--
-- FUTURE NOTE: This pattern (Registry + per-type handlers in Actions/*.lua)
-- is a strong candidate for promotion to BazUI when a second addon needs
-- action buttons. The handlers are almost entirely addon-agnostic - they
-- wrap Blizzard APIs with no BazBars-specific logic. At that point, move:
--   - Registry.lua > BazUI/Actions/Registry.lua
--   - Spell/Item/Toy/Mount/BattlePet/Macro/EquipmentSet/MacroText > BazUI/Actions/
-- BazBars would then call BazUI.Actions:FromCursor() etc. Leave it here
-- until there's a real second consumer so the API gets designed against
-- actual use cases rather than speculation.

local BazBars = BazUI.Bars   -- module namespace (was the BazBars global)
local addon = BazUI:GetModule("Bars")
local Actions = {}
addon.Actions = Actions
BazBars.Actions = Actions

---------------------------------------------------------------------------
-- Handler storage
---------------------------------------------------------------------------

local handlers = {} -- [type] = handlerTable

function Actions:Register(handler)
    if not handler or not handler.type then
        error("BazUIBars.Actions:Register requires a handler with a 'type' field")
    end
    handlers[handler.type] = handler
end

function Actions:Get(type)
    return handlers[type]
end

function Actions:GetAll()
    return handlers
end

---------------------------------------------------------------------------
-- Cursor detection
-- Returns (handler, data) if a registered handler recognizes what's on the
-- cursor, or nil if none do. Handlers are checked in priority order so more
-- specific types (e.g. Toy) can run before more general types (e.g. Item).
---------------------------------------------------------------------------

local function GetOrderedHandlers()
    local list = {}
    for _, h in pairs(handlers) do
        list[#list + 1] = h
    end
    table.sort(list, function(a, b)
        local pa = a.priority or 100
        local pb = b.priority or 100
        if pa ~= pb then return pa < pb end
        return a.type < b.type
    end)
    return list
end

function Actions:FromCursor()
    for _, handler in ipairs(GetOrderedHandlers()) do
        if handler.fromCursor then
            local data = handler.fromCursor()
            if data then
                return handler, data
            end
        end
    end
end

---------------------------------------------------------------------------
-- Button attribute helpers
---------------------------------------------------------------------------

-- Known attribute keys that any handler might set on a secure button.
-- Generic clear wipes all of these at once, so we don't have to track
-- per-handler which attributes were set.
local BUTTON_ATTRS = {
    "type", "type2",
    "spell", "spell2",
    "item", "item2",
    "macro", "macrotext",
    "toy",
    "unit2",
    "shift-type1", "shift-type2",
}

function Actions:ClearButtonAttributes(button)
    for _, attr in ipairs(BUTTON_ATTRS) do
        button:SetAttribute(attr, nil)
    end
end

---------------------------------------------------------------------------
-- Apply an action to a button
-- Dispatches to the handler and optionally sets up right-click self-cast.
---------------------------------------------------------------------------

function Actions:Apply(button, action, selfCastEnabled)
    if not action or not action.type then return false end
    local handler = handlers[action.type]
    if not handler or not handler.apply then return false end

    -- Always clear attributes first, even if swapping between same type,
    -- so stale type2/unit2 from self-cast don't linger.
    self:ClearButtonAttributes(button)

    -- Block actions while Shift is held (prevents firing during Shift+Drag removal)
    button:SetAttribute("shift-type1", "noop")
    button:SetAttribute("shift-type2", "noop")

    handler.apply(button, action.data)

    if selfCastEnabled and handler.applySelfCast then
        handler.applySelfCast(button, action.data)
    end
    return true
end

---------------------------------------------------------------------------
-- Serialize / deserialize
---------------------------------------------------------------------------

function Actions:Serialize(action)
    if not action or not action.type then return nil end
    local handler = handlers[action.type]
    if not handler then return nil end
    local data = action.data
    if handler.serialize then data = handler.serialize(action.data) end
    return { type = action.type, data = data }
end

function Actions:Deserialize(saved)
    if not saved or not saved.type then return nil end
    local handler = handlers[saved.type]
    if not handler then return nil end
    local data = saved.data
    if handler.deserialize then data = handler.deserialize(saved.data) end
    if not data then return nil end -- handler rejected (e.g. spell no longer exists)
    return { type = saved.type, data = data }
end

---------------------------------------------------------------------------
-- Migration from legacy bbCommand/bbValue/bbSubValue/bbID/bbMacrotext
-- Returns a new-format action, or nil if migration failed.
--
-- Handlers are tried in priority order (same as cursor detection), so more
-- specific handlers (e.g. Toy) get a chance to claim legacy entries before
-- more general ones (e.g. Item). Each handler's migrate() returns nil to
-- pass to the next handler.
---------------------------------------------------------------------------

function Actions:MigrateLegacy(legacy)
    if not legacy or not legacy.command then return nil end
    for _, handler in ipairs(GetOrderedHandlers()) do
        if handler.migrate then
            local data = handler.migrate(legacy)
            if data then
                return { type = handler.type, data = data }
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Handler Interface Contract
---------------------------------------------------------------------------
--
-- Every handler is a table passed to Actions:Register(). It should implement
-- as many of the methods below as apply to its action type. Missing methods
-- are silently skipped, so e.g. a macrotext handler can omit getCooldown.
--
-- {
--     type = "spell",           -- [required] unique string identifier
--     priority = 50,            -- [optional] lower = checked earlier for cursor
--                               -- detection. Default 100. Use lower values for
--                               -- more specific types (Toy before Item).
--
--     -- ── CURSOR ──────────────────────────────────────────────────────────
--     fromCursor = function()
--         -- Inspect GetCursorInfo() and return a handler-specific data table
--         -- if the cursor currently holds this type, or nil otherwise.
--     end,
--
--     pickup = function(data)
--         -- Put this action back on the WoW cursor, typically via
--         -- PickupSpell / PickupItem / PickupMacro / etc.
--     end,
--
--     -- ── BUTTON ──────────────────────────────────────────────────────────
--     apply = function(button, data)
--         -- Set SecureActionButton attributes (type, spell, item, macro...).
--         -- Registry already cleared old attrs and set shift-type noop guard
--         -- before calling this.
--     end,
--
--     applySelfCast = function(button, data)   -- [optional]
--         -- Set type2 / <action>2 / unit2 attributes for right-click self-cast.
--         -- Only implement for types that support targeting (spell, item).
--     end,
--
--     -- ── VISUALS (pure, return values - no side effects) ────────────────
--     getIcon = function(data)          -- [optional] textureID or path
--     getName = function(data)          -- [optional] display name string
--     getCount = function(data)         -- [optional] string for charges/stacks
--     getCooldown = function(data)      -- [optional] (start, duration, enable)
--                                       --             or a cooldown object
--     isUsable = function(data)         -- [optional] (isUsable, insufficientPower)
--     isInRange = function(data, unit)  -- [optional] true, false, or nil
--     hasProcGlow = function(data)      -- [optional] bool for spell overlay
--     showTooltip = function(data)      -- [optional] sets GameTooltip content
--                                       --             (caller already set owner)
--
--     -- ── PERSISTENCE ─────────────────────────────────────────────────────
--     serialize = function(data)        -- [optional] return SV-safe table.
--                                       -- Defaults to the data table itself.
--     deserialize = function(saved)     -- [optional] validate & return data,
--                                       -- or nil if no longer valid.
--     migrate = function(legacy)        -- [optional] convert from old format:
--                                       -- { command, value, subValue, id,
--                                       --   macrotext }. Return data or nil.
-- }
