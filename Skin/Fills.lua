-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Skin: bar fills
--
-- What the inside of a bar is drawn with. Every bar in the suite - health,
-- power, casting, experience, reputation, the readings in a panel - takes
-- its fill from here, so this is one choice rather than one per module.
--
-- A fill is a texture and two things about how to use it:
--
--   texture   the picture stretched along the bar. The game ships a
--             handful, and a flat one-pixel white is a real answer too.
--   atlas     the same thing named rather than pathed. Most of the art
--             added since the Dragonflight interface lives in the
--             client's atlas sheets and has no file of its own, which is
--             where the HUD bar shading comes from: there is no path to
--             point at, only a name.
--   gradient  work the color up and down the bar rather than painting it
--             evenly, which gives a lit bar out of a flat texture and no
--             art at all.
--   sheen     the single lit pixel along the top edge. Right on a glossy
--             fill, wrong on a deliberately flat one.
--
-- Only the game's own textures are shipped, because a texture we shipped
-- would be a file to download for something the client already has. If
-- somebody has LibSharedMedia - and a great many people do, since half
-- the addons out there register with it - every bar texture it knows
-- about turns up in the list as well.
--
-- Another addon adds one with:
--
--     BazUI.Skin.RegisterFill{
--         id = "myfill", name = "My Fill",
--         texture = "Interface\\AddOns\\MySkin\\Bar",
--     }
---------------------------------------------------------------------------

local Skin = BazUI.Skin

local WHITE = "Interface\\Buttons\\WHITE8x8"

-- The game's ordinary bar texture. Used three times over: it is the
-- Gloss fill, it is what an atlas fill wears on a client that has no
-- such atlas, and it is the plain path handed to anything that asks
-- for a bar texture without going through the fill system.
local PLAIN = "Interface\\TargetingFrame\\UI-StatusBar"

local fills, order = {}, {}

