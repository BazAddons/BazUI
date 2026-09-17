-- SPDX-License-Identifier: GPL-2.0-or-later
local ADDON_NAME = ...
---------------------------------------------------------------------------
-- BazUI Skin: skins
--
-- Almost nothing in this addon is a picture. Panels, bars, borders, rings
-- and plates are all drawn from a white texture tinted by the handful of
-- colors in Theme.colors, which means the look of the whole suite is a
-- table of numbers rather than a folder of art. A table of numbers is
-- something somebody else can write.
--
-- A skin is that table with a name on it, plus - for anyone who does have
-- art - a face and the two or three textures that are pictures. This file
-- is the register of them, BazUI's own among the rest, and the one call
-- that puts one on.
--
-- Two rules make swapping one work at all:
--
--  * Colors are written into the existing tables, never swapped for new
--    ones. Twenty files took a reference to Theme.colors.gold when they
--    loaded and kept it; handing out a different table would leave every
--    one of them painting in the old color for ever.
--  * A skin goes on before the modules build, at ADDON_LOADED. Anything
--    already drawn has its color baked into a texture it is holding, so
--    changing skins later needs a reload to be sure of everything - which
--    is what the Skin tab offers.
--
-- Another addon adds a skin with:
--
--     BazUI.Skin:RegisterSkin{
--         id     = "myskin",
--         name   = "My Skin",
--         author = "Someone",
--         desc   = "One line about it.",
--         colors = { gold = { 0.80, 0.90, 1.00, 1 } },
--         font   = "Interface\\AddOns\\MySkin\\Face.ttf",
--         textures = {
--             minimapFrame       = "Interface\\AddOns\\MySkin\\Ring",
--             minimapFrameWidth  = 929 / 756,
--             minimapFrameHeight = 1088 / 756,
--         },
--     }
--
-- Everything but id and name is optional: what a skin leaves out it takes
-- from BazUI's own, so a skin that only wants to change the gold says only
-- that. It has to be registered before ADDON_LOADED, which for another
-- addon means at file scope. Registering later than that still works -
-- a skin that arrives after BazUI has dressed itself, and is the one
-- chosen, goes on as it registers.
---------------------------------------------------------------------------

local Skin  = BazUI.Skin
local Theme = Skin.Theme

---------------------------------------------------------------------------
-- The palette, in words
--
-- What each color is for, in the order the editor shows them. This drives
-- the Skin tab only: applying a skin walks the theme itself, so a color
-- added to Theme.colors is skinnable the moment it exists, labelled here
-- or not.
---------------------------------------------------------------------------

Skin.COLOR_GROUPS = {
    { key = "metal",    label = "Metal",    desc = "The gold edge the suite is built in: headings, borders and rules." },
    { key = "surface",  label = "Surfaces", desc = "What panels, cards and rows are filled with." },
    { key = "text",     label = "Text" },
    { key = "reading",  label = "Readings", desc = "Colors that mean something. Green is finished, amber is running out - everywhere in the addon, so they are worth keeping apart." },
    { key = "rank",     label = "Unit ranks", desc = "The glow around a unit bar saying what rank the unit is. Off item quality, so blue reads rare and red reads boss without anyone having to learn it." },
    { key = "other",    label = "Other" },
}

Skin.COLOR_ROLES = {
    { key = "gold",      group = "metal",   label = "Gold",           desc = "Headings, the selected tab, the numbers that matter." },
    { key = "goldSoft",  group = "metal",   label = "Soft gold",      desc = "Names and labels sitting on artwork." },
    { key = "goldDim",   group = "metal",   label = "Dim gold",       desc = "The edge around a panel." },
    { key = "divider",   group = "metal",   label = "Divider",        desc = "The rule under a heading." },
    { key = "edge",      group = "metal",   label = "Inner edge",     desc = "One-pixel borders inside a panel." },

    { key = "bg",        group = "surface", label = "Panel",          desc = "Panel and toast interiors. The alpha here is what makes the suite see-through.", hasAlpha = true },
    { key = "bgRaised",  group = "surface", label = "Card",           desc = "Cards and rows sitting on a panel.", hasAlpha = true },
    { key = "bgHover",   group = "surface", label = "Hovered",        desc = "A row under the mouse.", hasAlpha = true },

    { key = "text",      group = "text",    label = "Text" },
    { key = "textSoft",  group = "text",    label = "Secondary text" },
    { key = "textMuted", group = "text",    label = "Muted text",     desc = "Timestamps, hints, anything you read second." },

    { key = "success",   group = "reading", label = "Done",           desc = "Finished, earned, collected." },
    { key = "caution",   group = "reading", label = "Closing",        desc = "A window running out." },
    { key = "warn",      group = "reading", label = "Warning" },
    { key = "danger",    group = "reading", label = "Danger" },

    { key = "rankRare",      group = "rank", label = "Rare",       hasAlpha = true },
    { key = "rankElite",     group = "rank", label = "Elite",      hasAlpha = true },
    { key = "rankRareElite", group = "rank", label = "Rare elite", hasAlpha = true },
    { key = "rankBoss",      group = "rank", label = "Boss",       hasAlpha = true },
}

