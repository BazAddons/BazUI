-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Auras: headers, buttons and painting
--
-- Four SecureAuraHeaderTemplate frames (buffs and debuffs for the
-- player, buffs and debuffs for the target) are parented to the BazUI
-- unit frames so they scale, move and hide with them. Each header
-- creates BazUIAuraButtonTemplate buttons, stamps "index" and "filter"
-- (or "target-slot" for weapon enchants) on each, sorts and positions
-- them, and handles the right-click cancel securely. The target frame
-- shows and hides through a secure state driver, so its headers follow
-- the target in and out of combat.
--
-- Everything here that touches a protected frame (attributes, anchors,
-- sizes, parent) runs out of combat only; a change requested in combat
-- is applied when combat ends. Painting icons and text is unrestricted.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("Auras")
local Auras = BazUI.Auras

local TEMPLATE = "BazUIAuraButtonTemplate"
local TICK     = 0.1     -- duration text refresh interval

local BUFF_RIM = { r = 0.08, g = 0.08, b = 0.10 }
-- Used when the client has no DebuffTypeColor table; same values.
local DEBUFF_COLORS = {
    none    = { r = 0.80, g = 0.00, b = 0.00 },
    Magic   = { r = 0.20, g = 0.60, b = 1.00 },
    Curse   = { r = 0.60, g = 0.00, b = 1.00 },
    Disease = { r = 0.60, g = 0.40, b = 0.00 },
    Poison  = { r = 0.00, g = 0.60, b = 0.00 },
}

local headers = {}       -- "HELPFUL" / "HARMFUL" (player), "TARGET_HELPFUL" / "TARGET_HARMFUL"
local buttons = {}       -- set of every button the headers have created
local hiddenParent
local initialized = false
local pendingApply  = false
-- A button the header made mid-fight that we were not allowed to resize.
local sizePending   = false
local refreshQueued = false
local applyQueued   = false

-- Preview state (see "Preview" below).
local demoFrame
local demoButtons = {}
local demoActive  = false
-- Defined with the rest of the preview, called from SizeRows above it.
local LayoutDemo

---------------------------------------------------------------------------
-- Reading auras
---------------------------------------------------------------------------

local function ReadAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if not a then return nil end
        return a.icon, a.applications, a.dispelName, a.expirationTime
    end
    local name, icon, count, dispelType, _, expirationTime = UnitAura(unit, index, filter)
    if not name then return nil end
    return icon, count, dispelType, expirationTime
end

-- Weapon enchants come from GetWeaponEnchantInfo, with expirations in
-- milliseconds from now rather than absolute times.
local function ReadWeapon(slot)
    local hasMain, mainExp, mainCharges, _, hasOff, offExp, offCharges = GetWeaponEnchantInfo()
    local has, exp, charges
    if slot == 16 then
        has, exp, charges = hasMain, mainExp, mainCharges
    elseif slot == 17 then
        has, exp, charges = hasOff, offExp, offCharges
    end
    if not has then return nil end
    local expirationTime = (exp and exp > 0) and (GetTime() + exp / 1000) or 0
    return GetInventoryItemTexture("player", slot), charges, expirationTime
end

local function FormatDuration(remaining)
    if remaining >= 86400 then return ("%dd"):format(math.floor(remaining / 86400 + 0.5)) end
    if remaining >= 3600  then return ("%dh"):format(math.floor(remaining / 3600 + 0.5)) end
    if remaining >= 60    then return ("%dm"):format(math.floor(remaining / 60 + 0.5)) end
    return ("%d"):format(math.ceil(remaining))
end

---------------------------------------------------------------------------
-- Painting one button
---------------------------------------------------------------------------

local function SetRim(btn, c)
    btn.Border:SetColorTexture(c.r, c.g, c.b, 1)
end

local function UpdateDuration(btn, now)
    if not btn.expirationTime
        or addon:RowValue(addon:RowOfButton(btn), "showDuration") == false then
        btn.Duration:SetText("")
        return
    end
    local remaining = btn.expirationTime - now
    if remaining <= 0 then
        btn.Duration:SetText("")
        return
    end
    btn.Duration:SetText(FormatDuration(remaining))
    if remaining < 5 then
        btn.Duration:SetTextColor(1, 0.35, 0.35)
    else
        btn.Duration:SetTextColor(1, 1, 1)
    end
end

-- The unit a button shows: its header's unit attribute.
local function ButtonUnit(btn)
    local h = btn:GetParent()
    return (h and h.GetAttribute and h:GetAttribute("unit")) or "player"
end

local function UpdateButton(btn)
    local slot   = tonumber(btn:GetAttribute("target-slot"))
    local index  = btn:GetAttribute("index")
    local filter = btn:GetAttribute("filter")
    local icon, count, dispel, expirationTime

    if slot then
        btn.isWeapon = true
        icon, count, expirationTime = ReadWeapon(slot)
    elseif index then
        btn.isWeapon = false
        icon, count, dispel, expirationTime = ReadAura(ButtonUnit(btn), index, filter)
    end

    if not icon then
        -- Nothing at this position (the unit died, or the header is a
        -- step behind): show nothing rather than an empty rim. Alpha is
        -- not protected, so this is safe in combat.
        btn.Icon:SetTexture(nil)
        btn.Count:SetText("")
        btn.Duration:SetText("")
        btn.expirationTime = nil
        btn:SetAlpha(0)
        return
    end

    btn:SetAlpha(1)
    btn.Icon:SetTexture(icon)
    if addon:GetSetting("showCount") ~= false and count and count > 1 then
        btn.Count:SetText(count)
    else
        btn.Count:SetText("")
    end
    btn.expirationTime = (expirationTime and expirationTime > 0) and expirationTime or nil

    if filter and filter:find("HARMFUL", 1, true) then
        local c
        if addon:GetSetting("debuffBorders") ~= false then
            local colors = _G.DebuffTypeColor or DEBUFF_COLORS
            c = colors[dispel or "none"] or colors.none or DEBUFF_COLORS.none
        else
            c = DEBUFF_COLORS.none
        end
        SetRim(btn, c)
    else
        SetRim(btn, BUFF_RIM)
    end
    UpdateDuration(btn, GetTime())

    if GameTooltip:IsOwned(btn) then
        Auras.OnButtonEnter(btn)
    end
end

function Auras.ApplyButtonSize(btn)
    local size = addon:RowValue(addon:RowOfButton(btn), "iconSize")
    if InCombatLockdown() then
        -- Resizing a button the secure header owns is protected, and the
        -- header makes a new one the moment an aura turns up that has no
        -- button yet. So a fight leaves a row wearing two sizes: the ones
        -- sized while we could, and the ones still at whatever the
        -- template started them at. Remember, and put it right after.
        if math.abs((btn:GetWidth() or 0) - size) > 0.5 then
            sizePending = true
        end
    else
        btn:SetSize(size, size)
    end
    local row = addon:RowOfButton(btn)
    btn.Duration:SetFont(BazUI.Skin.Theme.FontFile(),
        addon:DurationSize(row, size), "OUTLINE")
    btn.Count:SetFont(BazUI.Skin.Theme.FontFile(), math.max(8, math.floor(size * 0.40)), "OUTLINE")
