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

-- The palette. A skin repaints these tables in place rather than
-- replacing them (see Skin\Skins.lua), so hold a reference to one and
-- read it as you draw; taking a copy of the numbers opts out of skinning.
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

    -- What rank a unit is. Borrowed from item quality, because that is a
    -- reading every player already has: blue is rare, purple is rarer,
    -- and red is the one that kills you. Elite takes gold rather than a
    -- quality color, since a gold dragon is what elite has always looked
    -- like.
    rankRare      = { 0.40, 0.68, 1.00, 0.85 },
    rankElite     = { 1.00, 0.78, 0.25, 0.85 },
    rankRareElite = { 0.70, 0.40, 1.00, 0.85 },
    rankBoss      = { 1.00, 0.35, 0.30, 0.90 },
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
-- The border
--
-- Every edge in the suite - a bar's, a panel's, a round button's - is the
-- same recipe: bands of solid color laid one outside the next, with no
-- art anywhere. This is that recipe, and there is one of it.
--
-- The list runs inside out. Band 1 touches whatever is inside; each one
-- after it sits outside the last. A skin can say anything here, from
-- nothing at all - a naked fill with no edge - to as many bands as it
-- likes:
--
--   Theme.SetBorder({
--       { thickness = 1, color = { 0.03, 0.04, 0.06, 1 } },
--       { thickness = 1, color = { 0.55, 0.43, 0.25, 1 }, accent = true },
--       { thickness = 2, color = { 0, 0, 0, 0.75 } },
--   })
--
-- BazUI's own is those three: a dark line, a pixel of gold, and two
-- pixels of near-black outside it. The gold is one pixel and does all the
-- work, which it can only do with dark on both sides of it - one holding
-- it off the fill, the other holding it off whatever the frame is sitting
-- over. A band marked accent is the one worth lighting up: the micro menu
-- pulses a button by brightening it.
--
-- Everything that draws an edge reads this and nothing else, so how thick
-- a bar's chrome is, how far a ring reaches and where a fill starts all
-- follow from it. The three renderers below draw it square inside a
-- frame, round outside one, and round as an object; the status bar widget
-- draws the same bands along a bar.
---------------------------------------------------------------------------

Theme.border = {
    { thickness = 1, color = { 0.035, 0.04, 0.055, 1 } },
    { thickness = 1, color = { 0.55, 0.43, 0.25, 1 }, accent = true },
    { thickness = 2, color = { 0, 0, 0, 0.75 } },
}

-- Read through this rather than copied, so a skin change reaches the next
-- thing drawn.
function Theme.GetBorder()
    return Theme.border
end

-- How far the border reaches: where a fill starts, and how much room a
-- ring has to leave around what it surrounds.
function Theme.BorderThickness(scale, layers)
    local total = 0
    for _, band in ipairs(layers or Theme.border) do
        total = total + (tonumber(band.thickness) or 0)
    end
    return total * (scale or 1)
end

-- The band to brighten when something wants to light its edge up. A skin
-- can say which; failing that it is the lightest one, which is what
-- lighting up an edge means in the first place.
function Theme.AccentBand(layers)
    layers = layers or Theme.border
    local best, bestLight
    for index, band in ipairs(layers) do
        if band.accent then return index end
        local c = band.color or {}
        local light = ((c[1] or 0) + (c[2] or 0) + (c[3] or 0)) * (c[4] or 1)
        if not bestLight or light > bestLight then best, bestLight = index, light end
    end
    return best
end

---------------------------------------------------------------------------
-- Keeping what is already drawn in step
--
-- A color can be repainted by writing into the table everything is
-- reading from. A border cannot: it is a row of textures whose sizes and
-- positions came from the thicknesses, so changing those means drawing it
-- again. Everything wearing one says so here, and a change to the border
-- redraws the lot rather than waiting for a reload.
--
-- Weak keys: a frame that goes away takes its entry with it.
---------------------------------------------------------------------------

-- Draw order within a layer runs -8 to 7 and nothing outside that is
-- legal, so a border of more bands than there are slots would start
-- drawing them in whatever order they were created. Bands take the low
-- slots and a fill takes the top one.
local MIN_SUBLEVEL, MAX_SUBLEVEL = -8, 7
Theme.MAX_BORDER_BANDS = 12

local function Sublevel(value)
    return math.max(MIN_SUBLEVEL, math.min(MAX_SUBLEVEL, value))
end

local bordered = setmetatable({}, { __mode = "k" })

function Theme.TrackBorder(target, redraw)
    if target and redraw then bordered[target] = redraw end
end

-- The redraws, made once. Everything they need is on the target, so a
-- closure per call would only be garbage: these run on every drag step of
-- a color picker.
local function RedrawBorder(target) Theme.ApplyBorder(target, target._bazBorderOpts) end
local function RedrawRing(target) Theme.ApplyRing(target, target._bazRingOpts) end
local function RedrawRoundRing(ring)
    if ring._inner then ring:SetInnerSize(ring._inner) end
end

