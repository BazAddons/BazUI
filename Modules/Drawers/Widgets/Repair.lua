-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Repair
--
-- Paper-doll mini view + list of damaged equipment slots with their
-- current durability percentage. Click the widget to open the character
-- sheet. Event-driven updates on UPDATE_INVENTORY_DURABILITY and
-- PLAYER_EQUIPMENT_CHANGED.
--
-- The slot's title bar (provided by WidgetHost) shows the widget name
-- on the left and the overall durability % on the right via
-- GetStatusText, so the widget itself draws only its content area.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local DESIGN_WIDTH  = 220
local PAD           = 6     -- vertical padding (top/bottom)
local HPAD          = 12    -- horizontal padding (left/right)
local COL_GAP       = 8     -- gap between the three columns
local SLOT_SIZE     = 20
local SLOT_GAP      = 2
local ROW_HEIGHT    = 14

-- Layout: three equal-width columns with padding on either side and gaps
-- between. Column 1 = paper doll, column 2 = slot names, column 3 = %.
local COL_WIDTH    = (DESIGN_WIDTH - HPAD * 2 - COL_GAP * 2) / 3
local COL1_X       = HPAD
local COL2_X       = HPAD + COL_WIDTH + COL_GAP
local COL3_X       = HPAD + COL_WIDTH * 2 + COL_GAP * 2

-- Fixed vertical space taken by the paper doll icon block (2×5 grid)
local PAPER_DOLL_HEIGHT = 5 * SLOT_SIZE + 4 * SLOT_GAP

local WIDGET_ID = "bazdrawer_repair"

local function IsHideDefaultDurability()
    -- Default: true (hide Blizzard's durability figure unless explicitly
    -- told otherwise). Evaluated lazily so toggling the setting is live.
    return addon:GetWidgetSetting(WIDGET_ID, "hideBlizzardDurability", true) ~= false
end

-- Paper doll mode: "blizzard" (Blizzard's DurabilityFrame reparented in -
-- the default), "custom" (our icon grid), or "none" (hidden entirely).
local function PaperDollMode()
    -- Back-compat: old bool setting named "showPaperDoll"
    local mode = addon:GetWidgetSetting(WIDGET_ID, "paperDollMode")
    if mode then return mode end
    local legacy = addon:GetWidgetSetting(WIDGET_ID, "showPaperDoll")
    if legacy == false then return "none" end
    return "blizzard"
end

local function ShowPaperDoll()
    return PaperDollMode() ~= "none"
end

---------------------------------------------------------------------------
-- Blizzard DurabilityFrame dock/undock
--
-- Safe to reparent: DurabilityFrame is a normal (non-protected) frame
-- that's managed by UIParentRightManagedFrameContainer. We opt out of
-- that manager by setting `ignoreFramePositionManager = true` and
-- removing ourselves from its `showingFrames` list, then freely anchor
-- the frame into our widget. Restoration reverses both steps.
---------------------------------------------------------------------------

local DURABILITY_SCALE = 1.20  -- upscale the native DurabilityFrame inside our widget

local durabilityDocked = false
local durabilitySuppressed = false



---------------------------------------------------------------------------
-- Full suppression - hide DurabilityFrame and use hooksecurefunc to
-- re-hide it whenever Blizzard tries to Show it. The old approach of
-- replacing DurabilityFrame.Show with Hide tainted the frame's method
-- table, which propagated through UIParentRightManagedFrameContainer
-- to UnitFrame health bars and caused "secret number tainted by
-- BazUI Drawers" errors. hooksecurefunc preserves the original secure
-- method so no taint is introduced.
---------------------------------------------------------------------------

local function SuppressDurabilityFrame()
    if durabilitySuppressed or not DurabilityFrame then return end

    DurabilityFrame.ignoreFramePositionManager = true
    durabilitySuppressed = true

    -- Through the shared suppressor: it hooks OnShow rather than writing
    -- to the frame's method table, which is what broke the objective
    -- tracker on Forever. Hooked once; the test below is re-asked each
    -- time the frame shows.
    BazUI.SuppressFrame(DurabilityFrame, function() return durabilitySuppressed end)
end

