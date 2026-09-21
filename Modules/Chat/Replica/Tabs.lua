-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: Tabs (TabSystem, channel detection, chat-type routing)
--
-- Owns the modern TabSystemTemplate / TabSystemTopButtonTemplate strip
-- shared by every chat window. The selected tab grows taller and glows;
-- unselected tabs are dimmer (all native, no custom rendering).
--
-- Also owns the channel-related helpers (Trade tab visibility based
-- on whether the player can currently use a Trade channel) and the
-- per-tab chat-type binding that routes Enter to the right channel
-- (Guild tab → /g, Trade tab → /<trade-id>, etc.).
--
-- Public API (on addon.Tabs):
--   :Ensure(firstWindow)                -- lazy-create the TabSystem
--   :AddFor(window, index, label)       -- add one tab; returns tabID
--   :UpdateVisibility()                 -- re-evaluate Trade tab show/hide
--   :ApplyChatType(editBox, group)      -- set chat type/channel on editbox
--   :IsTradeUsable()                    -- player can use Trade channel
--   .system                             -- the TabSystem frame (read-only)
--   .addBtn                             -- the floating "+" button (read-only)
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

-- How far the first tab sits in from the chat window's left edge.
local TAB_STRIP_INDENT = 4


local Tabs = {}
addon.Tabs = Tabs

---------------------------------------------------------------------------
-- Which way a tab group runs
--
-- A dock instance - the main one, or any window a tab was popped out
-- into - is a tab group, and each has its own strip. Left to right by
-- default, against the window's left edge, with the add button after the
-- last tab.
--
-- Reversed, the whole group mirrors: the strip hangs off the right edge,
-- the tabs run leftward from it, and the add button moves to the far end
-- so it stays where the next tab would appear. Per group, because the
-- point of it is a window docked on the right-hand side of a screen.
---------------------------------------------------------------------------

-- Which group a tab belongs to. A method rather than one of the file's
-- local helpers, so the menu above can reach it without caring which of
-- them was declared first.
function Tabs:GroupIDFor(idx)
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    local ws = p and p.windows and p.windows[idx]
    return (ws and ws.dockID) or "dock"
end

function Tabs:IsGroupReversed(dockID)
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    local d = p and p.docks and p.docks[dockID or "dock"]
    return (d and d.reverseTabs) and true or false
end

function Tabs:SetGroupReversed(dockID, on)
    dockID = dockID or "dock"
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    if not p then return end
    p.docks = p.docks or {}
    p.docks[dockID] = p.docks[dockID] or {}
    p.docks[dockID].reverseTabs = on and true or nil
    self:ApplyGroupFlow(dockID)
end

-- Put a group the way round it is meant to be: the strip's own edge, the
-- direction its tabs run, and which side the add button sits on.
function Tabs:ApplyGroupFlow(dockID)
    dockID = dockID or "dock"
    local inst = addon.Window and addon.Window.docks
        and addon.Window.docks[dockID]
    local ts = inst and inst.tabSystem
    if not ts then return end

    local reverse = self:IsGroupReversed(dockID)
    local frame = inst.frame
    local Chrome = addon.Chrome

    if ts.SetReverseFlow then ts:SetReverseFlow(reverse) end

    if frame then
        ts:ClearAllPoints()
        if reverse then
            local right = (Chrome and Chrome.INSET_RIGHT) or 26
            ts:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT",
                right - TAB_STRIP_INDENT, 9)
        else
            local left = (Chrome and Chrome.INSET_LEFT) or 10
            ts:SetPoint("BOTTOMLEFT", frame, "TOPLEFT",
                -left + TAB_STRIP_INDENT, 9)
        end
    end

    local addBtn = inst.addBtn or ts.addBtn
    if addBtn then
        addBtn:ClearAllPoints()
        if reverse then
            addBtn:SetPoint("BOTTOMRIGHT", ts, "BOTTOMLEFT", -4, 0)
        else
            addBtn:SetPoint("BOTTOMLEFT", ts, "BOTTOMRIGHT", 4, 0)
        end
    end

    if ts.MarkDirty then ts:MarkDirty() end
end

---------------------------------------------------------------------------
-- chat-tab context menu section
--
-- Registered against the shared "chat-tab" scope so the BazChat
-- entries (Channels / Clear / Delete) sit alongside any other addon
-- that wants to extend tab behavior (BazTooltipEditor's Inspect,
-- a future log-archiver, etc.). Tabs.lua's OnMouseUp hook below
-- opens the menu on right-click.
---------------------------------------------------------------------------

