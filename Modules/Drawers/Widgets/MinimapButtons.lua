-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: MinimapButtons
--
-- Scans the Minimap for addon buttons and reparents them into a grid
-- inside the drawer. LibDBIcon buttons are recognized by name
-- (LibDBIcon10_<Name>). Addons that roll their own button (Vaultloom,
-- Zygor, ...) are caught by a conservative heuristic: a *named* Button
-- child of Minimap, roughly minimap-button sized, whose name doesn't
-- look like Blizzard chrome or a map pin. Unnamed frames (pins from
-- HandyNotes, gathering addons, ...) never qualify.
--
-- Buttons are adopted at login (after a short delay so other addons
-- finish registering), again a few seconds later for slow starters,
-- whenever LibDBIcon reports a new icon, after any addon finishes
-- loading (load-on-demand), and on demand via the widget's "Re-scan"
-- option. Original parent + anchor are saved so we can release buttons
-- back to the minimap on unload if ever needed.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_minimapbuttons"
local DESIGN_WIDTH = 220
local PAD          = 8
local BUTTON_SIZE  = 28
local BUTTON_GAP   = 4
local MIN_HEIGHT   = PAD * 2 + BUTTON_SIZE

-- Slot grid: the widget pre-builds this many empty slot frames. Each
-- adopted button gets reparented into a slot, which pins its CENTER to
-- the slot's CENTER so positioning is immune to SetPoint clobbering.
-- Empty slots are hidden; visible buttons fill slots in order. Future
-- custom-ordering can map button name > slot index via a persisted
-- table without changing any of the rendering code.
local INITIAL_SLOTS = 12  -- pre-built; LayoutButtons grows the pool on demand

-- Queue eye (dungeon/raid/PVP LFG button). Lives in MicroMenuContainer,
-- not Minimap, so it needs special handling outside the normal scanner.
-- It's also dynamically shown/hidden by Blizzard based on queue state -
-- LayoutButtons already filters by IsShown() so we just need to re-run
-- the layout on queue events.
local QUEUE_EYE_EVENTS = {
    "LFG_UPDATE",
    "LFG_PROPOSAL_SHOW",
    "LFG_PROPOSAL_FAILED",
    "LFG_PROPOSAL_SUCCEEDED",
    "LFG_LIST_APPLICATION_STATUS_UPDATED",
    "LFG_ROLE_CHECK_SHOW",
    "LFG_ROLE_CHECK_HIDE",
    "PVP_QUEUE_STATUS_UPDATE",
    "UPDATE_BATTLEFIELD_STATUS",
    "PVEFRAME_SHOW",
    "PLAYER_ENTERING_WORLD",
}

---------------------------------------------------------------------------
-- Adoption filter.
--
-- 1. LibDBIcon buttons (LibDBIcon10_*) are always adopted.
-- 2. Names on KNOWN_MINIMAP_BUTTONS are always adopted, even if they'd
--    fail the heuristic below.
-- 3. Anything else must be a *named* Button parented to Minimap, sized
--    like a minimap button (MIN_ADOPT_SIZE..MAX_ADOPT_SIZE px), with a
--    name that doesn't match Blizzard chrome or map-pin patterns.
--
-- The name requirement is what keeps map-pin addons (HandyNotes,
-- gathering trackers, ...) from flooding the grid: their pins are
-- unnamed Button children of Minimap. Names are also how the custom
-- ordering setting refers to buttons, so unnamed frames couldn't be
-- managed anyway.
---------------------------------------------------------------------------

-- Non-LibDBIcon minimap buttons from known addons that we always adopt.
local KNOWN_MINIMAP_BUTTONS = {
    ["LFGMinimapFrame"]            = true,
    ["MiniMapMailFrame"]           = true,
    ["BazUIMinimapButton"]       = true,
    ["ZygorGuidesViewerMapIcon"]   = true,
    ["VaultloomMinimapButton"]     = true,
}

-- Never adopt these even if they pass the heuristic.
local EXCLUDED_MINIMAP_BUTTONS = {
    ["MinimapZoomIn"]      = true,
    ["MinimapZoomOut"]     = true,
    ["QueueStatusButton"]  = true,  -- adopted via its own special path
    ["GameTimeFrame"]      = true,
    ["MiniMapTracking"]    = true,
}

-- Name fragments that mark Blizzard chrome or per-location pins rather
-- than a launcher button.
local EXCLUDED_NAME_PATTERNS = {
    "^Minimap", "^MiniMap", "^Blizzard", "^ExpansionLandingPage",
    "^AddonCompartment", "^GarrisonLandingPage", "^HandyNotes", "^TomTom",
    "Pin%d*$", "Pin[A-Z_]", "Waypoint", "Arrow", "Node", "Blip", "POI",
}

local MIN_ADOPT_SIZE = 20
local MAX_ADOPT_SIZE = 48

local function LooksLikeLauncherName(name)
    if EXCLUDED_MINIMAP_BUTTONS[name] then return false end
    for _, pat in ipairs(EXCLUDED_NAME_PATTERNS) do
        if name:find(pat) then return false end
    end
    return true
end

