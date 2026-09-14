-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Skin: Theme
--
-- The suite's shared look: dark, warm panel interiors with a gold metal
-- edge, gold headings, and round ring-framed buttons (the minimap ring,
-- the portrait ring, the minimap buttons). Modules pull colours,
-- backdrops and the round-button treatment from here so a panel in one
-- module reads the same as a panel in another.
---------------------------------------------------------------------------

local Skin = BazUI.Skin
local Theme = {}
Skin.Theme = Theme

-- Map surface extends beneath the ring to cover its antialiased inner edge.
Theme.minimapRingOverlap = 5
-- Edited ring: inner diameter 87% of the canvas; source preserved in Assets/Source.
Theme.minimapRingInnerRatio = 0.87
-- Preserve the original ring footprint independently of the artwork opening.
Theme.minimapRingDesignRatio = 0.75

Theme.colors = {
    gold      = { 1.00, 0.82, 0.00, 1.00 },  -- headings, selected state (the |cffffd700 gold)
    goldSoft  = { 1.00, 0.84, 0.50, 1.00 },  -- names and labels on artwork
    goldDim   = { 0.62, 0.48, 0.20, 1.00 },  -- frame edges
    divider   = { 0.55, 0.42, 0.18, 0.60 },
    edge      = { 0.42, 0.33, 0.14, 0.60 },  -- one-pixel borders inside a panel

    bg        = { 0.04, 0.035, 0.03, 0.92 }, -- panel and toast interiors
    bgRaised  = { 0.10, 0.09, 0.07, 0.88 },  -- cards and rows
    bgHover   = { 0.17, 0.14, 0.09, 0.94 },

    text      = { 1.00, 0.96, 0.88, 1.00 },
    textSoft  = { 0.82, 0.76, 0.62, 1.00 },
    textMuted = { 0.60, 0.55, 0.45, 1.00 },

    warn      = { 0.95, 0.50, 0.15, 1.00 },
    danger    = { 0.85, 0.30, 0.30, 1.00 },
}

