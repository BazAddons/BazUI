-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: StatusBar
--
-- Every bar in the suite. Health, power, casting, experience, reputation,
-- and the hairline readings inside a panel. One widget rather than one
-- per module, because they are the same object at different sizes: a
-- track, a fill, sometimes a second fill behind it, sometimes text.
--
-- Two presets, chosen with opts.style:
--
--   "screen"  a bar that stands on the screen. Drop shadow, gold rim,
--             a lit top edge, a spark at the fill's leading edge,
--             optional tick marks, and text that can show always, on
--             hover, or never. This is the XP bar's look, which is the
--             one the suite settled on.
--   "panel"   a bar that lives inside something else. The flat one-pixel
--             edge and nothing more, because a panel row that drew a
--             shadow would fight the card it sits in.
--
-- API:
--   local bar = BazUI.CreateStatusBar(name, parent, opts)
--   bar:SetValue(fraction)            0..1
--   bar:SetOverlay(fraction)          a second segment beyond the fill
--                                     (rested experience, cast delay)
--   bar:SetFillColor(color)           a Theme color or {r,g,b,a}
--   bar:SetOverlayColor(color)
--   bar:SetText(text)                 nil or "" hides it
--   bar:SetTextMode("always"|"hover"|"never")
--   bar:SetTicks(count)               0 for none
--   bar:SetFillDirection("LEFT"|"RIGHT")  which end it fills from
--   bar:SetBarSize(width, height)     the size of the FILL; the frame
--                                     comes out bigger by the border
--   bar:SetOuterSize(width, height)   the size of the frame instead
--   bar:GetFillSize() / bar:GetInset()
--
-- The frame it returns is a Button, so a caller can give it scripts. It
-- is never made secure here: a bar that needs to target something is
-- built on a secure template by its own module and handed in as parent.
---------------------------------------------------------------------------

local Theme = BazUI.Skin and BazUI.Skin.Theme

-- What a bar is filled with: a texture, whether to work the color up and
-- down it, and whether it wears the lit top edge. Asked as a bar draws
-- rather than copied at load, so a change of fill reaches all of them.
local function FillDef()
    local Skin = BazUI.Skin
    if Skin and Skin.FillDef then return Skin.FillDef() end
    return { texture = (Skin and Skin.XP_FILL) or "Interface\\TargetingFrame\\UI-StatusBar", sheen = true }
end

-- A gradient fill takes one color and makes two of it, lighter at the top
-- and darker at the bottom, so a flat white texture reads as a lit bar
-- with no artwork involved at all.
local LIFT, DROP = 0.30, 0.30

local function Shade(color, amount)
    local function Channel(value)
        value = (value or 0) + amount
        if value < 0 then return 0 elseif value > 1 then return 1 end
        return value
    end
    return Channel(color[1]), Channel(color[2]), Channel(color[3])
end

-- A bar's edge is the suite's border, drawn along a rectangle: bands of
-- solid color laid one outside the next.
--
-- The size a caller asks for is the size of the fill, and the chrome is
-- added around it - so the frame comes out as the fill plus twice the
-- border on each side. That is what makes a thicker border grow the bar
-- rather than eat it: a border you have just set to seven pixels should
-- not leave a twenty-pixel bar with six pixels of green in it.
--
-- The chrome is still drawn inside the frame, which is the other half of
-- it. Drawn beyond the frame's edges instead, a bar would be wider than
-- its own box, and one docked to a host of the same width would overhang
-- it on both sides. The frame bounds everything it draws; it is just
-- bigger than the fill by however much border there is.

local function Solid(parent, layer, color, sublevel)
    local texture = parent:CreateTexture(nil, layer, nil, sublevel)
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return texture
end

local BarMixin = {}

---------------------------------------------------------------------------
-- Color
---------------------------------------------------------------------------

