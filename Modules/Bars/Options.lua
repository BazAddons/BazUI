-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Bars: options pages
--
-- General     - what applies to every bar: Blizzard's own bar, button
--               text and tooltips, "same on every bar" values, combat.
-- Bar Options - a picker of your bars with New, Duplicate and Delete on
--               the row and the selected bar's form beneath it.
---------------------------------------------------------------------------

local BazBars = BazUI.Bars
local addon = BazUI:GetModule("Bars")
local Options = {}
addon.Options = Options

local MODULE_KEY   = "Bars"
local PAGE_GENERAL = "BazUIBars-Settings"
local PAGE_BARS    = "BazUIBars-Bars"

local function Profile()
    return addon.db and addon.db.profile
end

local function Refresh(page)
    if BazUI.RefreshOptions then BazUI:RefreshOptions(page) end
end

---------------------------------------------------------------------------
-- "Same on every bar"
--
-- An override forces one value onto every bar; each bar's own setting
-- is grayed out while it is on and comes back when it is turned off.
-- The bar helpers (SetScale, Resize, SetBarAlpha) save whatever value
-- they apply, so applying an override runs them with the bar's own
-- values snapshotted and restored around the call.
---------------------------------------------------------------------------

local OVERRIDES = {
    { key = "scale",       label = "Same icon size on every bar",    valueLabel = "Icon size",
      type = "range", default = 1, min = BazBars.MIN_SCALE, max = BazBars.MAX_SCALE, step = 0.05, isPercent = true },
    { key = "spacing",     label = "Same icon padding on every bar", valueLabel = "Icon padding",
      type = "range", default = BazBars.DEFAULT_SPACING, min = 0, max = 20, step = 1 },
    { key = "alpha",       label = "Same opacity on every bar",      valueLabel = "Bar opacity",
      type = "range", default = 1, min = 0, max = 1, step = 0.05, isPercent = true },
    { key = "showSlotArt", label = "Same slot art on every bar",     valueLabel = "Show slot art",
      type = "toggle", default = true },
}
-- Offered as overrides in older builds; per bar only now.
local DROPPED_OVERRIDES = { "alwaysShowButtons", "mouseoverFade", "clickThrough" }

local function Overrides()
    local p = Profile()
    if not p then return {} end
    p.globalOverrides = p.globalOverrides or {}
    return p.globalOverrides
end

local function Override(key)
    local o = Overrides()
    o[key] = o[key] or { enabled = false }
    return o[key]
end

-- Runs fn with the bar helpers free to write, then puts the bar's own
-- scale / spacing / alpha back so an override never overwrites them.
local function KeepingOwnValues(frame, bd, fn)
    local own = { scale = bd.scale, spacing = bd.spacing, alpha = bd.alpha }
    fn()
    for k, v in pairs(own) do bd[k] = v end
    if frame.barData and frame.barData ~= bd then
        for k, v in pairs(own) do frame.barData[k] = v end
    end
end

local function ApplyBarLook(frame, bd)
    KeepingOwnValues(frame, bd, function()
        addon.Bar:SetScale(frame, BazBars.GetBarSetting(bd, "scale") or 1)
        addon.Bar:Resize(frame, bd.rows, bd.cols, BazBars.GetBarSetting(bd, "spacing") or BazBars.DEFAULT_SPACING)
        addon.Bar:SetBarAlpha(frame, BazBars.GetBarSetting(bd, "alpha") or 1)
    end)
    addon.Bar:UpdateSlotArt(frame)
end

local function ApplyToAllBars()
    local p = Profile()
    if not p then return end
    for id, bd in pairs(p.bars or {}) do
        local frame = addon.Bar:Get(id)
        if frame and type(bd) == "table" then ApplyBarLook(frame, bd) end
    end
end

---------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------

