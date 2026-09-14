-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("UnitFrames")
local both = { options = true, editMode = true }
local valueModes = { always = "Always", hover = "On Hover", never = "Never" }
local function ValueMode(owner)
    local value = owner:GetSetting("showValues")
    if value == false then return "never" end
    if value == "hover" or value == "never" then return value end
    return "always"
end
local function Set(key)
    return function(_, value)
        addon:SetSetting(key, value)
        addon:ApplySettings()
    end
end
local function Get(key) return function() return addon:GetSetting(key) end end

local function SetBars(key)
    return function(_, value)
        addon:SetSetting(key, value)
        for unit in pairs(addon.UnitBars and addon.UnitBars.sets or {}) do
            addon.UnitBars:ApplySettings(unit)
        end
    end
end

-- The dropdown of places a bar can go, built from whatever the dock
-- knows about right now: floating, every action bar, and the other unit
-- bars. A bar never offers itself.
local function DockValues(selfId)
    local values = { float = "Floating" }
    for _, host in ipairs(BazUI.Dock:GetHosts()) do
        if host.id ~= selfId then values[host.id] = host.label end
    end
    return values
end

local EDGES = { BOTTOM = "Below", TOP = "Above" }

local function DockEntry(unit, key, label, order)
    local UnitBars = addon.UnitBars
    return {
        key = "dock_" .. unit .. "_" .. key,
        label = label, type = "select", section = "docking", order = order,
        surfaces = both,
        values = function() return DockValues(UnitBars:HostID(unit, key)) end,
        get = function()
            local dock = UnitBars:GetDock(unit, key)
            local host = dock.host or "float"
            if host:find("^self:") then host = UnitBars:HostID(unit, host:sub(6)) end
            return host
        end,
        set = function(_, value)
            local dock = UnitBars:GetDock(unit, key)
            UnitBars:SetDock(unit, key,
                { host = value, edge = dock.edge or "BOTTOM", reserve = dock.reserve })
        end,
    }
end

local function EdgeEntry(unit, key, label, order)
    local UnitBars = addon.UnitBars
    return {
        key = "edge_" .. unit .. "_" .. key,
        label = label, type = "select", section = "docking", order = order,
        surfaces = both, values = EDGES,
        get = function() return UnitBars:GetDock(unit, key).edge or "BOTTOM" end,
        set = function(_, value)
            local dock = UnitBars:GetDock(unit, key)
            UnitBars:SetDock(unit, key,
                { host = dock.host, edge = value, reserve = dock.reserve })
        end,
    }
end

