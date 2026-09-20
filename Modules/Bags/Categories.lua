-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Bags - Categories module
--
-- Owns the category data model + classification logic. Categories are
-- persisted in the `categories` saved variable as { [key] = { name,
-- order, isDefault } }; on first load FACTORY_DEFAULTS is folded in
-- so out-of-the-box users get six built-in groupings. Default
-- categories are renameable / reorderable / deletable like custom
-- ones, but the auto-classifier in Classify() is tied to their
-- *key* (not label) - so renaming "Equipment" > "Gear" doesn't
-- break the Weapon/Armor > equipment routing.
---------------------------------------------------------------------------

local MODULE_NAME = "Bags"
local addon = BazUI:GetAddon(MODULE_NAME)
if not addon then return end

addon.Categories = addon.Categories or {}
local Categories = addon.Categories

---------------------------------------------------------------------------
-- Factory defaults - the categories any first-time user starts with.
-- The Reset Defaults button in the Settings page restores from this
-- table. Order is spaced by 10 so user-added categories can slot in
-- between (Reset preserves their `order` if Soft mode).
---------------------------------------------------------------------------

-- `matchPriority` controls the order Classify evaluates rules; lower
-- numbers match first. Decoupled from `order` (the bag panel display
-- position) so a category can sit at the bottom of the bag visually
-- but still capture items before broader rules above it. Defaults
-- ship with matchPriority == order so the existing behavior is
-- preserved on first install; users who want specificity-over-position
-- override matchPriority via the detail page.
Categories.FACTORY_DEFAULTS = {
    {
        key = "equipment", name = "Equipment", order = 10, matchPriority = 10,
        matchMode = "any",
        tags = {
            { type = "class", op = "equals", value = Enum.ItemClass.Weapon },
            { type = "class", op = "equals", value = Enum.ItemClass.Armor  },
        },
    },
    {
        key = "consumables", name = "Consumables", order = 20, matchPriority = 20,
        matchMode = "any",
        tags = {
            { type = "class", op = "equals", value = Enum.ItemClass.Consumable },
            { type = "class", op = "equals", value = Enum.ItemClass.Projectile },
        },
    },
    {
        key = "tradegoods", name = "Trade Goods", order = 30, matchPriority = 30,
        matchMode = "any",
        tags = {
            { type = "class", op = "equals", value = Enum.ItemClass.Tradegoods      },
            { type = "class", op = "equals", value = Enum.ItemClass.Recipe          },
            { type = "class", op = "equals", value = Enum.ItemClass.Gem             },
            { type = "class", op = "equals", value = Enum.ItemClass.ItemEnhancement },
            { type = "class", op = "equals", value = Enum.ItemClass.Reagent         },
        },
    },
    {
        -- Not like the others: what puts an item here is the slot it is
        -- sitting in, not anything about the item. The same herb is the
        -- same herb wherever it is, so there is nothing to write a tag
        -- against - membership is decided in GetPairsByCategory, and the
        -- empty tag list here keeps the classifier from ever claiming
        -- something for this category by mistake.
        --
        -- Holds the empty reagent slots too. Free space that only takes
        -- reagents is not the same thing as free space, and lumping the
        -- two together is what made the bag look roomier than it was.
        key = "reagents", name = "Reagents", order = 35, matchPriority = 1001,
        matchMode = "all",
        tags = {},
        isProtected = true,
    },
    {
        key = "questitems", name = "Quest Items", order = 40, matchPriority = 40,
        matchMode = "any",
        tags = {
            { type = "class", op = "equals", value = Enum.ItemClass.Questitem },
        },
    },
    {
        key = "keys", name = "Keys", order = 45, matchPriority = 45,
        matchMode = "any",
        tags = {
            { type = "class", op = "equals", value = Enum.ItemClass.Key },
        },
    },
    {
        -- Junk sits at display order 50 (low in the bag panel) but
        -- gets matchPriority 5 - it has to claim gray items before
        -- Equipment / Consumables / etc. would, otherwise a gray
        -- weapon lands in Equipment instead of Junk and the user
        -- can't bulk-vendor grays.
        key = "junk", name = "Junk", order = 50, matchPriority = 5,
        matchMode = "all",
        tags = {
            { type = "quality", op = "=", value = 0 },
        },
    },
    {
        -- Catch-all. No tags - any item that doesn't match any other
        -- category's tags lands here via the FallbackKey("other") call
        -- at the end of Classify.
        --
        -- isProtected blocks Delete / SetHidden / AddTag / UpdateTag /
        -- RemoveTag / SetMatchMode / ResetTagsToDefault on this entry,
        -- because Other is load-bearing - if it's gone or hidden,
        -- items the classifier can't place visibly disappear from the
        -- bag panel. Rename and reorder are still allowed (cosmetic).
        -- EnsureDefaults re-creates Other on every load if it's
        -- somehow missing, so the catch-all always exists.
        key = "other", name = "Other", order = 60, matchPriority = 999,
        matchMode = "all",
        tags = {},
        isProtected = true,
    },
    {
        -- Free space, as a category rather than as a special case.
        --
        -- An empty slot has no item, so nothing classifies into this -
        -- Classify skips tagless categories, so it can never claim one -
        -- and GetPairsByCategory fills it directly instead. Everything
        -- else about it is ordinary: a divider, a collapse arrow, a
        -- position in the order you can move.
        --
        -- Protected, because there is nothing here to edit. Its
        -- membership is computed rather than matched, so tags would do
        -- nothing, and whether it appears at all is the Hide empty slots
        -- setting's business - two switches for one outcome is one too
        -- many.
        key = "empty", name = "Empty Slots", order = 70, matchPriority = 1000,
        matchMode = "all",
        tags = {},
        isProtected = true,
    },
    {
        -- Free space that will only take one kind of thing, kept apart
        -- from free space proper. A reagent slot is no use for the sword
        -- you are about to loot, so counting it as room - or showing it
        -- in the same block - says you have space you have not got.
        key = "emptyreagents", name = "Empty Reagent Slots",
        order = 71, matchPriority = 1002,
        matchMode = "all",
        tags = {},
        isProtected = true,
    },
    {
        -- The same for the keyring, which is the one that made this
        -- worth splitting: a keyring runs to thirty-odd slots and is
        -- nearly always empty, so its free space swamped everything
        -- else's and made a full bag look roomy.
        key = "emptykeyring", name = "Empty Keyring Slots",
        order = 72, matchPriority = 1003,
        matchMode = "all",
        tags = {},
        isProtected = true,
    },
}

