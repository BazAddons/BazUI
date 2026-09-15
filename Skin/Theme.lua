-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Skin: Theme
--
-- The suite's shared look: dark, warm panel interiors with a gold metal
-- edge, gold headings, and round ring-framed buttons (the minimap ring,
-- the portrait ring, the minimap buttons). Modules pull colors,
-- backdrops and the round-button treatment from here so a panel in one
-- module reads the same as a panel in another.
---------------------------------------------------------------------------

local Skin = BazUI.Skin
local Theme = {}
Skin.Theme = Theme

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

    -- Readings that mean something. A bar or a number takes one of
    -- these rather than a color of its own, so green means finished
    -- everywhere in the suite and amber always means running out.
    success   = { 0.45, 0.78, 0.48, 1.00 },  -- done, earned, collected
    caution   = { 0.95, 0.72, 0.20, 1.00 },  -- a window closing
    warn      = { 0.95, 0.50, 0.15, 1.00 },
    danger    = { 0.85, 0.30, 0.30, 1.00 },
}

-- Mix two colors. Used for readings that shift as they run: a reset
-- clock warming from gold to amber as its window closes.
function Theme.Blend(from, to, t)
    t = math.max(0, math.min(1, tonumber(t) or 0))
    return {
        from[1] + (to[1] - from[1]) * t,
        from[2] + (to[2] - from[2]) * t,
        from[3] + (to[3] - from[3]) * t,
        (from[4] or 1) + ((to[4] or 1) - (from[4] or 1)) * t,
    }
end

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
-- get an object with the same size, flags, color and justification,
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

    art.bgColor   = bgColor or Theme.colors.bg
    art.edgeColor = edgeColor or Theme.colors.goldDim
    Theme.SetFlatPanelAlpha(frame)
    art.bg:Show()
    for _, edge in ipairs(art.edges) do edge:Show() end
end

-- Recolor a flat panel's interior without rebuilding it (hover states,
-- an opacity slider). Silently does nothing on a frame that never had
-- ApplyFlatPanel, so callers can stay simple.
function Theme.SetFlatPanelColor(frame, bgColor, alpha)
    local art = frame._bazFlatPanel
    if not art then return end
    local c = bgColor or Theme.colors.bg
    art.bgColor = { c[1], c[2], c[3], alpha or c[4] or 1 }
    Theme.SetFlatPanelAlpha(frame)
end

-- Fade the interior and the edge independently, keeping both colors.
-- Pass nothing to redraw at the colors' own alpha; the drawer tweens
-- these two as it fades in and out.
function Theme.SetFlatPanelAlpha(frame, bgAlpha, edgeAlpha)
    local art = frame._bazFlatPanel
    if not art then return end
    local b, e = art.bgColor or Theme.colors.bg, art.edgeColor or Theme.colors.goldDim
    art.bg:SetColorTexture(b[1], b[2], b[3], bgAlpha or b[4] or 1)
    for _, edge in ipairs(art.edges) do
        edge:SetColorTexture(e[1], e[2], e[3], edgeAlpha or e[4] or 0.8)
    end
end

---------------------------------------------------------------------------
-- Search box
--
-- One text field for the whole suite, wearing the flat chrome: a raised
-- interior, the one-pixel edge, a placeholder that steps aside as soon
-- as you type, and Escape to let go. Anywhere a panel wants a filter or
-- a lookup it asks for this rather than reaching for Blizzard's gold
-- InputBoxTemplate, which belongs to a different UI than ours.
--
--   local box = Theme.CreateSearchBox(parent, "Search history...",
--       function(text) ReFilter(text) end)
--
-- The callback fires on every keystroke with the current text. The box
-- is a plain EditBox, so callers can still size, anchor and focus it.
---------------------------------------------------------------------------