local function IsAdoptable(frame)
    if not (frame and frame.IsObjectType and frame.GetName) then return false end

    -- A Button, or something we have named ourselves. The mail notice is
    -- a Frame rather than a Button - it is told to you, not clicked - and
    -- it is still a thing sitting loose on the map that belongs in the
    -- row with the rest. Anything unnamed stays out either way: the name
    -- is how the ordering setting refers to a button.
    if not frame:IsObjectType("Button")
        and not KNOWN_MINIMAP_BUTTONS[frame:GetName() or ""] then
        return false
    end
    -- Either of the minimap's two homes for a button. Blizzard hangs
    -- several of its own off MinimapBackdrop rather than the Minimap -
    -- the group finder eye among them, which is how that one went on
    -- sitting loose on the map while everything else was collected.
    local parent = frame:GetParent()
    if parent ~= Minimap and parent ~= MinimapBackdrop then return false end
    local name = frame:GetName()
    if not name or name == "" then return false end

    -- LibDBIcon buttons always match this prefix
    if name:match("^LibDBIcon10_") then return true end

    -- Known non-LibDBIcon minimap buttons
    if KNOWN_MINIMAP_BUTTONS[name] then return true end

    -- Heuristic for everything else: launcher-sized, launcher-named.
    if not LooksLikeLauncherName(name) then return false end
    local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
    if w < MIN_ADOPT_SIZE or w > MAX_ADOPT_SIZE then return false end
    if h < MIN_ADOPT_SIZE or h > MAX_ADOPT_SIZE then return false end
    return true
end

---------------------------------------------------------------------------
-- Widget
---------------------------------------------------------------------------

local MinimapButtonsWidget = {}
addon.MinimapButtonsWidget = MinimapButtonsWidget

---------------------------------------------------------------------------
-- Custom button order.
--
-- The per-widget setting `buttonOrder` is a list of button names in
-- display order. Buttons not listed appear after the listed ones in
-- alphabetical order. New buttons are appended to the list on first
-- adoption so the order is complete by default; the user can then
-- rearrange via Move Up / Move Down controls on the widget's settings
-- page. The sort in LayoutButtons uses this order first, then
-- alphabetical for any unlisted button.
---------------------------------------------------------------------------

local function GetButtonOrder()
    return addon:GetWidgetSetting(WIDGET_ID, "buttonOrder", nil) or {}
end

local function SetButtonOrder(list)
    addon:SetWidgetSetting(WIDGET_ID, "buttonOrder", list)
end

local function EnsureButtonInOrder(name)
    if not name or name == "" then return end
    local order = GetButtonOrder()
    for _, n in ipairs(order) do
        if n == name then return end
    end
    table.insert(order, name)
    SetButtonOrder(order)
end

local function MoveButtonInOrder(name, delta)
    local order = GetButtonOrder()
    local idx
    for i, n in ipairs(order) do
        if n == name then idx = i; break end
    end
    if not idx then return end
    local newIdx = idx + delta
    if newIdx < 1 or newIdx > #order then return end
    order[idx], order[newIdx] = order[newIdx], order[idx]
    SetButtonOrder(order)
end

function MinimapButtonsWidget:MoveButtonUp(name)
    MoveButtonInOrder(name, -1)
    self:LayoutButtons()
end

function MinimapButtonsWidget:MoveButtonDown(name)
    MoveButtonInOrder(name, 1)
    self:LayoutButtons()
end

-- [button] = { parent, points = {{point, rel, relPoint, x, y}, ...},
--               isScaled = bool, nativeSize = {w,h}, nativeScale = number }
local adopted = {}

---------------------------------------------------------------------------
-- Button skins.
--
-- Every addon ships its own minimap button art: LibDBIcon's 31px button
-- with a 17px icon, a tracking-border ring and a background disc, plus
-- countless hand-rolled variants. The optional BazUI style unifies them:
-- the icon is centered, cropped and clipped to a circle, the addon's own
-- ring / background textures are faded out, and a drawn border
-- is drawn over the top so every button wears the same brass ring.
--
-- Everything touched is recorded per button so switching back to Blizzard
-- Default restores each one exactly as it was adopted. The queue eye is
-- left alone - it's a compound Blizzard frame with its own animation, not
-- an icon button - as is any button whose icon we can't identify.
---------------------------------------------------------------------------

local STYLE_KEY = "buttonStyle"
local BUTTON_STYLES = {
    default = "Blizzard Default",
    bazui   = "BazUI",
}

