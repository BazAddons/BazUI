-- SPDX-License-Identifier: GPL-2.0-or-later
local addon
addon = BazUI:RegisterModule("AGN", {
    title = "AGN", profiles = true,
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    defaults = { size = 96, tomtom = true, zygor = true, waypointSets = {} },
    slash = { "/agn" },
    defaultHandler = function() BazUI:OpenOptionsPanel("AGN") end,
    commands = {
        way = { desc = "Set coordinates: /agn way [zone or #mapID] x y [name]",
            handler = function(args) addon:WayCommand(args) end },
        back = { desc = "Save your current position", handler = function(args) addon:SaveCurrentPosition(args) end },
        closest = { desc = "Select the closest saved waypoint", handler = function() addon:SelectClosest() end },
        clear = { desc = "Clear navigation", handler = function() addon:ClearNavigation() end },
        list = { desc = "List waypoints", handler = function() addon:ListWaypoints() end },
        paste = { desc = "Paste waypoint commands", handler = function() addon:OpenWaypointPaste() end },
        preview = { desc = "Show or hide the AGN arrow preview",
            handler = function() addon:TogglePreview() end },
        status = { desc = "Show navigation integration status",
            handler = function()
                addon:Print("Standalone navigation ready. TomTom "
                    .. (addon.tomtomReady and "connected" or "not connected")
                    .. "; Zygor " .. (addon.zygorReady and "connected" or "not connected") .. ".")
            end },
    },
    onReady = function(self)
        self:InitializeNavigation()
        self:InitializeIntegrations()
        self:OnProfileChanged(function() self:ApplySettings() end)
    end,
})
