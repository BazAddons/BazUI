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
local pendingApply  = false
local refreshQueued = false
local applyQueued   = false

-- Preview state (see "Preview" below).
local demoFrame
local demoButtons = {}
local demoActive  = false

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
    if not btn.expirationTime or addon:GetSetting("showDuration") == false then
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
    local size = addon:GetSetting("iconSize") or 26
    if not InCombatLockdown() then
        btn:SetSize(size, size)
    end
    btn.Duration:SetFont(BazUI.Skin.Theme.FontFile(), math.max(8, math.floor(size * 0.42)), "OUTLINE")
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

local function CreateHeader(key, unit, filter, name)
    local h = CreateFrame("Frame", name, UIParent, "SecureAuraHeaderTemplate")
    h:SetAttribute("unit", unit)
    h:SetAttribute("filter", filter)
    h:SetAttribute("template", TEMPLATE)
    h:SetAttribute("weaponTemplate", TEMPLATE)
    h:SetAttribute("templateType", "Button")
    h:Hide()
    headers[key] = h
    return h
end

-- below: rows hang under the group's anchor and stack downward, which is
-- what a group docked to the bottom of something wants; a group docked
-- above stacks upward instead. Icons always run left to right, and where
-- the row sits across its host is the group's alignment, not a growth
-- direction: the two used to be the same setting because the first icon
-- was pinned to a portrait.
local function ConfigureHeader(entry, below)
    local h       = headers[entry.key]
    local size    = addon:GetSetting("iconSize") or 26
    local spacing = addon:GetSetting("spacing") or 3
    local perRow  = addon:GetSetting("perRow") or 8
    local step    = size + spacing
    local side    = (entry.filter == "HELPFUL") and "left" or "right"

    local point = (below and "TOP" or "BOTTOM") .. "LEFT"

    h:SetAttribute("point", point)
    h:SetAttribute("xOffset", step)
    h:SetAttribute("yOffset", 0)
    h:SetAttribute("wrapAfter", perRow)
    h:SetAttribute("wrapXOffset", 0)
    h:SetAttribute("wrapYOffset", below and -step or step)
    h:SetAttribute("maxWraps", 0)           -- 0 = as many rows as needed
    h:SetAttribute("minWidth", perRow * step - spacing)
    h:SetAttribute("minHeight", size)
    h:SetAttribute("sortMethod", addon:GetSetting("sortMethod") or "INDEX")
    h:SetAttribute("sortDirection", addon:GetSetting("sortDirection") or "+")
    local isPlayer = entry.unit == "player"
    local weapons = isPlayer and side == "left" and addon:GetSetting("showWeapons") ~= false
    h:SetAttribute("includeWeapons", weapons and 1 or nil)
    if not isPlayer and side == "right" then
        -- Changing the filter re-runs the header's update, which is fine
        -- out of combat (ApplySettings never runs in combat).
        local mine = addon:GetSetting("targetOnlyMine") == true
        h:SetAttribute("filter", mine and "HARMFUL|PLAYER" or "HARMFUL")
    end
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
    local frame = addon:GroupFrame(entry.key)
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
-- corner its rows run from, and the frame is what docks. Centring then
-- costs nothing: the frame is anchored centre to centre, so widening it
-- as icons arrive spreads the row evenly without touching anything
-- secure. That is the one thing the artwork frames could never do.
---------------------------------------------------------------------------

local GROUPS = {
    { key = "HELPFUL",        label = "Player Buffs",   unit = "player", filter = "HELPFUL",
      position = { point = "CENTER", relPoint = "CENTER", x = -300, y = -230 } },
    { key = "HARMFUL",        label = "Player Debuffs", unit = "player", filter = "HARMFUL",
      position = { point = "CENTER", relPoint = "CENTER", x = -300, y = -270 } },
    { key = "TARGET_HELPFUL", label = "Target Buffs",   unit = "target", filter = "HELPFUL",
      position = { point = "CENTER", relPoint = "CENTER", x = 300, y = -230 } },
    { key = "TARGET_HARMFUL", label = "Target Debuffs", unit = "target", filter = "HARMFUL",
      position = { point = "CENTER", relPoint = "CENTER", x = 300, y = -270 } },
}
addon.GROUPS = GROUPS

addon.GROUP_ALIGNS = { LEFT = "Left", CENTER = "Centre", RIGHT = "Right" }
addon.GROUP_EDGES  = { BOTTOM = "Below", TOP = "Above" }

local groupFrames = {}

function addon:GroupFrame(key) return groupFrames[key] end