function Theme.CreateSearchBox(parent, placeholder, onChanged)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetHeight(22)
    box:SetAutoFocus(false)
    box:SetTextInsets(7, 7, 0, 0)
    box:SetFontObject(Theme.FontObject("GameFontHighlightSmall"))
    box:SetTextColor(unpack(Theme.colors.text))
    Theme.ApplyFlatPanel(box, Theme.colors.bgRaised, Theme.colors.edge)

    local hint = Theme.FontString(box, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", 7, 0)
    hint:SetTextColor(unpack(Theme.colors.textMuted))
    hint:SetText(placeholder or "Search...")
    box.placeholder = hint

    function box:SetPlaceholder(text)
        hint:SetText(text or "")
    end

    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        hint:SetShown(text == "")
        if onChanged then onChanged(text, self) end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- A field that lights up when it has the cursor tells you where your
    -- typing is going without a focus ring fighting the chrome.
    box:SetScript("OnEditFocusGained", function(self)
        Theme.SetFlatPanelColor(self, Theme.colors.bgHover)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        Theme.SetFlatPanelColor(self, Theme.colors.bgRaised)
    end)

    return box
end

---------------------------------------------------------------------------
-- Stat bar
--
-- The panel-sized bar: a reading inside a card or a row, drawn with the
-- flat one-pixel edge rather than the drop shadow a bar on the screen
-- wears. It is Core/StatusBar.lua in its "panel" dress, plus the labels
-- and breakpoints a panel row wants, so there is one bar in the suite
-- and not two drifting apart.
--
--   local bar = Theme.CreateStatBar(parent, { height = 10, labels = true })
--   bar:SetBreakpoints({ 2, 4, 8 }, 8)
--   bar:SetValues(6, 8, "6 of 8")
---------------------------------------------------------------------------

function Theme.CreateStatBar(parent, opts)
    opts = opts or {}
    local height = opts.height or 10

    local bar = BazUI.CreateStatusBar(nil, parent, {
        style      = "panel",
        height     = height,
        width      = opts.width or 100,
        color      = opts.color,
        trackColor = opts.trackColor or { 0.02, 0.02, 0.02, 0.85 },
        rimColor   = opts.edgeColor or Theme.colors.edge,
        overlay    = false,
        text       = false,
    })
    bar:SetHeight(height + (opts.labels and 16 or 0))

    -- The fill sits at the bottom so the labels can have the space above
    -- it, which is the one way a panel row differs from a screen bar.
    bar.fill:ClearAllPoints()
    bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
    bar.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    bar.fill:SetHeight(height - 2)
    bar.track = bar

    if opts.labels then
        bar.left = Theme.FontString(bar, "OVERLAY", "GameFontHighlightSmall")
        bar.left:SetPoint("TOPLEFT")
        bar.left:SetJustifyH("LEFT")
        bar.left:SetTextColor(unpack(Theme.colors.textSoft))

        bar.right = Theme.FontString(bar, "OVERLAY", "GameFontHighlightSmall")
        bar.right:SetPoint("TOPRIGHT")
        bar.right:SetJustifyH("RIGHT")
        bar.right:SetTextColor(unpack(Theme.colors.textMuted))
    end

    bar.pips = {}

    function bar:SetBarColor(c)
        self:SetFillColor(c or Theme.colors.gold)
    end

    function bar:SetLabel(text)
        if self.left then self.left:SetText(text or "") end
    end

    -- Notches at the counts where something changes, drawn over the fill
    -- so a passed one still reads. A bar sized by its anchors has no
    -- width until it is drawn, so the request is kept and replayed.
    function bar:SetBreakpoints(points, maximum)
        self._pipPoints, self._pipMax = points, maximum
        for _, pip in ipairs(self.pips) do pip:Hide() end
        if not points or not maximum or maximum <= 0 then return end
        local span = self:GetWidth() - 2
        for i, at in ipairs(points) do
            if at > 0 and at < maximum and span > 0 then
                local pip = self.pips[i]
                if not pip then
                    pip = self:CreateTexture(nil, "OVERLAY")
                    pip:SetWidth(1)
                    pip:SetColorTexture(0, 0, 0, 0.55)
                    self.pips[i] = pip
                end
                local x = math.floor(span * (at / maximum)) + 1
                pip:ClearAllPoints()
                pip:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 1)
                pip:SetHeight(height - 2)
                pip:Show()
            end
        end
    end

    function bar:SetValues(value, maximum, rightText)
        value, maximum = tonumber(value) or 0, tonumber(maximum) or 0
        local pct = maximum > 0 and math.min(1, math.max(0, value / maximum)) or 0
        self:SetValue(pct)
        self.fill:SetShown(pct > 0)
        if self.right then self.right:SetText(rightText or "") end
        return pct
    end

    bar:HookScript("OnSizeChanged", function(self)
        if self._pipPoints then self:SetBreakpoints(self._pipPoints, self._pipMax) end
    end)

    bar:SetBarColor(opts.color)
    return bar
end