local function GetBazChatSection(ctx)
    if not ctx or not ctx.index then return end
    local idx = ctx.index
    local tab = ctx.tab

    local items = {
        {
            label = "Rename...",
            onClick = function()
                local p = (addon.db and addon.db.profile)
                    or (addon.core and addon.core.db and addon.core.db.profile)
                local ws = p and p.windows and p.windows[idx]
                if not ws then return end
                local current = ws.label or ("Tab " .. idx)
                BazUI:OpenPopup({
                    title  = "Rename tab",
                    width  = 360,
                    fields = {
                        { type    = "input",
                          key     = "name",
                          label   = "Name",
                          default = current },
                    },
                    buttons = {
                        { label = "Cancel", style = "default" },
                        { label = "Save",   style = "primary",
                          onClick = function(values)
                              local newLabel = values and values.name
                              if not newLabel or newLabel == "" then return end
                              ws.label = newLabel
                              -- Refresh the live tab button on whichever
                              -- strip is hosting it.
                              if addon.Tabs and addon.Tabs.GetTabFor then
                                  local t = addon.Tabs:GetTabFor(idx)
                                  if t and t.Init then t:Init(idx, newLabel) end
                              end
                              -- Refresh the BazUI Tabs options page
                              -- if it's open.
                              if BazUI.RefreshOptions then
                                  BazUI:RefreshOptions("BazUIChat-Tabs")
                              end
                          end },
                    },
                })
            end,
        },
        {
            label = "Channels...",
            onClick = function()
                if addon.Channels and addon.Channels.ShowPopup and tab then
                    addon.Channels:ShowPopup(tab, idx)
                end
            end,
        },
        {
            label = "Clear messages",
            onClick = function()
                local w = addon.Window and addon.Window.Get and addon.Window:Get(idx)
                if w and w.Clear then w:Clear() end
            end,
        },
    }

    -- Lock / unlock toggle for the container holding this tab. When
    -- unlocked, the chat window can be drag-moved + resized directly
    -- without entering Edit Mode.
    if addon.Window and addon.Window.IsContainerLocked then
        local Wins   = addon.Window
        local p      = (addon.db and addon.db.profile)
            or (addon.core and addon.core.db and addon.core.db.profile)
        local ws     = p and p.windows and p.windows[idx]
        local dockID = (ws and ws.dockID) or "dock"
        local locked = Wins:IsContainerLocked(dockID)
        items[#items + 1] = {
            label   = locked and "Unlock window" or "Lock window",
            onClick = function()
                if Wins.ToggleContainerLocked then
                    Wins:ToggleContainerLocked(dockID)
                end
            end,
        }
    end

    -- "Move to" submenu: lists every existing container plus a
    -- "New window" entry that creates a fresh popped container. The
    -- tab's current container is hidden from the list (no-op move).
    -- Tab 1 (General) is the dock's anchor and can't be moved.
    if idx > 1 and addon.Window and addon.Window.ListContainers then
        local Wins         = addon.Window
        local currentID    = Wins.IsPopped and (
            (function()
                local p = (addon.db and addon.db.profile)
                    or (addon.core and addon.core.db and addon.core.db.profile)
                local ws = p and p.windows and p.windows[idx]
                return ws and ws.dockID or "dock"
            end)()
        ) or "dock"
        local hasSiblings  = Wins.HasSiblingsInContainer
            and Wins:HasSiblingsInContainer(idx)

        local moveItems = {}
        for _, c in ipairs(Wins:ListContainers()) do
            if c.id ~= currentID then
                local destID = c.id
                moveItems[#moveItems + 1] = {
                    label = c.label,
                    onClick = function()
                        if Wins.MoveTab then Wins:MoveTab(idx, destID) end
                    end,
                }
            end
        end
        -- "New window" splits the tab into a fresh popped container.
        -- For a tab alone in a popped container, this is a no-op
        -- (PopOut early-returns without siblings) so we hide it then.
        if currentID == "dock" or hasSiblings then
            if #moveItems > 0 then
                moveItems[#moveItems + 1] = { divider = true }
            end
            moveItems[#moveItems + 1] = {
                label = "New window (pop out)",
                onClick = function()
                    if Wins.PopOut then Wins:PopOut(idx) end
                end,
            }
        end

        if #moveItems > 0 then
            items[#items + 1] = {
                label   = "Move to",
                submenu = moveItems,
            }
        end
    end

    -- The group's own setting, offered on every tab in it rather than
    -- just the first: whichever one you happened to right-click is the
    -- one you were looking at.
    do
        local groupID = Tabs:GroupIDFor(idx)
        local reversed = Tabs:IsGroupReversed(groupID)
        items[#items + 1] = { divider = true }
        items[#items + 1] = {
            label   = reversed and "Run tabs left to right" or "Run tabs right to left",
            onClick = function() Tabs:SetGroupReversed(groupID, not reversed) end,
        }
    end

    -- Tab 1 is the protected default; deletion would orphan the dock
    -- chrome. DeleteTab itself guards this but skipping the entry on
    -- the first tab keeps the menu tidy.
    if idx > 1 then
        items[#items + 1] = {
            label = "Delete tab",
            onClick = function()
                if addon.Tabs and addon.Tabs.DeleteTab then
                    addon.Tabs:DeleteTab(idx)
                end
            end,
        }
    end

    return items
end

if BazUI and BazUI.RegisterContextMenuSection then
    BazUI:RegisterContextMenuSection("chat-tab", "Chat", GetBazChatSection)
end

---------------------------------------------------------------------------
-- DB / window-list accessors
--
-- These mirror the helpers in Window.lua. Both addon.db and
-- addon.core.db paths are checked: BazUI's onReady (which sets
-- addon.db) fires AFTER QueueForLogin callbacks, so during boot
-- addon.core.db is the only populated path.
---------------------------------------------------------------------------

local function WindowDB(idx)
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    return p and p.windows and p.windows[idx] or nil
end

local function WindowList()
    return (addon.Window and addon.Window.list) or {}
end

---------------------------------------------------------------------------
-- Channel detection (Trade tab visibility + chat-type routing)
---------------------------------------------------------------------------

-- The runtime ID of a zone channel, or nothing.
--
-- Realms decorate these names: "General", "General - Elwynn Forest",
-- "Trade", "Trade - City", "Trade (Services)". So the word has to start
-- the name and be followed by a separator rather than by more word -
-- searching for "trade" anywhere in the name also finds
-- TradeSkillMaster and every custom channel anybody has called tradehub,
-- which is how a Trade tab came to be sitting there in the middle of the
-- Wetlands.
--
-- Read only from the channel list, which is what you are actually in,
-- and only counting channels that are live. Leaving a capital does not
-- always take the channel out of the list - it can be left there marked
-- disabled, which is a channel you cannot say anything in.
local function FindZoneChannelID(word)
    if not (GetChannelList and word) then return nil end
    local want = word:lower()

    local channels = { GetChannelList() }
    for i = 1, #channels, 3 do
        local id, name, disabled = channels[i], channels[i + 1], channels[i + 2]
        if id and not disabled and type(name) == "string" then
            local lower = name:lower()
            if lower == want or lower:match("^" .. want .. "[%s%-%(]") then
                return id
            end
        end
    end
    return nil
end

local function FindTradeChannelID()
    return FindZoneChannelID("trade")
end

-- Blizzard joins you to the Trade channel when you enter a capital, so
-- "is Trade usable" is "am I in a live Trade channel". Works on every
-- client flavour; the zone PvP type does not (Classic capitals are not
-- sanctuaries).
function Tabs:IsTradeUsable()
    return FindTradeChannelID() ~= nil
end

-- Native chatType per event group. LOOT (Trade tab) is special-cased
-- in ResolveChatType because it depends on the player's current zone.
local CHAT_TYPE_BY_GROUP = {
    GENERAL = "SAY",   -- only when there is no General channel to join
    GUILD   = "GUILD",
    LOOT    = "SAY",   -- only used outside cities; cities use CHANNEL
    LOG     = "SAY",   -- LOG tab is read-only, but we still set
                       -- something defensive in case the editbox shows
}

-- Tabs named after a channel send to that channel.
--
-- Guild goes to /g and Trade to the Trade channel, so General going to
-- /say made it the odd one out - a tab named after a channel that typed
-- somewhere else. Both are resolved at the moment you press Enter rather
-- than remembered, because a zone channel's ID changes as you travel.
--
-- Falling back to /say when the channel is not there is the important
-- half: outside a city there is no Trade channel, and there are places
-- with no General either. Better to say it out loud than to send it
-- nowhere.
local CHANNEL_BY_GROUP = {
    GENERAL = "general",
    LOOT    = "trade",
}

local function ResolveChatType(group)
    local channelWord = CHANNEL_BY_GROUP[group]
    if channelWord then
        local id = FindZoneChannelID(channelWord)
        if id then return "CHANNEL", id end
        return "SAY", nil
    end
    return CHAT_TYPE_BY_GROUP[group] or "SAY", nil
end

-- Apply a (chatType, channelTarget) to an edit box and refresh its
-- header. Sets BOTH the legacy `.chatType` field and the modern frame
-- attributes that ChatEdit_UpdateHeader reads.
function Tabs:ApplyChatType(editBox, group)
    local chatType, channelTarget = ResolveChatType(group)
    editBox.chatType = chatType
    editBox:SetAttribute("chatType", chatType)
    if chatType == "CHANNEL" then
        editBox:SetAttribute("channelTarget", channelTarget)
        editBox:SetAttribute("chatTarget", nil)
    else
        editBox:SetAttribute("channelTarget", nil)
        editBox:SetAttribute("chatTarget", nil)
    end
    if ChatEdit_UpdateHeader then
        ChatEdit_UpdateHeader(editBox)
    end
end

---------------------------------------------------------------------------
-- Dynamic tab visibility (autoShow)
--
-- Each tab's `autoShow` field declares when the tab should be visible:
--   "always"   - always shown (default for General / Log)
--   "city"     - only while a Trade channel is joined (capitals) - default for Trade
--   "guild"    - only while in a guild - default for Guild
--   "party"    - only when in a party
--   "raid"     - only when in a raid
--   "combat"   - only during combat
--   "pvp"      - only in battlegrounds / arenas
--   "instance" - only in dungeons / raids / scenarios
--
-- :UpdateVisibility iterates all tabs, evaluates each predicate, and
-- shows/hides the tab to match. If the currently-active tab gets
-- hidden, we fall back to General (idx 1).
--
-- Re-fired on zone change, combat start/end, party/raid roster update,
-- and joining or leaving a guild.
-- Wiring lives in Window:CreateDock's watcher frame.
---------------------------------------------------------------------------

local function ShouldShowTab(autoShow)
    if not autoShow or autoShow == "always" then return true end
    if autoShow == "city" then
        return Tabs:IsTradeUsable()
    end
    if autoShow == "guild" then
        return IsInGuild and IsInGuild() or false
    end
    if autoShow == "raid" then
        return IsInRaid and IsInRaid() or false
    end
    if autoShow == "party" then
        -- Match Blizzard convention: "in a party" = grouped but not in raid
        return IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) or false
    end
    if autoShow == "combat" then
        return InCombatLockdown and InCombatLockdown() or false
    end
    if autoShow == "pvp" then
        local _, instanceType = IsInInstance()
        return instanceType == "pvp" or instanceType == "arena"
    end
    if autoShow == "instance" then
        local inInstance = IsInInstance and IsInInstance() or false
        return inInstance and true or false
    end
    return true