-- The status bar widget's two, kept here with the rest of them so it can
-- hand over a function rather than build one per bar.
function Theme.RedrawBarChrome(bar) bar:RefreshChrome() end
function Theme.RedrawBarFill(bar) bar:RefreshFill() end

function Theme.RefreshBorders()
    for target, redraw in pairs(bordered) do
        -- One that errors is one whose frame has gone strange; drop it
        -- rather than let it stop the rest being redrawn.
        if not pcall(redraw, target) then bordered[target] = nil end
    end
end

-- The same arrangement for what a bar is filled with, which is a texture
-- on a frame rather than anything a color table can reach.
local filled = setmetatable({}, { __mode = "k" })

function Theme.TrackFill(target, redraw)
    if target and redraw then filled[target] = redraw end
end

function Theme.RefreshFills()
    for target, redraw in pairs(filled) do
        if not pcall(redraw, target) then filled[target] = nil end
    end
end

-- And the same again for glows, which are a color painted onto textures
-- like a border is, but on their own frames and their own schedule.
local glowing = setmetatable({}, { __mode = "k" })

function Theme.TrackGlow(target, redraw)
    if target and redraw then glowing[target] = redraw end
end

function Theme.RefreshGlows()
    for target, redraw in pairs(glowing) do
        if not pcall(redraw, target) then glowing[target] = nil end
    end
end

---------------------------------------------------------------------------
-- A glow around a frame
--
-- Rings. One rectangular outline per pixel of glow, each a step fainter
-- than the one inside it, so the whole thing reads as light falling away
-- from the edge.
--
-- The first attempt at this was four gradient strips, and the corners
-- gave it away: the top strip had to run past the frame's sides to cover
-- them, and it arrived there still at full strength, so each corner came
-- out a bright rectangular flange. A gradient only fades along one axis
-- and a corner needs it to fade along two.
--
-- Rings have no such problem. Every ring is a complete outline at one
-- alpha, so a corner is simply part of its ring and cannot be brighter
-- or dimmer than the rest of it. Within a ring the top and bottom run
-- the full width and the sides only what is left between them - touching,
-- never overlapping, because these are drawn ADD and an overlap would
-- show as a seam.
--
-- No art either way, which is the point: a glow made of numbers takes
-- its color from the skin like everything else instead of needing a file
-- per color.
--
-- It does not pulse. A pulse says something just happened; this says
-- what a thing is, and a thing that is permanently true should not be
-- permanently moving in the corner of your eye.
---------------------------------------------------------------------------

Theme.GLOW_SIZE = 6
Theme.MAX_GLOW_SIZE = 16

local function RedrawGlow(frame)
    Theme.SetGlow(frame, frame._bazGlowColor, frame._bazGlowSize)
end

-- color nil takes the glow off. The color table is held rather than
-- copied, so a skin change reaches it: RefreshGlows draws it again with
-- whatever numbers are in the table by then.
function Theme.SetGlow(frame, color, size)
    if not frame then return end
    frame._bazGlowColor = color
    frame._bazGlowSize  = size

    local parts = frame._bazGlow
    if not color then
        if parts then
            for _, texture in ipairs(parts) do texture:Hide() end
        end
        return
    end

    size = math.max(1, math.min(Theme.MAX_GLOW_SIZE,
        math.floor(tonumber(size) or Theme.GLOW_SIZE)))

    parts = parts or {}
    frame._bazGlow = parts

    local r, g, b = color[1] or 1, color[2] or 1, color[3] or 1
    local base = color[4] or 1

    local slot = 0
    for ring = 1, size do
        -- Squared rather than straight, because light falls away faster
        -- than a straight line does and a linear ramp reads as a flat
        -- band with an edge on it.
        local t = 1 - (ring - 1) / size
        local alpha = base * t * t

        -- How far out this ring sits, and the gap its sides have to fill
        -- between the top and bottom of the same ring.
        local out = ring
        local inset = ring - 1

        -- Every piece is anchored by its own TOPLEFT and BOTTOMRIGHT, so
        -- each one is fully sized by where it is pinned rather than
        -- needing a width or a height of its own. Which of the frame's
        -- corners it hangs from is what makes it a top, a side or a
        -- bottom.
        --
        --   { relativePoint, x, y, relativePoint, x, y }
        local sides = {
            -- Top and bottom run the full width of this ring, corners
            -- included, so the corners belong to exactly one piece.
            { "TOPLEFT",    -out,   out,    "TOPRIGHT",     out,   inset  },
            { "BOTTOMLEFT", -out,  -inset,  "BOTTOMRIGHT",  out,  -out    },
            -- The sides fill only what is left between them.
            { "TOPLEFT",    -out,   inset,  "BOTTOMLEFT",  -inset, -inset },
            { "TOPRIGHT",    inset, inset,  "BOTTOMRIGHT",  out,   -inset },
        }

        for _, side in ipairs(sides) do
            slot = slot + 1
            local texture = parts[slot]
            if not texture then
                -- Outside the frame, so it covers nothing the frame owns
                -- and the sublevel only has to be stable.
                texture = frame:CreateTexture(nil, "BACKGROUND", nil, Sublevel(-8))
                parts[slot] = texture
            end
            texture:SetColorTexture(r, g, b, alpha)
            texture:SetBlendMode("ADD")
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT",     frame, side[1], side[2], side[3])
            texture:SetPoint("BOTTOMRIGHT", frame, side[4], side[5], side[6])
            texture:Show()
        end
    end

    -- Left over from a larger glow than this one.
    for index = slot + 1, #parts do parts[index]:Hide() end

    Theme.TrackGlow(frame, RedrawGlow)
