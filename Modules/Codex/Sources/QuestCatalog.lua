-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex: the Quests tab
--
-- Not to be confused with Sources/Quests.lua, which is the Today
-- tab's "ready to hand in" and "nearly there" blocks. That one is
-- about the handful in your log right now; this one is about all of
-- them.
--
-- Every quest in the game, what it asks of you, what it pays, and whether
-- you have done it.
--
-- Two halves, and the split is not arbitrary.
--
-- WHAT EXISTS is shipped: Data/Quests.lua, 2,142 quests with title,
-- level, tag, experience, coin and objectives. None of that is in the
-- client's files - QuestV2 has the ids and nothing readable, because
-- quest content lives on the server - so it was collected by asking the
-- server for each quest in turn. See tools/gen-quests.py.
--
-- WHAT YOU HAVE SEEN is yours, and fills in as you play. The description
-- is the one thing the server will not hand over for a quest you have
-- not met: it arrives with the offer, when an NPC is holding the scroll
-- out to you, and at no other moment. So the codex listens for that
-- moment and writes it down. Walk up to a quest giver and read the
-- offer - decline it if you like - and this page has it from then on.
--
-- Completion is not stored at all. The client knows, per character, and
-- answers instantly, so storing it would only be a copy that could go
-- stale.
---------------------------------------------------------------------------

local Codex = BazUI.Codex
local addon = Codex.addon
local Theme = BazUI.Skin.Theme

local TAB = "quests"

---------------------------------------------------------------------------
-- What the game has told us
---------------------------------------------------------------------------

local function Seen()
    return addon:GetSetting("questSeen") or {}
end

local function Catalog()
    local Quests = Codex.Quests
    if Quests and Quests.Available and Quests.Available() then return Quests end
    return nil
end

local function SeenCount()
    local n = 0
    for _ in pairs(Seen()) do n = n + 1 end
    return n
end

-- One quest, as the game has just described it. Only the fields we were
-- actually given; a later offer of the same quest fills in anything that
-- was missing rather than replacing what is there.
local function Remember(id, fields)
    id = tonumber(id)
    if not id or not fields then return false end
    if addon:GetSetting("indexQuests") == false then return false end

    local seen = Seen()
    local row = seen[id] or {}
    local learned = false
    for key, value in pairs(fields) do
        if value and value ~= "" then
            -- A table is never equal to another table, so comparing them
            -- would call everything new and write the file on every
            -- offer. A place we already know is a place we already know.
            local same = (row[key] == value)
                or (type(value) == "table" and type(row[key]) == "table"
                    and (key == "from" or key == "to"))
            if not same then
                row[key] = value
                learned = true
            end
        end
    end
    if not learned then return false end
    seen[id] = row
    addon:SetSetting("questSeen", seen)
    return true
end

---------------------------------------------------------------------------
-- Listening
--
-- QUEST_DETAIL is the offer window, and it is the richest moment there
-- is: the full text, the objective summary, and every reward in this
-- server's own numbers rather than some other version of the game's.
--
-- The other two are worth having for the quests you actually run:
-- QUEST_PROGRESS is what the giver says while you are still working, and
-- QUEST_COMPLETE is what they say when you hand it in. Neither is
-- reachable any other way.
---------------------------------------------------------------------------

