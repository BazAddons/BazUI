-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Bars: options pages
--
-- General - what applies to every bar: Blizzard's own bar, button text
--           and tooltips, "same on every bar" values, combat.
--
-- One page, not two. A bar's own settings live in its inspector in BazUI
-- Edit Mode and nowhere else; see the note further down about the page
-- that used to be here.
---------------------------------------------------------------------------

local BazBars = BazUI.Bars
local addon = BazUI:GetModule("Bars")
local Options = {}
addon.Options = Options

local MODULE_KEY   = "Bars"
local PAGE_GENERAL = "BazUIBars-Settings"

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
        stockXP = {
            order = 14, type = "toggle", name = "Show Blizzard's experience bar",
            desc = "Off by default, and stays off whether or not you have an experience bar of your own. It lives in the furniture around Blizzard's action bar, which is why it is here.",
            get = function() return p.stockXP == true end,
            set = function(_, val)
                p.stockXP = val and true or false
                if addon.ApplyStatusBarVisibility then addon:ApplyStatusBarVisibility() end
            end,
        },
        stockRep = {
            order = 15, type = "toggle", name = "Show Blizzard's reputation bar",
            desc = "As above, for reputation. The two share one container, so it only goes away when neither is wanted.",
            get = function() return p.stockRep == true end,
            set = function(_, val)
                p.stockRep = val and true or false
                if addon.ApplyStatusBarVisibility then addon:ApplyStatusBarVisibility() end
            end,
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
        dropCreatesBar = {
            order = 23.6, type = "toggle", name = "Drop on the world to make a bar",
            desc = "Drag an ability out of the spellbook and let go anywhere: "
                .. "a bar appears there holding it, or it joins a bar you "
                .. "dropped it beside. Pulling something off a bar and "
                .. "dropping it still just clears the slot.",
            get = function() return p.dropCreatesBar ~= false end,
            set = function(_, val) p.dropCreatesBar = val end,
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
                Refresh(PAGE_GENERAL)
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
-- There is no Bar Options page.
--
-- There was, and it said the same things as the bar's own inspector in
-- BazUI Edit Mode: two forms over one set of values, either of which
-- could be the one you had open when you changed the other. A setting
-- with two homes has no home.
--
-- The inspector won because it is the one you reach by clicking the bar
-- you mean, with that bar in front of you while you change it - and it
-- was already the only place for the things that never fitted a form,
-- like nudging a bar a pixel or reading its keybinds.
--
-- Nothing was lost with the page. Every setting on it is in the
-- inspector; New bar is on Edit Mode's own add menu; Duplicate and
-- Delete are in the bar's context menu, with the same confirmation.
--
-- What remains here is the General page: the global defaults and the
-- overrides that make one value apply to every bar, which are about the
-- bars together rather than about one of them.
---------------------------------------------------------------------------
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

end

-- Called after a bar is created, duplicated or deleted. The General page
-- counts bars in a couple of places, so it is redrawn if it is up.
function Options:Refresh()
    Refresh(PAGE_GENERAL)
end

function Options:Open()
    BazUI:OpenOptionsPanel(MODULE_KEY)
end