end

-- A band needs a thickness of at least a pixel and a color to draw; a
-- skin arriving from a paste box may have neither.
function Theme.SetBorder(layers)
    local clean = {}
    for _, band in ipairs(type(layers) == "table" and layers or {}) do
        local thickness = math.floor(tonumber(band.thickness) or 0)
        local color = type(band.color) == "table" and band.color or nil
        if thickness > 0 and color and #clean < Theme.MAX_BORDER_BANDS then
            clean[#clean + 1] = {
                thickness = math.min(thickness, 32),
                color     = { color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1 },
                accent    = band.accent and true or nil,
            }
        end
    end
    Theme.border = clean
    Theme.RefreshBorders()
    return clean
end

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

local SHIPPED_FONT = "Interface\\AddOns\\BazUI\\Skin\\Assets\\DORISBR.TTF"

-- The face in use. A skin can point this somewhere else; it is read
-- rather than copied, so read it through Theme.FontFile() or fresh each
-- time rather than taking a copy at load.
Theme.FONT_FILE = SHIPPED_FONT

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

-- A skin may bring a face of its own. Whether the client could read the
-- last one says nothing about this one, so that answer is thrown away
-- and asked again.
function Theme.SetFontFile(path)
    if type(path) ~= "string" or path == "" then path = SHIPPED_FONT end
    if path == Theme.FONT_FILE then return end
    Theme.FONT_FILE = path
    fontLoadable = nil
    Theme.RefreshFontObjects()
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
local fontRecipes = {}

-- Built once per recipe and edited in place from then on. The key is the
-- Blizzard name, plus the tint where there is one, so two buttons asking
-- for the same small white text share one object and a third asking for
-- it in red gets its own.
local function BuildFontObject(key, blizzardName, color)
    local base = _G[blizzardName]
    if not base then return nil end

    local obj = fontObjects[key]
    if not obj then
        obj = CreateFont("BazUI" .. key:gsub("%W", ""))
        fontObjects[key] = obj
        fontRecipes[key] = { name = blizzardName, color = color }
    end

    local baseFace, size, flags = base:GetFont()
    local face = baseFace
    if Theme.IsFontEnabled() and Theme.IsFontLoadable() then face = Theme.FONT_FILE end
    obj:SetFont(face, size or 12, flags or "")
    if color then
        obj:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    else
        obj:SetTextColor(base:GetTextColor())
    end
    obj:SetShadowColor(base:GetShadowColor())
    obj:SetShadowOffset(base:GetShadowOffset())
    local h, v = base:GetJustifyH(), base:GetJustifyV()
    if h then obj:SetJustifyH(h) end
    if v then obj:SetJustifyV(v) end
    return obj
end

function Theme.FontObject(blizzardName)
    return BuildFontObject(blizzardName, blizzardName, nil)
end

-- The same mirror in a color of its own. Text on a button cannot be
-- tinted with SetTextColor, because the button puts its font object back
-- whenever its state changes and takes the object's color with it - so a
-- button that wants red text needs a red font object, not a red string.
function Theme.TintedFontObject(blizzardName, color)
    if not color then return Theme.FontObject(blizzardName) end
    local key = ("%s:%02x%02x%02x"):format(blizzardName,
        math.floor((color[1] or 0) * 255 + 0.5),
        math.floor((color[2] or 0) * 255 + 0.5),
        math.floor((color[3] or 0) * 255 + 0.5))
    return BuildFontObject(key, blizzardName, color)
end

-- CreateFontString names a Blizzard font object to inherit from, which
-- can't be a mirror; this makes the string and points it at one.
function Theme.FontString(parent, layer, blizzardName, sublevel)
    local fs = parent:CreateFontString(nil, layer, nil, sublevel)
    local obj = Theme.FontObject(blizzardName)
    if obj then fs:SetFontObject(obj) end
    return fs
end

---------------------------------------------------------------------------
-- Text on a button
--
-- A button does not simply draw its font string: it holds a normal, a
-- highlight and a disabled font object and puts the right one back on
-- the string every time its state changes. UIPanelButtonTemplate's
-- normal font is GameFontNormalOutline - yellow, twelve point - so a
-- button fonted by reaching for GetFontString() and setting the object
-- there looks right until the first hover, and from then on wears
-- Blizzard's yellow and stays there.
--
-- So font the button, not the string. One face serves both resting and
-- hovered: the highlight texture already says the mouse is over it, and
-- text that changes size under the cursor reads as a fault.
---------------------------------------------------------------------------

