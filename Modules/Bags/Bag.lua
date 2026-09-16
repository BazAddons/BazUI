-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Bags - bag panel UI
--
-- One panel for every bag, built from Blizzard's own pieces so item
-- interaction behaves exactly like the stock bags:
--   * Frame:  BazUI:CreatePortraitWindow (PortraitFrameTemplate)
--   * Slots:  ContainerFrameItemButtonTemplate, the template Blizzard's
--             Classic ContainerFrame uses; updated the way its
--             ContainerFrame_Update does (quality, quest overlay, new-item
--             glow, junk coin, cooldown, search dimming)
--   * Money:  SmallMoneyFrameTemplate
--   * Search: BagSearchBoxTemplate
--
-- Layered on top: collapsible sections per bag type (Bags, Keyring, and a
-- reagent bag where the client has one), a categories mode, and pinning.
---------------------------------------------------------------------------

local MODULE_NAME = "Bags"
local addon = BazUI:GetAddon(MODULE_NAME)
if not addon then return end

local Bag = {}
addon.Bag = Bag

---------------------------------------------------------------------------
-- Layout constants - chosen to match Blizzard's combined bag exactly.
---------------------------------------------------------------------------

local DEFAULT_COLS      = 8       -- starting column count when no setting saved
local SLOT_SIZE         = 37      -- ContainerFrameItemButtonTemplate native size
local SLOT_SPACING_X    = 5       -- Blizzard's ITEM_SPACING_X
local SLOT_SPACING_Y    = 4
local SECTION_HEADER_H  = 20
local TOP_PAD           = 60      -- below title bar - leaves room for search/sort row
local SIDE_PAD          = 12

-- Live setting readers - re-evaluated on every Refresh so the panel
-- reshapes immediately when the user moves the Columns slider or
-- toggles Hide Empty on the General Settings page.
local function GetCols()
    local v = addon:GetSetting("cols")
    return (type(v) == "number" and v >= 1) and v or DEFAULT_COLS
end

local function HideEmpty()
    return addon:GetSetting("hideEmpty") and true or false
end

local function PanelWidthFor(cols)
    return cols * SLOT_SIZE + math.max(0, cols - 1) * SLOT_SPACING_X + SIDE_PAD * 2
end