-- The icon is 70% of the button, and the drawn border goes around it.
local RING_INNER_RATIO = 0.70
local ICON_OVERLAP     = 1     -- px the icon extends under the ring, per side
local ICON_CROP        = 0.06  -- texcoord inset (on top of the addon's own) trimming baked-in icon borders
local ICON_MASK_FILE   = BazUI.Skin.ROUND_MASK

-- Solid disc behind the icon so artwork with transparent areas reads as
-- solid as the rest. Drawn as a plain texture, the portrait mask file is
-- a white circle, so it doubles as the disc once tinted.
local BACKDROP_KEY   = "iconBackdrop"
local BACKDROP_COLOR = { 0.07, 0.07, 0.09, 1 }

-- Stock minimap-button chrome, by file data ID and by path fragment.
local CHROME_FILE_IDS = {
    [136430] = true, -- Interface\Minimap\MiniMap-TrackingBorder
    [136467] = true, -- Interface\Minimap\UI-Minimap-Background
}
local CHROME_PATH_FRAGMENTS = { "minimap%-trackingborder", "ui%-minimap%-background" }

local skins = {}

local function GetButtonStyle()
    local style = addon:GetWidgetSetting(WIDGET_ID, STYLE_KEY, "default")
    if not BUTTON_STYLES[style] then style = "default" end
    return style
end

local function IsChromeTexture(region)
    if not region or not region.GetTexture then return false end
    local tex = region:GetTexture()
    if type(tex) == "number" then return CHROME_FILE_IDS[tex] or false end
    if type(tex) == "string" then
        local path = tex:lower():gsub("/", "\\")
        for _, frag in ipairs(CHROME_PATH_FRAGMENTS) do
            if path:find(frag) then return true end
        end
    end
    return false
end

local function IsTexture(region)
    return region and region.GetObjectType and region:GetObjectType() == "Texture"
end

-- The button's icon: the conventional `icon` key first, then the largest
-- texture that isn't chrome or one of the button's state textures, then
-- a texture one level down in a child frame, then the normal texture for
-- buttons that use it as their icon.
local function FindIcon(btn)
    local icon = btn.icon or btn.Icon
    if IsTexture(icon) then return icon end

    local state = {}
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local tex = btn[getter] and btn[getter](btn)
        if tex then state[tex] = true end
    end

    local best, bestArea
    for _, region in ipairs({ btn:GetRegions() }) do
        if IsTexture(region) and not state[region] and not IsChromeTexture(region)
            and region:GetDrawLayer() ~= "HIGHLIGHT" then
            local w, h = region:GetSize()
            local area = (w or 0) * (h or 0)
            if area > 0 and (not bestArea or area > bestArea) then
                best, bestArea = region, area
            end
        end
    end
    if best then return best end

    -- A button whose icon is not on the button. The group finder eye is
    -- a child frame with an animated sheet inside it, so nothing on the
    -- button itself is the icon and the whole thing went unskinned: raw
    -- artwork at its own size, sitting over our ring rather than in it.
    -- One level is enough for the shape; going deeper would start
    -- finding things that are not icons.
    for _, child in ipairs({ btn:GetChildren() }) do
        local named = child.Texture or child.icon or child.Icon
        if IsTexture(named) then return named end
        for _, region in ipairs({ child:GetRegions() }) do
            if IsTexture(region) and not IsChromeTexture(region)
                and region:GetDrawLayer() ~= "HIGHLIGHT" then
                return region
            end
        end
    end

    return btn.GetNormalTexture and btn:GetNormalTexture() or nil
end

-- Axis-aligned rect from GetTexCoord's 8 values (ULx,ULy, LLx,LLy, URx,URy,
-- LRx,LRy). Rotated quads return nil and are left uncropped.
local function RectFromCoords(c)
    if c and #c == 8 and c[1] == c[3] and c[2] == c[6] and c[5] == c[7] and c[4] == c[8] then
        return c[1], c[5], c[2], c[4]
    end
    return nil
end

