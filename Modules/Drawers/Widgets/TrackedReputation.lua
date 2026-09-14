-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Tracked Reputation
--
-- Always-on widget that shows a single user-picked faction's standing
-- and progress to next level. Ideal for grinding reputations and
-- keeping the Watched Faction Bar out of the way.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID    = "bazdrawer_trackedreputation"
local DESIGN_WIDTH = 220
local DESIGN_HEIGHT = 48
local PAD          = 8
local BAR_H        = 10

local CLR_NAME  = { 1.00, 0.85, 0.45 }
local CLR_DIM   = { 0.65, 0.65, 0.70 }
local CLR_BAR   = { 0.40, 0.80, 0.40 }
local CLR_BG    = { 0.08, 0.08, 0.10, 0.85 }

local Rep = {}
addon.TrackedReputationWidget = Rep

---------------------------------------------------------------------------
-- Settings access
---------------------------------------------------------------------------

local function GetTrackedFactionID()
    return addon:GetWidgetSetting(WIDGET_ID, "factionID", nil)
end

local function SetTrackedFactionID(id)
    addon:SetWidgetSetting(WIDGET_ID, "factionID", id)
end

---------------------------------------------------------------------------
-- Faction data lookups (work for both regular factions and friendships)
---------------------------------------------------------------------------

local function FetchFactionData(factionID)
    if not factionID then return nil end
    if not (C_Reputation and C_Reputation.GetFactionDataByID) then
        -- Classic clients: GetFactionInfoByID returns the same facts positionally.
        if not GetFactionInfoByID then return nil end
        local name, _, standingID, barMin, barMax, barValue = GetFactionInfoByID(factionID)
        if not name then return nil end
        local total = (barMax or 0) - (barMin or 0)
        local current = (barValue or 0) - (barMin or 0)
        if total <= 0 then total, current = 1, 1 end
        return {
            name    = name,
            current = current,
            total   = total,
            isMax   = (standingID or 0) >= 8,
            standingLabel = _G["FACTION_STANDING_LABEL" .. tostring(standingID or "")] or "",
        }
    end
    local ok, data = pcall(C_Reputation.GetFactionDataByID, factionID)
    if not ok or not data then return nil end

    -- Friendship-style factions have their own threshold/standing
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local fok, rep = pcall(C_GossipInfo.GetFriendshipReputation, factionID)
        if fok and rep and rep.friendshipFactionID and rep.friendshipFactionID > 0 then
            local rank
            if C_GossipInfo.GetFriendshipReputationRanks then
                local rok, rankData = pcall(C_GossipInfo.GetFriendshipReputationRanks, factionID)
                if rok then rank = rankData end
            end
            local current = (rep.standing or 0) - (rep.reactionThreshold or 0)
            local total
            if rep.nextThreshold then
                total = (rep.nextThreshold or 0) - (rep.reactionThreshold or 0)
            else
                total = 1   -- max level
                current = 1
            end
            return {
                name    = rep.name or data.name or "",
                current = current,
                total   = (total and total > 0) and total or 1,
                isMax   = rep.nextThreshold == nil,
                standingLabel = rep.reaction or "",
                rankLabel = rank and rank.currentLevel and ("Rank " .. rank.currentLevel) or nil,
            }
        end
    end

    -- Standard reputation
    local current = (data.currentReactionThreshold and data.currentStanding
                     and (data.currentStanding - data.currentReactionThreshold)) or 0
    local total
    if data.nextReactionThreshold and data.currentReactionThreshold then
        total = data.nextReactionThreshold - data.currentReactionThreshold
    end
    if not total or total <= 0 then
        total = 1
        current = 1
    end
    local reactionName
    if data.reaction then
        local labels = _G.FACTION_STANDING_LABEL
        if type(labels) == "table" then
            reactionName = labels[data.reaction]
        elseif _G["FACTION_STANDING_LABEL" .. tostring(data.reaction)] then
            reactionName = _G["FACTION_STANDING_LABEL" .. tostring(data.reaction)]
        end
    end
    return {
        name    = data.name or "",
        current = current,
        total   = total,
        isMax   = not data.nextReactionThreshold,
        standingLabel = reactionName or "",
    }
end

---------------------------------------------------------------------------
-- Enumerate all tracked/visible factions for the picker dropdown
---------------------------------------------------------------------------

