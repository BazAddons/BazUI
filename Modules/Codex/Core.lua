-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Codex
--
-- One window answering two questions: what can I do today, and what
-- have I already accomplished. Everything it shows belongs under one or
-- the other, which is what keeps it a codex rather than a pile of
-- readouts. A host with a registry rather than
-- a fixed page, the same shape the drawer uses for widgets and
-- Notifications uses for its sources, so a new tracker is an addition
-- instead of a rewrite. That matters most for Forever, whose systems
-- are still arriving.
--
-- Nothing here ships a database. Every section answers from what the
-- client already knows: lockouts, completed quests, known spells, item
-- counts. Where an answer would need outside knowledge (where a thing
-- drops, which step of a chain comes next) that is a data pack we write
-- deliberately, not a hidden dependency.
---------------------------------------------------------------------------

local MODULE_NAME = "Codex"

local Codex = BazUI.Codex or {}
BazUI.Codex = Codex

local addon
addon = BazUI:RegisterModule(MODULE_NAME, {
    title    = "Codex",
    icon     = "Interface\\Icons\\INV_Misc_Book_09",
    profiles = true,
    defaults = {
        -- Panel
        position     = nil,      -- { point, relPoint, x, y }, set by dragging
        scale        = 1.0,
        opacity      = 0.95,
        activeTab    = "today",
        collapsed    = {},       -- [sectionID] = true

        -- Item lookup. The index is what this character has met: bags,
        -- bank, loot, vendors, links in chat. It ships empty and grows.
        indexItems   = true,
        itemIndex    = {},       -- [itemID] = itemName
        itemCategory = "all",    -- a category key from Bags, or "all"
        wishlist     = {},       -- [itemID] = { note = string, added = time }
    },
    minimap = {
        label = "Codex",
        icon  = "Interface\\Icons\\INV_Misc_Book_09",
        onClick = function() Codex:Toggle() end,
    },
    slash = { "/bazcodex", "/codex" },
    defaultHandler = function() Codex:Toggle() end,
    commands = {
        show  = { desc = "Open the codex",  handler = function() Codex:Show() end },
        hide  = { desc = "Close the codex", handler = function() Codex:Hide() end },
        reset = {
            desc = "Move the codex back to the middle of the screen",
            handler = function()
                addon:SetSetting("position", nil)
                Codex:ApplySettings()
            end,
        },
        -- Attunements and keys are written down rather than asked for,
        -- since the client has no way to answer them. This is how you
        -- see whether what is written down is right.
        -- The client lists only the factions this character has met. It
        -- will answer for any faction by id, though, so this asks it for
        -- every id in range and puts the answers in a box to copy from -
        -- the raw material for writing Forever's faction list down.
        factions = {
            desc = "List every faction the client knows, to copy",
            handler = function()
                local ask = C_Reputation and C_Reputation.GetFactionDataByID
                if not ask then
                    BazUI:Print("Codex: this client cannot be asked for factions by id.")
                    return
                end
                local lines, found = {}, 0
                for id = 1, 3000 do
                    local ok, d = pcall(ask, id)
                    if ok and d and d.name and d.name ~= "" then
                        found = found + 1
                        -- Spaces, not tabs: the game's fonts draw a tab
                        -- as a box.
                        lines[#lines + 1] = string.format("%d  %s%s%s", id, d.name,
                            d.isHeader and "  [header]" or "",
                            (d.reaction and d.reaction > 0 and (d.currentStanding or 0) ~= 0)
                                and "  [met]" or "")
                    end
                end
                BazUI:OpenCopyDialog({
                    title    = "Factions the client knows",
                    subtitle = string.format("%d found in ids 1-3000. id, name, [header], [met]", found),
                    content  = table.concat(lines, "\n"),
                    editable = false,
                    width    = 640,
                    height   = 520,
                })
            end,
        },
        verify = {
            desc = "Check the attunement and key list against the client",
            handler = function()
                local checked, wrong = 0, 0
                for label, source in pairs({
                    attunement = Codex.Access,
                    goal       = Codex.Goals,
                }) do
                    if source and source.Validate then
                        checked = checked + #source.entries
                        for _, reason in pairs(source.Validate()) do
                            BazUI:Print(("Codex (%s): %s"):format(label, reason))
                            wrong = wrong + 1
                        end
                    end
                end

                if checked == 0 then
                    BazUI:Print("Codex: no written-down data loaded.")
                elseif wrong == 0 then
                    BazUI:Print(("Codex: all %d written-down entries agree with the client."):format(checked))
                else
                    BazUI:Print(("Codex: %d of %d entries are wrong and are being hidden."):format(wrong, checked))
                end
            end,
        },
    },
    onReady = function(self) Codex:Initialize() end,
})

