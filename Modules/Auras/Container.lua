-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: aura rows drawn by the engine
--
-- Everything in Frames.lua is built on READING auras, and on this client
-- that is refused for the whole of every fight. Measured three ways:
--
--   ShouldUnitAuraIndexBeSecret   secret, for every index, on every unit
--   GetAuraDataByIndex            "Auras cannot be accessed when secret
--                                  while tainted by BazUI" - an error,
--                                  and not one that pcall can catch
--   UNIT_AURA                     arrives, but addedAuras is a secret
--                                  table: it cannot be indexed or counted
--
-- So a row froze on whatever it was showing when the fight began, and a
-- debuff applied during the fight never appeared at all. Blizzard's own
-- frames are unaffected because they are untainted, and that is the whole
-- of the difference.
--
-- The way out is to stop reading. AuraContainer is an intrinsic Blizzard
-- ships for addons to instantiate - its own TOC says the XML is loaded
-- globally "to allow intrinsics and templates to be instantiated by
-- external code without making their created objects implicitly
-- forbidden". We hand it a unit, a filter and a texture; it holds the
-- secret values and draws them. Nothing in this file ever looks at an
-- aura.
--
-- What that buys beyond working at all: the duration text and the stack
-- count are rendered from secret values too, so they keep counting during
-- a fight. And cancelling is Blizzard's - SetCancelAuraButtons, then
-- their OnClick calls CancelAuraByInstanceID from secure code. By
-- instance, rather than by a stamped index that goes stale the moment an
-- aura ahead of it falls off.
--
-- Five things this system will not tell you, each of which cost a test:
--
--   1. A container sizes itself from its contents. An empty one is 0x0,
--      so anything anchored to it vanishes. It lives inside a row frame.
--   2. elementWidth / elementHeight default to nil. The engine will make
--      frames and fill them and have no dimensions to lay them out with.
--   3. SetEnabled(true) is REQUIRED and defaults off. Without it nothing
--      registers for UNIT_AURA and nothing is ever parsed - while the
--      frame count still reads healthy, because the batch is pre-made.
--   4. CustomAuraButtonTemplate has no artwork whatsoever. It is mixins
--      only. SetIcon is what gives the engine something to paint into.
--   5. An aura frame becomes a FORBIDDEN OBJECT the moment it holds a
--      secret aura - GetWidth on one throws. So all styling happens in
--      initializeFrame and never afterwards.
---------------------------------------------------------------------------

local MODULE_NAME = "Auras"
local addon = BazUI:GetModule(MODULE_NAME)
if not addon then return end

local Auras = BazUI.Auras
local Container = {}
Auras.Container = Container

-- Live containers, one per row id, and what each was built for.
--
-- The engine only runs initializeFrame when it creates a frame, so
-- anything decided in there - icon size, whether right-click cancels -
-- cannot be changed afterwards. When one of those settings moves, the
-- container is thrown away and built again. That is the only honest way
-- to do it, and it is cheap because it only happens on a settings change.
local containers = {}
local builtFor = {}
local available

local GROUP = "auras"

function Container.Available()
    if available == nil then
        -- Asked once. The intrinsic either exists on this client or it
        -- does not, and CreateFrame on a missing one is an error rather
        -- than a nil, so it is tried behind a pcall exactly once.
        local ok, frame = pcall(CreateFrame, "AuraContainer", nil, UIParent,
            "CustomAuraContainerTemplate")
        available = (ok and frame) and true or false
        if ok and frame then frame:Hide() end
    end
    return available
end

-- The shape of a row, in pixels.
--
-- Computed from the settings rather than measured from the icons, because
-- the engine deliberately obscures how many auras there are:
-- FrameCreationBatchSize is commented "Must be sufficiently high to
-- obfuscate the number of auras". So a container row holds its configured
-- footprint whether it is full or empty, where the old row shrank to fit.
-- That is the price of the thing working during a fight.
local function Shape(cfg)
    local size = cfg.size or 26
    local gap = math.max(math.abs(cfg.xOffset or size) - size, 0)
    local across = math.max(cfg.across or 1, 1)
    local rows = math.max(cfg.rows or 1, 1)
    return across * size + (across - 1) * gap,
           rows * size + (rows - 1) * gap,
           size, gap, across
end

function Container.Measure(def)
    local c = def and containers[def.id]
    if not (c and c.bazShape) then return nil end
    return c.bazShape.w, c.bazShape.h
end

function Container.Get(def)
    return def and containers[def.id] or nil
end

-- Our sort settings, in the engine's terms.
--
-- The keys are the ones the options page actually stores - INDEX, TIME,
-- NAME and + / - , which is what Settings.lua offers and what
-- SortAuras compares against further down. Worth stating because the
-- first version of this table invented lowercase names, matched nothing,
-- and quietly sorted every engine row by Default forever: a mapping that
-- misses does not fail, it just always takes the fallback.
local SORTS = {
    INDEX = "Default",
    TIME  = "Expiration",
    NAME  = "Name",
}

local function SortEnum(cfg)
    local enum = _G.AuraContainerSortMethod
    if not enum then return nil end
    return enum[SORTS[cfg.sortMethod] or "Default"] or enum.Default
end

local function DirectionEnum(cfg)
    local enum = _G.AuraContainerSortDirection
    if not enum then return nil end
    return (cfg.sortDirection == "-") and enum.Reverse or enum.Normal
end