-- The keys that are not like the others, for the few places that have to
-- know: the reagent bag's own slots, and free space - of which there are
-- three kinds, because a slot that will only take one sort of thing is
-- not the same as a slot that will take anything.
Categories.REAGENT_KEY       = "reagents"
Categories.EMPTY_KEY         = "empty"
Categories.EMPTY_REAGENT_KEY = "emptyreagents"
Categories.EMPTY_KEYRING_KEY = "emptykeyring"

-- Every category that holds nothing but free space, so the panel can
-- fold them all away at once without naming them one at a time.
Categories.EMPTY_KEYS = {
    [Categories.EMPTY_KEY]         = true,
    [Categories.EMPTY_REAGENT_KEY] = true,
    [Categories.EMPTY_KEYRING_KEY] = true,
}

-- Whether a category can appear at all right now.
--
-- Different from `hidden`, which is a choice the player made. This is
-- about whether the thing the category describes exists: with no reagent
-- bag carried there are no reagent slots, so the category is not empty -
-- it is meaningless, and showing an empty heading for it would be
-- offering to sort something that cannot happen. Everything else is
-- always available.
function Categories.Available(key)
    if key == Categories.REAGENT_KEY or key == Categories.EMPTY_REAGENT_KEY then
        return addon.GetReagentBagID() ~= nil
    end
    if key == Categories.EMPTY_KEYRING_KEY then
        return addon.GetKeyringBagID() ~= nil
    end
    return true
end

-- Bags scanned in categories mode come from addon.GetAllBagIDs(), so the
-- keyring and any reagent bag are included exactly when the character is
-- carrying them. What differs is where their slots land: the reagent
-- bag's go to Categories.REAGENT_KEY whatever is in them, and the
-- keyring's are classified by item like anything else, because a key is
-- a key wherever it sits and the Keys category already collects them.