---------------------------------------------------------------------------
-- Scroll bars that stay out of the way
--
-- A scroll bar is only worth looking at while you are scrolling, so it
-- lives at zero alpha, appears the moment the wheel turns or the cursor
-- reaches it, and fades back out a beat after you stop. It still takes
-- the mouse while invisible, so grabbing where the bar sits works even
-- before it has faded in.
--
--   Theme.AutoFadeScrollBar(bar, scrollFrame)
--
-- A bar with nothing to scroll never appears at all, which is what
-- keeps a short page clean.
---------------------------------------------------------------------------

function Theme.AutoFadeScrollBar(bar, scrollFrame, opts)
    if not bar then return end
    opts = opts or {}
    local hold    = opts.hold or 1.1     -- seconds at full alpha after activity
    local fadeOut = opts.fade or 0.45    -- seconds to fade away
    local fadeIn  = opts.fadeIn or 0.12

    local awakeUntil = 0
    local function Wake()
        awakeUntil = GetTime() + hold
    end
    bar.Wake = Wake

    if scrollFrame then
        scrollFrame:HookScript("OnMouseWheel", Wake)
        scrollFrame:HookScript("OnVerticalScroll", Wake)
        scrollFrame:HookScript("OnScrollRangeChanged", Wake)
    end
    bar:HookScript("OnMouseWheel", Wake)
    bar:HookScript("OnMouseDown", Wake)
    bar:HookScript("OnShow", Wake)

    -- The tween lives on a frame of its own rather than on the bar's own
    -- OnUpdate, which belongs to Blizzard's scroll bar template.
    local driver = CreateFrame("Frame", nil, bar)
    driver:SetScript("OnUpdate", function(_, elapsed)
        local scrollable = true
        if scrollFrame and scrollFrame.GetVerticalScrollRange then
            scrollable = (scrollFrame:GetVerticalScrollRange() or 0) > 1
        end

        local target = 0
        if scrollable then
            -- The cursor resting on the bar counts as still scrolling.
            if bar:IsMouseOver() then Wake() end
            if GetTime() < awakeUntil then target = 1 end
        end

        local alpha = bar:GetAlpha() or 0
        if target > alpha then
            bar:SetAlpha(math.min(target, alpha + elapsed / fadeIn))
        elseif target < alpha then
            bar:SetAlpha(math.max(target, alpha - elapsed / fadeOut))
        end
    end)
    bar._bazFadeDriver = driver

    bar:SetAlpha(0)
    return bar
end

---------------------------------------------------------------------------
-- Round ring-framed button (the minimap-button treatment)
--
-- A dark disc, the icon masked to a circle inside the ring, and the gold
-- ring on top. Crop the icon with SetTexCoord *before* calling this:
-- a masked texture rejects SetTexCoord.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- The bar's border, bent into a circle
--
-- There is no way to draw a shape in this UI: everything on screen is a
-- texture, and a circle normally means an artist and a PNG per size. The
-- game ships a circular alpha mask, though, and a solid colour wearing
-- that mask is a filled circle at whatever size you make it. Three of
-- them, each smaller than the last and drawn over it, leave two rings
-- and a hole - which is a border.
--
-- The recipe is the status bar's, outside in: two pixels of dark, one of
-- gold, one of dark. The gold is a single pixel and only reads as a
-- border with dark on both sides of it, which is the whole reason the
-- bars look the way they do.
--
--   Theme.ApplyRing(frame, { scale = 1 })
--
-- Draws around the frame's edges, outside them, so whatever the frame
-- holds keeps every pixel it had. Call it again after a resize; the
-- textures anchor to the frame, so a resize alone needs nothing.
---------------------------------------------------------------------------

-- Same numbers as Core/StatusBar.lua. If those ever move, these move.
local RING_LAYERS = {
    { thickness = 2, color = { 0, 0, 0, 0.75 } },            -- outline
    { thickness = 1, color = { 0.55, 0.43, 0.25, 1 } },      -- rim
    { thickness = 1, color = { 0.035, 0.04, 0.055, 1 } },    -- the line inside it
}