BazUI:RegisterSettingsSpec("UnitFrames", {
    sections = {
        bars = { label = "Bars", order = 0 },
        docking = { label = "Docking", order = 1 },
        player = { label = "Player Frames", order = 1 },
        layout = { label = "Position", order = 2 },
        portraitAdjust = { label = "3D Portrait Placement", order = 3 },
        casting = { label = "Portrait Casting", order = 4 },
    },
    entries = {
        DockEntry("player", "health", "Player health sits", 10),
        EdgeEntry("player", "health", "Player health edge", 11),
        DockEntry("player", "power",  "Player power sits",  12),
        EdgeEntry("player", "power",  "Player power edge",  13),
        DockEntry("player", "cast",   "Player cast sits",   14),
        EdgeEntry("player", "cast",   "Player cast edge",   15),
        DockEntry("target", "health", "Target health sits", 20),
        EdgeEntry("target", "health", "Target health edge", 21),
        DockEntry("target", "power",  "Target power sits",  22),
        EdgeEntry("target", "power",  "Target power edge",  23),
        DockEntry("target", "cast",   "Target cast sits",   24),
        EdgeEntry("target", "cast",   "Target cast edge",   25),
        { key = "barMode", label = "Draw units as bars", type = "toggle", section = "bars", order = 1,
          desc = "The bars can float or dock to an action bar. Off returns the old portrait frames until they are retired.",
          get = Get("barMode"), set = SetBars("barMode") },
        { key = "barWidth", label = "Width", type = "slider", section = "bars", order = 2, surfaces = both,
          min = 80, max = 900, step = 5, get = Get("barWidth"), set = SetBars("barWidth") },
        { key = "barHeight", label = "Height", type = "slider", section = "bars", order = 3, surfaces = both,
          min = 10, max = 40, step = 1, get = Get("barHeight"), set = SetBars("barHeight") },
        { key = "barText", label = "Show text", type = "select", section = "bars", order = 4, surfaces = both,
          values = valueModes, get = Get("barText"), set = SetBars("barText") },
        { key = "healthText", label = "Health bar says", type = "select", section = "bars", order = 5, surfaces = both,
          values = { ["current/max"] = "Current / Max", current = "Current", percent = "Percent", name = "Name", namePercent = "Name and percent" }, get = Get("healthText"), set = SetBars("healthText") },
        { key = "powerText", label = "Power bar says", type = "select", section = "bars", order = 6, surfaces = both,
          values = { ["current/max"] = "Current / Max", current = "Current", percent = "Percent", name = "Name", namePercent = "Name and percent" }, get = Get("powerText"), set = SetBars("powerText") },
        { key = "unitTooltips", label = "Tooltip on hover", type = "toggle", section = "bars", order = 7,
          get = Get("unitTooltips"), set = SetBars("unitTooltips") },
        { key = "castEnabled", label = "Liquid portrait casting", type = "toggle", section = "casting", order = 1,
          get = Get("castEnabled"), set = Set("castEnabled") },
        { key = "castOpacity", label = "Liquid opacity", type = "slider", section = "casting", order = 2,
          min = 0.05, max = 0.75, step = 0.01, format = "percent", get = Get("castOpacity"), set = Set("castOpacity") },
        { key = "castSwirl", label = "Swirl intensity", type = "slider", section = "casting", order = 3,
          min = 0, max = 1, step = 0.05, format = "percent", get = Get("castSwirl"), set = Set("castSwirl") },
        { key = "castColor", label = "Liquid color", type = "select", section = "casting", order = 4,
          values = {gold = "Arcane Gold", arcane = "Violet", frost = "Frost Blue", jade = "Jade"}, get = Get("castColor"), set = Set("castColor") },
        { key = "castText", label = "Show spell name and countdown", type = "toggle", section = "casting", order = 5,
          get = Get("castText"), set = Set("castText") },
        { key = "castPreview", label = "Preview liquid casting", type = "execute", section = "casting", order = 6,
          func = function() addon.Casting:Preview() end },
        { key = "castHelp", type = "note", section = "casting", order = 7,
          text = "Liquid rises while casting and drains while channeling. Interruptions flash red. Disabling portrait casting restores Blizzard's cast bar. New textures require restarting the game once after installation." },
        { key = "modelLayer", label = "3D portrait layer", type = "select", section = "portraitAdjust", order = 1, surfaces = both,
          values = { above = "Above Frame", below = "Below Frame" }, get = Get("modelLayer"), set = Set("modelLayer") },
        { key = "modelScale", label = "3D portrait size", type = "slider", section = "portraitAdjust", order = 2, surfaces = both,
          min = 0.5, max = 2, step = 0.01, format = "percent", get = Get("modelScale"), set = Set("modelScale") },
        { key = "modelX", label = "Horizontal position", type = "slider", section = "portraitAdjust", order = 3, surfaces = both,
          min = -100, max = 100, step = 1, get = Get("modelX"), set = Set("modelX") },
        { key = "modelY", label = "Vertical position", type = "slider", section = "portraitAdjust", order = 4, surfaces = both,
          min = -100, max = 100, step = 1, get = Get("modelY"), set = Set("modelY") },
        { key = "modelDistance", label = "Camera distance (lower is closer)", type = "slider", section = "portraitAdjust", order = 5, surfaces = both,
          min = 0.2, max = 2, step = 0.01, get = Get("modelDistance"), set = Set("modelDistance") },
        { key = "portraitReport", label = "Print portrait placement", type = "execute", section = "portraitAdjust", order = 6,
          func = function() addon:PrintPortraitPlacement() end },
        { key = "portraitReset", label = "Reset portrait placement", type = "execute", section = "portraitAdjust", order = 7,
          func = function()
              addon:SetSetting("modelLayer", "above"); addon:SetSetting("modelScale", 1)
              addon:SetSetting("modelX", 0); addon:SetSetting("modelY", 0); addon:SetSetting("modelDistance", 0.7)
              addon:ApplySettings()
          end },
        { key = "enabled", label = "Replace the stock player frame", type = "toggle", section = "player", order = 1,
          get = Get("enabled"), set = Set("enabled") },
        { key = "portraitStyle", label = "Portrait", type = "select", section = "player", order = 2, surfaces = both,
          values = { ["3d"] = "3D portrait", flat = "Flat portrait" }, get = Get("portraitStyle"), set = Set("portraitStyle") },
        { key = "scale", label = "Frame scale", type = "slider", section = "player", order = 3, surfaces = both,
          min = 0.5, max = 2, step = 0.05, format = "percent", get = Get("scale"), set = Set("scale") },
        { key = "showValues", label = "Health and resource numbers", type = "select", section = "player", order = 4, surfaces = both,
          values = valueModes, get = function() return ValueMode(addon) end, set = Set("showValues") },
        { key = "classColor", label = "Use class color for health", type = "toggle", section = "player", order = 5, surfaces = both,
          get = Get("classColor"), set = Set("classColor") },
        { key = "move", label = "Unlock frame", type = "execute", section = "layout", order = 1,
          func = function() addon:SetUnlocked(true) end, disabled = InCombatLockdown },
        { key = "lock", label = "Lock frame", type = "execute", section = "layout", order = 2,
          func = function() addon:SetUnlocked(false) end },
        { key = "reset", label = "Reset position and scale", type = "execute", section = "layout", order = 3,
          func = function() addon:ResetLayout() end },
        { key = "nudge", label = "Position", type = "nudge", section = "layout", surfaces = { editMode = true } },
        { key = "help", type = "note", section = "layout", order = 4, style = "info",
          text = "Move the player frame in BazUI Edit Mode, or unlock it here and drag the blue panel. Changes made during combat apply when combat ends. The lower bar follows your current resource, including rage and energy." },
    },
})

