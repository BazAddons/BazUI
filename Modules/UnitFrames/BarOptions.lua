-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Unit Frames: the bar picker
--
-- The same page an action bar gets: a list of the bars you have made,
-- New and Delete, and the selected one's own form underneath. Every
-- choice about a bar lives on the bar, including where it docks, which
-- is the difference between one dropdown per bar and a grid of them
-- describing every combination.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("UnitFrames")

local Options = {}

-- The bar the picker should open on its next render, set by the button
-- that just made one. See pickerSelect in Core/Options/ListDetail.
local pendingBar

local function TakePendingBar()
    return pendingBar
end

local function TakePendingBarTaken()
    pendingBar = nil
end
addon.BarOptions = Options

local TEXT_MODES = { always = "Always", hover = "On Hover", never = "Never" }
local FORMATS = {
    detailed        = "Everything",
    ["current/max"] = "Current / Max",
    current         = "Current",
    percent         = "Percent",
    name            = "Name",
    namePercent     = "Name and percent",
}
local EDGES = { BOTTOM = "Below", TOP = "Above" }
local TAKES = {
    full = "The whole width",
    half = "Half the width",
    own  = "Its own width",
}
local ALIGNS = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
local FILL_FROM = { LEFT = "The left", RIGHT = "The right" }

local function Bars()
    return addon.UnitBars
end

-- Everywhere this bar could be sent. Its own entry is left out, and so
-- is anything already hanging off it, which would be a loop.
local function DockValues(def)
    local UnitBars = Bars()
    local values = { float = "Floating" }
    local selfFrame = UnitBars.bars[def.id] and UnitBars.bars[def.id].frame

    for _, host in ipairs(BazUI.Dock:GetHosts()) do
        local frame = BazUI.Dock:GetHostFrame(host.id)
        if frame and frame ~= selfFrame
            and not (selfFrame and BazUI.Dock:Follows(frame, selfFrame)) then
            values[host.id] = host.label
        end
    end
    return values
end

local function Field(def, key, default)
    return function()
        local value = def[key]
        if value == nil then return default end
        return value
    end
end

local function SetField(def, key, after)
    return function(_, value)
        if InCombatLockdown() then
            addon:Print("Change the bars after combat ends.")
            return
        end
        def[key] = value
        Bars():Save()
        local bar = Bars().bars[def.id]
        if bar then Bars():Apply(bar) end
        if after then after(def, value) end
    end
end

---------------------------------------------------------------------------
-- One bar's form
---------------------------------------------------------------------------

