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
--   bar:SetFillColor(color)           a Theme colour or {r,g,b,a}
--   bar:SetOverlayColor(color)
--   bar:SetText(text)                 nil or "" hides it
--   bar:SetTextMode("always"|"hover"|"never")
--   bar:SetTicks(count)               0 for none
--   bar:SetBarSize(width, height)     lays the inner parts out again
--
-- The frame it returns is a Button, so a caller can give it scripts. It
-- is never made secure here: a bar that needs to target something is
-- built on a secure template by its own module and handed in as parent.
---------------------------------------------------------------------------

local Theme = BazUI.Skin and BazUI.Skin.Theme

local DEFAULT_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local SHADOW = { 0, 0, 0, 0.75 }
local RIM    = { 0.55, 0.43, 0.25, 1 }
local TRACK  = { 0.035, 0.04, 0.055, 1 }

local function Solid(parent, layer, color, sublevel)
    local texture = parent:CreateTexture(nil, layer, nil, sublevel)
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return texture
end

local BarMixin = {}

---------------------------------------------------------------------------
-- Colour
---------------------------------------------------------------------------

function BarMixin:SetFillColor(color)
    color = color or (Theme and Theme.colors.gold) or { 1, 0.82, 0, 1 }
    self._fillColor = color
    self.fill:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
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

function BarMixin:SetValue(fraction)
    fraction = math.max(0, math.min(1, tonumber(fraction) or 0))
    self._value = fraction
    self.fill:SetValue(fraction)

    if self.spark then
        self.spark:SetShown(fraction > 0.001 and fraction < 0.999)
        self.spark:ClearAllPoints()
        self.spark:SetPoint("LEFT", self.fill, "LEFT", self._innerWidth * fraction - 1, 0)
    end
    self:_LayoutOverlay()
end

function BarMixin:GetValue()
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
    self.overlay:SetPoint("TOPLEFT", self.fill, "TOPLEFT", self._innerWidth * value, 0)
    self.overlay:SetSize(math.max(0.01, self._innerWidth * extra), self._innerHeight)
    self.overlay:Show()
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

function BarMixin:SetText(text)
    if not self.text then return end
    self._text = text
    self.text:SetText(text or "")
    self:_RefreshText()
end

function BarMixin:SetTextMode(mode)
    self._textMode = mode or "always"
    self:_RefreshText()
end

function BarMixin:_RefreshText()
    if not self.text then return end
    local mode = self._textMode or "always"
    local wanted = (self._text or "") ~= ""
        and (mode == "always" or (mode == "hover" and self._hovered))
    self.text:SetShown(wanted)
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

function BarMixin:SetBarSize(width, height)
    width  = math.max(8, tonumber(width) or 8)
    height = math.max(4, tonumber(height) or 4)
    self:SetSize(width, height)

    local inset = self._inset
    self._innerWidth  = width - inset * 2
    self._innerHeight = height - inset * 2
    self.fill:SetSize(self._innerWidth, self._innerHeight)

    if self.spark then self.spark:SetSize(2, self._innerHeight) end
    if self.text then
        self.text:SetWidth(math.max(10, self._innerWidth - 10))
        self.text:SetFont(Theme and Theme.FontFile() or STANDARD_TEXT_FONT,
            math.max(8, math.min(12, height - 2)), "OUTLINE")
    end

    self:SetTicks(self._tickCount or 0)
    self:SetValue(self._value or 0)
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
    bar._inset = screen and 2 or 1
    bar._textMode = opts.textMode or "always"

    if screen then
        -- A dark halo so the bar reads over any ground, then the rim,
        -- then the track it fills against.
        local shadow = Solid(bar, "BACKGROUND", SHADOW, -8)
        shadow:SetPoint("TOPLEFT", -2, 2)
        shadow:SetPoint("BOTTOMRIGHT", 2, -2)

        local rim = Solid(bar, "BACKGROUND", opts.rimColor or RIM, -7)
        rim:SetAllPoints(bar)

        local track = Solid(bar, "BACKGROUND", opts.trackColor or TRACK, -6)
        track:SetPoint("TOPLEFT", 1, -1)
        track:SetPoint("BOTTOMRIGHT", -1, 1)
        bar.rim, bar.track = rim, track
    elseif Theme and Theme.ApplyFlatPanel then
        Theme.ApplyFlatPanel(bar, opts.trackColor or { 0.02, 0.02, 0.02, 0.85 },
            opts.rimColor or Theme.colors.edge)
    end

    bar.fill = CreateFrame("StatusBar", nil, bar)
    bar.fill:SetPoint("TOPLEFT", bar._inset, -bar._inset)
    bar.fill:SetStatusBarTexture(screen and (opts.texture or DEFAULT_TEXTURE)
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

    if screen then
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
    bar:SetTicks(opts.ticks or 0)
    return bar
end
