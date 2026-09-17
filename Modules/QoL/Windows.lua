-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Quality of Life: windows you can drag
--
-- The game's own panels are placed by its panel manager, which puts each
-- one where it decides and puts it back there every time it opens. That
-- is fine until you want the character sheet somewhere other than where
-- Blizzard wanted it.
--
-- Each window gets its own switch, because wanting to move the character
-- sheet says nothing about wanting to move the mailbox.
--
-- Two halves to making one movable, and the second is the one that is
-- easy to miss: the frame has to be draggable, and the position has to be
-- put back after the panel manager has had its turn. Doing only the first
-- gives a window that moves and then jumps home the next time it opens.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("QoL")
if not addon then return end

-- key       what the switch is saved under
-- label     what the page calls it
-- frame     the global the game gives it
-- loadedBy  the load-on-demand addon that creates it, where there is one
-- windowed  only draggable while it is not full screen
local WINDOWS = {
    -- The game's own settings window, which is also where this page is.
    -- It is already marked movable in Blizzard's own XML and has never
    -- had the scripts to go with it, so it has always been a window that
    -- could be dragged and never was.
    { key = "dragOptions",    label = "Options",       frame = "SettingsPanel",
      desc = "Drag the options window - the game's settings, and BazUI's own pages inside it - where you want it." },
    { key = "dragCharacter",  label = "Character",     frame = "CharacterFrame"    },
    { key = "dragSpellbook",  label = "Spellbook",     frame = "SpellBookFrame"    },
    { key = "dragQuestLog",   label = "Quest log",     frame = "QuestLogFrame"     },
    { key = "dragSocial",     label = "Social",        frame = "FriendsFrame"      },
    { key = "dragMap",        label = "World map",     frame = "WorldMapFrame",
      windowed = true,
      desc = "Drag the map where you want it. Only while it is windowed - full screen has nowhere to be dragged to." },
    { key = "dragMerchant",   label = "Vendor",        frame = "MerchantFrame"     },
    { key = "dragMail",       label = "Mailbox",       frame = "MailFrame"         },
    { key = "dragBank",       label = "Bank",          frame = "BankFrame"         },
    { key = "dragTrainer",    label = "Class trainer", frame = "ClassTrainerFrame",
      loadedBy = "Blizzard_TrainerUI" },
    { key = "dragProfession", label = "Profession",    frame = "TradeSkillFrame",
      loadedBy = "Blizzard_TradeSkillUI" },
    { key = "dragCraft",      label = "Enchanting",    frame = "CraftFrame",
      loadedBy = "Blizzard_CraftUI" },
    { key = "dragMacros",     label = "Macros",        frame = "MacroFrame",
      loadedBy = "Blizzard_MacroUI" },
    { key = "dragAuction",    label = "Auction house", frame = "AuctionFrame",
      loadedBy = "Blizzard_AuctionUI" },
}

-- Whether this one may be moved right now, which for most of them is
-- simply yes.
local function Draggable(def, frame)
    if not def.windowed then return true end
    -- The map has a full screen mode, and a full screen window has
    -- nowhere to be dragged to.
    return not frame.isMaximized
end

---------------------------------------------------------------------------
-- Where a window was left
---------------------------------------------------------------------------

local function Positions()
    local all = addon:GetSetting("windowPositions")
    if type(all) ~= "table" then
        all = {}
        addon:SetSetting("windowPositions", all)
    end
    return all
end

local function SavePosition(key, frame)
    local point, _, relPoint, x, y = frame:GetPoint()
    if not point then return end
    Positions()[key] = {
        point = point, relPoint = relPoint or point,
        x = x or 0, y = y or 0,
    }
end

-- Put it back where it was left, anchored to the screen rather than to
-- whatever the panel manager had it hanging off. Anchored to a sibling
-- panel it would move again the moment that panel opened or closed.
--
-- Answered in the same frame as whatever moved it, never a tick later.
-- The manager anchors a panel with SetPoint while it is opening it, and
-- all of that finishes before the frame is drawn - so a restore deferred
-- to the next tick draws once at Blizzard's position first, and the
-- window is visibly in its old place for an instant before it jumps.
local function Reassert(def, frame)
    if frame._bazDragBusy or frame._bazDragMoving then return end
    if not addon:Enabled(def.key) then return end
    if not Draggable(def, frame) then return end

    local pos = Positions()[def.key]
    if not pos or InCombatLockdown() then return end

    frame._bazDragBusy = true
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    frame._bazDragBusy = false
end

function addon:ClearWindowPositions()
    self:SetSetting("windowPositions", {})
    self:Print("Windows will open where the game puts them again.")
end

---------------------------------------------------------------------------
-- Making one movable
---------------------------------------------------------------------------

-- Wired once per frame. The scripts ask whether the switch is on when
-- they fire rather than being attached and detached as it moves, so a
-- switch that is off leaves the window behaving exactly as the game
-- intended.
local function Wire(def, frame)
    if frame._bazDragWired then return end
    frame._bazDragWired = true

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:HookScript("OnDragStart", function(self)
        if not addon:Enabled(def.key) then return end
        if not Draggable(def, self) then return end
        if InCombatLockdown() then return end
        self._bazDragMoving = true
        self:StartMoving()
    end)

    frame:HookScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if addon:Enabled(def.key) then SavePosition(def.key, self) end
        self._bazDragMoving = nil
    end)

    -- Two ways in, because the windows are not all the same kind. A
    -- panel the manager owns is anchored every time it opens, and the
    -- hook below catches that anchoring as it happens. A window the
    -- manager has never heard of - the options panel - is never anchored
    -- again after the XML placed it, so it needs asking on the way up.
    frame:HookScript("OnShow", function(self) Reassert(def, self) end)
    hooksecurefunc(frame, "SetPoint", function(self) Reassert(def, self) end)
end

-- Wire it if it is there, and wait for its addon if it is not. Called
-- when the switch is thrown and again at login, so a window whose addon
-- loads later is picked up when it arrives.
local function Apply(def)
    local frame = _G[def.frame]
    if frame then
        Wire(def, frame)
        return
    end
    if not def.loadedBy or def._waiting then return end
    def._waiting = true
    if EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded(def.loadedBy, function()
            local late = _G[def.frame]
            if late then Wire(def, late) end
        end)
    end
end

---------------------------------------------------------------------------
-- The switches
--
-- Only offered for a window this client actually has. A switch for a
-- panel that does not exist is a switch that cannot do anything, and
-- which of these exist is a question about the flavour rather than
-- something to assume.
---------------------------------------------------------------------------

local function Installed(name)
    local GetInfo = C_AddOns and C_AddOns.GetAddOnInfo or _G.GetAddOnInfo
    if not GetInfo then return false end
    local ok, title = pcall(GetInfo, name)
    return ok and title and true or false
end

for index, def in ipairs(WINDOWS) do
    if _G[def.frame] or (def.loadedBy and Installed(def.loadedBy)) then
        addon:RegisterTweak({
            key     = def.key,
            label   = def.label,
            desc    = def.desc
                or ("Drag the " .. def.label:lower()
                    .. " window where you want it. It opens there from then on."),
            section = "windows",
            order   = index,
            OnApply = function(enabled)
                if enabled then Apply(def) end
            end,
        })
    end
end

addon.DRAGGABLE_WINDOWS = WINDOWS