local function EnumeratePlayerFactions()
    local list = {}
    local n = 0
    if C_Reputation and C_Reputation.GetNumFactions then
        n = C_Reputation.GetNumFactions()
    elseif GetNumFactions then
        n = GetNumFactions()
    end
    for i = 1, n do
        local info
        if C_Reputation and C_Reputation.GetFactionDataByIndex then
            local ok, data = pcall(C_Reputation.GetFactionDataByIndex, i)
            if ok then info = data end
        elseif GetFactionInfo then
            -- Classic: only rows visible in the reputation pane are listed,
            -- so a collapsed header hides its factions from the picker.
            local name, _, _, _, _, _, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i)
            if name then info = { name = name, isHeader = isHeader, factionID = factionID } end
        end
        if info and not info.isHeader and info.factionID and info.factionID > 0 then
            list[#list + 1] = { id = info.factionID, name = info.name or ("Faction " .. info.factionID) }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local frame

function Rep:Build()
    if frame then return frame end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    -- Faction name (gold, top row)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.name:SetPoint("TOPLEFT", PAD, -4)
    f.name:SetPoint("RIGHT", -PAD, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetTextColor(unpack(CLR_NAME))
    f.name:SetWordWrap(false)

    -- Standing label (small, dim, top-right)
    f.standing = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.standing:SetPoint("TOPRIGHT", -PAD, -4)
    f.standing:SetJustifyH("RIGHT")
    f.standing:SetTextColor(unpack(CLR_DIM))

    -- Progress bar (bottom row)
    f.bar = CreateFrame("StatusBar", nil, f, "BackdropTemplate")
    f.bar:SetPoint("BOTTOMLEFT", PAD, 6)
    f.bar:SetPoint("BOTTOMRIGHT", -PAD, 6)
    f.bar:SetHeight(BAR_H)
    f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.bar:SetStatusBarColor(unpack(CLR_BAR))
    f.bar:SetMinMaxValues(0, 1)
    f.bar:SetValue(0)

    f.barBg = f.bar:CreateTexture(nil, "BACKGROUND")
    f.barBg:SetAllPoints()
    f.barBg:SetColorTexture(unpack(CLR_BG))

    f.barText = f.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.barText:SetPoint("CENTER")
    f.barText:SetTextColor(1, 1, 1)

    frame = f
    return f
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function Rep:Refresh()
    if not frame then return end
    local factionID = GetTrackedFactionID()
    local info = FetchFactionData(factionID)

    if not info then
        frame.name:SetText("|cff888888No faction selected|r")
        frame.standing:SetText("")
        frame.bar:SetValue(0)
        frame.barText:SetText("Pick one in Widget Settings")
        if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
            addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
        end
        return
    end

    frame.name:SetText(info.name)
    frame.standing:SetText(info.rankLabel or info.standingLabel or "")

    local max = math.max(info.total or 1, 1)
    frame.bar:SetMinMaxValues(0, max)
    frame.bar:SetValue(info.current or 0)

    if info.isMax then
        frame.barText:SetText("|cff40ff40Max Level|r")
    else
        frame.barText:SetText(string.format("%d / %d", info.current or 0, max))
    end

    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(WIDGET_ID)
    end
end

function Rep:GetDesiredHeight() return DESIGN_HEIGHT end

function Rep:GetStatusText()
    local info = FetchFactionData(GetTrackedFactionID())
    if not info or info.isMax then return "" end
    local pct = info.total > 0 and math.floor((info.current / info.total) * 100) or 0
    return pct .. "%", 0.85, 0.85, 0.85
end

function Rep:GetOptionsArgs()
    local args = {
        header = {
            order = 1,
            type = "header",
            name = "Tracked Faction",
        },
        intro = {
            order = 2,
            type = "lead",
            text = "Pick which faction this widget tracks. The list includes every faction you've discovered on this character.",
        },
    }

    local factions = EnumeratePlayerFactions()
    if #factions == 0 then
        args.empty = {
            order = 10,
            type = "description",
            name = "|cff888888No factions discovered yet. Visit a faction's quest hub or open the reputation pane.|r",
        }
    else
        args.picker = {
            order = 10,
            type = "select",
            name = "Faction",
            values = function()
                local vals = {}
                for _, f in ipairs(factions) do vals[f.id] = f.name end
                return vals
            end,
            get = function() return GetTrackedFactionID() end,
            set = function(_, val)
                SetTrackedFactionID(val)
                Rep:Refresh()
            end,
        }
        args.clear = {
            order = 20,
            type = "execute",
            name = "Clear Selection",
            desc = "Stop tracking any faction (widget shows a placeholder).",
            func = function()
                SetTrackedFactionID(nil)
                Rep:Refresh()
            end,
        }
    end

    return args
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function Rep:Init()
    local f = self:Build()

    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Tracked Reputation",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = f,
        GetDesiredHeight = function() return Rep:GetDesiredHeight() end,
        GetStatusText    = function() return Rep:GetStatusText() end,
        GetOptionsArgs   = function() return Rep:GetOptionsArgs() end,
    })

    f:RegisterEvent("UPDATE_FACTION")
    f:RegisterEvent("QUEST_TURNED_IN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:HookScript("OnEvent", function() Rep:Refresh() end)

    self:Refresh()
end

BazUI:QueueForLogin(function() Rep:Init() end)
