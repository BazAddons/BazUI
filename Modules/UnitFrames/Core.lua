-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Unit Frames
--
-- A unit is drawn as bars you make yourself: health, power, casting,
-- experience and reputation, each one floating or docked to an action
-- bar or to another bar. There is no portrait and no frame around it,
-- which is exactly what lets any of them dock to anything else.
--
-- Almost nothing is configured here as a result. What a bar reads, how
-- wide it is, where it sits and what its text says are properties of
-- that bar and are kept on it; this page holds only the few things that
-- are true of all of them.
--
-- See REDESIGN.md for how this replaced the artwork frames.
---------------------------------------------------------------------------

local addon
addon = BazUI:RegisterModule("UnitFrames", {
    title = "Unit Frames",
    icon = "Interface\\Icons\\INV_Misc_Head_Human_01",
    minimap = { label = "Unit Frames", icon = "Interface\\Icons\\INV_Misc_Head_Human_01" },
    profiles = true,
    defaults = {
        classColor   = false,
        unitTooltips = true,
        -- Which rank a unit is. We have no portrait to hang the game's
        -- dragon on, so it is marked on the bar instead, three ways that
        -- do not argue with each other: a glow around it, a glyph in
        -- front of the name, or the rank written out. The first two are
        -- on because neither costs the name any room; the word does, so
        -- it waits to be asked for.
        rankGlow     = true,
        rankIcon     = true,
        rankWord     = false,
        -- The game's animated zZ for a rested player, on the player's
        -- own health bar. On by default: it is a fact the stock frame
        -- always showed, and losing it is a regression rather than a
        -- simplification.
        restIcon     = true,
        showLevel    = false,
        -- A bar showing something the game has a window for is a way into
        -- that window: reputation and experience each have one.
        barClicks    = true,
        -- Fading someone you cannot reach, and how far to fade them.
        rangeFade    = true,
        rangeAlpha   = 0.45,
    },
    slash = { "/bazframes", "/bazplayer" },
    defaultHandler = function() BazUI:OpenOptionsPanel("UnitFrames") end,
    commands = {
        reset = {
            desc = "Delete every bar and start again with the usual five",
            handler = function() addon:ResetBars() end,
        },
        stacks = {
            desc = "Print every bar and row with what it is docked to",
            handler = function() addon:PrintStacks() end,
        },
        paint = {
            desc = "Print why a bar is drawing the way it is: its color, its value and its texture, which are the three ways a bar ends up black.",
            handler = function()
                addon:Print("Bars:")
                for _, line in ipairs(addon.UnitBars:PaintReport()) do
                    print("  " .. line)
                end
            end,
        },
        stock = {
            desc = "Print what happened to each of the game's own frames the Blizzard's Frames switches cover",
            handler = function()
                addon:Print("Blizzard's own frames:")
                for _, line in ipairs(addon.UnitBars:StockReport()) do
                    print("  " .. line)
                end
            end,
        },
        preview = {
            desc = "Show bars for units that are not there, to arrange them",
            handler = function()
                local UnitBars = addon.UnitBars
                if InCombatLockdown() then
                    addon:Print("Preview the bars after combat ends.")
                    return
                end
                UnitBars:SetPreviewWanted(not UnitBars:PreviewWanted())
                addon:Print(UnitBars:PreviewWanted()
                    and "Previewing bars for absent units."
                    or "Preview off.")
            end,
        },
    },
    onReady = function(self)
        self:MigrateRankStyle()
        self:InitializeBars()
        self:OnProfileChanged(function()
            self:MigrateRankStyle()
            self:ApplySettings()
        end)
    end,
})

-- The three rank switches were one dropdown to begin with, before there
-- was an icon to be a third thing it could have been set to. Read the old
-- answer once and throw it away.
--
-- Off stays off: somebody who turned the marking off did not ask for a
-- new kind of it. Everything else keeps what it had and takes the icon,
-- which is what a profile made today would have started with.
local RANK_STYLE_WAS = {
    off  = { glow = false, icon = false, word = false },
    word = { glow = false, icon = true,  word = true  },
    glow = { glow = true,  icon = true,  word = false },
    both = { glow = true,  icon = true,  word = true  },
}