end

---------------------------------------------------------------------------
-- Template script handlers (called from Auras.xml)
---------------------------------------------------------------------------

function Auras.OnButtonLoad(btn)
    buttons[btn] = true
    SetRim(btn, BUFF_RIM)
    Auras.ApplyButtonSize(btn)
end

function Auras.OnButtonAttributeChanged(btn, name)
    if name == "index" or name == "filter" or name == "target-slot" then
        UpdateButton(btn)
    end
end

function Auras.OnButtonShow(btn)
    UpdateButton(btn)
end

function Auras.OnButtonHide(btn)
    if GameTooltip:IsOwned(btn) then GameTooltip:Hide() end
end

function Auras.OnButtonEnter(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
    if btn.isWeapon then
        local slot = tonumber(btn:GetAttribute("target-slot"))
        if slot then GameTooltip:SetInventoryItem("player", slot) end
    else
        local index = btn:GetAttribute("index")
        if index then GameTooltip:SetUnitAura(ButtonUnit(btn), index, btn:GetAttribute("filter")) end
    end
    GameTooltip:Show()
end

function Auras.OnButtonLeave()
    GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Headers
---------------------------------------------------------------------------

-- Secure frames cannot be created in combat, and cannot be destroyed at
-- all, so a deleted row's header is parked and handed to the next row
-- that wants the same unit and filter rather than leaked.
local parked = {}

local function HeaderKey(unit, filter)
    return (unit or "player") .. "|" .. (filter or "HELPFUL")
end

local function CreateHeader(def)
    local key = HeaderKey(def.unit, def.filter)
    local spare = parked[key] and table.remove(parked[key])
    if spare then
        headers[def.id] = spare
        return spare
    end
    if InCombatLockdown() then return nil end

    local h = CreateFrame("Frame", "BazUIAuraRow" .. def.id, UIParent,
        "SecureAuraHeaderTemplate")
    h:SetAttribute("unit", def.unit)
    h:SetAttribute("filter", def.filter)
    h:SetAttribute("template", TEMPLATE)
    h:SetAttribute("weaponTemplate", TEMPLATE)
    h:SetAttribute("templateType", "Button")
    h:Hide()

    -- A secure nudge when the unit dies or is revived: the attribute
    -- change makes the header re-run its update, clearing a dead unit's
    -- leftover buttons even if no aura event follows.
    if def.unit ~= "player" then
        RegisterAttributeDriver(h, "state-unitdead",
            ("[@%s,dead] 1; 0"):format(def.unit))
    end

    headers[def.id] = h
    return h
end

local function ParkHeader(def)
    local h = headers[def.id]
    if not h then return end
    headers[def.id] = nil
    h:Hide()
    h:ClearAllPoints()
    h:SetParent(hiddenParent)
    local key = HeaderKey(def.unit, def.filter)
    parked[key] = parked[key] or {}
    parked[key][#parked[key] + 1] = h
end

-- below: rows hang under the group's anchor and stack downward, which is
-- what a group docked to the bottom of something wants; a group docked
-- above stacks upward instead. Icons always run left to right, and where
-- the row sits across its host is the group's alignment, not a growth
-- direction: the two used to be the same setting because the first icon
-- was pinned to a portrait.
local function ConfigureHeader(def, below)
    local h       = headers[def.id]
    if not h then return end
    local size    = addon:RowValue(def, "iconSize")
    local spacing = addon:RowValue(def, "spacing")
    local perRow  = addon:RowValue(def, "perRow")
    local step    = size + spacing

    -- Which way the icons run, and which way extra rows stack. Stacking
    -- follows the docked edge unless the row says otherwise, since rows
    -- growing back over what they are docked to is never what anyone
    -- meant by it.
    local right = (def.grow or "RIGHT") == "RIGHT"
    if def.stack == "UP" then below = false
    elseif def.stack == "DOWN" then below = true end

    local point = (below and "TOP" or "BOTTOM") .. (right and "LEFT" or "RIGHT")

    h:SetAttribute("point", point)
    h:SetAttribute("xOffset", right and step or -step)
    h:SetAttribute("yOffset", 0)
    -- A total to show, spread evenly rather than filling rows of perRow
    -- and overshooting: ten at eight across is two rows of five, not two
    -- rows of eight. The header can only stop at the end of a row, so
    -- the row length is what has to give.
    local across, rows = perRow, def.maxRows or 0
    if def.maxIcons and def.maxIcons > 0 then
        rows   = math.ceil(def.maxIcons / perRow)
        across = math.ceil(def.maxIcons / rows)
        -- Both limits hold, whichever bites first, so neither setting
        -- has to disappear when the other is set. A control that has to
        -- vanish is a control whose panel has to be rebuilt, and
        -- rebuilding a panel from a slider rebuilds it on every step of
        -- the drag.
        if def.maxRows and def.maxRows > 0 then
            rows = math.min(rows, def.maxRows)
        end
    end

    h:SetAttribute("wrapAfter", across)
    h:SetAttribute("wrapXOffset", 0)
    h:SetAttribute("wrapYOffset", below and -step or step)
    -- How many rows at most, nought for as many as there are auras. A
    -- row on somebody else wants a limit: sixteen debuffs on a party
    -- member is a legal state of affairs and a tower of icons through
    -- the middle of your screen is not what anyone meant by showing
    -- them. The header does the cutting off, securely, so a limit still
    -- holds while everything else is frozen.
    h:SetAttribute("maxWraps", rows)

    -- No floor on the header's own size. It measures itself to the box
    -- its buttons occupy unless these say otherwise, and that box is the
    -- only honest answer to how big the row is: two icons should measure
    -- two icons, not a full row's worth of mostly nothing.
    h:SetAttribute("minWidth", 1)
    h:SetAttribute("minHeight", 1)
    h:SetAttribute("sortMethod", addon:RowValue(def, "sortMethod"))
    h:SetAttribute("sortDirection", addon:RowValue(def, "sortDirection"))
    -- Which row a button belongs to, for anything that has only the
    -- button and needs the row's settings.
    h._bazRow = def.id
    local isPlayer = def.unit == "player"
    local weapons = isPlayer and def.filter == "HELPFUL"
        and addon:GetSetting("showWeapons") ~= false
    h:SetAttribute("includeWeapons", weapons and 1 or nil)

    -- Only mine: the header does the filtering, so this is a filter
    -- string rather than anything we check per icon. Changing it re-runs
    -- the header's update, which is fine out of combat, and this never
    -- runs in combat.
    local filter = def.filter
    if def.onlyMine and not isPlayer then filter = filter .. "|PLAYER" end
    h:SetAttribute("filter", filter)
    -- Buttons the header creates during combat still get the right size:
    -- this snippet runs in the header's secure environment. The
    -- template's right-click is "cancelaura", which always cancels the
    -- PLAYER's aura at the button's index, so buttons for any other unit
    -- lose it: right-clicking a target's buff must not drop one of yours.
    local snippet = ("self:SetWidth(%d); self:SetHeight(%d)"):format(size, size)
    if not isPlayer then
        snippet = snippet .. '; self:SetAttribute("type2", nil)'
    end
    h:SetAttribute("initialConfigFunction", snippet)

    -- Inside its group, at the corner the rows run from. Anchored once,
    -- out of combat: moving a secure header is protected, which is the
    -- whole reason the group frame exists.
    local frame = addon:RowFrame(def.id)
    if frame then
        h:ClearAllPoints()
        h:SetPoint(point, frame, point, 0, 0)
    end
end

---------------------------------------------------------------------------
-- Groups
--
-- A row of auras is a dockable, the same as a bar: it floats where you
-- put it or attaches to an action bar or a bar, above or below, and Edit
-- Mode drags it with the same handle and the same snapping, because that
-- all lives in the dock now rather than in the bars.
--
-- The secure header is not what moves. It cannot be, in combat. Each
-- group is an ordinary frame with the header anchored inside it at the
-- corner its rows run from, and the frame is what docks. Centering then
-- costs nothing: the frame is anchored center to center, so widening it
-- as icons arrive spreads the row evenly without touching anything
-- secure. That is the one thing the artwork frames could never do.
---------------------------------------------------------------------------

local FILTERS = { HELPFUL = "Buffs", HARMFUL = "Debuffs" }
local UNITS   = {
    player = "Player",
    target = "Target",
    pet    = "Pet",
    party1 = "Party 1",
    party2 = "Party 2",
    party3 = "Party 3",
    party4 = "Party 4",
}

addon.ROW_FILTERS = FILTERS
addon.ROW_UNITS   = UNITS
addon.ROW_ALIGNS  = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
addon.ROW_GROWTH  = { RIGHT = "Left to right", LEFT = "Right to left" }
addon.ROW_STACK   = { AUTO = "Away from the dock", DOWN = "Downward", UP = "Upward" }
addon.ROW_SORTS   = { INDEX = "Order applied", TIME = "Time remaining", NAME = "Name" }
addon.ROW_SORT_DIRECTIONS = { ["+"] = "Ascending", ["-"] = "Descending" }
addon.ROW_EDGES   = { BOTTOM = "Below", TOP = "Above" }

local UNIT_ORDER   = {
    "player", "target", "pet",
    "party1", "party2", "party3", "party4",
}
local FILTER_ORDER = { "HELPFUL", "HARMFUL" }

local rowFrames = {}        -- [id] = the ordinary frame that docks
local refitting = false     -- guards the resize-begets-resize loop

function addon:RowFrame(id) return rowFrames[id] end

function addon:RowHostID(id) return "aurarow:" .. id end

-- Whether anything on screen cares about this unit's auras.
function addon:HasRowFor(unit)
    for _, def in ipairs(self:Rows()) do
        if def.unit == unit then return true end
    end
    return false
end

-- What a row has been told, or what the module says otherwise. Every
-- layout value works this way: set it on a row and that row uses it,
-- leave it alone and it follows the setting every row shares. That way
-- a row can differ without every row having to be configured.
local ROW_FALLBACK = {
    iconSize      = "iconSize",
    spacing       = "spacing",
    perRow        = "perRow",
    sortMethod    = "sortMethod",
    sortDirection = "sortDirection",
    showDuration  = "showDuration",
}

local ROW_DEFAULT = {
    iconSize      = 26,
    spacing       = 3,
    perRow        = 8,
    sortMethod    = "INDEX",
    sortDirection = "+",
    showDuration  = true,
    -- Nought is "whatever suits the icon", which is what the timer did
    -- before it could be set: a shade under half the icon's height, and
    -- never below eight, because a smaller number is not a number any
    -- more. On a row of small icons that floor is most of the icon, which
    -- is the reason this is a setting.
    durationSize  = 0,
}

-- Icon size worked out from the host's width, for a row set to fill
-- it. Kept here rather than saved: it is a consequence of the layout,
-- not a choice, and it changes whenever the host does.
local fillSizes = {}

function addon:RowValue(def, key)
    if key == "iconSize" and def and def.fill and fillSizes[def.id] then
        return fillSizes[def.id]
    end
    local value = def and def[key]
    if value ~= nil then return value end
    value = self:GetSetting(ROW_FALLBACK[key] or key)
    if value ~= nil then return value end
    return ROW_DEFAULT[key]
end

-- What size the timer on a button should be: the row's own answer, or
-- one worked out from the icon when the row has not got one.
function addon:DurationSize(def, iconSize)
    local wanted = self:RowValue(def, "durationSize")
    if wanted and wanted > 0 then return wanted end
    return math.max(8, math.floor(iconSize * 0.42))
end

-- The row a button was created for, so its own icon size reaches it.
function addon:RowOfButton(btn)
    local header = btn and btn:GetParent()
    local id = header and header._bazRow
    return id and self:Row(id) or nil
end

---------------------------------------------------------------------------
-- The list of rows
---------------------------------------------------------------------------

function addon:Rows()
    local rows = self:GetSetting("rows")
    if type(rows) ~= "table" then
        rows = {}
        self:SetSetting("rows", rows)
    end
    return rows
end

function addon:Row(id)
    for _, def in ipairs(self:Rows()) do
        if def.id == id then return def end
    end
end

function addon:SaveRows()
    self:SetSetting("rows", self:Rows())
end

local function NextID(rows)
    local highest = 0
    for _, def in ipairs(rows) do
        if (def.id or 0) > highest then highest = def.id end
    end
    return highest + 1
end

function addon:DefaultRowName(unit, filter)
    local base = (UNITS[unit] or unit) .. " " .. (FILTERS[filter] or filter)
    local taken = {}
    for _, def in ipairs(self:Rows()) do taken[def.name or ""] = true end
    local index = 1
    while taken[base .. " " .. index] do index = index + 1 end
    return base .. " " .. index
end

function addon:AddRow(unit, filter)
    if InCombatLockdown() then return nil end
    unit, filter = unit or "player", filter or "HELPFUL"

    local rows = self:Rows()
    local def = {
        id       = NextID(rows),
        unit     = unit,
        filter   = filter,
        -- Icon size, spacing, how many per row and the sorting are left
        -- unset on purpose: a row follows the shared settings until you
        -- give it one of its own.
        onlyMine = false,
        -- Your own buffs are worth every row they need; a party
        -- member's debuffs are worth one. That is what every raid UI
        -- worth copying does, and it is only a default.
        maxRows  = (unit ~= "player") and 1 or nil,
        align    = "LEFT",
        gap      = 4,
        dock     = { host = "float", edge = "BOTTOM" },
        position = { point = "CENTER", relPoint = "CENTER", x = 0, y = -230 },
    }
    def.name = self:DefaultRowName(unit, filter)
    rows[#rows + 1] = def
    self:SaveRows()
    self:BuildRow(def)
    self:ApplySettings()
    return def
end

-- One row of a stack being copied.
function addon:CopyRow(def, unit, hostId, edge, drop)
    if InCombatLockdown() then return nil end

    local copy = self:AddRow(unit or def.unit, def.filter)
    if not copy then return nil end

    for key, value in pairs(def) do
        if key ~= "id" and key ~= "name" and key ~= "unit"
            and key ~= "dock" and key ~= "position" then
            copy[key] = value
        end
    end
    copy.name = self:DefaultRowName(copy.unit, copy.filter)

    if hostId then
        copy.dock = { host = hostId, edge = edge or "BOTTOM" }
    else
        copy.dock = { host = "float", edge = (def.dock and def.dock.edge) or "BOTTOM" }
        local pos = def.position or { point = "CENTER", relPoint = "CENTER", x = 0, y = -230 }
        copy.position = {
            point = pos.point, relPoint = pos.relPoint,
            x = pos.x or 0, y = (pos.y or 0) - (drop or 80),
        }
    end

    self:SaveRows()
    self:ApplySettings()
    return self:RowHostID(copy.id), rowFrames[copy.id]
end

function addon:RemoveRow(id)
    if InCombatLockdown() then return false end
    local rows = self:Rows()
    for index, def in ipairs(rows) do
        if def.id == id then
            local frame = rowFrames[id]
            if frame then
                BazUI.Dock:Detach(frame)
                BazUI.Dock:UnregisterHost(self:RowHostID(id))
                BazUI.Dock:UnregisterCopier(frame)
                if frame.mover then
                    BazUI:UnregisterEditModeFrame(frame.mover)
                    frame.mover:Hide()
                end
                frame:Hide()
                rowFrames[id] = nil
            end
            ParkHeader(def)
            table.remove(rows, index)
            self:SaveRows()
            self:ApplySettings()
            return true
        end
    end
    return false
end

-- What a new profile starts with: the four rows anyone expects, in the
-- places they used to be fixed at. Making none would leave someone
-- wondering where their buffs went.
local STARTER_ROWS = {
    { unit = "player", filter = "HELPFUL", x = -300, y = -230 },
    { unit = "player", filter = "HARMFUL", x = -300, y = -270 },
    { unit = "target", filter = "HELPFUL", x =  300, y = -230 },
    { unit = "target", filter = "HARMFUL", x =  300, y = -270 },
}

function addon:SeedRows()
    if #self:Rows() > 0 then return end
    for _, seed in ipairs(STARTER_ROWS) do
        local def = self:AddRow(seed.unit, seed.filter)
        if def then
            def.position = { point = "CENTER", relPoint = "CENTER", x = seed.x, y = seed.y }
        end
    end
    self:SaveRows()
end

---------------------------------------------------------------------------
-- Building one
---------------------------------------------------------------------------

-- Rows run away from whatever the row is attached to: docked above
-- something they stack upward, everywhere else downward.
local function RowsBelow(def)
    if def.dock and def.dock.host and def.dock.host ~= "float" then
        return def.dock.edge ~= "TOP"
    end
    return true
end

function addon:BuildRow(def)
    if rowFrames[def.id] then return rowFrames[def.id] end
    if not CreateHeader(def) then return nil end

    local frame = CreateFrame("Frame", "BazUIAuraRowFrame" .. def.id, UIParent)
    frame:SetFrameStrata("LOW")
    frame:SetSize(26, 26)
    rowFrames[def.id] = frame

    headers[def.id]:SetParent(frame)

    -- A row is somewhere other things can dock, the same as a bar: a
    -- debuff row under a buff row is the obvious arrangement and there
    -- was nothing to attach it to, because only bars ever registered.
    BazUI.Dock:RegisterHost(addon:RowHostID(def.id), frame,
        def.name or ("Row " .. def.id), 40)

    -- And how to make another of itself, so a stack holding rows can be
    -- copied for somebody else along with the bars around them.
    BazUI.Dock:RegisterCopier(frame, function(unit, hostId, edge, drop)
        return addon:CopyRow(def, unit, hostId, edge, drop)
    end)

    -- The thing this is docked to can be rescaled or resized long after
    -- it was docked, and the dock passes that width straight down. A
    -- filling row measures its icons again when that happens; the guard
    -- is because sizing the row is itself a size change.
    frame:HookScript("OnSizeChanged", function()
        if refitting or InCombatLockdown() or not def.fill then return end
        refitting = true
        if addon:FitRow(def) then
            ConfigureHeader(def, RowsBelow(def))
            addon:SizeRows()
        end
        refitting = false
    end)

    frame.mover = BazUI.Dock:CreateMover(frame, {
        name      = "BazUIAuraRowMover" .. def.id,
        label     = def.name or ("Row " .. def.id),
        addonName = "Auras",
        -- A full row of icons, so the handle shows the space the row
        -- can take rather than the space it happens to be using. An
        -- empty row is one pixel tall, and a handle that size says
        -- nothing about where the icons will land.
        minSize   = function()
            local size    = addon:RowValue(def, "iconSize")
            local spacing = addon:RowValue(def, "spacing")
            local perRow  = addon:RowValue(def, "perRow")
            return perRow * (size + spacing) - spacing, size
        end,
        settings  = function() return addon:RowEditSettings(def) end,
        actions   = function() return addon:RowEditActions(def) end,
        onDrop    = function(snap, x, y) addon:RowDropped(def, snap, x, y) end,
        onOffset  = function(x, y)
            -- Kept with the dock it belongs to, so undocking takes the
            -- nudge with it rather than leaving it to surprise whoever
            -- docks the row somewhere else later.
            def.dock = def.dock or { host = "float" }
            def.dock.offset = (x ~= 0 or y ~= 0) and { x = x, y = y } or nil
            addon:SaveRows()
        end,
    })
    return frame
end

function addon:BuildRows()
    if InCombatLockdown() then return end
    -- Rows made before names were numbered can collide, and two entries
    -- with one name in a list is a coin toss.
    local seen = {}
    for _, def in ipairs(self:Rows()) do
        if not def.name or seen[def.name] then
            def.name = self:DefaultRowName(def.unit, def.filter)
        end
        seen[def.name] = true
        self:BuildRow(def)
    end
    self:SaveRows()
end

---------------------------------------------------------------------------
-- Size and place
---------------------------------------------------------------------------

-- How wide and tall a row is right now, which is what its alignment
-- works from.
--
-- Not in combat, though the frame is an ordinary one. A secure header is
-- anchored to it, so resizing it moves something protected and the game
-- blocks the call: an unprotected wrapper buys you a parent you may
-- move, not a parent you may move at any time. Rows therefore keep the
-- size they had when the fight started, icons still come and go inside
-- them securely, and the size is taken again when combat ends. Left and
-- right aligned rows never needed it anyway, since they grow from their
-- anchored end; a centered one is briefly off center.
local function VisibleIcons(header)
    local count = 0
    for index = 1, select("#", header:GetChildren()) do
        local child = select(index, header:GetChildren())
        if child:IsShown() then count = count + 1 end
    end
    return count
end

-- Size the icons so a full row spans exactly what it is docked to.
-- Returns whether the answer changed, since re-stamping the header's
-- attributes for the same number is work nobody needs.
function addon:FitRow(def)
    local frame = rowFrames[def.id]
    if not (frame and def.fill and BazUI.Dock:IsDocked(frame)) then
        local had = fillSizes[def.id] ~= nil
        fillSizes[def.id] = nil
        return had
    end

    local perRow  = self:RowValue(def, "perRow")
    local spacing = self:RowValue(def, "spacing")
    local width   = frame:GetWidth() or 0
    if width <= 1 or perRow < 1 then return false end

    local size = math.max(8, math.floor((width - (perRow - 1) * spacing) / perRow))
    if fillSizes[def.id] == size then return false end
    fillSizes[def.id] = size
    return true
end

function addon:SizeRows()
    if InCombatLockdown() then return end

    for _, def in ipairs(self:Rows()) do
        local frame, header = rowFrames[def.id], headers[def.id]
        if frame and header then
            local size    = self:RowValue(def, "iconSize")
            local spacing = self:RowValue(def, "spacing")
            local step    = size + spacing
            local perRow  = self:RowValue(def, "perRow")
            local count   = VisibleIcons(header)
            -- A row that fills its host keeps the width the dock gave
            -- it, whether or not there are enough icons to cover it.
            -- That is the point of it: the row is as wide as the bar
            -- above it, always, and the icons are sized to suit.
            local filling = def.fill and BazUI.Dock:IsDocked(frame)

            if count == 0 then
                -- Nothing to show, so it takes up no height: a docked
                -- row with no auras in it should not hold space open
                -- above whatever is under it. The width it would have
                -- when full is kept, because that is what anything
                -- docked underneath takes, and a bar squeezed to a
                -- single pixel because nobody is buffed is nonsense.
                --
                -- Except while it is being arranged. A row is empty most
                -- of the time you are laying one out: solo, nobody in
                -- the party, nothing on anybody. A stack of one pixel
                -- rows puts every handle on top of the last, since a
                -- handle is an icon tall whatever it stands for, so with
                -- Edit Mode open an empty row holds a row's height and
                -- the handles are spaced the way the icons will be.
                local empty = (BazUI:IsEditMode() or demoActive) and size or 1
                if filling then
                    frame:SetHeight(empty)
                else
                    frame:SetSize(math.max(1, perRow * step - spacing), empty)
                end
            else
                -- Ask the header. It lays the icons out and then sizes
                -- itself to the box they occupy, so it knows exactly how
                -- tall the row is, including any limit it applied and
                -- any row it balanced. Working the same number out again
                -- from counts is how a row came to sit on top of the one
                -- it was docked under: two answers to one question, and
                -- the icons follow the header's.
                local width  = math.max(1, header:GetWidth() or 1)
                local height = math.max(1, header:GetHeight() or 1)
                if filling then
                    frame:SetHeight(height)
                else
                    frame:SetSize(width, height)
                end
            end
        end
    end

    -- The stand-ins are placed against the rows, so they are placed
    -- again whenever the rows change. Entering Edit Mode is exactly that
    -- case: an empty row is a pixel tall until this runs and stands it up
    -- to its real height, and laying the stand-ins out first put them
    -- against nothing. Doing it here rather than at each call site means
    -- no caller has to know the order.
    if demoActive then LayoutDemo() end
end

function addon:ApplyRows()
    if InCombatLockdown() then return end
    local enabled = self:GetSetting("enabled") ~= false

    for _, def in ipairs(self:Rows()) do
        local frame = rowFrames[def.id]
        if frame then
            local dock = def.dock or { host = "float" }
            BazUI.Dock:AttachTo(frame, dock.host, {
                edge  = dock.edge or "BOTTOM",
                mode  = def.fill and "stretch" or "align",
                align = def.align or "LEFT",
                gap   = def.gap,
                offset = dock.offset,
                -- Past every bar, so rows stay next to each other in the
                -- order: two of them can only share a line if nothing
                -- full width is sorted between them, and a bar and a row
                -- can each number themselves 1.
                order = 1000 + def.id,
            })

            if not BazUI.Dock:IsDocked(frame) then
                local pos = def.position or
                    { point = "CENTER", relPoint = "CENTER", x = 0, y = -230 }
                frame:ClearAllPoints()
                frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
            end

            -- Through the dock, so a row hanging off something hidden
            -- goes with it rather than floating over the screen alone.
            BazUI.Dock:SetShown(frame, enabled)
            if headers[def.id] then headers[def.id]:SetShown(enabled) end
            BazUI.Dock:RegisterHost(self:RowHostID(def.id), frame,
                def.name or ("Row " .. def.id), 40)

            if frame.mover then
                BazUI:UpdateEditModeLabel(frame.mover, def.name)
                frame.mover:ShowForEdit()
            end

            -- Now that the width is settled, the icons can be measured
            -- against it.
            self:FitRow(def)
        end
    end
end

-- Where a row ended up after a drag.
function addon:RowDropped(def, snap, x, y)
    if snap then
        def.dock = { host = snap.host, edge = snap.edge }
    elseif x then
        def.dock = { host = "float", edge = def.dock and def.dock.edge or "BOTTOM" }
        def.position = { point = "CENTER", relPoint = "BOTTOMLEFT", x = x, y = y }
    end
    self:SaveRows()
    -- Which way the icons stack can have changed with the edge, so the
    -- header is configured again rather than only moved.
    self:ApplySettings()
end

function addon:ShowRowMovers()
    for _, def in ipairs(self:Rows()) do
        local frame = rowFrames[def.id]
        if frame and frame.mover then frame.mover:ShowForEdit() end
    end
end

-- Rebuilding the panel is never done on the spot.
--
-- Half of these are asked for by a widget's own setter, because changing
-- where a row docks changes which settings are worth showing. Rebuilding
-- there tears down the widget that is mid-callback and builds a new one,
-- which sets its value, which calls a setter, and the game runs out of C
-- stack somewhere inside the menu code with no sign of who started it.
-- A frame's delay lets the callback finish first, and the flag means ten
-- changes in one frame cost one rebuild.
local refreshQueuedEdit = false

function addon:RefreshRowEditSettings()
    if refreshQueuedEdit then return end
    refreshQueuedEdit = true
    C_Timer.After(0, function()
        refreshQueuedEdit = false
        for _, def in ipairs(addon:Rows()) do
            local frame = rowFrames[def.id]
            if frame and frame.mover then
                BazUI:UpdateEditModeSettings(frame.mover, addon:RowEditSettings(def))
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Edit Mode: one row's form, and what can be done to it
---------------------------------------------------------------------------

local function Values(map)
    local out = {}
    for value, label in pairs(map) do
        out[#out + 1] = { label = label, value = value }
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

function addon:RowEditSettings(def)
    local function Refresh()
        addon:SaveRows()
        addon:ApplySettings()
    end

    local dockOptions = { { label = "Floating", value = "float" } }
    local frame = rowFrames[def.id]
    for _, host in ipairs(BazUI.Dock:GetHosts()) do
        local hostFrame = BazUI.Dock:GetHostFrame(host.id)
        -- Not itself, and not anything already hanging off it, which
        -- would be a loop.
        if hostFrame and hostFrame ~= frame
            and not (frame and BazUI.Dock:Follows(hostFrame, frame)) then
            dockOptions[#dockOptions + 1] = { label = host.label, value = host.id }
        end
    end

    local docked = def.dock and def.dock.host and def.dock.host ~= "float"

    local widgets = {
        { type = "dropdown", section = "Docking", label = "Dock to",
          options = dockOptions,
          get = function() return (def.dock and def.dock.host) or "float" end,
          set = function(value)
              def.dock = { host = value, edge = (def.dock and def.dock.edge) or "BOTTOM" }
              Refresh()
              -- Floating and docked do not offer the same choices.
              addon:RefreshRowEditSettings()
          end },
    }

    if docked then
        widgets[#widgets + 1] = { type = "dropdown", section = "Docking", label = "On the",
            options = Values(addon.ROW_EDGES),
            get = function() return (def.dock and def.dock.edge) or "BOTTOM" end,
            set = function(value)
                def.dock = { host = (def.dock and def.dock.host) or "float", edge = value }
                Refresh()
            end }
        widgets[#widgets + 1] = { type = "checkbox", section = "Docking", label = "Fill the width",
            get = function() return def.fill == true end,
            set = function(value)
                def.fill = value and true or false
                Refresh()
                -- Filling has no end to be aligned to, and its icon size
                -- is no longer a choice.
                addon:RefreshRowEditSettings()
            end }
        if not def.fill then
            widgets[#widgets + 1] = { type = "dropdown", section = "Docking", label = "Aligned",
                options = Values(addon.ROW_ALIGNS),
                get = function() return def.align or "LEFT" end,
                set = function(value) def.align = value Refresh() end }
        end
        widgets[#widgets + 1] = { type = "slider", section = "Docking", label = "Gap",
            min = 0, max = 24, step = 1,
            get = function() return def.gap or 4 end,
            set = function(value) def.gap = value Refresh() end }
    end

    local function Slider(label, key, low, high)
        widgets[#widgets + 1] = { type = "slider", section = "Icons", label = label,
            min = low, max = high, step = 1,
            get = function() return addon:RowValue(def, key) end,
            set = function(value) def[key] = value Refresh() end }
    end

    if not (def.fill and docked) then
        Slider("Icon size", "iconSize", 12, 48)
    end
    Slider("Spacing", "spacing", 0, 12)
    Slider("Icons per row", "perRow", 1, 20)

    widgets[#widgets + 1] = { type = "slider", section = "Icons", label = "Show at most",
        min = 0, max = 32, step = 1,
        get = function() return def.maxIcons or 0 end,
        set = function(value)
            def.maxIcons = (value > 0) and value or nil
            Refresh()
        end }

    widgets[#widgets + 1] = { type = "slider", section = "Icons", label = "Rows at most",
        min = 0, max = 6, step = 1,
        get = function() return def.maxRows or 0 end,
        set = function(value) def.maxRows = (value > 0) and value or nil Refresh() end }

    widgets[#widgets + 1] = { type = "dropdown", section = "Icons", label = "Icons run",
        options = Values(addon.ROW_GROWTH),
        get = function() return def.grow or "RIGHT" end,
        set = function(value) def.grow = value Refresh() end }
    widgets[#widgets + 1] = { type = "dropdown", section = "Icons", label = "Rows stack",
        options = Values(addon.ROW_STACK),
        get = function() return def.stack or "AUTO" end,
        set = function(value)
            def.stack = (value ~= "AUTO") and value or nil
            Refresh()
        end }

    if def.unit ~= "player" then
        widgets[#widgets + 1] = { type = "checkbox", section = "Icons", label = "Only mine",
            get = function() return def.onlyMine == true end,
            set = function(value) def.onlyMine = value and true or false Refresh() end }
    end

    widgets[#widgets + 1] = { type = "checkbox", section = "Timers", label = "Show timers",
        get = function() return addon:RowValue(def, "showDuration") ~= false end,
        set = function(value)
            def.showDuration = value and true or false
            Refresh()
            -- A row with no timers has no timer size. A checkbox may
            -- change which settings are showing; a slider may not.
            addon:RefreshRowEditSettings()
        end }

    if addon:RowValue(def, "showDuration") ~= false then
        widgets[#widgets + 1] = { type = "slider", section = "Timers", label = "Timer size",
            min = 0, max = 24, step = 1,
            format = function(value)
                return (value or 0) > 0 and tostring(value) or "Auto"
            end,
            get = function() return addon:RowValue(def, "durationSize") end,
            set = function(value)
                def.durationSize = (value > 0) and value or nil
                Refresh()
            end }
    end

    widgets[#widgets + 1] = { type = "dropdown", section = "Sorting", label = "Sort by",
        options = Values(addon.ROW_SORTS),
        get = function() return addon:RowValue(def, "sortMethod") end,
        set = function(value) def.sortMethod = value Refresh() end }
    widgets[#widgets + 1] = { type = "dropdown", section = "Sorting", label = "Direction",
        options = Values(addon.ROW_SORT_DIRECTIONS),
        get = function() return addon:RowValue(def, "sortDirection") end,
        set = function(value) def.sortDirection = value Refresh() end }

    widgets[#widgets + 1] = { type = "nudge", section = "Position" }
    return widgets
end

function addon:RowEditActions(def)
    return {
        {
            label = "Copy this and everything under it...",
            onClick = function(mover)
                local frame = rowFrames[def.id]
                if frame then BazUI:OpenCopyStackMenu(frame, mover) end
            end,
        },
        {
            label = "Duplicate",
            onClick = function()
                if InCombatLockdown() then
                    addon:Print("Create rows after combat ends.")
                    return
                end
                local copy = addon:AddRow(def.unit, def.filter)
                if not copy then return end
                for key, value in pairs(def) do
                    if key ~= "id" and key ~= "name"
                        and key ~= "dock" and key ~= "position" then
                        copy[key] = value
                    end
                end
                addon:SaveRows()
                addon:ApplySettings()
                addon:Print("Duplicated " .. (def.name or "row"))
            end,
        },
        {
            label = "|cffff4444Delete This Row|r",
            onClick = function()
                if not BazUI.Confirm then return end
                BazUI:Confirm({
                    title       = "Delete row?",
                    body        = ("Delete %s? Anything docked to it goes back to floating. Can't be undone."):format(def.name or "this row"),
                    acceptLabel = "Delete",
                    acceptStyle = "destructive",
                    onAccept    = function()
                        local frame = rowFrames[def.id]
                        if frame and frame.mover then BazUI:DeselectEditFrame(frame.mover) end
                        addon:RemoveRow(def.id)
                    end,
                })
            end,
        },
    }
end

-- Every kind of row, offered on Edit Mode's Create button beside the
-- bars, because a row of auras is the same sort of thing as a bar.
function addon:RegisterRowCreator()
    BazUI:RegisterEditModeCreator("Aura rows", function()
        local items = {}
        for _, filter in ipairs(FILTER_ORDER) do
            local submenu = {}
            for _, unit in ipairs(UNIT_ORDER) do
                submenu[#submenu + 1] = {
                    label = UNITS[unit],
                    onClick = function()
                        local def = addon:AddRow(unit, filter)
                        if def then addon:Print("Created " .. def.name) end
                    end,
                }
            end
            items[#items + 1] = { label = FILTERS[filter], submenu = submenu }
        end
        return items
    end)
end

local function SetBlizzardHidden(hide)
    for _, name in ipairs({ "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" }) do
        local f = _G[name]
        if f then
            if hide and not f._bazAurasParent then
                f._bazAurasParent = f:GetParent() or UIParent
                f:SetParent(hiddenParent)
            elseif not hide and f._bazAurasParent then
                f:SetParent(f._bazAurasParent)
                f._bazAurasParent = nil
            end
        end
    end
end

---------------------------------------------------------------------------
-- Preview
--
-- A full spread of made-up auras on every side, so the layout can be
-- judged without waiting for real ones. The stand-ins are plain frames
-- laid out by the same attributes the secure headers use, anchored to
-- the headers themselves, so they land exactly where real icons would.
-- Nothing secure is touched: the preview can start and stop at any
-- time and ends by itself when combat begins. Real auras stay
-- underneath it.
---------------------------------------------------------------------------

local DEMO_ROWS = 3

local DEMO_BUFFS = {
    "Spell_Holy_WordFortitude", "Spell_Holy_PowerWordShield", "Spell_Nature_Regeneration",
    "Ability_Warrior_BattleShout", "Spell_Frost_FrostArmor", "Spell_Holy_DivineSpirit",
    "Spell_Holy_Renew", "Spell_Nature_Thorns", "Spell_Holy_SealOfMight",
    "Spell_Nature_StrengthOfEarthTotem02", "Ability_Hunter_AspectOfTheMonkey", "Spell_Fire_FireArmor",
}
-- Icon and dispel type, so the rim colors show.
local DEMO_DEBUFFS = {
    { "Spell_Shadow_CurseOfTounges", "Curse" },      { "Spell_Nature_CorrosiveBreath", "Poison" },
    { "Spell_Shadow_CallofBone", "Disease" },        { "Spell_Fire_Immolation", "Magic" },
    { "Spell_Shadow_ShadowWordPain", "Magic" },      { "Ability_Warrior_Sunder" },
    { "Spell_Frost_FrostShock", "Magic" },           { "Ability_Rogue_Garrote" },
    { "Spell_Shadow_AbominationExplosion", "Poison" }, { "Spell_Nature_NullifyDisease", "Disease" },
    { "Spell_Shadow_UnholyFrenzy", "Curse" },        { "Ability_CriticalStrike" },
}

local function DemoButton(i)
    local btn = demoButtons[i]
    if not btn then
        btn = CreateFrame("Button", nil, demoFrame, "BazUIAuraVisualTemplate")
        btn:EnableMouse(false)
        demoButtons[i] = btn
    end
    return btn
end

function LayoutDemo()
    local now  = GetTime()
    local used = 0
    -- Every row there is, rather than the four there used to be, and
    -- each at its own icon size rather than a shared one.
    local sides = {}
    for _, def in ipairs(addon:Rows()) do
        sides[#sides + 1] = {
            headers[def.id],
            def.filter == "HARMFUL" and DEMO_DEBUFFS or DEMO_BUFFS,
            def.filter == "HARMFUL",
            def,
        }
    end
    for _, side in ipairs(sides) do
        local h, icons, harmful, def = side[1], side[2], side[3], side[4]
        if h and h:GetNumPoints() > 0 then
            local size   = addon:RowValue(def, "iconSize")
            local perRow = addon:RowValue(def, "perRow")
            local point = h:GetAttribute("point") or "BOTTOMLEFT"
            local xOff  = h:GetAttribute("xOffset") or 0
            local yWrap = h:GetAttribute("wrapYOffset") or 0
            local wrap  = math.max(1, h:GetAttribute("wrapAfter") or perRow)

            -- Under the row's own limits, read from the header so there
            -- is one answer rather than two. A preview that ignores them
            -- shows a layout the row will never produce, which is worse
            -- than no preview: it was showing three rows to somebody who
            -- had just asked for one.
            local maxWraps = tonumber(h:GetAttribute("maxWraps")) or 0
            local rows  = (maxWraps > 0) and maxWraps or DEMO_ROWS
            local count = wrap * rows
            -- The header lives in its unit frame's scale; the stand-ins
            -- live under UIParent, so offsets and sizes scale to match.
            local s = h:GetEffectiveScale() / demoFrame:GetEffectiveScale()
            local colors = _G.DebuffTypeColor or DEBUFF_COLORS
            for i = 0, count - 1 do
                used = used + 1
                local btn = DemoButton(used)
                local entry = icons[(i % #icons) + 1]
                local icon, dispel = entry, nil
                if type(entry) == "table" then icon, dispel = entry[1], entry[2] end

                local px = size * s
                btn:SetSize(px, px)
                btn.Duration:SetFont(BazUI.Skin.Theme.FontFile(),
                    addon:DurationSize(def, px), "OUTLINE")
                btn.Count:SetFont(BazUI.Skin.Theme.FontFile(), math.max(8, math.floor(px * 0.40)), "OUTLINE")
                btn.Icon:SetTexture("Interface\\Icons\\" .. icon)
                btn.Count:SetText((i % 3 == 1 and addon:GetSetting("showCount") ~= false) and tostring((i % 5) + 2) or "")
                -- Twenty seconds to an hour, spread so the labels differ.
                btn.expirationTime = now + 20 + (i * 137) % 3600
                local rim = BUFF_RIM
                if harmful then
                    if addon:GetSetting("debuffBorders") ~= false then
                        rim = colors[dispel or "none"] or colors.none or DEBUFF_COLORS.none
                    else
                        rim = DEBUFF_COLORS.none
                    end
                end
                SetRim(btn, rim)
                UpdateDuration(btn, now)

                local col, row = i % wrap, math.floor(i / wrap)
                btn:ClearAllPoints()
                btn:SetPoint(point, h, point, col * xOff * s, row * yWrap * s)
                btn:Show()
            end
        end
    end
    for i = used + 1, #demoButtons do demoButtons[i]:Hide() end
end

-- Turn the preview on or off; no argument toggles it.
-- Asked for by hand, as opposed to asked for by Edit Mode being open.
-- Kept apart so leaving Edit Mode does not cancel a preview somebody
-- turned on deliberately, and so entering it does not have to remember
-- what the answer was before.
local previewWanted = false

function addon:SetPreviewWanted(on)
    if on == nil then on = not previewWanted end
    previewWanted = on and true or false
    self:RefreshPreview()
end

function addon:PreviewWanted()
    return previewWanted
end

-- Rows are empty most of the time somebody is arranging them, and an
-- empty row tells you nothing about where its icons will sit or how big
-- they will be. Edit Mode therefore fills them in, the same as the bars
-- show placeholders for units who are not there.
function addon:RefreshPreview()
    self:SetPreview(previewWanted or BazUI:IsEditMode())
end

function addon:SetPreview(on)
    if on == nil then on = not demoActive end
    on = on and true or false
    if on == demoActive then return end
    demoActive = on
    if demoActive then
        if not demoFrame then
            demoFrame = CreateFrame("Frame", "BazUIAurasPreview", UIParent)
            demoFrame:SetFrameStrata("MEDIUM")
            demoFrame:SetSize(1, 1)
            demoFrame:SetPoint("CENTER")
        end
        LayoutDemo()
        demoFrame:Show()
        if previewWanted then
            BazUI:Print("Auras preview on. It turns off when combat starts, or type /bazauras preview.")
        end
    elseif demoFrame then
        demoFrame:Hide()
    end
    if BazUI.RefreshOptions then BazUI:RefreshOptions(self.MODULE_NAME .. "-Settings") end
end

function addon:IsPreviewing()
    return demoActive
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function addon:RefreshAll()
    for btn in pairs(buttons) do
        if btn:IsShown() then UpdateButton(btn) end
    end
    self:SizeRows()
end

function addon:QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        addon:RefreshAll()
    end)
end

-- Every button to the size its row asks for. Cheap enough to do the lot:
-- the alternative is tracking which ones missed out, and a button that
-- misses out is exactly the one nobody is tracking.
function Auras.ResizeButtons()
    if InCombatLockdown() then return end
    sizePending = false
    for btn in pairs(buttons) do
        Auras.ApplyButtonSize(btn)
    end
end

function addon:ApplySettings()
    if InCombatLockdown() then
        pendingApply = true
        return
    end
    pendingApply = false
    local enabled = self:GetSetting("enabled") ~= false

    -- Docking first: a row that fills its host cannot size its icons
    -- until it knows how wide the host made it.
    self:BuildRows()
    self:ApplyRows()
    for _, def in ipairs(self:Rows()) do
        ConfigureHeader(def, RowsBelow(def))
    end
    self:SizeRows()

    for btn in pairs(buttons) do
        Auras.ApplyButtonSize(btn)
        -- Buttons that already exist get the same treatment as new ones.
        if ButtonUnit(btn) ~= "player" and btn:GetAttribute("type2") then
            btn:SetAttribute("type2", nil)
        end
    end
    SetBlizzardHidden(enabled and self:GetSetting("hideBlizzard") ~= false)
    self:RefreshAll()
    if demoActive then LayoutDemo() end
end

-- The headers refresh themselves, securely, on their unit's UNIT_AURA
-- (which also fires with a full update when the target changes) and on
-- any attribute change. Never call SecureAuraHeader_Update from addon
-- code: buttons it creates during such a call are tainted, and every
-- later secure update that touches them in combat is blocked, leaving
-- stale icons frozen on screen.

function addon:QueueApply()
    if applyQueued then return end
    applyQueued = true
    C_Timer.After(0, function()
        applyQueued = false
        addon:ApplySettings()
    end)
end

function addon:Initialize()
    if initialized then return end

    -- Every row in this module is a secure aura header, and the client
    -- either ships that template or it does not - there is no drawing
    -- our way around it, because only Blizzard's secure code is allowed
    -- to decide which aura goes in which button.
    --
    -- Forever moved SecureAuraHeaderTemplate into its own file, gated on
    -- the client's game type, so a client outside that gate has the rest
    -- of the secure templates and not this one. Ask before building
    -- rather than letting CreateFrame throw once per row.
    if not BazUI.Has.Template("SecureAuraHeaderTemplate") then
        self.unavailable = "This client does not provide secure aura headers, so aura rows cannot be built."
        BazUI:Print("Auras are off: " .. self.unavailable)
        return
    end

    initialized = true
    -- Secure frames must not be created in combat.
    if InCombatLockdown() then
        initialized = false
        self:On("PLAYER_REGEN_ENABLED", function() self:Initialize() end)
        return
    end

    hiddenParent = CreateFrame("Frame")
    hiddenParent:Hide()

    -- Every header lives inside a row frame, which is the thing that
    -- docks and the thing Edit Mode moves.
    self:RegisterRowCreator()
    self:BuildRows()
    self:SeedRows()

    -- One ticker for every duration label.
    local ticker = CreateFrame("Frame")
    ticker.elapsed = 0
    ticker:SetScript("OnUpdate", function(f, elapsed)
        f.elapsed = f.elapsed + elapsed
        if f.elapsed < TICK then return end
        f.elapsed = 0
        local now = GetTime()
        for btn in pairs(buttons) do
            if btn.expirationTime and btn:IsVisible() then
                UpdateDuration(btn, now)
            end
        end
        if demoActive then
            for _, btn in ipairs(demoButtons) do
                if btn.expirationTime and btn:IsVisible() then
                    UpdateDuration(btn, now)
                end
            end
        end
    end)

    -- Any unit somebody has made a row for, not the two there used to
    -- be. A party row that never heard about its member's auras kept the
    -- size it had while empty, so the icons ran out of a one-pixel frame
    -- and a centered row was centered on nothing.
    self:On("UNIT_AURA", function(_, unit)
        if unit and self:HasRowFor(unit) then self:QueueRefresh() end
    end)
    self:On("PLAYER_TARGET_CHANGED", function() self:QueueRefresh() end)
    -- Party slots change hands without any unit event of their own.
    self:On("GROUP_ROSTER_UPDATE", function() self:QueueRefresh() end)
    self:On("UNIT_INVENTORY_CHANGED", function(_, unit)
        if unit == "player" then self:QueueRefresh() end
    end)
    self:On("PLAYER_ENTERING_WORLD", function() self:QueueRefresh() end)
    self:On("PLAYER_REGEN_ENABLED", function()
        if pendingApply then
            self:ApplySettings()
            return
        end
        -- Buttons before rows: a row measures the box its buttons make,
        -- so it has to be asked after they are the right size.
        if sizePending then Auras.ResizeButtons() end
        self:SizeRows()
    end)
    self:On("PLAYER_REGEN_DISABLED", function()
        -- Stand-ins have no business on screen during a fight, whoever
        -- asked for them.
        previewWanted = false
        if demoActive then self:SetPreview(false) end
    end)
    self:OnProfileChanged(function() self:ApplySettings() end)

    self:On("BAZ_EDITMODE_ENTER", function()
        self:RefreshRowEditSettings()
        -- Empty rows stand up to their full height while arranging, and
        -- fill with stand-in icons so the footprint is the real one.
        self:RefreshPreview()
        self:SizeRows()
        self:ShowRowMovers()
    end)
    self:On("BAZ_EDITMODE_EXIT", function()
        self:RefreshPreview()
        self:SizeRows()
        self:ShowRowMovers()
    end)

    -- Follow the unit frames: a bar a group is docked to can move or
    -- resize, and the dock passes that down, but a group floating beside
    -- one still wants re-applying after the bars settle.
    local uf = BazUI:GetModule("UnitFrames")
    if uf and uf.ApplySettings then
        hooksecurefunc(uf, "ApplySettings", function() addon:QueueApply() end)
    end

    self:ApplySettings()
end
