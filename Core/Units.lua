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

    if opts.classColor and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then return { color.r, color.g, color.b, 1 } end
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
