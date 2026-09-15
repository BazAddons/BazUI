-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Bags - Categories settings page
--
-- Built on BazUI:CreateManagedListPage so the page is automatically
-- cohesive with the User Manual's visual chrome - same title bar,
-- gold-gradient list selection, auto-h1 detail title, rich content
-- blocks (paragraph, h3, note, divider) interleaved with form widgets
-- (input, range, execute).
--
-- Each category becomes a row on the left; selecting one shows its
-- editable detail (display name, order, pinned items, delete) on the
-- right. Default categories include an "auto-classifier" intro
-- paragraph so users understand what the category does for them
-- before they tinker with it.
---------------------------------------------------------------------------

local MODULE_NAME = "Bags"
local addon = BazUI:GetAddon(MODULE_NAME)
if not addon then return end

local PAGE_KEY = MODULE_NAME .. "-Categories"

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Format an item ID as a display string. Tries GetItemInfo for a
-- proper name; falls back to the ID. Pins use the cache when warm,
-- so this gradually fills in over time.
local function ItemDisplayName(itemID)
    if not itemID then return "?" end
    local name, link = C_Item.GetItemInfo(itemID)
    if name then
        -- Prefer the colored link if available so quality colors come through.
        return link or name
    end
    return "Item " .. itemID
end

-- Refresh the bag panel + the settings page. Called after every CRUD
-- op so the user sees their change immediately in both surfaces.
local function RefreshAll()
    if addon.Bag and addon.Bag.Refresh then addon.Bag:Refresh() end
    BazUI:RefreshOptions(PAGE_KEY)
end

---------------------------------------------------------------------------
-- Inline rule-row widget
--
-- Each match rule is rendered as one full-width row with everything
-- editable inline:
--
--   [ Type ▼ ]  [ Op ▼ ]  [ Value ▼ / input ]                [ Remove ]
--
-- Changing any control rebuilds the tag and writes back through
-- Categories.UpdateTag, then refreshes the page so the row re-renders
-- with the new shape (changing Type swaps the Op options + the Value
-- widget kind, e.g. picking "Item Level" replaces a class-name
-- dropdown with a numeric input). The whole row is one custom widget
-- registered via O.widgetFactories.ruleRow
-- so the LayoutEngine treats it as a block-level item that gets its
-- own row in the panel.
---------------------------------------------------------------------------

local O = BazUI._Options

-- Helpers for translating tag fields into UI-friendly labels.

local function TypeLabel(t)
    for _, o in ipairs(addon.Categories.TYPE_OPTIONS) do
        if o.value == t then return o.label end
    end
    return t or "?"
end

local function OpLabelFor(tagType, op)
    local list = addon.Categories.OPS_FOR_TYPE[tagType] or {}
    for _, o in ipairs(list) do
        if o.value == op then return o.label end
    end
    return op or "?"
end

local function ClassValueLabel(classID)
    for _, o in ipairs(addon.Categories.CLASS_OPTIONS) do
        if o.value == classID then return o.label end
    end
    return tostring(classID)
end

local function SubclassValueLabel(value)
    if type(value) == "table" then
        for _, o in ipairs(addon.Categories.SUBCLASS_OPTIONS) do
            if o.class == value[1] and o.subclass == value[2] then return o.label end
        end
    end
    return "?"
end

local function EquipSlotValueLabel(invtype)
    for _, o in ipairs(addon.Categories.EQUIP_SLOT_OPTIONS) do
        if o.value == invtype then return o.label end
    end
    return invtype or "?"
end

local function QualityValueLabel(q)
    for _, o in ipairs(addon.Categories.QUALITY_OPTIONS) do
        if o.value == q then return o.label end
    end
    return tostring(q)
end

local function ExpacValueLabel(id)
    for _, o in ipairs(addon.Categories.EXPAC_OPTIONS) do
        if o.value == id then return o.label end
    end
    return tostring(id)
end

local ROW_HEIGHT = 36
local TYPE_W    = 110
local OP_W      = 90
local REMOVE_W  = 70
local GAP       = 6

