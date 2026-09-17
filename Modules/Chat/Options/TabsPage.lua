-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Tabs page
--
-- Managed list of every chat tab. Built on BazUI's CreateManagedListPage
-- (left-side list with up/down reorder arrows, right-side per-item
-- detail editor). Each tab gets:
--   * Tab Name input (rename)
--   * Edit Channels button (opens the right-click popup)
--   * Delete button (disabled for the General tab, which owns the
--     DEFAULT_CHAT_FRAME claim and can't be removed)
--
-- "Create New Tab" at the top of the list adds a new entry; the same
-- flow runs when the user clicks the "+" button on the chat tab strip.
-- Both call addon.Tabs:CreateNewTab so behavior stays identical.
---------------------------------------------------------------------------

local addon     = BazUI.Chat          -- Chat's private namespace
local addonName = addon.MODULE_NAME

local PAGE_KEY = "BazUIChat-Tabs"

local function GetWindow(idx)
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    return p and p.windows and p.windows[idx] or nil
end

local function GetWindowList()
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)
    return p and p.windows or {}
end

---------------------------------------------------------------------------
-- Refresh helpers — update the live tab strip after a rename/delete
---------------------------------------------------------------------------

local function RefreshTabLabel(idx, newLabel)
    if not (addon.Tabs and addon.Tabs.GetTabFor) then return end
    local tab = addon.Tabs:GetTabFor(idx)
    if tab and tab.Init then
        tab:Init(idx, newLabel)
    end
end

---------------------------------------------------------------------------
-- Detail-pane builder for a single tab
---------------------------------------------------------------------------

-- Auto-show options. Keys match the autoShow strings ShouldShowTab in
-- Replica/Tabs.lua expects; values are the labels shown in the dropdown.
-- Format matches BazUI's CreateSelectWidget which iterates pairs() and
-- looks up the current key directly: values[opt.get()] -> displayed label.
local AUTO_SHOW_VALUES = {
    always   = "Always",
    city     = "In a city",
    guild    = "In a guild",
    party    = "In a party",
    raid     = "In a raid",
    combat   = "In combat",
    pvp      = "In a battleground / arena",
    instance = "In a dungeon / raid",
}

local function BuildTabDetail(item)
    local idx = item._idx
    return {
        { type = "header", name = "Identity" },

        { type = "input",
          name = "Tab Name",
          desc = "Display name shown on the tab button at the top of the chat.",
          get = function()
              local d = GetWindow(idx)
              return d and d.label or ""
          end,
          set = function(_, val)
              local d = GetWindow(idx)
              if d then
                  d.label = val
                  RefreshTabLabel(idx, val)
                  if BazUI.RefreshOptions then
                      BazUI:RefreshOptions(PAGE_KEY)
                  end
              end
          end,
        },

        { type = "select",
          name = "Auto-show",
          desc = "When this tab should be visible. 'Always' keeps it on the strip permanently. The others hide the tab unless the listed condition is true (e.g. 'In a city' shows the tab only in major cities, matching the default Trade tab behavior).",
          values = AUTO_SHOW_VALUES,
          get = function()
              local d = GetWindow(idx)
              return d and d.autoShow or "always"
          end,
          set = function(_, val)
              local d = GetWindow(idx)
              if d then
                  d.autoShow = val
                  if addon.Tabs and addon.Tabs.UpdateVisibility then
                      addon.Tabs:UpdateVisibility()
                  end
              end
          end,
        },

        { type = "header", name = "Channels" },

        { type = "note", style = "info",
          text = "Click Edit Channels to pick which chat events this tab receives. The same popup opens from the tab's right-click menu under Channels...",
        },

        { type = "execute",
          name = "Edit Channels...",
          desc = "Open the channel picker for this tab.",
          func = function()
              if not addon.Channels then return end
              -- Anchor the popup to the tab button if available, else
              -- to UIParent center-ish. Tab can live on any dock
              -- instance's strip - GetTabFor scans them all.
              local tab = addon.Tabs and addon.Tabs.GetTabFor
                  and addon.Tabs:GetTabFor(idx) or nil
              if tab then
                  addon.Channels:ShowPopup(tab, idx)
              else
                  addon.Channels:ShowPopup(UIParent, idx)
              end
          end,
        },

        { type = "header", name = "Actions" },

        { type = "execute",
          name = "Delete Tab",
          desc = "Remove this tab. Cannot be undone.",
          disabled = function() return idx == 1 end,
          confirm = true,
          confirmText = "Delete the '" .. (item.name or ("Tab " .. idx)) .. "' tab?",
          func = function()
              if addon.Tabs and addon.Tabs.DeleteTab then
                  addon.Tabs:DeleteTab(idx)   -- live cleanup, no reload
              end
          end,
        },
    }
end

---------------------------------------------------------------------------
-- Page builder
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Order helpers — list rows reflect the tab strip's visual order
--
-- The TabDrag module saves the user's drag-to-reorder result in
-- profile.tabOrder (array of window indices in visual order). The
-- managed list reads from the same source so the list rows match the
-- strip's order. New tabs (and any indices missing from the saved
-- order) get appended at the end.
---------------------------------------------------------------------------