function addon:MigrateRankStyle()
    local old = self:GetSetting("rankStyle")
    local mapped = type(old) == "string" and RANK_STYLE_WAS[old]
    if not mapped then return end

    self:SetSetting("rankGlow", mapped.glow)
    self:SetSetting("rankIcon", mapped.icon)
    self:SetSetting("rankWord", mapped.word)
    self:SetSetting("rankStyle", nil)
end

-- The rank glyphs, declared so /baz check says whether they are on
-- disk. A missing one is not fatal - the rank falls back to the marks
-- it is made of - but it is still worth being told about, because the
-- fallback is quieter than the thing it stands in for.
BazUI:QueueForLogin(function()
    local Skin = BazUI.Skin
    for _, icon in ipairs({
        { key = "RANK_ICON_RARE",       label = "rareIcon.png"      },
        { key = "RANK_ICON_ELITE",      label = "eliteIcon.png"     },
        { key = "RANK_ICON_RARE_ELITE", label = "eliteRareIcon.png" },
        { key = "RANK_ICON_BOSS",       label = "bossIcon.png"      },
    }) do
        BazUI:RegisterDependency({
            module = "Unit Frames",
            label  = "Skin\\Assets\\" .. icon.label,
            why    = "The mark in front of a ranked unit's name.",
            check  = function() return BazUI.Has.Texture(Skin[icon.key]) end,
        })
    end
end)

BazUI:RegisterDependency({
    module = "Unit Frames",
    label  = "ToggleCharacter()",
    why    = "Clicking the reputation or experience bar opens its panel.",
    check  = function() return BazUI.Has.Global("ToggleCharacter") end,
})