---------------------------------------------------------------------------
-- EnsureDefaults
--
-- Called once at addon load. If the persisted `categories` map is
-- empty (first run) or missing any default keys (user upgraded from
-- a build that didn't track them), backfill from FACTORY_DEFAULTS.
-- Never overwrites user-edited names or orders - only fills holes.
---------------------------------------------------------------------------

function Categories.EnsureDefaults()
    local cats = addon:GetSetting("categories") or {}
    for _, def in ipairs(Categories.FACTORY_DEFAULTS) do
        if not cats[def.key] then
            -- Brand-new entry: copy the whole factory record (tags,
            -- matchMode, matchPriority, isProtected, the works).
            cats[def.key] = {
                name          = def.name,
                order         = def.order,
                matchPriority = def.matchPriority or def.order,
                isDefault     = true,
                isProtected   = def.isProtected or nil,
                matchMode     = def.matchMode,
                tags          = def.tags and (function()
                    -- Deep-copy tags so mutating SV doesn't poison the
                    -- factory table. Pairs of {type, op, value} are
                    -- shallow-copied; values that are tables (subclass)
                    -- are also copied.
                    local out = {}
                    for i, t in ipairs(def.tags) do
                        local copy = { type = t.type, op = t.op }
                        if type(t.value) == "table" then
                            local vc = {}
                            for k, v in pairs(t.value) do vc[k] = v end
                            copy.value = vc
                        else
                            copy.value = t.value
                        end
                        out[i] = copy
                    end
                    return out
                end)() or nil,
            }
        else
            -- Existing entry: backfill the tag-related fields on
            -- defaults that pre-date the tag system (v062 and earlier
            -- shipped no tags). Don't clobber - only fill if missing.
            -- Custom categories (isDefault ~= true) are left alone.
            if cats[def.key].isDefault and not cats[def.key].tags then
                cats[def.key].matchMode = def.matchMode
                local out = {}
                for i, t in ipairs(def.tags or {}) do
                    local copy = { type = t.type, op = t.op }
                    if type(t.value) == "table" then
                        local vc = {}
                        for k, v in pairs(t.value) do vc[k] = v end
                        copy.value = vc
                    else
                        copy.value = t.value
                    end
                    out[i] = copy
                end
                cats[def.key].tags = out
            end
            -- Backfill isProtected on installs that pre-date the
            -- protected-categories feature (v068 and earlier). The
            -- factory record is the source of truth - if a default
            -- ships protected, force-mark it on existing entries too.
            if def.isProtected and not cats[def.key].isProtected then
                cats[def.key].isProtected = true
                -- Clear any stray rules a previous version might have
                -- accumulated on a now-protected category, so the
                -- protection is consistent (a protected catch-all
                -- with rules would no longer be a catch-all).
                if def.tags and #def.tags == 0 then
                    cats[def.key].tags = {}
                end
                -- Hidden + protected together would mean the catch-all
                -- is invisible, which is the exact failure mode the
                -- protection exists to prevent. Force-unhide.
                cats[def.key].hidden = false
            end
            -- Backfill matchPriority on installs that pre-date the
            -- decoupled-priority feature. Defaults get their factory
            -- priority; everything else falls back to its display
            -- order so behavior stays identical until the user
            -- explicitly changes it.
            if cats[def.key].matchPriority == nil then
                cats[def.key].matchPriority = def.matchPriority
                    or cats[def.key].order
                    or def.order
            end
        end
    end
    addon:SetSetting("categories", cats)
end

---------------------------------------------------------------------------
-- GetAll
--
-- Returns the persisted category list as an array sorted by `order`,
-- with stable tie-break on `key`. Each entry is the saved record plus
-- the `key` field copied in for convenience.
---------------------------------------------------------------------------

function Categories.GetAll()
    local cats = addon:GetSetting("categories") or {}
    local list = {}
    for key, info in pairs(cats) do
        list[#list + 1] = {
            key           = key,
            name          = info.name or key,
            order         = info.order or 100,
            matchPriority = info.matchPriority or info.order or 100,
            isDefault     = info.isDefault or false,
            isProtected   = info.isProtected or false,
            hidden        = info.hidden  or false,
        }
    end
    table.sort(list, function(a, b)
        if a.order == b.order then return a.key < b.key end
        return a.order < b.order
    end)
    return list
end

-- Same data as GetAll() but sorted by matchPriority for the classifier.
-- Display order is independent: the bag panel renders by `order`, but
-- Classify walks by matchPriority so a category sitting low in the bag
-- can still claim items before a higher-displayed category.
function Categories.GetByMatchPriority()
    local list = Categories.GetAll()
    -- Stable secondary sort on display order then key, so equal
    -- priorities tie-break predictably.
    table.sort(list, function(a, b)
        if a.matchPriority ~= b.matchPriority then
            return a.matchPriority < b.matchPriority
        end
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
    return list
end

function Categories.Get(key)
    local cats = addon:GetSetting("categories") or {}
    return cats[key]
end

-- Protected categories (currently just "Other") refuse mutating ops
-- that would make them disappear or stop being a catch-all: Delete,
-- SetHidden, and any tag CRUD. Rename + reorder are still allowed
-- since those are purely cosmetic.
function Categories.IsProtected(key)
    local cats = addon:GetSetting("categories") or {}
    return cats[key] and cats[key].isProtected and true or false
end

---------------------------------------------------------------------------
-- CRUD operations
---------------------------------------------------------------------------

function Categories.Rename(key, newName)
    if not key or not newName or newName == "" then return end
    local cats = addon:GetSetting("categories") or {}
    if not cats[key] then return end
    cats[key].name = newName
    addon:SetSetting("categories", cats)
end

function Categories.Reorder(key, newOrder)
    local cats = addon:GetSetting("categories") or {}
    if not cats[key] then return end
    cats[key].order = newOrder
    addon:SetSetting("categories", cats)
end

-- Match Priority controls when Classify evaluates this category's
-- rules against an item. Lower numbers match first. Decoupled from
-- display `order` so a category can sit anywhere in the bag visually
-- but still capture items before broader-rule categories.
function Categories.SetMatchPriority(key, priority)
    if not key then return end
    local n = tonumber(priority)
    if not n then return end
    local cats = addon:GetSetting("categories") or {}
    if not cats[key] then return end
    cats[key].matchPriority = n
    addon:SetSetting("categories", cats)
end

---------------------------------------------------------------------------
-- MoveUp / MoveDown
--
-- Swap the order value with the adjacent neighbour in the currently
-- sorted list. The Categories settings page wires its row up/down
-- arrow buttons to these so the user never has to hand-pick numeric
-- order values - they just nudge the row up or down and the
-- orderings shuffle to match.
--
-- Both no-op cleanly at the list edges, matching the renderer which
-- grays out the boundary arrow.
---------------------------------------------------------------------------

local function SwapOrders(keyA, keyB)
    local cats = addon:GetSetting("categories") or {}
    if not cats[keyA] or not cats[keyB] then return end
    local oa, ob = cats[keyA].order or 0, cats[keyB].order or 0
    -- Defensive: if both share the same order (which the GetAll
    -- tie-break tolerates) bump one off by 1 so they actually swap
    -- positions instead of staying coincident.
    if oa == ob then ob = oa + 1 end
    cats[keyA].order, cats[keyB].order = ob, oa
    addon:SetSetting("categories", cats)
end

function Categories.MoveUp(key)
    local list = Categories.GetAll()
    for i, c in ipairs(list) do
        if c.key == key then
            if i == 1 then return end
            SwapOrders(key, list[i-1].key)
            return
        end
    end
end

function Categories.MoveDown(key)
    local list = Categories.GetAll()
    for i, c in ipairs(list) do
        if c.key == key then
            if i == #list then return end
            SwapOrders(key, list[i+1].key)
            return
        end
    end
end

-- Hidden categories still exist in the data model - items can still be
-- classified/pinned to them - but the bag layout skips them entirely
-- (no divider, no items, no drop slot). Useful for "Junk" so gray
-- items don't visually clutter the bag while still occupying their
-- real container slots, and for stashing items the user wants out of
-- the way without permanently removing them.
function Categories.SetHidden(key, hidden)
    local cats = addon:GetSetting("categories") or {}
    if not cats[key] then return end
    if cats[key].isProtected then return end  -- catch-all must stay visible
    cats[key].hidden = hidden and true or false
    addon:SetSetting("categories", cats)
end

-- Generates a unique key (custom_<n>) and inserts a new entry. New
-- categories slot at the end of the list (max-order + 10) so they
-- don't accidentally jump above defaults.
function Categories.Create(name)
    name = name and name ~= "" and name or "New Category"
    local cats = addon:GetSetting("categories") or {}

    local maxOrder = 0
    local n = 0
    for _, info in pairs(cats) do
        if (info.order or 0) > maxOrder then maxOrder = info.order end
        n = n + 1
    end

    local key
    repeat
        n = n + 1
        key = "custom_" .. n
    until not cats[key]

    -- Custom categories get matchPriority = order on creation, so
    -- the new category sits at the end of both the bag display AND
    -- the match-evaluation chain. Users who want their custom rule
    -- to outrank a broader default rule can lower matchPriority via
    -- the detail page without having to also move the category up
    -- in the bag panel.
    local newOrder = maxOrder + 10
    cats[key] = {
        name          = name,
        order         = newOrder,
        matchPriority = newOrder,
    }
    addon:SetSetting("categories", cats)
    return key
end

-- Removes a category outright. Items pinned to it via itemCategories
-- are unpinned (drop back to auto-classify) so they still appear in
-- the bag - just under whatever default category their class implies.
function Categories.Delete(key)
    local cats = addon:GetSetting("categories") or {}
    if not cats[key] then return end
    if cats[key].isProtected then return end  -- catch-all is undeletable
    cats[key] = nil
    addon:SetSetting("categories", cats)

    local pins = addon:GetSetting("itemCategories") or {}
    local changed = false
    for itemID, catKey in pairs(pins) do
        if catKey == key then
            pins[itemID] = nil
            changed = true
        end
    end
    if changed then addon:SetSetting("itemCategories", pins) end
end

-- ResetDefaults
--   wipeCustoms = false > restore default labels + order, keep customs + pins
--   wipeCustoms = true  > also delete all user-created categories +
--                          itemCategories, leaving only factory state
function Categories.ResetDefaults(wipeCustoms)
    local cats = addon:GetSetting("categories") or {}
    if wipeCustoms then
        cats = {}
        addon:SetSetting("itemCategories", {})
    end
    for _, def in ipairs(Categories.FACTORY_DEFAULTS) do
        cats[def.key] = {
            name      = def.name,
            order     = def.order,
            isDefault = true,
        }
    end
    addon:SetSetting("categories", cats)
end

---------------------------------------------------------------------------
-- Tag-based match rules (Tier 1)
--
-- Custom categories can carry an array of tags that the classifier
-- evaluates BEFORE the default item-class auto-router. If any tag rule
-- matches (under the category's `matchMode` of "all" or "any"), the
-- item lands in that custom category. Manual pins still win above
-- everything (they short-circuit at the very top of Classify).
--
-- Tag schema:
--   { type = "name",      op = "contains|equals|regex", value = string }
--   { type = "class",     op = "equals", value = <classID> }
--   { type = "subclass",  op = "equals", value = { <classID>, <subclassID> } }
--   { type = "equipSlot", op = "equals", value = "INVTYPE_*" }
--   { type = "quality",   op = ">=|=|<=", value = <0-7> }
--   { type = "ilvl",      op = ">=|=|<=", value = <number> }
---------------------------------------------------------------------------

-- User-friendly enums and lookup tables. The classID / subclassID
-- numbers come from Enum.ItemClass / Enum.ItemArmorSubclass etc but
-- we publish stable string keys so the SV doesn't break if Blizzard
-- ever renumbers (they almost never do, but defensive).

-- Item type labels come from the client so they match what the game
-- calls each class on this flavour.
local function ClassName(classID, fallback)
    local name = C_Item and C_Item.GetItemClassInfo and C_Item.GetItemClassInfo(classID)
    if type(name) == "string" and name ~= "" then return name end
    return fallback
end

local CLASS_LIST = {
    { "Weapon", "Weapon" }, { "Armor", "Armor" }, { "Consumable", "Consumable" },
    { "Tradegoods", "Trade Goods" }, { "Reagent", "Reagent" }, { "Recipe", "Recipe" },
    { "Gem", "Gem" }, { "ItemEnhancement", "Item Enhancement" }, { "Projectile", "Projectile" },
    { "Quiver", "Quiver" }, { "Questitem", "Quest Item" }, { "Key", "Key" },
    { "Container", "Container" }, { "Miscellaneous", "Miscellaneous" },
}

Categories.CLASS_OPTIONS = (function()
    local out = {}
    for _, entry in ipairs(CLASS_LIST) do
        local classID = Enum.ItemClass[entry[1]]
        if classID then
            out[#out + 1] = { value = classID, label = ClassName(classID, entry[2]) }
        end
    end
    return out
end)()

-- Subclass labels likewise come from the client. Only classes whose
-- subclasses are worth filtering on are scanned; empty names are skipped.
local SUBCLASS_SCAN = { "Weapon", "Armor", "Consumable", "Tradegoods", "Projectile", "Recipe", "Container" }

Categories.SUBCLASS_OPTIONS = (function()
    local out = {}
    if not (C_Item and C_Item.GetItemSubClassInfo) then return out end
    for _, className in ipairs(SUBCLASS_SCAN) do
        local classID = Enum.ItemClass[className]
        if classID then
            local classLabel = ClassName(classID, className)
            for subID = 0, 24 do
                local name = C_Item.GetItemSubClassInfo(classID, subID)
                if type(name) == "string" and name ~= "" then
                    out[#out + 1] = { class = classID, subclass = subID,
                                      label = name .. " |cff888888(" .. classLabel .. ")|r" }
                end
            end
        end
    end
    return out
end)()

-- Friendly equip-slot list. Maps to INVTYPE_* strings under the hood.
Categories.EQUIP_SLOT_OPTIONS = {
    { value = "INVTYPE_HEAD",          label = "Head"            },
    { value = "INVTYPE_NECK",          label = "Neck"            },
    { value = "INVTYPE_SHOULDER",      label = "Shoulder"        },
    { value = "INVTYPE_CLOAK",         label = "Cloak / Back"    },
    { value = "INVTYPE_CHEST",         label = "Chest"           },
    { value = "INVTYPE_ROBE",          label = "Robe"            },
    { value = "INVTYPE_BODY",          label = "Shirt"           },
    { value = "INVTYPE_TABARD",        label = "Tabard"          },
    { value = "INVTYPE_WRIST",         label = "Wrist"           },
    { value = "INVTYPE_HAND",          label = "Hands"           },
    { value = "INVTYPE_WAIST",         label = "Waist"           },
    { value = "INVTYPE_LEGS",          label = "Legs"            },
    { value = "INVTYPE_FEET",          label = "Feet"            },
    { value = "INVTYPE_FINGER",        label = "Ring"            },
    { value = "INVTYPE_TRINKET",       label = "Trinket"         },
    { value = "INVTYPE_WEAPON",        label = "One-Handed Weapon"   },
    { value = "INVTYPE_2HWEAPON",      label = "Two-Handed Weapon"   },
    { value = "INVTYPE_WEAPONMAINHAND", label = "Main Hand"      },
    { value = "INVTYPE_WEAPONOFFHAND", label = "Off Hand"        },
    { value = "INVTYPE_HOLDABLE",      label = "Held In Off-Hand" },
    { value = "INVTYPE_SHIELD",        label = "Shield Slot"     },
    { value = "INVTYPE_RANGED",        label = "Ranged"          },
    { value = "INVTYPE_RANGEDRIGHT",   label = "Ranged (Wand/Crossbow)" },
    { value = "INVTYPE_BAG",           label = "Bag"             },
}

Categories.QUALITY_OPTIONS = {
    { value = 0, label = "Poor (Gray)"        },
    { value = 1, label = "Common (White)"     },
    { value = 2, label = "Uncommon (Green)"   },
    { value = 3, label = "Rare (Blue)"        },
    { value = 4, label = "Epic (Purple)"      },
    { value = 5, label = "Legendary (Orange)" },
    { value = 6, label = "Artifact (Red)"     },
    { value = 7, label = "Heirloom (Cyan)"    },
}

Categories.TYPE_OPTIONS = {
    { value = "name",      label = "Name"           },
    { value = "class",     label = "Item Type"      },
    { value = "subclass",  label = "Item Subtype"   },
    { value = "equipSlot", label = "Equip Slot"     },
    { value = "quality",   label = "Quality"        },
    { value = "ilvl",      label = "Item Level"     },
}

-- Built lazily from Blizzard's EXPANSION_NAME{n} globals so we pick
-- up future expansions automatically. Stops on the first gap.
Categories.EXPAC_OPTIONS = (function()
    local out = {}
    for i = 0, 30 do
        local name = _G["EXPANSION_NAME" .. i]
        if type(name) ~= "string" or name == "" then break end
        out[#out+1] = { value = i, label = name }
    end
    return out
end)()

-- Best guess at the latest expansion ID for default-tag seeding.
local function CurrentExpacID()
    if GetExpansionLevel then
        local lvl = GetExpansionLevel()
        if type(lvl) == "number" then return lvl end
    end
    if #Categories.EXPAC_OPTIONS > 0 then
        return Categories.EXPAC_OPTIONS[#Categories.EXPAC_OPTIONS].value
    end
    return 0
end

-- Valid operators per tag type. Used by the popup to filter the op
-- dropdown to only those that make sense for the chosen type.
Categories.OPS_FOR_TYPE = {
    name      = { { value = "contains", label = "contains"   },
                  { value = "equals",   label = "equals"     },
                  { value = "regex",    label = "matches regex" } },
    class     = { { value = "equals",   label = "is" } },
    subclass  = { { value = "equals",   label = "is" } },
    equipSlot = { { value = "equals",   label = "is" } },
    quality   = { { value = ">=", label = "at least" },
                  { value = "=",  label = "exactly"  },
                  { value = "<=", label = "at most"  } },
    ilvl      = { { value = ">=", label = "at least" },
                  { value = "=",  label = "exactly"  },
                  { value = "<=", label = "at most"  } },
    expac     = { { value = "=",  label = "is"               },
                  { value = ">=", label = "is at least"      },
                  { value = "<=", label = "is at most"       } },
}

-- Lookup helpers for friendly label rendering.
local function ClassLabel(classID)
    for _, o in ipairs(Categories.CLASS_OPTIONS) do
        if o.value == classID then return o.label end
    end
    return tostring(classID)
end

local function SubclassLabel(classID, subclassID)
    for _, o in ipairs(Categories.SUBCLASS_OPTIONS) do
        if o.class == classID and o.subclass == subclassID then return o.label end
    end
    return ClassLabel(classID) .. ":" .. tostring(subclassID)
end

local function EquipSlotLabel(invtype)
    for _, o in ipairs(Categories.EQUIP_SLOT_OPTIONS) do
        if o.value == invtype then return o.label end
    end
    return invtype or "?"
end

local function QualityLabel(q)
    for _, o in ipairs(Categories.QUALITY_OPTIONS) do
        if o.value == q then return o.label end
    end
    return tostring(q)
end

local function ExpacLabel(id)
    for _, o in ipairs(Categories.EXPAC_OPTIONS) do
        if o.value == id then return o.label end
    end
    return "Expansion " .. tostring(id)
end

-- Pretty-print a tag for display in the rules list. Format reads as
-- a natural-language clause: "Name contains 'PoE'", "Quality at least Rare".
function Categories.FormatTag(tag)
    if not tag or not tag.type then return "(invalid rule)" end
    local t, op, v = tag.type, tag.op or "equals", tag.value
    if t == "name" then
        local opLabel = (op == "contains" and "contains")
            or (op == "equals" and "equals")
            or (op == "regex" and "matches regex")
            or op
        return string.format("Name %s |cffffd700\"%s\"|r",
            opLabel, tostring(v or ""))
    elseif t == "class" then
        return "Item Type is |cffffd700" .. ClassLabel(v) .. "|r"
    elseif t == "subclass" then
        if type(v) == "table" then
            return "Item Subtype is |cffffd700" .. SubclassLabel(v[1], v[2]) .. "|r"
        end
        return "Item Subtype is " .. tostring(v)
    elseif t == "equipSlot" then
        return "Equip Slot is |cffffd700" .. EquipSlotLabel(v) .. "|r"
    elseif t == "quality" then
        local opLabel = (op == ">=" and "at least")
            or (op == "<=" and "at most")
            or "exactly"
        return string.format("Quality %s |cffffd700%s|r",
            opLabel, QualityLabel(tonumber(v) or 0))
    elseif t == "ilvl" then
        local opLabel = (op == ">=" and "at least")
            or (op == "<=" and "at most")
            or "exactly"
        return string.format("Item Level %s |cffffd700%d|r",
            opLabel, tonumber(v) or 0)
    elseif t == "expac" then
        local opLabel = (op == ">=" and "is at least")
            or (op == "<=" and "is at most")
            or "is"
        return string.format("Expansion %s |cffffd700%s|r",
            opLabel, ExpacLabel(tonumber(v) or 0))
    end
    return "(unknown rule type: " .. tostring(t) .. ")"
end

-- Pull metadata for matching. Returns nil if GetItemInfo hasn't cached
-- the item yet (the bag refresh loop will hit the same item again on
-- the next refresh once Blizzard fills the cache).
local function ItemMeta(itemID)
    if not itemID then return nil end
    local name, _, quality, ilvl, minLvl, _, _, stack,
          equipLoc, _, _, classID, subclassID, bindType,
          expacID, setID, isCraftingReagent = C_Item.GetItemInfo(itemID)
    if not name then return nil end
    return {
        name              = name,
        quality           = quality,
        ilvl              = ilvl,
        minLvl            = minLvl,
        stack             = stack,
        equipLoc          = equipLoc,
        classID           = classID,
        subclassID        = subclassID,
        bindType          = bindType,
        expacID           = expacID,
        setID             = setID,
        isCraftingReagent = isCraftingReagent,
    }
end

-- Single-tag match. Returns true/false. Defensive against malformed
-- tag tables - bad ops just fail-match rather than throwing.
local function MatchTag(tag, meta)
    if not tag or not tag.type or not meta then return false end
    local t  = tag.type
    local op = tag.op or "equals"
    local v  = tag.value

    if t == "name" then
        local n = (meta.name or ""):lower()
        local s = tostring(v or "")
        if op == "contains" then
            return n:find(s:lower(), 1, true) ~= nil
        elseif op == "equals" then
            return n == s:lower()
        elseif op == "regex" then
            local ok, m = pcall(string.match, meta.name or "", s)
            return ok and m ~= nil
        end
        return false
    elseif t == "class" then
        return meta.classID == tonumber(v)
    elseif t == "subclass" then
        if type(v) == "table" then
            return meta.classID == v[1] and meta.subclassID == v[2]
        end
        return false
    elseif t == "equipSlot" then
        return meta.equipLoc == v
    elseif t == "quality" then
        local q = meta.quality or 0
        local n = tonumber(v) or 0
        if op == ">=" then return q >= n end
        if op == "=" then return q == n end
        if op == "<=" then return q <= n end
        return false
    elseif t == "ilvl" then
        local i = meta.ilvl or 0
        local n = tonumber(v) or 0
        if op == ">=" then return i >= n end
        if op == "=" then return i == n end
        if op == "<=" then return i <= n end
        return false
    elseif t == "expac" then
        local e = meta.expacID
        if e == nil then return false end
        local n = tonumber(v) or 0
        if op == ">=" then return e >= n end
        if op == "=" then return e == n end
        if op == "<=" then return e <= n end
        return false
    end
    return false
end

-- Returns true if `itemID` passes ALL (or ANY, depending on matchMode)
-- of the tags on `categoryKey`. False if the category has no tags or
-- the item info isn't cached yet.
function Categories.MatchesCategory(itemID, categoryKey)
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[categoryKey]
    if not cat or not cat.tags or #cat.tags == 0 then return false end

    local meta = ItemMeta(itemID)
    if not meta then return false end

    local mode = cat.matchMode or "all"
    if mode == "all" then
        for _, tag in ipairs(cat.tags) do
            if not MatchTag(tag, meta) then return false end
        end
        return true
    else
        for _, tag in ipairs(cat.tags) do
            if MatchTag(tag, meta) then return true end
        end
        return false
    end
end

---------------------------------------------------------------------------
-- Tag CRUD
---------------------------------------------------------------------------

function Categories.GetTags(key)
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[key]
    return (cat and cat.tags) or {}
end

function Categories.AddTag(key, tag)
    if not key or not tag then return end
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[key]
    if not cat or cat.isProtected then return end
    cat.tags = cat.tags or {}
    cat.tags[#cat.tags + 1] = tag
    addon:SetSetting("categories", cats)
end

function Categories.RemoveTag(key, index)
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[key]
    if not cat or cat.isProtected or not cat.tags then return end
    table.remove(cat.tags, index)
    addon:SetSetting("categories", cats)
end

-- Replace the tag at `index` with a new one. Used by the inline rule
-- editor when the user changes any field in a row (type, op, or
-- value) - the row rebuilds the tag from scratch and writes it back
-- through this function.
function Categories.UpdateTag(key, index, tag)
    if not key or not index or not tag then return end
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[key]
    if not cat or cat.isProtected or not cat.tags or not cat.tags[index] then return end
    cat.tags[index] = tag
    addon:SetSetting("categories", cats)
end

-- Default-shaped tag for a given type. Used when the user changes a
-- rule's Type via the inline editor - the existing op + value are
-- discarded (they don't make sense for the new type) and replaced
-- with sensible starter values for the new type.
function Categories.MakeDefaultTag(tagType)
    if tagType == "name" then
        return { type = "name", op = "contains", value = "" }
    elseif tagType == "class" then
        return { type = "class", op = "equals", value = Enum.ItemClass.Weapon }
    elseif tagType == "subclass" then
        return { type = "subclass", op = "equals",
                 value = { Enum.ItemClass.Armor, 1 } }  -- Armor: Cloth
    elseif tagType == "equipSlot" then
        return { type = "equipSlot", op = "equals", value = "INVTYPE_HEAD" }
    elseif tagType == "quality" then
        return { type = "quality", op = ">=", value = 3 }  -- Rare+
    elseif tagType == "ilvl" then
        return { type = "ilvl", op = ">=", value = 100 }
    elseif tagType == "expac" then
        return { type = "expac", op = "=", value = CurrentExpacID() }
    end
    return { type = "name", op = "contains", value = "" }
end

function Categories.GetMatchMode(key)
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[key]
    return (cat and cat.matchMode) or "all"
end

function Categories.SetMatchMode(key, mode)
    if mode ~= "all" and mode ~= "any" then return end
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[key]
    if not cat or cat.isProtected then return end
    cat.matchMode = mode
    addon:SetSetting("categories", cats)
end

-- Restore the factory tags + matchMode for a default category. No-op
-- on custom categories (they have no factory state to restore) or
-- protected categories (they're locked).
function Categories.ResetTagsToDefault(key)
    local cats = addon:GetSetting("categories") or {}
    local cat  = cats[key]
    if not cat or not cat.isDefault or cat.isProtected then return end
    for _, def in ipairs(Categories.FACTORY_DEFAULTS) do
        if def.key == key then
            cat.matchMode = def.matchMode
            local out = {}
            for i, t in ipairs(def.tags or {}) do
                local copy = { type = t.type, op = t.op }
                if type(t.value) == "table" then
                    local vc = {}
                    for k, v in pairs(t.value) do vc[k] = v end
                    copy.value = vc
                else
                    copy.value = t.value
                end
                out[i] = copy
            end
            cat.tags = out
            addon:SetSetting("categories", cats)
            return
        end
    end
end

---------------------------------------------------------------------------
-- Item pinning
---------------------------------------------------------------------------

function Categories.AddItem(itemID, categoryKey)
    if not itemID or not categoryKey then return end
    local pins = addon:GetSetting("itemCategories") or {}
    pins[itemID] = categoryKey
    addon:SetSetting("itemCategories", pins)
end

function Categories.RemoveItem(itemID)
    local pins = addon:GetSetting("itemCategories") or {}
    pins[itemID] = nil
    addon:SetSetting("itemCategories", pins)
end

function Categories.GetPinnedItems(categoryKey)
    local out = {}
    local pins = addon:GetSetting("itemCategories") or {}
    for itemID, key in pairs(pins) do
        if key == categoryKey then
            out[#out + 1] = itemID
        end
    end
    table.sort(out)
    return out
end

---------------------------------------------------------------------------
-- Classify
--
-- Maps a single item to a category key. Lookup chain:
--   1. itemCategories[itemID]    - explicit pin wins
--   2. quality == 0              > junk
--   3. ItemClass-based rules     > equipment / consumables / tradegoods / questitems
--   4. catch-all                 > other
--
-- The default keys (equipment, consumables, etc.) keep working even if
-- the user renames or reorders them - the classifier only cares about
-- the *key*, not the displayed label. If the user has deleted a
-- default category entirely, items that would have landed there fall
-- through to "other" (assuming "other" still exists; otherwise the
-- first remaining category by order).
---------------------------------------------------------------------------

local function FallbackKey(preferred)
    local cats = addon:GetSetting("categories") or {}
    if cats[preferred] then return preferred end
    -- The lowest-ordered surviving category as a final fallback - but
    -- never the empty-slots one, which holds no items by definition.
    for _, entry in ipairs(Categories.GetAll()) do
        if entry.key ~= Categories.EMPTY_KEY then return entry.key end
    end
    return preferred
end

function Categories.Classify(itemID, quality, classID)
    -- 1. Manual pin override always wins.
    local pins = addon:GetSetting("itemCategories")
    if pins and itemID and pins[itemID] then
        local catKey = pins[itemID]
        local cats = addon:GetSetting("categories") or {}
        if cats[catKey] then return catKey end
        -- Pin points at a category that no longer exists; drop to auto.
    end

    -- 2. Tag-based matching for ALL categories (default + custom).
    -- Walk by matchPriority ASC (NOT display order); first category
    -- whose tags match wins. Junk's factory matchPriority is 5 so a
    -- gray weapon lands in Junk before Equipment (priority 10) gets
    -- a look, even though Junk's display order is 50 (low in the
    -- bag panel). Categories with no tags (e.g. "Other" by design)
    -- are skipped so they only ever match via the catch-all below.
    local list = Categories.GetByMatchPriority()
    for _, entry in ipairs(list) do
        local cats = addon:GetSetting("categories") or {}
        local cat  = cats[entry.key]
        if cat and cat.tags and #cat.tags > 0 then
            if Categories.MatchesCategory(itemID, entry.key) then
                return entry.key
            end
        end
    end

    -- 3. Catch-all: nothing claimed it. Land in "other" if it still
    -- exists, otherwise the lowest-ordered surviving category.
    return FallbackKey("other")
end

---------------------------------------------------------------------------
-- Backwards-compatible alias for callers that still ask for GetOrdered.
-- New code should call GetAll directly (returns the same shape - list
-- of { key, name, order, isDefault }).
---------------------------------------------------------------------------

function Categories.GetOrdered()
    local list = Categories.GetAll()
    -- Layouts.Render expects { key, title, order } - copy `name` to
    -- `title` for backwards compat.
    for _, entry in ipairs(list) do
        entry.title = entry.name
    end
    return list
end

---------------------------------------------------------------------------
-- GetPairsByCategory
--
-- Walks every bag, classifies each occupied slot, returns a
-- { [categoryKey] = { {bagID, slotID}, ... } } table. Empty slots go
-- under Categories.EMPTY_KEY, when they are asked for.
---------------------------------------------------------------------------

-- includeEmpty puts every empty slot under Categories.EMPTY_KEY. Left
-- out, and empties are skipped entirely, which is what Hide empty slots
-- means in this mode.
function Categories.GetPairsByCategory(includeEmpty)
    local byCategory = {}

    local function Bucket(key)
        local bucket = byCategory[key]
        if not bucket then
            bucket = {}
            byCategory[key] = bucket
        end
        return bucket
    end

    local reagentBag = addon.GetReagentBagID()
    local keyringBag = addon.GetKeyringBagID()

    -- Which free-space category a bag's empty slots belong to, worked out
    -- once per bag: the answer cannot change halfway down one.
    local emptyKeyForBag = {}
    if reagentBag then emptyKeyForBag[reagentBag] = Categories.EMPTY_REAGENT_KEY end
    if keyringBag then emptyKeyForBag[keyringBag] = Categories.EMPTY_KEYRING_KEY end

    for _, bagID in ipairs(addon.GetAllBagIDs()) do
        local n = C_Container.GetContainerNumSlots(bagID) or 0
        -- What is in the reagent bag goes to the Reagents category,
        -- because where it is says more about it than what it is.
        local reagentSlot = (reagentBag ~= nil and bagID == reagentBag)
        local emptyKey = emptyKeyForBag[bagID] or Categories.EMPTY_KEY
        for slotID = 1, n do
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if not (info and info.iconFileID) then
                -- Free space, filed by what the slot will accept. Still
                -- silenced by "hide empty slots", which means empty slots
                -- wherever they are.
                if includeEmpty then
                    local bucket = Bucket(emptyKey)
                    bucket[#bucket + 1] = { bagID = bagID, slotID = slotID }
                end
            elseif reagentSlot then
                local bucket = Bucket(Categories.REAGENT_KEY)
                bucket[#bucket + 1] = { bagID = bagID, slotID = slotID }
            else
                local link    = info.hyperlink
                local quality = info.quality
                local classID = info.classID
                if (not classID or not quality) and link then
                    local _, _, q, _, _, _, _, _, _, _, _, c = C_Item.GetItemInfo(link)
                    quality = quality or q
                    classID = classID or c
                end
                local catKey = Categories.Classify(info.itemID, quality or 1, classID)
                local bucket = byCategory[catKey]
                if not bucket then
                    bucket = {}
                    byCategory[catKey] = bucket
                end
                bucket[#bucket + 1] = { bagID = bagID, slotID = slotID }
            end
        end
    end
    return byCategory
end

---------------------------------------------------------------------------
-- Init: backfill defaults at addon load. SafeForLogin so addon.db is
-- ready by the time we read/write settings.
---------------------------------------------------------------------------

if BazUI.QueueForModule then
    BazUI:QueueForModule("Bags", function() Categories.EnsureDefaults() end)
end