-- Build a value control (input or dropdown) inside `frame`, anchored
-- between leftAnchorPoint and the Remove button (right edge). Returns
-- the created widget so callers can SetEnabled / refocus it.
local function BuildValueControl(frame, tag, key, idx, leftPx, rightInsetPx)

    if tag.type == "name" or tag.type == "ilvl" then
        local input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        input:SetPoint("LEFT",  frame, "LEFT",  leftPx + 8, 0)
        input:SetPoint("RIGHT", frame, "RIGHT", -(rightInsetPx + 4), 0)
        input:SetHeight(22)
        input:SetAutoFocus(false)
        input:SetText(tostring(tag.value or ""))

        local commit = function(self)
            local raw = self:GetText()
            local v = raw
            if tag.type == "ilvl" then v = tonumber(raw) or 0 end
            addon.Categories.UpdateTag(key, idx,
                { type = tag.type, op = tag.op, value = v })
            RefreshAll()
        end
        input:SetScript("OnEnterPressed", function(self)
            commit(self); self:ClearFocus()
        end)
        input:SetScript("OnEscapePressed", function(self)
            self:SetText(tostring(tag.value or ""))
            self:ClearFocus()
        end)
        -- Commit on focus-lost too so click-away works without Enter.
        input:SetScript("OnEditFocusLost", commit)
        return input
    end

    -- Dropdown for class / subclass / equipSlot / quality.
    local btn = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    btn:SetPoint("LEFT",  frame, "LEFT",  leftPx, 0)
    btn:SetPoint("RIGHT", frame, "RIGHT", -rightInsetPx, 0)

    -- Default-text label for the currently-selected value.
    local label
    if tag.type == "class" then
        label = ClassValueLabel(tonumber(tag.value))
    elseif tag.type == "subclass" then
        label = SubclassValueLabel(tag.value)
    elseif tag.type == "equipSlot" then
        label = EquipSlotValueLabel(tag.value)
    elseif tag.type == "quality" then
        label = QualityValueLabel(tonumber(tag.value))
    elseif tag.type == "expac" then
        label = ExpacValueLabel(tonumber(tag.value))
    end
    btn:SetDefaultText(label or "?")

    btn:SetupMenu(function(_, root)
        if tag.type == "class" then
            for _, o in ipairs(addon.Categories.CLASS_OPTIONS) do
                root:CreateRadio(o.label,
                    function() return tonumber(tag.value) == o.value end,
                    function()
                        addon.Categories.UpdateTag(key, idx,
                            { type = "class", op = "equals", value = o.value })
                        RefreshAll()
                    end)
            end
        elseif tag.type == "subclass" then
            for _, o in ipairs(addon.Categories.SUBCLASS_OPTIONS) do
                root:CreateRadio(o.label,
                    function()
                        return type(tag.value) == "table"
                           and tag.value[1] == o.class
                           and tag.value[2] == o.subclass
                    end,
                    function()
                        addon.Categories.UpdateTag(key, idx,
                            { type = "subclass", op = "equals",
                              value = { o.class, o.subclass } })
                        RefreshAll()
                    end)
            end
        elseif tag.type == "equipSlot" then
            for _, o in ipairs(addon.Categories.EQUIP_SLOT_OPTIONS) do
                root:CreateRadio(o.label,
                    function() return tag.value == o.value end,
                    function()
                        addon.Categories.UpdateTag(key, idx,
                            { type = "equipSlot", op = "equals", value = o.value })
                        RefreshAll()
                    end)
            end
        elseif tag.type == "quality" then
            for _, o in ipairs(addon.Categories.QUALITY_OPTIONS) do
                root:CreateRadio(o.label,
                    function() return tonumber(tag.value) == o.value end,
                    function()
                        addon.Categories.UpdateTag(key, idx,
                            { type = "quality", op = tag.op, value = o.value })
                        RefreshAll()
                    end)
            end
        elseif tag.type == "expac" then
            for _, o in ipairs(addon.Categories.EXPAC_OPTIONS) do
                root:CreateRadio(o.label,
                    function() return tonumber(tag.value) == o.value end,
                    function()
                        addon.Categories.UpdateTag(key, idx,
                            { type = "expac", op = tag.op, value = o.value })
                        RefreshAll()
                    end)
            end
        end
    end)

    return btn