BazUI:QueueForLogin(function()
    BazUI:RegisterOptionsTable("UnitFrames", function()
        return BazUI:BuildOptionsTableFromSpec("UnitFrames", { name = "Player Frames" })
    end)
    BazUI:AddToSettings("UnitFrames", "Unit Frames")
    BazUI:RegisterOptionsTable("UnitFrames-Player", function()
        return BazUI:BuildOptionsTableFromSpec("UnitFrames", { name = "Player Frames" })
    end)
    BazUI:AddToSettings("UnitFrames-Player", "Player", "UnitFrames")
    BazUI:RegisterOptionsTable("UnitFrames-Target", function()
        return BazUI:BuildOptionsTableFromSpec("UnitFramesTarget", { name = "Target Frame" })
    end)
    BazUI:AddToSettings("UnitFrames-Target", "Target", "UnitFrames")
end)

local function TargetGet(key) return function() return addon.Target:GetSetting(key) end end
local function TargetSet(key)
    return function(_, value)
        addon.Target:SetSetting(key, value)
        addon.Target:ApplySettings()
    end
end
BazUI:RegisterSettingsSpec("UnitFramesTarget", {
    sections = { target = { label = "Target Frame", order = 1 }, layout = { label = "Position", order = 2 },
        portraitAdjust = { label = "3D Portrait Placement", order = 3 } },
    entries = {
        { key = "targetModelLayer", label = "3D portrait layer", type = "select", section = "portraitAdjust", order = 1, surfaces = both,
          values = { above = "Above Frame", below = "Below Frame" }, get = TargetGet("modelLayer"), set = TargetSet("modelLayer") },
        { key = "targetModelScale", label = "3D portrait size", type = "slider", section = "portraitAdjust", order = 2, surfaces = both,
          min = 0.5, max = 2, step = 0.01, format = "percent", get = TargetGet("modelScale"), set = TargetSet("modelScale") },
        { key = "targetModelX", label = "Horizontal position", type = "slider", section = "portraitAdjust", order = 3, surfaces = both,
          min = -100, max = 100, step = 1, get = TargetGet("modelX"), set = TargetSet("modelX") },
        { key = "targetModelY", label = "Vertical position", type = "slider", section = "portraitAdjust", order = 4, surfaces = both,
          min = -100, max = 100, step = 1, get = TargetGet("modelY"), set = TargetSet("modelY") },
        { key = "targetModelDistance", label = "Camera distance (lower is closer)", type = "slider", section = "portraitAdjust", order = 5, surfaces = both,
          min = 0.2, max = 2, step = 0.01, get = TargetGet("modelDistance"), set = TargetSet("modelDistance") },
        { key = "targetPortraitReport", label = "Print portrait placement", type = "execute", section = "portraitAdjust", order = 6,
          func = function() addon.Target:PrintPortraitPlacement() end },
        { key = "targetPortraitReset", label = "Reset portrait placement", type = "execute", section = "portraitAdjust", order = 7,
          func = function()
              addon.Target:SetSetting("modelLayer", "below"); addon.Target:SetSetting("modelScale", 1)
              addon.Target:SetSetting("modelX", 0); addon.Target:SetSetting("modelY", -5); addon.Target:SetSetting("modelDistance", 0.98)
              addon.Target:ApplySettings()
          end },
        { key = "targetEnabled", label = "Replace the stock target frame", type = "toggle", section = "target", order = 1,
          get = TargetGet("enabled"), set = TargetSet("enabled") },
        { key = "targetPortraitStyle", label = "Portrait", type = "select", section = "target", order = 2, surfaces = both,
          values = { ["3d"] = "3D portrait", flat = "Flat portrait" }, get = TargetGet("portraitStyle"), set = TargetSet("portraitStyle") },
        { key = "targetScale", label = "Frame scale", type = "slider", section = "target", order = 3, surfaces = both,
          min = 0.5, max = 2, step = 0.05, format = "percent", get = TargetGet("scale"), set = TargetSet("scale") },
        { key = "targetShowValues", label = "Health and resource numbers", type = "select", section = "target", order = 4, surfaces = both,
          values = valueModes, get = function() return ValueMode(addon.Target) end, set = TargetSet("showValues") },
        { key = "targetClassColor", label = "Use class color for player targets", type = "toggle", section = "target", order = 5, surfaces = both,
          get = TargetGet("classColor"), set = TargetSet("classColor") },
        { key = "targetMove", label = "Unlock target frame", type = "execute", section = "layout", order = 1,
          func = function() addon.Target:SetUnlocked(true) end, disabled = InCombatLockdown },
        { key = "targetLock", label = "Lock target frame", type = "execute", section = "layout", order = 2,
          func = function() addon.Target:SetUnlocked(false) end },
        { key = "targetReset", label = "Reset target position and scale", type = "execute", section = "layout", order = 3,
          func = function() addon.Target:ResetLayout() end },
        { key = "targetNudge", label = "Position", type = "nudge", section = "layout", surfaces = { editMode = true } },
        { key = "targetHelp", type = "note", section = "layout", order = 4, style = "info",
          text = "Appears at the top center when you select a target, including during combat. Health color indicates hostile, neutral or friendly targets. Target a unit to preview the artwork while moving it. Changes during combat apply afterward." },
    },
})