end

function Tabs:UpdateVisibility()
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    local Wins = addon.Window
    local docks = Wins and Wins.docks
    if not docks then return end

    -- For each dock instance, walk its strip. A tab is shown if
    -- its window's autoShow predicate is true AND its profile dockID
    -- matches the strip's dockID (so a stale tab on the wrong strip
    -- - shouldn't happen but defensive - hides itself). Deleted tabs
    -- (no profile entry) and tabs with no _windowIdx back-reference
    -- (severed by DeleteTab / MoveTab) are unconditionally hidden.
    for stripDockID, inst in pairs(docks) do
        local ts = inst.tabSystem
        if ts and ts.tabs then
            local layoutChanged, activeNeedsSwap = false, false
            for tID, tab in ipairs(ts.tabs) do
                local idx = self:WindowIdxOf(ts, tID)
                local ws  = idx and p and p.windows and p.windows[idx]
                local should
                if not ws or not tab._windowIdx then
                    -- Tab no longer has a profile entry (deleted) or
                    -- has been severed by a migration - leave hidden.
                    should = false
                else
                    local rightStrip = (ws.dockID or "dock") == stripDockID
                    should = rightStrip and ShouldShowTab(ws.autoShow)
                end
                if tab:IsShown() ~= should then
                    tab:SetShown(should)
                    layoutChanged = true
                    if not should and ts.selectedTabID == tID then
                        activeNeedsSwap = true
                    end
                end
            end
            if layoutChanged and ts.MarkDirty then ts:MarkDirty() end
            if activeNeedsSwap then
                -- Pick any other visible tab on the same strip; falls
                -- back to tabID 1 if everything's hidden (rare edge).
                local fallback
                for i = 1, #ts.tabs do
                    if ts.tabs[i]:IsShown() then fallback = i; break end
                end
                ts:SetTab(fallback or 1, false)
            end
        end
    end