end

local function CreateRuleRowWidget(parent, opt, contentWidth)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(contentWidth, ROW_HEIGHT)

    local key = opt.categoryKey
    local idx = opt.tagIndex
    local tag = opt.tag

    -- 1. Type dropdown (left, fixed width)
    local typeBtn = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    typeBtn:SetPoint("LEFT", frame, "LEFT", 0, 0)
    typeBtn:SetWidth(TYPE_W)
    typeBtn:SetDefaultText(TypeLabel(tag.type))
    typeBtn:SetupMenu(function(_, root)
        for _, t in ipairs(addon.Categories.TYPE_OPTIONS) do
            root:CreateRadio(t.label,
                function() return tag.type == t.value end,
                function()
                    -- Replace with a default-shaped tag for the new
                    -- type. The existing op/value almost certainly
                    -- don't translate (e.g. switching from Quality to
                    -- Name) so the cleanest behavior is a fresh
                    -- starter the user can refine.
                    addon.Categories.UpdateTag(key, idx,
                        addon.Categories.MakeDefaultTag(t.value))
                    RefreshAll()
                end)
        end
    end)

    -- 2. Op slot (90px wide) - dropdown for multi-op types,
    -- static "is" label for single-op types (class/subclass/equipSlot).
    local ops = addon.Categories.OPS_FOR_TYPE[tag.type] or {}
    if #ops > 1 then
        local opBtn = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
        opBtn:SetPoint("LEFT", typeBtn, "RIGHT", GAP, 0)
        opBtn:SetWidth(OP_W)
        opBtn:SetDefaultText(OpLabelFor(tag.type, tag.op))
        opBtn:SetupMenu(function(_, root)
            for _, o in ipairs(ops) do
                root:CreateRadio(o.label,
                    function() return tag.op == o.value end,
                    function()
                        addon.Categories.UpdateTag(key, idx,
                            { type = tag.type, op = o.value, value = tag.value })
                        RefreshAll()
                    end)
            end
        end)
    else
        local opLabel = frame:CreateFontString(nil, "OVERLAY", O.LABEL_FONT)
        opLabel:SetPoint("LEFT", typeBtn, "RIGHT", GAP, 0)
        opLabel:SetWidth(OP_W)
        opLabel:SetJustifyH("CENTER")
        opLabel:SetText("is")
        opLabel:SetTextColor(unpack(O.TEXT_DESC))
    end

    -- 3. Value control (input or dropdown depending on type),
    --    anchored between the op slot and the Remove button.
    local valueLeftPx = TYPE_W + GAP + OP_W + GAP
    local rightInset  = REMOVE_W + GAP
    BuildValueControl(frame, tag, key, idx, valueLeftPx, rightInset)

    -- 4. Remove button (right-aligned)
    local rmBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    rmBtn:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    rmBtn:SetSize(REMOVE_W, 22)
    rmBtn:SetText("Remove")
    rmBtn:SetScript("OnClick", function()
        addon.Categories.RemoveTag(key, idx)
        RefreshAll()
    end)

    return frame, ROW_HEIGHT
end

-- Register with BazUI. Idempotent - re-running on a /reload just
-- overwrites the same factory entry.
if O and O.widgetFactories then
    O.widgetFactories.ruleRow = CreateRuleRowWidget
end

---------------------------------------------------------------------------
-- Per-category detail blocks
--
-- Returns an array of opt tables (content blocks + form widgets) in
-- display order. CreateManagedListPage handles converting this into
-- the keyed args table the renderer expects, and auto-prepends an h1
-- with the category name above whatever this returns.
---------------------------------------------------------------------------

