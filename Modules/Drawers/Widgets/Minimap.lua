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
-- Breathing room around the minimap inside the wrapper. Kept small
-- because it scales with everything else: the drawer sizes a widget by
-- its declared width, so eighteen pixels of padding around a hundred and
-- forty pixel map becomes fifty either side once the map is filling a
-- drawer, and the map ends up two thirds of the width it was given. The
-- border used to need the room - the old ring art hung outside the map -
-- and the drawn one sits inside the footprint instead.
local VISUAL_PAD   = 4
                        -- (bigger than it looks because the cardinal
                        -- decoration points extend past GetWidth/Height)

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

    -- Pin Minimap's own scale to 1.0 - the widget host's SetScale on the
    -- wrapper handles all visual sizing. A non-1.0 Minimap scale on top
    -- would multiply and break the layout.
    Minimap:SetScale(1.0)

    -- Suppress Blizzard Edit Mode handling for the Minimap
    if MinimapCluster and MinimapCluster.Selection then
        MinimapCluster.Selection:Hide()
        MinimapCluster.Selection.Show = MinimapCluster.Selection.Hide
    end

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
-- Init
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Minimap frame (ring) styles.
--
-- Blizzard draws its ring on MinimapBackdrop, which is a CHILD of the
-- Minimap on both flavours (Era: MinimapBorder + MinimapNorthTag +
-- MinimapCompassTexture; Retail: MinimapCompassTexture, the
-- ui-hud-minimap-frame atlas). Being a child, it follows the map into our
-- wrapper - that is why the stock ring shows up in the widget at all, and
-- why the zoom / tracking / day-night buttons (also MinimapBackdrop
-- children) sit on it.
--
-- The BazUI style fades Blizzard's ring textures to alpha 0 (Show/Hide
-- independent, so Blizzard toggling MinimapCompassTexture for the
-- rotate-minimap CVar can't bring them back) and draws our own ring on the
-- same backdrop frame, inheriting its exact layering: above the map
-- surface, below the buttons that live on the ring.
---------------------------------------------------------------------------

local FRAME_STYLE_KEY = "frameStyle"
local FRAME_STYLES = {
    default = "Blizzard Default",
    bazui   = "BazUI",
}

-- Assets\BazUI_Frame.png is 1024x1024 with the ring centered. Its inner
-- edge is 87% of the texture width; the N tag and
-- outer rim stay outside the map. Sized so the inner edge overlaps by a
-- few pixels to hide the mask's anti-aliasing.
-- The ring is drawn rather than painted: three circles around the map,
-- the same border the status bars wear, at a scale that suits something
-- this size. They sit behind the map, since a filled circle in front of
-- it is just a filled circle; what shows of each is the part the next
-- one does not cover, and the map itself covers the innermost.
local RING_SCALE = 2

local ring, ringHost

local function BlizzardRingTextures()
    return { MinimapBorder, MinimapNorthTag, MinimapCompassTexture }
end

local function EnsureRing()
    if ring then return ring end
    if not Minimap then return nil end

    -- Behind the map, which means not a child of it: anything parented
    -- to the minimap draws over the map itself.
    ringHost = CreateFrame("Frame", nil, Minimap:GetParent() or UIParent)
    ringHost:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
    ringHost:SetSize(1, 1)
    ringHost:SetFrameStrata(Minimap:GetFrameStrata())
    ringHost:SetFrameLevel(math.max(0, (Minimap:GetFrameLevel() or 1) - 1))

    ring = BazUI.Skin.Theme.CreateRoundRing(ringHost, {
        layer = "ARTWORK", sublevel = 0, scale = RING_SCALE,
    })
    ring:Hide()
    return ring
end

local function LayoutRing()
    if not ring or not Minimap then return end
    -- Sized from the widget's own footprint, never from the map as it
    -- stands: the map is shrunk to make room for the border, and
    -- measuring the shrunken map would shrink it again on every apply.
    local d = nativeMapWidth or DEFAULT_SIZE
    local mapSize = math.max(16, d - ring:Thickness() * 2)
    raw.SetSize(Minimap, mapSize, mapSize)
    ring:SetInnerSize(mapSize)
end

local function GetFrameStyle()
    local style = addon:GetWidgetSetting(WIDGET_ID, FRAME_STYLE_KEY, "default")
    if not FRAME_STYLES[style] then style = "default" end
    return style
end

function MinimapWidget:ApplyFrameStyle()
    local bazui = (GetFrameStyle() == "bazui")
    for _, tex in ipairs(BlizzardRingTextures()) do
        if tex and tex.SetAlpha then
            tex:SetAlpha(bazui and 0 or 1)
        end
    end
    if bazui then
        local drawn = EnsureRing()
        if drawn then
            LayoutRing()
            drawn:Show()
        end
    else
        if ring then ring:Hide() end
        if nativeMapWidth then raw.SetSize(Minimap, nativeMapWidth, nativeMapHeight) end
    end
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
            desc   = "The ring drawn around the minimap. BazUI is the Baz Suite's brass ring; Blizzard Default keeps the game's own frame.",
            values = FRAME_STYLES,
            get    = function() return GetFrameStyle() end,
            set    = function(_, val)
                if not FRAME_STYLES[val] then val = "default" end
                addon:SetWidgetSetting(WIDGET_ID, FRAME_STYLE_KEY, val)
                MinimapWidget:ApplyFrameStyle()
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

    -- Wrapper is slightly larger than the minimap so the circular edge
    -- isn't flush against the widget border. The minimap is centered in
    -- the wrapper, so the padding appears evenly on all sides.
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
