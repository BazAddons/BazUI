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

-- Defined with the frame styles further down, called from AttachMinimap
-- above it.
local MapScale

---------------------------------------------------------------------------
-- Parent the Minimap into the given frame (either the wrapper when docked,
-- or the wrapper when floating - the wrapper is always its immediate
-- parent; only the wrapper's own parent changes based on dock/float).
---------------------------------------------------------------------------

local pendingAttach

local function AttachMinimap(parent)
    if not Minimap or not parent then return end
    if minimapParentedInto == parent then return end

    -- The Minimap is a protected frame; reparenting and anchoring it in
    -- combat is refused, and marking it done anyway is how a reload
    -- mid-fight left the map sitting in the middle of the screen. Park
    -- the request and do it when the fight ends.
    if InCombatLockdown() and Minimap:IsProtected() then
        pendingAttach = parent
        return
    end
    pendingAttach = nil

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

    -- The game's own Edit Mode selection overlay for the minimap, kept
    -- down. This used to do `Selection.Show = Selection.Hide`, which
    -- writes to the method table of a frame we do not own: on Forever the
    -- write does not survive and Blizzard's own Show call then finds a
    -- nil, which is exactly how the objective tracker and the nameplates
    -- broke. SuppressFrame appends an OnShow handler and writes nothing.
    if MinimapCluster and MinimapCluster.Selection then
        BazUI.SuppressFrame(MinimapCluster.Selection, function() return true end)
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

-- Whether the wheel is already wired, held here rather than as a field on
-- Blizzard's frame. A field we write onto one of their frames counts as
-- ours from then on, and their code reading it back carries that with it -
-- which is how hiding an action bar ended up tainting Edit Mode.
local wheelZoomed = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- Shift-right-click for the calendar
--
-- The game hangs its calendar off a button on the minimap, and BazUI
-- takes that whole cluster away. Shift and right click is free here, so
-- it is the obvious home for the thing that used to sit an inch away.
--
-- The map's own click handler pings the spot under the cursor, and it
-- does that for every mouse button - Blizzard's handler reads the
-- cursor, never the button, on all three clients. A hook cannot call
-- that off, so this stands in front of the handler instead of behind
-- it: our combination opens the calendar and stops there, and every
-- other click is handed to Blizzard's own script untouched, through
-- securecallfunction so the ping still runs as the game's own code.
---------------------------------------------------------------------------

local function OpenCalendar()
    if BazUI.Codex and BazUI.Codex.OpenCalendar then
        BazUI.Codex.OpenCalendar()
    elseif _G.ToggleCalendar then
        if securecallfunction then
            securecallfunction(_G.ToggleCalendar)
        else
            _G.ToggleCalendar()
        end
    end
end

local function EnableCalendarClick()
    if not Minimap or Minimap._bazCalendarHooked then return end
    Minimap._bazCalendarHooked = true

    local theirs = Minimap:GetScript("OnMouseUp")
    Minimap:SetScript("OnMouseUp", function(self, button, ...)
        if button == "RightButton" and IsShiftKeyDown() then
            OpenCalendar()
            return
        end
        if theirs then
            if securecallfunction then
                securecallfunction(theirs, self, button, ...)
            else
                theirs(self, button, ...)
            end
        end
    end)
end

local function EnableWheelZoom()
    if not Minimap or wheelZoomed[Minimap] then return end
    wheelZoomed[Minimap] = true
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
    -- No frame at all: the game's ring faded out and ours never drawn,
    -- leaving the bare map. A third answer to the question this dropdown
    -- already asks, rather than a switch beside it - a switch could say
    -- "hidden" while this said "BazUI", and then neither of them is the
    -- answer.
    none    = "None",
}

-- The suite's own frame is what this module is for, so it is what a new
-- profile gets. Blizzard Default and None are there for anyone who wants
-- them back.
local function GetFrameStyle()
    local style = addon:GetWidgetSetting(WIDGET_ID, FRAME_STYLE_KEY, "bazui")
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