local function BarArgs(def)
    local UnitBars = Bars()
    return {
        name = def.name or ("Bar " .. def.id),
        type = "group",
        _barId = def.id,
        args = {
            barName = {
                order = 1, type = "input", name = "Name",
                get = Field(def, "name", ""),
                set = function(_, value)
                    def.name = (value ~= "" and value) or UnitBars:DefaultName(def.kind, def.unit)
                    UnitBars:Save()
                    -- The name is also how this bar appears in every
                    -- other bar's docking list.
                    BazUI.Dock:RegisterHost(UnitBars:HostID(def.id),
                        UnitBars.bars[def.id] and UnitBars.bars[def.id].frame, def.name, 30)
                    local bar = UnitBars.bars[def.id]
                    if bar then UnitBars:Apply(bar) end
                end,
            },
            kind = {
                order = 2, type = "select", name = "Reads",
                values = UnitBars.KINDS,
                get = Field(def, "kind", "health"),
                set = SetField(def, "kind", function(d)
                    local bar = UnitBars.bars[d.id]
                    if bar then UnitBars:Update(bar) end
                end),
            },
            unit = {
                order = 3, type = "select", name = "Of",
                values = UnitBars.UNITS,
                hidden = function() return not UnitBars.IsUnitKind(def.kind) end,
                get = Field(def, "unit", "player"),
                set = SetField(def, "unit"),
            },
            dockHeader = { order = 10, type = "header", name = "Docking" },
            dockHost = {
                order = 11, type = "select", name = "Dock to",
                desc = "Floating keeps it where you put it. Docking makes it take the width of whatever it is attached to.",
                values = function() return DockValues(def) end,
                get = function() return (def.dock and def.dock.host) or "float" end,
                set = function(_, value)
                    if InCombatLockdown() then
                        addon:Print("Change the bars after combat ends.")
                        return
                    end
                    def.dock = { host = value, edge = (def.dock and def.dock.edge) or "BOTTOM" }
                    UnitBars:Save()
                    local bar = UnitBars.bars[def.id]
                    if bar then UnitBars:Apply(bar) end
                end,
            },
            dockEdge = {
                order = 12, type = "select", name = "On the",
                values = EDGES,
                hidden = function() return not def.dock or def.dock.host == "float" end,
                get = function() return (def.dock and def.dock.edge) or "BOTTOM" end,
                set = function(_, value)
                    def.dock = { host = (def.dock and def.dock.host) or "float", edge = value }
                    UnitBars:Save()
                    local bar = UnitBars.bars[def.id]
                    if bar then UnitBars:Apply(bar) end
                end,
            },
            takes = {
                order = 13, type = "select", name = "Takes",
                desc = "Half the width lets two bars share one line: a health bar aligned left and a power bar aligned right on the same action bar.",
                values = TAKES,
                hidden = function() return not def.dock or def.dock.host == "float" end,
                get = Field(def, "takes", "full"), set = SetField(def, "takes"),
            },
            align = {
                order = 14, type = "select", name = "Aligned",
                desc = "Which end of its host it sits at.",
                values = ALIGNS,
                hidden = function()
                    return not def.dock or def.dock.host == "float"
                        or (def.takes or "full") == "full"
                end,
                get = Field(def, "align", "LEFT"), set = SetField(def, "align"),
            },
            gutter = {
                order = 15, type = "range", name = "Space beside",
                desc = "Pixels left between this bar and the one sharing its line. One number for the line, so setting it on either of the two is enough.",
                min = 0, max = 40, step = 1,
                hidden = function()
                    return not def.dock or def.dock.host == "float"
                        or (def.takes or "full") == "full"
                end,
                get = Field(def, "gutter", 0), set = SetField(def, "gutter"),
            },
            gap = {
                order = 16, type = "range", name = "Gap",
                desc = "Pixels between this bar and the one it is docked to. Each bar owns the space above it, so a chain is spaced by setting each bar in turn.",
                min = 0, max = 24, step = 1,
                hidden = function() return not def.dock or def.dock.host == "float" end,
                get = Field(def, "gap", 2), set = SetField(def, "gap"),
            },
            lookHeader = { order = 20, type = "header", name = "Size and text" },
            width = {
                order = 21, type = "range", name = "Width",
                min = 60, max = 1200, step = 5,
                hidden = function()
                    return def.dock and def.dock.host ~= "float"
                        and (def.takes or "full") ~= "own"
                end,
                desc = "A docked bar is measured from its host unless it is set to keep its own width.",
                get = Field(def, "width", 240), set = SetField(def, "width"),
            },
            height = {
                order = 22, type = "range", name = "Height",
                desc = "The height of the fill. The border is added around it, so the bar comes out taller than this by however thick the border is.",
                -- Four hundred, to agree with the Edit Mode panel. It
                -- stopped at forty-eight here while that one allowed
                -- more, so a bar meant to stand beside a two-row action
                -- bar could be given that height in one editor and not
                -- the other, and the manual could not tell you which.
                min = 1, max = 400, step = 1,
                get = Field(def, "height", 24), set = SetField(def, "height"),
            },
            fillFrom = {
                order = 22.5, type = "select", name = "Fills from",
                desc = "Which end the bar empties towards. Two bars sharing a line often want opposite ends, so they drain towards each other.",
                values = FILL_FROM,
                get = Field(def, "fillFrom", "LEFT"), set = SetField(def, "fillFrom"),
            },
            textMode = {
                order = 23, type = "select", name = "Show text",
                values = TEXT_MODES,
                get = Field(def, "textMode", "always"), set = SetField(def, "textMode"),
            },
            textFormat = {
                order = 24, type = "select", name = "Text says",
                desc = "Everything spells out the name, the values and the exact percent.",
                hidden = function() return def.kind == "cast" end,
                values = FORMATS,
                get = Field(def, "textFormat", "namePercent"),
                set = SetField(def, "textFormat"),
            },
            hideAtMax = {
                order = 26, type = "toggle", name = "Hide at maximum level",
                desc = "An experience bar has nothing to show once you stop earning any.",
                hidden = function() return def.kind ~= "xp" end,
                get = function() return def.hideAtMax ~= false end,
                set = SetField(def, "hideAtMax", function(d)
                    local bar = Bars().bars[d.id]
                    if bar then Bars():Update(bar) end
                end),
            },
            ticks = {
                order = 25, type = "range", name = "Tenth marks",
                desc = "Divider lines across the fill. Ten marks the tenths of a level.",
                min = 0, max = 20, step = 1,
                get = Field(def, "ticks", 0), set = SetField(def, "ticks"),
            },
        },
    }
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

function Options:Build()
    local UnitBars = Bars()
    local bars = {}
    for index, def in ipairs(UnitBars:Defs()) do
        bars["bar" .. def.id] = BarArgs(def)
        bars["bar" .. def.id].order = index
    end

    return {
        name = "Bars",
        type = "group",
        args = {
            newBar = {
                order = 1, type = "execute", name = "New bar",
                func = function()
                    if InCombatLockdown() then
                        addon:Print("Create bars after combat ends.")
                        return
                    end
                    local def = UnitBars:Add("health", "player")
                    if def then
                        -- Open on the one just made. See pickerSelect in
                        -- Core/Options/ListDetail.
                        pendingBar = "bar" .. def.id
                        addon:Print("Created " .. (def.name or "a bar"))
                    end
                end,
            },
            bars = {
                order = 10, type = "group", name = "",
                pickerLabel = "Bar",
                pickerSelect = TakePendingBar,
                pickerSelectTaken = TakePendingBarTaken,
                emptyText = "No bars yet. Click New bar to make one.",
                args = bars,
                itemActions = {
                    {
                        name = "Delete", style = "danger",
                        confirm = true, confirmTitle = "Delete bar?",
                        confirmText = function(item)
                            return string.format("Delete %s? Anything docked to it goes back to floating.",
                                item and item.name or "this bar")
                        end,
                        confirmStyle = "destructive",
                        confirmAcceptLabel = "Delete", confirmCancelLabel = "Cancel",
                        func = function(item) UnitBars:Remove(item._barId) end,
                    },
                },
            },
        },
    }
end
