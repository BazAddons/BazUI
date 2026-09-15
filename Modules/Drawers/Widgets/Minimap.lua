-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Minimap
--
-- Reparents the real Minimap into a wrapper frame and registers that
-- wrapper as a dockable BazUI Drawers widget. The Minimap becomes a first-
-- class widget that can be docked (sized by the drawer's widget host)
-- or floated (Edit Mode draggable on UIParent).
--
-- At startup the component hides Blizzard's default MinimapCluster
-- shell so the native minimap chrome doesn't occupy screen space
-- alongside the widget.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_minimap"
local DEFAULT_SIZE = 140
-- Breathing room around the minimap inside the wrapper, for the Blizzard
-- style: its ring is part of the map's own textures and sits right on the
-- edge, so without a little room it butts against whatever is docked
-- above. Kept small because it scales with everything else - the drawer
-- sizes a widget by its declared width, so padding here is multiplied
-- before anyone sees it. The BazUI frame brings its own margin and does
-- not use this.
local VISUAL_PAD   = 4

---------------------------------------------------------------------------
-- Raw method helpers
--
-- Minimap is a special widget type and requires unhooked method calls
-- for reparenting (otherwise it stops rendering entirely). `raw` gives
-- us a plain Frame we can use to access native methods on Minimap.
---------------------------------------------------------------------------

local raw = CreateFrame("Frame")

local MinimapWidget = {}
addon.MinimapWidget = MinimapWidget

local wrapper
local widgetInfo
local minimapParentedInto = nil
local nativeMapWidth, nativeMapHeight

-- Defined with the frame styles further down, both called from
-- AttachMinimap above them.
local HostRing, MapScale

---------------------------------------------------------------------------
-- Parent the Minimap into the given frame (either the wrapper when docked,
-- or the wrapper when floating - the wrapper is always its immediate
-- parent; only the wrapper's own parent changes based on dock/float).
---------------------------------------------------------------------------

local function AttachMinimap(parent)
    if not Minimap or not parent then return end
    if minimapParentedInto == parent then return end

    -- Lock strata/level BEFORE reparenting or the Minimap widget stops
    -- rendering. Fixed so inherited strata from our wrapper can't leak
    -- back in after some future SetParent.
    raw.SetFrameStrata(Minimap, "MEDIUM")
    raw.SetFrameLevel(Minimap, (parent:GetFrameLevel() or 0) + 2)
    raw.SetFixedFrameStrata(Minimap, true)
    raw.SetFixedFrameLevel(Minimap, true)

    raw.SetParent(Minimap, parent)
    raw.ClearAllPoints(Minimap)
    raw.SetPoint(Minimap, "CENTER", parent, "CENTER", 0, 0)

    -- The widget host's SetScale on the wrapper handles fitting the map
    -- to the drawer; the map's own scale is the player's, and multiplies
    -- with it. Nothing else may set it - a scale arriving from anywhere
    -- but here is a scale nobody asked for.
    Minimap:SetScale(MapScale())

    -- Suppress Blizzard Edit Mode handling for the Minimap
    if MinimapCluster and MinimapCluster.Selection then
        MinimapCluster.Selection:Hide()
        MinimapCluster.Selection.Show = MinimapCluster.Selection.Hide
    end

    -- The frame is drawn behind the map on a host of its own, which has
    -- to follow it.
    HostRing(parent)

    minimapParentedInto = parent
end

---------------------------------------------------------------------------
-- Zooming with the wheel
--
-- Vanilla never wired the scroll wheel to the minimap; zoom is the + and
-- - buttons and nothing else, which is a surprise on any modern client
-- and a worse one once those buttons are hidden. So the widget adds it.
--
-- Where Blizzard's zoom buttons exist the wheel clicks them, which keeps
-- the sound, the zoom limits and the buttons' own enabled states in
-- Blizzard's hands. A click on a disabled button does nothing, so the
-- ends of the range look after themselves. Clients that hang the buttons
-- off the Minimap instead, or have none, fall back to setting the zoom
-- with the same clamp.
---------------------------------------------------------------------------

local function ZoomButtons()
    return MinimapZoomIn  or (Minimap and Minimap.ZoomIn),
           MinimapZoomOut or (Minimap and Minimap.ZoomOut)
end

local function Zoom(delta)
    if not Minimap then return end

    local zoomIn, zoomOut = ZoomButtons()
    local button = (delta > 0) and zoomIn or zoomOut
    if button and button.Click then
        -- A hidden button still clicks, so this works with the zoom
        -- buttons turned off.
        button:Click()
        return
    end

    local levels = Minimap.GetZoomLevels and Minimap:GetZoomLevels()
    local zoom   = Minimap.GetZoom and Minimap:GetZoom()
    if not (levels and zoom) then return end

    local wanted = math.max(0, math.min(levels - 1, zoom + (delta > 0 and 1 or -1)))
    if wanted == zoom then return end
    Minimap:SetZoom(wanted)
    PlaySound(delta > 0 and SOUNDKIT.IG_MINIMAP_ZOOM_IN or SOUNDKIT.IG_MINIMAP_ZOOM_OUT)
end

local function EnableWheelZoom()
    if not Minimap or Minimap._bazWheelZoom then return end
    Minimap._bazWheelZoom = true
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", function(_, delta) Zoom(delta) end)
end

---------------------------------------------------------------------------
-- Hide the MinimapCluster shell so it doesn't occupy screen space
-- alongside the reparented Minimap.
---------------------------------------------------------------------------

local function HideMinimapCluster()
    if not MinimapCluster then return end
    MinimapCluster:SetSize(1, 1)
    MinimapCluster:SetAlpha(0)
    MinimapCluster:EnableMouse(false)
    MinimapCluster:ClearAllPoints()
    MinimapCluster:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
end

---------------------------------------------------------------------------
-- Minimap frame styles.
--
-- Blizzard draws its ring on MinimapBackdrop, which is a CHILD of the
-- Minimap on both flavours (Era: MinimapBorder + MinimapNorthTag +
-- MinimapCompassTexture; Retail: MinimapCompassTexture, the
-- ui-hud-minimap-frame atlas). Being a child, it follows the map into our
-- wrapper - that is why the stock ring shows up in the widget at all, and
-- why the zoom / tracking / day-night buttons (also MinimapBackdrop
-- children) sit on it.
--
-- The BazUI style fades those textures to alpha 0 - alpha rather than
-- Hide, which is independent of Show, so Blizzard toggling
-- MinimapCompassTexture for the rotate-minimap CVar cannot bring them
-- back - and puts our own frame behind the map instead, with the map
-- shrunk to sit in the hole in the middle of it.
---------------------------------------------------------------------------

local FRAME_STYLE_KEY = "frameStyle"
local FRAME_STYLES = {
    default = "Blizzard Default",
    bazui   = "BazUI",
}

local function GetFrameStyle()
    local style = addon:GetWidgetSetting(WIDGET_ID, FRAME_STYLE_KEY, "default")
    if not FRAME_STYLES[style] then style = "default" end
    return style
end

---------------------------------------------------------------------------
-- Map scale
--
-- How much of the room it is given the map actually takes. The drawer
-- stretches a widget to fill its width, so without this the only way to
-- change the size of the map is to change the width of the drawer - and
-- the frame costs about a fifth of that width, which is a fair reason to
-- want some of the map back.
--
-- It scales the map and the frame's host together rather than resizing
-- either. That is what makes one number mean the same thing under both
-- styles: Blizzard's ring is part of the map's own textures, and its zoom
-- and day/night buttons hang off them, so all of it scales at once and
-- stays where it belongs. Resizing the map would leave that ring behind
-- at its old size.
--
-- The widget still declares its full width, and only its height comes
-- down. The declared width is what the drawer divides by, so holding it
-- still is what turns the scale into a share of the drawer instead of
-- something the stretch that follows cancels straight back out.
---------------------------------------------------------------------------

local MAP_SCALE_KEY = "mapScale"
local MAP_SCALE_MIN, MAP_SCALE_MAX = 0.5, 1

function MapScale()
    local scale = tonumber(addon:GetWidgetSetting(WIDGET_ID, MAP_SCALE_KEY, 1)) or 1
    return math.max(MAP_SCALE_MIN, math.min(MAP_SCALE_MAX, scale))
end

-- How far the map is grown past the hole in the frame, so its edge slides
-- under the band. The art's inner edge is antialiased and the map's
-- circle does not quite reach the edge of the frame it is drawn in, so an
-- edge that only meets the art leaves a ring of background showing
-- through between the two.
--
-- In design pixels, which the drawer multiplies along with everything
-- else, so this is a few more on screen than it says. Two was not enough
-- to clear the gap; five is, and it costs a sliver of the band's inner
-- edge, which is the widest part of the picture and has it to spare. The
-- map comes out a little bigger for it, which is the other thing wanted.
local FRAME_OVERLAP = 5

local ring, ringHost

local function BlizzardRingTextures()
    return { MinimapBorder, MinimapNorthTag, MinimapCompassTexture }
end

-- Put the ring's host behind the map, wherever the map currently lives.
--
-- Behind, which means not a child of the Minimap: anything parented to it
-- draws over the map itself. Behind is also what keeps Blizzard's zoom
-- and day/night buttons usable. Those hang off MinimapBackdrop, out at
-- the ring's own radius, which is exactly where our band is - a frame
-- drawn over the map would bury them in it.
function HostRing(parent)
    if not (ringHost and parent and Minimap) then return end
    ringHost:SetParent(parent)
    ringHost:SetScale(Minimap:GetScale() or 1)
    ringHost:SetFrameStrata(Minimap:GetFrameStrata())
    ringHost:SetFrameLevel(math.max(0, (Minimap:GetFrameLevel() or 1) - 1))
    ringHost:ClearAllPoints()
    ringHost:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
end

local function EnsureRing()
    if ring then return ring end
    if not Minimap then return nil end

    ringHost = CreateFrame("Frame", nil, Minimap:GetParent() or UIParent)
    ringHost:SetSize(1, 1)
    HostRing(Minimap:GetParent() or UIParent)

    local Skin = BazUI.Skin
    ring = Skin.Theme.CreateArtRing(ringHost, {
        layer       = "ARTWORK",
        sublevel    = 0,
        texture     = Skin.MINIMAP_FRAME,
        widthRatio  = Skin.MINIMAP_FRAME_WIDTH,
        heightRatio = Skin.MINIMAP_FRAME_HEIGHT,
        overlap     = FRAME_OVERLAP,
    })
    ring:Hide()
    return ring
end

-- The map's diameter under the BazUI frame.
--
-- Measured from the widget's declared width, never from the map as it
-- stands: the map is shrunk to make room for the frame, and measuring the
-- shrunken map would shrink it again on every apply.
local function MapSizeFor(frame)
    return math.max(16, frame:InnerFor(nativeMapWidth or DEFAULT_SIZE))
end

-- What the widget asks the drawer for.
--
-- Proportions rather than sizes: the drawer scales a widget to fill its
-- width, so what these numbers decide is how that width is divided
-- between the map and the frame around it, and how much height the pair
-- needs. The frame keeps the declared width and gives the map what is
-- left inside the hole; it is taller than it is wide, because the points
-- at the top and bottom run past the circle.
local function Footprint()
    local width, height
    if GetFrameStyle() == "bazui" then
        local frame = EnsureRing()
        if frame then width, height = frame:Extent(MapSizeFor(frame)) end
    end
    if not width then
        local pad = VISUAL_PAD * 2
        width  = (nativeMapWidth  or DEFAULT_SIZE) + pad
        height = (nativeMapHeight or DEFAULT_SIZE) + pad
    end
    -- Full width, scaled height: see the note on the map scale above.
    return width, height * MapScale()
end

-- Tell the drawer what the widget wants now.
--
-- The two styles do not have the same shape, so switching between them
-- changes the room the widget needs. Docked, the host reads the footprint
-- back on the next reflow; floating, nothing else is going to resize the
-- wrapper, so set it here and let the reflow ignore it.
-- The map and the frame around it scale together, so they stay
-- concentric: both are centred on the wrapper, and a scale changes only
-- how big each one draws, never where its middle is.
function MinimapWidget:ApplyScale()
    if not Minimap then return end
    local scale = MapScale()
    Minimap:SetScale(scale)
    if ringHost then ringHost:SetScale(scale) end
end

function MinimapWidget:ApplyFootprint()
    if not (wrapper and widgetInfo) then return end
    local width, height = Footprint()
    widgetInfo.designWidth, widgetInfo.designHeight = width, height
    wrapper:SetSize(width, height)
    if addon.WidgetHost and addon.WidgetHost.Reflow then
        addon.WidgetHost:Reflow()
    end
end

function MinimapWidget:ApplyFrameStyle()
    local bazui = (GetFrameStyle() == "bazui")
    for _, tex in ipairs(BlizzardRingTextures()) do
        if tex and tex.SetAlpha then
            tex:SetAlpha(bazui and 0 or 1)
        end
    end
    if bazui then
        local frame = EnsureRing()
        if frame then
            local map = MapSizeFor(frame)
            raw.SetSize(Minimap, map, map)
            frame:SetInnerSize(map)
            frame:Show()
        end
    else
        if ring then ring:Hide() end
        if nativeMapWidth then raw.SetSize(Minimap, nativeMapWidth, nativeMapHeight) end
    end
    self:ApplyScale()
    self:ApplyFootprint()
end

---------------------------------------------------------------------------
-- Optional hiding of Blizzard's minimap buttons.
--
-- Each entry resolves its frames per flavour: Classic names the zoom
-- buttons MinimapZoomIn/Out, Retail hangs them off Minimap as ZoomIn/ZoomOut
-- (and only shows them on hover). GameTimeFrame is the day/night indicator
-- on Classic and the calendar button on Retail. Hiding installs a one-time
-- Show hook so Blizzard (or another addon) re-showing the button doesn't
-- undo the setting; turning the option off shows the frame again.
---------------------------------------------------------------------------

local HIDE_TARGETS = {
    hideDayNight = {
        order  = 21,
        name   = "Hide Day/Night Indicator",
        desc   = "Hides the sun/moon button on the minimap ring (the calendar button on Retail).",
        frames = function() return { GameTimeFrame } end,
    },
    hideZoomButtons = {
        order  = 22,
        name   = "Hide Zoom Buttons",
        desc   = "Hides the + and - zoom buttons. The mouse wheel still zooms the minimap.",
        frames = function()
            return {
                MinimapZoomIn  or (Minimap and Minimap.ZoomIn),
                MinimapZoomOut or (Minimap and Minimap.ZoomOut),
            }
        end,
    },
}

local hideHooked = {}

-- Apply one hide setting. `userToggled` is true when the player just
-- flipped the option; only then do we call Show() on the frames, because
-- at login Blizzard may legitimately keep them hidden (Retail's zoom
-- buttons appear on hover) and forcing them visible would be wrong.
local function ApplyHideSetting(key, userToggled)
    local def = HIDE_TARGETS[key]
    if not def then return end
    local hide = addon:GetWidgetSetting(WIDGET_ID, key, false) and true or false
    for _, f in ipairs(def.frames()) do
        if f and f.Hide then
            if hide then
                f:Hide()
                if not hideHooked[f] then
                    hideHooked[f] = true
                    hooksecurefunc(f, "Show", function(self)
                        if addon:GetWidgetSetting(WIDGET_ID, key, false) then
                            self:Hide()
                        end
                    end)
                end
            elseif userToggled then
                f:Show()
            end
        end
    end
end

function MinimapWidget:ApplyHideSettings()
    for key in pairs(HIDE_TARGETS) do
        ApplyHideSetting(key, false)
    end
end

function MinimapWidget:GetOptionsArgs()
    local args = {
        frameHeader = {
            order = 10,
            type  = "header",
            name  = "Minimap Frame",
        },
        [FRAME_STYLE_KEY] = {
            order  = 11,
            type   = "select",
            name   = "Frame Style",
            desc   = "The frame around the minimap. BazUI is the brass ring from the WoW Forever logo; Blizzard Default keeps the game's own.",
            values = FRAME_STYLES,
            get    = function() return GetFrameStyle() end,
            set    = function(_, val)
                if not FRAME_STYLES[val] then val = "default" end
                addon:SetWidgetSetting(WIDGET_ID, FRAME_STYLE_KEY, val)
                MinimapWidget:ApplyFrameStyle()
            end,
        },
        [MAP_SCALE_KEY] = {
            order     = 12,
            type      = "range",
            name      = "Map Scale",
            desc      = "How much of the drawer's width the minimap takes. Below 100% it sits smaller, centered, with room to spare either side. For a map bigger than that, widen the drawer.",
            min       = MAP_SCALE_MIN,
            max       = MAP_SCALE_MAX,
            step      = 0.05,
            isPercent = true,
            format    = function(value)
                return string.format("%d%%", math.floor(value * 100 + 0.5))
            end,
            get       = function() return MapScale() end,
            set       = function(_, val)
                addon:SetWidgetSetting(WIDGET_ID, MAP_SCALE_KEY, tonumber(val) or 1)
                MinimapWidget:ApplyScale()
                MinimapWidget:ApplyFootprint()
            end,
        },
        buttonsHeader = {
            order = 20,
            type  = "header",
            name  = "Minimap Buttons",
        },
    }
    for key, def in pairs(HIDE_TARGETS) do
        args[key] = {
            order = def.order,
            type  = "toggle",
            name  = def.name,
            desc  = def.desc,
            get   = function() return addon:GetWidgetSetting(WIDGET_ID, key, false) and true or false end,
            set   = function(_, val)
                addon:SetWidgetSetting(WIDGET_ID, key, val and true or false)
                ApplyHideSetting(key, true)
            end,
        }
    end
    return args
end

function MinimapWidget:Init()
    if wrapper then return end
    if not Minimap then return end

    -- Query the Minimap's native (unscaled) size BEFORE we do anything.
    -- GetWidth returns the logical size regardless of SetScale.
    local mapW = Minimap:GetWidth() or DEFAULT_SIZE
    local mapH = Minimap:GetHeight() or DEFAULT_SIZE
    if not mapW or mapW == 0 then mapW = DEFAULT_SIZE end
    if not mapH or mapH == 0 then mapH = DEFAULT_SIZE end
    nativeMapWidth, nativeMapHeight = mapW, mapH

    -- Hide Blizzard's cluster shell
    HideMinimapCluster()

    -- The minimap sits in the middle of the wrapper, so whatever room the
    -- frame needs appears evenly around it. ApplyFrameStyle sets the real
    -- footprint once the style is known; this is only what the wrapper is
    -- born at.
    local wrapperW = mapW + VISUAL_PAD * 2
    local wrapperH = mapH + VISUAL_PAD * 2

    wrapper = CreateFrame("Frame", "BazUIDrawerMinimapWrapper", UIParent)
    wrapper:SetSize(wrapperW, wrapperH)

    widgetInfo = {
        id           = WIDGET_ID,
        label        = "Minimap",
        designWidth  = wrapperW,
        designHeight = wrapperH,
        frame        = wrapper,
        -- Asked on every reflow, so a style change is picked up even if
        -- something else in the drawer triggers the reflow first.
        GetDesiredHeight = function() return (select(2, Footprint())) end,
        OnDock       = function() AttachMinimap(wrapper) end,
        OnUndock     = function()
            -- When switching to floating mode or re-docking, we keep the
            -- wrapper as the Minimap's parent so the Minimap follows the
            -- wrapper wherever WidgetHost puts it.
            AttachMinimap(wrapper)
        end,
        GetOptionsArgs = function() return MinimapWidget:GetOptionsArgs() end,
    }

    BazUI:RegisterDockableWidget(widgetInfo)

    -- Parent the minimap right away so it's ready before the widget
    -- host's first reflow.
    AttachMinimap(wrapper)
    EnableWheelZoom()
    self:ApplyFrameStyle()
    self:ApplyHideSettings()
end

BazUI:QueueForModule("Drawers", function()
    -- Small delay gives Blizzard Minimap finish init before we grab it.
    C_Timer.After(0.2, function() MinimapWidget:Init() end)
end)