---------------------------------------------------------------------------
-- Reading a color safely
--
-- A skin can arrive from a paste box, so nothing coming in is trusted:
-- anything that is not a number between nought and one is not a color.
---------------------------------------------------------------------------

local function Channel(value, fallback)
    value = tonumber(value)
    if not value then return fallback end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

-- Accepts either of the two shapes a color comes in: ours, { r, g, b, a },
-- and the game's own { r = , g = , b = }.
local function SanitizeColor(color, fallback)
    if type(color) ~= "table" then return nil end
    fallback = fallback or { 1, 1, 1, 1 }
    local r = color[1]; if r == nil then r = color.r end
    local g = color[2]; if g == nil then g = color.g end
    local b = color[3]; if b == nil then b = color.b end
    local a = color[4]; if a == nil then a = color.a end
    return {
        Channel(r, fallback[1]),
        Channel(g, fallback[2]),
        Channel(b, fallback[3]),
        Channel(a, fallback[4] or 1),
    }
end

local function CopyPalette(source)
    local out = {}
    for role, color in pairs(source or {}) do
        local clean = SanitizeColor(color)
        if clean then out[role] = clean end
    end
    return out
end

-- A border is a list of bands, running inside out. Same treatment as a
-- palette: nothing that arrives is trusted, and a band without a color or
-- without a thickness is not a band.
local function CopyBorder(source)
    local out = {}
    for _, band in ipairs(type(source) == "table" and source or {}) do
        local color = SanitizeColor(band.color)
        local thickness = math.floor(tonumber(band.thickness) or 0)
        if color and thickness > 0 then
            out[#out + 1] = {
                thickness = math.min(thickness, 32),
                color     = color,
                accent    = band.accent and true or nil,
            }
        end
    end
    return out
end

Skin.SanitizeColor = SanitizeColor

---------------------------------------------------------------------------
-- BazUI's own
--
-- Taken off the theme as it stands rather than written out again here.
-- The numbers live in one place, and "BazUI" is by definition whatever
-- Theme.lua and Skin.lua say before anybody changes anything.
---------------------------------------------------------------------------

local BUILT_IN = {
    id     = "bazui",
    name   = "BazUI",
    author = "Baz4k",
    desc   = "The suite's own look: warm dark panels behind a gold edge.",
    colors = CopyPalette(Theme.colors),
    border = CopyBorder(Theme.border),
    fill   = Skin.DEFAULT_FILL,
    font   = Theme.FONT_FILE,
    textures = {
        minimapFrame       = Skin.MINIMAP_FRAME,
        minimapFrameWidth  = Skin.MINIMAP_FRAME_WIDTH,
        minimapFrameHeight = Skin.MINIMAP_FRAME_HEIGHT,
    },
}

---------------------------------------------------------------------------
-- The register
---------------------------------------------------------------------------

local skins, order = {}, {}

-- Whether the choice saved has been read and put on yet. Until it has,
-- registering a skin is only registering it.
local applied = false

