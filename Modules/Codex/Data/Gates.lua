-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- Codex data: gates
--
-- The small set of questions this client will actually answer about a
-- character, and the one place that asks them. An attunement and a
-- long-term goal are the same shape underneath: a list of conditions,
-- each of which the client can settle, and a name for the thing they
-- add up to.
--
--   level       reach a level
--   money       have saved an amount
--   item        own an item, bank included
--   quest       have completed a quest
--   mount       own a mount, matched by name in the companion list
--   reputation  stand at least this well with a faction
--
-- Gates that carry an id also carry the name we believe that id has, so
-- the client can be asked whether the number is right. A number we got
-- wrong then hides its entry instead of showing something false. That
-- check is the whole reason it is safe to write this knowledge down at
-- all, since none of it can be derived from the client.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
Codex.Gates = Codex.Gates or {}
local Gates = Codex.Gates

local function Same(a, b)
    if not (a and b) then return false end
    return a:lower() == b:lower()
end
Gates.Same = Same

---------------------------------------------------------------------------
-- Asking the client
---------------------------------------------------------------------------

function Gates.StandingWith(factionName)
    local count = (C_Reputation and C_Reputation.GetNumFactions
        and C_Reputation.GetNumFactions()) or (GetNumFactions and GetNumFactions()) or 0
    for i = 1, count do
        local name, standing, isHeader
        if C_Reputation and C_Reputation.GetFactionDataByIndex then
            local data = C_Reputation.GetFactionDataByIndex(i)
            if data then name, standing, isHeader = data.name, data.reaction, data.isHeader end
        else
            local n, _, s, _, _, _, _, _, header = GetFactionInfo(i)
            name, standing, isHeader = n, s, header
        end
        if name and not isHeader and Same(name, factionName) then return standing or 0 end
    end
    return nil
end

local function OwnsMount(mountName)
    if not (GetNumCompanions and GetCompanionInfo) then return false end
    local ok, count = pcall(GetNumCompanions, "MOUNT")
    if not ok or not count then return false end
    for i = 1, count do
        local ok2, _, name = pcall(GetCompanionInfo, "MOUNT", i)
        if ok2 and name and Same(name, mountName) then return true end
    end
    return false
end

-- Whether one gate is satisfied, and how far through it you are. The
-- fraction is what lets a savings target draw a bar rather than a tick.
function Gates.Met(gate)
    if gate.kind == "level" then
        local level = UnitLevel("player") or 1
        return level >= (gate.level or 60), math.min(1, level / (gate.level or 60))
    end

    if gate.kind == "money" then
        local have = GetMoney and GetMoney() or 0
        local want = gate.copper or 0
        return have >= want, want > 0 and math.min(1, have / want) or 1
    end

    if gate.kind == "item" then
        local owned = (C_Item.GetItemCount(gate.id, true) or 0) > 0
        return owned, owned and 1 or 0
    end

    if gate.kind == "quest" then
        if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return false, 0 end
        local done = C_QuestLog.IsQuestFlaggedCompleted(gate.id) and true or false
        return done, done and 1 or 0
    end

    if gate.kind == "mount" then
        local owned = OwnsMount(gate.name)
        return owned, owned and 1 or 0
    end

    if gate.kind == "reputation" then
        local standing = Gates.StandingWith(gate.faction)
        local want = gate.standing or 8
        return (standing or 0) >= want, math.min(1, (standing or 0) / want)
    end

    return false, 0
end

---------------------------------------------------------------------------
-- Checking a written-down number against the client
---------------------------------------------------------------------------

-- true when the client agrees, false when it disagrees, nil when it has
-- not heard of the id yet. A missing answer is not evidence of a wrong
-- number: item and quest names arrive over the wire. The second return
-- is what the client actually calls the id, which is the whole of the
-- fix when a number is wrong.
function Gates.Agrees(gate)
    if gate.kind == "quest" then
        if not (C_QuestLog and C_QuestLog.GetQuestInfo) then return nil end
        local title = C_QuestLog.GetQuestInfo(gate.id)
        if not title or title == "" then return nil end
        return Same(title, gate.name), title
    end

    if gate.kind == "item" then
        local itemName = C_Item.GetItemInfo(gate.id)
        if not itemName then
            if C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(gate.id)
            end
            return nil
        end
        return Same(itemName, gate.name), itemName
    end

    -- level, money, mount and reputation gates carry no id to be wrong
    -- about: they are written in the same terms the client answers in.
    return true
end

-- Walk a list of entries, each { id, name, steps }, and return a map of
-- entry id to the reason it was rejected.
function Gates.Validate(entries)
    local rejected = {}
    for _, entry in ipairs(entries) do
        for _, gate in ipairs(entry.steps or {}) do
            local agrees, actual = Gates.Agrees(gate)
            if agrees == false then
                rejected[entry.id] = string.format(
                    "%s: %s %d should be \"%s\" but the client calls it \"%s\"",
                    entry.name, gate.kind, gate.id or 0, gate.name or "?", actual or "?")
                break
            end
        end
    end
    return rejected
end

-- The whole state of one entry: how many gates are met, which are not,
-- and how far through it is counting part-finished gates.
function Gates.Evaluate(entry)
    local done, missing, fraction = 0, {}, 0
    local steps = entry.steps or {}

    for _, gate in ipairs(steps) do
        local met, part = Gates.Met(gate)
        if met then
            done = done + 1
            fraction = fraction + 1
        else
            fraction = fraction + (part or 0)
            missing[#missing + 1] = gate.label or gate.name or gate.kind
        end
    end

    local total = #steps
    return {
        entry    = entry,
        done     = done,
        total    = total,
        missing  = missing,
        complete = (total > 0 and done == total),
        fraction = (total > 0) and (fraction / total) or 0,
    }
end
