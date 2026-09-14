-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Bags - lightweight unified bag panel
--
-- Core registration: BazUI addon entry, slash commands, profiles,
-- minimap menu entry, options pages. The actual bag UI lives in Bag.lua.
---------------------------------------------------------------------------

local MODULE_NAME = "Bags"

local addon
addon = BazUI:RegisterModule(MODULE_NAME, {
    title         = "Bags",
    savedVariable = "BazUIBagsDB",
    profiles      = true,
    defaults = {
        -- Layout
        cols          = 12,    -- columns wide; 4..20 via the slider - 12 fits a typical bag in 2-3 rows
        hideEmpty     = true,  -- skip empty slots by default - most first-time users prefer the compact view
        maxRows       = 15,    -- soft cap on the panel's content area in rows of slots; content past
                                -- this scrolls. Set to ~30 to effectively disable the cap and let
                                -- the panel grow with content.
        bgAlpha       = 1.0,   -- 0..1 opacity of the panel's dark background - drop below 1 to see
                                -- the world through the bag
        strata        = "DIALOG", -- frame strata; DIALOG keeps the bag above the BazUI Settings
                                -- window (HIGH) by default. Picker in Settings > Layout.

        -- Grouping mode:
        --   "bags"                 - Blizzard-style sections per bag/reagent
        --   "categories" (default) - group items by category (Equipment,
        --                            Consumables, etc.) regardless of bag,
        --                            with thin divider rows separating
        --                            each category's grid block
        bagMode = "categories",

        -- Bags-mode sub-option. When true (default), bag mode renders
        -- one thin-divider section per equipped bag - Backpack, Bag 1
        -- (BagName), Bag 2 (BagName), ..., Reagent Bag - using the
        -- same divider chrome Categories mode uses. When false, all
        -- equippable bag slots merge into a single Bags section + a
        -- Reagents section (Blizzard's combined-bag style).
        -- Categories mode ignores this setting.
        perBagSections = true,

        -- Custom categories. Keys are auto-generated at creation time
        -- ("custom1", "custom2", ...). Values are { name, order }. Empty
        -- by default; the management UI lives in Settings > Categories
        -- (planned for v2 - storage exists already so v1 doesn't break
        -- the data shape).
        customCategories = {},

        -- Item-to-custom-category overrides. {[itemID] = categoryKey}.
        -- Wins over the auto-classifier in ClassifyItem so a user-
        -- pinned Iron Bar sits in their custom "Crafting" group rather
        -- than the built-in "tradegoods".
        itemCategories = {},

        -- Money
        goldOnly        = false,  -- hide silver + copper in the money display

        -- Blizzard UI. Reparent Blizzard's BagsBar (backpack, bag slots,
        -- keyring) to a hidden frame so only the BazUI panel remains.
        hideBagBar      = false,

        -- Section collapse state. Per-section, persisted across
        -- sessions so the user's preference sticks. Built-in bag
        -- sections + every category key share this map.
        sectionCollapsed = {
            bags     = false,
            keyring  = false,
            reagents = false,
        },
        -- Window position. nil = first-run default (set in Bag.lua).
        position = nil,
    },

    slash = { "/bbg", "/bazbags" },
    commands = {
        toggle = {
            desc = "Toggle the BazUI Bags panel",
            handler = function()
                if addon.Bag and addon.Bag.Toggle then
                    addon.Bag:Toggle()
                end
            end,
        },
        sort = {
            desc = "Sort bag contents (Blizzard's Clean Up Bags)",
            handler = function() addon.SortBags() end,
        },
        categorize = {
            desc = "Toggle Categorize mode (drop slots + every category visible)",
            handler = function()
                if addon.Bag and addon.Bag.ToggleCategorizeMode then
                    addon.Bag:ToggleCategorizeMode()
                end
            end,
        },
    },
    -- Bare slash with no subcommand toggles the panel - most common
    -- intent and matches how addons like Bagnon/Baganator behave.
    defaultHandler = function()
        if addon.Bag and addon.Bag.Toggle then
            addon.Bag:Toggle()
        end
    end,

    minimap = {
        label = "Bags",
        icon  = "Interface\\AddOns\\BazUI\\Modules\\Bags\\Assets\\bag_icon.tga",
        onClick = function()
            if addon.Bag and addon.Bag.Toggle then
                addon.Bag:Toggle()
            end
        end,
    },
})

