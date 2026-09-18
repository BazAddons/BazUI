-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: what colour a unit is
--
-- One answer, because two would drift. A health bar and a name plate are
-- looking at the same unit and should agree about it; they only ask a
-- different question at the edges. A bar watching somebody's health
-- paints an NPC green whatever it thinks of you, while a plate floating
-- over that NPC's head is mostly there to say whether it will attack.
--
--   BazUI.UnitColor(unit, { classColor = true })                -- a bar
--   BazUI.UnitColor(unit, { classColor = true, reaction = true })-- a plate
--
-- Offline and dead come first either way, since neither is worth
-- painting as though it were a living unit's current health.
---------------------------------------------------------------------------

BazUI.UNIT_COLORS = {
    offline  = { 0.35, 0.35, 0.40, 1 },
    dead     = { 0.45, 0.45, 0.45, 1 },
    alive    = { 0.10, 0.80, 0.15, 1 },

    -- Reaction, for a plate. The game hands out eight of these and they
    -- collapse to three things worth telling apart: it will attack you,
    -- it will not, and it has not decided yet.
    hostile  = { 0.78, 0.25, 0.25, 1 },
    neutral  = { 0.85, 0.72, 0.25, 1 },
    friendly = { 0.30, 0.65, 0.35, 1 },
}

function BazUI.UnitColor(unit, opts)
    local C = BazUI.UNIT_COLORS
    if not unit then return C.alive end
    opts = opts or {}

    if UnitIsConnected and not UnitIsConnected(unit) then return C.offline end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return C.dead end

    -- UnitClass is SecretWhenUnitIdentityRestricted, and identity comes and
    -- goes: the same unit answers plainly one moment and with a value we
    -- are not allowed to read the next. Indexing RAID_CLASS_COLORS with one
    -- of those yields a colour whose parts are secret too, and a bar
    -- painted with it comes out black - which is what made health and power
    -- bars flick to black and back for no visible reason.
    --
    -- Two ways to the same colour, and the first is the one we want.
    -- RAID_CLASS_COLORS gives ordinary numbers, which a gradient can shade,
    -- so the bar keeps its lit top edge.
    --
    -- Where identity is not ours to have, that lookup raises and
    -- GetClassColor answers instead: it is one of the few the client lets a
    -- tainted caller hand a secret to, and what it returns is something a
    -- status bar will still accept. Flat rather than shaded, and right -
    -- which beats the green we used to fall back to, since the unit is not
    -- a stranger, only one we are not allowed to name.
    if opts.classColor and UnitIsPlayer(unit) then
        local class = select(2, UnitClass(unit))

        local plain = BazUI.Secret.Read(function()
            local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if not c then return nil end
            -- Touched here, inside the read, so a secret component raises
            -- here rather than on its way to SetVertexColor.
            return { c.r + 0, c.g + 0, c.b + 0, 1 }
        end, nil)
        if plain then return plain end

        if GetClassColor then
            local secret = BazUI.Secret.Read(function()
                return BazUI.Secret.Color(GetClassColor(class))
            end, nil)
            if secret then return secret end
        end
    end

    if opts.reaction then
        -- Nothing special for players: UnitReaction answers for them
        -- too, so one we have no quarrel with reads friendly and one we
        -- do reads hostile, without asking a second question.
        local reaction = UnitReaction and UnitReaction("player", unit)
        if not reaction then return C.hostile end
        if reaction <= 3 then return C.hostile end
        if reaction == 4 then return C.neutral end
        return C.friendly
    end

    return C.alive
end

---------------------------------------------------------------------------
-- What rank a unit is
--
-- The game sorts NPCs into ranks and puts a dragon around the portrait
-- to say so. We have no portraits - that is what lets any bar dock to
-- any other - so the rank has to be said in words instead.
--
-- Two forms of the same fact, because it is read in two places. `suffix`
-- rides along behind a level, the way vanilla has always written elite:
-- "62+", "62 Rare+". `label` stands on its own where there is no level
-- to attach to.
--
-- Normal, trivial and minus come back nil on purpose. They are the
-- ordinary case, and naming them would put a word beside almost every
-- unit you look at, which is the opposite of what this is for.
---------------------------------------------------------------------------

