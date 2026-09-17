-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI taint scanner
--
-- Forever's own taint log came back empty twice, so this asks the client
-- directly instead. issecurevariable(name) and issecurevariable(table, key)
-- both report whether a value is still Blizzard's and, when it is not, which
-- addon took it over. That is the same answer Logs/taint.log was meant to
-- give, available live and without a reload.
--
-- The report names what BazUI has claimed, so a fix has something concrete
-- to aim at: a global we assigned or hooked, or a field we wrote onto one of
-- their frames.
---------------------------------------------------------------------------

local Taint = {}
BazUI.Taint = Taint

local ME = "BazUI"

---------------------------------------------------------------------------
-- What to look at
--
-- The Edit Mode entry path, which is where the errors land: the panel
-- manager opens the manager frame, EditModeFrameSetup walks the action
-- bars and status bars, then the compact party frames.
---------------------------------------------------------------------------

Taint.GLOBALS = {
    -- Panel manager / game menu, the outer half of the stack
    "ShowUIPanel", "HideUIPanel", "CloseAllWindows", "CloseWindows",
    "CloseSpecialWindows", "CloseAllBags", "UpdateUIPanelPositions",
    "FramePositionDelegate", "UIParent", "GameMenuFrame", "UISpecialFrames",
    "ToggleGameMenu", "UIPanelWindows", "UIMenus",

    -- Edit Mode
    "EditModeManagerFrame", "EnterEditMode", "ExitEditMode",
    "EditModeManagerFrameMixin", "EditModeAccountSettingsMixin",

    -- Things EditModeFrameSetup reads by name
    "MainActionBar", "MainMenuBar", "MainMenuBarArtFrame", "StanceBar",
    "PetActionBar", "PossessActionBar", "MultiBarBottomLeft",
    "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
    "StatusTrackingBarManager", "StatusTrackingBarInfo",
    "SecondaryStatusTrackingBarContainer", "MainMenuExpBar",
    "ReputationWatchBar", "ExhaustionTick",

    -- Compact frames, where the error surfaces
    "CompactPartyFrame", "CompactRaidFrameContainer",
    "CompactUnitFrame_UpdateHealthColor", "CompactUnitFrame_UpdateAll",
    "CompactUnitFrame_SetUpFrame", "DefaultCompactUnitFrameSetup",

    -- Globals BazUI is known to hook or replace somewhere
    "ClearCursor", "UpdateMicroButtons", "MicroButtonPulse",
    "MicroButtonPulseStop", "ToggleBackpack", "OpenBag", "OpenAllBags",
    "CloseBackpack", "ToggleAllBags", "DEFAULT_CHAT_FRAME",
    "GameTooltip_SetDefaultAnchor", "AlertFrame", "UIErrorsFrame",
    "RaidWarningFrame", "ObjectiveTrackerFrame",
}

-- Frames whose own fields are worth walking. Anything BazUI wrote onto one
-- of these shows up as ours the moment Blizzard reads it back.
Taint.FRAMES = {
    "EditModeManagerFrame", "StatusTrackingBarManager", "MainActionBar",
    "MainMenuBar", "StanceBar", "PetActionBar", "MainMenuBarArtFrame",
    "SecondaryStatusTrackingBarContainer", "CompactPartyFrame",
    "FramePositionDelegate", "UIParent", "GameMenuFrame",
}

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------

-- issecurevariable raises on a few argument shapes rather than returning,
-- so every call goes through here and an unanswerable name is simply left
-- out of the report.
local function Ask(a, b)
    if not _G.issecurevariable then return nil end
    local ok, secure, who
    if b == nil then
        ok, secure, who = pcall(_G.issecurevariable, a)
    else
        ok, secure, who = pcall(_G.issecurevariable, a, b)
    end
    if not ok then return nil end
    return secure and true or false, who
end

-- Returns a list of { name = ..., owner = ... } for every named global that
-- is no longer Blizzard's. `owner` is the addon that claimed it, or nil when
-- the client does not say.
function Taint.ScanGlobals(names)
    local found = {}
    for _, name in ipairs(names or Taint.GLOBALS) do
        if _G[name] ~= nil then
            local secure, who = Ask(name)
            if secure == false then
                found[#found + 1] = { name = name, owner = who }
            end
        end
    end
    return found
end

-- Returns a list of { name = "Frame.field", owner = ... } for every field on
-- `frame` that is no longer Blizzard's. Fields whose value is itself a table
-- are not descended into: one level is enough to name the write, and walking
-- deeper on UIParent never ends.
function Taint.ScanFrame(frameName)
    local frame = _G[frameName]
    if type(frame) ~= "table" then return {} end
    local found = {}
    local ok = pcall(function()
        for key in pairs(frame) do
            if type(key) == "string" then
                local secure, who = Ask(frame, key)
                if secure == false then
                    found[#found + 1] = { name = frameName .. "." .. key, owner = who }
                end
            end
        end
    end)
    if not ok then return {} end
    return found
end

---------------------------------------------------------------------------
-- The report
--
-- `onlyUs` limits it to what BazUI itself claimed, which is the usual
-- question. Everything else is another addon's business and only adds noise.
---------------------------------------------------------------------------

function Taint.Report(onlyUs)
    if not _G.issecurevariable then
        BazUI:Print("|cffff4444issecurevariable is not available on this client.|r")
        return
    end

    local function Keep(entry)
        if not onlyUs then return true end
        return entry.owner == ME
    end

    local function Line(entry)
        print("  |cffffd700" .. entry.name .. "|r  <- " .. (entry.owner or "unknown"))
    end

    local hits = 0

    local globals = Taint.ScanGlobals()
    local shown = false
    for _, entry in ipairs(globals) do
        if Keep(entry) then
            if not shown then print("|cff00ff00Globals no longer Blizzard's:|r"); shown = true end
            Line(entry)
            hits = hits + 1
        end
    end

    for _, frameName in ipairs(Taint.FRAMES) do
        local fields = Taint.ScanFrame(frameName)
        local header = false
        for _, entry in ipairs(fields) do
            if Keep(entry) then
                if not header then
                    print("|cff00ff00Fields written onto " .. frameName .. ":|r")
                    header = true
                end
                Line(entry)
                hits = hits + 1
            end
        end
    end

    if hits == 0 then
        BazUI:Print(onlyUs
            and "Nothing in the Edit Mode path belongs to BazUI."
            or  "Nothing in the Edit Mode path is tainted.")
    else
        BazUI:Print(hits .. " tainted " .. (hits == 1 and "value" or "values")
            .. (onlyUs and " claimed by BazUI." or " found."))
    end
end