local function BuildCategoryDetail(item)
    local key         = item.key
    local isDefault   = item.isDefault and true or false
    local isProtected = item.isProtected and true or false

    local blocks = {}

    if isProtected then
        blocks[#blocks+1] = {
            type  = "note",
            style = "info",
            text  = "|cffffd700This is the catch-all category.|r Items that don't match any other category's rules land here, so it can't be deleted, hidden, or have rules added to it. You can still rename it (cosmetic only), reorder it in the bag panel, and pin items to it manually.",
        }
    else
        blocks[#blocks+1] = {
            type  = "note",
            style = "info",
            text  = isDefault
                and "You can rename this category, reorder it (use the up/down arrows on the left list), edit its match rules below, adjust its Match Priority, or pin extra items as overrides. The category's internal key is locked, so renaming doesn't break anything."
                or  "Custom category. Add match rules below to auto-include items, adjust Match Priority to control when its rules are evaluated, or shift+right-click items in the bag to pin them here manually.",
        }
    end

    blocks[#blocks+1] = { type = "h3", name = "Identity" }

    blocks[#blocks+1] = {
        type = "input",
        name = "Display Name",
        desc = "Shown in the bag panel's category divider.",
        get  = function()
            local entry = addon.Categories.Get(key)
            return entry and entry.name or ""
        end,
        set  = function(_, val)
            if not val or val == "" then return end
            addon.Categories.Rename(key, val)
            RefreshAll()
        end,
    }

    -- Hide is gated for protected categories - hiding the catch-all
    -- would mean items the classifier can't place visibly disappear
    -- from the bag, which is the exact failure mode the protection
    -- exists to prevent.
    if not isProtected then
        blocks[#blocks+1] = {
            type = "toggle",
            name = "Hide from bag panel",
            desc = "When on, this category's divider and items don't appear in the bag panel. Items still occupy their real bag slots - Hide is a display preference, not a delete. Pin an item to a hidden category (via shift+right-click on the item) to keep it out of view.",
            get  = function()
                local entry = addon.Categories.Get(key)
                return entry and entry.hidden or false
            end,
            set  = function(_, val)
                addon.Categories.SetHidden(key, val)
                RefreshAll()
            end,
        }
    end

    blocks[#blocks+1] = { type = "divider" }

    -----------------------------------------------------------------
    -- Match Priority - decoupled from display order so a category
    -- can sit anywhere in the bag visually but still control when
    -- its rules are evaluated. Lower number = matches first.
    -----------------------------------------------------------------

    blocks[#blocks+1] = { type = "h3", name = "Match Priority" }

    blocks[#blocks+1] = {
        type  = "note", style = "tip",
        text  = "Lower numbers match first. Independent of where this category sits in the bag panel - so a custom \"PoE Equipment\" category can live at the bottom of the bag (priority 5) and still claim items before \"Equipment\" (priority 10) does. Junk ships at priority 5 so gray items always vendor together regardless of bag layout.",
    }

    blocks[#blocks+1] = {
        type  = "range",
        name  = "Priority",
        min   = 1, max = 999, step = 1,
        get   = function()
            local entry = addon.Categories.Get(key)
            return (entry and entry.matchPriority) or (entry and entry.order) or 100
        end,
        set   = function(_, val)
            addon.Categories.SetMatchPriority(key, val)
            RefreshAll()
        end,
    }

    blocks[#blocks+1] = { type = "divider" }

    -----------------------------------------------------------------
    -- Match Rules - the tag-based auto-classifier for this category.
    -- Skipped entirely on protected categories (Other) since they
    -- exist as the catch-all and can't carry rules.
    -----------------------------------------------------------------

    if not isProtected then
        blocks[#blocks+1] = { type = "h3", name = "Match Rules" }

        blocks[#blocks+1] = {
            type  = "note", style = "info",
            text  = "Items that pass these rules drop into this category automatically. Pinned items (further down) override the rules.",
        }

        -- Top row of the section is a side-by-side pair: Match Mode
        -- dropdown on the left card, action button on the right card.
        -- Layout engine alternates strictly between left and right
        -- columns, so the order here matters: Match Mode (col 1) ->
        -- Add (col 2) -> (defaults only) Reset (col 1, stacks under
        -- Match Mode in the left card).
        --
        -- Add Match Rule appends a sensible default tag (Name contains "")
        -- and refreshes - the new row appears in the list below ready for
        -- the user to fill in inline via its Type / Op / Value dropdowns.
        -- No popup needed; the rule editor below IS the input surface.
        blocks[#blocks+1] = {
            type   = "select",
            name   = "Match Mode",
            desc   = "All - the item must match every rule (AND). Any - the item lands here as soon as one rule hits (OR).",
            values = {
                all = "All  (item must match every rule)",
                any = "Any  (item matches if it hits any rule)",
            },
            get = function() return addon.Categories.GetMatchMode(key) end,
            set = function(_, val)
                addon.Categories.SetMatchMode(key, val)
                RefreshAll()
            end,
        }

        blocks[#blocks+1] = {
            type  = "execute",
            name  = "Add Match Rule",
            width = "half",
            func  = function()
                addon.Categories.AddTag(key, addon.Categories.MakeDefaultTag("name"))
                RefreshAll()
            end,
        }

        if isDefault then
            blocks[#blocks+1] = {
                type  = "execute",
                name  = "Reset Rules to Default",
                width = "half",
                confirm            = true,
                confirmTitle       = "Reset rules?",
                confirmText        = "Restore the factory match rules for this category, discarding your edits? Pinned items are not affected.",
                confirmStyle       = "destructive",
                confirmAcceptLabel = "Reset",
                func = function()
                    addon.Categories.ResetTagsToDefault(key)
                    RefreshAll()
                end,
            }
        end

        -- Header + thin spacer rule between the actions above and the
        -- Remove-rule list below. The "Current Rules" h4 doubles as the
        -- empty-state label - its paragraph note swaps out to "No rules
        -- yet." text when the tag list is empty.
        blocks[#blocks+1] = { type = "h4", name = "Current Rules" }

        -- Render each existing tag as an inline ruleRow widget so every
        -- field (type / op / value) is editable in place, no popup needed.
        -- Empty list shows a hint paragraph instead.
        local tags = addon.Categories.GetTags(key)
        if #tags == 0 then
            blocks[#blocks+1] = {
                type = "paragraph",
                text = "|cff999999No rules yet. Click " ..
                       "|cffffd700Add Match Rule|r above to start - the new row will appear here ready to edit.|r",
            }
        else
            for i, tag in ipairs(tags) do
                blocks[#blocks+1] = {
                    type        = "ruleRow",
                    categoryKey = key,
                    tagIndex    = i,
                    tag         = tag,
                }
            end
        end

        blocks[#blocks+1] = { type = "divider" }
    end

    -- Pinned Items is hidden on protected (catch-all) categories.
    -- Pinning an item to "Other" is meaningless - Other catches
    -- everything by default already, so a manual pin to it would
    -- be a redundant override that adds no information.
    if not isProtected then
        blocks[#blocks+1] = { type = "h3", name = "Pinned Items" }

        -- This section is a VIEW + UNPIN surface. Adding pins lives in the
        -- bag UI itself (Categorize Mode + the shift+right-click context
        -- menu) where it's faster and more visual - the settings page used
        -- to also have a "type or paste an item ID" input box, but it was
        -- a redundant text-only fallback nobody reached for when the bag
        -- UI was right there. Kept here: the list of currently-pinned
        -- items with one-click unpin buttons, useful for auditing pins
        -- without having to find the item in your bag.
        blocks[#blocks+1] = {
            type  = "note", style = "tip",
            text  = "To pin items into this category, use |cffffd700Categorize Mode|r in the bag panel (middle-click the portrait, then drop items onto the gold |cffffd700+|r slot at the end of this category's row), or |cffffd700shift+right-click|r any bag item and pick this category from the menu. Pinned items override the auto-classifier and always appear in this category. Unpin them from the list below.",
        }

        -- One execute button per pinned item - clicking unpins it.
        local pins = addon.Categories.GetPinnedItems(key)
        if #pins == 0 then
            blocks[#blocks+1] = {
                type = "paragraph",
                text = "|cff999999No items pinned yet.|r",
            }
        else
            for _, itemID in ipairs(pins) do
                blocks[#blocks+1] = {
                    type  = "execute",
                    name  = "Remove " .. ItemDisplayName(itemID),
                    width = "full",
                    func  = function()
                        addon.Categories.RemoveItem(itemID)
                        RefreshAll()
                    end,
                }
            end
        end
    end

    if not isProtected then
        blocks[#blocks+1] = { type = "divider" }

        blocks[#blocks+1] = { type = "h3", name = "Delete" }

        blocks[#blocks+1] = {
            type  = "note",
            style = isDefault and "warning" or "danger",
            text  = isDefault
                and "Deleting a default category lets you reset it back later via Reset to Defaults at the top of the page. Items pinned to this category will fall back to the auto-classifier."
                or  "Permanently removes this custom category. Items pinned to it will fall back to their default category (or 'Other').",
        }

        blocks[#blocks+1] = {
            type = "execute",
            name = "Delete This Category",
            func = function()
                addon.Categories.Delete(key)
                RefreshAll()
            end,
        }
    end

    return blocks
end

---------------------------------------------------------------------------
-- Register
---------------------------------------------------------------------------

if BazUI.QueueForModule then
    BazUI:QueueForModule("Bags", function()
        if not BazUI.RegisterOptionsTable then return end

        local pageFunc = BazUI:CreateManagedListPage(MODULE_NAME, {
            pageName = "Categories",
            intro    = "Categories group items by what they are. Default categories auto-classify by item type; custom categories collect items you pin to them. Pick a category on the left to rename it, reorder it, pin items, or delete it.",

            getItems    = function()
                -- Decorate the list with gray suffixes so the user
                -- can see at a glance which categories are hidden
                -- from the bag panel and which are protected
                -- (catch-all only, currently just Other).
                local cats = addon.Categories.GetAll()
                for _, c in ipairs(cats) do
                    if c.isProtected then
                        c.name = (c.name or c.key) .. "  |cff888888(catch-all)|r"
                    elseif c.hidden then
                        c.name = (c.name or c.key) .. "  |cff888888(hidden)|r"
                    end
                end
                return cats
            end,
            buildDetail = BuildCategoryDetail,

            onCreate = function()
                addon.Categories.Create("New Category")
                RefreshAll()
            end,
            createButtonText = "Create New Category",

            onReset = function()
                -- Reset is destructive: presets are restored but any
                -- user-tweaked names / order changes are gone. Gate
                -- behind a confirm so an accidental click doesn't
                -- silently overwrite a polished setup.
                if BazUI.Confirm then
                    BazUI:Confirm({
                        title       = "Reset categories?",
                        body        = "Reset every category back to its default name and order? Your tweaks to category names and ordering are wiped. Custom (user-created) categories are preserved.",
                        acceptLabel = "Reset",
                        acceptStyle = "destructive",
                        onAccept    = function()
                            addon.Categories.ResetDefaults(false)
                            RefreshAll()
                        end,
                    })
                end
            end,
            resetButtonText = "Reset to Defaults",

            -- Up/down arrows on every row replace the old "Order" range
            -- slider in the detail pane. Click the arrow, the row jumps
            -- one slot, the bag panel re-renders. Top/bottom rows
            -- render their boundary arrow disabled automatically (the
            -- shared row renderer handles the graying based on whether
            -- we hand it a callback for that direction).
            onMoveUp = function(item)
                addon.Categories.MoveUp(item.key)
                RefreshAll()
            end,
            onMoveDown = function(item)
                addon.Categories.MoveDown(item.key)
                RefreshAll()
            end,
        })

        BazUI:RegisterOptionsTable(PAGE_KEY, pageFunc)
        BazUI:AddToSettings(PAGE_KEY, "Categories", MODULE_NAME)
    end)
end