function BarMixin:SetFillColor(color)
    color = color or (Theme and Theme.colors.gold) or { 1, 0.82, 0, 1 }
    self._fillColor = color

    local alpha = color[4] or 1
    local texture = self.fill:GetStatusBarTexture()
    local def = self._screen and FillDef() or nil

    -- A colour we are not allowed to read, from a unit whose identity is
    -- restricted. It can still be painted - SetStatusBarColor is one of the
    -- setters the client lets a tainted caller hand a secret to - but not
    -- shaded, because working out a lighter top and a darker bottom means
    -- arithmetic on the parts, and SetGradient will not take them either.
    --
    -- So this one goes on flat. The gradient is levelled off first, since a
    -- texture keeps the last one it was given and a reused bar would
    -- otherwise wear the previous unit's shading over this unit's colour.
    if color.secret then
        if texture and texture.SetGradient and CreateColor then
            texture:SetGradient("VERTICAL",
                CreateColor(1, 1, 1, alpha), CreateColor(1, 1, 1, alpha))
        end
        self.fill:SetStatusBarColor(color[1], color[2], color[3], alpha)
        return
    end

    -- Through the gradient either way, even when both ends are the same
    -- color. A gradient and a vertex color are the same slot on a texture,
    -- so setting one of them sometimes and the other the rest of the time
    -- would leave whichever was set last on a texture that gets reused.
    if def and texture and texture.SetGradient and CreateColor then
        local topR, topG, topB, botR, botG, botB
        if def.gradient then
            topR, topG, topB = Shade(color, LIFT)
            botR, botG, botB = Shade(color, -DROP)
        else
            topR, topG, topB = color[1], color[2], color[3]
            botR, botG, botB = color[1], color[2], color[3]
        end
        -- VERTICAL runs bottom to top.
        texture:SetGradient("VERTICAL",
            CreateColor(botR, botG, botB, alpha),
            CreateColor(topR, topG, topB, alpha))
    else
        self.fill:SetStatusBarColor(color[1], color[2], color[3], alpha)
    end
end

-- The fill, and the lit edge that belongs to it. Called again whenever
-- the choice changes, so a bar answers without a reload.
function BarMixin:RefreshFill()
    if not self._screen then return end
    local def = FillDef()
    self.fill:SetStatusBarTexture(self._fillTexture or def.texture)
    if self.sheen then self.sheen:SetShown(def.sheen ~= false) end
    self:SetFillColor(self._fillColor)
    Theme.TrackFill(self, Theme.RedrawBarFill)
end

function BarMixin:SetOverlayColor(color)
    color = color or { 0.12, 0.3, 0.52, 0.9 }
    self._overlayColor = color
    if self.overlay then
        self.overlay:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    end
end

---------------------------------------------------------------------------
-- Value
--
-- The fill is a StatusBar so the texture stretches properly; the overlay
-- and the spark are plain textures positioned from the same fraction,
-- which is why the bar has to know its own inner width.
---------------------------------------------------------------------------

-- Which end the bar fills from. "LEFT" is the usual: empty on the left,
-- filling rightward. "RIGHT" mirrors it, which is what the right-hand
-- half of a pair of bars wants so the two drain towards each other
-- rather than both marching the same way.
function BarMixin:SetFillDirection(from)
    self._reversed = (from == "RIGHT")
    self.fill:SetReverseFill(self._reversed)
    if self._rawMax ~= nil then
        self:SetValue(self._rawValue, self._rawMax)
    else
        self:SetValue(self._value or 0)
    end
end

-- One value, given one of two ways.
--
-- Normally a fraction, which the bar clamps and then measures against so
-- it can place a spark and an overlay.
--
-- The other way is a value and its maximum, handed straight to the
-- widget underneath. That exists for numbers we are not allowed to read:
-- Forever made unit health and power *secret*, meaning an addon may hold
-- one and pass it to a widget but may not compare it, divide it, or turn
-- it into a string. Nothing can be measured against a number we cannot
-- look at, so the spark and the overlay - both of which need the
-- fraction - sit out, and the widget, which is allowed to see what we
-- are not, does the filling.
--
-- Callers with a real maximum should pass both on either client. A plain
-- number goes through this path just as happily as a secret one.
function BarMixin:SetValue(fraction, maximum)
    if maximum ~= nil then
        self._rawValue, self._rawMax = fraction, maximum
        self._value = nil
        self.fill:SetMinMaxValues(0, maximum)
        self.fill:SetValue(fraction)
        if self.spark then self.spark:Hide() end
        if self.overlay then self.overlay:Hide() end
        return
    end

    self._rawValue, self._rawMax = nil, nil
    fraction = math.max(0, math.min(1, tonumber(fraction) or 0))
    self._value = fraction
    self.fill:SetMinMaxValues(0, 1)
    self.fill:SetValue(fraction)

    -- The spark sits at the leading edge, which is the other end when
    -- the bar is reversed.
    if self.spark then
        self.spark:SetShown(fraction > 0.001 and fraction < 0.999)
        self.spark:ClearAllPoints()
        if self._reversed then
            self.spark:SetPoint("RIGHT", self.fill, "RIGHT",
                -(self._innerWidth * fraction) + 1, 0)
        else
            self.spark:SetPoint("LEFT", self.fill, "LEFT",
                self._innerWidth * fraction - 1, 0)
        end
    end
    self:_LayoutOverlay()