function Skin.RegisterFill(def)
    if type(def) ~= "table" then return nil end
    local id = def.id
    if type(id) ~= "string" or id == "" then return nil end

    if not fills[id] then order[#order + 1] = id end
    fills[id] = {
        id       = id,
        name     = tostring(def.name or id),
        atlas    = type(def.atlas) == "string" and def.atlas or nil,
        -- How much to lift the color a bar is tinted with, for artwork
        -- that is not white to begin with. A status bar's color
        -- multiplies whatever is under it, so art whose body sits at
        -- three quarters brightness turns every color into three
        -- quarters of itself. Absent means the art is white and the
        -- color arrives intact.
        boost    = tonumber(def.boost) or nil,
        -- Still a texture even when there is an atlas, because the bar is
        -- given one before the atlas is applied over it and a nil there
        -- draws the green-and-black missing grid for a frame.
        texture  = type(def.texture) == "string" and def.texture or WHITE,
        gradient = def.gradient and true or false,
        -- Absent means yes: a fill that says nothing about the sheen gets
        -- the suite's.
        sheen    = def.sheen ~= false,
    }
    return id
end

---------------------------------------------------------------------------
-- The ones the game already has
--
-- Every path here was read off the client's own interface code rather
-- than remembered, because a texture that is not there draws as a green
-- and black grid and says nothing about why.
---------------------------------------------------------------------------

Skin.RegisterFill({ id = "gloss", name = "Gloss", texture = PLAIN })

Skin.RegisterFill({ id = "smooth", name = "Smooth",
    texture = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" })

Skin.RegisterFill({ id = "resource", name = "Resource",
    texture = "Interface\\RaidFrame\\Raid-Bar-Resource-Fill" })

Skin.RegisterFill({ id = "gradient", name = "Gradient",
    texture = WHITE, gradient = true, sheen = false })

Skin.RegisterFill({ id = "flat", name = "Flat",
    texture = WHITE, sheen = false })

---------------------------------------------------------------------------
-- The game's own HUD bars
--
-- What the player frame draws itself with, taken as a texture the suite
-- colors rather than as finished artwork.
--
-- Named, not pathed - these live in the client's atlas sheets and have no
-- file to point at. Nothing is shipped either way; the client already has
-- them.
--
-- The first attempt took the finished art: the green health bar and the
-- blue mana bar, one fill each, untinted. That looked right for anything
-- that happened to be green and wrong for everything else, because a
-- status bar's color multiplies what is under it and a blue bar over
-- green art is very nearly black.
--
-- The answer was already in the client. Every one of these bars has a
-- "-Status" cut of the same artwork - same shape, same soft edges, no
-- color - which Blizzard use underneath for heal prediction and absorbs.
-- Taking that one and coloring it ourselves means every color works, and
-- a health bar keeps its class color instead of being forced to green.
--
-- The body of that art sits at 188 of 255, so a color put through it
-- arrives at about three quarters strength. BOOST lifts it back; it is
-- measured off the texture rather than guessed.
--
-- No sheen and no gradient: the art has its own soft top and bottom
-- edges, and the suite's highlight on top of those makes a bar look wet.
--
-- What is deliberately not taken is the mask that goes with them.
-- Blizzard's health bar is 124 by 20 with a notch cut for the portrait,
-- and the mask is drawn at its own size to suit. On a bar of ours - any
-- width, no portrait - it would either cover a third of it or have to be
-- stretched, and stretching a rounded end is how you get an oval. The
-- technique is there if we ever want shaped ends, but it needs a mask cut
-- for our shape rather than theirs.
---------------------------------------------------------------------------

-- 255 / 188, the brightness of the artwork's body.
local HUD_BOOST = 1.36

Skin.RegisterFill({ id = "hud", name = "HUD",
    atlas   = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Status",
    texture = PLAIN, boost = HUD_BOOST, sheen = false })

-- The party frames' flatter cut of the same thing: shorter, no notch at
-- the end, which suits a thin bar better.
Skin.RegisterFill({ id = "hudparty", name = "HUD Party",
    atlas   = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Status",
    texture = PLAIN, boost = HUD_BOOST, sheen = false })

-- The one a fresh profile wears. The game's own bar art, colored by us:
-- it is what the player frame looks like, so the suite looks like part
-- of the game rather than something bolted to it. A client without
-- that atlas falls back to PLAIN, which is what this used to be.
Skin.DEFAULT_FILL = "hud"

---------------------------------------------------------------------------
-- Whatever else is installed
--
-- LibSharedMedia is where addons put fonts, sounds and bar textures for
-- each other to use. Read only, and only if it is there: nothing is
-- registered into it and nothing breaks without it. Asked each time
-- rather than once, because an addon loading later adds to it.
---------------------------------------------------------------------------

local LSM_PREFIX = "lsm:"

local function SharedMedia()
    if not LibStub then return nil end
    local lsm = LibStub("LibSharedMedia-3.0", true)
    if not (lsm and lsm.List and lsm.Fetch) then return nil end
    return lsm
end

local function SharedMediaFills()
    local lsm = SharedMedia()
    if not lsm then return {} end

    local list = {}
    local ok, names = pcall(lsm.List, lsm, "statusbar")
    if not (ok and type(names) == "table") then return {} end

    for _, name in ipairs(names) do
        local fetched = select(2, pcall(lsm.Fetch, lsm, "statusbar", name))
        if type(fetched) == "string" then
            list[#list + 1] = {
                id      = LSM_PREFIX .. name,
                name    = name,
                texture = fetched,
                sheen   = true,
            }
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Reading them back
---------------------------------------------------------------------------

-- Ours first, in the order they were registered, then anything shared.
-- Built fresh each time so a list shown twice is up to date the second
-- time.
function Skin.GetFills()
    local list = {}
    for _, id in ipairs(order) do
        list[#list + 1] = fills[id]
    end

    local shared = SharedMediaFills()
    table.sort(shared, function(a, b) return a.name < b.name end)
    for _, def in ipairs(shared) do
        -- One of ours by the same name wins: it is the one somebody
        -- picked from this list before.
        if not fills[def.id] then list[#list + 1] = def end
    end

    return list
end

function Skin.ActiveFill()
    return Skin.activeFill or Skin.DEFAULT_FILL
end

-- What to actually draw with. Always answers something drawable: a fill
-- that has gone away - a shared-media texture from an addon since
-- uninstalled - falls back to the suite's own rather than to nothing.
function Skin.FillDef(id)
    id = id or Skin.ActiveFill()

    local def = fills[id]
    if not def and id and id:sub(1, #LSM_PREFIX) == LSM_PREFIX then
        local lsm = SharedMedia()
        local name = id:sub(#LSM_PREFIX + 1)
        local ok, texture = pcall(function() return lsm and lsm:Fetch("statusbar", name, true) end)
        if ok and type(texture) == "string" then
            def = { id = id, name = name, texture = texture, gradient = false, sheen = true }
        end
    end

    return def or fills[Skin.DEFAULT_FILL]
end

-- Set by the skin rather than called directly; the Skin tab goes through
-- Skin.SetFill, which forks into the custom skin first.
function Skin.ApplyFill(id)
    Skin.activeFill = Skin.FillDef(id).id

    -- XP_FILL is the one path-only channel left: a plain texture path for
    -- anything that wants a bar texture without going through the fill
    -- system. An atlas fill has no path of its own, so that consumer
    -- gets the ordinary bar texture rather than a blank square - and it
    -- is named here rather than read off the default fill, because the
    -- default is an atlas fill itself now.
    local def = Skin.FillDef()
    Skin.XP_FILL = (not def.atlas and def.texture) or PLAIN
    if Skin.Theme and Skin.Theme.RefreshFills then Skin.Theme.RefreshFills() end
    return Skin.activeFill
end

BazUI:RegisterDependency({
    module = "Skin",
    label  = "Texture:SetGradient",
    why    = "Working a bar's color up and down it, for the Gradient fill.",
    check  = function()
        local probe = UIParent:CreateTexture()
        local has = probe.SetGradient ~= nil
        probe:SetTexture(nil)
        return has
    end,
})