local function GetGeneralOptionsTable()
    local p = Profile() or {}
    local args = {
        blizzardHeader = { order = 10, type = "header", name = "Blizzard UI" },
        hideDefaultActionBar = {
            order = 11, type = "toggle", name = "Hide Blizzard's main action bar",
            desc = "Keys 1 to 12 still work; only the bar is hidden. In combat the change waits until combat ends.",
            get = function() return p.hideDefaultActionBar == true end,
            set = function(_, val)
                p.hideDefaultActionBar = val
                if addon.ApplyDefaultBarVisibility then addon:ApplyDefaultBarVisibility() end
                Refresh(PAGE_GENERAL)
            end,
        },
        hideDefaultActionBarArt = {
            order = 12, type = "toggle", name = "Hide only its art",
            desc = "Keeps Blizzard's buttons and drops the gryphons and frame around them.",
            get = function() return p.hideDefaultActionBarArt == true end,
            set = function(_, val)
                p.hideDefaultActionBarArt = val
                if addon.ApplyDefaultBarVisibility then addon:ApplyDefaultBarVisibility() end
            end,
            disabled = function() return p.hideDefaultActionBar == true end,
        },
        hideStanceBar = {
            order = 13, type = "toggle", name = "Hide Blizzard's stance bar",
            desc = "Stances and forms live on a BazUI bar instead; a new character's are placed there for you.",
            get = function() return p.hideStanceBar ~= false end,
            set = function(_, val)
                p.hideStanceBar = val
                if addon.ApplyDefaultBarVisibility then addon:ApplyDefaultBarVisibility() end
            end,
        },

        buttonsHeader = { order = 20, type = "header", name = "Buttons" },
        fullRangeColor = {
            order = 21, type = "toggle", name = "Tint the whole button when out of range",
            desc = "Off tints only the keybind text.",
            get = function() return p.fullRangeColor ~= false end,
            set = function(_, val) p.fullRangeColor = val end,
        },
        showKeybindText = {
            order = 22, type = "toggle", name = "Show keybind text",
            get = function() return p.showKeybindText ~= false end,
            set = function(_, val)
                p.showKeybindText = val
                for _, frame in pairs(addon.Bar:GetAll()) do
                    for _, row in pairs(frame.buttons) do
                        for _, btn in pairs(row) do
                            if btn.HotKey then
                                btn.HotKey:SetShown(val and btn.HotKey:GetText() ~= "")
                            end
                        end
                    end
                end
            end,
        },
        showMacroNames = {
            order = 23, type = "toggle", name = "Show macro names",
            get = function() return p.showMacroNames ~= false end,
            set = function(_, val)
                p.showMacroNames = val
                for _, frame in pairs(addon.Bar:GetAll()) do
                    for _, row in pairs(frame.buttons) do
                        for _, btn in pairs(row) do
                            if btn.Name then
                                local isMacro = btn.action and btn.action.type == "macro"
                                btn.Name:SetShown(val and isMacro)
                            end
                        end
                    end
                end
            end,
        },
        dragRequiresShift = {
            order = 23.5, type = "toggle", name = "Drag buttons only while Shift is held",
            desc = "A plain drag does nothing, so a slip can't pull an ability off a bar. Dropping onto a bar still works.",
            get = function() return p.dragRequiresShift == true end,
            set = function(_, val) p.dragRequiresShift = val end,
        },
        showTooltips = {
            order = 24, type = "toggle", name = "Show tooltips",
            get = function() return p.showTooltips ~= false end,
            set = function(_, val)
                p.showTooltips = val
                Refresh(PAGE_GENERAL)
            end,
        },
        tooltipAnchor = {
            order = 25, type = "select", name = "Tooltip position",
            values = { default = "Bottom right of the screen", button = "Next to the button" },
            sorting = { "default", "button" },
            get = function() return p.tooltipAnchor or "default" end,
            set = function(_, val) p.tooltipAnchor = val end,
            disabled = function() return p.showTooltips == false end,
        },

        allBarsHeader = { order = 30, type = "header", name = "All bars" },
        allBarsDesc = {
            order = 31, type = "description",
            name = "Force one value on every bar. A bar's own setting is grayed out while its override is on.",
        },

        abilitiesHeader = { order = 44, type = "header", name = "Abilities" },
        autoFill = {
            order = 45, type = "toggle", name = "Put a new character's abilities on the bars",
            desc = "On its first login: forms and stances on the first side bar, everything else on the main bar.",
            get = function() return p.autoFill ~= false end,
            set = function(_, val) p.autoFill = val end,
        },
        autoPlaceNew = {
            order = 46, type = "toggle", name = "Add newly learned spells to the first empty slot",
            get = function() return p.autoPlaceNew ~= false end,
            set = function(_, val) p.autoPlaceNew = val end,
        },
        fillNow = {
            order = 47, type = "execute", name = "Fill empty slots with my unplaced abilities",
            func = function()
                if InCombatLockdown() then
                    addon:Print("Wait until combat ends to fill the bars.")
                    return
                end
                local n = addon.AutoFill and addon.AutoFill:Fill() or 0
                addon:Print(n > 0 and ("Placed %d abilities."):format(n) or "Everything you know is already on a bar, or there are no empty slots.")
            end,
        },

        combatHeader = { order = 50, type = "header", name = "Combat" },
        combatDesc = {
            order = 51, type = "description",
            name = "BazUI bars always cast on key release. This applies to Blizzard's own bars.",
        },
        castOnKeyDown = {
            order = 52, type = "toggle", name = "Blizzard bars cast on key down",
            desc = "Needed for hold-to-cast features.",
            get = function() return GetCVarBool("ActionButtonUseKeyDown") end,
            set = function(_, val) SetCVar("ActionButtonUseKeyDown", val and "1" or "0") end,
        },
    }

    for i, def in ipairs(OVERRIDES) do
        local key = def.key
        args["same_" .. key] = {
            order = 31 + i * 2, type = "toggle", name = def.label,
            get = function() return Override(key).enabled == true end,
            set = function(_, val)
                local o = Override(key)
                o.enabled = val
                if o.value == nil then o.value = def.default end
                ApplyToAllBars()
                Refresh(PAGE_GENERAL)
                Refresh(PAGE_BARS)
            end,
        }
        local value = {
            order = 32 + i * 2, type = def.type, name = def.valueLabel,
            min = def.min, max = def.max, step = def.step, isPercent = def.isPercent,
            hidden = function() return Override(key).enabled ~= true end,
            set = function(_, val)
                Override(key).value = val
                ApplyToAllBars()
            end,
        }
        if def.type == "toggle" then
            value.get = function()
                local v = Override(key).value
                if v == nil then return def.default end
                return v ~= false
            end
        else
            value.get = function()
                local v = Override(key).value
                if v == nil then return def.default end
                return v
            end
        end
        args["value_" .. key] = value
    end

    return { name = "General", type = "group", args = args }