-- `color` names a skin colour rather than holding one, because the skin
-- writes new numbers into its own tables and anything holding a copy
-- would keep painting the old ones.
BazUI.UNIT_RANKS = {
    worldboss = { key = "worldboss", label = "Boss",       suffix = " Boss",  color = "rankBoss"      },
    rareelite = { key = "rareelite", label = "Rare Elite", suffix = " Rare+", color = "rankRareElite" },
    elite     = { key = "elite",     label = "Elite",      suffix = "+",      color = "rankElite"     },
    rare      = { key = "rare",      label = "Rare",       suffix = " Rare",  color = "rankRare"      },
}

-- The live table for a rank, or nil for a unit with no rank worth
-- saying. Looked up fresh so a recoloured skin reaches it.
function BazUI.UnitRankColor(unit)
    local rank = BazUI.UnitRank(unit)
    local colors = BazUI.Skin and BazUI.Skin.Theme and BazUI.Skin.Theme.colors
    return rank and colors and colors[rank.color] or nil
end

---------------------------------------------------------------------------
-- The rank as a glyph
--
-- Drawn inline in whatever is writing the unit's name, using the client's
-- own texture escape. That is what makes it sit on the text's baseline at
-- the text's height without anything here having to measure a font.
--
-- Each rank names the icons it is made of rather than one file. Rare
-- elite is a rare and an elite, so if there is no icon of its own it is
-- shown as both; a world boss is an elite of the worst kind, so it falls
-- back to the elite mark. The set works half-finished, and a file dropped
-- in later is picked up with no code change.
---------------------------------------------------------------------------

local RANK_ICONS = {
    rare      = { "RANK_ICON_RARE" },
    elite     = { "RANK_ICON_ELITE" },
    -- A rank whose own mark is missing borrows the nearest thing it is
    -- made of, so a skin that ships three of the four still works.
    rareelite = { "RANK_ICON_RARE_ELITE", "RANK_ICON_RARE", "RANK_ICON_ELITE" },
    worldboss = { "RANK_ICON_BOSS", "RANK_ICON_ELITE" },
}

-- Worked out once. Which files are on disk cannot change while the game
-- is running, and this is read on every health update.
local resolved = {}

local function IconFor(key)
    local cached = resolved[key]
    if cached ~= nil then return cached or nil end

    local Skin = BazUI.Skin
    local wanted = RANK_ICONS[key]
    if not (Skin and wanted) then return nil end

    for _, name in ipairs(wanted) do
        local path = Skin[name]
        if path and BazUI.Has.Texture(path) then
            resolved[key] = path
            return path
        end
    end

    resolved[key] = false
    return nil
end

-- The texture for a unit's rank, or nil. A path rather than anything
-- drawn: how big it is and where it sits belong to whoever is drawing the
-- unit, who is the only one who knows how much room there is.
function BazUI.UnitRankIcon(unit)
    local rank = BazUI.UnitRank(unit)
    return rank and IconFor(rank.key) or nil
end

function BazUI.UnitRank(unit)
    if not (unit and UnitClassification and UnitExists(unit)) then return nil end
    -- A player is always "normal", so this is only ever a wasted string
    -- compare on the bars that update most often.
    if UnitIsPlayer and UnitIsPlayer(unit) then return nil end
    return BazUI.UNIT_RANKS[UnitClassification(unit)]
end

-- The level and the rank as one piece of text, for whoever is drawing a
-- unit. Nil when there is nothing worth saying, so a caller can leave
-- the field out rather than print an empty one.
--
--   opts.level = false   the rank on its own
--   opts.rank  = false   the level on its own
function BazUI.UnitLevelText(unit, opts)
    opts = opts or {}
    local rank = (opts.rank ~= false) and BazUI.UnitRank(unit) or nil

    if opts.level == false then
        return rank and rank.label or nil
    end

    local level = UnitLevel and UnitLevel(unit)
    if not level or level == 0 then return rank and rank.label or nil end

    -- A level the game will not put a number on is one far enough above
    -- you that the number stopped being the point. Its own UI says ??,
    -- so ours does.
    local text = (level < 0) and "??" or tostring(level)
    return rank and (text .. rank.suffix) or text
end