addon.MODULE_NAME = MODULE_NAME
Codex.addon = addon

---------------------------------------------------------------------------
-- Sections
--
-- A section is one block of rows on a tab. Register one with:
--
--   BazUI.Codex:RegisterSection({
--       id     = "lockouts",          -- unique
--       tab    = "today",             -- "today" or "progress", mostly
--       title  = "Raid lockouts",
--       order  = 10,
--       empty  = "Nothing saved.",    -- shown when GetRows returns none
--       events = { "UPDATE_INSTANCE_INFO" },   -- refresh triggers
--       GetRows = function() return { ... } end,
--   })
--
-- A row is data, not frames, so every section looks the same and the
-- panel owns the drawing:
--
--   { label = "Molten Core", detail = "9/10 bosses", state = "locked",
--     tip = "Resets Wednesday", icon = "Interface\\Icons\\..." }
--
-- state is "open" (available), "locked" (on cooldown or saved), "done"
-- (finished) or nil (no state color).
---------------------------------------------------------------------------

Codex.sections = Codex.sections or {}

-- A tab that cannot be expressed as a stack of rows owns its whole page
-- instead: it supplies Render(content, width), sets its own height, and
-- a Hide() that puts its frames away when another tab is showing. Item
-- lookup and the wishlist work this way because they take typing.
Codex.customTabs = Codex.customTabs or {}

function Codex:RegisterSection(def)
    if type(def) ~= "table" or not def.id then return end
    def.tab   = def.tab or "today"
    def.order = def.order or 100
    self.sections[def.id] = def
    if self.Panel and self.Panel.QueueRefresh then self.Panel:QueueRefresh() end
    return def
end

-- Blocks made from what the client lists rather than written down here:
-- faction groups, currency groups, whatever the game chooses to group.
-- Called again whenever the list changes. Each block keeps the id of
-- its key so one you folded stays folded; blocks whose key has gone are
-- dropped; the functions are swapped in fresh each time so they see the
-- latest reading.
--
--   Codex:SyncGroupSections("rep.", { tab = ..., tabLabel = ..., tabOrder = ..., tabIcon = ... }, {
--       { key = "Alliance", title = "Alliance", GetRows = fn, GetBar = fn, GetHighlight = fn, empty = "..." },
--   })
function Codex:SyncGroupSections(prefix, common, blocks)
    local wanted = {}
    for index, block in ipairs(blocks) do
        local id = prefix .. block.key
        wanted[id] = true
        local def = self.sections[id]
        if not def then
            def = self:RegisterSection({
                id       = id,
                tab      = common.tab,
                tabLabel = common.tabLabel,
                tabOrder = common.tabOrder,
                tabIcon  = common.tabIcon,
                title    = block.title,
            })
        end
        def.title        = block.title
        def.order        = block.order or index * 10
        def.empty        = block.empty or common.empty
        def.GetRows      = block.GetRows
        def.GetBar       = block.GetBar
        def.GetHighlight = block.GetHighlight
        -- What a block may wear: a picture behind, an icon on the
        -- heading, and leave to stand with no rows under it.
        def.art          = block.art
        def.artFallback  = block.artFallback
        def.artAlpha     = block.artAlpha
        def.artSquare    = block.artSquare
        def.icon         = block.icon
        def.rowless      = block.rowless
        -- Which column it belongs in, where the block cares. Most do
        -- not, and fall where the layout puts them.
        def.column       = block.column
        -- A paragraph under the heading, for a block whose subject
        -- needs saying rather than counting.
        def.blurb        = block.blurb
    end
    for id in pairs(self.sections) do
        if id:sub(1, #prefix) == prefix and not wanted[id] then
            self.sections[id] = nil
        end
    end
end

-- Sections on one tab, in order.
function Codex:GetSections(tab)
    local out = {}
    for _, def in pairs(self.sections) do
        if def.tab == (tab or "today") then out[#out + 1] = def end
    end
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return tostring(a.title) < tostring(b.title)
    end)
    return out
end

function Codex:IsCollapsed(sectionID)
    local map = addon:GetSetting("collapsed") or {}
    return map[sectionID] == true
end

function Codex:SetCollapsed(sectionID, collapsed)
    local map = addon:GetSetting("collapsed") or {}
    map[sectionID] = collapsed or nil
    addon:SetSetting("collapsed", map)
end