local function UnsuppressDurabilityFrame()
    if not durabilitySuppressed or not DurabilityFrame then return end

    DurabilityFrame.ignoreFramePositionManager = nil
    -- The hook stays installed but durabilitySuppressed = false
    -- means it's a no-op, so Show works normally again.

    durabilitySuppressed = false
end

-- Forward declaration - defined after the hide setting is read from the
-- addon DB so that external enable/disable hooks can call it too.
local ApplyDurabilityVisibility

local function DockBlizzardDurability(anchor)
    if durabilityDocked or not DurabilityFrame then return end

    -- Docking overrides suppression - unlock Show before parenting so
    -- the frame can actually render inside our widget.
    UnsuppressDurabilityFrame()

    -- Remove from the right-managed-frame container and flag opt-out
    if UIParentRightManagedFrameContainer
        and UIParentRightManagedFrameContainer.RemoveManagedFrame then
        UIParentRightManagedFrameContainer:RemoveManagedFrame(DurabilityFrame)
    end
    DurabilityFrame.ignoreFramePositionManager = true

    -- Blizzard's Edit Mode handling for this frame, kept out of the way.
    --
    -- This used to override OnEditModeEnter, OnEditModeExit and
    -- HighlightSystem with no-ops and replace Selection.Show with
    -- Selection.Hide. DurabilityFrame is one of their Edit Mode systems,
    -- and writing to the method table of one is what left MainActionBar's
    -- snap state owned by BazUI - which surfaced four files away as their
    -- compact party frames comparing a secret color.
    --
    -- Two things do the same job without writing anything of theirs: the
    -- highlight frame goes down through SuppressFrame, and the frame is
    -- not movable, so a drag cannot start even if their Edit Mode does
    -- decide to offer it.
    if DurabilityFrame.Selection then
        BazUI.SuppressFrame(DurabilityFrame.Selection, function()
            return durabilityDocked
        end)
    end

    DurabilityFrame:SetMovable(false)

    DurabilityFrame:SetParent(anchor)
    DurabilityFrame:ClearAllPoints()
    DurabilityFrame:SetScale(DURABILITY_SCALE)
    DurabilityFrame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    DurabilityFrame:Show()

    durabilityDocked = true
end

local function UndockBlizzardDurability()
    if not durabilityDocked or not DurabilityFrame then return end
    DurabilityFrame.ignoreFramePositionManager = nil
    DurabilityFrame:SetParent(UIParent)
    DurabilityFrame:SetScale(1.0)
    DurabilityFrame:ClearAllPoints()

    -- Nothing of theirs to put back: the highlight answers `durabilityDocked`,
    -- which is about to be false, and the rest was never taken.
    DurabilityFrame:SetMovable(true)

    if UIParentRightManagedFrameContainer
        and UIParentRightManagedFrameContainer.AddManagedFrame then
        UIParentRightManagedFrameContainer:AddManagedFrame(DurabilityFrame)
    end
    durabilityDocked = false
end

---------------------------------------------------------------------------
-- Single entry point that decides whether DurabilityFrame should be:
--   1. docked into the widget (mode=blizzard + widget enabled),
--   2. suppressed entirely (hide option on OR widget disabled),
--   3. restored to Blizzard defaults (hide option off and widget disabled
--      with mode not blizzard - rare, only if user explicitly wants it).
---------------------------------------------------------------------------

ApplyDurabilityVisibility = function(anchor, mode)
    local widgetEnabled = addon:IsWidgetEnabled(WIDGET_ID)
    local wantDock = widgetEnabled and mode == "blizzard" and anchor

    if wantDock then
        DockBlizzardDurability(anchor)
        return
    end

    -- Not docking - release any existing dock first so parenting is clean
    UndockBlizzardDurability()

    if IsHideDefaultDurability() then
        SuppressDurabilityFrame()
    else
        UnsuppressDurabilityFrame()
    end
end

---------------------------------------------------------------------------
-- Equipment slots with durability (in paper-doll display order)
---------------------------------------------------------------------------