-- A masked texture rejects SetTexCoord ("Cannot set tex coords when
-- texture has mask"), yet addons keep calling it on their icon - LibDBIcon
-- does on every mouse down and up. While a skin is active the icon carries
-- a per-object SetTexCoord that lifts the mask, applies the coords with our
-- inset on top, and puts the mask back. The addon's press effect survives
-- and it never sees the mask. Removed again on unskin.
local function InstallCoordWrapper(s)
    if s.wrapped then return end
    local icon = s.icon
    s.rawSetTexCoord = rawget(icon, "SetTexCoord")
    local base = icon.SetTexCoord
    icon.SetTexCoord = function(self, ...)
        local n = select("#", ...)
        local l, r, tp, b = ...
        if s.masked then self:RemoveMaskTexture(s.mask) end
        if n == 4 and type(l) == "number" and type(r) == "number"
            and type(tp) == "number" and type(b) == "number" then
            s.wantL, s.wantR, s.wantT, s.wantB = l, r, tp, b
            local dx, dy = (r - l) * ICON_CROP, (b - tp) * ICON_CROP
            base(self, l + dx, r - dx, tp + dy, b - dy)
        else
            base(self, ...)
        end
        if s.masked then self:AddMaskTexture(s.mask) end
    end
    s.wrapped = true
end

local function RemoveCoordWrapper(s)
    if not s.wrapped then return end
    s.icon.SetTexCoord = s.rawSetTexCoord
    s.wrapped = false
end

local function BackdropEnabled()
    local v = addon:GetWidgetSetting(WIDGET_ID, BACKDROP_KEY, nil)
    if v == nil then return true end
    return v and true or false
end

local function ApplyBackdrop(btn, s)
    if not s or not s.active then return end
    if not BackdropEnabled() then
        if s.backdrop then s.backdrop:Hide() end
        return
    end
    if not s.backdrop then
        s.backdrop = btn:CreateTexture(nil, "BACKGROUND", nil, -5)
        s.backdrop:SetTexture(ICON_MASK_FILE)
        s.backdrop:SetVertexColor(unpack(BACKDROP_COLOR))
    end
    -- An icon that itself sits at the very bottom of BACKGROUND would tie
    -- with the disc; lift it one sublevel (restored on unskin).
    local layer, sublevel = s.icon:GetDrawLayer()
    if layer == "BACKGROUND" and (sublevel or 0) <= -5 and not s.iconLayer then
        s.iconLayer = { layer, sublevel }
        s.icon:SetDrawLayer("BACKGROUND", -4)
    end
    s.backdrop:ClearAllPoints()
    s.backdrop:SetAllPoints(s.icon)
    s.backdrop:Show()
end

local function ApplyButtonSkin(btn)
    if btn == QueueStatusButton then return end
    local orig = adopted[btn]
    if orig and orig.isScaled then return end
    local s = skins[btn]
    if s and s.active then return end

    local icon = FindIcon(btn)
    if not icon then return end

    if not s then
        s = { icon = icon, hidden = {}, hiddenAlpha = {}, iconPoints = {} }
        skins[btn] = s
        s.iconW, s.iconH = icon:GetSize()
        for i = 1, icon:GetNumPoints() do
            s.iconPoints[i] = { icon:GetPoint(i) }
        end
        s.texCoord = { icon:GetTexCoord() }
        for _, region in ipairs({ btn:GetRegions() }) do
            if region ~= icon and IsTexture(region) and IsChromeTexture(region) then
                s.hidden[#s.hidden + 1] = region
                s.hiddenAlpha[region] = region:GetAlpha() or 1
            end
        end
        s.mask = btn:CreateMaskTexture()
        s.mask:SetTexture(ICON_MASK_FILE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        -- Drawn rather than a picture of a ring: three filled circles,
        -- the same border the status bars wear. They sit under the icon,
        -- since a filled circle drawn over one hides it; the picture
        -- they replace could sit on top only because it had a hole.
        s.ring = BazUI.Skin.Theme.CreateRoundRing(btn, { sublevel = -8 })
        s.ring:Hide()
    end

    -- Fresh baseline each activation: the icon is unmasked here, so these
    -- are the coords the addon currently wants.
    s.texCoord = { icon:GetTexCoord() }
    s.wantL, s.wantR, s.wantT, s.wantB = nil, nil, nil, nil

    for _, region in ipairs(s.hidden) do region:SetAlpha(0) end

    local size = (btn:GetWidth() or BUTTON_SIZE) * RING_INNER_RATIO + ICON_OVERLAP * 2
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetSize(size, size)
    s.ring:SetInnerSize(size)

    -- The rings take the bottom three sublevels, so an icon sitting down
    -- there has to come up or it draws inside its own border.
    local iconLayer, iconSub = icon:GetDrawLayer()
    if iconLayer == "BACKGROUND" and (iconSub or 0) <= -6 and not s.iconLayer then
        s.iconLayer = { iconLayer, iconSub }
        icon:SetDrawLayer("BACKGROUND", -5)
    end

    -- Icons the addon already masks (BazUI's own button uses SetMask,
    -- for one) reject SetTexCoord outright. Those keep their coords and
    -- their shape - we only center them and draw the ring. Detected by
    -- counting mask textures and, because SetMask masks don't count,
    -- by probing SetTexCoord with the coords it already has. The wrapper
    -- isn't installed yet here, so the probe hits the real method.
    s.foreignMask = (icon.GetNumMaskTextures and icon:GetNumMaskTextures() > 0)
        or not pcall(icon.SetTexCoord, icon, unpack(s.texCoord))

    if not s.foreignMask then
        -- Crop first (the wrapper applies ICON_CROP), then mask.
        InstallCoordWrapper(s)
        local l, r, tp, b = RectFromCoords(s.texCoord)
        if l then icon:SetTexCoord(l, r, tp, b) end
        s.mask:ClearAllPoints()
        s.mask:SetAllPoints(icon)
        if not s.masked then
            icon:AddMaskTexture(s.mask)
            s.masked = true
        end
    end
    s.ring:Show()
    s.active = true
    ApplyBackdrop(btn, s)
end

local function RemoveButtonSkin(btn)
    local s = skins[btn]
    if not s or not s.active then return end
    s.active = false
    s.ring:Hide()
    if s.backdrop then s.backdrop:Hide() end
    if s.iconLayer then
        s.icon:SetDrawLayer(s.iconLayer[1], s.iconLayer[2])
        s.iconLayer = nil
    end
    if s.masked then
        s.icon:RemoveMaskTexture(s.mask)
        s.masked = false
    end
    for _, region in ipairs(s.hidden) do
        region:SetAlpha(s.hiddenAlpha[region] or 1)
    end
    local icon = s.icon
    icon:ClearAllPoints()
    for _, p in ipairs(s.iconPoints) do
        icon:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end
    if s.iconW and s.iconW > 0 then icon:SetSize(s.iconW, s.iconH) end
    RemoveCoordWrapper(s)
    if not s.foreignMask then
        if s.wantL then
            -- The addon set coords while skinned; give it exactly those.
            icon:SetTexCoord(s.wantL, s.wantR, s.wantT, s.wantB)
        elseif s.texCoord and #s.texCoord == 8 then
            icon:SetTexCoord(unpack(s.texCoord))
        end
    end
end

function MinimapButtonsWidget:RefreshBackdrops()
    for btn, s in pairs(skins) do
        ApplyBackdrop(btn, s)
    end
end

function MinimapButtonsWidget:ApplyButtonStyle()
    local bazui = (GetButtonStyle() == "bazui")
    for btn in pairs(adopted) do
        if bazui then ApplyButtonSkin(btn) else RemoveButtonSkin(btn) end
    end
    self:LayoutButtons()
end

-- Build the fixed slot grid. Each slot is a frame at a pre-computed
-- (col, row) position with a fixed BUTTON_SIZE footprint. Buttons are
-- reparented into these slots and anchored CENTER-to-CENTER, which
-- makes positioning completely immune to Blizzard SetPoint clobbering.
function MinimapButtonsWidget:BuildSlots()
    if self.slots then return end
    self.slots = {}

    local f = self.frame
    local usableWidth = DESIGN_WIDTH - PAD * 2
    local cols = math.max(1, math.floor((usableWidth + BUTTON_GAP) / (BUTTON_SIZE + BUTTON_GAP)))
    self._cols = cols

    for i = 1, INITIAL_SLOTS do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local slot = CreateFrame("Frame", nil, f)
        slot:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        slot:SetPoint("TOPLEFT", f, "TOPLEFT",
            PAD + col * (BUTTON_SIZE + BUTTON_GAP),
            -PAD - row * (BUTTON_SIZE + BUTTON_GAP))
        slot:Hide()  -- empty until a button is assigned in LayoutButtons
        self.slots[i] = slot
    end
end

-- opts.useScale = true to rescale the button via SetScale instead of SetSize
-- (required for compound frames like QueueStatusButton whose child frames
-- have their own hard-coded sizes that SetSize can't reach).
function MinimapButtonsWidget:AdoptButton(btn, opts)
    if adopted[btn] then return end
    opts = opts or {}
    local orig = {
        parent      = btn:GetParent(),
        points      = {},
        isScaled    = opts.useScale and true or false,
        nativeW     = btn:GetWidth(),
        nativeH     = btn:GetHeight(),
        nativeScale = btn:GetScale(),
    }
    for i = 1, btn:GetNumPoints() do
        orig.points[i] = { btn:GetPoint(i) }
    end
    adopted[btn] = orig

    -- Some buttons are adopted long before they are ever shown: the
    -- group finder eye exists from login and turns up at level ten, and
    -- LibDBIcon hides one whenever its addon is told to. The grid counts
    -- only what is visible, so it has to be laid out again when that
    -- changes - debounced, since a button that shows usually brings
    -- others with it.
    if not btn._bazVisibilityHooked then
        btn._bazVisibilityHooked = true
        local function Relayout()
            if MinimapButtonsWidget._relayoutPending then return end
            MinimapButtonsWidget._relayoutPending = true
            C_Timer.After(0, function()
                MinimapButtonsWidget._relayoutPending = false
                MinimapButtonsWidget:LayoutButtons()
            end)
        end
        btn:HookScript("OnShow", Relayout)
        btn:HookScript("OnHide", Relayout)
    end

    -- Preliminary parenting to the widget frame so the button's z-order
    -- and scale inheritance are correct before it's assigned to a slot
    -- in LayoutButtons (which re-parents to the slot frame).
    btn:SetParent(self.frame)
    btn:SetFrameStrata("MEDIUM")

    -- Register this button in the custom-order list so the user can
    -- move it up/down from the widget's settings page. First adoption
    -- appends to the end; subsequent calls are no-ops (preserving any
    -- existing user-chosen position).
    EnsureButtonInOrder(btn:GetName() or "")

    if opts.useScale then
        -- Keep native size; scale the whole button (children + animations
        -- included) so the effective footprint matches BUTTON_SIZE.
        local nativeW = orig.nativeW
        if not nativeW or nativeW <= 0 then nativeW = BUTTON_SIZE end
        btn:SetScale(BUTTON_SIZE / nativeW)
    else
        btn:SetScale(1)
        btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    end

    -- Some addons re-anchor their own LibDBIcon button when the user
    -- activates them (VaultLoom is one example) - the button click
    -- triggers internal addon code that resets the icon's position
    -- back to its saved Minimap angle, pulling it out of our slot.
    --
    -- Hook OnClick only. We schedule two delayed re-layouts:
    --   * 0.05s  - catches addons that re-anchor synchronously in
    --              their OnClick handler.
    --   * 0.30s  - catches addons that defer the re-anchor to a
    --              later frame (timers, animations, ADDON_LOADED-ish
    --              event handlers triggered by the click).
    -- Two timers is bounded and cheap. We deliberately do NOT hook
    -- SetPoint / SetParent here - that path interacts badly with
    -- LibDBIcon's startup churn and crashed the client when we tried
    -- it previously.
    -- Not everything adopted is a Button. The mail notice is a Frame,
    -- which has no OnClick to hook and nothing to re-lay on either, so
    -- ask rather than assume: hooking a script a frame does not have is
    -- an error, not a no-op.
    if btn:HasScript("OnClick") then
        btn:HookScript("OnClick", function()
            C_Timer.After(0.05, function() MinimapButtonsWidget:LayoutButtons() end)
            C_Timer.After(0.30, function() MinimapButtonsWidget:LayoutButtons() end)
        end)
    end

    -- Actual slot assignment + anchor happens in LayoutButtons
end

-- Reentry guard. LayoutButtons is called from hooksecurefunc hooks on
-- QueueStatusButton (Show/Hide/SetPoint), and any frame operation we
-- perform during a layout pass can re-trigger those hooks. Without this
-- guard the stack blows up in a few frames.
local layoutInProgress = false

function MinimapButtonsWidget:LayoutButtons()
    if layoutInProgress then return end
    layoutInProgress = true

    local f = self.frame
    if not f then layoutInProgress = false return end
    if not self.slots then self:BuildSlots() end

    -- Collect + sort the buttons that want to be here. The custom
    -- `buttonOrder` list drives primary ordering; anything not listed
    -- falls back to an alphabetical sort at the end.
    --
    -- Asked of the button itself - IsShown and its own alpha - and not
    -- of IsVisible, which folds in every parent above it. Every parent
    -- above it is ours, so IsVisible was really asking "is this widget
    -- collapsed", and collapsing it made every button answer no.
    --
    -- That was enough to lose them for good. Collapsing hides the
    -- content frame, which fires OnHide on each adopted button, which
    -- schedules this; this then found nothing visible and hid every
    -- slot. Expanding shows the content frame again - but the buttons
    -- live in those hidden slots, so they stayed hidden, never fired
    -- OnShow, and nothing asked for another layout. Only a reload,
    -- which builds the lot again, brought them back.
    --
    -- IsShown is the honest question: it is the button's own flag, and
    -- it is what LibDBIcon sets when somebody switches a button off.
    local list = {}
    for btn in pairs(adopted) do
        if btn:IsShown() and (btn:GetAlpha() or 1) > 0 then
            table.insert(list, btn)
        end
    end

    local order = GetButtonOrder()
    local orderIndex = {}
    for i, n in ipairs(order) do orderIndex[n] = i end

    -- QueueStatusButton always gets the leftmost slot (index 1)
    -- regardless of custom order or alphabetical fallback. Everything
    -- else sorts by the user's custom order, then alphabetically.
    table.sort(list, function(a, b)
        local aIsEye = (a == QueueStatusButton)
        local bIsEye = (b == QueueStatusButton)
        if aIsEye then return true end
        if bIsEye then return false end
        local ia = orderIndex[a:GetName() or ""]
        local ib = orderIndex[b:GetName() or ""]
        if ia and ib then return ia < ib end
        if ia then return true end
        if ib then return false end
        return (a:GetName() or "") < (b:GetName() or "")
    end)

    -- Compute grid dimensions and centering offset. The grid's total
    -- width is based on how many columns the visible buttons actually
    -- occupy (not the max the widget could hold). The offset pushes
    -- the grid right so the occupied columns are horizontally centered.
    local cols = self._cols or 1
    local used = #list
    local rows = used > 0 and math.ceil(used / cols) or 1
    local occupiedCols = used > 0 and math.min(used, cols) or 0
    local gridWidth = occupiedCols * BUTTON_SIZE + math.max(0, occupiedCols - 1) * BUTTON_GAP
    local usableWidth = DESIGN_WIDTH - PAD * 2
    local xOffset = PAD + math.max(0, math.floor((usableWidth - gridWidth) / 2))

    -- Grow the slot pool on demand. With 30+ LibDBIcon-publishing
    -- addons installed it's easy to overflow a fixed cap; if `list`
    -- is bigger than the current pool, build more slots. Anything in
    -- the pool beyond `#list` gets hidden in the loop below.
    while #self.slots < #list do
        local slot = CreateFrame("Frame", nil, f)
        slot:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        self.slots[#self.slots + 1] = slot
    end
    local nSlots = #self.slots
    local bazui = (GetButtonStyle() == "bazui")

    -- Reposition slots to the centered grid and assign buttons. We
    -- DO NOT call btn:Show() - the buttons are already shown (they're
    -- in `list` because we filtered for visibility), and calling Show
    -- would retrigger the hooksecurefunc hooks and recurse.
    for i = 1, nSlots do
        local slot = self.slots[i]
        local btn = list[i]
        if btn then
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", f, "TOPLEFT",
                xOffset + col * (BUTTON_SIZE + BUTTON_GAP),
                -PAD - row * (BUTTON_SIZE + BUTTON_GAP))
            -- Always force reparent + re-anchor. Blizzard's
            -- MicroMenu:Layout can steal the QueueStatusButton back
            -- between our layout passes, so we can't rely on a
            -- parent-check guard here - we must assert ownership
            -- every single pass.
            btn:SetParent(slot)
            btn:ClearAllPoints()
            btn:SetPoint("CENTER", slot, "CENTER", 0, 0)
            if bazui then ApplyButtonSkin(btn) else RemoveButtonSkin(btn) end
            slot:Show()
        else
            slot:Hide()
        end
    end
    local h = PAD + rows * BUTTON_SIZE + (rows - 1) * BUTTON_GAP + PAD
    if used == 0 then h = MIN_HEIGHT end
    self._desiredHeight = h
    f:SetHeight(h)
    self._count = used

    layoutInProgress = false

    if addon.WidgetHost and addon.WidgetHost.Reflow then
        addon.WidgetHost:Reflow()
    end
end

---------------------------------------------------------------------------
-- Queue eye adoption. QueueStatusButton is a global Button parented to
-- MicroMenuContainer with the mixin `QueueStatusButtonMixin`. It's
-- auto-shown/hidden by Blizzard based on active LFG / PVP queues. We
-- steal it into our widget and let its natural show/hide state drive
-- whether it appears in the grid.
--
-- We also remove it from `MicroMenu.buttonsToLayout` so MicroMenu:Layout
-- stops clobbering its position on every layout pass.
---------------------------------------------------------------------------

local queueAdopted = false

local function AdoptQueueEye(widget)
    if queueAdopted then return end
    if not QueueStatusButton then return end

    -- Remove from MicroMenu's layout list. This is a one-time removal
    -- but MicroMenu:Layout can re-add the button, so we also hook
    -- Layout below to persistently keep it out.
    local function RemoveFromMicroMenu()
        if MicroMenu and MicroMenu.buttonsToLayout then
            for i = #MicroMenu.buttonsToLayout, 1, -1 do
                if MicroMenu.buttonsToLayout[i] == QueueStatusButton then
                    table.remove(MicroMenu.buttonsToLayout, i)
                end
            end
        end
    end
    RemoveFromMicroMenu()

    -- Keep QueueStatusButton out of the micro menu's layout, checked on
    -- a ticker rather than by hooking MicroMenu:Layout.
    --
    -- Blizzard rebuilds that layout on instance entry, queue changes and
    -- reloads, and re-adds the button each time. Hooking their Layout
    -- caught every rebuild, but hooksecurefunc writes to the method
    -- table of a frame we do not own, and on Forever that left their own
    -- `MicroMenu:Layout()` calling a nil while Edit Mode was anchoring.
    --
    -- Watching instead means the button can sit in their row for up to
    -- half a second after a rebuild before being taken back. Nobody sees
    -- a rebuild happen, and nothing is tainted.
    local guard, guardSince = CreateFrame("Frame"), 0
    guard:SetScript("OnUpdate", function(_, elapsed)
        guardSince = guardSince + elapsed
        if guardSince < 0.5 then return end
        guardSince = 0
        if not (MicroMenu and QueueStatusButton) then return end
        if QueueStatusButton:GetParent() == MicroMenu
            or (MicroMenu.buttonsToLayout and #MicroMenu.buttonsToLayout > 0) then
            RemoveFromMicroMenu()
            if QueueStatusButton:IsShown() then widget:LayoutButtons() end
        end
    end)

    -- Use SetScale - QueueStatusButton has a child Eye frame at 30×30
    -- plus a 96×96 glow overlay child, and those aren't reachable via
    -- SetSize. Scaling the whole button proportionally keeps everything
    -- in alignment.
    widget:AdoptButton(QueueStatusButton, { useScale = true })
    queueAdopted = true

    -- Hook visibility transitions. Blizzard flips the button's Shown
    -- state on LFG state changes as part of its own OnEvent handlers,
    -- which run BEFORE any C_Timer.After(0, ...) we schedule from our
    -- own handler. By hooking Show/Hide directly, we catch every
    -- transition the same frame it happens and re-run the grid layout
    -- immediately. The `layoutInProgress` guard in LayoutButtons
    -- prevents recursion when this hook fires as a downstream effect of
    -- a layout pass (e.g. from slot:Show cascading effective visibility
    -- changes on child buttons).
    -- HookScript, not hooksecurefunc: the latter writes to the button's
    -- method table, and on Forever that leaves Blizzard's own Show/Hide
    -- calling a nil. OnShow and OnHide fire for exactly the same moments.
    QueueStatusButton:HookScript("OnShow", function() widget:LayoutButtons() end)
    QueueStatusButton:HookScript("OnHide", function() widget:LayoutButtons() end)
end

function MinimapButtonsWidget:Scan()
    for _, host in ipairs({ Minimap, MinimapBackdrop }) do
        if host then
            for _, child in ipairs({ host:GetChildren() }) do
                if IsAdoptable(child) then
                    self:AdoptButton(child)
                end
            end
        end
    end

    -- Queue eye (special case - different parent)
    AdoptQueueEye(self)

    self:LayoutButtons()
end

function MinimapButtonsWidget:GetDesiredHeight()
    return self._desiredHeight or MIN_HEIGHT
end

function MinimapButtonsWidget:GetStatusText()
    return tostring(self._count or 0), 0.85, 0.85, 0.85
end

---------------------------------------------------------------------------
-- Friendly-name map for known addon minimap buttons so the options
-- page shows something human-readable instead of raw frame names like
-- `LibDBIcon10_BazNotificationCenter`.
---------------------------------------------------------------------------

local function FriendlyName(btnName)
    if not btnName or btnName == "" then return "Unknown" end
    -- Strip the LibDBIcon prefix
    local stripped = btnName:gsub("^LibDBIcon10_", "")
    -- Split CamelCase: "BazNotificationCenter" > "Baz Notification Center"
    stripped = stripped:gsub("([a-z])([A-Z])", "%1 %2")
    -- Special-case the queue eye
    if btnName == "QueueStatusButton" then return "Queue Eye" end
    return stripped
end

function MinimapButtonsWidget:GetOptionsArgs()
    local args = {
        styleHeader = {
            order = 1,
            type = "header",
            name = "Appearance",
        },
        [STYLE_KEY] = {
            order  = 2,
            type   = "select",
            name   = "Button Frame",
            desc   = "BazUI puts every adopted button in the same brass ring with a round icon, so buttons from different addons match. Blizzard Default leaves each addon's own button art alone.",
            values = BUTTON_STYLES,
            get    = function() return GetButtonStyle() end,
            set    = function(_, val)
                if not BUTTON_STYLES[val] then val = "default" end
                addon:SetWidgetSetting(WIDGET_ID, STYLE_KEY, val)
                MinimapButtonsWidget:ApplyButtonStyle()
            end,
        },
        [BACKDROP_KEY] = {
            order = 3,
            type  = "toggle",
            name  = "Icon Backdrop",
            desc  = "Draws a solid dark disc behind each icon so buttons with transparent artwork look as solid as the rest. Only used with the BazUI frame.",
            get   = function() return BackdropEnabled() end,
            set   = function(_, val)
                addon:SetWidgetSetting(WIDGET_ID, BACKDROP_KEY, val and true or false)
                MinimapButtonsWidget:RefreshBackdrops()
            end,
            disabled = function() return GetButtonStyle() ~= "bazui" end,
        },
        rescanHeader = {
            order = 10,
            type = "header",
            name = "Detection",
        },
        rescan = {
            order = 11,
            type = "execute",
            name = "Re-scan Minimap",
            desc = "Scan the minimap for addon buttons and adopt any new ones. This also happens automatically at login and whenever an addon finishes loading; use it if a button still slipped through. Run this after loading a new addon that adds a minimap button.",
            func = function() MinimapButtonsWidget:Scan() end,
        },
        orderHeader = {
            order = 20,
            type = "header",
            name = "Button Order",
        },
        orderDescription = {
            order = 21,
            type = "note",
            style = "info",
            text = "Reorder the buttons in the grid. Buttons appear left-to-right, top-to-bottom in the order listed below. New buttons detected by Re-scan are appended to the end.",
        },
    }

    -- Build one row per ordered button with Move Up / Move Down
    -- controls. The row order is driven by the live `buttonOrder`
    -- setting so it always reflects the current state (including after
    -- a move that happened earlier in this same options session).
    local order = GetButtonOrder()
    local total = #order
    local baseOrder = 30
    for i, btnName in ipairs(order) do
        local nameCopy = btnName  -- capture for closures
        local label = FriendlyName(btnName)

        args["btn_" .. i .. "_label"] = {
            order = baseOrder + (i - 1) * 10 + 0,
            type = "paragraph",
            text = "|cffffd700" .. label .. "|r",
        }
        args["btn_" .. i .. "_up"] = {
            order = baseOrder + (i - 1) * 10 + 1,
            type = "execute",
            name = "Move Up",
            desc = "Move " .. label .. " one position earlier in the grid.",
            func = function() MinimapButtonsWidget:MoveButtonUp(nameCopy) end,
            disabled = function()
                local cur = GetButtonOrder()
                for idx, n in ipairs(cur) do
                    if n == nameCopy then return idx <= 1 end
                end
                return true
            end,
        }
        args["btn_" .. i .. "_down"] = {
            order = baseOrder + (i - 1) * 10 + 2,
            type = "execute",
            name = "Move Down",
            desc = "Move " .. label .. " one position later in the grid.",
            func = function() MinimapButtonsWidget:MoveButtonDown(nameCopy) end,
            disabled = function()
                local cur = GetButtonOrder()
                for idx, n in ipairs(cur) do
                    if n == nameCopy then return idx >= #cur end
                end
                return true
            end,
        }
    end

    if total == 0 then
        args.orderEmpty = {
            order = 29,
            type = "note",
            style = "info",
            text = "No adopted buttons yet. Load an addon that adds a minimap button, then run Re-scan.",
        }
    end

    return args
end

function MinimapButtonsWidget:Build()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "BazUIDrawerMinimapButtonsWidget", UIParent)
    f:SetSize(DESIGN_WIDTH, MIN_HEIGHT)

    -- Anchored from the moment it exists, even though the dock will place
    -- it properly later and clears these points when it does.
    --
    -- A frame with a size but no anchor has no resolved position, and
    -- GetLeft() on it - or on anything parented to it - answers nil. The
    -- buttons in here belong to other addons, and one of them asked where
    -- its icon was during its own startup, before the dock had placed
    -- this: Zygor positions its notification popup by reading
    -- ZygorGuidesViewerMapIcon:GetLeft(), got nil, and threw. Somewhere
    -- is better than nowhere for a frame holding other people's things.
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    self.frame = f
    self._desiredHeight = MIN_HEIGHT
    self._count = 0

    -- Pre-build the fixed slot grid so LayoutButtons always has frames
    -- to slot buttons into.
    self:BuildSlots()
    return f
end

function MinimapButtonsWidget:Init()
    local f = self:Build()

    BazUI:RegisterDockableWidget({
        id = WIDGET_ID,
        label = "Minimap Buttons",
        designWidth = DESIGN_WIDTH,
        designHeight = MIN_HEIGHT,
        frame = f,
        GetDesiredHeight = function() return MinimapButtonsWidget:GetDesiredHeight() end,
        GetStatusText    = function() return MinimapButtonsWidget:GetStatusText() end,
        GetOptionsArgs   = function() return MinimapButtonsWidget:GetOptionsArgs() end,
    })

    -- Queue eye event handler - re-run layout whenever LFG/PVP queue
    -- state changes so the adopted QueueStatusButton appears or
    -- disappears in the grid as Blizzard shows/hides it.
    for _, ev in ipairs(QUEUE_EYE_EVENTS) do
        pcall(f.RegisterEvent, f, ev)
    end
    -- Whatever else may have left the slots out of step with the
    -- buttons, being shown again is the moment to put it right.
    f:HookScript("OnShow", function()
        C_Timer.After(0, function() MinimapButtonsWidget:LayoutButtons() end)
    end)

    f:HookScript("OnEvent", function()
        -- Blizzard toggles the queue eye's Shown state asynchronously
        -- on these events, so defer the relayout by a frame.
        C_Timer.After(0, function() MinimapButtonsWidget:LayoutButtons() end)
    end)

    -- Delay the first scan so LibDBIcon-using addons finish registering,
    -- then sweep once more for slow starters (addons that build their
    -- button on PLAYER_ENTERING_WORLD or after their own saved-variable
    -- load finishes).
    C_Timer.After(1.5, function() MinimapButtonsWidget:Scan() end)
    C_Timer.After(6.0, function() MinimapButtonsWidget:Scan() end)

    -- Load-on-demand and late-loading addons: rescan shortly after any
    -- addon finishes loading. Debounced so a burst of ADDON_LOADED at
    -- login collapses into one pass.
    local rescanPending = false
    local loadWatcher = CreateFrame("Frame")
    loadWatcher:RegisterEvent("ADDON_LOADED")
    loadWatcher:SetScript("OnEvent", function()
        if rescanPending then return end
        rescanPending = true
        C_Timer.After(1.0, function()
            rescanPending = false
            MinimapButtonsWidget:Scan()
        end)
    end)

    -- LibDBIcon tells us the moment a new icon is created, no matter
    -- how late. Optional: only wired if some loaded addon embeds it.
    local dbicon = LibStub and LibStub("LibDBIcon-1.0", true)
    if dbicon and dbicon.RegisterCallback then
        dbicon.RegisterCallback(MinimapButtonsWidget, "LibDBIcon_IconCreated", function()
            C_Timer.After(0, function() MinimapButtonsWidget:Scan() end)
        end)
    end
end

BazUI:QueueForModule("Drawers", function() MinimapButtonsWidget:Init() end)