-- Blizzard's tooltip nine-slice tinted gold: the frame Bags and the
-- Drawers already use, so panels and toasts belong to the same family.
Theme.BACKDROP_PANEL = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Flat one-pixel frame for elements that sit inside a panel.
Theme.BACKDROP_FLAT = {
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

---------------------------------------------------------------------------
-- The suite's face
--
-- DorisPP, shipped in Skin/Assets. Modules ask for Theme.FontFile()
-- wherever they would have named STANDARD_TEXT_FONT, so one switch
-- changes the lot. The client reads font files at startup, so a file
-- added while it is running is unreadable until it restarts: rather
-- than draw nothing, an unreadable face quietly resolves to the game's
-- own. Chat keeps its own switch, since it also has a size of its own.
---------------------------------------------------------------------------

Theme.FONT_FILE = "Interface\\AddOns\\BazUI\\Skin\\Assets\\DORISBR.TTF"

local fontProbe, fontLoadable

-- Whether the client can actually read the file. Fixed for the session.
function Theme.IsFontLoadable()
    if fontLoadable == nil then
        fontProbe = fontProbe or CreateFont("BazUIFontProbe")
        -- A Font object's SetFont reports nothing, so read the face back.
        fontProbe:SetFont(Theme.FONT_FILE, 12, "")
        local applied = fontProbe:GetFont()
        fontLoadable = (applied and applied:lower() == Theme.FONT_FILE:lower()) or false
    end
    return fontLoadable
end

-- The global switch, on unless the user turned it off.
function Theme.IsFontEnabled()
    return not BazUIDB or BazUIDB.useFont ~= false
end

-- The face to draw with: ours when it is wanted and readable, the
-- game's otherwise.
function Theme.FontFile()
    if Theme.IsFontEnabled() and Theme.IsFontLoadable() then
        return Theme.FONT_FILE
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- Blizzard's font objects, mirrored in our face.
--
-- Code that calls SetFontObject(GameFontNormal) can't take a file the
-- way SetFont does, so ask for Theme.FontObject("GameFontNormal") and
-- get an object with the same size, flags, colour and justification,
-- drawn in the suite's face. The object is shared and edited in place,
-- so every string using it follows when the switch changes: flipping
-- it calls RefreshFontObjects and the text redraws with no reload.
local fontObjects = {}

function Theme.FontObject(blizzardName)
    local base = _G[blizzardName]
    if not base then return nil end

    local obj = fontObjects[blizzardName]
    if not obj then
        obj = CreateFont("BazUI" .. blizzardName)
        fontObjects[blizzardName] = obj
    end

    local baseFace, size, flags = base:GetFont()
    local face = baseFace
    if Theme.IsFontEnabled() and Theme.IsFontLoadable() then face = Theme.FONT_FILE end
    obj:SetFont(face, size or 12, flags or "")
    obj:SetTextColor(base:GetTextColor())
    obj:SetShadowColor(base:GetShadowColor())
    obj:SetShadowOffset(base:GetShadowOffset())
    local h, v = base:GetJustifyH(), base:GetJustifyV()
    if h then obj:SetJustifyH(h) end
    if v then obj:SetJustifyV(v) end
    return obj
end

-- CreateFontString names a Blizzard font object to inherit from, which
-- can't be a mirror; this makes the string and points it at one.
function Theme.FontString(parent, layer, blizzardName, sublevel)
    local fs = parent:CreateFontString(nil, layer, nil, sublevel)
    local obj = Theme.FontObject(blizzardName)
    if obj then fs:SetFontObject(obj) end
    return fs
end

-- Re-point every mirrored object at the face now in force.
function Theme.RefreshFontObjects()
    for name in pairs(fontObjects) do Theme.FontObject(name) end
end

local function SetColor(fn, c)
    fn(c[1], c[2], c[3], c[4] or 1)
end

-- Gold-edged panel backdrop. `frame` must inherit BackdropTemplate.
function Theme.ApplyPanel(frame, bgColor)
    frame:SetBackdrop(Theme.BACKDROP_PANEL)
    SetColor(function(...) frame:SetBackdropColor(...) end, bgColor or Theme.colors.bg)
    SetColor(function(...) frame:SetBackdropBorderColor(...) end, Theme.colors.goldDim)
end

---------------------------------------------------------------------------
-- Flat panel (the tooltip treatment)
--
-- A solid interior and a one-pixel gold edge: the quiet chrome the
-- tooltips wear (Theme.ApplyTooltipFrame below builds the same thing in
-- a child frame, which GameTooltip needs because it manages its own
-- regions). Panels of our own can take it directly. Any backdrop the
-- frame already has is cleared so the two treatments never stack.
---------------------------------------------------------------------------

function Theme.ApplyFlatPanel(frame, bgColor, edgeColor)
    if frame.GetBackdrop and frame:GetBackdrop() then frame:SetBackdrop(nil) end

    local art = frame._bazFlatPanel
    if not art then
        art = { edges = {} }
        art.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        art.bg:SetAllPoints(frame)
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local edge = frame:CreateTexture(nil, "BORDER", nil, 7)
            if side == "TOP" or side == "BOTTOM" then
                edge:SetPoint(side .. "LEFT", frame, side .. "LEFT")
                edge:SetPoint(side .. "RIGHT", frame, side .. "RIGHT")
                edge:SetHeight(1)
            else
                edge:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, -1)
                edge:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 1)
                edge:SetWidth(1)
            end
            art.edges[#art.edges + 1] = edge
        end
        frame._bazFlatPanel = art
    end

    local c = edgeColor or Theme.colors.goldDim
    for _, edge in ipairs(art.edges) do
        edge:SetColorTexture(c[1], c[2], c[3], c[4] or 0.8)
        edge:Show()
    end
    Theme.SetFlatPanelColor(frame, bgColor)
    art.bg:Show()
end

-- Recolour a flat panel's interior without rebuilding it (hover states,
-- an opacity slider). Silently does nothing on a frame that never had
-- ApplyFlatPanel, so callers can stay simple.
function Theme.SetFlatPanelColor(frame, bgColor, alpha)
    local art = frame._bazFlatPanel
    if not art then return end
    local c = bgColor or Theme.colors.bg
    art.bg:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
end

---------------------------------------------------------------------------
-- Round ring-framed button (the minimap-button treatment)
--
-- A dark disc, the icon masked to a circle inside the ring, and the gold
-- ring on top. Crop the icon with SetTexCoord *before* calling this:
-- a masked texture rejects SetTexCoord.
---------------------------------------------------------------------------