Theme.BUTTON_FONT = "GameFontHighlightSmall"

-- The colors button text comes in. A style at the call site rather than
-- three numbers, so every destructive button in the suite is the same
-- red and changing that red is one edit.
Theme.BUTTON_STYLES = {
    danger  = { 1.00, 0.45, 0.45 },
    primary = Theme.colors.gold,
}

-- Font object names come in a Normal / Highlight / Disable set around a
-- shared prefix and suffix, so the grey sibling of a face can be worked
-- out rather than asked for.
local FONT_ROLES = { "Normal", "Highlight", "Disable" }

local function DisabledSibling(blizzardName)
    for _, role in ipairs(FONT_ROLES) do
        local prefix, suffix = blizzardName:match("^(.-)" .. role .. "(.*)$")
        if prefix then
            local sized = prefix .. "Disable" .. suffix
            if _G[sized] then return sized end
            local plain = prefix .. "Disable"
            if _G[plain] then return plain end
            return nil
        end
    end
end

function Theme.SetButtonFont(button, blizzardName, color)
    if not (button and button.SetNormalFontObject) then return end
    blizzardName = blizzardName or Theme.BUTTON_FONT

    local face = Theme.TintedFontObject(blizzardName, color)
    if not face then return end

    local greyName = DisabledSibling(blizzardName)
    local grey = greyName and Theme.FontObject(greyName) or face

    button:SetNormalFontObject(face)
    button:SetHighlightFontObject(face)
    button:SetDisabledFontObject(grey)

    -- Those are only read when the state changes, so put the resting one
    -- on the string now instead of waiting for the first hover.
    local fs = button:GetFontString()
    if fs then fs:SetFontObject(face) end
end

-- The one way to make a push button.
--
--   Theme.CreateButton(parent, { text = "Save", width = 80, height = 22 })
--   Theme.CreateButton(row, { text = "Remove", style = "danger" })
--
-- Size and anchors are left to the caller where it is easier to read
-- them beside the rest of the layout; what the factory guarantees is
-- that the text is in the suite's face and stays there.
function Theme.CreateButton(parent, opts)
    opts = opts or {}
    local button = CreateFrame("Button", opts.name, parent,
        opts.template or "UIPanelButtonTemplate")
    if opts.width and opts.height then button:SetSize(opts.width, opts.height) end
    if opts.text then button:SetText(opts.text) end
    Theme.SetButtonFont(button, opts.font or Theme.BUTTON_FONT,
        opts.color or (opts.style and Theme.BUTTON_STYLES[opts.style]))
    if opts.onClick then button:SetScript("OnClick", opts.onClick) end
    return button
end

-- Re-point every mirrored object at the face now in force.
---------------------------------------------------------------------------
-- Blizzard's font objects, taken over
--
-- Theme.FontObject makes a copy for text we create ourselves. This is the
-- other case: text the game creates, from a font object we do not own and
-- cannot hand a different one to. A tooltip line is made by the game, in
-- GameTooltipText, and the only way to reach it is to change that object -
-- at which point everything drawn in it follows at once, which is the
-- point. A tooltip we have skinned should not be the one thing left in
-- the game's own face.
--
-- It reaches further than our own frames, so the original is kept and put
-- back the moment the switch goes off: taking something over is only
-- reasonable if you can give it back.
--
--   Theme.AdoptFontObject("GameTooltipText")
--   Theme.ReleaseFontObject("GameTooltipText")
--
-- The size and flags are read fresh each time rather than restored from
-- the original, so a font object something else has resized keeps that
-- size and only changes face.
---------------------------------------------------------------------------

local adoptedFonts = {}

local function DrawAdopted(name)
    local object, original = _G[name], adoptedFonts[name]
    if not (object and original and object.GetFont) then return end

    local _, size, flags = object:GetFont()
    local face = original.face
    if Theme.IsFontEnabled() and Theme.IsFontLoadable() then
        face = Theme.FONT_FILE
    end
    object:SetFont(face, size or original.size or 12, flags or original.flags or "")
end

function Theme.AdoptFontObject(name)
    local object = _G[name]
    if not (object and object.GetFont and object.SetFont) then return false end

    if not adoptedFonts[name] then
        local face, size, flags = object:GetFont()
        adoptedFonts[name] = { face = face, size = size, flags = flags }
    end
    DrawAdopted(name)
    return true
end

function Theme.ReleaseFontObject(name)
    local object, original = _G[name], adoptedFonts[name]
    if not (object and original) then return end
    local _, size, flags = object:GetFont()
    object:SetFont(original.face, size or original.size or 12, flags or original.flags or "")
    adoptedFonts[name] = nil
end