-- What one build has to be told apart from another by.
--
-- Everything here is decided inside initializeFrame, which the engine
-- only runs when it creates a frame - and an aura frame is forbidden to
-- us the moment it holds an aura, so there is no reaching back in later.
-- When any of these move, the container is rebuilt. That is why the list
-- has to be complete: a setting missing from it is a setting that
-- silently does nothing until the next reload.
local function Signature(cfg)
    return table.concat({
        tostring(cfg.unit), tostring(cfg.filter),
        tostring(cfg.size), tostring(cfg.across), tostring(cfg.rows),
        tostring(cfg.xOffset), tostring(cfg.cancel),
        tostring(cfg.shape), tostring(cfg.showDuration),
        tostring(cfg.showCount), tostring(cfg.dispelRims),
        tostring(cfg.weapons),
    }, "|")
end

function Container.Release(def)
    local id = def and def.id
    local c = id and containers[id]
    if not c then return end
    pcall(c.SetEnabled, c, false)
    c:Hide()
    containers[id] = nil
    builtFor[id] = nil
end

-- Build the row, or hand back the one that is already right.
--
-- Not rebuilt during a fight. Nothing here is protected, but a container
-- built mid-fight would come up empty and stay that way: SetEnabled runs
-- ParseAllAuras, and every read that makes is refused while the fight is
-- on. The one we already have is still being driven by the engine, so
-- keeping it is strictly better than replacing it with a blank.
function Container.Ensure(def, cfg, parent)
    if not (def and cfg and parent and Container.Available()) then return nil end

    local id = def.id
    local want = Signature(cfg)
    if containers[id] and builtFor[id] == want then return containers[id] end
    if InCombatLockdown() then return containers[id] end

    Container.Release(def)

    local ok, c = pcall(CreateFrame, "AuraContainer", "BazUIAuraContainer" .. id,
        parent, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end

    local w, h, size, gap, across = Shape(cfg)
    c.bazShape = { w = w, h = h }

    local point = cfg.point or "TOPLEFT"
    c:ClearAllPoints()
    c:SetPoint(point, parent, point, 0, 0)
    c:SetSize(w, h)

    local cancel = cfg.cancel and "RightButtonUp, RightButtonDown" or nil

    -- The one moment anything about a frame can be decided.
    --
    -- A setting not read here is a setting that does not apply to engine
    -- rows at all, so every one of them is read here and none anywhere
    -- else. Each Set* hands the engine a region of ours and takes it over:
    -- from that call on it carries secret aspects and the engine drives
    -- it. Handing it nothing is how a feature is turned off - there is no
    -- later moment to hide something in.
    local function Initialize(frame)
        pcall(function()
            frame:SetSize(size, size)

            if frame.Icon then frame:SetIcon(frame.Icon) end

            -- Only where the player asked for them. A font string never
            -- handed over is simply never written to.
            if cfg.showCount ~= false and frame.Count then
                frame:SetApplicationCount(frame.Count)
            end
            if cfg.showDuration ~= false and frame.Duration then
                frame:SetDurationText(frame.Duration)
            end

            -- The rim, colored by what the debuff is. Blue for Magic,
            -- purple for Curse, and so on - the same scheme the
            -- hand-rolled rows paint by hand, except the engine does the
            -- coloring from a dispel type we are not allowed to read.
            -- Left alone on a buff row, and when the setting is off, so
            -- the border keeps the flat color the template gives it.
            if cfg.dispelRims and frame.Border then
                frame:AddDispelTypeTexture(frame.Border)
            end

            -- Rounded corners, if that is the chosen shape. Applied here
            -- rather than by Auras.ApplyButtonShape, which walks the
            -- button pool and resizes masks on every layout - neither of
            -- which is possible on a frame that is about to be forbidden.
            if Auras.ApplyButtonShape then
                Auras.ApplyButtonShape(frame, cfg.shape)
            end

            if cancel then frame:SetCancelAuraButtons(cancel) end
        end)
    end

    local built = pcall(c.SetUnit, c, cfg.unit)
    built = built and pcall(c.AddAuraGroup, c, GROUP, cfg.filter, {
        -- The same artwork the hand-rolled buttons wear - rim, inset
        -- icon, count, duration - so a container row and a classic row
        -- look identical. AuraButton is a Button intrinsic, so a Button
        -- template inherits onto it.
        templateNames   = { "BazUIAuraVisualTemplate" },
        initializeFrame = Initialize,
        maxFrameCount   = ((cfg.rows or 0) > 0) and (across * cfg.rows) or nil,
        sortMethod      = SortEnum(cfg),
        sortDirection   = DirectionEnum(cfg),
        layout = {
            elementWidth   = size,
            elementHeight  = size,
            elementSpacing = gap,
            lineSpacing    = gap,
        },
    })

    if not built then
        Container.Release(def)
        return nil
    end

    -- Weapon enchants, as a slot type of their own.
    --
    -- The hand-rolled row faked these: a button stamped with a weapon
    -- slot instead of an aura index, read through GetWeaponEnchantInfo,
    -- with its own expiry arithmetic because that API answers in
    -- milliseconds-from-now rather than an absolute time. None of that
    -- is needed here - the engine has a first-class enchantment slot and
    -- counts it down itself.
    if cfg.weapons then
        local slots = _G.AuraContainerItemEnchantmentSlot
        if slots then
            for _, slot in ipairs({ slots.MainHand, slots.OffHand, slots.Ranged }) do
                if slot ~= nil then
                    pcall(c.AddItemEnchantment, c, slot, {
                        templateNames   = { "BazUIAuraVisualTemplate" },
                        initializeFrame = Initialize,
                        -- A permanent enchant is not news. It has no
                        -- timer and it is not going anywhere, so it would
                        -- sit in the row forever taking a slot.
                        hidePermanent   = true,
                    })
                end
            end
        end
    end

    pcall(c.SetFlowLayoutMaximumLineSize, c, w)
    pcall(c.SetEnabled, c, true)
    c:Show()

    containers[id] = c
    builtFor[id] = want
    return c
end
