-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: LibDataBroker feeds (from BazBrokerWidget)
--
-- Every LibDataBroker-1.1 data object, whether a `data source` or a
-- `launcher`, becomes its own dockable widget:
--
--   [icon]  Label                    Value
--
-- Clicks forward to the feed's OnClick, hover shows its tooltip, and
-- text / value / icon / label changes re-render the widget live. Feeds
-- that register after login are picked up as they appear.
--
-- BazUI does not ship the library. Feeds only exist when another addon
-- publishes them, and that addon brings LibDataBroker along; if none
-- does, this file registers nothing.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local DESIGN_WIDTH  = 200
local DESIGN_HEIGHT = 22
local ICON_SIZE     = 16
local PAD           = 4
local ID_PREFIX     = "bazdrawer_ldb_"

local Broker = {}
addon.Broker = Broker

local LDB
local feeds = {}      -- [feedName] = { frame = frame, dataobj = dataobj }

local function Settings()
    return addon:GetSetting("broker") or {}
end

local function GetLDB()
    if LDB then return LDB end
    if LibStub and LibStub.GetLibrary then
        LDB = LibStub:GetLibrary("LibDataBroker-1.1", true)
    end
    return LDB
end

local function SafeStr(v)
    if v == nil then return "" end
    if type(v) == "string" then return v end
    return tostring(v)
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function ApplyIcon(frame, dataobj)
    if Settings().showIcon == false or not dataobj.icon then
        frame.icon:Hide()
        return
    end
    frame.icon:SetTexture(dataobj.icon)
    if dataobj.iconCoords then
        frame.icon:SetTexCoord(unpack(dataobj.iconCoords))
    else
        frame.icon:SetTexCoord(0, 1, 0, 1)
    end
    if dataobj.iconR and dataobj.iconG and dataobj.iconB then
        frame.icon:SetVertexColor(dataobj.iconR, dataobj.iconG, dataobj.iconB)
    else
        frame.icon:SetVertexColor(1, 1, 1)
    end
    frame.icon:Show()
end

local function ApplyText(frame, dataobj)
    -- Some feeds publish only `value` + `suffix`, others a pre-formatted
    -- `text`. Prefer `text`, fall back to `value suffix`.
    local valueText = dataobj.text
    if not valueText or valueText == "" then
        local v = dataobj.value
        if v ~= nil and v ~= "" then
            local s = dataobj.suffix
            valueText = s and (SafeStr(v) .. " " .. SafeStr(s)) or SafeStr(v)
        end
    end
    if not valueText or valueText == "" then
        valueText = Settings().emptyText or "-"
    end
    frame.value:SetText(valueText)
end

local function ApplyLabel(frame, name, dataobj)
    if Settings().showLabel == false then
        frame.label:SetText("")
        return
    end
    local label = dataobj.label
    if not label or label == "" then label = name end
    frame.label:SetText(label)
end

local function Render(name)
    local entry = feeds[name]
    if not entry then return end
    ApplyIcon(entry.frame, entry.dataobj)
    ApplyLabel(entry.frame, name, entry.dataobj)
    ApplyText(entry.frame, entry.dataobj)
    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus(ID_PREFIX .. name)
    end
end

local function BuildFrame(name, dataobj)
    local frame = CreateFrame("Button", "BazUIDrawerBroker_" .. name:gsub("%W", "_"), UIParent)
    frame:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)
    frame:RegisterForClicks("AnyUp")
    frame:EnableMouse(true)

    local hover = frame:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0)
    frame.hover = hover

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", PAD, 0)
    frame.icon = icon

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", icon, "RIGHT", PAD, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(0.85, 0.85, 0.85)
    label:SetWordWrap(false)
    label:SetNonSpaceWrap(false)
    frame.label = label

    local value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    value:SetPoint("RIGHT", -PAD, 0)
    value:SetJustifyH("RIGHT")
    value:SetTextColor(1, 0.82, 0)
    frame.value = value

    -- The label may not run under the value.
    label:SetPoint("RIGHT", value, "LEFT", -PAD, 0)

    frame:SetScript("OnClick", function(self, button)
        if dataobj.OnClick then
            local ok, err = pcall(dataobj.OnClick, self, button)
            if not ok then geterrorhandler()(err) end
        end
    end)
    -- LDB feeds expose either OnEnter (their own tooltip) or OnTooltipShow
    -- (fills the GameTooltip we own).
    frame:SetScript("OnEnter", function(self)
        self.hover:SetColorTexture(1, 1, 1, 0.06)
        if dataobj.OnEnter then
            pcall(dataobj.OnEnter, self)
        elseif dataobj.OnTooltipShow then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            pcall(dataobj.OnTooltipShow, GameTooltip)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        self.hover:SetColorTexture(1, 1, 1, 0)
        if dataobj.OnLeave then
            pcall(dataobj.OnLeave, self)
        else
            GameTooltip:Hide()
        end
    end)
    return frame
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

