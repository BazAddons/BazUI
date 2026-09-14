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

BazUI:RegisterSettingsSpec("UnitFrames", {
    sections = {
        player = { label = "Player Frames", order = 1 },
        layout = { label = "Position", order = 2 },
        portraitAdjust = { label = "3D Portrait Placement", order = 3 },
    },
    entries = {
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
    sections = { target = { label = "Target Frame", order = 1 }, layout = { label = "Position", order = 2 } },
    entries = {
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