local function GetCurrentOrder()
    local list = GetWindowList()
    local p = (addon.db and addon.db.profile)
        or (addon.core and addon.core.db and addon.core.db.profile)

    local result, seen = {}, {}
    if p and p.tabOrder then
        for _, id in ipairs(p.tabOrder) do
            if list[id] and not seen[id] then
                result[#result + 1] = id
                seen[id] = true
            end
        end
    end
    -- Append any windows not in the saved order (e.g. brand-new tabs
    -- created since the last drag-reorder, or canonical tabs in a
    -- fresh profile that hasn't reordered anything yet).
    local extras = {}
    for k in pairs(list) do
        if type(k) == "number" and not seen[k] then
            extras[#extras + 1] = k
        end
    end
    table.sort(extras)
    for _, id in ipairs(extras) do result[#result + 1] = id end
    return result
end

-- Save the order via TabDrag's existing path so a single source of
-- truth (profile.tabOrder) drives both the strip and the list. Then
-- apply live to the tab strip so the user's reorder is visible
-- immediately, and refresh the options page.
local function ApplyOrder(order)
    if addon.TabDrag and addon.TabDrag.Save then
        addon.TabDrag:Save(order)
    end
    if addon.TabDrag and addon.TabDrag.ApplyOrder
       and addon.Tabs and addon.Tabs.system then
        addon.TabDrag:ApplyOrder(order, addon.Tabs.system)
    end
    if BazUI.RefreshOptions then
        BazUI:RefreshOptions(PAGE_KEY)
    end
end

-- Swap a tab's position with its neighbor. dir = -1 for up, +1 for down.
local function MoveTab(idx, dir)
    local order = GetCurrentOrder()
    local pos
    for i, id in ipairs(order) do
        if id == idx then pos = i; break end
    end
    if not pos then return end
    local newPos = pos + dir
    if newPos < 1 or newPos > #order then return end
    order[pos], order[newPos] = order[newPos], order[pos]
    ApplyOrder(order)
end

local function GetItems()
    local list  = GetWindowList()
    local order = GetCurrentOrder()

    local items = {}
    for i, idx in ipairs(order) do
        local ws = list[idx]
        if ws then
            items[#items + 1] = {
                key   = tostring(idx),
                name  = ws.label or ("Tab " .. idx),
                order = i * 10,
                _idx  = idx,
            }
        end
    end
    return items
end

---------------------------------------------------------------------------
-- Register
---------------------------------------------------------------------------

BazUI:QueueForModule("Chat", function()
    if not BazUI.RegisterOptionsTable then return end
    if not BazUI.CreateManagedListPage then return end

    local builder = BazUI:CreateManagedListPage(addonName, {
        pageName = "Tabs",

        intro = "Each tab subscribes to its own set of chat channels. Click Create New Tab to add one (e.g. a Whispers-only or Combat-only tab); click an existing tab to rename it or pick its channels. Use the up/down arrows on the right edge of each row to reorder tabs (also reorderable by holding a tab in the strip for 2 seconds and dragging). The General tab can't be deleted — it owns the chat keybind.",

        getItems    = GetItems,
        buildDetail = BuildTabDetail,
        detailTitle = "h1",

        -- Reorder arrows: BazUI's list-detail panel renders up/down
        -- arrow buttons on each row when these callbacks are set, with
        -- the topmost arrow disabled on row 1 and the bottommost arrow
        -- disabled on the last row.
        onMoveUp   = function(item) if item and item._idx then MoveTab(item._idx, -1) end end,
        onMoveDown = function(item) if item and item._idx then MoveTab(item._idx,  1) end end,

        createButtonText = "Create New Tab",
        onCreate = function()
            if not addon.Tabs then return end
            local newIdx, err = addon.Tabs:CreateNewTab("New Tab")
            if not newIdx then
                if addon.core and err then
                    addon.core:Print("|cffff8800" .. err .. "|r")
                end
                return
            end
            if BazUI.RefreshOptions then
                BazUI:RefreshOptions(PAGE_KEY)
            end
        end,

        -- "Reset to Defaults" panic button. Wipes user-created tabs +
        -- restores General/Guild/Trade/Log with their preset channels.
        -- Preserves the user's appearance settings (alpha/scale/fade
        -- modes) so resetting doesn't nuke unrelated preferences.
        resetButtonText = "Reset Tabs to Defaults",
        onReset = function()
            if BazUI.Confirm then
                BazUI:Confirm({
                    title       = "Reset tabs?",
                    body        = "Reset all chat tabs to defaults? Custom tabs will be removed and the canonical four (General / Guild / Trade / Log) will be restored. Reload follows.",
                    acceptLabel = "Reset",
                    acceptStyle = "destructive",
                    onAccept    = function()
                        if addon.Tabs and addon.Tabs.ResetTabsToDefaults
                           and addon.Tabs:ResetTabsToDefaults() then
                            if addon.core then
                                addon.core:Print(
                                    "|cffffd100tabs reset, reloading...|r")
                            end
                            C_Timer.After(0.1, ReloadUI)
                        end
                    end,
                })
            end
        end,
    })

    BazUI:RegisterOptionsTable(PAGE_KEY, builder)
    BazUI:AddToSettings(PAGE_KEY, "Tabs", addonName)
end)