-- The offer window knows an item's picture without anybody having to
-- look it up, and its link carries the id. Both were being thrown away,
-- which is why a quest you had met showed its rewards as bare words
-- while one you had not showed them with icons: what you had seen was
-- winning, and what you had seen was the poorer record.
local function RewardList(which, count)
    if not (GetQuestItemInfo and count and count > 0) then return nil end
    local out = {}
    for index = 1, count do
        local name, texture, quantity = GetQuestItemInfo(which, index)
        if name then
            local itemID
            if GetQuestItemLink then
                local ok, link = pcall(GetQuestItemLink, which, index)
                if ok and link then
                    itemID = tonumber(link:match("item:(%d+)"))
                end
            end
            out[#out + 1] = {
                name = name, count = quantity or 1,
                texture = texture, item = itemID,
            }
        end
    end
    return (#out > 0) and out or nil
end

-- Where you are, at the moment the game hands you a quest window.
--
-- A quest has two places - where it is given and where it is handed in -
-- and neither reaches the client for a quest you have not met. They are
-- not in the client's data either: Forever ships almost no map or POI
-- tables, so the usual joins come back empty.
--
-- But when the offer window opens you are standing in front of the
-- giver, and when the completion window opens you are standing in front
-- of whoever takes it. So the position is not looked up at all; it is
-- simply noticed, at the one moment it happens to be true.
--
-- It is your position rather than the NPC's, so it is a step or two out.
-- That is the right kind of wrong for this: near enough to walk to, and
-- never confidently pointing at somewhere else entirely.
local function Where()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, uiMapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not uiMapID then return nil end

    local spot
    if C_Map.GetPlayerMapPosition then
        local fine, position = pcall(C_Map.GetPlayerMapPosition, uiMapID, "player")
        if fine and position and position.GetXY then
            local x, y = position:GetXY()
            if x and y and (x > 0 or y > 0) then
                spot = { math.floor(x * 1000 + 0.5) / 10,
                         math.floor(y * 1000 + 0.5) / 10 }
            end
        end
    end

    local zone = GetZoneText and GetZoneText()
    local subzone = GetSubZoneText and GetSubZoneText()
    if subzone == "" then subzone = nil end
    if (not zone or zone == "") and C_Map.GetMapInfo then
        local fine, info = pcall(C_Map.GetMapInfo, uiMapID)
        if fine and info then zone = info.name end
    end
    if not zone or zone == "" then return nil end

    -- And who you are talking to. "questnpc" is the game's own name for
    -- the one holding the scroll out - QuestFrame titles itself with it -
    -- so this is their name rather than a guess from where you stand.
    local who = UnitName and UnitName("questnpc")
    if who == "" then who = nil end

    return {
        map = uiMapID, zone = zone, spot = subzone, npc = who,
        x = spot and spot[1], y = spot and spot[2],
    }
end

local function TakeOffer()
    local id = GetQuestID and GetQuestID()
    if not id or id == 0 then return end
    Remember(id, {
        title       = GetTitleText and GetTitleText(),
        description = GetQuestText and GetQuestText(),
        summary     = GetObjectiveText and GetObjectiveText(),
        xp          = GetRewardXP and GetRewardXP(),
        money       = GetRewardMoney and GetRewardMoney(),
        rewards     = RewardList("reward", GetNumQuestRewards and GetNumQuestRewards()),
        choices     = RewardList("choice", GetNumQuestChoices and GetNumQuestChoices()),
        -- Standing at the giver, by definition.
        from        = Where(),
    })
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("QUEST_DETAIL")
listener:RegisterEvent("QUEST_PROGRESS")
listener:RegisterEvent("QUEST_COMPLETE")
listener:SetScript("OnEvent", function(_, event)
    if event == "QUEST_DETAIL" then
        TakeOffer()
    elseif event == "QUEST_PROGRESS" then
        local id = GetQuestID and GetQuestID()
        if id and id ~= 0 then
            Remember(id, { progress = GetProgressText and GetProgressText() })
        end
    else
        local id = GetQuestID and GetQuestID()
        if id and id ~= 0 then
            Remember(id, {
                completion = GetRewardText and GetRewardText(),
                -- And standing at whoever takes it.
                to = Where(),
            })
        end
    end
end)

-- An objective the client could put a name to.
--
-- GetQuestObjectives answers with what the client knows, and for a quest
-- it has only been told about it often does not know the creature's name
-- - so "8 Mindless Zombie slain" comes back as "8   slain", a hole where
-- the noun should be. Once the quest is in your log it knows, which is
-- why this is worth capturing at all.
--
-- The count at the front is yours, not the quest's, so it comes off.
local function UsableObjective(text)
    if not text or text == "" then return nil end
    if text:find("%d+%s%s+") then return nil end
    local trimmed = text:gsub("^%s*%d+%s*/%s*(%d+)%s*", "%1 ")
    if not trimmed:find("%s") then return nil end
    return trimmed
end

local function LogObjectives(id)
    if not C_QuestLog.GetQuestObjectives then return nil end
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, id)
    if not ok or type(list) ~= "table" or #list == 0 then return nil end
    local out = {}
    for _, objective in ipairs(list) do
        local text = UsableObjective(objective.text)
        if not text then return nil end   -- all of them, or none
        out[#out + 1] = text
    end
    return (#out > 0) and out or nil
end

-- And the ones already in your log, which the client holds the text for
-- because the log has to draw it. Swept when the codex opens rather than
-- on a timer: the selection is the game's own and is put straight back.
local function SweepLog()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
    local previous = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    for index = 1, (C_QuestLog.GetNumQuestLogEntries()) do
        local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID then
            C_QuestLog.SetSelectedQuest(info.questID)
            local description, summary = GetQuestLogQuestText()
            Remember(info.questID, {
                description = description,
                summary = summary,
                -- The catalogue's own objectives were collected from a
                -- client that had never met these creatures, so some of
                -- them have holes where a name should be. Yours knows.
                objectives = LogObjectives(info.questID),
            })
        end
    end
    if previous then C_QuestLog.SetSelectedQuest(previous) end
end

---------------------------------------------------------------------------
-- One quest, everything we have about it
---------------------------------------------------------------------------

local Done, InLog

local function Merged(id)
    local shipped = Catalog() and Codex.Quests.Get(id)
    local mine = Seen()[id]
    if not (shipped or mine) then return nil end

    local row = {
        id    = id,
        title = (mine and mine.title) or (shipped and shipped.title) or "?",
        level = (shipped and shipped.level) or 0,
        tag   = shipped and shipped.tag,
        -- What the offer said beats the harvest: it came from the game in
        -- front of you rather than from a list made on somebody's client.
        xp    = (mine and mine.xp) or (shipped and shipped.xp) or 0,
        money = (mine and mine.money) or (shipped and shipped.money) or 0,
    }
    row.from        = mine and mine.from
    row.to          = mine and mine.to
    row.description = mine and mine.description
    row.summary     = mine and mine.summary
    row.progress    = mine and mine.progress
    row.completion  = mine and mine.completion
    row.objectives  = (mine and mine.objectives)
        or (Catalog() and Codex.Quests.Objectives(id)) or nil

    -- Given and chosen are two different lists and the catalogue keeps
    -- them in one, marked. Asking for "the rewards" and getting both is
    -- how the same two items came to be listed twice - once as what you
    -- get and again as what you pick from.
    local give, pick
    for _, reward in ipairs((Catalog() and Codex.Quests.Rewards(id)) or {}) do
        if reward.kind == "pick" then
            pick = pick or {}
            pick[#pick + 1] = reward
        else
            give = give or {}
            give[#give + 1] = reward
        end
    end
    -- The fuller of the two lists wins, not simply the learned one.
    --
    -- What you saw is the better record for names and counts, but a
    -- capture made before the recorder kept item ids has neither a
    -- picture nor an id - and the catalogue does. Preferring "learned"
    -- blindly there means showing the poorer of two records we hold.
    local function Richer(learned, listed)
        if not learned then return listed end
        if not listed then return learned end
        for _, reward in ipairs(learned) do
            if reward.item or reward.texture then return learned end
        end
        return listed
    end

    row.rewards = Richer(mine and mine.rewards, give)
    row.choices = Richer(mine and mine.choices, pick)

    -- Where this came from, which is not the same question as whether it
    -- is here. Anything you have met in game is first-hand whatever the
    -- catalogue says; otherwise the catalogue knows which of its own
    -- fields it had to borrow.
    local catalog = Catalog()
    row.textFromGame = (mine and mine.description) and true
        or (not catalog) or Codex.Quests.FromGame(id, "text")
    row.numbersFromGame = (mine and mine.xp) and true
        or (not catalog) or Codex.Quests.FromGame(id, "numbers")
    return row
end

-- Three states, and none of them stored: the client answers all of it
-- about the character you are on, so a saved copy could only be wrong.
function Done(id)
    return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
        and C_QuestLog.IsQuestFlaggedCompleted(id) or false
end

local logIDs = {}

function InLog(id)
    return logIDs[id] and true or false
end

local function RefreshLog()
    wipe(logIDs)
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID then
            logIDs[info.questID] = true
        end
    end
end

local function StateOf(id)
    if InLog(id) then return "doing" end
    if Done(id) then return "done" end
    return "todo"
end

-- Read from the page below, and by anything else that wants to know.
Codex.QuestState = StateOf


---------------------------------------------------------------------------
-- The page
--
-- Laid out like the quest log, because that is the window a player
-- already knows: the list down the left, and whichever one you clicked
-- opened up on the right. Two tabs over the list, and they are the only
-- question the page really asks - have I done this one or not.
---------------------------------------------------------------------------

local ROW_H = 26
local HEADER_H = 22
local WHEEL = 3
local GUTTER = 10          -- between the list and the detail
local LIST_SHARE = 0.67    -- the list's share of the width

-- Where the tabs sit against the list they belong to.
--
-- In from the corner, because a tab flush with the edge reads as part of
-- the frame rather than as a tab on it; and down far enough to stand on
-- the card's top border rather than above it, so the selected one covers
-- that line and the two become one shape.
local TAB_INSET  = 10
local TAB_OVERLAP = 2

local page, header
local query = ""
-- Which of the three the list is showing. They are the same three
-- states a quest can be in, so the tabs and the truth cannot drift:
-- nothing you have not started, nothing you are carrying, nothing you
-- have finished.
local stateFilter = "todo"   -- todo | doing | done
local bandFilter = 0       -- 0 = any, else the decade
local sortKey, sortDesc = "level", false
local opened               -- the quest showing on the right
local hits, hitsFor

local STATES = {
    { value = "todo",  label = "Incomplete" },
    { value = "doing", label = "In progress" },
    { value = "done",  label = "Complete" },
}

local STATE_WORDS = {
    todo  = "still to do",
    doing = "in your log",
    done  = "completed",
}

---------------------------------------------------------------------------
-- Which quests answer the question being asked
---------------------------------------------------------------------------

local function Matches(row, needle)
    if Codex.QuestState(row.id) ~= stateFilter then return false end
    if needle ~= "" then
        local hay = row.title:lower()
        if not hay:find(needle, 1, true) then
            local also = (row.summary or "") .. " " .. (row.description or "")
            if not also:lower():find(needle, 1, true) then return false end
        end
    end
    if bandFilter > 0 then
        local level = row.level or 0
        if bandFilter == 60 then
            if level < 60 then return false end
        elseif level < bandFilter or level > bandFilter + 9 then
            return false
        end
    end
    return true
end

local function Gather()
    local question = table.concat({ query, stateFilter, bandFilter,
        sortKey, tostring(sortDesc) }, "\1")
    if hits and hitsFor == question then return hits end

    local catalog = Catalog()
    local out = {}
    local needle = query:lower()

    local function Consider(id)
        local row = Merged(id)
        if row and Matches(row, needle) then out[#out + 1] = row end
    end

    if catalog then
        for id in pairs(Codex.Quests.All()) do Consider(id) end
    else
        -- No shipped list for this client: what you have met is still
        -- worth showing, rather than an empty page.
        for id in pairs(Seen()) do Consider(id) end
    end

    local key, desc = sortKey, sortDesc
    table.sort(out, function(a, b)
        local x, y = a[key], b[key]
        if type(x) == "string" or type(y) == "string" then
            x, y = tostring(x or ""), tostring(y or "")
        else
            x, y = x or 0, y or 0
        end
        if x == y then return a.title < b.title end
        if desc then return x > y end
        return x < y
    end)

    hits, hitsFor = out, question
    return out
end

---------------------------------------------------------------------------
-- The header: what to search for, and which half of the game to look in
---------------------------------------------------------------------------

local function Invalidate(keepOpen)
    hits, hitsFor = nil, nil
    if not keepOpen then opened = nil end
    if page then page.first = 0 end
    Codex.Panel:QueueRefresh()
end

local function FillStrip(strip, entries, picked, onPick)
    strip:ClearTabs()
    strip.keys = {}
    local activeID
    for index, entry in ipairs(entries) do
        local tabID = strip:AddTab(entry.label)
        strip.keys[tabID] = index
        if entry.value == picked then activeID = tabID end
    end
    strip:SetTabSelectedCallback(function(tabID, isUserAction)
        if not isUserAction then return end
        local entry = entries[strip.keys[tabID]]
        if entry then onPick(entry.value) end
    end)
    strip:Layout()
    if activeID then
        strip:SetTabVisuallySelected(activeID)
        strip.selectedTabID = activeID
    end
end

local BANDS = {
    { value = 0,  label = "Any level" },
    { value = 1,  label = "1-9" },   { value = 10, label = "10-19" },
    { value = 20, label = "20-29" }, { value = 30, label = "30-39" },
    { value = 40, label = "40-49" }, { value = 50, label = "50-59" },
    { value = 60, label = "60+" },
}

local function BuildHeader(host)
    if header then
        header:SetParent(host)
        return header
    end

    header = CreateFrame("Frame", nil, host)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")

    header.box = Theme.CreateSearchBox(header,
        "Filter by name, or by what a quest asks of you",
        function(text)
            query = text or ""
            Invalidate()
        end)
    header.box:SetPoint("TOPLEFT", 0, 0)
    header.box:SetPoint("TOPRIGHT", 0, 0)

    -- The level bands are a filter, so they go with the search box.
    header.band = BazUI.CreateTabStrip(nil, header, {
        style = "panel", tabHeight = 20, spacing = 3,
        minTabWidth = 40, maxTabWidth = 140,
    })
    header.band:SetPoint("TOPLEFT", header.box, "BOTTOMLEFT", 0, -7)

    header.note = Theme.FontString(header, "OVERLAY", "GameFontHighlightSmall")
    header.note:SetPoint("TOPLEFT", header.band, "BOTTOMLEFT", 2, -7)
    header.note:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    header.note:SetJustifyH("LEFT")
    header.note:SetTextColor(unpack(Theme.colors.textMuted))

    -- Complete and Incomplete last, and hard against the bottom of the
    -- header so they sit directly on the list.
    --
    -- They were up under the search box with the level bands and the
    -- count line between them and the list, which made them read as a
    -- third filter rather than as the tabs of the thing underneath. A
    -- tab has to touch what it belongs to.
    header.state = BazUI.CreateTabStrip(nil, header, {
        style = "raised", tabHeight = 28, spacing = 4,
        minTabWidth = 104, maxTabWidth = 200,
        -- The chosen tab takes the list card's own colour, so the two
        -- join instead of one sitting on the other.
        tabFill = Codex.Panel.BOX_FILL,
    })
    header.state:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT",
        TAB_INSET, -TAB_OVERLAP)

    return header
end

local function RenderHeader(host, width)
    local h = BuildHeader(host)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT")
    h:SetWidth(width)
    h:Show()

    FillStrip(h.state, STATES, stateFilter, function(value)
        stateFilter = value or "todo"
        Invalidate()
    end)
    FillStrip(h.band, BANDS, bandFilter, function(value)
        bandFilter = value or 0
        Invalidate()
    end)
    h.state:SetWrapWidth(width)
    h.band:SetWrapWidth(width)


    local total = Catalog() and Codex.Quests.count or SeenCount()
    local showing = #Gather()
    h.note:SetText(("%d %s | %d quests in all | the story of %d has been told to you")
        :format(showing, STATE_WORDS[stateFilter] or "", total, SeenCount()))

    -- No air under the tabs: the list card begins where the header ends,
    -- and the two are meant to meet.
    local height = 26 + 7 + (h.band:GetHeight() or 20) + 7 + 14 + 8
        + (h.state:GetHeight() or 28)
    h:SetHeight(height)
    return height
end

---------------------------------------------------------------------------
-- The list, down the left
---------------------------------------------------------------------------

local COLUMNS = {
    { key = "level", title = "Lvl", width = 40, justify = "RIGHT" },
    { key = "xp",    title = "XP",  width = 58, justify = "RIGHT" },
}

-- Is TomTom here, and will it take a waypoint?
local function TomTomReady()
    local tt = _G.TomTom
    return (tt and type(tt.AddWaypoint) == "function") and tt or nil
end

---------------------------------------------------------------------------
-- The right-click menu
--
-- Through BazUI:OpenContextMenu rather than a menu of its own, which is
-- what every other right-click in the suite uses - so this one wears the
-- same chrome, and another module could add to it without touching this
-- file.
--
-- Everything here is done to "the selected quest", which is the game's
-- own single selection shared with the quest log and the map. It is put
-- back afterwards, exactly as QuestMapFrame does.
---------------------------------------------------------------------------

local function WithSelected(id, fn)
    if not (C_QuestLog and C_QuestLog.SetSelectedQuest) then return end
    local previous = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    C_QuestLog.SetSelectedQuest(id)
    local ok, err = pcall(fn)
    if previous then C_QuestLog.SetSelectedQuest(previous) end
    if not ok then error(err, 0) end
end

local function Watched(id)
    if not (C_QuestLog and C_QuestLog.GetQuestWatchType) then return false end
    local ok, kind = pcall(C_QuestLog.GetQuestWatchType, id)
    return ok and kind ~= nil
end

BazUI:QueueForModule("Codex", function()
    BazUI:RegisterContextMenuSection("codexQuest", "Quest", function(context)
        local id = context and context.questID
        if not id then return {} end

        local quest = Merged(id)
        local state = Codex.QuestState(id)
        local items = {}

        if state == "doing" then
            if Watched(id) then
                items[#items + 1] = { label = "Stop tracking", onClick = function()
                    local index = C_QuestLog.GetLogIndexForQuestID(id)
                    if index then C_QuestLog.RemoveQuestWatch(index) end
                end }
            else
                items[#items + 1] = { label = "Track it", onClick = function()
                    local index = C_QuestLog.GetLogIndexForQuestID(id)
                    if index then C_QuestLog.AddQuestWatch(index) end
                end }
            end

            local pushable = C_QuestLog.IsPushableQuest
                and select(2, pcall(C_QuestLog.IsPushableQuest, id))
            items[#items + 1] = {
                label = "Share with the group",
                disabled = not (pushable and IsInGroup and IsInGroup()),
                onClick = function()
                    WithSelected(id, function()
                        if _G.QuestLogPushQuest then _G.QuestLogPushQuest() end
                    end)
                end,
            }
        end

        if _G.GetQuestLink then
            items[#items + 1] = { label = "Link it in chat", onClick = function()
                local link = _G.GetQuestLink(id)
                if link and _G.ChatEdit_InsertLink then
                    if not _G.ChatEdit_InsertLink(link) then
                        _G.ChatFrame_OpenChat(link)
                    end
                end
            end }
        end

        -- Somewhere to go, when we have been there.
        local function Waypoint(label, where)
            if not (where and where.x and TomTomReady()) then return end
            items[#items + 1] = { label = label, onClick = function()
                TomTomReady():AddWaypoint(where.map, where.x / 100, where.y / 100, {
                    title = (where.npc or where.zone) .. "\n" .. (quest.title or ""),
                    from = "BazUI", crazy = true,
                })
            end }
        end
        Waypoint("Point me at the giver", quest and quest.from)
        Waypoint("Point me at the turn-in", quest and quest.to)

        if state == "doing" then
            items[#items + 1] = { divider = true }
            items[#items + 1] = {
                label = "|cffff4444Abandon it|r",
                onClick = function()
                    local title = (quest and quest.title) or ("quest " .. id)
                    local function Abandon()
                        WithSelected(id, function()
                            C_QuestLog.SetAbandonQuest()
                            C_QuestLog.AbandonQuest()
                        end)
                    end
                    if BazUI.Confirm then
                        BazUI:Confirm({
                            title       = "Abandon quest?",
                            body        = ("Give up %s? Everything you have done "
                                .. "towards it is lost, and you would have to take "
                                .. "it again from the start."):format(title),
                            acceptLabel = "Abandon",
                            acceptStyle = "destructive",
                            onAccept    = Abandon,
                        })
                    else
                        Abandon()
                    end
                end,
            }
        end

        return items
    end)
end)

local function AcquireRow(index)
    local row = page.rows[index]
    if row then return row end

    row = Codex.Panel.CreateBandRow(page.card)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetSize(14, 14)
    row.mark:SetPoint("LEFT", 9, 0)

    row.label = Theme.FontString(row, "OVERLAY", "GameFontHighlight")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.cols = {}
    for _, column in ipairs(COLUMNS) do
        local fs = Theme.FontString(row, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH(column.justify)
        row.cols[column.key] = fs
    end

    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local quest = self.questID and Merged(self.questID)
            BazUI:OpenContextMenu("codexQuest", self,
                { questID = self.questID },
                { title = quest and quest.title or nil })
            return
        end
        opened = self.questID
        Codex.Panel:QueueRefresh()
    end)

    page.rows[index] = row
    return row
end

local function ColumnSpots()
    local right, spots = 8, {}
    for index = #COLUMNS, 1, -1 do
        local column = COLUMNS[index]
        spots[column.key] = right
        right = right + column.width + 8
    end
    return spots, right
end

local function FillRows()
    local list = page.hits
    local visible = page.visible or 0
    local spots, nameRight = ColumnSpots()
    local shown = 0

    for i = page.first + 1, math.min(#list, page.first + visible) do
        shown = shown + 1
        local row = AcquireRow(shown)
        local quest = list[i]
        row.questID = quest.id

        local state = Codex.QuestState(quest.id)
        if state == "done" then
            row.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            row.mark:Show()
        elseif state == "doing" then
            row.mark:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
            row.mark:Show()
        else
            row.mark:Hide()
        end

        row.label:SetText(quest.title)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 29, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -nameRight, 0)
        row.label:SetTextColor(unpack((quest.id == opened)
            and Theme.colors.gold or Theme.colors.text))

        for _, column in ipairs(COLUMNS) do
            local fs = row.cols[column.key]
            fs:ClearAllPoints()
            fs:SetWidth(column.width)
            fs:SetPoint("RIGHT", row, "RIGHT", -spots[column.key], 0)
            local value = quest[column.key]
            fs:SetText((value and value > 0) and tostring(value) or "")
            fs:SetTextColor(unpack(Theme.colors.textMuted))
        end

        -- The banding is the row's position in the list, not its state.
        -- Which one is open is said by the gold title instead.
        Codex.Panel.SetRowBand(row, shown)

        local top = -(8 + HEADER_H + (shown - 1) * ROW_H)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", page.card, "TOPLEFT", 8, top)
        row:SetPoint("TOPRIGHT", page.card, "TOPRIGHT", -8, top)
        row:Show()
    end

    for index = shown + 1, #page.rows do page.rows[index]:Hide() end

    local most = math.max(0, #list - visible)
    page.hint:SetShown(most > 0 and page.first < most)
end

local function FillHeader()
    local spots, nameRight = ColumnSpots()

    local function Place(key, title, justify, width, offset)
        local head = page.heads[key]
        if not head then
            head = CreateFrame("Button", nil, page.head)
            head:SetHeight(HEADER_H)
            head.text = Theme.FontString(head, "OVERLAY", "GameFontHighlightSmall")
            head.text:SetAllPoints()
            head.arrow = head:CreateTexture(nil, "OVERLAY")
            head.arrow:SetSize(10, 10)
            head:SetScript("OnClick", function()
                if sortKey == key then sortDesc = not sortDesc
                else sortKey, sortDesc = key, (key ~= "title") end
                Invalidate(true)
            end)
            page.heads[key] = head
        end
        head.text:SetText(title)
        head.text:SetJustifyH(justify)
        head:ClearAllPoints()
        if width then
            head:SetWidth(width)
            head:SetPoint("RIGHT", page.head, "RIGHT", -offset, 0)
        else
            head:SetPoint("LEFT", page.head, "LEFT", 21, 0)
            head:SetPoint("RIGHT", page.head, "RIGHT", -offset, 0)
        end
        head.text:SetTextColor(unpack(
            (sortKey == key) and Theme.colors.gold or Theme.colors.textMuted))
        head.arrow:SetShown(sortKey == key)
        if sortKey == key then
            BazUI.SetArrowTexture(head.arrow, sortDesc and "DOWN" or "UP", 10)
            head.arrow:ClearAllPoints()
            if justify == "RIGHT" then
                head.arrow:SetPoint("RIGHT", head.text, "LEFT", -3, 0)
            else
                head.arrow:SetPoint("LEFT", head.text, "LEFT",
                    math.min(head.text:GetStringWidth() or 0,
                        head:GetWidth() or 0) + 4, 0)
            end
        end
        head:Show()
    end

    Place("title", "Quest", "LEFT", nil, nameRight)
    for _, column in ipairs(COLUMNS) do
        Place(column.key, column.title, column.justify,
            column.width, spots[column.key])
    end
end

---------------------------------------------------------------------------
-- The detail, down the right
--
-- Built as a stack of lines rather than one long string with colour
-- codes in it. A single string cannot space a heading differently from
-- the paragraph under it, cannot indent a list, and cannot put two
-- things on one line - so the old one had every section the same size,
-- the same colour and the same distance apart, and read as a wall.
--
-- The lines come from a pool and are laid out top down, so a quest with
-- two sections costs two sections.
---------------------------------------------------------------------------

local LINE_GAP     = 3     -- between the lines of one block
local BLOCK_GAP    = 16    -- between one block and the next
local HEADING_GAP  = 7     -- between a heading and its body
local RULE_GAP     = 9     -- either side of the rule under the title
local PLACE_INSET  = 10    -- places sit in from the edge, like objectives

local function AcquireRule(index)
    local pool = page.detail.rules
    local rule = pool[index]
    if not rule then
        rule = page.detail.inner:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        pool[index] = rule
    end
    return rule
end

-- One place, as a line you can press.
--
-- A button rather than a font string, because knowing a quest is given
-- at (31.0, 66.2) in Deathknell is a good deal less useful than being
-- pointed at it. With TomTom installed this sets its arrow; without it
-- the line is the same words and simply does not click.
local function AcquirePlace(index)
    local pool = page.detail.places
    local place = pool[index]
    if place then return place end

    place = CreateFrame("Button", nil, page.detail.inner)

    -- Two lines, not one. Run together they wrapped mid-address and read
    -- as one long string of nouns, with the name - the part you actually
    -- want - buried somewhere in the middle of it.
    place.who = Theme.FontString(place, "OVERLAY", "GameFontNormalSmall")
    place.who:SetPoint("TOPLEFT")
    place.who:SetPoint("TOPRIGHT")
    place.who:SetJustifyH("LEFT")

    place.at = Theme.FontString(place, "OVERLAY", "GameFontHighlightSmall")
    place.at:SetPoint("TOPLEFT", place.who, "BOTTOMLEFT", 0, -2)
    place.at:SetPoint("TOPRIGHT", place.who, "BOTTOMRIGHT", 0, -2)
    place.at:SetJustifyH("LEFT")

    place:SetScript("OnEnter", function(self)
        if not self.where then return end
        self.who:SetTextColor(unpack(Theme.colors.gold))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.where.npc or self.where.zone,
            unpack(Theme.colors.text))
        if self.where.spot then
            GameTooltip:AddLine(self.where.spot .. ", " .. self.where.zone,
                0.6, 0.55, 0.45)
        end
        if TomTomReady() and self.where.x then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to point TomTom at it.", 0.5, 0.8, 0.5)
        end
        GameTooltip:Show()
    end)
    place:SetScript("OnLeave", function(self)
        self.who:SetTextColor(unpack(Theme.colors.text))
        GameTooltip:Hide()
    end)
    place:SetScript("OnClick", function(self)
        local tt = TomTomReady()
        local where = self.where
        if not (tt and where and where.x and where.map) then return end
        -- TomTom wants the position as a fraction; ours is a percentage
        -- because that is how a player reads a coordinate.
        tt:AddWaypoint(where.map, where.x / 100, where.y / 100, {
            title = (where.npc or where.zone) .. "\n" .. (self.questTitle or ""),
            from = "BazUI",
            crazy = true,
        })
    end)

    pool[index] = place
    return place
end

local function AcquireLine(index, font)
    local pool = page.detail.lines
    local line = pool[index]
    if not line then
        line = Theme.FontString(page.detail.inner, "OVERLAY", font)
        line:SetJustifyH("LEFT")
        line:SetSpacing(LINE_GAP)
        pool[index] = line
        pool.fonts[index] = font
    elseif pool.fonts[index] ~= font then
        line:SetFontObject(font)
        pool.fonts[index] = font
    end
    return line
end

-- What this reward looks like: whatever the offer window handed us, or
-- the item's own icon looked up by id.
local function IconFor(reward)
    if reward.texture then return reward.texture end
    local itemID = reward.item
    -- A name and no picture still deserves a slot, so a list does not go
    -- ragged where one item happens to be unknown. This used to bail out
    -- here, which made the fallback below unreachable in the one case it
    -- was written for.
    if not itemID or itemID == 0 then
        return "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    if C_Item and C_Item.GetItemIconByID then
        local ok, texture = pcall(C_Item.GetItemIconByID, itemID)
        if ok and texture then return texture end
    end
    if _G.GetItemIcon then
        local ok, texture = pcall(_G.GetItemIcon, itemID)
        if ok and texture then return texture end
    end
    -- A name and no picture still deserves a slot, so the list does not
    -- go ragged where one item happens to be unknown.
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

---------------------------------------------------------------------------
-- Everything a quest has to say, laid out. Returns the height used.
--
-- Shaped like the game's own quest window, because that is the one every
-- player already knows how to read: the summary and the objectives sit
-- straight under the title with nothing announcing them, and only two
-- things get a heading of their own - the story and what you are paid.
--
-- It used to have four headings, one of them "What it asks" over a list
-- that said the same as the summary above it. A heading on every block
-- is the same as no headings at all: nothing stands out because
-- everything does.
---------------------------------------------------------------------------

local function LayoutDetail(quest, width)
    local pool = page.detail.lines
    local used, count, rules = 0, 0, 0

    local function Put(text, font, colour, gapAbove, indent)
        if not text or text == "" then return end
        count = count + 1
        local line = AcquireLine(count, font)
        line:ClearAllPoints()
        line:SetWidth(width - (indent or 0))
        line:SetText(text)
        line:SetTextColor(unpack(colour))
        used = used + (gapAbove or 0)
        line:SetPoint("TOPLEFT", page.detail.inner, "TOPLEFT", indent or 0, -used)
        line:Show()
        used = used + (line:GetStringHeight() or 12)
    end

    local function Rule(colour, gapAbove)
        rules = rules + 1
        local rule = AcquireRule(rules)
        rule:ClearAllPoints()
        used = used + (gapAbove or 0)
        rule:SetPoint("TOPLEFT", page.detail.inner, "TOPLEFT", 0, -used)
        rule:SetPoint("RIGHT", page.detail.inner, "RIGHT", 0, 0)
        rule:SetColorTexture(unpack(colour))
        rule:Show()
        used = used + 1
    end

    local function Heading(text)
        Put(text, "GameFontNormalSmall", Theme.colors.gold, BLOCK_GAP)
        local line = pool[count]
        local at = (line:GetStringWidth() or 0) + 9
        rules = rules + 1
        local rule = AcquireRule(rules)
        rule:ClearAllPoints()
        rule:SetPoint("LEFT", line, "LEFT", at, 0)
        rule:SetPoint("RIGHT", page.detail.inner, "RIGHT", 0, 0)
        rule:SetColorTexture(unpack(Theme.colors.divider))
        rule:Show()
    end

    -- The name, and one quiet line saying what it is.
    Put(quest.title, "GameFontNormalLarge", Theme.colors.gold, 0)

    local facts = {}
    if quest.level and quest.level > 0 then
        facts[#facts + 1] = "Level " .. quest.level
    end
    if quest.tag then facts[#facts + 1] = quest.tag end
    local state = Codex.QuestState(quest.id)
    facts[#facts + 1] = (state == "done" and "Completed")
        or (state == "doing" and "In your log")
        or "Not done"
    Put(table.concat(facts, "  |  "), "GameFontHighlightSmall",
        Theme.colors.textMuted, 5)

    Rule(Theme.colors.edge, RULE_GAP)
    used = used + RULE_GAP

    -- What it wants, unannounced, the way the game says it.
    Put(quest.summary, "GameFontHighlightSmall", Theme.colors.text, 0)

    if quest.objectives and #quest.objectives > 0 then
        for index, text in ipairs(quest.objectives) do
            Put(text, "GameFontHighlightSmall", Theme.colors.textMuted,
                (index == 1) and 10 or LINE_GAP, 10)
        end
    end

    -- Where it came from and where it goes, when you have been to
    -- either. Yours, from having stood there.
    --
    -- A section of its own, below what the quest asks and above the story
    -- behind it: it is the one part of this page that can send you
    -- somewhere, and it was unreadable crammed in beside the level and
    -- the tag. Each place is a name on one line and an address on the
    -- next, so the name reads as the subject rather than as the middle of
    -- a sentence.
    local placed = 0
    local function Place(label, where)
        if not where then return end
        if placed == 0 then Heading("Where") end
        placed = placed + 1

        local row = AcquirePlace(placed)
        row.where = where
        row.questTitle = quest.title
        row:SetWidth(width - PLACE_INSET)

        row.who:SetText(("%s:  %s"):format(label, where.npc or where.zone))
        row.who:SetTextColor(unpack(Theme.colors.text))

        local at = where.spot and (where.spot .. ", " .. where.zone) or where.zone
        if where.x then
            at = ("%s   (%.1f, %.1f)"):format(at, where.x, where.y)
        end
        row.at:SetText(at)
        row.at:SetTextColor(unpack(Theme.colors.textMuted))

        -- Measured rather than assumed, so a long address that wraps
        -- pushes the next line down instead of sitting on top of it.
        row:SetHeight((row.who:GetStringHeight() or 12)
            + 2 + (row.at:GetStringHeight() or 11))

        row:ClearAllPoints()
        used = used + ((placed == 1) and HEADING_GAP or LINE_GAP + 4)
        row:SetPoint("TOPLEFT", page.detail.inner, "TOPLEFT", PLACE_INSET, -used)
        row:EnableMouse(true)
        row:Show()
        used = used + row:GetHeight()
    end
    Place("Given by", quest.from)
    Place("Handed to", quest.to)

    Heading("Description")
    Put(quest.description
        or "Not in here yet. A quest's words only reach your client when "
        .. "somebody offers it to you, so this fills in when you meet the "
        .. "one who gives it.",
        "GameFontHighlightSmall",
        quest.description and Theme.colors.text or Theme.colors.textMuted,
        HEADING_GAP)

    if quest.description and not quest.textFromGame then
        Put("From a public database, not yet seen in game.",
            "GameFontHighlightSmall", Theme.colors.textMuted, 6)
    end

    -- The rest, only when there is any. These are the giver's words at
    -- moments other than the offer, and most quests have none of them.
    if quest.progress and quest.progress ~= "" then
        Heading("While you are working")
        Put(quest.progress, "GameFontHighlightSmall", Theme.colors.text,
            HEADING_GAP)
    end
    if quest.completion and quest.completion ~= "" then
        Heading("On handing in")
        Put(quest.completion, "GameFontHighlightSmall", Theme.colors.text,
            HEADING_GAP)
    end

    for index = count + 1, #pool do pool[index]:Hide() end
    for index = rules + 1, #page.detail.rules do page.detail.rules[index]:Hide() end
    for index = placed + 1, #page.detail.places do
        page.detail.places[index]:Hide()
    end
    return used + 10
end

---------------------------------------------------------------------------
-- What you are paid, along the bottom
--
-- Its own block rather than the last paragraph of the story, because
-- that is where the game puts it and because it is the one part of a
-- quest that does not want reading - it wants glancing at. Pinned to the
-- foot of the panel so it is in the same place for every quest, however
-- long the description above it runs.
---------------------------------------------------------------------------

local PLATE_H   = 26
local PLATE_GAP = 5
local XP_ICON   = "Interface\\Icons\\XP_Icon"
local COIN_ICONS = {
    { 10000, "Interface\\MoneyFrame\\UI-GoldIcon",   "ffd700" },
    { 100,   "Interface\\MoneyFrame\\UI-SilverIcon", "c7c7cf" },
    { 1,     "Interface\\MoneyFrame\\UI-CopperIcon", "eda55f" },
}

local function AcquireFooterLine(index, font)
    local pool = page.detail.footLines
    local line = pool[index]
    if not line then
        line = Theme.FontString(page.detail.footer, "OVERLAY", font)
        line:SetJustifyH("LEFT")
        pool[index] = line
        pool.fonts[index] = font
    elseif pool.fonts[index] ~= font then
        line:SetFontObject(font)
        pool.fonts[index] = font
    end
    return line
end

-- One reward, as a plate: its picture in a slot, its name beside it.
local function AcquirePlate(index)
    local pool = page.detail.plates
    local plate = pool[index]
    if plate then return plate end

    plate = CreateFrame("Button", nil, page.detail.footer)
    plate:SetHeight(PLATE_H)

    plate.bg = plate:CreateTexture(nil, "BACKGROUND")
    plate.bg:SetAllPoints()
    plate.bg:SetColorTexture(0.10, 0.09, 0.07, 0.55)

    plate.icon = plate:CreateTexture(nil, "ARTWORK")
    plate.icon:SetSize(PLATE_H - 8, PLATE_H - 8)
    plate.icon:SetPoint("LEFT", 4, 0)
    plate.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    plate.edge = plate:CreateTexture(nil, "BORDER")
    plate.edge:SetPoint("TOPLEFT", plate.icon, "TOPLEFT", -1, 1)
    plate.edge:SetPoint("BOTTOMRIGHT", plate.icon, "BOTTOMRIGHT", 1, -1)
    plate.edge:SetColorTexture(unpack(Theme.colors.divider))

    plate.label = Theme.FontString(plate, "OVERLAY", "GameFontHighlightSmall")
    plate.label:SetPoint("LEFT", plate.icon, "RIGHT", 6, 0)
    plate.label:SetPoint("RIGHT", -5, 0)
    plate.label:SetJustifyH("LEFT")
    plate.label:SetWordWrap(false)

    plate:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.18, 0.15, 0.09, 0.75)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shown = false
        if GameTooltip.SetItemByID then
            shown = pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
        end
        if not shown then
            pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.itemID)
        end
        GameTooltip:Show()
    end)
    plate:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(0.10, 0.09, 0.07, 0.55)
        GameTooltip:Hide()
    end)

    pool[index] = plate
    return plate
end

-- The coin, written the way the game writes it: a number and its icon,
-- for each denomination there is any of.
local function CoinText(copper)
    copper = tonumber(copper) or 0
    if copper == 0 then return nil end
    if _G.GetCoinTextureString then return _G.GetCoinTextureString(copper) end

    local parts, left = {}, copper
    for _, unit in ipairs(COIN_ICONS) do
        local amount = math.floor(left / unit[1])
        left = left % unit[1]
        if amount > 0 then
            if BazUI.Has and BazUI.Has.Texture and BazUI.Has.Texture(unit[2]) then
                parts[#parts + 1] = ("%d|T%s:12:12:0:0|t"):format(amount, unit[2])
            else
                parts[#parts + 1] = ("|cff%s%d|r"):format(unit[3], amount)
            end
        end
    end
    return table.concat(parts, " ")
end

-- Returns the height it needs. Nothing to pay means nothing drawn.
local function LayoutRewards(quest, width)
    local footer = page.detail.footer
    local lines, plates = 0, 0
    local used = 0

    local coin = CoinText(quest.money)
    local xp = (quest.xp and quest.xp > 0) and quest.xp or nil
    local choices = quest.choices or {}
    local giving = quest.rewards or {}

    if #choices == 0 and #giving == 0 and not coin and not xp then
        footer:Hide()
        for _, line in ipairs(page.detail.footLines) do line:Hide() end
        for _, plate in ipairs(page.detail.plates) do plate:Hide() end
        return 0
    end
    footer:Show()

    local function Say(text, font, colour, gapAbove)
        lines = lines + 1
        local line = AcquireFooterLine(lines, font)
        line:ClearAllPoints()
        line:SetWidth(width)
        line:SetText(text)
        line:SetTextColor(unpack(colour))
        used = used + (gapAbove or 0)
        line:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, -used)
        line:Show()
        used = used + (line:GetStringHeight() or 12)
    end

    -- Two across where they fit, the way the game lays them out; one
    -- across when the panel is too narrow for a name to survive it.
    local columns = (width >= 300) and 2 or 1
    local plateWidth = math.floor((width - PLATE_GAP * (columns - 1)) / columns)

    local function Row(list)
        for index, reward in ipairs(list) do
            plates = plates + 1
            local plate = AcquirePlate(plates)
            local column = (index - 1) % columns
            if column == 0 and index > 1 then
                used = used + PLATE_H + PLATE_GAP
            end
            plate:SetWidth(plateWidth)
            plate:ClearAllPoints()
            plate:SetPoint("TOPLEFT", footer, "TOPLEFT",
                column * (plateWidth + PLATE_GAP), -used)
            plate.icon:SetTexture(IconFor(reward))
            plate.itemID = reward.item
            local label = reward.name or "?"
            if (reward.count or 1) > 1 then label = label .. " x" .. reward.count end
            plate.label:SetText(label)
            plate:Show()
        end
        if #list > 0 then used = used + PLATE_H end
    end

    Say("Rewards", "GameFontNormalSmall", Theme.colors.gold, 0)

    if #choices > 0 then
        Say("You will be able to choose one of these:",
            "GameFontHighlightSmall", Theme.colors.textMuted, 5)
        used = used + 4
        Row(choices)
    end

    if #giving > 0 or xp or coin then
        Say((#choices > 0) and "You will also receive:" or "You will receive:",
            "GameFontHighlightSmall", Theme.colors.textMuted,
            (#choices > 0) and 8 or 5)
        used = used + 4
        Row(giving)

        if xp or coin then
            local pay = {}
            if xp then
                pay[#pay + 1] = ("|T%s:14:14:0:0|t %s"):format(XP_ICON,
                    _G.BreakUpLargeNumbers and _G.BreakUpLargeNumbers(xp) or xp)
            end
            if coin then pay[#pay + 1] = coin end
            Say(table.concat(pay, "      "), "GameFontHighlight",
                Theme.colors.text, (#giving > 0) and 6 or 0)
        end
    end

    for index = lines + 1, #page.detail.footLines do
        page.detail.footLines[index]:Hide()
    end
    for index = plates + 1, #page.detail.plates do
        page.detail.plates[index]:Hide()
    end

    return used + 4
end

---------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------

local function Build(parent)
    if page then
        page:SetParent(parent)
        return page
    end

    page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT")
    page.rows = {}
    page.heads = {}
    page.first = 0
    page.hits = {}

    -- The list, left.
    page.card = Codex.Panel.CreateBox(page)
    page.card:SetPoint("TOPLEFT")

    page.head = CreateFrame("Frame", nil, page.card)
    page.head:SetPoint("TOPLEFT", 8, -8)
    page.head:SetPoint("TOPRIGHT", -8, -8)
    page.head:SetHeight(HEADER_H)
    page.head.rule = page.head:CreateTexture(nil, "ARTWORK")
    page.head.rule:SetHeight(1)
    page.head.rule:SetPoint("BOTTOMLEFT")
    page.head.rule:SetPoint("BOTTOMRIGHT")
    page.head.rule:SetColorTexture(unpack(Theme.colors.edge))

    page.hint = page.card:CreateTexture(nil, "OVERLAY")
    page.hint:SetPoint("BOTTOM", page.card, "BOTTOM", 0, 4)
    BazUI.SetArrowTexture(page.hint, "DOWN", 20)
    page.hint:SetAlpha(0.45)
    page.hint:Hide()

    page.card:EnableMouseWheel(true)
    page.card:SetScript("OnMouseWheel", function(_, delta)
        local most = math.max(0, #page.hits - (page.visible or 1))
        local to = math.max(0, math.min(most, page.first - delta * WHEEL))
        if to ~= page.first then
            page.first = to
            FillRows()
        end
    end)

    -- The quest, right. Its own scroll, because a description runs long
    -- and the page it sits on does not scroll at all.
    page.detail = Codex.Panel.CreateBox(page)
    page.detail:SetPoint("TOPRIGHT")

    -- What you are paid, along the bottom, in the same place whatever
    -- the quest above it says.
    page.detail.footer = CreateFrame("Frame", nil, page.detail)
    page.detail.footer:SetPoint("BOTTOMLEFT", 16, 14)
    page.detail.footer:SetPoint("BOTTOMRIGHT", -14, 14)
    page.detail.footer:SetHeight(1)
    page.detail.footLines = { fonts = {} }
    page.detail.plates = {}

    page.detail.footRule = page.detail:CreateTexture(nil, "ARTWORK")
    page.detail.footRule:SetHeight(1)
    page.detail.footRule:SetPoint("BOTTOMLEFT", page.detail.footer, "TOPLEFT", 0, 10)
    page.detail.footRule:SetPoint("BOTTOMRIGHT", page.detail.footer, "TOPRIGHT", 0, 10)
    page.detail.footRule:SetColorTexture(unpack(Theme.colors.edge))

    page.detail.scroll = CreateFrame("ScrollFrame", nil, page.detail)
    page.detail.scroll:SetPoint("TOPLEFT", 16, -15)
    page.detail.scroll:SetPoint("RIGHT", -14, 0)
    page.detail.scroll:SetPoint("BOTTOM", page.detail.footRule, "TOP", 0, 8)
    Codex.Panel.MakeScrollable(page.detail.scroll, page.detail)

    page.detail.inner = CreateFrame("Frame", nil, page.detail.scroll)
    page.detail.scroll:SetScrollChild(page.detail.inner)
    page.detail.lines = { fonts = {} }
    page.detail.rules = {}
    page.detail.places = {}

    -- What it says when nothing is picked.
    page.detail.empty = Theme.FontString(page.detail, "OVERLAY", "GameFontHighlightSmall")
    page.detail.empty:SetPoint("TOPLEFT", 16, -15)
    page.detail.empty:SetPoint("TOPRIGHT", -14, -15)
    page.detail.empty:SetJustifyH("LEFT")
    page.detail.empty:SetText("Pick a quest on the left.")
    page.detail.empty:SetTextColor(unpack(Theme.colors.textMuted))

    return page
end

---------------------------------------------------------------------------
-- Drawing it
---------------------------------------------------------------------------

local function Render(content, width)
    local p = Build(content)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT")
    p:SetWidth(width)
    p:Show()

    p.hits = Gather()

    -- Both halves are as tall as the room there is, so the page itself
    -- never scrolls: the list scrolls, and so does the quest beside it.
    local room = math.max((Codex.Panel.ContentHeight() or 300) - 2, ROW_H + 60)
    local listWidth = math.floor((width - GUTTER) * LIST_SHARE)

    p.card:SetWidth(listWidth)
    p.card:SetHeight(room)
    p.detail:SetWidth(width - GUTTER - listWidth)
    p.detail:SetHeight(room)

    p.visible = math.max(1, math.floor((room - 16 - HEADER_H) / ROW_H))
    p.first = math.max(0, math.min(p.first, math.max(0, #p.hits - p.visible)))

    p.head:SetShown(#p.hits > 0)
    if #p.hits > 0 then FillHeader() end
    FillRows()

    local quest = opened and Merged(opened)
    p.detail.empty:SetShown(quest == nil)
    p.detail.scroll:SetShown(quest ~= nil)

    if quest then
        local inner = p.detail:GetWidth() - 30

        -- The rewards are measured first: the text above them scrolls in
        -- whatever room is left once they have taken theirs.
        local footHeight = LayoutRewards(quest, inner)
        p.detail.footer:SetHeight(math.max(footHeight, 1))
        p.detail.footRule:SetShown(footHeight > 0)

        p.detail.inner:SetWidth(inner)
        local height = LayoutDetail(quest, inner)
        p.detail.inner:SetHeight(height)
        p.detail.scroll.bazContentH = height
        p.detail.scroll:SetVerticalScroll(0)
        Codex.Panel.UpdateScrollHint(p.detail.scroll)
    else
        for _, line in ipairs(p.detail.lines or {}) do line:Hide() end
        for _, rule in ipairs(p.detail.rules or {}) do rule:Hide() end
        for _, place in ipairs(p.detail.places or {}) do place:Hide() end
        for _, line in ipairs(p.detail.footLines or {}) do line:Hide() end
        for _, plate in ipairs(p.detail.plates or {}) do plate:Hide() end
        p.detail.footer:Hide()
        p.detail.footRule:Hide()
    end

    p:SetHeight(room)
    Codex.customTabs.quests.height = room
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

Codex.customTabs.quests = {
    label        = "Quests",
    order        = 25,
    RenderHeader = RenderHeader,
    Render       = Render,
    Hide         = function()
        if page then page:Hide() end
        if header then header:Hide() end
    end,
    height = 1,
    -- Everything this tab was holding, let go when the window opens.
    Reset        = function()
        query, stateFilter, bandFilter = "", "todo", 0
        sortKey, sortDesc = "level", false
        opened = nil
        hits, hitsFor = nil, nil
        if header and header.box then header.box:SetText("") end
        if page then page.first = 0 end
        RefreshLog()
        SweepLog()
    end,
    GetHighlights = function()
        local catalog = Catalog()
        local total = catalog and Codex.Quests.count or SeenCount()
        local done = 0
        if catalog then
            for id in pairs(Codex.Quests.All()) do
                if Done(id) then done = done + 1 end
            end
        end
        return {
            { value = done, label = "quests completed",
              color = done > 0 and Theme.colors.success or nil },
            { value = total - done, label = "still to do" },
        }
    end,
}

---------------------------------------------------------------------------
-- Staying current
---------------------------------------------------------------------------

BazUI:QueueForModule("Codex", function()
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("QUEST_LOG_UPDATE")
    watcher:RegisterEvent("QUEST_TURNED_IN")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", function()
        RefreshLog()
        hits, hitsFor = nil, nil
        if Codex.IsShown and Codex:IsShown()
            and (addon:GetSetting("activeTab") or "today") == TAB then
            Codex.Panel:QueueRefresh()
        end
    end)
end)