function addon:GroupEntry(key)
    for _, entry in ipairs(GROUPS) do
        if entry.key == key then return entry end
    end
end

-- Written on first use rather than shipped in the defaults, so a group
-- added later starts somewhere sensible instead of nowhere.
function addon:GroupDef(key)
    local groups = self:GetSetting("groups")
    if type(groups) ~= "table" then
        groups = {}
        self:SetSetting("groups", groups)
    end
    local def = groups[key]
    if not def then
        local entry = self:GroupEntry(key)
        def = {
            dock     = { host = "float", edge = "BOTTOM" },
            align    = "LEFT",
            gap      = 4,
            position = entry and entry.position or
                { point = "CENTER", relPoint = "CENTER", x = 0, y = -230 },
        }
        groups[key] = def
        self:SetSetting("groups", groups)
    end
    return def
end

function addon:SaveGroups()
    self:SetSetting("groups", self:GetSetting("groups"))
end

-- Rows run away from whatever the group is attached to: docked above
-- something they stack upward, everywhere else downward.
local function RowsBelow(def)
    if def.dock and def.dock.host and def.dock.host ~= "float" then
        return def.dock.edge ~= "TOP"
    end
    return true
end

local function CreateGroup(entry)
    if groupFrames[entry.key] then return groupFrames[entry.key] end

    local frame = CreateFrame("Frame", "BazUIAuraGroup" .. entry.key, UIParent)
    frame:SetFrameStrata("LOW")
    frame:SetSize(26, 26)
    groupFrames[entry.key] = frame

    headers[entry.key]:SetParent(frame)

    frame.mover = BazUI.Dock:CreateMover(frame, {
        name      = "BazUIAuraGroupMover" .. entry.key,
        label     = entry.label,
        addonName = "Auras",
        settings  = function() return addon:GroupEditSettings(entry) end,
        onDrop    = function(snap, x, y) addon:GroupDropped(entry, snap, x, y) end,
    })
    return frame
end

-- How wide and tall the group is right now, which is what its alignment
-- works from. Safe in combat: the group frame is an ordinary frame, and
-- this is the only thing that has to change while icons come and go.
local function VisibleIcons(header)
    local count = 0
    for index = 1, select("#", header:GetChildren()) do
        local child = select(index, header:GetChildren())
        if child:IsShown() then count = count + 1 end
    end
    return count
end

function addon:SizeGroups()
    local size    = self:GetSetting("iconSize") or 26
    local spacing = self:GetSetting("spacing") or 3
    local perRow  = self:GetSetting("perRow") or 8
    local step    = size + spacing

    for _, entry in ipairs(GROUPS) do
        local frame, header = groupFrames[entry.key], headers[entry.key]
        if frame and header then
            local count = VisibleIcons(header)
            if count == 0 then
                -- Nothing to show, so it takes up nothing: a docked row
                -- with no auras in it should not hold an icon's worth of
                -- space open above whatever is under it.
                frame:SetSize(1, 1)
            else
                local columns = math.min(perRow, count)
                local rows    = math.ceil(count / perRow)
                frame:SetSize(math.max(1, columns * step - spacing),
                    math.max(1, rows * step - spacing))
            end
        end
    end
end

function addon:ApplyGroups()
    if InCombatLockdown() then return end

    for _, entry in ipairs(GROUPS) do
        local def   = self:GroupDef(entry.key)
        local frame = groupFrames[entry.key]
        if frame then
            local dock = def.dock or { host = "float" }
            BazUI.Dock:AttachTo(frame, dock.host, {
                edge  = dock.edge or "BOTTOM",
                mode  = "align",
                align = def.align or "LEFT",
                gap   = def.gap,
                order = 50,
            })

            if not BazUI.Dock:IsDocked(frame) then
                local pos = def.position or
                    { point = "CENTER", relPoint = "CENTER", x = 0, y = -230 }
                frame:ClearAllPoints()
                frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
            end

            if frame.mover then frame.mover:ShowForEdit() end
        end
    end
    self:SizeGroups()
end

-- Where a group ended up after a drag.
function addon:GroupDropped(entry, snap, x, y)
    local def = self:GroupDef(entry.key)
    if snap then
        def.dock = { host = snap.host, edge = snap.edge }
    elseif x then
        def.dock = { host = "float", edge = def.dock and def.dock.edge or "BOTTOM" }
        def.position = { point = "CENTER", relPoint = "BOTTOMLEFT", x = x, y = y }
    end
    self:SaveGroups()
    -- Which way the rows run can have changed with the edge, so the
    -- header is configured again rather than only re-anchored.
    self:ApplySettings()
