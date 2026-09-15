-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Auras: settings page
--
-- One spec feeds the Options panel (Options > AddOns > BazUI > Auras).
-- Every change re-applies live; anything that touches the secure
-- headers waits for combat to end.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("Auras")
local MODULE_NAME = addon.MODULE_NAME

local function Get(key)
    return function() return addon:GetSetting(key) end
end

local function Set(key)
    return function(_, value)
        addon:SetSetting(key, value)
        addon:ApplySettings()
    end
end

-- Toggles default to true, so nil reads as on.
local function GetBool(key)
    return function() return addon:GetSetting(key) ~= false end
end

local function SetBool(key)
    return function(_, value)
        addon:SetSetting(key, value and true or false)
        addon:ApplySettings()
    end
end

BazUI:RegisterSettingsSpec(MODULE_NAME, {
    sections = {
        general = { label = "",        order = 1 },
        layout  = { label = "Layout",  order = 2 },
        icons   = { label = "Icons",   order = 4 },
        sorting = { label = "Sorting", order = 5 },
    },
    entries = {
        { key = "enabled", label = "Show BazUI auras", type = "toggle", section = "general", order = 1,
          desc = "Draw your buffs and debuffs on the player frame.",
          get = GetBool("enabled"), set = SetBool("enabled") },
        { key = "hideBlizzard", label = "Hide Blizzard's buff and debuff frames", type = "toggle", section = "general", order = 2,
          desc = "Park the stock frames by the minimap while BazUI auras are shown. Turn off to keep both.",
          get = GetBool("hideBlizzard"), set = SetBool("hideBlizzard") },

        { key = "perRow", label = "Icons per row", type = "slider", section = "layout", order = 1,
          desc = "Used by every row that has not been given one of its own on the Rows page.",
          min = 4, max = 16, step = 1, get = Get("perRow"), set = Set("perRow") },
        { key = "iconSize", label = "Icon size", type = "slider", section = "layout", order = 2,
          desc = "Used by every row that has not been given one of its own.",
          min = 16, max = 40, step = 1, get = Get("iconSize"), set = Set("iconSize") },
        { key = "spacing", label = "Spacing", type = "slider", section = "layout", order = 3,
          desc = "Pixels between icons, and between rows. Used by every row that has not been given its own.",
          min = 0, max = 10, step = 1, get = Get("spacing"), set = Set("spacing") },
        { key = "preview", label = "Preview a full spread of auras", type = "execute", section = "layout", order = 6,
          desc = "Three rows of made-up icons on every side. Ends when combat starts.",
          hidden = function() return addon:IsPreviewing() end,
          func = function() addon:SetPreview(true) end },
        { key = "previewOff", label = "Hide the preview", type = "execute", section = "layout", order = 6,
          desc = "Three rows of made-up icons on every side. Ends when combat starts.",
          hidden = function() return not addon:IsPreviewing() end,
          func = function() addon:SetPreview(false) end },
        { key = "reset", label = "Reset layout", type = "execute", section = "layout", order = 7,
          func = function() addon:ResetLayout() end },

        { key = "showDuration", label = "Time remaining on icons", type = "toggle", section = "icons", order = 1,
          get = GetBool("showDuration"), set = SetBool("showDuration") },
        { key = "showCount", label = "Stack counts", type = "toggle", section = "icons", order = 2,
          get = GetBool("showCount"), set = SetBool("showCount") },
        { key = "debuffBorders", label = "Color debuff rims by type", type = "toggle", section = "icons", order = 3,
          desc = "Blue for Magic, purple for Curse, brown for Disease, green for Poison, red for everything else. Off keeps every debuff rim red.",
          get = GetBool("debuffBorders"), set = SetBool("debuffBorders") },
        { key = "showWeapons", label = "Weapon enchants with the buffs", type = "toggle", section = "icons", order = 4,
          desc = "Show poisons, sharpening stones and other temporary weapon enchants as buff icons. Right-click removes them.",
          get = GetBool("showWeapons"), set = SetBool("showWeapons") },

        { key = "sortMethod", label = "Sort by", type = "select", section = "sorting", order = 1,
          values = { INDEX = "Order applied", TIME = "Time remaining", NAME = "Name" },
          get = Get("sortMethod"), set = Set("sortMethod") },
        { key = "sortDirection", label = "Direction", type = "select", section = "sorting", order = 2,
          values = { ["+"] = "Ascending", ["-"] = "Descending" },
          get = Get("sortDirection"), set = Set("sortDirection") },
    },
})