end

-- The fraction this bar is showing, or nil when it was given a value it
-- is not allowed to read. Nothing in the suite reads this today; it
-- answers nil rather than nought so that anything which starts to read
-- it cannot mistake "cannot say" for "empty".
function BarMixin:GetValue()
    if self._rawMax ~= nil then return nil end
    return self._value or 0
end

-- A second segment starting where the fill stops. Rested experience uses
-- it; so does the delay on a pushed-back cast.
function BarMixin:SetOverlay(fraction)
    self._overlay = math.max(0, math.min(1, tonumber(fraction) or 0))
    self:_LayoutOverlay()
end

function BarMixin:_LayoutOverlay()
    if not self.overlay then return end
    local value = self._value or 0
    local extra = math.min(self._overlay or 0, 1 - value)
    if extra <= 0 then
        self.overlay:Hide()
        return
    end
    self.overlay:ClearAllPoints()
    if self._reversed then
        self.overlay:SetPoint("TOPRIGHT", self.fill, "TOPRIGHT",
            -(self._innerWidth * value), 0)
    else
        self.overlay:SetPoint("TOPLEFT", self.fill, "TOPLEFT",
            self._innerWidth * value, 0)
    end
    self.overlay:SetSize(math.max(0.01, self._innerWidth * extra), self._innerHeight)
    self.overlay:Show()
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

function BarMixin:SetText(text)
    if not self.text then return end
    self._rawText = nil
    self._text = text
    self.text:SetText(text or "")
    self:_RefreshText()
end

-- Text built from numbers we are not allowed to read.
--
-- SetText is given a string this addon assembled, and _RefreshText then
-- measures that string to fit it to the bar. Neither is possible for a
-- secret: only the widget may turn one into text. So the format and the
-- values go straight to the font string, and the fitting is skipped -
-- there is nothing here to measure.
function BarMixin:SetFormattedText(format, ...)
    if not self.text then return end
    self._text = nil
    self._rawText = true
    self.text:SetFormattedText(format, ...)
    self:_RefreshText()
end

-- How big the text in this bar currently is. Anything drawing inline with
-- it - an icon in the middle of the string - has to match a size it did
-- not choose, and SetBarSize works this out from the bar's height rather
-- than from a setting anyone can read.
function BarMixin:TextSize()
    if not self.text then return 12 end
    local _, size = self.text:GetFont()
    return tonumber(size) or 12
end

function BarMixin:SetTextMode(mode)
    self._textMode = mode or "always"
    self:_RefreshText()
end

---------------------------------------------------------------------------
-- A mark in front of the text
--
-- A real texture rather than one of the client's inline text escapes. An
-- escape is laid against the font's baseline and can only be the size of
-- the writing it sits in, and a mark on a bar wants to be the size of the
-- bar: on a tall bar the text stops growing at twelve pixels and an inline
-- glyph stops with it, leaving a speck in a lot of empty height.
--
-- The text is centred in the fill, so an icon hanging off its left would
-- carry the pair off centre. Both move instead: the text shifts right by
-- half of what the icon and its gap take up, which puts the two of them
-- together back in the middle.
---------------------------------------------------------------------------

local LEAD_GAP = 3

function BarMixin:SetLeadIcon(path, size)
    if not self.text then return end

    if not path then
        self._leadSize = nil
        if self.leadIcon then self.leadIcon:Hide() end
        self:_RefreshText()
        return
    end

    local icon = self.leadIcon
    if not icon then
        icon = self.fill:CreateTexture(nil, "OVERLAY")
        self.leadIcon = icon
    end

    size = math.max(1, math.floor(tonumber(size) or self:TextSize()))
    icon:SetTexture(path)
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    -- Against the text rather than the bar, so it stays with the writing
    -- it belongs to however the pair ends up centred.
    icon:SetPoint("RIGHT", self.text, "LEFT", -LEAD_GAP, 0)

    self._leadSize = size
    self:_RefreshText()
end