function Broker:Build(name, dataobj)
    if feeds[name] or type(name) ~= "string" or type(dataobj) ~= "table" then return end
    local id = ID_PREFIX .. name

    -- First sight of a feed decides its enabled flag explicitly, so the
    -- "auto-enable new feeds" setting is honoured whatever the profile's
    -- default mode for unknown widgets is.
    local enabledMap = addon:GetSetting("widgetEnabled")
    if type(enabledMap) == "table" and enabledMap[id] == nil then
        enabledMap[id] = Settings().autoEnableNew ~= false
    end

    local frame = BuildFrame(name, dataobj)
    feeds[name] = { frame = frame, dataobj = dataobj }
    Render(name)

    BazUI:RegisterDockableWidget({
        id           = id,
        label        = dataobj.label or name,
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = frame,
        -- Every feed sits in one "LibDataBroker" group on the Widgets page
        -- instead of each publishing addon getting a one-widget group.
        source = "LibDataBroker",
        tags   = { { text = "LDB", color = "60a0ff" } },
        GetStatusText = function()
            return frame.value:GetText() or "", 1, 0.82, 0
        end,
    })

    local ldb = GetLDB()
    local function OnAttr(_, _, _, _, dobj)
        if dobj == dataobj then Render(name) end
    end
    for _, attr in ipairs({ "text", "value", "label", "icon" }) do
        ldb.RegisterCallback(frame, "LibDataBroker_AttributeChanged_" .. name .. "_" .. attr, OnAttr)
    end
end

-- Create widgets for every feed the registry knows. Returns the count
-- of feeds, or nil when LibDataBroker isn't loaded at all.
function Broker:Rescan(announce)
    local ldb = GetLDB()
    if not ldb then
        if announce then addon:Print("LibDataBroker is not loaded; no addon is publishing feeds.") end
        return nil
    end
    local count = 0
    for name, dataobj in ldb:DataObjectIterator() do
        count = count + 1
        self:Build(name, dataobj)
    end
    if announce then addon:Print(("%d LibDataBroker feed%s registered."):format(count, count == 1 and "" or "s")) end
    return count
end

function Broker:Refresh()
    for name in pairs(feeds) do Render(name) end
end

function Broker:PrintList()
    local ldb = GetLDB()
    if not ldb then
        addon:Print("LibDataBroker is not loaded; no addon is publishing feeds.")
        return
    end
    local count = 0
    addon:Print("LibDataBroker feeds:")
    for name, dataobj in ldb:DataObjectIterator() do
        count = count + 1
        print(("  |cff8888ff%d.|r %s |cff999999(%s)|r - %s"):format(count, name, dataobj.type or "unknown", dataobj.label or name))
    end
    if count == 0 then print("  None. Load an addon that publishes LibDataBroker data.") end
end

---------------------------------------------------------------------------
-- Settings page (registered from Settings.lua as "Broker Feeds")
---------------------------------------------------------------------------

local function Toggle(order, key, name, desc)
    return {
        order = order, type = "toggle", name = name, desc = desc,
        get = function() return Settings()[key] ~= false end,
        set = function(_, val)
            local s = Settings(); s[key] = val and true or false
            addon:SetSetting("broker", s)
            Broker:Refresh()
        end,
    }
end

function Broker.GetOptionsTable()
    return {
        name = "Broker Feeds",
        type = "group",
        args = {
            intro = {
                order = 0.1, type = "lead",
                text = "Any addon that publishes a LibDataBroker feed (Bagnon, Recount, BugSack and most addons with a minimap data button) shows up as its own widget on the Widgets page, in the LibDataBroker group. Enable, reorder and float them like any other widget.",
            },
            displayHeader = { order = 1, type = "header", name = "Display" },
            showIcon  = Toggle(2, "showIcon",  "Show Icon",  "Show the feed's icon at the left of its widget."),
            showLabel = Toggle(3, "showLabel", "Show Label", "Show the feed's label next to its value."),
            emptyText = {
                order = 4, type = "input", name = "Empty-Value Placeholder",
                desc = "Shown when a feed has no value yet.",
                get = function() return Settings().emptyText or "-" end,
                set = function(_, val)
                    local s = Settings(); s.emptyText = val
                    addon:SetSetting("broker", s)
                    Broker:Refresh()
                end,
            },
            discoveryHeader = { order = 10, type = "header", name = "Discovery" },
            autoEnableNew = Toggle(11, "autoEnableNew", "Auto-Enable New Feeds",
                "Turn a feed's widget on the first time it is seen. Off leaves new feeds disabled until you enable them on the Widgets page."),
            rescan = {
                order = 12, type = "execute", name = "Rescan Feeds",
                desc = "Check the registry again and create widgets for any feed that was missed.",
                func = function() Broker:Rescan(true) end,
            },
            printFeeds = {
                order = 13, type = "execute", name = "Print Feed List",
                desc = "List every registered feed in the chat frame.",
                func = function() Broker:PrintList() end,
            },
        },
    }
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

BazUI:QueueForLogin(function()
    local ldb = GetLDB()
    if not ldb then return end
    -- Many addons register their feed after login; catch those as they arrive.
    ldb.RegisterCallback(Broker, "LibDataBroker_DataObjectCreated", function(_, name, dataobj)
        Broker:Build(name, dataobj)
    end)
    Broker:Rescan()
end)
