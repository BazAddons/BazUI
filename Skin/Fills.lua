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

local fills, order = {}, {}

function Skin.RegisterFill(def)
    if type(def) ~= "table" then return nil end
    local id = def.id
    if type(id) ~= "string" or id == "" then return nil end

    if not fills[id] then order[#order + 1] = id end
    fills[id] = {
        id       = id,
        name     = tostring(def.name or id),
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

Skin.RegisterFill({ id = "gloss", name = "Gloss",
    texture = "Interface\\TargetingFrame\\UI-StatusBar" })

Skin.RegisterFill({ id = "smooth", name = "Smooth",
    texture = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" })

Skin.RegisterFill({ id = "resource", name = "Resource",
    texture = "Interface\\RaidFrame\\Raid-Bar-Resource-Fill" })

Skin.RegisterFill({ id = "gradient", name = "Gradient",
    texture = WHITE, gradient = true, sheen = false })

Skin.RegisterFill({ id = "flat", name = "Flat",
    texture = WHITE, sheen = false })

Skin.DEFAULT_FILL = "gloss"

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
    Skin.XP_FILL = Skin.FillDef().texture
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