---------------------------------------------------------------------------
-- Bag inventory shape. Classic-family clients have the backpack, four bag
-- slots and a keyring (which only exists once the character owns a key);
-- a reagent bag only where the client has one. Everything that walks bags
-- goes through these so the module adapts to whatever the client offers.
---------------------------------------------------------------------------

function addon.GetMainBagIDs()
    local ids = { Enum.BagIndex.Backpack }
    for i = 1, (NUM_BAG_SLOTS or 4) do
        local id = Enum.BagIndex["Bag_" .. i]
        if id then ids[#ids + 1] = id end
    end
    return ids
end

function addon.GetKeyringBagID()
    local id = Enum.BagIndex.Keyring
    if id and (C_Container.GetContainerNumSlots(id) or 0) > 0 then
        return id
    end
    return nil
end

function addon.GetReagentBagID()
    if (NUM_REAGENTBAG_SLOTS or 0) > 0 then
        return Enum.BagIndex.ReagentBag
    end
    return nil
end

-- Every bag the panel shows, in display order.
function addon.GetAllBagIDs()
    local ids = addon.GetMainBagIDs()
    local keyring = addon.GetKeyringBagID()
    if keyring then ids[#ids + 1] = keyring end
    local reagent = addon.GetReagentBagID()
    if reagent then ids[#ids + 1] = reagent end
    return ids
end

-- Divider label for a bag: "Backpack", "Bag 2 (Mooncloth Bag)", "Keyring".
function addon.BagLabel(bagID)
    if bagID == Enum.BagIndex.Backpack then return "Backpack" end
    if bagID == Enum.BagIndex.Keyring then return "Keyring" end
    local equipped = C_Container.GetBagName and C_Container.GetBagName(bagID)
    local base = (bagID == Enum.BagIndex.ReagentBag) and "Reagent Bag" or ("Bag " .. tostring(bagID))
    if equipped and equipped ~= "" then
        return base .. " |cff888888(" .. equipped .. ")|r"
    end
    return base
end

-- Blizzard's bag sort: C_Container.SortBags on newer clients, the global
-- SortBags (Clean Up Bags) on Classic.
function addon.HasSort()
    return (C_Container and C_Container.SortBags) or SortBags
end

function addon.SortBags()
    if C_Container and C_Container.SortBags then
        C_Container.SortBags()
    elseif SortBags then
        SortBags()
    end
end

---------------------------------------------------------------------------
-- Hide Blizzard's bag bar
--
-- The backpack, bag slot and keyring buttons sit on Blizzard's BagsBar,
-- an Edit Mode system that Edit Mode itself has no hide option for.
-- With the BazUI panel on B, most players want that row gone.
--
-- Reparenting the bar to a hidden carrier frame keeps it out of sight
-- no matter who calls Show() on it later (Edit Mode re-applying a
-- layout, Blizzard's keyring fly-in). Restoring puts it straight back
-- under its original parent, live. None of these frames are protected,
-- so the toggle works in combat too.
---------------------------------------------------------------------------

local hiddenParent
local function GetHiddenParent()
    if not hiddenParent then
        hiddenParent = CreateFrame("Frame")
        hiddenParent:Hide()
    end
    return hiddenParent
end

-- Modern clients group everything on BagsBar. Fall back to the
-- individual buttons for any client that still parents them straight
-- to the main bar.
local function GetBagBarFrames()
    if _G.BagsBar then return { _G.BagsBar } end
    local frames = {}
    for _, name in ipairs({
        "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
        "CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot",
        "KeyRingButton", "BagBarExpandToggle",
    }) do
        if _G[name] then frames[#frames + 1] = _G[name] end
    end
    return frames
end

function addon:ApplyBagBarVisibility()
    local hide = self:GetSetting("hideBagBar") == true
    for _, f in ipairs(GetBagBarFrames()) do
        if hide then
            if not f._bazOriginalParent then
                f._bazOriginalParent = f:GetParent() or UIParent
                f:SetParent(GetHiddenParent())
            end
        elseif f._bazOriginalParent then
            f:SetParent(f._bazOriginalParent)
            f._bazOriginalParent = nil
        end
    end
end

---------------------------------------------------------------------------
-- Options pages
---------------------------------------------------------------------------

local function GetLandingPage()
    return BazUI:CreateLandingPage("Bags", {
        subtitle    = "Unified bag panel",
        description = "A lightweight combined bag panel that merges " ..
            "all bags into one window with collapsible sections per " ..
            "bag type. The keyring lives in the same panel as the " ..
            "main bags - fold it away when you don't need it.",
        features = "Single combined panel for bags + keyring. " ..
            "Collapsible sections per bag type, state persisted. " ..
            "Native item button template (cooldown sweep, quality " ..
            "border, drag/drop, click-to-use all work as Blizzard " ..
            "intends). Sort + free-slot indicator. Minimap entry " ..
            "and slash-command toggle.",
        guide = {
            { "/bbg",        "Toggle the panel" },
            { "Click a section header", "Fold or expand that bag type" },
            { "Drag the title bar",     "Move the panel" },
            { "Sort button",            "Calls Blizzard's bag sort" },
        },
    })
end

---------------------------------------------------------------------------
-- Settings page - landing page sub-category
---------------------------------------------------------------------------

local function GetSettingsPage()
    return {
        name = "Settings",
        type = "group",
        args = {
            intro = {
                order = 0.1,
                type  = "lead",
                text  = "Configure how the bag panel renders. Changes apply live - open the panel with /bbg to see them.",
            },

            layoutHeader = {
                order = 1,
                type  = "header",
                name  = "Layout",
            },
            cols = {
                order = 2,
                type  = "range",
                name  = "Columns",
                desc  = "How many slots wide the panel should be. The window resizes around this; rows are added or removed automatically.",
                min   = 4,
                max   = 20,
                step  = 1,
                get   = function() return addon:GetSetting("cols") or 8 end,
                set   = function(_, val)
                    addon:SetSetting("cols", val)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
            },
            hideEmpty = {
                order = 3,
                type  = "toggle",
                name  = "Hide Empty Slots",
                desc  = "Skip empty slots when rendering - shows only slots with items. Compact view; the panel shrinks vertically when many slots are empty.",
                get   = function() return addon:GetSetting("hideEmpty") and true or false end,
                set   = function(_, val)
                    addon:SetSetting("hideEmpty", val and true or false)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
                disabled = function() return addon:GetSetting("bagMode") == "categories" end,
            },
            maxRows = {
                order = 4,
                type  = "range",
                name  = "Max Rows",
                desc  = "Soft cap on the bag panel's content area, measured in rows of item slots. The panel grows naturally up to this many rows, then scrolls for anything past it. Crank to the max if you'd rather the panel always sized to fit all your items.",
                min   = 3,
                max   = 30,
                step  = 1,
                get   = function() return addon:GetSetting("maxRows") or 15 end,
                set   = function(_, val)
                    addon:SetSetting("maxRows", val)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
            },
            bgAlpha = {
                order = 5,
                type  = "range",
                name  = "Background Opacity",
                desc  = "Opacity of the panel's dark background, in percent. 100 is solid; lower lets the world show through. Items, text and chrome stay fully opaque regardless.",
                min   = 0,
                max   = 100,
                step  = 5,
                get   = function() return math.floor(((addon:GetSetting("bgAlpha") or 1.0) * 100) + 0.5) end,
                set   = function(_, val)
                    addon:SetSetting("bgAlpha", val / 100)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
            },
            strata = {
                order = 6,
                type  = "select",
                name  = "Frame Strata",
                desc  = "Which Z-order layer the bag renders on. Dialog keeps the bag above the settings panel; pick a lower strata if you'd rather the bag tuck under other UI.",
                values = {
                    LOW    = "Low",
                    MEDIUM = "Medium",
                    HIGH   = "High",
                    DIALOG = "Dialog (default)",
                },
                get = function() return addon:GetSetting("strata") or "DIALOG" end,
                set = function(_, val)
                    addon:SetSetting("strata", val)
                    if addon.Bag and addon.Bag.frame and addon.Bag.frame.SetFrameStrata then
                        addon.Bag.frame:SetFrameStrata(val)
                    end
                end,
            },

            groupingHeader = {
                order = 5,
                type  = "header",
                name  = "Grouping",
            },
            bagMode = {
                order = 6,
                type  = "select",
                name  = "Mode",
                desc  = "Bags shows one collapsible section per equipped bag (the default Blizzard layout). Categories regroups items by what they are - Equipment, Consumables, Trade Goods, Quest Items, Junk, Other - regardless of which bag holds them, with thin divider rows separating each group.",
                values = {
                    bags       = "Bags (per-bag sections)",
                    categories = "Categories (group by item type)",
                },
                get = function() return addon:GetSetting("bagMode") or "bags" end,
                set = function(_, val)
                    addon:SetSetting("bagMode", val)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
            },
            perBagSections = {
                order = 7,
                type  = "toggle",
                name  = "Separate Each Bag",
                desc  = "Bags-mode only. When on (default), renders one thin-divider section per equipped bag - Backpack, Bag 1 (BagName), Bag 2 (BagName), ..., Keyring - using the same divider style Categories mode uses, with the equipped bag's actual name shown next to its slot label. When off, all equippable bag slots merge into one Bags section plus a Keyring section. Greys out in Categories mode (the setting has no effect there).",
                get   = function() return addon:GetSetting("perBagSections") and true or false end,
                set   = function(_, val)
                    addon:SetSetting("perBagSections", val and true or false)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
                disabled = function() return addon:GetSetting("bagMode") == "categories" end,
            },

            moneyHeader = {
                order = 10,
                type  = "header",
                name  = "Money",
            },
            goldOnly = {
                order = 12,
                type  = "toggle",
                name  = "Gold Only",
                desc  = "Hide silver and copper in the gold display next to the search bar - keeps just the gold total. Useful at high gold totals where the silver/copper digits add visual noise.",
                get   = function() return addon:GetSetting("goldOnly") and true or false end,
                set   = function(_, val)
                    addon:SetSetting("goldOnly", val and true or false)
                    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
                end,
            },

            blizzardHeader = {
                order = 20,
                type  = "header",
                name  = "Blizzard UI",
            },
            hideBagBar = {
                order = 21,
                type  = "toggle",
                name  = "Hide Blizzard's Bag Bar",
                desc  = "Hide the backpack, bag slot and keyring buttons in the bottom-right corner of the screen. B, /bbg and the minimap entry still open the BazUI panel. To equip a new bag while the bar is hidden, right-click it in your inventory and it goes into an empty bag slot. Applies live.",
                get   = function() return addon:GetSetting("hideBagBar") and true or false end,
                set   = function(_, val)
                    addon:SetSetting("hideBagBar", val and true or false)
                    addon:ApplyBagBarVisibility()
                end,
            },
        },
    }
end

addon.config.onLoad = function(self)
    BazUI:RegisterOptionsTable(MODULE_NAME, GetLandingPage)
    BazUI:AddToSettings(MODULE_NAME, "Bags")

    BazUI:RegisterOptionsTable(MODULE_NAME .. "-Settings", GetSettingsPage)
    BazUI:AddToSettings(MODULE_NAME .. "-Settings", "General Settings", MODULE_NAME)
end

addon.config.onReady = function(self)
    self:ApplyBagBarVisibility()
end

addon:OnProfileChanged(function()
    addon:ApplyBagBarVisibility()
end)
