-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: Legacy
--
-- Forever's own system, and the one thing in the codex that is not in
-- any other version of the game: points earned once for the account and
-- spent per character across three trees, with a reward track alongside
-- them.
--
-- The page is built now and fills in by itself. Everything here is
-- asked of the client - the renown track's level, the trait currency,
-- what each tree has had spent in it - so on a build where the system
-- is not open yet nothing answers and the page says so, in as many
-- words. Nothing is written down, because the moment it were it would
-- be wrong.
--
-- What the ids mean (Constants.LegacyConsts, confirmed in the Forever
-- client): the reward track is a major faction, the points are a trait
-- currency, and the three trees are trait trees.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local Theme = BazUI.Skin.Theme

local TAB = "legacy"
local COMMON = {
    tab      = TAB,
    tabLabel = "Legacy",
    tabOrder = 120,
    tabIcon  = "Interface\\Icons\\INV_Misc_Trophy_Argent",
}
local PREFIX = "leg."

---------------------------------------------------------------------------
-- The ids
--
-- Asked of the client first, because a constant it publishes is a
-- constant it will keep in step with itself; the numbers are what this
-- build answered, and are only the fallback.
---------------------------------------------------------------------------

local function Const(name, fallback)
    local consts = _G.Constants and _G.Constants.LegacyConsts
    local value = consts and consts[name]
    return (type(value) == "number" and value) or fallback
end

local function TrackFactionID()  return Const("LEGACY_REWARD_TRACK_FACTION_ID", 2802) end
local function PointsCurrencyID() return Const("LEGACY_POINTS_TRAIT_CURRENCY_ID", 4225) end

-- The trees, in the order the game's own page puts them.
local function Trees()
    return {
        { id = Const("LEGACY_TREE_ADVENTURE_ID", 1188),
          name = _G.LEGACY_TREE_ADVENTURE or "Adventure" },
        { id = Const("LEGACY_TREE_PROFESSIONS_ID", 1187),
          name = _G.LEGACY_TREE_PROFESSIONS or "Professions" },
        { id = Const("LEGACY_TREE_PROGRESSION_ID", 1189),
          name = _G.LEGACY_TREE_PROGRESSION or "Progression" },
    }
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

-- Points earned, points there are to earn, and where the reward track
-- stands. Nil for anything this build will not answer.
local function Points()
    local out = {}
    if C_MajorFactions and C_MajorFactions.GetCurrentRenownLevel then
        local ok, level = pcall(C_MajorFactions.GetCurrentRenownLevel, TrackFactionID())
        if ok and type(level) == "number" then out.earned = level end
    end
    if C_Traits and C_Traits.GetMaxAvailableTraitCurrency then
        local ok, total = pcall(C_Traits.GetMaxAvailableTraitCurrency, PointsCurrencyID(), false)
        if ok and type(total) == "number" and total > 0 then out.available = total end
    end
    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local ok, data = pcall(C_MajorFactions.GetMajorFactionData, TrackFactionID())
        if ok and type(data) == "table" then
            out.trackName = data.name
            out.trackMax  = data.maxLevel
        end
    end
    return out
end