-- Back to the five a new profile starts with. Testing an arrangement
-- leaves debris, and deleting a dozen bars one at a time through a
-- confirmation each is its own punishment.
function addon:ResetBars()
    if InCombatLockdown() then
        self:Print("Reset the bars after combat ends.")
        return
    end
    if not BazUI.Confirm then return end

    BazUI:Confirm({
        title       = "Delete every bar?",
        body        = "Every bar you have made goes, and the five a new profile starts with come back. Aura rows are separate: /bazauras reset does those.",
        acceptLabel = "Delete them",
        acceptStyle = "destructive",
        onAccept    = function()
            local UnitBars = addon.UnitBars
            local ids = {}
            for _, def in ipairs(UnitBars:Defs()) do ids[#ids + 1] = def.id end
            for _, id in ipairs(ids) do UnitBars:Remove(id) end
            addon:SeedBars()
            UnitBars:ApplyAll()
            addon:Print("Bars reset.")
        end,
    })
end

-- What is docked to what, as the saved definitions have it and as the
-- dock has it. The two disagreeing is worth seeing directly rather than
-- inferring from where things landed on screen.
function addon:PrintStacks()
    local UnitBars = self.UnitBars
    for _, def in ipairs(UnitBars:Defs()) do
        local bar = UnitBars.bars[def.id]
        local docked = bar and BazUI.Dock:IsDocked(bar.frame) and "docked" or "loose"
        self:Print(("%s (%s) -> %s %s [%s]"):format(
            def.name or "?", UnitBars:HostID(def.id),
            (def.dock and def.dock.host) or "float",
            (def.dock and def.dock.edge) or "-", docked))
    end

    local auras = BazUI:GetModule("Auras")
    if not (auras and auras.Rows) then return end
    for _, def in ipairs(auras:Rows()) do
        local frame = auras:RowFrame(def.id)
        local docked = frame and BazUI.Dock:IsDocked(frame) and "docked" or "loose"
        self:Print(("%s (%s) -> %s %s [%s]"):format(
            def.name or "?", auras:RowHostID(def.id),
            (def.dock and def.dock.host) or "float",
            (def.dock and def.dock.edge) or "-", docked))
    end
end

-- Everything the module owns, applied again from what is saved. Named
-- ApplySettings because that is what the suite calls on a profile
-- change, and safe to call twice: every bar is laid out from its own
-- definition rather than from wherever it happens to be.
function addon:ApplySettings()
    local UnitBars = self.UnitBars
    if not UnitBars then return end
    UnitBars:ApplyAll()
    UnitBars:UpdateAll()
    UnitBars:SuppressStock()
end

-- The set a new profile starts with: the readings almost everyone wants,
-- arranged the way they were before any of this was configurable. Making
-- none would leave a blank screen and no clue where to begin.
local STARTER_BARS = {
    { kind = "health", unit = "player", y = -140 },
    { kind = "power",  unit = "player", y = -164, dockPrevious = true },
    { kind = "cast",   unit = "player", y = -188, dockPrevious = true },
    { kind = "health", unit = "target", y = -140, x = 300 },
    { kind = "power",  unit = "target", y = -164, x = 300, dockPrevious = true },
}

function addon:SeedBars()
    local UnitBars = self.UnitBars
    if #UnitBars:Defs() > 0 then return end

    local previous
    for _, seed in ipairs(STARTER_BARS) do
        local def = UnitBars:Add(seed.kind, seed.unit)
        if def then
            if seed.dockPrevious and previous then
                def.dock = { host = UnitBars:HostID(previous.id), edge = "BOTTOM" }
            else
                def.position = { point = "CENTER", relPoint = "CENTER",
                    x = seed.x or -300, y = seed.y or -140 }
                previous = def
            end
            if not seed.dockPrevious then previous = def end
        end
    end
    UnitBars:Save()
    UnitBars:ApplyAll()
end

function addon:InitializeBars()
    if InCombatLockdown() then
        self:On("PLAYER_REGEN_ENABLED", function() self:InitializeBars() end)
        return
    end

    local UnitBars = self.UnitBars
    UnitBars:RegisterCreator()
    UnitBars:RegisterCopyMenu()
    UnitBars:BuildAll()
    self:SeedBars()
    UnitBars:WatchAll()
    UnitBars:UpdateAll()
    -- Whichever of the game's own frames the player asked us to put away.
    UnitBars:SuppressStock()

    -- Asked again when the cast of frames can change. Blizzard's raid
    -- manager is built hidden and only turns up once you are in a group,
    -- so login is too early to take hold of it; a roster change is the
    -- moment it appears. Both calls cost nothing when nothing has
    -- changed - SuppressStock compares the switches and the frames it has
    -- already hooked before it touches anything.
    self:On("GROUP_ROSTER_UPDATE",    function() UnitBars:SuppressStock() end)
    self:On("PLAYER_ENTERING_WORLD",  function() UnitBars:SuppressStock() end)

    -- Edit Mode may open or close at any time, and the movers are the
    -- only thing it is ever allowed to move.
    self:On("BAZ_EDITMODE_ENTER", function()
        UnitBars:RefreshEditSettings()
        -- Bars for absent units turn up while arranging, so a party
        -- layout can be built without a party.
        UnitBars:RefreshPreview()
        UnitBars:ShowAllMovers()
    end)
    self:On("BAZ_EDITMODE_EXIT",  function()
        UnitBars:RefreshPreview()
        UnitBars:ShowAllMovers()
    end)
    self:On("PLAYER_REGEN_ENABLED", function()
        UnitBars:BuildAll()
        UnitBars:ApplyAll()
        -- Showing and hiding these is protected, so whatever the preview
        -- should have been while the fight ran, it is now.
        UnitBars:RefreshPreview()
        UnitBars:ShowAllMovers()
        -- Hiding Blizzard's frames is protected, so anything that
        -- changed mid-fight has been waiting for this.
        UnitBars:SuppressStock()
    end)
end