function Theme.ApplyRoundButton(button, icon, opts)
    opts = opts or {}
    local size  = opts.size or button:GetWidth()
    local inner = size * (opts.innerRatio or Skin.BUTTON_RING_INNER_RATIO) + (opts.overlap or 2) * 2

    if not button._bazRing then
        local disc = button:CreateTexture(nil, "BACKGROUND", nil, -1)
        SetColor(function(...) disc:SetColorTexture(...) end, Skin.BUTTON_BACKDROP_COLOR)
        local discMask = button:CreateMaskTexture()
        discMask:SetTexture(Skin.ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        disc:AddMaskTexture(discMask)

        local iconMask = button:CreateMaskTexture()
        iconMask:SetTexture(Skin.ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(iconMask)

        local ring = button:CreateTexture(nil, "OVERLAY", nil, 7)
        ring:SetTexture(Skin.BUTTON_RING)

        button._bazDisc, button._bazDiscMask, button._bazIconMask, button._bazRing = disc, discMask, iconMask, ring

        -- Press feedback: the icon and its disc sink a pixel down-right
        -- and darken while the mouse button is held; the ring stays put
        -- like a bezel. Released on mouse up, on leaving, and on hide so
        -- a drag off the button can't leave it stuck down.
        button:HookScript("OnMouseDown", function(self) Theme.SetRoundButtonPressed(self, true) end)
        button:HookScript("OnMouseUp",   function(self) Theme.SetRoundButtonPressed(self, false) end)
        button:HookScript("OnLeave",     function(self) Theme.SetRoundButtonPressed(self, false) end)
        button:HookScript("OnHide",      function(self) Theme.SetRoundButtonPressed(self, false) end)
    end
    button._bazIcon = icon

    button._bazRing:ClearAllPoints()
    button._bazRing:SetPoint("CENTER")
    button._bazRing:SetSize(size, size)

    icon:SetSize(inner, inner)
    button._bazDisc:SetSize(inner + 2, inner + 2)
    button._bazDiscMask:SetAllPoints(button._bazDisc)
    button._bazIconMask:SetAllPoints(icon)
    Theme.SetRoundButtonPressed(button, false)
end

local PRESS_SHIFT = 1

function Theme.SetRoundButtonPressed(button, pressed)
    local icon, disc = button._bazIcon, button._bazDisc
    if not icon or not disc then return end
    local dx = pressed and PRESS_SHIFT or 0
    local dy = pressed and -PRESS_SHIFT or 0
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", button, "CENTER", dx, dy)
    disc:ClearAllPoints()
    disc:SetPoint("CENTER", button, "CENTER", dx, dy)
    local shade = pressed and 0.75 or 1
    icon:SetVertexColor(shade, shade, shade)
end

-- Hover tint for a round button's disc; pass nil to restore.
function Theme.SetRoundButtonHover(button, hovered)
    if not button._bazDisc then return end
    local c = hovered and Theme.colors.bgHover or Skin.BUTTON_BACKDROP_COLOR
    button._bazDisc:SetColorTexture(c[1], c[2], c[3], 1)
end

-- Three slices of the padded unit-name artwork; end caps never stretch.
Theme.nameplate = {
    width = 2110, height = 309, textureWidth = 4096, textureHeight = 512, capPixels = 220,
}

-- Quiet tooltip chrome: no stretched artwork, bright ornament or glow.
function Theme.ApplyTooltipFrame(tooltip, opacity)
    if not tooltip._bazTooltipArt then
        -- Native GameTooltip content updates/fades manage its own regions.
        -- Keep our chrome in a child frame, inheriting the tooltip's alpha.
        local chrome = CreateFrame("Frame", nil, tooltip)
        chrome:SetAllPoints(tooltip)
        chrome:EnableMouse(false)
        tooltip._bazTooltipArtFrame = chrome
        local art = {}
        local function Texture(color, alpha)
            local t = chrome:CreateTexture(nil, "BACKGROUND", nil, -7)
            t:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
            art[#art + 1] = t
            return t
        end
        local bg = Texture(Theme.colors.bg)
        bg:SetAllPoints(tooltip)
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local edge = Texture(Theme.colors.goldDim, .8)
            edge:SetDrawLayer("BORDER", 7)
            if side == "TOP" or side == "BOTTOM" then
                edge:SetPoint(side .. "LEFT", tooltip, side .. "LEFT")
                edge:SetPoint(side .. "RIGHT", tooltip, side .. "RIGHT")
                edge:SetHeight(1)
            else
                edge:SetPoint("TOP" .. side, tooltip, "TOP" .. side, 0, -1)
                edge:SetPoint("BOTTOM" .. side, tooltip, "BOTTOM" .. side, 0, 1)
                edge:SetWidth(1)
            end
        end
        tooltip._bazTooltipArt = art
    end
    tooltip._bazTooltipArtFrame:SetFrameLevel(math.max(0, tooltip:GetFrameLevel() - 1))
    local bg = Theme.colors.bg
    tooltip._bazTooltipArt[1]:SetColorTexture(bg[1], bg[2], bg[3], opacity or .96)
    for _, t in ipairs(tooltip._bazTooltipArt) do t:Show() end
end