end

---------------------------------------------------------------------------
-- TabSystem construction
---------------------------------------------------------------------------
--
-- Each dock instance (main "dock" or a popped "pop:N") gets its own
-- tab strip + "+" button. Tabs:EnsureFor(dockInstance) lazily builds
-- both and stashes them on the instance struct. Tabs:AddFor reads
-- windows[idx].dockID to pick the right strip.
--
-- TabSystem assigns tabIDs sequentially per-strip starting at 1, so
-- in a popped strip with two windows the first tab has ID 1 even if
-- it represents window 5. We always store the authoritative window
-- index on tab._windowIdx; helpers below resolve back through it.
---------------------------------------------------------------------------

local function DockIDForWindow(idx)
    local ws = WindowDB(idx)
    return (ws and ws.dockID) or "dock"
end

-- tabID -> windowIdx for a given strip. Falls back to tabID when the
-- back-reference is missing (early boot / migration edge).
function Tabs:WindowIdxOf(strip, tabID)
    if not (strip and strip.tabs and strip.tabs[tabID]) then return nil end
    return strip.tabs[tabID]._windowIdx or tabID
end

-- Find a tab button by window index, scanning every dock instance's
-- strip. Returns (tab, strip, tabID) or nil if no strip holds it.
function Tabs:GetTabFor(windowIdx)
    local Wins = addon.Window
    if not (Wins and Wins.docks) then return nil end
    for _, inst in pairs(Wins.docks) do
        local s = inst.tabSystem
        if s and s.tabs then
            for tID, tab in ipairs(s.tabs) do
                if (tab._windowIdx or tID) == windowIdx then
                    return tab, s, tID
                end
            end
        end
    end
    return nil
end

local function BuildAddButton(ts, dockID)
    -- Floating "+" button to the right of the tab strip. Just a gold
    -- "+" glyph, no tab chrome (avoids the doubled-shadow problems
    -- that came from squeezing TabSystemTopButtonTemplate into a
    -- narrow width). Per-strip; clicking adds a tab to THIS strip's
    -- dock instance.
    local safeID = (dockID or "dock"):gsub("[^%w_]", "_")
    local btnName = (dockID == "dock") and "BazUIChatAddTabButton"
                                       or  ("BazUIChatAddTabButton_" .. safeID)
    -- Sized off the tabs it sits beside rather than a number of its own,
    -- which is how it came to be a 32-pixel glyph next to 19-pixel tabs.
    local size = ts.tabHeight or 26

    local addBtn = CreateFrame("Button", btnName, ts)
    addBtn:SetSize(size, size)
    -- Bottom to bottom, so it stands on the same line as the tab plates
    -- whatever height the strip itself reports.
    addBtn:SetPoint("BOTTOMLEFT", ts, "BOTTOMRIGHT", 4, 0)

    local plus = BazUI.Skin.Theme.FontString(addBtn, "OVERLAY", "GameFontNormalHuge")
    local fontFile, _, fontFlags = plus:GetFont()
    plus:SetFont(fontFile, math.max(10, size), fontFlags or "")
    plus:SetShadowOffset(1, -1)
    plus:SetShadowColor(0, 0, 0, 1)
    plus:SetPoint("CENTER", addBtn, "CENTER", 0, 1)
    plus:SetText("+")
    plus:SetTextColor(1, 0.82, 0)   -- WoW gold
    addBtn.Text = plus

    addBtn:SetScript("OnEnter", function(self) self.Text:SetTextColor(1, 1, 0.6) end)
    addBtn:SetScript("OnLeave", function(self) self.Text:SetTextColor(1, 0.82, 0) end)
    addBtn:SetScript("OnMouseDown", function(self)
        self.Text:ClearAllPoints()
        self.Text:SetPoint("CENTER", self, "CENTER", 1, 0)
        self.Text:SetTextColor(0.75, 0.62, 0.18)
    end)
    addBtn:SetScript("OnMouseUp", function(self)
        self.Text:ClearAllPoints()
        self.Text:SetPoint("CENTER", self, "CENTER", 0, 1)
        if self:IsMouseOver() then
            self.Text:SetTextColor(1, 1, 0.6)
        else
            self.Text:SetTextColor(1, 0.82, 0)
        end
    end)
    addBtn:SetScript("OnClick", function()
        local newIdx, err = Tabs:CreateNewTab("New Tab", dockID)
        if not newIdx then
            if addon.core and err then
                addon.core:Print("|cffff8800" .. err .. "|r")
            end
            return
        end
        if addon.core then
            addon.core:Print(string.format(
                "Added Tab %d. Right-click the tab to set its channels, or use BazUI options for full editor.",
                newIdx))
        end
        -- If the BazUI options page is open, refresh it so the new
        -- tab appears in the list immediately.
        if BazUI.RefreshOptions then
            BazUI:RefreshOptions("BazUIChat-Tabs")
        end
    end)
    return addBtn
