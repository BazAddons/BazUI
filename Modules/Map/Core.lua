-- SPDX-License-Identifier: GPL-2.0-or-later
-- One BazUI module owns the default world map; no second map window.
local addon
addon = BazUI:RegisterModule("Map", {
    title = "Map",
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    profiles = true,
    defaults = { terrainOpacity = 85, terrainStart = 20, maxZoom = 48, fogOfWar = true },
    slash = { "/bazmap" },
    defaultHandler = function() BazUI:OpenOptionsPanel("Map") end,
    onReady = function(self)
        self:Initialize()
        self:OnProfileChanged(function() self:ApplySettings() end)
    end,
})

function addon:Initialize()
    if BazUI.IsRetail then return end -- Terrain file IDs are Forever's.
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("OpenMap") then
        self:Print("Disable OpenMap and reload to use BazUI's Map module. Only one addon can own world-map zoom.")
        return
    end
    local runtime = BazUI.MapRuntime
    local renderer = runtime:GetModule("worldmap")
    renderer.db = CopyTable(renderer.defaults)
    -- Only the continuous map and its terrain transition are adopted.
    -- Keep Blizzard's quest log and map controls; add no side panels,
    -- routes, POIs, reveal controls, drawings, navigation or window skin.
    for _, key in ipairs({ "icons", "boats", "zeppelins", "flight", "routes", "gapFills",
        "chart", "underground", "gapMinimap", "soften", "hoverHighlight", "padMap" }) do
        renderer.db[key] = false
    end
    self.renderer = renderer
    self:ApplySettings()
    renderer.enabled = true
    renderer:OnEnable()
end

function addon:GetUnexploredStyle()
    local style = self:GetSetting("unexplored")
    if style == "hide" or style == "dim" or style == "show" then return style end
    -- Preserve the existing fog toggle until a style is selected.
    return self:GetSetting("fogOfWar") == false and "show" or "hide"
end

function addon:ApplySettings()
    local renderer = self.renderer
    if not renderer then return end
    local opacity = math.max(0, math.min(100, tonumber(self:GetSetting("terrainOpacity")) or 85)) / 100
    renderer.db.minimapDeep = opacity
    -- Keep the intermediate blend below the selected maximum too.
    renderer.db.minimapMix = math.min(renderer.defaults.minimapMix, opacity)
    renderer.db.cityMinimapMax = opacity
    renderer.db.minimapFrom = math.max(1, math.min(60, tonumber(self:GetSetting("terrainStart")) or 20))
    local maxZoom = math.max(16, math.min(192, tonumber(self:GetSetting("maxZoom")) or 48))
    if renderer.db.maxZoom ~= maxZoom then renderer.SetMaxZoom(maxZoom) end
    renderer.db.unexplored = self:GetUnexploredStyle()
    -- The native exploration mask and the close-up overlay must agree.
    -- Before the map is built these calls simply retain the settings.
    renderer:Refresh()
end