BazUI:QueueForLogin(function()
    -- The module entry itself never renders: its pages are tabs.
    BazUI:RegisterOptionsTable(MODULE_NAME, function()
        return { name = "Auras", type = "group", args = {} }
    end)
    BazUI:AddToSettings(MODULE_NAME, "Auras")

    BazUI:RegisterOptionsTable(MODULE_NAME .. "-Settings", function()
        return BazUI:BuildOptionsTableFromSpec(MODULE_NAME, { name = "General" })
    end)
    BazUI:AddToSettings(MODULE_NAME .. "-Settings", "General", MODULE_NAME)

    -- The rows you have made, each with its own form. A page rather
    -- than a section, because the list can be any length.
    BazUI:RegisterOptionsTable(MODULE_NAME .. "-Groups", function()
        return addon:BuildRowOptions()
    end)
    BazUI:AddToSettings(MODULE_NAME .. "-Groups", "Rows", MODULE_NAME)
end)

---------------------------------------------------------------------------
-- One row's form, in the shape the bars use: a list of the rows you have
-- made, New and Delete, and the selected one's own settings underneath.
---------------------------------------------------------------------------

local function DockValues(frame)
    local values = { float = "Floating" }
    for _, host in ipairs(BazUI.Dock:GetHosts()) do
        local hostFrame = BazUI.Dock:GetHostFrame(host.id)
        if hostFrame and hostFrame ~= frame then values[host.id] = host.label end
    end
    return values
end