end

-- Tab-selected callback factory. Closures over the strip's dockID so
-- the show/hide loop only touches windows in the same container, and
-- the active-container update reflects which strip the user clicked.
local function MakeTabSelectedCallback(stripDockID)
    return function(tabID, isUserAction)
        local strip
        local Wins = addon.Window
        if Wins and Wins.docks then
            local inst = Wins.docks[stripDockID]
            strip = inst and inst.tabSystem
        end
        local windowIdx = Tabs:WindowIdxOf(strip, tabID) or tabID

        -- If the clicked tab's profile says it lives in another dock
        -- (rare - UpdateVisibility hides cross-dock tabs - but defensive
        -- against state desync), migrate it to this dock first so the
        -- show below targets the right window.
        if isUserAction then
            local cur = DockIDForWindow(windowIdx)
            if cur ~= stripDockID and Wins and Wins.MoveTabToDock then
                Wins:MoveTabToDock(windowIdx, stripDockID)
            end
        end

        -- Mark this strip's container active. The dock uses the legacy
        -- nil convention; popped containers identify by their dockID.
        if isUserAction and Wins and Wins.SetActiveContainer then
            if stripDockID == "dock" then
                Wins:SetActiveContainer(nil)
            else
                Wins:SetActiveContainer(windowIdx)
            end
        end

        -- Show the clicked window, hide siblings IN THE SAME container.
        -- Other containers' windows are untouched: switching dock tabs
        -- doesn't hide popped windows, switching popped tabs doesn't
        -- hide dock windows.
        for idx, win in pairs(WindowList()) do
            if DockIDForWindow(idx) == stripDockID then
                local active = idx == windowIdx
                win:SetShown(active)
            end
            if win.editBox then win.editBox:Hide() end
        end

        -- Instant state-sync for the newly-active window's chrome and
        -- scrollbar so they don't flash to their old alpha (possibly 0
        -- in onhover/onscroll mode) before the per-window hover poller
        -- catches up.
        if addon.AutoHide and addon.AutoHide.SyncWindow then
            local newF = WindowList()[windowIdx]
            if newF then addon.AutoHide:SyncWindow(newF) end
        end

        local w     = WindowList()[windowIdx]
        local wDB   = WindowDB(windowIdx)
        local group = wDB and wDB.eventGroup or "GENERAL"
        local readOnly = group == "LOG"
        local inEditMode = Wins and Wins.dock
                           and Wins.dock._inEditMode

        if isUserAction and w and w.editBox and not readOnly then
            -- Re-assert chat type on every tab switch. Defensive against
            -- Blizzard's chat code occasionally rewriting chatType (eg
            -- after /whisper). Trade tab also re-resolves the channel
            -- ID in case the player just /joined or left a Trade channel.
            Tabs:ApplyChatType(w.editBox, group)
            ChatEdit_ActivateChat(w.editBox)
        elseif inEditMode and w and w.editBox and not readOnly then
            -- Edit Mode: keep editbox visible without stealing focus.
            w.editBox:Show()
        end
        return false
    end
end

-- Lazy-create a tab strip on the given dock instance. Each instance
-- gets exactly one strip; the cached strip is stashed on the instance
-- so future calls return it. The main dock's strip is also exposed as
-- self.system for back-compat with the many call sites that read it.
function Tabs:EnsureFor(dockInstance)
    if not dockInstance then return nil end
    if dockInstance.tabSystem then return dockInstance.tabSystem end

    local id    = dockInstance.id
    local frame = dockInstance.frame
    if not frame then return nil end

    -- Parent the strip to UIParent (NOT the chat window). When the
    -- user clicks a tab we hide the previous window and show the new
    -- one - if the TabSystem were a child of the hidden window it'd
    -- vanish too.
    local safeID = (id or "dock"):gsub("[^%w_]", "_")
    local stripName = (id == "dock") and "BazUIChatTabSystem"
                                     or  ("BazUIChatTabSystem_" .. safeID)
    -- Blizzard's TabSystem exists in every client's source tree but
    -- Classic-family clients don't load it. BazUI.CreateTabStrip speaks
    -- the same API, so everything below works against either.
    -- Ours, always, rather than Blizzard's TabSystemTemplate where the
    -- client has one.
    --
    -- The two speak the same API, so this used to take theirs when it was
    -- there and fall back to ours when it was not. That left the tabs
    -- wearing Blizzard's gray plates above a window drawn in the suite's
    -- own border and colors - the same mismatch the chrome itself had.
    -- Ours takes its plates and its accent straight from the palette, so
    -- the strip follows a skin change with the window under it.
    local ts = BazUI.CreateTabStrip(stripName, UIParent, {
        -- Chat tab labels are short, and these sit above a chat box
        -- around 440 wide. The floor is low enough that "Log" is allowed
        -- to be a small tab rather than padded out to match "General".
        minTabWidth = 40, maxTabWidth = 120,
        tabHeight   = 19,
        tabFont     = "GameFontNormalSmall",
        textPad     = 16,
        tabSelectSound = SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB,
    })
    if not ts then
        if addon.core then
            addon.core:Print("|cffff4444Could not build the chat tab strip|r")
        end
        return nil
    end

    -- Anchor only - no SetSize. TabSystemTemplate inherits
    -- HorizontalLayoutFrame which sizes from child tabs after MarkDirty
    -- (which AddTab calls). Anchor to the dock instance's frame so the
    -- strip tracks the container's position; parent stays UIParent so
    -- visibility is independent.
    -- Measured from the window's left edge rather than the chat text's:
    -- the chrome reaches further left than the frame it wraps, so lining
    -- up with the frame left the tabs sitting inside the panel's corner.
    -- A few pixels in from there, so the first tab clears the corner
    -- instead of growing out of it.
    local chromeLeft = (addon.Chrome and addon.Chrome.INSET_LEFT) or 10
    ts:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -chromeLeft + TAB_STRIP_INDENT, 9)
    ts:SetFrameLevel((frame:GetFrameLevel() or 5) + 20)
    -- Re-points the strip and the add button if this group runs the
    -- other way. Done after the default anchor above rather than instead
    -- of it, so the ordinary case needs no special path, and a tick
    -- later because the instance does not hold this strip yet.
    C_Timer.After(0, function() Tabs:ApplyGroupFlow(id) end)
    -- Ours is drawn at the size it means, so no scaling down.
    ts:Show()

    ts._dockID = id
    ts:SetTabSelectedCallback(MakeTabSelectedCallback(id))

    dockInstance.tabSystem = ts
    if id == "dock" then self.system = ts end   -- back-compat alias

    dockInstance.addBtn = BuildAddButton(ts, id)
    -- Hover-to-reveal for the "onhover" tabsMode (no-op in always/never).
    if addon.AutoHide then addon.AutoHide:WireTab(dockInstance.addBtn) end

    -- Drag-to-move: when the container is unlocked, dragging from any
    -- empty area of the tab strip (between/around tabs) moves the
    -- container. Tab buttons themselves get a separate, TabDrag-aware
    -- handler in :AddFor.
    if addon.Window and addon.Window.WireDragForFrame then
        addon.Window:WireDragForFrame(ts, id)
    end

    return ts