end

---------------------------------------------------------------------------
-- Bar Options
---------------------------------------------------------------------------

local function BarLabel(id, bd)
    local name = bd.customName or ("Bar " .. id)
    return string.format("%s  (%d x %d)", name, bd.cols or 0, bd.rows or 0)
end

local function BuildBarArgs(id, bd)
    local function Frame() return addon.Bar:Get(id) end
    local function Overridden(key) return BazBars.IsGlobalOverrideActive(key) end
    local function OverrideDesc(key)
        if Overridden(key) then return "Set for every bar under General." end
    end
    local function EndcapsOff()
        return (BazBars.GetBarSetting(bd, "endcaps") or "off") == "off"
    end

    return {
        layoutHeader = { order = 10, type = "header", name = "Layout" },
        customName = {
            order = 11, type = "input", name = "Name",
            get = function() return bd.customName or "" end,
            set = function(_, val)
                bd.customName = (val ~= "") and val or nil
                local frame = Frame()
                if frame then addon.Bar:SetCustomName(frame, bd.customName) end
                Refresh(PAGE_BARS)
            end,
        },
        orientation = {
            order = 12, type = "select", name = "Orientation",
            values = { horizontal = "Horizontal", vertical = "Vertical" },
            sorting = { "horizontal", "vertical" },
            get = function() return bd.orientation or "horizontal" end,
            set = function(_, val)
                bd.orientation = val
                local frame = Frame()
                if frame then addon.Bar:LayoutButtons(frame, bd) end
            end,
        },
        cols = {
            order = 13, type = "range", name = "Icons per row",
            min = 1, max = BazBars.MAX_COLS, step = 1,
            get = function() return bd.cols end,
            set = function(_, val)
                local frame = Frame()
                if frame then
                    KeepingOwnValues(frame, bd, function()
                        addon.Bar:Resize(frame, bd.rows, val, BazBars.GetBarSetting(bd, "spacing"))
                    end)
                end
                bd.cols = val
                Refresh(PAGE_BARS)
            end,
        },
        rows = {
            order = 14, type = "range", name = "Rows",
            min = 1, max = BazBars.MAX_ROWS, step = 1,
            get = function() return bd.rows end,
            set = function(_, val)
                local frame = Frame()
                if frame then
                    KeepingOwnValues(frame, bd, function()
                        addon.Bar:Resize(frame, val, bd.cols, BazBars.GetBarSetting(bd, "spacing"))
                    end)
                end
                bd.rows = val
                Refresh(PAGE_BARS)
            end,
        },

        appearanceHeader = { order = 20, type = "header", name = "Appearance" },
        scale = {
            order = 21, type = "range", name = "Icon size", desc = OverrideDesc("scale"),
            min = BazBars.MIN_SCALE, max = BazBars.MAX_SCALE, step = 0.05, isPercent = true,
            get = function() return BazBars.GetBarSetting(bd, "scale") or 1 end,
            set = function(_, val)
                bd.scale = val
                local frame = Frame()
                if frame then addon.Bar:SetScale(frame, val) end
            end,
            disabled = function() return Overridden("scale") end,
        },
        spacing = {
            order = 22, type = "range", name = "Icon padding", desc = OverrideDesc("spacing"),
            min = 0, max = 20, step = 1,
            get = function() return BazBars.GetBarSetting(bd, "spacing") or BazBars.DEFAULT_SPACING end,
            set = function(_, val)
                bd.spacing = val
                local frame = Frame()
                if frame then addon.Bar:Resize(frame, bd.rows, bd.cols, val) end
            end,
            disabled = function() return Overridden("spacing") end,
        },
        alpha = {
            order = 23, type = "range", name = "Bar opacity", desc = OverrideDesc("alpha"),
            min = 0, max = 1, step = 0.05, isPercent = true,
            get = function() return BazBars.GetBarSetting(bd, "alpha") or 1 end,
            set = function(_, val)
                bd.alpha = val
                local frame = Frame()
                if frame then addon.Bar:SetBarAlpha(frame, val) end
            end,
            disabled = function() return Overridden("alpha") end,
        },
        endcaps = {
            order = 24, type = "select", name = "Side endcaps",
            values = { off = "None", alliance = "Alliance gryphons", horde = "Horde wyverns" },
            sorting = { "off", "alliance", "horde" },
            get = function() return BazBars.GetBarSetting(bd, "endcaps") or "off" end,
            set = function(_, val)
                bd.endcaps = val
                local frame = Frame()
                if frame then addon.Bar:ApplyEndcaps(frame) end
                Refresh(PAGE_BARS)
            end,
        },
        endcapsAutoScale = {
            order = 25, type = "toggle", name = "Scale endcaps with the bar's height",
            hidden = EndcapsOff,
            get = function() return BazBars.GetBarSetting(bd, "endcapsAutoScale") == true end,
            set = function(_, val)
                bd.endcapsAutoScale = val
                local frame = Frame()
                if frame then addon.Bar:ApplyEndcaps(frame) end
                Refresh(PAGE_BARS)
            end,
        },
        endcapsScale = {
            order = 26, type = "range", name = "Endcap size",
            min = 0.5, max = 2, step = 0.05, isPercent = true,
            hidden = function() return EndcapsOff() or BazBars.GetBarSetting(bd, "endcapsAutoScale") == true end,
            get = function() return BazBars.GetBarSetting(bd, "endcapsScale") or 1 end,
            set = function(_, val)
                bd.endcapsScale = val
                local frame = Frame()
                if frame then addon.Bar:ApplyEndcaps(frame) end
            end,
        },

        visibilityHeader = { order = 30, type = "header", name = "Visibility" },
        alwaysShowButtons = {
            order = 31, type = "toggle", name = "Always show buttons",
            desc = "Off hides empty slots until you drag something onto them.",
            get = function() return BazBars.GetBarSetting(bd, "alwaysShowButtons") ~= false end,
            set = function(_, val)
                bd.alwaysShowButtons = val
                local frame = Frame()
                if frame then addon.Bar:UpdateButtonVisibility(frame) end
            end,
        },
        showSlotArt = {
            order = 32, type = "toggle", name = "Show slot art", desc = OverrideDesc("showSlotArt"),
            get = function() return BazBars.GetBarSetting(bd, "showSlotArt") ~= false end,
            set = function(_, val)
                bd.showSlotArt = val
                local frame = Frame()
                if frame then addon.Bar:UpdateSlotArt(frame) end
            end,
            disabled = function() return Overridden("showSlotArt") end,
        },
        mouseoverFade = {
            order = 33, type = "toggle", name = "Fade until hovered",
            get = function() return BazBars.GetBarSetting(bd, "mouseoverFade") == true end,
            set = function(_, val)
                bd.mouseoverFade = val
                local frame = Frame()
                if frame then addon.Bar:ApplyMouseoverFade(frame) end
            end,
        },
        visibilityMacro = {
            order = 34, type = "input", name = "Show when",
            desc = "A macro condition such as [combat] show; hide. Empty means always.",
            get = function() return bd.visibilityMacro or "" end,
            set = function(_, val)
                bd.visibilityMacro = val
                local frame = Frame()
                if frame then addon.Bar:SetVisibilityMacro(frame, val) end
            end,
        },

        behaviorHeader = { order = 40, type = "header", name = "Behavior" },
        locked = {
            order = 41, type = "toggle", name = "Lock buttons",
            desc = "Buttons can't be dragged off or swapped.",
            get = function() return bd.locked == true end,
            set = function(_, val) bd.locked = val end,
        },
        rightClickSelfCast = {
            order = 42, type = "toggle", name = "Right-click casts on yourself",
            get = function() return bd.rightClickSelfCast == true end,
            set = function(_, val)
                bd.rightClickSelfCast = val
                local frame = Frame()
                if frame then addon.Button:ApplySelfCast(frame) end
            end,
        },
        clickThrough = {
            order = 43, type = "toggle", name = "Click-through",
            desc = "Buttons ignore the mouse. Cooldowns, range tint and glows still show.",
            get = function() return BazBars.GetBarSetting(bd, "clickThrough") == true end,
            set = function(_, val)
                bd.clickThrough = val
                local frame = Frame()
                if frame then addon.Bar:ApplyClickThrough(frame) end
            end,
        },
    }