function Theme.RefreshFontObjects()
    for key, recipe in pairs(fontRecipes) do BuildFontObject(key, recipe.name, recipe.color) end
    for name in pairs(adoptedFonts) do DrawAdopted(name) end
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

    -- A stat bar fills a space in a card, so the width it was given is
    -- the box rather than the fill.
    bar:SetOuterSize(opts.width or 100, height)
    -- A labelled bar reserves a band above the fill for its two captions.
    -- Twenty rather than sixteen, because sixteen left the text sitting on
    -- the fill with nothing between them.
    local LABEL_BAND  = 20
    local LABEL_INSET = 3

    bar:SetHeight(height + (opts.labels and LABEL_BAND or 0))

    -- The fill sits at the bottom so the labels can have the space above
    -- it, which is the one way a panel row differs from a screen bar.
    bar.fill:ClearAllPoints()
    bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
    bar.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    bar.fill:SetHeight(height - 2)
    bar.track = bar

    if opts.labels then
        -- Inset from the ends rather than flush with them. A caption that
        -- stops exactly where the bar stops reads as cramped against
        -- whatever the bar is sitting in, and the bar is usually sitting
        -- just inside the edge of a card.
        bar.left = Theme.FontString(bar, "OVERLAY", "GameFontHighlightSmall")
        bar.left:SetPoint("TOPLEFT", LABEL_INSET, -2)
        bar.left:SetJustifyH("LEFT")
        bar.left:SetTextColor(unpack(Theme.colors.textSoft))

        bar.right = Theme.FontString(bar, "OVERLAY", "GameFontHighlightSmall")
        bar.right:SetPoint("TOPRIGHT", -LABEL_INSET, -2)
        bar.right:SetJustifyH("RIGHT")
        bar.right:SetTextColor(unpack(Theme.colors.textMuted))

        -- Neither caption may run into the other.
        bar.left:SetPoint("RIGHT", bar.right, "LEFT", -8, 0)
        bar.left:SetWordWrap(false)
        bar.right:SetWordWrap(false)
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