-- Where the text sits, how much room it has and whether it is shown at
-- all, in one place - because the icon in front of it changes all three
-- and two owners would drift.
function BarMixin:_RefreshText()
    if not self.text then return end
    local mode = self._textMode or "always"
    -- Text we cannot read is still text. _text is empty for a secret,
    -- so asking only that would hide the string the moment anything
    -- refreshed the layout - a hover, a resize.
    local hasText = (self._text or "") ~= "" or self._rawText == true
    local wanted = hasText
        and (mode == "always" or (mode == "hover" and self._hovered))
    self.text:SetShown(wanted)

    -- The mark is only there to lead the text, so it goes when the text
    -- does.
    local lead = wanted and self._leadSize or nil
    if self.leadIcon then self.leadIcon:SetShown(lead and true or false) end

    local taken = lead and (lead + LEAD_GAP) or 0
    local width = self._innerWidth or self:GetWidth() or 0
    self.text:SetWidth(math.max(10, width - 10 - taken))
    self.text:ClearAllPoints()
    self.text:SetPoint("CENTER", self.fill, "CENTER", taken / 2, 0)
end

---------------------------------------------------------------------------
-- Ticks
---------------------------------------------------------------------------

function BarMixin:SetTicks(count)
    self._tickCount = count or 0
    for _, tick in ipairs(self._ticks) do tick:Hide() end
    if self._tickCount < 2 then return end

    for i = 1, self._tickCount - 1 do
        local tick = self._ticks[i]
        if not tick then
            tick = Solid(self.fill, "OVERLAY", { 0, 0, 0, 0.22 })
            self._ticks[i] = tick
        end
        tick:ClearAllPoints()
        tick:SetPoint("LEFT", self.fill, "LEFT", self._innerWidth * i / self._tickCount, 0)
        tick:SetSize(1, self._innerHeight)
        tick:Show()
    end
end

---------------------------------------------------------------------------
-- Size
--
-- Called whenever the bar is resized, including by the dock system when
-- its host changes width. Everything inside is positioned from the inner
-- measurements, so they are worked out once here.
---------------------------------------------------------------------------

-- The bands, and how far in they push the fill. Called again whenever
-- the border changes, so a bar answers a new skin without a reload.
function BarMixin:RefreshChrome()
    if not self._screen then return end

    local layers = Theme.GetBorder()
    self._bands = self._bands or {}
    local accent = Theme.AccentBand(layers)

    -- Outermost first, each one inset by everything drawn before it.
    local slot, inset = 0, 0
    for index = #layers, 1, -1 do
        local band = layers[index]
        slot = slot + 1

        local texture = self._bands[slot]
        if not texture then
            texture = Solid(self, "BACKGROUND", band.color, math.max(-8, -8 + slot - 1))
            self._bands[slot] = texture
        end

        -- A caller can recolor two of them without knowing what the
        -- border is: the band against the fill, and the one that reads
        -- as the edge.
        local color = band.color
        if index == 1 and self._trackColor then color = self._trackColor end
        if index == accent and self._rimColor then color = self._rimColor end
        texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)

        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", self, "TOPLEFT", inset, -inset)
        texture:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -inset, inset)
        texture:Show()

        inset = inset + band.thickness
    end

    for index = slot + 1, #self._bands do self._bands[index]:Hide() end

    self._inset = inset
    self.fill:ClearAllPoints()
    self.fill:SetPoint("TOPLEFT", inset, -inset)
    -- Laid out again around the same fill: the frame grows or shrinks by
    -- the change in the border, and the spark, ticks and text follow.
    self:SetBarSize(self._fillWidth or self:GetWidth(), self._fillHeight or self:GetHeight())

    Theme.TrackBorder(self, Theme.RedrawBarChrome)
end

function BarMixin:SetBarSize(width, height)
    -- A pixel is the floor, and only because nothing can be drawn with
    -- none. How thin a bar is worth having is the reader's business, not
    -- this widget's: a two-pixel power bar under a health bar is a
    -- perfectly good way to run a unit frame.
    width  = math.max(1, tonumber(width) or 1)
    height = math.max(1, tonumber(height) or 1)

    -- Remembered, because this is the one size the bar is told and the
    -- chrome around it can change afterwards. RefreshChrome asks for
    -- these again rather than reading the frame, which by then is the
    -- fill plus the old border.
    self._fillWidth, self._fillHeight = width, height

    local inset = self._inset or 0
    self._innerWidth, self._innerHeight = width, height
    self:SetSize(width + inset * 2, height + inset * 2)
    self.fill:SetSize(width, height)

    if self.spark then self.spark:SetSize(2, self._innerHeight) end
    if self.text then
        self.text:SetFont(Theme and Theme.FontFile() or STANDARD_TEXT_FONT,
            math.max(8, math.min(12, height - 2)), "OUTLINE")
        self:_RefreshText()
    end

    self:SetTicks(self._tickCount or 0)
    self:SetValue(self._value or 0)
