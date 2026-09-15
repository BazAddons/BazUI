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
        target  = { label = "Target",  order = 3 },
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
          min = 4, max = 16, step = 1, get = Get("perRow"), set = Set("perRow") },
        { key = "iconSize", label = "Icon size", type = "slider", section = "layout", order = 2,
          min = 16, max = 40, step = 1, get = Get("iconSize"), set = Set("iconSize") },
        { key = "spacing", label = "Spacing", type = "slider", section = "layout", order = 3,
          desc = "Pixels between icons, and between rows.",
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

        { key = "targetEnabled", label = "Show the target's auras", type = "toggle", section = "target", order = 1,
          desc = "Draw the target's buffs and debuffs. Where they sit is on the Rows page.",
          get = GetBool("targetEnabled"), set = SetBool("targetEnabled") },
        { key = "targetOnlyMine", label = "Only my debuffs", type = "toggle", section = "target", order = 2,
          desc = "Hide debuffs other players put on the target.",
          get = function() return addon:GetSetting("targetOnlyMine") == true end, set = SetBool("targetOnlyMine") },

        { key = "showDuration", label = "Time remaining on icons", type = "toggle", section = "icons", order = 1,
          get = GetBool("showDuration"), set = SetBool("showDuration") },
        { key = "showCount", label = "Stack counts", type = "toggle", section = "icons", order = 2,
          get = GetBool("showCount"), set = SetBool("showCount") },
        { key = "debuffBorders", label = "Colour debuff rims by type", type = "toggle", section = "icons", order = 3,
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

    -- The four rows, each with where it sits. A page rather than a
    -- section: four groups times four choices as a flat list is the grid
    -- of dropdowns this suite keeps deciding not to have.
    BazUI:RegisterOptionsTable(MODULE_NAME .. "-Groups", function()
        return addon:BuildGroupOptions()
    end)
    BazUI:AddToSettings(MODULE_NAME .. "-Groups", "Rows", MODULE_NAME)
end)

---------------------------------------------------------------------------
-- One row's form, in the shape the bars use: pick one from the list, and
-- everything about it appears underneath.
---------------------------------------------------------------------------

local function DockValues(frame)
    local values = { float = "Floating" }
    for _, host in ipairs(BazUI.Dock:GetHosts()) do
        local hostFrame = BazUI.Dock:GetHostFrame(host.id)
        if hostFrame and hostFrame ~= frame then values[host.id] = host.label end
    end
    return values
end

local function GroupArgs(entry, index)
    local def = addon:GroupDef(entry.key)

    local function Apply()
        addon:SaveGroups()
        addon:ApplySettings()
    end

    local function Docked() return def.dock and def.dock.host ~= "float" end

    return {
        name = entry.label,
        type = "group",
        order = index,
        args = {
            dockHost = {
                order = 1, type = "select", name = "Dock to",
                desc = "Floating keeps it where you put it. Docked, it follows whatever it is attached to and hides when that hides.",
                values = function() return DockValues(addon:GroupFrame(entry.key)) end,
                get = function() return (def.dock and def.dock.host) or "float" end,
                set = function(_, value)
                    def.dock = { host = value, edge = (def.dock and def.dock.edge) or "BOTTOM" }
                    Apply()
                end,
            },
            dockEdge = {
                order = 2, type = "select", name = "On the",
                values = { BOTTOM = "Below", TOP = "Above" },
                hidden = function() return not Docked() end,
                get = function() return (def.dock and def.dock.edge) or "BOTTOM" end,
                set = function(_, value)
                    def.dock = { host = (def.dock and def.dock.host) or "float", edge = value }
                    Apply()
                end,
            },
            align = {
                order = 3, type = "select", name = "Aligned",
                desc = "Which end of its host the row starts from. Centre keeps the row centred as icons come and go.",
                values = { LEFT = "Left", CENTER = "Centre", RIGHT = "Right" },
                hidden = function() return not Docked() end,
                get = function() return def.align or "LEFT" end,
                set = function(_, value) def.align = value Apply() end,
            },
            gap = {
                order = 4, type = "range", name = "Gap",
                desc = "Pixels between this row and what it is docked to.",
                min = 0, max = 24, step = 1,
                hidden = function() return not Docked() end,
                get = function() return def.gap or 4 end,
                set = function(_, value) def.gap = value Apply() end,
            },
            note = {
                order = 10, type = "description",
                name = "Rows can also be dragged in Edit Mode: drop one near the edge of a bar or an action bar to dock it there.",
            },
        },
    }
end

function addon:BuildGroupOptions()
    local groups = {}
    for index, entry in ipairs(self.GROUPS) do
        groups[entry.key] = GroupArgs(entry, index)
    end

    return {
        name = "Rows",
        type = "group",
        args = {
            rows = {
                order = 1, type = "group", name = "",
                pickerLabel = "Row",
                args = groups,
            },
        },
    }
end