function Skin:RegisterSkin(def)
    if type(def) ~= "table" then return nil end
    local id = def.id
    if type(id) ~= "string" or id == "" then return nil end

    local skin = {
        id       = id,
        name     = tostring(def.name or id),
        author   = def.author and tostring(def.author) or nil,
        desc     = def.desc and tostring(def.desc) or nil,
        colors   = CopyPalette(def.colors),
        -- No border at all is a real answer - a naked fill - so a skin
        -- has to leave the key out to mean "BazUI's", not hand over an
        -- empty list.
        border   = def.border ~= nil and CopyBorder(def.border) or nil,
        -- The name of a fill rather than a texture path: a skin wanting
        -- one of its own registers it and names that. See Skin/Fills.lua.
        fill     = type(def.fill) == "string" and def.fill or nil,
        font     = type(def.font) == "string" and def.font or nil,
        textures = type(def.textures) == "table" and def.textures or nil,
        builtIn  = def.builtIn and true or false,
    }

    if not skins[id] then order[#order + 1] = id end
    skins[id] = skin

    -- Registered after we went looking for it. Another addon's files load
    -- after ours, so its skin arrives after the one saved was asked for
    -- and came back missing; if this is that one, put it on now rather
    -- than leaving somebody in the fallback until they reload.
    if applied and BazUIDB and BazUIDB.skin and BazUIDB.skin.active == id then
        Skin.ApplySkin(id)
    end

    return id
end

function Skin.GetSkin(id)
    return id and skins[id] or nil
end

-- Every registered skin, BazUI's first and the rest in the order they
-- registered, so a list built from this reads the same twice running.
function Skin.GetSkins()
    local list = {}
    for _, id in ipairs(order) do
        list[#list + 1] = skins[id]
    end
    return list
end

Skin:RegisterSkin(BUILT_IN)
skins[BUILT_IN.id].builtIn = true

---------------------------------------------------------------------------
-- Where the choice is kept
--
-- Beside the font switch, in BazUIDB rather than in a profile. A skin is
-- what the addon looks like to you, not what this character's bars are
-- arranged like, and putting it in a profile would mean a profile switch
-- silently repainting half the screen and needing a reload to finish.
---------------------------------------------------------------------------

local CUSTOM_ID = "custom"

local function Store()
    BazUIDB = BazUIDB or {}
    BazUIDB.skin = BazUIDB.skin or {}
    return BazUIDB.skin
end

function Skin.ActiveSkin()
    return Skin.activeSkin or "bazui"
end

---------------------------------------------------------------------------
-- Putting one on
---------------------------------------------------------------------------

function Skin.ApplySkin(id)
    local skin = Skin.GetSkin(id) or skins[BUILT_IN.id]
    local base = BUILT_IN.colors

    -- Every color the theme has, not only the ones with a label: the
    -- theme is the list, and a skin that says nothing about a role gets
    -- BazUI's.
    for role, live in pairs(Theme.colors) do
        if type(live) == "table" then
            local want = SanitizeColor(skin.colors and skin.colors[role], base[role])
                or base[role] or live
            live[1], live[2], live[3], live[4] = want[1], want[2], want[3], want[4] or 1
        end
    end

    -- Bands are drawn rather than read as they go, so this repaints
    -- every edge already on screen as well as setting the recipe - which
    -- picks up the new palette on the same pass.
    Theme.SetBorder(skin.border or BUILT_IN.border)
    Skin.ApplyFill(skin.fill or BUILT_IN.fill)

    if Theme.SetFontFile then
        Theme.SetFontFile(skin.font or BUILT_IN.font)
    end

    local art  = skin.textures or {}
    local stock = BUILT_IN.textures
    Skin.MINIMAP_FRAME        = art.minimapFrame or stock.minimapFrame
    Skin.MINIMAP_FRAME_WIDTH  = tonumber(art.minimapFrameWidth) or stock.minimapFrameWidth
    Skin.MINIMAP_FRAME_HEIGHT = tonumber(art.minimapFrameHeight) or stock.minimapFrameHeight

    Skin.activeSkin = skin.id
    Store().active = skin.id

    return skin
end

---------------------------------------------------------------------------
-- The one anybody can edit
--
-- Changing a color puts you on the custom skin, taking a copy of whatever
-- you were wearing as its starting point. A shipped skin is never edited
-- out from under its author, and going back to it is picking it again
-- rather than undoing fifteen changes.
---------------------------------------------------------------------------

local function RegisterCustom()
    local store = Store()
    store.custom = store.custom or {}
    store.custom.colors = CopyPalette(store.custom.colors)

    Skin:RegisterSkin({
        id     = CUSTOM_ID,
        name   = store.custom.name or "Custom",
        author = store.custom.author,
        desc   = "Yours. Changing anything below puts you on this one.",
        colors = store.custom.colors,
        border = store.custom.border,
        fill   = store.custom.fill,
        font   = store.custom.font,
        textures = store.custom.textures,
    })

    -- Registering copies the palette, and the copy is the one the editor
    -- has to write into for a change to survive a reload. Point both at
    -- the saved table.
    local skin = skins[CUSTOM_ID]
    store.custom.colors = skin.colors
    store.custom.border = skin.border
    return skin
end

function Skin.IsCustom(id)
    return (id or Skin.ActiveSkin()) == CUSTOM_ID
end

-- The color a role is wearing right now: the live theme table, which is
-- what everything else in the addon is painting from.
function Skin.RoleColor(role)
    return Theme.colors[role]
end

-- Fork what is on now into the custom skin, without applying anything: the
-- colors are already on screen, that is where they came from.
local function ForkIntoCustom()
    local custom = skins[CUSTOM_ID] or RegisterCustom()
    if Skin.ActiveSkin() == CUSTOM_ID then return custom, false end

    local from = Skin.GetSkin(Skin.ActiveSkin()) or skins[BUILT_IN.id]
    wipe(custom.colors)
    for role, color in pairs(CopyPalette(Theme.colors)) do
        custom.colors[role] = color
    end
    custom.border   = CopyBorder(Theme.border)
    custom.fill     = Skin.ActiveFill()
    custom.font     = from.font
    custom.textures = from.textures

    local store = Store()
    store.custom.border   = custom.border
    store.custom.fill     = custom.fill
    store.custom.font     = from.font ~= BUILT_IN.font and from.font or nil
    store.custom.textures = from.textures ~= BUILT_IN.textures and from.textures or nil

    Skin.activeSkin = CUSTOM_ID
    store.active    = CUSTOM_ID
    return custom, true
end

-- One color changed. Written into the theme as well as into the skin, so
-- anything that reads its color as it draws is already right and only what
-- is already on screen needs the reload.
-- Answers whether this was the change that moved you onto the custom
-- skin, which is the moment anything naming the skin is out of date.
function Skin.SetColor(role, r, g, b, a)
    if not Theme.colors[role] then return false end
    local custom, forked = ForkIntoCustom()
    local clean = SanitizeColor({ r, g, b, a }, Theme.colors[role])
    custom.colors[role] = clean

    local live = Theme.colors[role]
    live[1], live[2], live[3], live[4] = clean[1], clean[2], clean[3], clean[4]

    -- Anything that painted a color onto a texture is holding a copy of
    -- the old numbers. The things that can be drawn again say so, so draw
    -- them again: a tooltip's interior and a panel's fill follow at once
    -- instead of waiting for a reload.
    Theme.RefreshBorders()
    if Theme.RefreshGlows then Theme.RefreshGlows() end
    return forked
end


---------------------------------------------------------------------------
-- Editing the border
--
-- The list runs inside out: band 1 is the one touching the fill, and each
-- one after it sits outside the last. Removing them all is a real answer -
-- a naked fill with no edge at all - so nothing here puts a floor under
-- it.
--
-- Every one of these forks into the custom skin the same way a color
-- does, and every one ends by handing the list to the theme, which
-- sanitizes it and redraws everything already wearing a border. No reload.
---------------------------------------------------------------------------

-- A custom skin with no border of its own is wearing the one it forked
-- from. Take a copy of what is on screen before changing it, or the first
-- edit would throw the other bands away.
local function CustomBorder(custom)
    if not custom.border then
        custom.border = CopyBorder(Theme.border)
        Store().custom.border = custom.border
    end
    return custom.border
end

local function CommitBorder(custom)
    -- The theme hands back the list it actually kept, so the skin and
    -- what is on screen cannot drift apart.
    custom.border = Theme.SetBorder(custom.border)
    Store().custom.border = custom.border
    return custom.border
end

-- The border as it stands, for anything showing it.
function Skin.GetBands()
    return Theme.GetBorder()
end

function Skin.SetBandColor(index, r, g, b, a)
    local custom, forked = ForkIntoCustom()
    local band = CustomBorder(custom)[index]
    if not band then return forked end
    band.color = SanitizeColor({ r, g, b, a }, band.color)
    CommitBorder(custom)
    return forked
end

function Skin.SetBandThickness(index, pixels)
    local custom, forked = ForkIntoCustom()
    local band = CustomBorder(custom)[index]
    if not band then return forked end
    band.thickness = math.max(1, math.min(32, math.floor(tonumber(pixels) or 1)))
    CommitBorder(custom)
    return forked
end

-- A new band goes on the outside, which is where somebody adding one is
-- looking. It starts as a copy of the outermost band there is, so it
-- appears as a wider version of what was already there rather than as a
-- white stripe.
function Skin.AddBand()
    local custom, forked = ForkIntoCustom()
    local border = CustomBorder(custom)
    if #border >= (Theme.MAX_BORDER_BANDS or 12) then return forked end

    local outer = border[#border]
    border[#border + 1] = {
        thickness = outer and outer.thickness or 1,
        color     = SanitizeColor(outer and outer.color) or { 0, 0, 0, 0.75 },
    }
    CommitBorder(custom)
    return forked
end

function Skin.RemoveBand(index)
    local custom, forked = ForkIntoCustom()
    local border = CustomBorder(custom)
    if not border[index] then return forked end
    table.remove(border, index)
    CommitBorder(custom)
    return forked
end

-- What a bar is filled with. Like a color, this forks into the custom
-- skin: picking one is a change to how the addon looks, not a setting
-- that sits beside it.
function Skin.SetFill(id)
    local custom, forked = ForkIntoCustom()
    custom.fill = Skin.ApplyFill(id)
    Store().custom.fill = custom.fill
    return forked
end

-- Back to the shipped palette, border and fill, on whichever skin is on.
function Skin.ResetColors()
    if Skin.ActiveSkin() == CUSTOM_ID then
        wipe(skins[CUSTOM_ID].colors)
        skins[CUSTOM_ID].border = nil
        skins[CUSTOM_ID].fill = nil
        Store().custom.border = nil
        Store().custom.fill = nil
    end
    return Skin.ApplySkin(Skin.ActiveSkin())
end

---------------------------------------------------------------------------
-- Sharing one
--
-- The same encoded string the rest of the suite trades bars and profiles
-- in. What travels is the palette, the name and who made it - not the
-- texture paths, which point into a folder the other person has no reason
-- to have. A skin with art travels as an addon.
---------------------------------------------------------------------------

function Skin.Export(id)
    local skin = Skin.GetSkin(id or Skin.ActiveSkin())
    if not skin then return nil end

    local palette = {}
    for role, live in pairs(Theme.colors) do
        if type(live) == "table" then
            palette[role] = { live[1], live[2], live[3], live[4] or 1 }
        end
    end

    return BazUI:Serialize({
        bazuiSkin = 1,
        name      = skin.name,
        author    = skin.author,
        colors    = palette,
        border    = CopyBorder(Theme.border),
        fill      = Skin.ActiveFill(),
    })
end

function Skin.Import(encoded)
    if type(encoded) ~= "string" or encoded:trim() == "" then
        return false, "Nothing to import."
    end

    local data = BazUI:Deserialize(encoded:trim())
    if type(data) ~= "table" or type(data.colors) ~= "table" then
        return false, "That is not a skin string."
    end

    local palette = CopyPalette(data.colors)
    if not next(palette) then
        return false, "That string has no colors in it."
    end

    local store = Store()
    store.custom = store.custom or {}
    store.custom.name   = type(data.name) == "string" and data.name or "Custom"
    store.custom.author = type(data.author) == "string" and data.author or nil

    local custom = skins[CUSTOM_ID] or RegisterCustom()
    custom.name   = store.custom.name
    custom.author = store.custom.author
    wipe(custom.colors)
    for role, color in pairs(palette) do custom.colors[role] = color end

    -- An older string, from before borders travelled, has no border key
    -- at all. That is not the same as one that means "no border", so it
    -- keeps the one already on.
    if data.border ~= nil then
        custom.border = CopyBorder(data.border)
        store.custom.border = custom.border
    end

    -- A fill naming a shared-media texture the receiver does not have
    -- falls back on its own when it is drawn, so it is taken as given.
    if type(data.fill) == "string" then
        custom.fill = data.fill
        store.custom.fill = data.fill
    end

    Skin.ApplySkin(CUSTOM_ID)
    return true, custom.name
end

---------------------------------------------------------------------------
-- On, before anything is drawn
--
-- ADDON_LOADED rather than login: saved variables are ready and no module
-- has built a frame yet, so the first thing drawn is drawn in the right
-- colors. This file loads before every module, so this callback is queued
-- before theirs and runs before theirs.
---------------------------------------------------------------------------

if EventUtil and EventUtil.ContinueOnAddOnLoaded then
    EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
        RegisterCustom()
        Skin.ApplySkin(Store().active or BUILT_IN.id)
        applied = true
    end)
end

BazUI:RegisterDependency({
    module = "Skin",
    label  = "ColorPickerFrame:SetupColorPickerAndShow",
    why    = "Picking a color on the Skin tab.",
    check  = function()
        return BazUI.Has.Member(_G.ColorPickerFrame, "SetupColorPickerAndShow")
    end,
})