end

-- Sized by its box instead, for a caller with a space to fill rather than
-- a bar to draw: a nameplate as wide as the width somebody set, a bar
-- stretched to match the frame it is docked to. Either measurement may be
-- left out, and that one is kept as it is.
function BarMixin:SetOuterSize(width, height)
    local inset = self._inset or 0
    local fillW = width and math.max(1, width - inset * 2) or self._fillWidth or 1
    local fillH = height and math.max(1, height - inset * 2) or self._fillHeight or 1
    self:SetBarSize(fillW, fillH)
end

-- The fill's size, which is not the frame's.
function BarMixin:GetFillSize()
    return self._fillWidth or 0, self._fillHeight or 0
end

-- How much of the frame is border, on each side. For a caller laying a
-- bar out inside something it has to size itself.
function BarMixin:GetInset()
    return self._inset or 0
end

---------------------------------------------------------------------------
-- Factory
---------------------------------------------------------------------------

function BazUI.CreateStatusBar(name, parent, opts)
    opts = opts or {}
    local style = opts.style or "screen"
    local screen = (style ~= "panel")

    -- A bar that has to answer a click with something protected, like
    -- targeting a unit, is built on a secure template and handed its
    -- attributes by the caller. The widget itself sets none of them.
    local bar = CreateFrame("Button", name, parent or UIParent, opts.template)
    Mixin(bar, BarMixin)
    bar._ticks = {}
    bar._textMode = opts.textMode or "always"
    bar._screen = screen
    bar._rimColor, bar._trackColor = opts.rimColor, opts.trackColor
    bar._inset = screen and Theme.BorderThickness() or 1

    if not screen and Theme and Theme.ApplyFlatPanel then
        Theme.ApplyFlatPanel(bar, opts.trackColor or { 0.02, 0.02, 0.02, 0.85 },
            opts.rimColor or Theme.colors.edge)
    end

    -- A caller naming its own texture keeps it whatever the skin says:
    -- it asked for that one in particular.
    bar._fillTexture = opts.texture

    bar.fill = CreateFrame("StatusBar", nil, bar)
    bar.fill:SetPoint("TOPLEFT", bar._inset, -bar._inset)
    bar.fill:SetStatusBarTexture(screen and (opts.texture or FillDef().texture)
        or "Interface\\Buttons\\WHITE8x8")
    bar.fill:SetMinMaxValues(0, 1)
    bar.fill:SetValue(0)

    if opts.overlay ~= false then
        bar.overlay = Solid(bar.fill, "BACKGROUND", { 0.12, 0.3, 0.52, 0.9 })
        bar.overlay:Hide()
    end

    -- A light line along the top of the fill, so it reads as lit rather
    -- than painted. The one detail that makes the XP bar look finished.
    local sheen = Solid(bar.fill, "OVERLAY", { 1, 1, 1, screen and 0.12 or 0.14 })
    sheen:SetPoint("TOPLEFT", bar.fill, "TOPLEFT")
    sheen:SetPoint("TOPRIGHT", bar.fill, "TOPRIGHT")
    sheen:SetHeight(1)
    bar.sheen = sheen

    -- The lit edge that follows the fill. Right on a bar you watch, and
    -- twenty of them at once - one per nameplate - is a lot of sparkle,
    -- so a caller can say no.
    if screen and opts.spark ~= false then
        bar.spark = Solid(bar.fill, "OVERLAY", { 0.8, 0.9, 1, 0.8 })
        bar.spark:Hide()
    end

    if opts.text ~= false and screen then
        bar.text = bar.fill:CreateFontString(nil, "OVERLAY")
        bar.text:SetPoint("CENTER")
        bar.text:SetTextColor(1, 1, 1)
        bar.text:SetWordWrap(false)
    end

    bar:HookScript("OnEnter", function(self)
        self._hovered = true
        self:_RefreshText()
    end)
    bar:HookScript("OnLeave", function(self)
        self._hovered = false
        self:_RefreshText()
    end)

    bar:SetFillColor(opts.color)
    bar:SetOverlayColor(opts.overlayColor)
    bar:SetBarSize(opts.width or 200, opts.height or 18)
    -- The bands last, because drawing them re-lays the fill out and the
    -- fill has to exist first.
    bar:RefreshChrome()
    bar:RefreshFill()
    bar:SetTicks(opts.ticks or 0)
    return bar
end