-- Nine tenths rather than all of it: the frame's points run past the
-- circle, and a little room around the widget keeps them off whatever is
-- docked above and below.
local MAP_SCALE_DEFAULT = 0.9

function MapScale()
    local scale = tonumber(addon:GetWidgetSetting(WIDGET_ID, MAP_SCALE_KEY,
        MAP_SCALE_DEFAULT)) or MAP_SCALE_DEFAULT
    return math.max(MAP_SCALE_MIN, math.min(MAP_SCALE_MAX, scale))
end

-- How far the brass sits over the edge of the map.
--
-- Now that the map is never resized, this is the only number deciding
-- where the frame's opening falls: the art is sized so its opening is
-- this much smaller than the map, all the way round.
--
-- It has to cover more than nothing, because the map's round edge does
-- not quite reach the edge of the square it is drawn in, and the last
-- steps of the artwork's own alpha are not solid either. Between the two
-- there was a ring of sky showing through. In design pixels, which the
-- drawer multiplies, so this is a few more than it says on screen.
local FRAME_OVERLAP = 5

local ring

-- Every piece of the game's own ring, found rather than listed.
--
-- The named three were Era's and retail's, and they missed Forever's: this
-- client draws the ring from Skin.lua as MinimapCompassTexture plus a
-- MinimapCompassTextureUnderlay when the map rotates, and the runes showed
-- through our frame because nothing here knew that second name.
--
-- Naming them one client at a time is a losing game, so the named ones are
-- a floor and the rest are swept off MinimapBackdrop - which is the frame
-- Blizzard draws its ring on, and where ours goes too. Our own art is
-- skipped by identity, so the sweep cannot fade the frame it is protecting.
local function BlizzardRingTextures()
    local found = { MinimapBorder, MinimapNorthTag,
                    MinimapCompassTexture, _G.MinimapCompassTextureUnderlay }

    local backdrop = MinimapBackdrop
    if backdrop and backdrop.GetRegions then
        local ours = ring and ring.art
        for _, region in ipairs({ backdrop:GetRegions() }) do
            if region ~= ours and region.SetAlpha and region.GetObjectType
                and region:GetObjectType() == "Texture" then
                found[#found + 1] = region
            end
        end
    end

    return found
end

-- Where the frame is drawn.
--
-- On MinimapBackdrop, which is the frame Blizzard draws its own ring on,
-- so ours inherits exactly the layering theirs had: over the map surface,
-- under the buttons that live out on the ring. That matters twice over.
-- The zoom and day/night buttons hang off this frame at the ring's own
-- radius, which is where our brass is, and a frame drawn over the whole
-- lot would bury them. And the artwork casts a shadow inwards, which is
-- only a shadow if it falls on the map - drawn behind, the map covers it
-- and the picture loses the thing that made it sit in the frame rather
-- than beside it.
--
-- A texture on that frame rather than a child frame of it: a texture
-- cannot come out above the buttons, and a child frame's level would be
-- ours to get wrong. Being inside the Minimap, it also takes the map's
-- own scale without being told.
-- See Core/Compat.lua.
BazUI:RegisterDependency({
    module = "Minimap",
    label  = "MinimapBackdrop",
    why    = "Where the frame is drawn, over the map and under the ring buttons. Without it the frame falls back onto the Minimap itself and covers them.",
    check  = function() return BazUI.Has.Frame("MinimapBackdrop") end,
})

local function RingParent()
    return MinimapBackdrop or Minimap
end

local function EnsureRing()
    if ring then return ring end
    if not Minimap then return nil end

    local Skin = BazUI.Skin
    ring = Skin.Theme.CreateArtRing(RingParent(), {
        layer       = "ARTWORK",
        sublevel    = 2,
        anchor      = Minimap,
        texture     = Skin.MINIMAP_FRAME,
        widthRatio  = Skin.MINIMAP_FRAME_WIDTH,
        heightRatio = Skin.MINIMAP_FRAME_HEIGHT,
        overlap     = FRAME_OVERLAP,
    })
    ring:Hide()
    return ring
end

-- The map is never resized. The frame is sized around it.
--
-- The game draws the terrain at whatever size the Minimap frame is, but
-- it does not lay the blips out from that size - a quest marker, a
-- tracking dot, a party member all sit at radii worked out from the size
-- the minimap was born at. Shrink the frame and the terrain follows while
-- the blips do not, so the ones near the rim end up outside the smaller
-- circle and the terrain's own round edge cuts them in half.
--
-- Scaling is not the same thing and is not affected: the drawer has
-- always scaled this whole widget, blips and all.
--
-- So the map keeps its native size and the frame is drawn around it,
-- which makes the widget wider than the map rather than the other way
-- about. The drawer then fits the pair of them to its width as it fits
-- everything else.
local function MapDiameter()
    return nativeMapWidth or DEFAULT_SIZE
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
        if frame then width, height = frame:Extent(MapDiameter()) end
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
-- concentric: both are centered on the wrapper, and a scale changes only
-- how big each one draws, never where its middle is.
function MinimapWidget:ApplyScale()
    if not Minimap then return end
    -- One call: the frame is drawn inside the Minimap, so it takes this
    -- with everything else the map carries.
    Minimap:SetScale(MapScale())
end

-- `settled` is for the dock and undock hooks, which run inside a
-- reflow: the host is already laying the widget out, so telling it to
-- start again is asking it to redo the pass it is halfway through. The
-- new size is written down and the pass that is running picks it up.
function MinimapWidget:ApplyFootprint(settled)
    if not (wrapper and widgetInfo) then return end
    local width, height = Footprint()
    widgetInfo.designWidth, widgetInfo.designHeight = width, height
    wrapper:SetSize(width, height)
    if settled then return end
    if addon.WidgetHost and addon.WidgetHost.Reflow then
        addon.WidgetHost:Reflow()
    end
end

function MinimapWidget:ApplyFrameStyle(settled)
    local style = GetFrameStyle()
    local bazui = (style == "bazui")

    -- The game's own ring belongs to the game's own style, and nothing
    -- else: ours covers it, and None means none.
    for _, tex in ipairs(BlizzardRingTextures()) do
        if tex and tex.SetAlpha then
            tex:SetAlpha(style == "default" and 1 or 0)
        end
    end

    -- Native, always. See MapDiameter.
    if nativeMapWidth then raw.SetSize(Minimap, nativeMapWidth, nativeMapHeight) end

    if bazui then
        local frame = EnsureRing()
        if frame then
            frame:SetInnerSize(MapDiameter())
            frame:Show()
        end
    elseif ring then
        ring:Hide()
    end
    self:ApplyScale()
    self:ApplyFootprint(settled)
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

-- Both start hidden. The wheel zooms, which is what the buttons were for,
-- and the day/night dial is an ornament on a ring we are not drawing any
-- more - left on, they sit on the brass looking like something that came
-- loose.
local HIDE_TARGETS = {
    hideDayNight = {
        default = true,
        order  = 21,
        name   = "Hide Day/Night Indicator",
        desc   = "Hides the sun/moon button on the minimap ring (the calendar button on Retail).",
        frames = function() return { GameTimeFrame } end,
    },
    hideZoomButtons = {
        default = true,
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


-- Apply one hide setting. `userToggled` is true when the player just
-- flipped the option; only then do we call Show() on the frames, because
-- at login Blizzard may legitimately keep them hidden (Retail's zoom
-- buttons appear on hover) and forcing them visible would be wrong.
local function ApplyHideSetting(key, userToggled)
    local def = HIDE_TARGETS[key]
    if not def then return end
    local hide = addon:GetWidgetSetting(WIDGET_ID, key, def.default or false)
        and true or false
    for _, f in ipairs(def.frames()) do
        if f and f.Hide then
            if hide then
                -- Through the shared suppressor: it hooks OnShow rather
                -- than writing to the frame's method table, which on
                -- Forever leaves Blizzard's own Show() calling a nil.
                BazUI.SuppressFrame(f, function()
                    return addon:GetWidgetSetting(WIDGET_ID, key, def.default or false) and true or false
                end)
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
            desc   = "The frame around the minimap. BazUI is the brass ring from the WoW Forever logo, Blizzard Default keeps the game's own, and None leaves the map bare.",
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
            desc      = "How big the map draws. In a drawer this is how much of the drawer's width it takes, and below 100% it sits centered with room either side. Floating, it is simply the size of the map.",
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
            get   = function()
                return addon:GetWidgetSetting(WIDGET_ID, key, def.default or false)
                    and true or false
            end,
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
    -- Invisible until the dock has put it somewhere. A frame born at the
    -- center of the screen and left there by combat should not be seen
    -- there; alpha is the one thing combat lets us change.
    wrapper:SetAlpha(0)

    -- Anchored straight away, though the dock will place it properly and
    -- clear this when it does. The Minimap ends up parented to this, and
    -- a frame with no anchor has no resolved position - so GetLeft() on
    -- the Minimap would answer nil, and there are a great many addons
    -- that work out where to put their minimap button by reading exactly
    -- that. Somewhere is better than nowhere.
    wrapper:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    widgetInfo = {
        id           = WIDGET_ID,
        label        = "Minimap",
        -- The map scales itself rather than letting the frame around it
        -- be scaled, so that the map and the ring drawn round it stay
        -- concentric. Map Scale below is the one control; the host does
        -- not offer its own on top of it.
        ownsScale    = true,
        designWidth  = wrapperW,
        designHeight = wrapperH,
        frame        = wrapper,
        -- Asked on every reflow, so a style change is picked up even if
        -- something else in the drawer triggers the reflow first.
        GetDesiredHeight = function() return (select(2, Footprint())) end,
        -- Docked and floating are not the same size.
        --
        -- In a drawer the wrapper is scaled to the drawer's width and
        -- the map fills it; floating there is nothing to fill, so the
        -- map draws at its own size and the wrapper has to be told what
        -- that is. Re-applying the style does all of it - the map's
        -- native size, the ring drawn round it, the scale and the
        -- footprint - so the transition either way is one call.
        OnDock       = function()
            AttachMinimap(wrapper)
            wrapper:SetAlpha(1)
            MinimapWidget:ApplyFrameStyle(true)
        end,
        OnUndock     = function()
            -- The wrapper stays the Minimap's parent through both, so
            -- the map follows it wherever the host puts it.
            AttachMinimap(wrapper)
            wrapper:SetAlpha(1)
            MinimapWidget:ApplyFrameStyle(true)
        end,
        GetOptionsArgs = function() return MinimapWidget:GetOptionsArgs() end,
    }

    BazUI:RegisterDockableWidget(widgetInfo)

    -- Parent the minimap right away so it's ready before the widget
    -- host's first reflow.
    AttachMinimap(wrapper)

    -- And again when a fight that refused it ends.
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:SetScript("OnEvent", function()
        if pendingAttach then
            local parent = pendingAttach
            AttachMinimap(parent)
            if MinimapWidget.ApplyFrameStyle then MinimapWidget:ApplyFrameStyle() end
        end
    end)
    EnableWheelZoom()
    EnableCalendarClick()
    self:ApplyFrameStyle()
    self:ApplyHideSettings()
end

BazUI:QueueForModule("Drawers", function()
    -- Small delay gives Blizzard Minimap finish init before we grab it.
    C_Timer.After(0.2, function() MinimapWidget:Init() end)
end)