end

---------------------------------------------------------------------------
-- :AddFor — add one tab to the system. Returns the tab's ID.
---------------------------------------------------------------------------

function Tabs:AddFor(window, index, label)
    -- Resolve which dock instance this window belongs to via its
    -- profile dockID. CreateDockInstance is idempotent - if the
    -- container already exists we get the cached one.
    local dockID = DockIDForWindow(index)
    local Wins   = addon.Window
    local inst   = Wins and Wins:CreateDockInstance(dockID)
    local ts     = self:EnsureFor(inst)
    if not ts then return nil end

    -- If this strip already has a tab button for this window
    -- (eg the user is yo-yoing pop in / pop out), reveal the existing
    -- one instead of duplicating. The tab's _windowIdx back-reference
    -- is the source of truth.
    if ts.tabs then
        for tID, tab in ipairs(ts.tabs) do
            if tab._windowIdx == index then
                if not tab:IsShown() then
                    tab:Show()
                    if ts.MarkDirty then ts:MarkDirty() end
                end
                if label and tab.Init then tab:Init(tID, label) end
                -- First-tab-on-strip activation rule: if this is the
                -- ONLY visible tab on the strip after revealing it,
                -- make it the selected tab.
                local visibleCount = 0
                for _, t in ipairs(ts.tabs) do
                    if t:IsShown() then visibleCount = visibleCount + 1 end
                end
                if visibleCount == 1 and ts.SetTab then
                    ts:SetTab(tID, false)
                end
                return tID
            end
        end
    end

    local tabID = ts:AddTab(label or "Chat")
    -- Authoritative back-reference: a strip's tabIDs are sequential
    -- per-strip (1, 2, 3, ...) so on a popped strip with two tabs the
    -- IDs don't match the underlying window indices. Always store the
    -- window idx on the tab so callbacks / lookups can resolve it.
    local tab = ts.tabs and ts.tabs[tabID]
    if tab then
        tab._windowIdx = index
        -- Defensive Show: AddTab usually creates the tab visible, but
        -- the layout pass that places it in the strip can land late
        -- enough that the tab button shows up at the strip's origin
        -- (0, 0) until the next /reload. Forcing Show + MarkDirty
        -- below pushes the layout to recompute this frame.
        tab:Show()
    end

    -- Activate the first visible tab on the strip so a chat window
    -- is shown out of the gate. Applies to the main dock (window 1)
    -- and to every popped strip's first tab.
    if tab then
        local visibleCount = 0
        for _, t in ipairs(ts.tabs) do
            if t:IsShown() then visibleCount = visibleCount + 1 end
        end
        if visibleCount == 1 and ts.SetTab then
            ts:SetTab(tabID, false)
        end
    end

    if tab and addon.TabDrag then
        addon.TabDrag:Setup(tab, tabID, ts)
    end
    if tab and addon.AutoHide then
        addon.AutoHide:WireTab(tab)
    end

    -- Drag-to-move container FROM the tab button itself. Built with
    -- manual OnMouseDown + OnUpdate cursor tracking instead of
    -- RegisterForDrag because TabSystemTopButtonTemplate's button
    -- machinery silently swallows RegisterForDrag - OnDragStart never
    -- fires regardless of RegisterForClicks shape. The cursor-distance
    -- check below runs once per frame while the mouse is held; if the
    -- user moves more than DRAG_THRESHOLD pixels we hand off to
    -- StartMoving on the dock instance frame.
    --
    -- Coexists with TabDrag's hold-2s reorder: if movement is detected
    -- before the 2-second hold elapses we cancel the hold timer and
    -- preempt with a container drag. If the user holds still through
    -- the full 2s, reorder mode wins (TabDrag sets _bcDragging which
    -- our OnUpdate respects).
    if tab and Wins then
        local DRAG_THRESHOLD = 4   -- pixels of cursor movement
        local function StopMonitor(self)
            self:SetScript("OnUpdate", nil)
            self._bcMouseDownX = nil
        end
        local function OnUpdate(self)
            if not self._bcMouseDownX then StopMonitor(self); return end
            -- Already in TabDrag reorder OR already container-dragging:
            -- either way, our work here is done.
            if self._bcDragging or self._bcContainerDragging then
                StopMonitor(self); return
            end
            local x = GetCursorPosition()
            if math.abs(x - self._bcMouseDownX) <= DRAG_THRESHOLD then return end
            -- Movement detected. Try to start a container drag.
            if Wins:IsContainerLocked(dockID) then StopMonitor(self); return end
            local dock = Wins.docks and Wins.docks[dockID]
            if not dock or not dock.frame then StopMonitor(self); return end
            if dock.frame._inEditMode then StopMonitor(self); return end
            -- Cancel TabDrag's pending hold timer (movement preempted).
            if self._bcHoldTimer then
                self._bcHoldTimer:Cancel()
                self._bcHoldTimer = nil
            end
            dock.frame:StartMoving()
            self._bcContainerDragging = true
            StopMonitor(self)
        end
        tab:HookScript("OnMouseDown", function(self, btn)
            if btn ~= "LeftButton" then return end
            self._bcMouseDownX = GetCursorPosition()
            self:SetScript("OnUpdate", OnUpdate)
        end)
        tab:HookScript("OnMouseUp", function(self, btn)
            -- Finalize if we started a container drag.
            if self._bcContainerDragging then
                local dock = Wins.docks and Wins.docks[dockID]
                if dock and dock.frame then
                    dock.frame:StopMovingOrSizing()
                    if Wins.SaveContainerPos then
                        Wins:SaveContainerPos(dockID)
                    end
                end
                self._bcContainerDragging = nil
            end
            StopMonitor(self)
        end)
    end
    -- Right-click on a tab (shift or not) opens BazUI's shared context
    -- menu (scope "chat-tab"): Rename / Channels / Clear / Lock / Move to
    -- / Delete, contributed via RegisterContextMenuSection above. Other
    -- modules can append their own entries against the same scope.
    if tab then
        tab:HookScript("OnMouseUp", function(self, button)
            if button == "RightButton" and BazUI.OpenContextMenu then
                BazUI:OpenContextMenu("chat-tab", self, {
                    tab   = self,
                    index = index,
                })
            end
        end)
    end

    -- TabSystem's MarkDirty triggers HorizontalLayoutFrame's recompute
    -- on the next OnUpdate. AddTab calls it internally during ordinary
    -- creation, but the path via Tabs:CreateNewTab -> Window:Create ->
    -- Tabs:AddFor sometimes lands a frame past the layout pass and the
    -- tab button is registered without being placed. Forcing MarkDirty
    -- here guarantees the strip re-lays out and the new tab appears
    -- immediately rather than waiting for the next /reload.
    if ts.MarkDirty then ts:MarkDirty() end

    return tabID