function Theme.ApplyRing(frame, opts)
    opts = opts or {}
    local scale  = opts.scale or 1
    local layers = opts.layers or RING_LAYERS

    frame._bazRingParts = frame._bazRingParts or {}
    local parts = frame._bazRingParts

    -- How far out the outermost ring reaches, so each one can be placed
    -- by how much is left outside it.
    local total = 0
    for _, layer in ipairs(layers) do total = total + layer.thickness * scale end

    local out = total
    for index, layer in ipairs(layers) do
        local part = parts[index]
        if not part then
            part = frame:CreateTexture(nil, "BACKGROUND", nil, -8 + index)
            local mask = frame:CreateMaskTexture()
            mask:SetTexture(Skin.ROUND_MASK,
                "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            part:AddMaskTexture(mask)
            part._mask = mask
            parts[index] = part
        end

        local color = layer.color
        part:SetColorTexture(color[1], color[2], color[3], color[4] or 1)

        -- Each circle reaches `out` beyond the frame on every side, and
        -- the next one in covers all but its own thickness.
        part:ClearAllPoints()
        part:SetPoint("TOPLEFT", frame, "TOPLEFT", -out, out)
        part:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", out, -out)
        part._mask:ClearAllPoints()
        part._mask:SetAllPoints(part)

        out = out - layer.thickness * scale
    end

    -- Anything left over from a shorter list of layers.
    for index = #layers + 1, #parts do
        parts[index]:Hide()
    end
    for index = 1, #layers do parts[index]:Show() end

    return frame
end

---------------------------------------------------------------------------
-- Small icon buttons
--
-- A gear that opens settings should be the same gear everywhere. It was
-- not: the notification panel drew one, the drawer used Blizzard's round
-- info button - an "i", for a button that opens settings - and anything
-- added later would have picked whichever it saw first.
--
--   Theme.CreateSettingsButton(parent, { size = 20, onClick = fn })
--
-- Muted until the mouse is on it, gold while it is, with a tooltip
-- saying what it does. Theme.CreateIconButton takes any texture or atlas
-- and behaves the same way.
---------------------------------------------------------------------------

function Theme.CreateIconButton(parent, opts)
    opts = opts or {}
    local size = opts.size or 20

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(opts.iconSize or (size - 4), opts.iconSize or (size - 4))
    if opts.atlas then
        icon:SetAtlas(opts.atlas)
    else
        icon:SetTexture(opts.texture)
    end

    -- Blizzard's icons carry their own colour; desaturating first means
    -- the tint is the only colour on them, so they sit in our palette
    -- rather than beside it.
    icon:SetDesaturated(true)
    icon:SetVertexColor(unpack(opts.color or Theme.colors.textSoft))
    button.icon = icon

    button:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(unpack(opts.hoverColor or Theme.colors.gold))
        if opts.tooltip then
            GameTooltip:SetOwner(self, opts.tooltipAnchor or "ANCHOR_BOTTOM")
            GameTooltip:SetText(opts.tooltip)
            if opts.tooltipLine then
                GameTooltip:AddLine(opts.tooltipLine, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(unpack(opts.color or Theme.colors.textSoft))
        GameTooltip:Hide()
    end)

    if opts.onClick then button:SetScript("OnClick", opts.onClick) end

    return button
end

-- The gear, everywhere it is wanted.
function Theme.CreateSettingsButton(parent, opts)
    opts = opts or {}
    opts.texture = opts.texture or "Interface\\Buttons\\UI-OptionsButton"
    opts.tooltip = opts.tooltip or "Settings"
    return Theme.CreateIconButton(parent, opts)
end

-- The same border, square.
--
-- Four solid textures inset inside each other: two pixels of dark, one
-- of gold, one of dark, then whatever the inside should be. No mask and
-- no art, which is the whole point - this is the status bar's border
-- with the bar taken out, so anything wearing it belongs to the same
-- suite without anybody drawing anything.
--
--   Theme.ApplyBorder(frame, { fill = Theme.colors.bg, scale = 1 })
--
-- Drawn inside the frame's own bounds, so what the frame measures is
-- what it covers.
local BORDER_LAYERS = {
    { inset = 0, color = { 0, 0, 0, 0.75 } },
    { inset = 2, color = { 0.55, 0.43, 0.25, 1 } },
    { inset = 3, color = { 0.035, 0.04, 0.055, 1 } },
}

function Theme.ApplyBorder(frame, opts)
    opts = opts or {}
    local scale = opts.scale or 1
    local layer = opts.layer or "BACKGROUND"
    local base  = opts.sublevel or -8

    frame._bazBorder = frame._bazBorder or {}
    local parts = frame._bazBorder

    for index, spec in ipairs(BORDER_LAYERS) do
        local texture = parts[index]
        if not texture then
            texture = frame:CreateTexture(nil, layer, nil, base + index - 1)
            parts[index] = texture
        end
        local color = spec.color
        texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        local inset = spec.inset * scale
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    end

    local fill = opts.fill
    if fill then
        local texture = parts[4]
        if not texture then
            texture = frame:CreateTexture(nil, layer, nil, base + 3)
            parts[4] = texture
        end
        texture:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
        local inset = 4 * scale
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    elseif parts[4] then
        parts[4]:Hide()
    end

    return frame
end

-- A round border around an icon, as an object.
--
-- Three filled circles, each smaller than the last: what shows of each
-- is the part the next one does not cover, which is the status bar's
-- border bent into a circle. They go under whatever they surround,
-- because a filled circle drawn over an icon is just a filled circle -
-- the picture these replace could sit on top only by having a hole in
-- the middle.
--
--   local ring = Theme.CreateRoundRing(parent, { sublevel = -8 })
--   ring:SetInnerSize(26)          -- the icon's diameter
--   ring:SetTint(1, 0.92, 0.55)    -- lands on the gold
--
-- The tint goes to the gold because that is the part worth colouring:
-- the micro menu pulses a button by brightening it.
local ROUND_RING_LAYERS = {
    { thickness = 2, color = { 0, 0, 0, 0.75 } },
    { thickness = 1, color = { 0.55, 0.43, 0.25, 1 } },
    { thickness = 1, color = { 0.035, 0.04, 0.055, 1 } },
}

function Theme.CreateRoundRing(parent, opts)
    opts = opts or {}
    local layer = opts.layer or "BACKGROUND"
    local base  = opts.sublevel or -8

    -- A caller can thicken a layer without redesigning the border. The
    -- round mask blends over roughly a pixel at every edge, so a gold
    -- layer only one pixel wide is nearly all blend, with dark mixing in
    -- from both sides: the same colour as the square border, and duller
    -- to look at. Giving it a second pixel gives it one at full strength.
    local layers = opts.layers or ROUND_RING_LAYERS

    local ring = { parts = {} }

    for index, spec in ipairs(layers) do
        local texture = parent:CreateTexture(nil, layer, nil, base + index - 1)
        texture:SetColorTexture(spec.color[1], spec.color[2],
            spec.color[3], spec.color[4] or 1)
        local mask = parent:CreateMaskTexture()
        mask:SetTexture(Skin.ROUND_MASK,
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        texture:AddMaskTexture(mask)
        texture._mask = mask
        ring.parts[index] = texture
    end

    ring.gold = ring.parts[2]

    -- Four pixels of border all told, so each circle is the inner size
    -- plus twice whatever is still outside it. A scale multiplies every
    -- layer: the proportions are what make it look like our border, and
    -- a ring around something the size of the minimap wants them bigger
    -- rather than different.
    local scale = opts.scale or 1

    function ring:Thickness()
        local total = 0
        for _, spec in ipairs(layers) do
            total = total + spec.thickness * scale
        end
        return total
    end

    function ring:SetInnerSize(inner)
        local out = self:Thickness()
        for index, spec in ipairs(layers) do
            local texture = self.parts[index]
            local diameter = inner + out * 2
            texture:ClearAllPoints()
            texture:SetPoint("CENTER", opts.anchor or parent, "CENTER", 0, 0)
            texture:SetSize(diameter, diameter)
            texture._mask:SetAllPoints(texture)
            out = out - spec.thickness * scale
        end
    end

    function ring:SetTint(r, g, b)
        self.gold:SetVertexColor(r or 1, g or 1, b or 1)
    end

    function ring:Show()
        for _, texture in ipairs(self.parts) do texture:Show() end
    end

    function ring:Hide()
        for _, texture in ipairs(self.parts) do texture:Hide() end
    end

    return ring
end

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

        local ringObject = Theme.CreateRoundRing(button, { sublevel = -6 })
        button._bazRingObject = ringObject

        -- The gold circle answers to the name the old ring texture had,
        -- since callers tint it and that is the part worth tinting.
        button._bazRingOuter = ringObject.parts[1]
        button._bazRingInner = ringObject.parts[3]
        button._bazDisc, button._bazDiscMask, button._bazIconMask, button._bazRing =
            disc, discMask, iconMask, ringObject.gold

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

    button._bazRingObject:SetInnerSize(inner)

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