function Theme.ApplyRing(frame, opts)
    opts = opts or {}
    local scale  = opts.scale or 1
    local layers = opts.layers or Theme.GetBorder()

    frame._bazRingParts = frame._bazRingParts or {}
    frame._bazRingOpts  = opts
    local parts = frame._bazRingParts

    -- The band list runs inside out, and these are filled circles rather
    -- than rings: each one has to be drawn before the one inside it, or
    -- it would cover it. So the list is walked backwards, outermost
    -- first, and `out` - how far this circle reaches past the frame -
    -- comes down by a band's thickness as each is drawn.
    local out = Theme.BorderThickness(scale, layers)

    local slot = 0
    for index = #layers, 1, -1 do
        local layer = layers[index]
        slot = slot + 1

        local part = parts[slot]
        if not part then
            part = frame:CreateTexture(nil, "BACKGROUND", nil, Sublevel(-8 + slot))
            local mask = frame:CreateMaskTexture()
            mask:SetTexture(Skin.ROUND_MASK,
                "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            part:AddMaskTexture(mask)
            part._mask = mask
            parts[slot] = part
        end

        local color = layer.color
        part:SetColorTexture(color[1], color[2], color[3], color[4] or 1)

        part:ClearAllPoints()
        part:SetPoint("TOPLEFT", frame, "TOPLEFT", -out, out)
        part:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", out, -out)
        part._mask:ClearAllPoints()
        part._mask:SetAllPoints(part)

        out = out - layer.thickness * scale
    end

    -- Anything left over from a longer border than this one.
    for index = slot + 1, #parts do
        parts[index]:Hide()
    end
    for index = 1, slot do parts[index]:Show() end

    Theme.TrackBorder(frame, RedrawRing)

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
    -- An atlas where the client has one, a plain texture where it does
    -- not: the Classic flavours are missing plenty of atlases the rest
    -- of the game takes for granted.
    if opts.atlas and BazUI.SetAtlasOrTexture then
        BazUI.SetAtlasOrTexture(icon, opts.atlas, opts.texture, false)
    elseif opts.atlas then
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

-- The X in the corner of a window.
--
-- Blizzard's UIPanelCloseButton is a perfectly good button and looks
-- like a perfectly good Blizzard button, which is the problem: ten
-- windows of ours wore it, and none of them matched the window it was
-- sitting on. Same treatment as the gear, and it hides its parent unless
-- told to do something else, since that is what the template did and
-- half the callers relied on it.
function Theme.CreateCloseButton(parent, opts)
    opts = opts or {}
    opts.atlas    = opts.atlas   or "common-icon-redx"
    opts.texture  = opts.texture or "Interface\\RAIDFRAME\\ReadyCheck-NotReady"
    opts.tooltip  = opts.tooltip or "Close"
    opts.size     = opts.size or 22
    opts.iconSize = opts.iconSize or 14
    opts.onClick  = opts.onClick or function() parent:Hide() end
    return Theme.CreateIconButton(parent, opts)
end

-- The same border, square.
--
-- One solid texture per band, each inset inside the last, and then
-- whatever the inside should be. No mask and no art, which is the whole
-- point - this is the status bar's border with the bar taken out, so
-- anything wearing it belongs to the same suite without anybody drawing
-- anything.
--
--   Theme.ApplyBorder(frame, { fill = Theme.colors.bg, scale = 1 })
--
-- Drawn inside the frame's own bounds, so what the frame measures is
-- what it covers, and the fill gets whatever the bands leave. A border
-- of no bands is a naked fill.
function Theme.ApplyBorder(frame, opts)
    opts = opts or {}
    local scale  = opts.scale or 1
    local layer  = opts.layer or "BACKGROUND"
    local base   = opts.sublevel or -8
    local layers = opts.layers or Theme.GetBorder()

    frame._bazBorder     = frame._bazBorder or {}
    frame._bazBorderOpts = opts
    local parts = frame._bazBorder

    -- Backwards, because band 1 is the innermost and each is drawn over
    -- the one outside it. The inset grows by a band's thickness once it
    -- has been drawn, so the next sits just inside it.
    local slot, inset = 0, 0
    for index = #layers, 1, -1 do
        local spec = layers[index]
        slot = slot + 1

        local texture = parts[slot]
        if not texture then
            texture = frame:CreateTexture(nil, layer, nil, Sublevel(base + slot - 1))
            parts[slot] = texture
        end
        local color = spec.color
        texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        texture:Show()

        inset = inset + spec.thickness * scale
    end

    for index = slot + 1, #parts do
        parts[index]:Hide()
    end

    local fill = opts.fill
    if fill then
        local texture = frame._bazBorderFill
        if not texture then
            texture = frame:CreateTexture(nil, layer, nil, Sublevel(base + 15))
            frame._bazBorderFill = texture
        end
        -- fillAlpha lets a caller pass one of the palette's own tables -
        -- which follows the skin, being the table everything else reads -
        -- and still say how see-through this one should be.
        texture:SetColorTexture(fill[1], fill[2], fill[3],
            opts.fillAlpha or fill[4] or 1)
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        texture:Show()
    elseif frame._bazBorderFill then
        frame._bazBorderFill:Hide()
    end

    Theme.TrackBorder(frame, RedrawBorder)

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
function Theme.CreateRoundRing(parent, opts)
    opts = opts or {}
    local layer = opts.layer or "BACKGROUND"
    local base  = opts.sublevel or -8

    -- A caller can hand over a border of its own rather than wear the
    -- suite's. Worth knowing if one does: the round mask blends over
    -- roughly a pixel at every edge, so a band only one pixel wide is
    -- nearly all blend, with its neighbours mixing in from both sides -
    -- the same color as on a square edge, and duller to look at. A second
    -- pixel gives it one at full strength.
    local fixedLayers = opts.layers

    -- A scale multiplies every band: the proportions are what make it
    -- look like our border, and a ring around something the size of the
    -- minimap wants them bigger rather than different.
    local scale = opts.scale or 1

    local ring = { parts = {} }

    local function Layers()
        return fixedLayers or Theme.GetBorder()
    end

    -- Made as they are needed rather than up front, because how many
    -- there are is a question about the skin, and the skin can change
    -- while this ring is on screen.
    local function Part(slot)
        local texture = ring.parts[slot]
        if texture then return texture end
        texture = parent:CreateTexture(nil, layer, nil, Sublevel(base + slot - 1))
        local mask = parent:CreateMaskTexture()
        mask:SetTexture(Skin.ROUND_MASK,
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        texture:AddMaskTexture(mask)
        texture._mask = mask
        ring.parts[slot] = texture
        return texture
    end

    function ring:Thickness()
        return Theme.BorderThickness(scale, Layers())
    end

    function ring:SetInnerSize(inner)
        local layers = Layers()
        self._inner = inner

        -- Outermost first: these are filled circles, so each has to be
        -- drawn before the one that covers its middle.
        local out = self:Thickness()
        local slot = 0
        for index = #layers, 1, -1 do
            local spec = layers[index]
            slot = slot + 1

            local texture = Part(slot)
            local color = spec.color
            texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)

            local diameter = inner + out * 2
            texture:ClearAllPoints()
            texture:SetPoint("CENTER", opts.anchor or parent, "CENTER", 0, 0)
            texture:SetSize(diameter, diameter)
            texture._mask:SetAllPoints(texture)
            texture:Show()

            out = out - spec.thickness * scale
        end

        -- Left over from a border with more bands than this one has.
        for index = slot + 1, #self.parts do self.parts[index]:Hide() end
        self._bands = slot

        -- Whichever band is the one worth lighting up, counted from the
        -- outside in, because that is the order they were drawn in.
        local accent = Theme.AccentBand(layers)
        self.gold = accent and self.parts[#layers - accent + 1] or nil
        if self._tint and self.gold then
            self.gold:SetVertexColor(unpack(self._tint))
        end

        Theme.TrackBorder(self, RedrawRoundRing)
    end

    -- Both kinds of ring answer the same two questions, so whatever holds
    -- one can hold the other: how big the hole comes out when the ring
    -- has to fit a footprint this wide, and how much room the ring wants
    -- around a hole of a given size.
    function ring:InnerFor(width)
        return math.max(1, width - self:Thickness() * 2)
    end

    function ring:Extent(inner)
        local outer = inner + self:Thickness() * 2
        return outer, outer
    end

    function ring:SetTint(r, g, b)
        self._tint = { r or 1, g or 1, b or 1 }
        if self.gold then self.gold:SetVertexColor(r or 1, g or 1, b or 1) end
    end

    function ring:Show()
        for index, texture in ipairs(self.parts) do
            -- Only the ones this border actually uses: the rest are
            -- leftovers from a longer one.
            if index <= (self._bands or #self.parts) then texture:Show() end
        end
    end

    function ring:Hide()
        for _, texture in ipairs(self.parts) do texture:Hide() end
    end

    return ring
end

---------------------------------------------------------------------------
-- A floating dialog
--
-- Popups, the copy box, the icon picker, the flyout grid. All of them
-- float over the game rather than sitting inside a panel, so they wear
-- the suite's full border rather than the one-pixel edge a row inside a
-- card gets: a dialog over the world needs the weight to read as a thing
-- in front of it.
--
--   Theme.ApplyDialog(frame)
--   Theme.ApplyDialog(frame, Theme.colors.bgRaised, 0.98)
---------------------------------------------------------------------------

function Theme.ApplyDialog(frame, bgColor, alpha)
    if frame.GetBackdrop and frame:GetBackdrop() then frame:SetBackdrop(nil) end

    -- A frame that wore the flat panel before this was called has its
    -- textures still on it, under ours.
    local flat = frame._bazFlatPanel
    if flat then
        flat.bg:Hide()
        for _, edge in ipairs(flat.edges) do edge:Hide() end
    end

    Theme.ApplyBorder(frame, {
        fill      = bgColor or Theme.colors.bg,
        fillAlpha = alpha or 0.97,
    })
    return frame
end

---------------------------------------------------------------------------
-- A dropdown menu
--
-- The game's menus come out of a pool the game also uses for its own, so
-- this is careful in two ways. Blizzard's backgrounds are hidden rather
-- than taken off, and the compositor shows them again when it hands that
-- frame to the next menu; and ours go on a child frame we own, hidden
-- again the moment the menu closes. A menu frame given back to the pool
-- comes out of it looking like the game's.
--
-- Only menus BazUI opened get this. Restyling the game's own dropdowns
-- is a different and much larger claim than making ours match.
---------------------------------------------------------------------------

-- The suite's face on a menu's words.
--
-- A menu's text belongs to its buttons, not to the menu, so the walk goes
-- down: the regions of this frame, then each child and its regions in
-- turn. Depth-capped because a menu with a submenu open is a tree, and an
-- unbounded walk over somebody else's frames is a good way to find a
-- cycle nobody knew was there.
--
-- Through the font object rather than the file. The menu compositor
-- forbids SetFont on the strings it owns, and it refuses on the key being
-- read rather than on the call - so even reaching for the function to
-- hand it to pcall is enough to raise. Every read below is inside the
-- pcall for that reason.
--
-- Mirroring the object the string is already using is what keeps its
-- size: the mirror copies size, flags, colour and justification from the
-- one it was made from, and changes only the face. A menu sets its sizes
-- deliberately and this leaves them alone.
local function ApplyMenuFont(frame, depth)
    if not (frame and frame.GetRegions) or depth > 4 then return end

    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            pcall(function()
                local base = region:GetFontObject()
                local name = base and base.GetName and base:GetName()
                local mirrored = name and Theme.FontObject(name)
                if mirrored then region:SetFontObject(mirrored) end
            end)
        end
    end

    if not frame.GetChildren then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        ApplyMenuFont(child, depth + 1)
    end
end

function Theme.ApplyMenuChrome(menu)
    -- Asked only about GetRegions. A menu frame's metatable raises on so
    -- much as reading CreateTexture, CreateFontString or CreateMaskTexture
    -- from it - the compositor blocks them so that callers go through its
    -- own AttachTexture - and a guard that throws is worse than no guard.
    if not (menu and menu.GetRegions) then return end

    -- The two the menu style attached: an atlas ring and a dark interior.
    -- Everything else a menu draws belongs to its buttons, which are
    -- frames of their own rather than regions of this one.
    for _, region in ipairs({ menu:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then
            region:Hide()
        end
    end

    local chrome = menu._bazMenuChrome
    if not chrome then
        chrome = CreateFrame("Frame", nil, menu)
        -- Out to where the game's own border reached, so the menu's
        -- contents keep the padding they were laid out with.
        chrome:SetPoint("TOPLEFT", -3, 3)
        chrome:SetPoint("BOTTOMRIGHT", 3, -3)
        chrome:EnableMouse(false)
        menu._bazMenuChrome = chrome

        menu:HookScript("OnHide", function(self)
            if self._bazMenuChrome then self._bazMenuChrome:Hide() end
        end)
    end

    chrome:SetFrameLevel(math.max(0, menu:GetFrameLevel() - 1))
    chrome:Show()
    Theme.ApplyDialog(chrome)

    -- After the menu has laid itself out, since that is when its buttons
    -- have their text. Re-done on every open rather than once, because a
    -- menu frame is reused and comes back with the game's font object on
    -- it again.
    ApplyMenuFont(menu, 0)

    return menu
end

---------------------------------------------------------------------------
-- A ring made of a picture
--
-- CreateRoundRing draws its border out of masked circles, which is the
-- right answer nearly everywhere: it is four pixels of the same border
-- the bars wear, it costs nothing, and it cannot go missing. It was never
-- the right answer for the minimap. At that size a border is just a thick
-- line, and the minimap is the one piece of chrome a player looks at all
-- day.
--
-- So the minimap gets artwork, and this wraps it in the same interface so
-- the widget does not care which kind of ring it is holding:
--
--   local ring = Theme.CreateArtRing(host, {
--       texture = Skin.MINIMAP_FRAME,
--       widthRatio = Skin.MINIMAP_FRAME_WIDTH,
--       heightRatio = Skin.MINIMAP_FRAME_HEIGHT,
--       overlap = 2,
--   })
--   local map = ring:InnerFor(footprintWidth)
--   ring:SetInnerSize(map)
--
-- The ratios are the picture's width and height measured against the hole
-- in the middle of it, so the art is positioned by what goes inside it
-- rather than by numbers pulled off a canvas. A frame whose decoration
-- runs past the circle - points, tags, anything - is taller or wider than
-- its hole, and says so in those two numbers; nothing here assumes the
-- picture is square.
---------------------------------------------------------------------------

function Theme.CreateArtRing(parent, opts)
    opts = opts or {}
    local widthRatio  = opts.widthRatio or 1
    local heightRatio = opts.heightRatio or widthRatio
    local overlap     = opts.overlap or 0

    local art = parent:CreateTexture(nil, opts.layer or "ARTWORK", nil,
        opts.sublevel or 0)
    art:SetTexture(opts.texture)

    local ring = { art = art, parts = { art } }

    -- The overlap is how far what sits inside is grown past the hole, so
    -- its edge slides under the band instead of meeting it: the picture's
    -- inner edge is antialiased, and two edges that merely touch leave a
    -- seam of half-lit pixels between them.
    function ring:InnerFor(width)
        return math.max(1, width / widthRatio + overlap * 2)
    end

    function ring:Extent(inner)
        local hole = math.max(1, inner - overlap * 2)
        return hole * widthRatio, hole * heightRatio
    end

    function ring:SetInnerSize(inner)
        local width, height = self:Extent(inner)
        art:ClearAllPoints()
        art:SetPoint("CENTER", opts.anchor or parent, "CENTER", 0, 0)
        art:SetSize(width, height)
    end

    function ring:SetTint(r, g, b)
        art:SetVertexColor(r or 1, g or 1, b or 1)
    end

    function ring:Show() art:Show() end
    function ring:Hide() art:Hide() end

    return ring
end

function Theme.ApplyRoundButton(button, icon, opts)
    opts = opts or {}
    local size  = opts.size or button:GetWidth()
    local inner = size * (opts.innerRatio or Skin.BUTTON_RING_INNER_RATIO) + (opts.overlap or 2) * 2

    if not button._bazRingObject then
        local disc = button:CreateTexture(nil, "BACKGROUND", nil, -1)
        SetColor(function(...) disc:SetColorTexture(...) end, Skin.BUTTON_BACKDROP_COLOR)
        local discMask = button:CreateMaskTexture()
        discMask:SetTexture(Skin.ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        disc:AddMaskTexture(discMask)

        local iconMask = button:CreateMaskTexture()
        iconMask:SetTexture(Skin.ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(iconMask)

        button._bazRingObject = Theme.CreateRoundRing(button, { sublevel = -6 })
        button._bazDisc, button._bazDiscMask, button._bazIconMask =
            disc, discMask, iconMask

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
    local chrome = tooltip._bazTooltipArtFrame
    if not chrome then
        -- The game updates and fades a tooltip's own regions as it fills
        -- it in, so our chrome lives in a child frame of its own. It
        -- inherits the tooltip's alpha and nothing the game does reaches
        -- it.
        chrome = CreateFrame("Frame", nil, tooltip)
        chrome:SetAllPoints(tooltip)
        chrome:EnableMouse(false)
        tooltip._bazTooltipArtFrame = chrome
    end

    chrome:SetFrameLevel(math.max(0, tooltip:GetFrameLevel() - 1))
    chrome:Show()

    -- The suite's border, the same one a bar or a panel wears, rather
    -- than an edge of its own. A tooltip drawn some other way is the one
    -- thing on screen that does not follow the skin.
    --
    -- The palette's own table goes in rather than a copy of its numbers,
    -- so a color change reaches it; the opacity is passed beside it,
    -- since how see-through a tooltip is belongs to the tooltip rather
    -- than to the palette.
    Theme.ApplyBorder(chrome, {
        fill      = Theme.colors.bg,
        fillAlpha = opacity or 0.96,
    })
end