end

---------------------------------------------------------------------------
-- :CreateNewTab — add a new tab with default channels, return new idx.
--
-- Used by:
--   * The "+" button on the tab strip (OnClick handler)
--   * The "Create New Tab" button on the Tabs options page
-- Both flows hand off to here so behavior stays identical.
--
-- Default channels = "BLANK" preset (just Say) to keep new tabs quiet
-- until the user picks what they want via the channel popup.
---------------------------------------------------------------------------

function Tabs:CreateNewTab(label, dockID)
    dockID = dockID or "dock"
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    if not p then return nil end
    p.windows = p.windows or {}

    -- Refuse if there's no room ON THE TARGET STRIP. Sum the ACTUAL
    -- widths of currently-visible tabs in that strip (tabs render
    -- between minTabWidth and maxTabWidth based on label length, so
    -- projecting minTabWidth × count under-estimates real usage). Add
    -- minTabWidth for the projected new tab, plus 40 px for the "+"
    -- button slot. Multiply by the strip's scale to get screen pixels
    -- and compare against the container's width.
    local Wins = addon.Window
    local inst = Wins and Wins.docks and Wins.docks[dockID]
    local ts   = inst and inst.tabSystem
    if ts and ts.tabs then
        local stripW = 0
        for _, t in ipairs(ts.tabs) do
            if t:IsShown() then stripW = stripW + (t:GetWidth() or 0) end
        end
        local newTabW = ts.minTabWidth or 60
        local addBtn  = 40
        local scale   = ts:GetScale() or 1
        local containerW = (inst and inst.frame and inst.frame:GetWidth()) or 440
        local projectedScreen = (stripW + newTabW + addBtn) * scale
        if projectedScreen > containerW then
            return nil, "tab strip is full at this chat width - delete a tab first"
        end
    end

    -- Find the next free index. Walk past existing windows[] to handle
    -- gaps from previous deletes.
    local nextIdx = 1
    while p.windows[nextIdx] do nextIdx = nextIdx + 1 end

    p.windows[nextIdx] = {
        label    = label or "New Tab",
        dockID   = dockID,
        channels = addon.Channels and addon.Channels:DefaultsFor("BLANK") or {},
    }

    -- Instantiate the chat frame + tab button live (no /reload). The
    -- chat frame anchors to dockID's container automatically because
    -- Window:Create reads windows[idx].dockID.
    if Wins and Wins.Create then
        Wins:Create(nextIdx, { label = p.windows[nextIdx].label })
    end

    return nextIdx
end

---------------------------------------------------------------------------
-- :DeleteTab — remove a tab by index. General (idx 1) is undeletable
-- because it owns the DEFAULT_CHAT_FRAME claim.
--
-- Approach: clear the DB entry then reload. Compacting in-memory across
-- a deletion would require shifting every windows[] / tabs[] / tabOrder
-- entry above the deleted index, plus reindexing live frames - the
-- /reload trade-off is "1 second to settle, guaranteed clean state."
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- :ResetTabsToDefaults — wipe user customizations + restore the four
-- canonical tabs (General/Guild/Trade/Log) with their preset channels.
--
-- Triggers a /reload so the live state rebuilds cleanly. Useful as
-- the "panic button" when a user deletes/renames things and wants to
-- start over without nuking their whole BazChat profile.
---------------------------------------------------------------------------