-- What each tree has had spent in it, and what it can hold.
local function TreeSpend()
    if not (C_Traits and C_Traits.GetConfigIDByTreeID and C_Traits.GetTreeCurrencyInfo) then
        return nil
    end
    local out, any = {}, false
    for _, tree in ipairs(Trees()) do
        local spent, held
        local ok, configID = pcall(C_Traits.GetConfigIDByTreeID, tree.id)
        if ok and configID then
            local ok2, list = pcall(C_Traits.GetTreeCurrencyInfo, configID, tree.id, true)
            local info = ok2 and list and list[1]
            if info then
                any = true
                spent = info.spentInTree or info.spent or 0
                held  = info.quantity
            end
        end
        out[#out + 1] = { name = tree.name, id = tree.id, spent = spent, held = held }
    end
    return any and out or nil
end

-- Legacy challenges are achievements. The client will only answer where
-- the achievement side is loaded, which it is not on every build.
local function Challenges()
    if not (GetCategoryNumAchievements and GetCategoryList) then return nil end
    local ok, categories = pcall(GetCategoryList)
    if not (ok and type(categories) == "table" and #categories > 0) then return nil end
    local done, total = 0, 0
    for _, id in ipairs(categories) do
        local ok2, num, complete = pcall(GetCategoryNumAchievements, id)
        if ok2 and type(num) == "number" then
            total = total + num
            done = done + (complete or 0)
        end
    end
    if total == 0 then return nil end
    return { done = done, total = total }
end

---------------------------------------------------------------------------
-- Blocks
---------------------------------------------------------------------------

local function Blocks()
    local points = Points()
    local trees  = TreeSpend()
    local chal   = Challenges()
    local live   = points.earned ~= nil or trees ~= nil or chal ~= nil

    -- Nothing answered: the system is not open on this build. Said
    -- plainly, with what the codex will show once it is.
    if not live then
        return { {
            key   = "_waiting",
            title = "Legacy",
            GetRows = function()
                return {
                    { label = "Forever's Legacy system is not open yet.",
                      detail = "not yet", muted = true },
                    { label = "When it opens, this page fills in on its own.",
                      muted = true },
                    { label = "Points earned and left to earn", detail = "waiting", muted = true },
                    { label = "What each of the three trees holds", detail = "waiting", muted = true },
                    { label = "How far along the reward track you are", detail = "waiting", muted = true },
                }
            end,
        } }
    end

    local blocks = {}

    -- The points themselves, and the track they feed.
    blocks[#blocks + 1] = {
        key   = "points",
        title = "Legacy points",
        about = "Points the whole account earns once, from challenges, and that"
            .. " every character then spends separately across the three trees.",
        GetRows = function()
            local p, rows = Points(), {}
            if p.earned then
                rows[#rows + 1] = {
                    label  = "Earned",
                    detail = p.available and ("%d of %d"):format(p.earned, p.available)
                        or tostring(p.earned),
                    state  = "done",
                    tip    = "Legacy points are earned once for the account.|nEvery character spends them separately.",
                }
            end
            if p.available and p.earned then
                local left = math.max(0, p.available - p.earned)
                rows[#rows + 1] = {
                    label  = "Left to earn",
                    detail = tostring(left),
                    state  = left > 0 and "open" or "done",
                }
            end
            if p.trackName or p.trackMax then
                rows[#rows + 1] = {
                    label  = p.trackName or "Reward track",
                    detail = (p.earned and p.trackMax)
                        and ("%d of %d"):format(p.earned, p.trackMax)
                        or (p.trackMax and ("to %d"):format(p.trackMax) or "open"),
                    state  = "open",
                }
            end
            return rows
        end,
        GetHighlight = function()
            local p = Points()
            if not p.earned then return nil end
            return {
                value = p.earned,
                label = p.available and ("legacy points of %d"):format(p.available)
                    or (p.earned == 1 and "legacy point" or "legacy points"),
                color = Theme.colors.gold,
            }
        end,
    }

    -- The three trees, and what this character has put in them.
    if trees then
        blocks[#blocks + 1] = {
            key   = "trees",
            title = "Trees",
            about = "Where this character has put its legacy points. Another"
                .. " character may spend the very same points quite differently.",
            empty = "Nothing spent yet.",
            GetRows = function()
                local rows = {}
                for _, tree in ipairs(TreeSpend() or {}) do
                    rows[#rows + 1] = {
                        label  = tree.name,
                        detail = tree.spent and (tree.spent == 1 and "1 point" or (tree.spent .. " points"))
                            or "nothing spent",
                        state  = (tree.spent or 0) > 0 and "open" or nil,
                        muted  = (tree.spent or 0) == 0 or nil,
                        tip    = tree.name .. "|nPoints are spent per character, so another character may"
                            .. " spend the same points quite differently.",
                    }
                end
                return rows
            end,
            GetBar = function()
                local spent = 0
                for _, tree in ipairs(TreeSpend() or {}) do spent = spent + (tree.spent or 0) end
                return { text = spent == 1 and "1 point spent on this character"
                    or (spent .. " points spent on this character") }
            end,
        }
    end

    -- The challenges that earn the points.
    if chal then
        blocks[#blocks + 1] = {
            key   = "challenges",
            title = "Challenges",
            GetRows = function()
                local c = Challenges()
                if not c then return {} end
                return { {
                    label  = "Completed",
                    detail = ("%d of %d"):format(c.done, c.total),
                    state  = c.done >= c.total and "done" or "open",
                    progress = { bar = true, value = c.done, max = math.max(c.total, 1) },
                } }
            end,
        }
    end

    return blocks
end

local function Sync()
    Codex:SyncGroupSections(PREFIX, COMMON, Blocks())
end

---------------------------------------------------------------------------
-- Staying current
---------------------------------------------------------------------------

BazUI:QueueForModule("Codex", function()
    Sync()
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    for _, event in ipairs({ "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "TRAIT_CONFIG_UPDATED",
                             "ACHIEVEMENT_EARNED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" }) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    watcher:SetScript("OnEvent", function()
        Sync()
        if Codex.IsShown and Codex:IsShown() then
            Codex.Panel:RebuildTabs()
            Codex.Panel:QueueRefresh()
        end
    end)
end)