end

function addon:ShowGroupMovers()
    for _, entry in ipairs(GROUPS) do
        local frame = groupFrames[entry.key]
        if frame and frame.mover then frame.mover:ShowForEdit() end
    end
end

function addon:RefreshGroupEditSettings()
    for _, entry in ipairs(GROUPS) do
        local frame = groupFrames[entry.key]
        if frame and frame.mover then
            BazUI:UpdateEditModeSettings(frame.mover, self:GroupEditSettings(entry))
        end
    end
end

-- The same form the options page offers, for selecting a group in Edit
-- Mode. Everything about where a group sits is here; what its icons look
-- like is shared by all four and stays on the module's page.
function addon:GroupEditSettings(entry)
    local def = self:GroupDef(entry.key)

    local function Refresh()
        addon:SaveGroups()
        addon:ApplySettings()
    end

    local dockOptions = { { label = "Floating", value = "float" } }
    local frame = groupFrames[entry.key]
    for _, host in ipairs(BazUI.Dock:GetHosts()) do
        local hostFrame = BazUI.Dock:GetHostFrame(host.id)
        if hostFrame and hostFrame ~= frame then
            dockOptions[#dockOptions + 1] = { label = host.label, value = host.id }
        end
    end

    local function Values(map)
        local out = {}
        for value, label in pairs(map) do
            out[#out + 1] = { label = label, value = value }
        end
        table.sort(out, function(a, b) return a.label < b.label end)
        return out
    end

    local widgets = {
        { type = "dropdown", section = "Docking", label = "Dock to",
          options = dockOptions,
          get = function() return (def.dock and def.dock.host) or "float" end,
          set = function(value)
              def.dock = { host = value, edge = (def.dock and def.dock.edge) or "BOTTOM" }
              Refresh()
              addon:RefreshGroupEditSettings()
          end },
    }

    if def.dock and def.dock.host and def.dock.host ~= "float" then
        widgets[#widgets + 1] = { type = "dropdown", section = "Docking", label = "On the",
            options = Values(addon.GROUP_EDGES),
            get = function() return (def.dock and def.dock.edge) or "BOTTOM" end,
            set = function(value)
                def.dock = { host = (def.dock and def.dock.host) or "float", edge = value }
                Refresh()
            end }
        widgets[#widgets + 1] = { type = "dropdown", section = "Docking", label = "Aligned",
            options = Values(addon.GROUP_ALIGNS),
            get = function() return def.align or "LEFT" end,
            set = function(value) def.align = value Refresh() end }
        widgets[#widgets + 1] = { type = "slider", section = "Docking", label = "Gap",
            min = 0, max = 24, step = 1,
            get = function() return def.gap or 4 end,
            set = function(value) def.gap = value Refresh() end }
    end

    widgets[#widgets + 1] = { type = "nudge", section = "Position" }
    return widgets
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
-- Icon and dispel type, so the rim colours show.
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

local function LayoutDemo()
    local size   = addon:GetSetting("iconSize") or 26
    local perRow = addon:GetSetting("perRow") or 8
    local count  = perRow * DEMO_ROWS
    local now    = GetTime()
    local used   = 0
    local sides = {
        { headers.HELPFUL,        DEMO_BUFFS,   false },
        { headers.HARMFUL,        DEMO_DEBUFFS, true  },
        { headers.TARGET_HELPFUL, DEMO_BUFFS,   false },
        { headers.TARGET_HARMFUL, DEMO_DEBUFFS, true  },
    }
    for _, side in ipairs(sides) do
        local h, icons, harmful = side[1], side[2], side[3]
        if h and h:GetNumPoints() > 0 then
            local point = h:GetAttribute("point") or "BOTTOMLEFT"
            local xOff  = h:GetAttribute("xOffset") or 0
            local yWrap = h:GetAttribute("wrapYOffset") or 0
            local wrap  = math.max(1, h:GetAttribute("wrapAfter") or perRow)
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
                btn.Duration:SetFont(BazUI.Skin.Theme.FontFile(), math.max(8, math.floor(px * 0.42)), "OUTLINE")
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
function addon:SetPreview(on)
    if on == nil then on = not demoActive end
    demoActive = on and true or false
    if demoActive then
        if not demoFrame then
            demoFrame = CreateFrame("Frame", "BazUIAurasPreview", UIParent)
            demoFrame:SetFrameStrata("MEDIUM")
            demoFrame:SetSize(1, 1)
            demoFrame:SetPoint("CENTER")
        end
        LayoutDemo()
        demoFrame:Show()
        BazUI:Print("Auras preview on. It turns off when combat starts, or type /bazauras preview.")
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
    -- A group is only as wide as the icons in it, which is what its
    -- alignment measures from. Resizing an ordinary frame is not
    -- protected, so a row centred under a bar stays centred mid-fight.
    self:SizeGroups()
end

function addon:QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        addon:RefreshAll()
    end)
end

function addon:ApplySettings()
    if not headers.HELPFUL then return end
    if InCombatLockdown() then
        pendingApply = true
        return
    end
    pendingApply = false
    local enabled = self:GetSetting("enabled") ~= false
    local targetOn = enabled and self:GetSetting("targetEnabled") ~= false

    for _, entry in ipairs(GROUPS) do
        ConfigureHeader(entry, RowsBelow(self:GroupDef(entry.key)))
    end
    self:ApplyGroups()

    for btn in pairs(buttons) do
        Auras.ApplyButtonSize(btn)
        -- Buttons that already exist get the same treatment as new ones.
        if ButtonUnit(btn) ~= "player" and btn:GetAttribute("type2") then
            btn:SetAttribute("type2", nil)
        end
    end
    headers.HELPFUL:SetShown(enabled)
    headers.HARMFUL:SetShown(enabled)
    headers.TARGET_HELPFUL:SetShown(targetOn)
    headers.TARGET_HARMFUL:SetShown(targetOn)

    -- Through the dock, so a group hanging off something hidden goes
    -- with it rather than floating on its own over the screen.
    for _, entry in ipairs(GROUPS) do
        local frame = self:GroupFrame(entry.key)
        if frame then
            BazUI.Dock:SetShown(frame, entry.unit == "target" and targetOn or enabled)
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
    if headers.HELPFUL then return end
    -- Secure frames must not be created in combat.
    if InCombatLockdown() then
        self:On("PLAYER_REGEN_ENABLED", function()
            if not headers.HELPFUL then self:Initialize() end
        end)
        return
    end

    hiddenParent = CreateFrame("Frame")
    hiddenParent:Hide()
    CreateHeader("HELPFUL", "player", "HELPFUL", "BazUIAurasBuffs")
    CreateHeader("HARMFUL", "player", "HARMFUL", "BazUIAurasDebuffs")
    CreateHeader("TARGET_HELPFUL", "target", "HELPFUL", "BazUIAurasTargetBuffs")
    CreateHeader("TARGET_HARMFUL", "target", "HARMFUL", "BazUIAurasTargetDebuffs")
    -- A secure nudge when the target dies or is revived: the attribute
    -- change makes the header re-run its update, hiding a dead unit's
    -- leftover buttons even if no aura event follows.
    for _, key in ipairs({ "TARGET_HELPFUL", "TARGET_HARMFUL" }) do
        RegisterAttributeDriver(headers[key], "state-targetdead", "[@target,dead] 1; 0")
    end

    -- Every header lives inside a group frame, which is the thing that
    -- docks and the thing Edit Mode moves.
    for _, entry in ipairs(GROUPS) do CreateGroup(entry) end

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

    self:On("UNIT_AURA", function(_, unit)
        if unit == "player" or unit == "target" then self:QueueRefresh() end
    end)
    self:On("PLAYER_TARGET_CHANGED", function() self:QueueRefresh() end)
    self:On("UNIT_INVENTORY_CHANGED", function(_, unit)
        if unit == "player" then self:QueueRefresh() end
    end)
    self:On("PLAYER_ENTERING_WORLD", function() self:QueueRefresh() end)
    self:On("PLAYER_REGEN_ENABLED", function()
        if pendingApply then self:ApplySettings() end
    end)
    self:On("PLAYER_REGEN_DISABLED", function()
        if demoActive then self:SetPreview(false) end
    end)
    self:OnProfileChanged(function() self:ApplySettings() end)

    self:On("BAZ_EDITMODE_ENTER", function()
        self:RefreshGroupEditSettings()
        self:ShowGroupMovers()
    end)
    self:On("BAZ_EDITMODE_EXIT", function() self:ShowGroupMovers() end)

    -- Follow the unit frames: a bar a group is docked to can move or
    -- resize, and the dock passes that down, but a group floating beside
    -- one still wants re-applying after the bars settle.
    local uf = BazUI:GetModule("UnitFrames")
    if uf and uf.ApplySettings then
        hooksecurefunc(uf, "ApplySettings", function() addon:QueueApply() end)
    end

    self:ApplySettings()
end