function Tabs:ResetTabsToDefaults()
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    if not p then return false end

    -- Wipe windows[] and tab-related metadata. windows[1]'s chrome
    -- settings (alpha/scale/fade modes) are preserved by reading them
    -- before the wipe and re-applying after - the user's appearance
    -- preferences shouldn't get reset just because they wanted tabs back.
    local preserve = {}
    if p.windows and p.windows[1] then
        for _, key in ipairs({
            "alpha", "bgAlpha", "bgMode", "tabsAlpha", "chromeFadeMode",
            "scale", "scrollbarMode", "tabsMode", "fading", "fadeDuration",
            "timeVisible", "maxLines", "indentedWordWrap",
        }) do
            preserve[key] = p.windows[1][key]
        end
        preserve.dockID = "dock"
    end
    -- Preserve the main dock's geometry so the dock doesn't snap to
    -- the default corner just because the user reset tabs.
    local dockGeom
    if p.docks and p.docks.dock then
        dockGeom = {
            pos    = p.docks.dock.pos,
            width  = p.docks.dock.width,
            height = p.docks.dock.height,
        }
    end
    p.windows = nil
    p.deletedCanonicals = nil
    p.tabOrder = nil
    p.docks = nil

    -- Re-stamp window 1's chrome settings + the dock's geometry so
    -- CreateAll's migration doesn't overwrite them with raw defaults.
    p.windows = { [1] = preserve }
    if dockGeom then
        p.docks = { dock = dockGeom }
    end

    return true
end

function Tabs:DeleteTab(idx)
    if idx == 1 then return false end
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    if not p or not p.windows or not p.windows[idx] then return false end

    -- Live cleanup: hide the chat frame and the tab button so they
    -- vanish without a /reload. The runtime tables (Window.list, the
    -- TabSystem's tabs array) still hold references; that's a harmless
    -- memory leak that gets cleaned up on next /reload (CreateAll
    -- iterates the DB only). Avoids the trickier in-memory compaction
    -- of windows[] / tabs[] / tabSystem.tabs which would require
    -- reindexing every entry above the deleted position.
    local list = (addon.Window and addon.Window.list) or {}
    local f = list[idx]
    if f then f:Hide() end
    -- Find the tab on whatever strip is hosting it (main dock or a
    -- popped container) and hide it there.
    local tab, strip, tabID = self:GetTabFor(idx)
    if tab then
        tab:Hide()
        -- Sever the back-reference so UpdateVisibility / GetTabFor
        -- can't find this orphan tab again. Without this, the next
        -- UpdateVisibility pass would re-show the tab because the
        -- profile entry is gone and ShouldShowTab(nil) returns true.
        tab._windowIdx = nil
        if strip and strip.MarkDirty then strip:MarkDirty() end
        -- If the deleted tab was the active one on its strip, fall
        -- back to the strip's first remaining tab.
        if strip and strip.selectedTabID == tabID then
            for i = 1, #(strip.tabs or {}) do
                if strip.tabs[i]:IsShown() and i ~= tabID then
                    strip:SetTab(i, false)
                    break
                end
            end
        end
    end

    -- Which container it was living in, read before the entry goes.
    local dockID = p.windows[idx].dockID or "dock"

    -- Wipe the DB entry. From this point any code reading
    -- windows[idx] from the profile sees nil, so right-click /
    -- channel-popup / options-page entries all become inert for it.
    p.windows[idx] = nil

    -- Track explicit deletions of CANONICAL tabs (Guild=2, Trade=3,
    -- Log=4). Without this, CreateAll's migration would re-create them
    -- on the next /reload because the canonical entry was missing.
    -- User-created tabs (idx 5+) don't need tracking - the canonical
    -- iteration only runs for 1..4, so a deleted user tab simply
    -- isn't seen on reload.
    if idx >= 2 and idx <= 4 then
        p.deletedCanonicals = p.deletedCanonicals or {}
        p.deletedCanonicals[idx] = true
    end

    -- Also strip the deleted index out of any saved tab order so
    -- TabDrag:LoadOrder doesn't reference a now-missing window on
    -- the next reload.
    if p.tabOrder then
        local cleaned = {}
        for _, id in ipairs(p.tabOrder) do
            if id ~= idx then cleaned[#cleaned + 1] = id end
        end
        p.tabOrder = cleaned
    end

    -- A popped-out window that has just lost its last tab.
    --
    -- The container, its strip and its add button are not the tab, so
    -- none of them went away with it: what was left was an empty window
    -- with a lone "+" in it. And the container's saved geometry outlived
    -- the tab too, so the next reload built that empty window again.
    --
    -- Only when nothing else is living there. A popped window can hold
    -- several tabs, and deleting one of them should leave the rest where
    -- they are.
    if dockID ~= "dock" and addon.Window and addon.Window.DestroyDockInstance then
        local stillUsed = false
        for _, win in pairs(p.windows) do
            if (win.dockID or "dock") == dockID then stillUsed = true break end
        end
        if not stillUsed then
            -- With the geometry, since there is no longer anything that
            -- would be restored into it.
            addon.Window:DestroyDockInstance(dockID, true)
        end
    end

    -- Close the channel popup if it was for this tab; refresh the
    -- BazUI Tabs options page so the row disappears from the list.
    if addon.Channels and addon.Channels.HidePopup then
        addon.Channels:HidePopup()
    end
    if BazUI.RefreshOptions then
        BazUI:RefreshOptions("BazUIChat-Tabs")
    end

    return true
end