end

local function GetBarsOptionsTable()
    local p = Profile()
    local bars = {}
    for id, bd in pairs(p and p.bars or {}) do
        if type(bd) == "table" then
            bars["bar" .. id] = {
                order = id,
                type = "group",
                name = BarLabel(id, bd),
                args = BuildBarArgs(id, bd),
                _barId = id,
            }
        end
    end

    return {
        name = "Bar Options",
        type = "group",
        args = {
            newBar = {
                order = 1, type = "execute", name = "New bar",
                func = function()
                    if InCombatLockdown() then
                        addon:Print("Cannot create bars during combat.")
                        return
                    end
                    local id = addon:CreateNewBar()
                    if id then addon:Print("Created Bar " .. id) end
                end,
            },
            bars = {
                order = 10,
                type = "group",
                name = "",
                pickerLabel = "Bar",
                emptyText = "No bars yet. Click New bar to make one.",
                args = bars,
                itemActions = {
                    {
                        name = "Duplicate",
                        func = function(item) addon:DuplicateBar(item._barId) end,
                    },
                    {
                        name = "Delete", style = "danger",
                        confirm = true, confirmTitle = "Delete bar?",
                        confirmText = function(item)
                            return string.format("Delete %s? This removes the bar and every button on it and can't be undone.",
                                item and item.name or "this bar")
                        end,
                        confirmStyle = "destructive", confirmAcceptLabel = "Delete", confirmCancelLabel = "Cancel",
                        func = function(item) addon:DeleteBar(item._barId) end,
                    },
                },
            },
        },
    }
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

function Options:Setup()
    local o = Profile() and Profile().globalOverrides
    if o then
        for _, key in ipairs(DROPPED_OVERRIDES) do o[key] = nil end
    end

    -- The module entry itself never renders: its pages are tabs.
    BazUI:RegisterOptionsTable(MODULE_KEY, function()
        return { name = "Bars", type = "group", args = {} }
    end)
    BazUI:AddToSettings(MODULE_KEY, "Bars")

    BazUI:RegisterOptionsTable(PAGE_GENERAL, GetGeneralOptionsTable)
    BazUI:AddToSettings(PAGE_GENERAL, "General", MODULE_KEY)

    BazUI:RegisterOptionsTable(PAGE_BARS, GetBarsOptionsTable)
    BazUI:AddToSettings(PAGE_BARS, "Bar Options", MODULE_KEY)
end

-- Called after a bar is created, duplicated or deleted.
function Options:Refresh()
    Refresh(PAGE_BARS)
end

function Options:Open()
    BazUI:OpenOptionsPanel(MODULE_KEY)
end