-- Bag type > section definition, rebuilt per refresh: the keyring only
-- exists once the character owns a key, and a reagent bag only on
-- clients that have one.
local function GetSectionDefs()
    local defs = {
        { key = "bags", title = "Bags", bagIDs = addon.GetMainBagIDs() },
    }
    local keyring = addon.GetKeyringBagID()
    if keyring then
        defs[#defs + 1] = { key = "keyring", title = "Keyring", bagIDs = { keyring } }
    end
    local reagent = addon.GetReagentBagID()
    if reagent then
        defs[#defs + 1] = { key = "reagents", title = "Reagents", bagIDs = { reagent } }
    end
    return defs
end

-- Category data and layouts live in their own modules - see
-- Categories.lua and Layouts.lua. Bag.lua keeps the panel chrome,
-- the bag-mode rendering, and the Refresh dispatcher.

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local frame                       -- top-level panel
local bagContexts   = {}          -- [bagID] = invisible parent (provides GetID + IsCombinedBagContainer for slots)
local slotButtons   = {}          -- [bagID] = { [slotID] = button }
local sections      = {}          -- [key]   = { header, body, ... }
local refreshPending = false
local categorizeMode = false      -- toggled via left-click on the portrait;
                                  -- when on, the category layout shows drop
                                  -- slots + empty categories so the user can
                                  -- pin items by dropping them. In-memory
                                  -- only - resets to off on /reload.

-- Sections is exposed so the Layouts module can hide them when it
-- takes over (e.g. switching from Sections to Flow mode). Other
-- internals are exposed at the bottom of the section-builder block
-- once the helpers are defined.
addon.Bag.sections = sections

---------------------------------------------------------------------------
-- Section collapse persistence
---------------------------------------------------------------------------

local function IsCollapsed(key)
    local map = addon:GetSetting("sectionCollapsed") or {}
    return map[key] and true or false
end

local function SetCollapsed(key, val)
    local map = addon:GetSetting("sectionCollapsed") or {}
    map[key] = val and true or false
    addon:SetSetting("sectionCollapsed", map)
end

---------------------------------------------------------------------------
-- Bag context frames + item slot construction
--
-- Each slot needs to be parented to a frame whose GetID() returns the
-- bag ID. The slot template's mixin reads `parent:IsCombinedBagContainer()`
-- in Initialize() - when that returns true, it adds the proper
-- ItemSlotBackgroundCombinedBagsTemplate texture (leather/brown art),
-- which is what makes empty slots look like Blizzard's combined bag
-- instead of the default ItemButton "blue square" appearance.
---------------------------------------------------------------------------

local SLOT_TEMPLATE = "ContainerFrameItemButtonTemplate"
local slotFrameType

-- The slot template is a Button on Classic clients and an ItemButton on
-- newer ones; ask the client rather than guess.
local function SlotFrameType()
    if slotFrameType then return slotFrameType end
    local info = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(SLOT_TEMPLATE)
    slotFrameType = (info and info.type) or "Button"
    return slotFrameType
end

local function GetOrCreateBagContext(bagID)
    if bagContexts[bagID] then return bagContexts[bagID] end
    -- Parent to scrollChild (when it exists) so slot buttons live
    -- inside the scroll hierarchy and get clipped + translated when
    -- the panel scrolls. Falls back to frame for the (vanishingly
    -- small) window between BuildFrame's first lines and the scroll
    -- frame's creation.
    local parent = (frame and frame.scrollChild) or frame
    local f = CreateFrame("Frame", nil, parent)
    f:SetID(bagID)
    f:SetSize(1, 1)
    -- Blizzard's slot Initialize checks this to add the combined-bag bg.
    f.IsCombinedBagContainer = function() return true end
    bagContexts[bagID] = f
    return f
end

local function GetOrCreateSlotButton(bagID, slotID)
    slotButtons[bagID] = slotButtons[bagID] or {}
    if slotButtons[bagID][slotID] then return slotButtons[bagID][slotID] end

    -- A protected frame cannot be created, moved or shown in combat, so
    -- there is nothing to do here until the fight ends. Refresh knows to
    -- come back.
    if InCombatLockdown() then return nil end

    local parent = GetOrCreateBagContext(bagID)
    local name = "BazUIBagSlot_" .. bagID .. "_" .. slotID
    local btn = CreateFrame(SlotFrameType(), name,
        parent, SLOT_TEMPLATE .. ",SecureActionButtonTemplate")

    -- Using an item has to be the game's doing rather than ours.
    --
    -- The slot template's own click handler calls UseContainerItem, and
    -- that call is refused for anything an addon made: the button is
    -- ours, so the code path is ours, so the game will not run a
    -- protected function down it. No amount of care on this side changes
    -- that, and reusing Blizzard's own buttons does not either - the
    -- taint follows the moment they are reparented.
    --
    -- So the right button is handed to the secure environment, which
    -- takes a bag and a slot and uses what is in it. Everything else a
    -- slot does - picking up, dropping, linking, splitting - is
    -- unprotected and stays with Blizzard's handler, called from PreClick
    -- below because inheriting the secure template replaced it.
    btn:SetAttribute("type2", "item")
    btn:SetAttribute("item", bagID .. " " .. slotID)
    btn:RegisterForClicks("AnyUp")

    -- Initialize handles SetID, SetBagID attribute, ItemSlotBackground
    -- (the combined-bag leather background), and Show. Without this we
    -- get the default empty-slot appearance, which is the source of the
    -- blue tint on empty slots reported earlier.
    if btn.Initialize then
        btn:Initialize(bagID, slotID)
    else
        btn:SetID(slotID)
    end

    -- Shift+right-click > category context menu. PreClick fires before
    -- the secure action handler (which would normally use the item on
    -- right-click), so we can show our menu without losing the rest of
    -- the slot's standard behavior. shift+right is unbound by default
    -- in modern WoW so this doesn't compete with use-item / split-stack.
    btn:HookScript("PreClick", function(self, mouseBtn)
        if mouseBtn == "RightButton" and IsShiftKeyDown() then
            Bag:ShowCategoryMenuForSlot(self, bagID, slotID)
            return
        end

        -- What the slot template's own OnClick used to do, for the
        -- clicks the secure handler is not answering. A plain right
        -- click is the one it does answer, and doing it here as well
        -- would be asking twice for the same thing - once refused.
        if mouseBtn == "RightButton" and not IsModifiedClick() then return end

        if IsModifiedClick() then
            if _G.ContainerFrameItemButton_OnModifiedClick then
                _G.ContainerFrameItemButton_OnModifiedClick(self, mouseBtn)
            end
        elseif _G.ContainerFrameItemButton_OnClick then
            _G.ContainerFrameItemButton_OnClick(self, mouseBtn)
        end
    end)

    -- Blizzard's Classic modified-click handler opens the stack-split
    -- dialog for the same gesture on stacks. Our menu offers "Split
    -- stack..." explicitly, so close Blizzard's dialog again if this
    -- click opened it.
    btn:HookScript("PostClick", function(self, mouseBtn)
        if mouseBtn == "RightButton" and IsShiftKeyDown() and StackSplitFrame
           and StackSplitFrame.owner == self and StackSplitFrame:IsShown() then
            StackSplitFrame:Hide()
        end
    end)

    slotButtons[bagID][slotID] = btn
    return btn
end

---------------------------------------------------------------------------
-- Category context menu (shift+right-click on a bag item)
--
-- Shows a MenuUtil context menu listing every category with the
-- current pin highlighted. Clicking a category pins the item there;
-- clicking the already-pinned category unpins. An explicit "Unpin"
-- entry is included whenever a pin exists for ergonomic discovery.
---------------------------------------------------------------------------

-- Small green check icon used to mark the active pin in the menu.
local CHECK_GLYPH = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t"

-- Register BazUI Bags's contribution to the shared "bag-item" context-menu
-- scope. Other addons can register their own sections against the same
-- scope (BazTooltipEditor's "Inspect tooltip", e.g.) and they all show
-- up in one menu when the user shift+right-clicks a bag slot.
local function GetBazBagsSection(ctx)
    if not ctx or not ctx.itemID then return end

    local pins       = addon:GetSetting("itemCategories") or {}
    local currentKey = pins[ctx.itemID]

    local Categories = addon.Categories
    if not Categories then return end
    local cats = Categories.GetAll() or {}

    -- Build the category submenu items first; they live inside a
    -- single "Category" parent at the top level so the BazUI Bags section
    -- isn't 8-10 categories tall on every shift+right-click.
    local categoryItems = {}
    for _, cat in ipairs(cats) do
        local label = cat.name or cat.key
        if cat.hidden then
            label = label .. "  |cff888888(hidden)|r"
        end
        if cat.key == currentKey then
            label = "|cffffd700" .. CHECK_GLYPH .. " " .. label .. "|r"
        end
        local capturedKey = cat.key
        categoryItems[#categoryItems + 1] = {
            label = label,
            onClick = function()
                if capturedKey == currentKey then
                    Categories.RemoveItem(ctx.itemID)
                else
                    Categories.AddItem(ctx.itemID, capturedKey)
                end
                if Bag.Refresh then Bag:Refresh() end
            end,
        }
    end

    local items = {
        { label = "Category", submenu = categoryItems },
    }

    if currentKey then
        items[#items + 1] = {
            label = "Unpin (auto-classify)",
            onClick = function()
                Categories.RemoveItem(ctx.itemID)
                if Bag.Refresh then Bag:Refresh() end
            end,
        }
    end

    -- Split stack entry. BazUI Bags's shift+right-click intercepts
    -- Blizzard's default split-stack gesture, so we have to expose
    -- it here. StackSplitFrame normally lives at DIALOG strata; bump
    -- it above BazUI Bags's own DIALOG-strata panel so it pops on top.
    if ctx.button and ctx.stackCount and ctx.stackCount > 1 and not ctx.isLocked then
        local bagID, slotID = ctx.bagID, ctx.slotID
        local btn = ctx.button
        items[#items + 1] = {
            label = "Split stack...",
            onClick = function()
                if not StackSplitFrame then return end
                btn.SplitStack = function(_, amount)
                    C_Container.SplitContainerItem(bagID, slotID, amount)
                end
                StackSplitFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                if StackSplitFrame.OpenStackSplitFrame then
                    StackSplitFrame:OpenStackSplitFrame(ctx.stackCount, btn, "BOTTOMRIGHT", "TOPRIGHT")
                elseif OpenStackSplitFrame then
                    OpenStackSplitFrame(ctx.stackCount, btn, "BOTTOMRIGHT", "TOPRIGHT")
                end
            end,
        }
    end

    return items
end

if BazUI.RegisterContextMenuSection then
    BazUI:RegisterContextMenuSection("bag-item", "Bags", GetBazBagsSection)
end

function Bag:ShowCategoryMenuForSlot(anchor, bagID, slotID)
    local info = C_Container.GetContainerItemInfo(bagID, slotID)
    if not info or not info.itemID then return end  -- empty slot

    if BazUI.OpenContextMenu then
        -- No title intentionally - the bag slot's icon is right next
        -- to the menu, so an item-link title would just echo what the
        -- user can already see.
        BazUI:OpenContextMenu("bag-item", anchor, {
            button   = anchor,
            bagID    = bagID,
            slotID   = slotID,
            itemID   = info.itemID,
            itemLink = info.hyperlink,
            stackCount = info.stackCount,
            isLocked   = info.isLocked,
        })
    end
end

---------------------------------------------------------------------------
-- Slot rendering - mirrors Blizzard's Classic ContainerFrame_Update.
-- Every piece is optional-guarded so a client that lacks one of the
-- template's children (or ships a mixin instead) still renders the rest.
---------------------------------------------------------------------------

local NEW_ITEM_FALLBACK_ATLAS = "bags-glow-white"

local function UpdateSlot(btn, bagID, slotID)
    local info = C_Container.GetContainerItemInfo(bagID, slotID)
    local texture    = info and info.iconFileID
    local count      = info and info.stackCount
    local locked     = info and info.isLocked
    local quality    = info and info.quality
    local link       = info and info.hyperlink
    local isFiltered = info and info.isFiltered
    local noValue    = info and info.hasNoValue
    local itemID     = info and info.itemID
    local name       = btn:GetName()

    if ClearItemButtonOverlay then ClearItemButtonOverlay(btn) end
    SetItemButtonTexture(btn, texture)
    SetItemButtonQuality(btn, quality, link or itemID)
    SetItemButtonCount(btn, count)
    SetItemButtonDesaturated(btn, locked)

    -- Quest overlay: a bang for a quest starter you haven't accepted,
    -- the border for any other quest item.
    local questTexture = btn.IconQuestTexture or (name and _G[name .. "IconQuestTexture"])
    if questTexture then
        local q = texture and C_Container.GetContainerItemQuestInfo(bagID, slotID)
        if q and q.questID and not q.isActive then
            questTexture:SetTexture(TEXTURE_ITEM_QUEST_BANG)
            questTexture:Show()
        elseif q and (q.questID or q.isQuestItem) then
            questTexture:SetTexture(TEXTURE_ITEM_QUEST_BORDER)
            questTexture:Show()
        else
            questTexture:Hide()
        end
    end

    -- New-item glow, Blizzard's rules: quality-colored atlas, one flash,
    -- then the slow pulse until the item is touched.
    local newTex, flash, glow = btn.NewItemTexture, btn.flashAnim, btn.newitemglowAnim
    if newTex then
        local isNew = texture and C_NewItems and C_NewItems.IsNewItem
            and C_NewItems.IsNewItem(bagID, slotID)
        if isNew then
            local atlas = (quality and NEW_ITEM_ATLAS_BY_QUALITY and NEW_ITEM_ATLAS_BY_QUALITY[quality])
                or NEW_ITEM_FALLBACK_ATLAS
            BazUI.SetAtlasOrTexture(newTex, atlas, nil)
            newTex:Show()
            if flash and glow and not flash:IsPlaying() and not glow:IsPlaying() then
                flash:Play()
                glow:Play()
            end
        else
            newTex:Hide()
            if flash and flash:IsPlaying() then flash:Stop() end
            if glow and glow:IsPlaying() then glow:Stop() end
        end
    end
    if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide() end
    if btn.UpgradeIcon then btn.UpgradeIcon:Hide() end

    -- Junk coin only while a merchant is open, like the stock bags.
    if btn.JunkIcon then
        btn.JunkIcon:SetShown(texture and quality == 0 and not noValue
            and MerchantFrame and MerchantFrame:IsShown() or false)
    end

    -- Cooldown sweep
    local cooldown = btn.Cooldown or (name and _G[name .. "Cooldown"])
    if texture and ContainerFrame_UpdateCooldown and name then
        ContainerFrame_UpdateCooldown(bagID, btn)
        btn.hasItem = 1
    elseif cooldown then
        cooldown:Hide()
        btn.hasItem = nil
    end
    btn.readable = info and info.isReadable

    -- Search dimming
    if btn.SetMatchesSearch then
        btn:SetMatchesSearch(not isFiltered)
    elseif btn.searchOverlay then
        btn.searchOverlay:SetShown(isFiltered and true or false)
    end
end

---------------------------------------------------------------------------
-- Section builder
---------------------------------------------------------------------------

local function BuildSection(def)
    local section = { def = def }

    -- Sections live inside scrollChild so they scroll with the rest of
    -- the bag content. Falls back to frame in the unlikely case the
    -- scroll frame isn't built yet.
    local parent = (frame and frame.scrollChild) or frame

    local header = CreateFrame("Button", nil, parent)
    header:SetHeight(SECTION_HEADER_H)
    section.header = header

    local hover = header:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.04)
    hover:Hide()

    local toggle = header:CreateTexture(nil, "OVERLAY")
    toggle:SetSize(14, 14)
    toggle:SetPoint("LEFT", 4, 0)
    section.toggle = toggle

    local title = BazUI.Skin.Theme.FontString(header, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", toggle, "RIGHT", 6, 0)
    title:SetText(def.title)
    title:SetTextColor(1.00, 0.82, 0.00)  -- suite gold to read as a "Baz section"
    section.title = title

    local count = BazUI.Skin.Theme.FontString(header, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("RIGHT", -8, 0)
    section.count = count

    header:SetScript("OnEnter", function() hover:Show() end)
    header:SetScript("OnLeave", function() hover:Hide() end)
    header:SetScript("OnClick", function()
        SetCollapsed(def.key, not IsCollapsed(def.key))
        Bag:Refresh()
    end)

    -- Body holds the slot buttons. Height is computed in Refresh().
    local body = CreateFrame("Frame", nil, parent)
    section.body = body

    return section
end

local function GetOrCreateSection(def)
    local section = sections[def.key]
    if not section then
        section = BuildSection(def)
        sections[def.key] = section
    end
    section.def = def
    return section
end

-- Public API surface for the Layouts module. Capturing the locals
-- on addon.Bag means Layouts.lua can drive the same rendering
-- primitives without re-implementing them.
addon.Bag.IsCollapsed           = IsCollapsed
addon.Bag.SetCollapsed          = SetCollapsed
addon.Bag.GetOrCreateSlotButton = GetOrCreateSlotButton
addon.Bag.UpdateSlot            = UpdateSlot

---------------------------------------------------------------------------
-- Top-level panel
---------------------------------------------------------------------------

local function BuildFrame()
    if frame then return frame end

    local panelW = PanelWidthFor(GetCols())

    -- BazUI handles the Blizzard-styled chrome (PortraitFrameFlatTemplate)
    -- including title bar, portrait, close button, drag, and ESC-close.
    -- Anything bag-specific (search, sort, money, slots) we add ourselves.
    frame = BazUI:CreatePortraitWindow("BazUIBagsFrame", {
        title          = "Bags",
        -- The module's own icon, shared with the minimap entry and the
        -- options panel. (A Retail-only file ID here drew green on Era.)
        portrait       = addon.config.minimap.icon,
        width          = panelW,
        height         = 400,
        savedAddon     = addon,
        savedKey       = "position",
        uiSpecialFrame = true,
        -- DIALOG by default so the bag floats above the BazUI
        -- Settings window (HIGH) - see the Strata setting in
        -- Settings > Layout for picking a different layer.
        strata         = addon:GetSetting("strata") or "DIALOG",

        -- Hover the portrait > tooltip explaining the click actions.
        -- Left-click sorts the bag (Blizzard's C_Container.SortBags).
        -- Middle-click toggles Categorize mode (drop slots + every
        -- category visible, for batch-pinning items). Right-click
        -- opens the bag-change popup. Drag from anywhere else on
        -- the title bar still works to move the frame.
        portraitTooltip = {
            title = "Bags",
            lines = {
                "|cffffd700Left-click|r to sort bags",
                "|cffffd700Middle-click|r to toggle Categorize mode",
                "|cffffd700Right-click|r to change bags",
                "|cffffd700Drag the title bar|r to move the panel",
            },
        },
        portraitOnClick = function(_, button)
            if button == "LeftButton" then
                addon.SortBags()
            elseif button == "MiddleButton" then
                Bag:ToggleCategorizeMode()
            elseif button == "RightButton" then
                Bag:ToggleBagChangePopup()
            end
        end,
    })

    -- Search box - Blizzard's BagSearchBoxTemplate handles the icon,
    -- placeholder text, focus/blur visuals, and live filtering of
    -- ContainerFrameItemButton instances via SetMatchesSearch. The
    -- right edge anchors to the money frame's LEFT so the search box
    -- automatically shrinks when the player's gold total grows wider.
    -- (We dropped Blizzard's auto-sort 'broom' button - /bbg sort
    -- still runs C_Container.SortBags on demand, and the corner real
    -- estate is now used for the money display.)
    frame.search = CreateFrame("EditBox", nil, frame, "BagSearchBoxTemplate")
    frame.search:SetHeight(18)
    frame.search:SetPoint("TOPLEFT", 62, -37)

    -- Solid backing layer behind the panel's translucent stock
    -- background. PortraitFrameFlatTemplate's Bg uses
    -- PANEL_BACKGROUND_COLOR which has built-in alpha (~0.7) - so
    -- frame.Bg:SetAlpha(1) still reads as see-through. This extra
    -- texture sits *under* frame.Bg at sub-level -1 so the dark
    -- overlay still tints the panel, but at 100% opacity the result
    -- is fully solid. Both layers scale together with the bgAlpha
    -- setting (Refresh applies SetAlpha to both).
    --
    -- Uses Blizzard's "spec-background" atlas - the same textured
    -- mid-gray backdrop the BazUI standalone options window uses,
    -- so the bag panel reads as part of the game UI rather than a
    -- stark dark void.
    frame.solidBg = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    BazUI.SetAtlasOrTexture(frame.solidBg, "spec-background", "Interface\\FrameGeneral\\UI-Background-Rock")
    frame.solidBg:SetPoint("TOPLEFT",     2, -20)
    frame.solidBg:SetPoint("BOTTOMRIGHT", -2, 3)

    -- Money frame - Blizzard's exact gold/silver/copper readout.
    -- Anchored where Blizzard's auto-sort button used to live so the
    -- player's gold sits next to the title bar instead of taking a
    -- whole row at the bottom of the panel.
    --
    -- Anchored by its RIGHT (right-middle) edge instead of TOPRIGHT so
    -- the vertical center lines up with the search bar's center
    -- regardless of the money frame's intrinsic height (which varies
    -- with Blizzard's template). Search bar center:
    --   TOPLEFT y = -37, height 18  >  center y = -46
    -- Pinning money's right-middle to (-12, -46) puts both centers on
    -- the same horizontal line.
    frame.money = CreateFrame("Frame", "BazUIBagsMoneyFrame", frame, "SmallMoneyFrameTemplate")
    frame.money:ClearAllPoints()
    frame.money:SetPoint("RIGHT", frame, "TOPRIGHT", -12, -47)
    frame.search:SetPoint("RIGHT", frame.money, "LEFT", -8, 0)

    -- Scroll container for the bag content (sections, dividers, slots).
    -- All content anchors to scrollChild so when the player has more
    -- items than the maxHeight setting allows, scrollFrame clips the
    -- overflow and the mouse wheel handler shifts the visible slice.
    -- Positioned between the search bar (top chrome) and the
    -- money/tokens row (bottom chrome) - its exact height is
    -- recomputed every Refresh. We deliberately use a bare ScrollFrame
    -- without a scrollbar template (Blizzard's modern minimal scrollbar
    -- is wired to ScrollBox, not plain ScrollFrame) and rely on the
    -- mouse wheel for scrolling.
    local sf = CreateFrame("ScrollFrame", nil, frame)
    sf:SetPoint("TOPLEFT",  frame, "TOPLEFT",  SIDE_PAD, -TOP_PAD)
    sf:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_PAD, -TOP_PAD)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        if (self.bazMaxScroll or 0) <= 0 then return end
        local cur = self:GetVerticalScroll() or 0
        local next = cur - delta * 30
        if next < 0 then next = 0 end
        if next > self.bazMaxScroll then next = self.bazMaxScroll end
        self:SetVerticalScroll(next)
    end)
    frame.scrollFrame = sf

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(1, 1)  -- resized per refresh; width tracks scrollFrame
    sf:SetScrollChild(sc)
    frame.scrollChild = sc

    -- Divider rule between the scroll area and the footer chrome
    -- (money + tokens). Without it the last row of items reads as
    -- bleeding into the gold / currency strip - this gives the eye
    -- a clear "end of bag content" line. Same warm-gold tone as the
    -- category dividers inside the scroll area for consistency.
    frame.contentDivider = frame:CreateTexture(nil, "ARTWORK")
    frame.contentDivider:SetHeight(1)
    frame.contentDivider:SetColorTexture(0.55, 0.42, 0.18, 0.85)
    frame.contentDivider:SetPoint("TOPLEFT",  sf, "BOTTOMLEFT",  0, -3)
    frame.contentDivider:SetPoint("TOPRIGHT", sf, "BOTTOMRIGHT", 0, -3)

    -- Expose the live frame so settings setters (e.g. Frame Strata)
    -- can poke it directly without going through Refresh.
    addon.Bag.frame = frame

    -- Hide every slot button whenever the panel closes. The slots are
    -- ContainerFrameItemButtonTemplate frames, and third-party bag
    -- overlays (Vaultloom's Bag Item Level, for one) track every such
    -- button and refresh it on BAG_UPDATE_DELAYED whenever IsShown() is
    -- true - parent visibility isn't consulted. With the panel hidden
    -- but ~200 slots still flagged Shown, every loot event triggered an
    -- item-level scan of all of them: a visible hitch with the bag
    -- closed. Refresh re-shows exactly the slots it lays out, so this
    -- is the only change needed.
    frame:HookScript("OnHide", function()
        for _, slots in pairs(slotButtons) do
            for _, btn in pairs(slots) do btn:Hide() end
        end
    end)

    return frame
end

---------------------------------------------------------------------------
-- Bag-change popup
--
-- A small floating panel anchored under the portrait. Holds five bag
-- slot buttons - the four equipped bag slots plus the reagent bag.
-- Drag a bag from your inventory onto a slot to equip it; drag a slot
-- icon off to clear it. Mirrors what Blizzard surfaces via the
-- character pane's "Bags" tab, just one click closer.
---------------------------------------------------------------------------

-- Resolve the inventory slot IDs for the player's equipped bags.
--
-- Earlier we hardcoded {20, 21, 22, 23, 24} (the INVSLOT_BAG_* values
-- from TWW 11.x), but Midnight 12.0 renumbered the equipped slots:
-- INVSLOT_BAG_* aren't exported as globals anymore, and slot 20 in
-- particular is now a profession tool slot - that's why the popup
-- was showing alchemy tools instead of bags.
--
-- C_Container.ContainerIDToInventoryID is the canonical mapping from
-- a container's bag index to its inventory slot, and Blizzard's own
-- character pane goes through it. We resolve once on first use so
-- we don't pay the lookup cost on every popup show.
local BAG_SLOT_INV_IDS
local function ResolveBagSlots()
    if BAG_SLOT_INV_IDS then return BAG_SLOT_INV_IDS end

    local slots = {}
    local C = C_Container
    if not (C and C.ContainerIDToInventoryID) then
        -- Defensive: very old clients fall back to the legacy values.
        -- Modern retail always has the API, so this branch is dead in
        -- practice but keeps the popup from crashing if it's missing.
        BAG_SLOT_INV_IDS = { 20, 21, 22, 23, 24 }
        return BAG_SLOT_INV_IDS
    end

    -- Backpack is bag index 0 (and lives at INVSLOT_BACKPACK / cursor
    -- slot 0); the four equipable bag slots are indices 1..4 and the
    -- reagent bag is index 5. Width-defensive on NUM_BAG_SLOTS so we
    -- pick up the count Blizzard exposes rather than assuming four.
    local numBags = NUM_BAG_SLOTS or 4
    for bagID = 1, numBags do
        local invID = C.ContainerIDToInventoryID(bagID)
        if invID then slots[#slots + 1] = invID end
    end

    if (NUM_REAGENTBAG_SLOTS or 0) > 0 then
        local reagentBagID = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag)
                             or (numBags + 1)
        local invID = C.ContainerIDToInventoryID(reagentBagID)
        if invID then slots[#slots + 1] = invID end
    end

    BAG_SLOT_INV_IDS = slots
    return slots
end

local function UpdateBagSlotButton(btn)
    local slot = btn.invSlot
    local link    = GetInventoryItemLink("player", slot)
    local texture = GetInventoryItemTexture("player", slot)

    btn:SetIconTexture(texture)
    if link then
        local _, _, quality = C_Item.GetItemInfo(link)
        btn:SetQuality(quality, link)
    else
        btn:SetQuality(0)
    end
end

local function BuildBagSlotButton(parent, invSlot, isReagent)
    -- BazUI:CreateItemButton hands us an ItemButton-styled frame
    -- (icon + quality border + slot background + highlight + pushed)
    -- without going through ItemButtonTemplate / BagSlotButtonTemplate
    -- - both of those exist in Blizzard's XML but aren't exposed as
    -- runtime CreateFrame targets in retail Midnight. The bag-slot
    -- background uses the same "bags-item-slot64" atlas as Blizzard's
    -- combined bag, so empty slots show the familiar slot artwork.
    local btn = BazUI:CreateItemButton(parent, {
        size        = 36,
        slotAtlas   = "bags-item-slot64",
        slotTexture = "Interface\\Buttons\\UI-EmptySlot-Disabled",
    })
    btn:SetID(invSlot)
    btn.invSlot = invSlot
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not GameTooltip:SetInventoryItem("player", self.invSlot) then
            GameTooltip:SetText(isReagent and (REAGENT_BAG_HELP_TEXT or "Reagent Bag")
                                or "Bag Slot")
            GameTooltip:AddLine("Drag a bag here to equip it.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function(self)
        -- If the cursor has an item, drop it into this slot.
        -- Otherwise no-op (don't toggle a bag - that's not the
        -- popup's purpose).
        if CursorHasItem() then
            PutItemInBag(self.invSlot)
        end
    end)

    btn:SetScript("OnDragStart", function(self)
        PickupBagFromSlot(self.invSlot)
    end)

    btn:SetScript("OnReceiveDrag", function(self)
        PutItemInBag(self.invSlot)
    end)

    return btn
end

local bagPopup
local function BuildBagChangePopup()
    if bagPopup then return bagPopup end
    if not frame then return nil end

    local PAD = 8
    local POPUP_SLOT = 36
    local SLOT_GAP  = 4
    local invSlots  = ResolveBagSlots()
    local slotCount = #invSlots

    local p = CreateFrame("Frame", "BazUIBagsBagChangePopup", frame, "BackdropTemplate")
    p:SetSize(PAD * 2 + slotCount * POPUP_SLOT + (slotCount - 1) * SLOT_GAP,
              PAD * 2 + POPUP_SLOT + 18)
    p:SetFrameStrata("DIALOG")
    BazUI.Skin.Theme.ApplyFlatPanel(p)
    p:Hide()

    -- Position is set per-Show in PositionBagPopup so we adapt to the
    -- bag's current screen position (above when there's room, below
    -- otherwise) - see the comment block on PositionBagPopup.

    -- Header label
    p.title = BazUI.Skin.Theme.FontString(p, "OVERLAY", "GameFontNormalSmall")
    p.title:SetPoint("TOPLEFT", PAD, -PAD)
    p.title:SetText("Bag Slots")
    p.title:SetTextColor(1.00, 0.82, 0.00)

    -- Bag buttons in a row
    p.buttons = {}
    for i, invSlot in ipairs(invSlots) do
        local isReagent = (i == #invSlots) and (NUM_REAGENTBAG_SLOTS or 0) > 0
        local btn = BuildBagSlotButton(p, invSlot, isReagent)
        btn:SetSize(POPUP_SLOT, POPUP_SLOT)
        btn:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT",
            PAD + (i - 1) * (POPUP_SLOT + SLOT_GAP), PAD)
        p.buttons[i] = btn
    end

    -- Refresh on inventory changes
    local ev = CreateFrame("Frame", nil, p)
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:RegisterEvent("UNIT_INVENTORY_CHANGED")
    ev:SetScript("OnEvent", function()
        if not p:IsShown() then return end
        for _, b in ipairs(p.buttons) do UpdateBagSlotButton(b) end
    end)

    bagPopup = p
    return p
end

-- Position the popup outside the bag panel so it doesn't obscure
-- bag contents. We pick the side adaptively: above the bag when
-- there's screen room (so the popup floats near the portrait the
-- user just clicked), below the bag when the panel is already near
-- the top of the screen. The 80 px threshold leaves a comfortable
-- gap for the popup's ~62 px height plus the small visual offset.
local function PositionBagPopup(p)
    if not p or not frame then return end
    p:ClearAllPoints()

    local screenH    = UIParent and UIParent:GetHeight() or 1080
    local bagTop     = frame:GetTop() or screenH
    local roomAbove  = screenH - bagTop

    if roomAbove >= 80 then
        -- Above the bag, x-offset clears the portrait so the popup
        -- sits beside it rather than under it.
        p:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 56, 4)
    else
        -- Below the bag, aligned to the left edge.
        p:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -4)
    end
end

function Bag:ToggleBagChangePopup()
    local p = BuildBagChangePopup()
    if not p then return end
    if p:IsShown() then
        p:Hide()
    else
        PositionBagPopup(p)
        for _, b in ipairs(p.buttons) do UpdateBagSlotButton(b) end
        p:Show()
    end
end

---------------------------------------------------------------------------
-- Categorize mode
--
-- When on, the category layout reveals every category (including
-- hidden ones and ones with no items currently) and shows a gold "+"
-- drop slot at the end of each grid. Click a drop slot or release a
-- drag onto it to pin the held item. Toggle off to return to the
-- normal "only categories with items" view. Triggered by left-click
-- on the bag's portrait icon. State is in-memory only - every fresh
-- /reload starts in normal mode.
---------------------------------------------------------------------------

function Bag:IsCategorizeMode()
    return categorizeMode
end

function Bag:ToggleCategorizeMode()
    categorizeMode = not categorizeMode
    Bag:Refresh()
end

---------------------------------------------------------------------------
-- Money frame state
--
-- ContainerMoneyFrameTemplate registers PLAYER_MONEY itself and calls
-- MoneyFrame_UpdateMoney whenever the player's gold changes. That
-- helper re-shows SilverButton + CopperButton based on the money
-- value, which silently clobbers any hide we did during the previous
-- Refresh. From the user's perspective the Gold Only toggle "doesn't
-- save" - the setting is persisted, but Blizzard's auto-update keeps
-- bringing silver/copper back the next time their gold changes.
--
-- ApplyMoneyState centralises the visibility + anchor logic so we can
-- call it both during Refresh and from a hooksecurefunc on
-- MoneyFrame_UpdateMoney. The hook fires after Blizzard's logic, so
-- our state always wins regardless of who triggered the update.
---------------------------------------------------------------------------

local function ApplyMoneyState(mf)
    if not mf then return end
    local goldOnly = addon:GetSetting("goldOnly") and true or false
    if mf.SilverButton then mf.SilverButton:SetShown(not goldOnly) end
    if mf.CopperButton then mf.CopperButton:SetShown(not goldOnly) end
    if mf.GoldButton then
        if not mf._bazGoldPoint then
            mf._bazGoldPoint = { mf.GoldButton:GetPoint(1) }
        end
        mf.GoldButton:ClearAllPoints()
        if goldOnly then
            -- Gold takes the copper button's place at the right edge.
            mf.GoldButton:SetPoint("RIGHT", mf, "RIGHT", 0, 0)
        else
            local p = mf._bazGoldPoint
            if p and p[1] then
                mf.GoldButton:SetPoint(p[1], p[2], p[3], p[4], p[5])
            elseif mf.SilverButton then
                mf.GoldButton:SetPoint("RIGHT", mf.SilverButton, "LEFT", 0, 0)
            end
        end
    end
end

-- Re-apply our gold-only state every time Blizzard's MoneyFrame logic
-- runs for our money frame (e.g. PLAYER_MONEY events fired by the
-- template's own OnEvent handler). Installed once at file load; the
-- closure null-checks `frame` so it's safe to register before the
-- frame is built.
hooksecurefunc("MoneyFrame_UpdateMoney", function(moneyFrame)
    if frame and moneyFrame == frame.money then
        ApplyMoneyState(moneyFrame)
    end
end)

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

-- Everything a slot says, without moving anything.
--
-- The slot buttons are protected now, so showing, hiding or placing one
-- during a fight is refused. What is not refused is changing what it
-- shows - the icon, the count, the border - which is all that a stack
-- growing or a potion being drunk actually needs. The real layout waits
-- for the fight to end.
function Bag:RefreshContents()
    for bagID, slots in pairs(slotButtons) do
        for slotID, btn in pairs(slots) do
            if btn:IsShown() then UpdateSlot(btn, bagID, slotID) end
        end
    end
end

function Bag:Refresh()
    if not frame then return end

    -- Slot buttons are protected, so a fight is no time to be moving
    -- them. Leaving combat is one of the events that asks for a refresh,
    -- so the layout happens then; until it does, what a slot shows is
    -- still kept current.
    if InCombatLockdown() then
        self:RefreshContents()
        return
    end

    -- Pin the frame to its current top-left corner before any resize
    -- so width/height changes grow toward bottom-right rather than
    -- expanding outward from the center. Without this, toggling
    -- Categorize mode (or any setting that changes height) visually
    -- shifts the title bar / portrait icon - reads as jittery.
    -- BazUI's drag-stop handler re-saves whichever anchor GetPoint
    -- returns, so converting to TOPLEFT here is durable: the next
    -- drag will persist a TOPLEFT-anchored position.
    do
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end

    -- Live settings - re-read on every refresh so toggling the Columns
    -- slider or Hide Empty toggle applies immediately.
    local cols       = GetCols()
    local hideEmpty  = HideEmpty()

    -- Resize the panel width to match the column count. The search bar
    -- + sort button + money frame are anchored relative to the panel
    -- edges so they reflow automatically.
    frame:SetWidth(PanelWidthFor(cols))

    -- Apply the bg-opacity setting. frame.Bg is the stock
    -- FlatPanelBackgroundTemplate (a translucent dark overlay).
    -- frame.solidBg is the solid-black layer we added behind it so
    -- that 100% actually reads as opaque rather than the stock's
    -- ~70%. Scaling both together gives a clean fade from solid
    -- (100%) to fully see-through (0%).
    local bgAlpha = addon:GetSetting("bgAlpha") or 1.0
    if frame.Bg      then frame.Bg:SetAlpha(bgAlpha)      end
    if frame.solidBg then frame.solidBg:SetAlpha(bgAlpha) end

    -- Hide every existing slot button up front. Anything we still want
    -- visible gets re-shown + repositioned in the layout loop. This is
    -- the simplest way to handle (a) Hide Empty on/off, (b) bag size
    -- shrinking, and (c) section-collapsed-this-frame all at once.
    for _, slots in pairs(slotButtons) do
        for _, btn in pairs(slots) do
            btn:Hide()
        end
    end

    -- Width the inner content gets - match scrollChild to scrollFrame.
    -- ScrollFrame's width comes from its TOPLEFT/TOPRIGHT anchors
    -- (= frame width minus the two SIDE_PADs), so we read it back
    -- rather than recomputing.
    if frame.scrollChild and frame.scrollFrame then
        frame.scrollChild:SetWidth(frame.scrollFrame:GetWidth() or 1)
    end

    -- Content y-cursor starts at 0 (top of scrollChild) instead of
    -- -TOP_PAD relative to frame - the chrome lives outside the
    -- scroll area now.
    local y = 0

    -- Dispatch to the appropriate layout. Bag mode renders the static
    -- bag/reagent sections inline (kept here because it's the simple
    -- common case). Category mode hands off to the Layouts module.
    local mode = addon:GetSetting("bagMode") or "bags"

    if mode == "categories" and addon.Layouts and addon.Layouts.Render then
        -- Hide bag-mode sections when category mode is active so a
        -- pooled section frame from a previous render doesn't peek
        -- through the category layout.
        for _, section in pairs(sections) do
            section.header:Hide()
            section.body:Hide()
        end

        y = addon.Layouts.Render({
            -- Layouts anchor relative to scrollChild now so the bag
            -- content scrolls cleanly when content > maxHeight.
            frame                 = frame.scrollChild or frame,
            cols                  = cols,
            SLOT_SIZE             = SLOT_SIZE,
            SLOT_SPACING_X        = SLOT_SPACING_X,
            SLOT_SPACING_Y        = SLOT_SPACING_Y,
            SIDE_PAD              = 0,   -- scrollChild already has the side pad applied
            TOP_PAD               = 0,   -- scrollChild already starts below the chrome
            IsCollapsed           = IsCollapsed,
            SetCollapsed          = SetCollapsed,
            GetOrCreateSlotButton = GetOrCreateSlotButton,
            UpdateSlot            = UpdateSlot,
            Refresh               = function() Bag:Refresh() end,
        })
    elseif addon:GetSetting("perBagSections")
           and addon.Layouts and addon.Layouts.RenderPerBag then
        -- Bags mode + Separate Each Bag - render one thin-divider
        -- section per equipped bag, sharing the divider chrome with
        -- Categories mode.
        for _, section in pairs(sections) do
            section.header:Hide()
            section.body:Hide()
        end

        y = addon.Layouts.RenderPerBag({
            frame                 = frame.scrollChild or frame,
            cols                  = cols,
            SLOT_SIZE             = SLOT_SIZE,
            SLOT_SPACING_X        = SLOT_SPACING_X,
            SLOT_SPACING_Y        = SLOT_SPACING_Y,
            SIDE_PAD              = 0,
            TOP_PAD               = 0,
            IsCollapsed           = IsCollapsed,
            SetCollapsed          = SetCollapsed,
            GetOrCreateSlotButton = GetOrCreateSlotButton,
            UpdateSlot            = UpdateSlot,
            Refresh               = function() Bag:Refresh() end,
            hideEmpty             = hideEmpty,
        })
    else
        -- Bag mode (the default). Clear any category chrome left over
        -- from a Flow / Hybrid render before drawing the bag sections.
        if addon.Layouts and addon.Layouts.HideAll then
            addon.Layouts.HideAll()
        end
        -- One section per bag type with the existing collapse / count chrome.
        -- Sections not in this refresh's defs (a keyring that vanished)
        -- get hidden first.
        local anchor = frame.scrollChild or frame
        local defs = GetSectionDefs()
        local live = {}
        for _, def in ipairs(defs) do live[def.key] = true end
        for key, section in pairs(sections) do
            if not live[key] then
                section.header:Hide()
                section.body:Hide()
            end
        end
        for _, def in ipairs(defs) do
            local section = GetOrCreateSection(def)
            local collapsed = IsCollapsed(def.key)

            -- Header
            section.header:ClearAllPoints()
            section.header:SetPoint("TOPLEFT",  anchor, "TOPLEFT",  0, y)
            section.header:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, y)
            section.toggle:SetTexture(collapsed
                and "Interface\\Buttons\\UI-PlusButton-Up"
                or  "Interface\\Buttons\\UI-MinusButton-Up")
            section.title:SetText(def.title)
            section.header:Show()
            y = y - SECTION_HEADER_H - 2

            -- Collect (bag, slot) pairs. When Hide Empty is on, skip slots
            -- that don't currently hold an item.
            local pairs_list = {}
            for _, bagID in ipairs(def.bagIDs) do
                local n = C_Container.GetContainerNumSlots(bagID) or 0
                for slotID = 1, n do
                    if hideEmpty then
                        local info = C_Container.GetContainerItemInfo(bagID, slotID)
                        if info and info.iconFileID then
                            pairs_list[#pairs_list + 1] = { bagID = bagID, slotID = slotID }
                        end
                    else
                        pairs_list[#pairs_list + 1] = { bagID = bagID, slotID = slotID }
                    end
                end
            end

            -- Section count e.g. "3 / 24"
            local total, free = 0, 0
            for _, bagID in ipairs(def.bagIDs) do
                free  = free  + (C_Container.GetContainerNumFreeSlots(bagID) or 0)
                total = total + (C_Container.GetContainerNumSlots(bagID) or 0)
            end
            section.count:SetText(string.format("|cff999999%d / %d|r", total - free, total))

            -- Body layout
            local rows  = math.ceil(#pairs_list / cols)
            local bodyH = rows * SLOT_SIZE + math.max(0, rows - 1) * SLOT_SPACING_Y
            if collapsed then bodyH = 0 end

            section.body:ClearAllPoints()
            section.body:SetPoint("TOPLEFT",  anchor, "TOPLEFT",  0, y)
            section.body:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, y)
            section.body:SetHeight(math.max(bodyH, 0.001))
            section.body:Show()

            if not collapsed then
                for i, p in ipairs(pairs_list) do
                    local btn = GetOrCreateSlotButton(p.bagID, p.slotID)
                    local col = (i - 1) % cols
                    local row = math.floor((i - 1) / cols)

                    if btn then
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", section.body, "TOPLEFT",
                        col * (SLOT_SIZE + SLOT_SPACING_X),
                        -row * (SLOT_SIZE + SLOT_SPACING_Y))
                    btn:Show()
                    UpdateSlot(btn, p.bagID, p.slotID)
                    end
                end
            end

            if not collapsed then
                y = y - bodyH - 8
            else
                y = y - 4
            end
        end
    end

    -- Bottom padding below the scroll area. The money frame lives in the
    -- top-right chrome, so this is just breathing room.
    local bottomPad  = 12

    -- Cap the scroll area at the user's maxRows setting (one row =
    -- SLOT_SIZE + SLOT_SPACING_Y ≈ 41 px). Anything taller scrolls;
    -- anything shorter shrinks the panel to fit content.
    local contentH = math.abs(y)
    local maxRows  = addon:GetSetting("maxRows") or 15
    local maxH     = maxRows * (SLOT_SIZE + SLOT_SPACING_Y)
    local scrollH  = math.min(contentH, maxH)

    if frame.scrollChild then
        frame.scrollChild:SetHeight(math.max(contentH, 1))
    end
    if frame.scrollFrame then
        frame.scrollFrame:SetHeight(math.max(scrollH, 1))
        frame.scrollFrame.bazMaxScroll = math.max(0, contentH - scrollH)
        -- Clamp current scroll so it never points past the new content
        -- height (e.g. user emptied the bag while scrolled to bottom).
        local cur = frame.scrollFrame:GetVerticalScroll() or 0
        if cur > frame.scrollFrame.bazMaxScroll then
            frame.scrollFrame:SetVerticalScroll(frame.scrollFrame.bazMaxScroll)
        end
    end

    -- Frame height = top chrome (search + money) + scroll area + padding.
    frame:SetHeight(TOP_PAD + scrollH + bottomPad)

    if frame.SetTitle then frame:SetTitle("Bags") end

    -- Money frame lives in the top-right chrome (anchored once in
    -- BuildFrame). Per refresh we just update its values and the
    -- gold-only state - its position never changes. MoneyFrame_Update
    -- sizes the frame, and the search bar (anchored to money's LEFT)
    -- follows.
    -- The "Show Money" toggle was removed in favour of always showing
    -- gold; with the money frame in the top-right corner there's no
    -- vertical real estate to reclaim by hiding it.
    if frame.money then
        do
            frame.money:Show()

            if MoneyFrame_Update then
                MoneyFrame_Update(frame.money:GetName() or frame.money, GetMoney())
            end
            -- Always re-apply our gold-only state. The hooksecurefunc on
            -- MoneyFrame_UpdateMoney catches event-driven refreshes
            -- (PLAYER_MONEY etc.) but Refresh calls MoneyFrame_Update
            -- directly, which doesn't go through UpdateMoney - so
            -- without this explicit call the Gold Only toggle had no
            -- effect when triggered from the Settings page.
            ApplyMoneyState(frame.money)

        end

    end
end

---------------------------------------------------------------------------
-- Show / Hide / Toggle
---------------------------------------------------------------------------

-- Show the panel for the first time? On the very first BuildFrame
-- the scroll-frame's anchor-derived width hasn't propagated yet, so
-- the first Refresh's contentH / scrollH math comes out off and the
-- player sees a tall, mostly-empty panel until they close + reopen.
-- Trigger a one-frame-deferred re-refresh on first show to recompute
-- with the now-settled layout.
local function ShowPanel(self)
    -- Always start at the top of the scroll area when the panel is
    -- shown - without this, ScrollFrame can come up at a stale scroll
    -- position (e.g. saved from a prior session) and items render
    -- below the visible window, making the panel look empty.
    if frame.scrollFrame and frame.scrollFrame.SetVerticalScroll then
        frame.scrollFrame:SetVerticalScroll(0)
    end

    self:Refresh()
    frame:Show()

    if not self._firstShownDone then
        self._firstShownDone = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if frame and frame:IsShown() then self:Refresh() end
            end)
        end
    end
end

function Bag:Show()
    BuildFrame()
    ShowPanel(self)
end

function Bag:Hide()
    if frame then frame:Hide() end
end

function Bag:Toggle()
    BuildFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        ShowPanel(self)
    end
end

---------------------------------------------------------------------------
-- Event-driven refresh (coalesced to one Refresh per frame)
---------------------------------------------------------------------------

local function ScheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        if frame and frame:IsShown() then
            Bag:Refresh()
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("INVENTORY_SEARCH_UPDATE")    -- search box text > re-evaluate isFiltered
events:RegisterEvent("MERCHANT_SHOW")              -- junk coins only show at a vendor
events:RegisterEvent("MERCHANT_CLOSED")
-- A layout the fight would not let us do.
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "BAG_NEW_ITEMS_UPDATED")
events:SetScript("OnEvent", ScheduleRefresh)

---------------------------------------------------------------------------
-- Override Blizzard's bag toggles so the B key, the bag bar and any
-- addon that calls these functions open our panel instead of the stock
-- container frames.
--
-- Hooks happen at file-scope so they're in place before PLAYER_LOGIN.
-- Inside the replacement we still call the original function for
-- close paths, so closing all panels (escape from a UI panel) clears
-- both BazUI Bags and any Blizzard bag state.
---------------------------------------------------------------------------

local function HookBlizzardBagToggles()
    -- Bags deliberately replaces these Blizzard bag entry points.
    -- luacheck: globals ToggleAllBags OpenAllBags OpenBackpack CloseAllBags
    -- luacheck: globals ToggleBackpack CloseBackpack ToggleBag OpenBag CloseBag
    if Bag._blizzHooked then return end
    Bag._blizzHooked = true

    local function Open()   Bag:Show() end
    local function Toggle()
        if frame and frame:IsShown() then Bag:Hide() else Bag:Show() end
    end

    -- Retail-style entry points (Open All Bags keybind, addons).
    ToggleAllBags = Toggle
    OpenAllBags   = Open
    OpenBackpack  = Open

    -- Classic entry points: B is bound to ToggleBackpack, and the bag
    -- buttons on the micro bar call ToggleBag / OpenBag / CloseBag.
    ToggleBackpack = Toggle
    ToggleBag      = function() Toggle() end
    OpenBag        = function() Open() end

    -- Close paths keep calling Blizzard's originals so any stock bag
    -- frame another addon opened directly closes too. They report
    -- whether anything was closed, as Blizzard's do: the Escape chain
    -- (CloseAllWindows) uses that so the press that closes the bag
    -- stops there instead of also clearing the target.
    local origCloseAll, origCloseBackpack, origCloseBag = CloseAllBags, CloseBackpack, CloseBag
    local function CloseOurs()
        local wasShown = frame and frame:IsShown() or false
        Bag:Hide()
        return wasShown
    end
    local function Wrap(orig)
        return function(...)
            local closed = CloseOurs()
            if orig then
                local ok, result = pcall(orig, ...)
                if ok and result then closed = true end
            end
            return closed
        end
    end
    CloseAllBags  = Wrap(origCloseAll)
    CloseBackpack = Wrap(origCloseBackpack)
    CloseBag      = Wrap(origCloseBag)
end

BazUI:QueueForModule("Bags", HookBlizzardBagToggles)