local DURABILITY_SLOTS = {
    { id = 1,  name = "Head",      tex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head" },
    { id = 3,  name = "Shoulders", tex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder" },
    { id = 5,  name = "Chest",     tex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest" },
    { id = 6,  name = "Waist",     tex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist" },
    { id = 7,  name = "Legs",      tex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs" },
    { id = 8,  name = "Feet",      tex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet" },
    { id = 9,  name = "Wrists",    tex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists" },
    { id = 10, name = "Hands",     tex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands" },
    { id = 16, name = "Main Hand", tex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand" },
    { id = 17, name = "Off Hand",  tex = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand" },
}

---------------------------------------------------------------------------
-- Durability color ramp: 100% green > 50% yellow > 0% red
---------------------------------------------------------------------------

local function ColorForPct(pct)
    if pct >= 1.0 then return 0.3, 1.0, 0.3 end
    if pct <= 0   then return 1.0, 0.2, 0.2 end
    if pct > 0.5 then
        local t = (1.0 - pct) / 0.5
        return 0.3 + t * 0.7, 1.0, 0.3 - t * 0.3
    else
        local t = (0.5 - pct) / 0.5
        return 1.0, 1.0 - t * 0.8, 0.2
    end
end

local function GetDurability(slotId)
    local cur, max = GetInventoryItemDurability(slotId)
    if not cur or not max or max == 0 then return nil end
    return cur / max
end

---------------------------------------------------------------------------
-- Widget
---------------------------------------------------------------------------

local RepairWidget = {}
addon.RepairWidget = RepairWidget

-- Height depends on the longer of (paper doll block, damaged-list block).
-- When the paper doll is hidden, only the list drives the height.
function RepairWidget:ComputeDesiredHeight(damagedCount)
    local rows = math.max(damagedCount or 0, 1)
    local listHeight = rows * ROW_HEIGHT
    local contentHeight = listHeight
    if ShowPaperDoll() then
        contentHeight = math.max(PAPER_DOLL_HEIGHT, listHeight)
    end
    return PAD + contentHeight + PAD
end

function RepairWidget:GetDesiredHeight()
    return self._desiredHeight or self:ComputeDesiredHeight(0)
end

function RepairWidget:GetStatusText()
    local avg = self._avgPct or 1.0
    local r, g, b = ColorForPct(avg)
    return string.format("%d%%", math.floor(avg * 100 + 0.5)), r, g, b
end

-- Options exposed in the BazUI Drawers > Widgets > Repair page
function RepairWidget:GetOptionsArgs()
    return {
        appearanceHeader = {
            order = 20,
            type = "header",
            name = "Appearance",
        },
        paperDollMode = {
            order = 21,
            type = "select",
            name = "Paper Doll",
            desc = "Choose how the equipment preview is displayed next to the damaged list.",
            values = {
                custom   = "Custom (slot icons)",
                blizzard = "Blizzard (native DurabilityFrame)",
                none     = "None (list only)",
            },
            get = function() return PaperDollMode() end,
            set = function(_, val)
                addon:SetWidgetSetting(WIDGET_ID, "paperDollMode", val)
                -- Clear legacy bool so mode takes precedence
                addon:SetWidgetSetting(WIDGET_ID, "showPaperDoll", nil)
                RepairWidget:Update()
                if addon.WidgetHost then addon.WidgetHost:Reflow() end
            end,
        },
        behaviorHeader = {
            order = 30,
            type = "header",
            name = "Behavior",
        },
        hideBlizzardDurability = {
            order = 31,
            type = "toggle",
            name = "Hide Default Durability Frame",
            desc = "Always hide Blizzard's native durability figure (the little armored man that pops up when gear is damaged), even when this module is disabled or not in Blizzard paper-doll mode.",
            get = function() return IsHideDefaultDurability() end,
            set = function(_, val)
                addon:SetWidgetSetting(WIDGET_ID, "hideBlizzardDurability", val)
                RepairWidget:ApplyVisibility()
            end,
        },
    }
end

-- Public entry point usable from option setters and from the widget host's
-- enable/disable callback. Uses the widget's paper-doll anchor when the
-- frame exists, otherwise passes nil so ApplyDurabilityVisibility will just
-- suppress or restore without attempting to dock.
function RepairWidget:ApplyVisibility()
    local anchor = self.frame and self.frame.paperDollAnchor or nil
    ApplyDurabilityVisibility(anchor, PaperDollMode())
end

function RepairWidget:Build()
    if self.frame then return self.frame end

    local initialHeight = self:ComputeDesiredHeight(0)
    self._desiredHeight = initialHeight
    self._avgPct = 1.0

    local f = CreateFrame("Button", "BazUIDrawerRepairWidget", UIParent)
    f:SetSize(DESIGN_WIDTH, initialHeight)
    f:RegisterForClicks("LeftButtonUp")
    -- Blizzard's own button opens Blizzard's own panel, so the sheet's
    -- OnShow is not ours and may read the player's health. See
    -- BazUI.SecureForward. Calling the toggle ourselves is the fallback
    -- for a client that cannot forward, and throws one error doing it.
    if not BazUI.SecureForward(f, "CharacterMicroButton", { parent = f, relayMotion = f }) then
        f:SetScript("OnClick", function() BazUI.OpenCharacterSheet("PaperDollFrame") end)
    end
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Repair")
        GameTooltip:AddLine("Click to open the character sheet", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Paper-doll anchor: left column (col 1), spans the full widget
    -- content height so whichever paper doll style is active centers
    -- vertically regardless of how tall the damaged list gets.
    local anchor = CreateFrame("Frame", nil, f)
    anchor:SetPoint("TOPLEFT", f, "TOPLEFT", COL1_X, -PAD)
    anchor:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", COL1_X, PAD)
    anchor:SetWidth(COL_WIDTH)
    f.paperDollAnchor = anchor

    -- Custom paper-doll slots (2 cols × 5 rows), centered inside the anchor
    local iconsBlockWidth = 2 * SLOT_SIZE + SLOT_GAP
    local iconsBlockHeight = PAPER_DOLL_HEIGHT
    local iconsFrame = CreateFrame("Frame", nil, anchor)
    iconsFrame:SetSize(iconsBlockWidth, iconsBlockHeight)
    iconsFrame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    f.customIcons = iconsFrame

    f.slots = {}
    for i, info in ipairs(DURABILITY_SLOTS) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local icon = iconsFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(SLOT_SIZE, SLOT_SIZE)
        icon:SetPoint("TOPLEFT",
            col * (SLOT_SIZE + SLOT_GAP),
            -row * (SLOT_SIZE + SLOT_GAP))
        icon:SetTexture(info.tex)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.slots[i] = { icon = icon, info = info }
    end

    -- Damaged list area - rows occupy the middle + right columns
    -- (name left-aligned in col 2, percentage right-aligned in col 3).
    f.listRows = {}

    -- "All OK" fallback when nothing is damaged (anchored in col 2)
    f.allOk = BazUI.Skin.Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.allOk:SetPoint("TOPLEFT", COL2_X, -PAD)
    f.allOk:SetText("All OK")
    f.allOk:SetTextColor(0.3, 1.0, 0.3)
    f.allOk:Hide()

    self.frame = f
    return f
end

function RepairWidget:GetOrCreateRow(index)
    local f = self.frame
    local row = f.listRows[index]
    if row then return row end

    -- Row spans columns 2+3. Name takes column 2 left-aligned, percentage
    -- takes column 3 right-aligned - explicit column anchoring so the
    -- two values line up perfectly between rows.
    row = CreateFrame("Frame", nil, f)
    row:SetHeight(ROW_HEIGHT)

    row.name = BazUI.Skin.Theme.FontString(row, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetWidth(COL_WIDTH)
    row.name:SetJustifyH("LEFT")

    row.pct = BazUI.Skin.Theme.FontString(row, "OVERLAY", "GameFontHighlightSmall")
    row.pct:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.pct:SetWidth(COL_WIDTH)
    row.pct:SetJustifyH("RIGHT")

    f.listRows[index] = row
    return row
end

function RepairWidget:Update()
    local f = self.frame; if not f then return end

    local mode = PaperDollMode()
    local showCustom = (mode == "custom")
    local total, count = 0, 0
    local damaged = {}

    -- Custom paper doll icons
    for i, entry in ipairs(f.slots) do
        local info = entry.info

        if showCustom then
            entry.icon:Show()
            local itemTex = GetInventoryItemTexture("player", info.id)
            if itemTex then
                entry.icon:SetTexture(itemTex)
            else
                entry.icon:SetTexture(info.tex)
            end
        else
            entry.icon:Hide()
        end

        local pct = GetDurability(info.id)
        if pct then
            if showCustom then
                local r, g, b = ColorForPct(pct)
                entry.icon:SetVertexColor(r, g, b, 1)
            end
            total = total + pct
            count = count + 1
            if pct < 1.0 then
                table.insert(damaged, { name = info.name, pct = pct })
            end
        elseif showCustom then
            entry.icon:SetVertexColor(0.4, 0.4, 0.4, 0.7)
        end
    end

    -- DurabilityFrame dispatch: dock it if we're actively using blizzard
    -- paper-doll mode, otherwise hide it outright so it can't auto-surface
    -- when durability drops. ApplyDurabilityVisibility handles all the
    -- dock/undock/suppress/unsuppress transitions.
    ApplyDurabilityVisibility(f.paperDollAnchor, mode)

    -- Show/hide the custom icons frame as a unit
    if mode == "custom" then
        f.customIcons:Show()
    else
        f.customIcons:Hide()
    end

    -- Cache average for GetStatusText (used by the slot title bar)
    self._avgPct = (count > 0) and (total / count) or 1.0

    -- Sort worst first, build list rows
    table.sort(damaged, function(a, b) return a.pct < b.pct end)

    -- Recompute desired height and trigger a reflow if the widget needs
    -- to grow or shrink.
    local newHeight = self:ComputeDesiredHeight(#damaged)
    if newHeight ~= self._desiredHeight then
        self._desiredHeight = newHeight
        f:SetHeight(newHeight)
        if addon.WidgetHost and addon.WidgetHost.Reflow then
            addon.WidgetHost:Reflow()
        end
    end

    for _, row in ipairs(f.listRows) do row:Hide() end

    if #damaged == 0 then
        f.allOk:Show()
    else
        f.allOk:Hide()
        for i, d in ipairs(damaged) do
            local row = self:GetOrCreateRow(i)
            local rowY = -PAD - (i - 1) * ROW_HEIGHT
            row:ClearAllPoints()
            -- Row spans from start of column 2 to end of column 3
            row:SetPoint("TOPLEFT", f, "TOPLEFT", COL2_X, rowY)
            row:SetPoint("TOPRIGHT", f, "TOPLEFT",
                COL3_X + COL_WIDTH, rowY)
            row.name:SetText(d.name)
            row.pct:SetText(string.format("%d%%", math.floor(d.pct * 100 + 0.5)))
            local r, g, b = ColorForPct(d.pct)
            row.pct:SetTextColor(r, g, b)
            row.name:SetTextColor(0.85, 0.85, 0.85)
            row:Show()
        end
    end

    -- Refresh the slot title bar's status text (avg %)
    if addon.WidgetHost and addon.WidgetHost.UpdateWidgetStatus then
        addon.WidgetHost:UpdateWidgetStatus("bazdrawer_repair")
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function RepairWidget:Init()
    local f = self:Build()

    BazUI:RegisterDockableWidget({
        id = WIDGET_ID,
        label = "Repair",
        designWidth = DESIGN_WIDTH,
        designHeight = self._desiredHeight or self:ComputeDesiredHeight(0),
        frame = f,
        GetDesiredHeight = function() return RepairWidget:GetDesiredHeight() end,
        GetStatusText    = function() return RepairWidget:GetStatusText() end,
        GetOptionsArgs   = function() return RepairWidget:GetOptionsArgs() end,
    })

    f:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:HookScript("OnEvent", function() RepairWidget:Update() end)

    -- Apply durability visibility independently of the widget's own
    -- update cycle so the suppression kicks in even if the module is
    -- disabled. Without this, a disabled Repair module leaves Blizzard's
    -- DurabilityFrame free to auto-pop whenever gear drops below 50%.
    self:ApplyVisibility()

    self:Update()
end

BazUI:QueueForModule("Drawers", function() RepairWidget:Init() end)
