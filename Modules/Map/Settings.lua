-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("Map")
local function Set(key, value) addon:SetSetting(key, value); addon:ApplySettings() end

BazUI:RegisterSettingsSpec("Map", {
    sections = { appearance = { label = "World map", order = 1 } },
    entries = {
        { key = "terrainOpacity", label = "Terrain opacity at full zoom", type = "slider",
          section = "appearance", order = 1, min = 0, max = 100, step = 5,
          get = function() return addon:GetSetting("terrainOpacity") end,
          set = function(_, value) Set("terrainOpacity", value) end,
          desc = "At 100%, terrain fully covers the painted map at the deepest zoom. Lower values blend the two. Underground cities keep their interior maps." },
        { key = "terrainStart", label = "Terrain transition starts", type = "slider",
          section = "appearance", order = 2, min = 1, max = 60, step = 1,
          get = function() return addon:GetSetting("terrainStart") end,
          set = function(_, value) Set("terrainStart", value) end,
          desc = "The zoom level where terrain begins fading in. Lower values show terrain sooner; higher values keep the painted map longer. Default: 20." },
        { key = "maxZoom", label = "Maximum zoom", type = "slider",
          section = "appearance", order = 3, min = 16, max = 192, step = 8,
          get = function() return addon:GetSetting("maxZoom") end,
          set = function(_, value) Set("maxZoom", value) end,
          desc = "How far you can zoom into the map. Higher values allow a closer view but may look blurry. Cities allow extra zoom. Default: 48." },
        { key = "unexplored", label = "Unexplored areas", type = "select", section = "appearance", order = 4,
          values = { hide = "Hidden (fog of war)", dim = "Dimmed", show = "Revealed" },
          get = function() return addon:GetUnexploredStyle() end,
          set = function(_, value) Set("unexplored", value) end,
          desc = "Hide unexplored areas, show their artwork under a dark shade, or reveal them fully. This changes the display only, not exploration progress." },
    },
})

BazUI:QueueForModule("Map", function()
    BazUI:RegisterOptionsTable("Map", function() return { name = "Map", type = "group", args = {} } end)
    BazUI:AddToSettings("Map", "Map")
    BazUI:RegisterOptionsTable("Map-General", function()
        return BazUI:BuildOptionsTableFromSpec("Map", { name = "General" })
    end)
    BazUI:AddToSettings("Map-General", "General", "Map")
end)