local function RowArgs(def, index)
    local function Apply()
        addon:SaveRows()
        addon:ApplySettings()
    end

    local function Docked() return def.dock and def.dock.host ~= "float" end

    local function Field(key, fallback, after)
        return function(_, value)
            if InCombatLockdown() then
                addon:Print("Change the rows after combat ends.")
                return
            end
            def[key] = value
            Apply()
            if after then after(value) end
        end, function()
            local value = def[key]
            if value == nil then return fallback end
            return value
        end
    end

    local setPerRow            = Field("perRow", 8)
    local setIconSize          = Field("iconSize", 26)
    local setSpacing           = Field("spacing", 3)
    local setGrow              = Field("grow", "RIGHT")
    local setSortMethod        = Field("sortMethod", "INDEX")
    local setSortDirection     = Field("sortDirection", "+")
    local setAlign,  getAlign  = Field("align", "LEFT")
    local setGap,    getGap    = Field("gap", 4)
    local setMine,   getMine   = Field("onlyMine", false)
    local setUnit,   getUnit   = Field("unit", "player")
    local setFilter, getFilter = Field("filter", "HELPFUL")

    return {
        name = def.name or ("Row " .. def.id),
        type = "group",
        order = index,
        _rowId = def.id,
        args = {
            rowName = {
                order = 1, type = "input", name = "Name",
                get = function() return def.name or "" end,
                set = function(_, value)
                    def.name = (value ~= "" and value)
                        or addon:DefaultRowName(def.unit, def.filter)
                    Apply()
                end,
            },
            filter = {
                order = 2, type = "select", name = "Shows",
                values = addon.ROW_FILTERS,
                get = getFilter, set = setFilter,
            },
            unit = {
                order = 3, type = "select", name = "Of",
                values = addon.ROW_UNITS,
                get = getUnit, set = setUnit,
            },
            onlyMine = {
                order = 4, type = "toggle", name = "Only mine",
                desc = "Hide auras other players applied.",
                hidden = function() return def.unit == "player" end,
                get = getMine, set = setMine,
            },

            dockHeader = { order = 10, type = "header", name = "Docking" },
            dockHost = {
                order = 11, type = "select", name = "Dock to",
                desc = "Floating keeps it where you put it. Docked, it follows whatever it is attached to and hides when that hides.",
                values = function() return DockValues(addon:RowFrame(def.id)) end,
                get = function() return (def.dock and def.dock.host) or "float" end,
                set = function(_, value)
                    def.dock = { host = value, edge = (def.dock and def.dock.edge) or "BOTTOM" }
                    Apply()
                end,
            },
            dockEdge = {
                order = 12, type = "select", name = "On the",
                values = { BOTTOM = "Below", TOP = "Above" },
                hidden = function() return not Docked() end,
                get = function() return (def.dock and def.dock.edge) or "BOTTOM" end,
                set = function(_, value)
                    def.dock = { host = (def.dock and def.dock.host) or "float", edge = value }
                    Apply()
                end,
            },
            fill = {
                order = 13, type = "toggle", name = "Fill the width",
                desc = "The row spans whatever it is docked to, and the icons are sized to suit: icons per row decides how big they are. Off keeps the icons their own size and aligns the row to one end.",
                hidden = function() return not Docked() end,
                get = function() return def.fill == true end,
                set = function(_, value)
                    def.fill = value and true or false
                    Apply()
                end,
            },
            align = {
                order = 14, type = "select", name = "Aligned",
                desc = "Which end of its host the row starts from.",
                values = addon.ROW_ALIGNS,
                hidden = function() return not Docked() or def.fill end,
                get = getAlign, set = setAlign,
            },
            gap = {
                order = 15, type = "range", name = "Gap",
                desc = "Pixels between this row and what it is docked to.",
                min = 0, max = 24, step = 1,
                hidden = function() return not Docked() end,
                get = getGap, set = setGap,
            },

            sizeHeader = { order = 20, type = "header", name = "Icons" },
            iconSize = {
                order = 21, type = "range", name = "Icon size",
                desc = "This row only. Leave every row alone and they follow the size on the General page.",
                hidden = function() return def.fill and Docked() end,
                min = 12, max = 48, step = 1,
                get = function() return addon:RowValue(def, "iconSize") end,
                set = setIconSize,
            },
            spacing = {
                order = 22, type = "range", name = "Spacing",
                desc = "Pixels between icons, and between rows of them.",
                min = 0, max = 12, step = 1,
                get = function() return addon:RowValue(def, "spacing") end,
                set = setSpacing,
            },
            perRow = {
                order = 23, type = "range", name = "Icons per row",
                desc = "How many icons fill a row before the next one starts.",
                min = 1, max = 20, step = 1,
                get = function() return addon:RowValue(def, "perRow") end,
                set = setPerRow,
            },
            maxRows = {
                order = 24, type = "range", name = "Rows at most",
                desc = "Nought means as many rows as there are auras. One row is the usual choice for somebody else's debuffs: sixteen of them is a legal state of affairs, and a tower of icons is not what showing them meant.",
                min = 0, max = 6, step = 1,
                get = function() return def.maxRows or 0 end,
                set = function(_, value)
                    def.maxRows = (value > 0) and value or nil
                    Apply()
                end,
            },
            grow = {
                order = 25, type = "select", name = "Icons run",
                desc = "Which way the icons fill from the row's anchored end.",
                values = addon.ROW_GROWTH,
                get = function() return def.grow or "RIGHT" end,
                set = setGrow,
            },
            stack = {
                order = 26, type = "select", name = "Rows stack",
                desc = "Where a second row goes when the first fills up. Away from the dock keeps them off whatever the row is attached to.",
                values = addon.ROW_STACK,
                get = function() return def.stack or "AUTO" end,
                set = function(_, value)
                    def.stack = (value ~= "AUTO") and value or nil
                    Apply()
                end,
            },

            sortHeader = { order = 30, type = "header", name = "Sorting" },
            sortMethod = {
                order = 31, type = "select", name = "Sort by",
                values = addon.ROW_SORTS,
                get = function() return addon:RowValue(def, "sortMethod") end,
                set = setSortMethod,
            },
            sortDirection = {
                order = 32, type = "select", name = "Direction",
                values = addon.ROW_SORT_DIRECTIONS,
                get = function() return addon:RowValue(def, "sortDirection") end,
                set = setSortDirection,
            },
            note = {
                order = 40, type = "description",
                name = "Rows can also be made and dragged in Edit Mode: use Create, then drop one near the edge of a bar or an action bar to dock it there.",
            },
        },
    }
end

function addon:BuildRowOptions()
    local rows = {}
    for index, def in ipairs(self:Rows()) do
        rows["row" .. def.id] = RowArgs(def, index)
    end

    return {
        name = "Rows",
        type = "group",
        args = {
            newRow = {
                order = 1, type = "execute", name = "New row",
                func = function()
                    if InCombatLockdown() then
                        addon:Print("Create rows after combat ends.")
                        return
                    end
                    local def = addon:AddRow("player", "HELPFUL")
                    if def then addon:Print("Created " .. (def.name or "a row")) end
                end,
            },
            rows = {
                order = 10, type = "group", name = "",
                pickerLabel = "Row",
                emptyText = "No rows yet. Click New row to make one.",
                args = rows,
                itemActions = {
                    {
                        name = "Delete", style = "danger",
                        confirm = true, confirmTitle = "Delete row?",
                        confirmText = function(item)
                            return string.format("Delete %s? It can be made again from Create.",
                                item and item.name or "this row")
                        end,
                        confirmStyle = "destructive",
                        confirmAcceptLabel = "Delete", confirmCancelLabel = "Cancel",
                        func = function(item) addon:RemoveRow(item._rowId) end,
                    },
                },
            },
        },
    }
end
