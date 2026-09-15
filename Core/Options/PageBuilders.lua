-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: Page Builders
--
-- One generator: a page of editable items. The landing, modules and
-- global-options generators went when those pages did.
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- CreateManagedListPage
--
-- Standardized "list of editable items" page. Used wherever the user
-- has a collection of things (categories, drawers, bars, profiles...)
-- and needs to:
--   * Optionally Create new items via a button at the top of the list
--   * Optionally Reset to defaults
--   * Click each item to view / edit its details on the right
--
-- Visual design is intentionally cohesive with the User Manual page:
--   * Same title bar (O.BuildTitleBar) - addon icon, gold title, version
--   * Same list/detail chrome - gold-gradient selection highlight,
--     shared list width (O.ResolveListWidth), shared backdrops
--   * Detail panel auto-prepends an h1 with the item name, mirroring
--     the User Manual's `{ type="h1", text=page.title }` convention
--     (set `detailTitle = false` to opt out)
--   * Detail content uses the same rich content blocks (paragraph, h3,
--     note, divider, list, table, ...) interleaved with form widgets
--     (input, range, toggle, execute) so each page reads like docs
--     that happen to be editable.
--
-- Returns a FUNCTION (not a table) so each Refresh re-reads getItems
-- - items can be added/removed/reordered between renders without
-- re-registering the page. Pass the function directly to
-- BazUI:RegisterOptionsTable.
--
-- Internally produces the wrapper-group shape that the picker
-- expects: top-level intro blocks + create/reset executes + a single
-- `items` group whose `args` are one sub-group per item. Addons just
-- supply data + callbacks; layout is fully owned by BazUI.
--
-- config = {
--   pageName,            -- string, shown in title bar
--
--   intro,               -- optional string, rendered as a single `lead`
--                        -- block above the list/detail. Mutually exclusive
--                        -- with `introBlocks` - pass one or the other.
--   introBlocks,         -- optional array of content-block opt tables for
--                        -- richer intros (lead + note + list, etc.).
--                        -- Mirrors the User Manual page `blocks` field.
--
--   getItems,            -- () -> array. Each entry: { key, name, [order], [source], ... }
--                        --   key:    unique stable id; used for the args key + selection
--                        --           persistence.
--                        --   name:   shown in the left list AND as the detail
--                        --           panel's auto-h1 (unless detailTitle = false).
--                        --   order:  optional sort order. Defaults to position * 10
--                        --           when omitted.
--                        --   source: optional grouping label. When ANY item supplies
--                        --           one, the list switches to BazWidgetDrawers-style
--                        --           collapsible sections, one per source value.
--                        -- The function is called fresh on each render so the page
--                        -- always reflects current state.
--
--   buildDetail,         -- (item) -> array of opt tables for the detail pane.
--                        -- Pass widgets/blocks in display order; each opt is a
--                        -- standard widget definition (see ContentFactories /
--                        -- WidgetFactories for valid `type` values). Order is
--                        -- assigned automatically from array position.
--
--   detailTitle,         -- optional. Default true. When truthy, an h1 with
--                        -- item.name is auto-prepended to the detail panel
--                        -- (matches User Manual page-content style). Pass
--                        --   false      to suppress the auto-header
--                        --   "h1"/"h2"/"h3"  to use a smaller heading
--
--   onCreate,            -- optional () -> ()
--                        --   When set, adds a "Create New" execute at the top of
--                        --   the list. Called when clicked. Caller is responsible
--                        --   for calling BazUI:RefreshOptions(...) afterward
--                        --   so the new item appears.
--   createButtonText,    -- optional, defaults to "Create New".
--
--   onReset,             -- optional () -> ()
--                        --   Same pattern as onCreate; surfaces a Reset button
--                        --   below Create.
--   resetButtonText,     -- optional, defaults to "Reset to Defaults".
--
--   onMoveUp,            -- optional (item) -> ()
--   onMoveDown,          -- optional (item) -> ()
--                        --   When set, every row in the left list gets up /
--                        --   down arrow buttons on its right edge. Topmost
--                        --   and bottommost rows render their boundary arrow
--                        --   grayed out so the affordance is still visible.
--                        --   The callback receives the same `item` object
--                        --   getItems returned, so the caller can swap order
--                        --   with the adjacent neighbour and refresh. Replaces
--                        --   the "Order" range slider pattern - much less
--                        --   convoluted than asking users to type values
--                        --   between two existing orders.
-- }
---------------------------------------------------------------------------

function BazUI:CreateManagedListPage(addonName, config)
    return function()
        local args = {}

        -- Intro blocks render above the list/detail split. Either a
        -- single string (-> one lead block) or a full array of content
        -- blocks. introBlocks wins if both are passed.
        local introList = config.introBlocks
        if (not introList or #introList == 0) and config.intro then
            introList = { { type = "lead", text = config.intro } }
        end
        if introList then
            for i, block in ipairs(introList) do
                -- Negative orders so intro renders before create/reset.
                block.order = -100 + i
                args["intro_" .. i] = block
            end
        end

        -- Top-level execute buttons. CreateTwoPanelLayout collects any
        -- non-group execute that appears BEFORE a group (sorted by
        -- order) into executeArgs and renders them at the top of the
        -- LEFT list inside the picker.
        if config.onCreate then
            args.createBtn = {
                order = 0,
                type  = "execute",
                name  = config.createButtonText or "Create New",
                func  = config.onCreate,
            }
        end
        if config.onReset then
            args.resetBtn = {
                order = 1,
                type  = "execute",
                name  = config.resetButtonText or "Reset to Defaults",
                func  = config.onReset,
            }
        end

        -- Resolve the auto-h1 detail title behavior up front.
        --   nil / true  -> "h1" (default - matches User Manual)
        --   false       -> no auto-title
        --   "h2"/"h3"   -> use that heading level
        local detailTitleType
        if config.detailTitle == false then
            detailTitleType = nil
        elseif type(config.detailTitle) == "string" then
            detailTitleType = config.detailTitle
        else
            detailTitleType = "h1"
        end

        -- Build the wrapper group whose `.args` contain one sub-group
        -- per item. the picker scans the wrapper, treats
        -- each sub-group as a list row (clicking selects it), and
        -- renders the selected sub-group's args in the detail pane via
        -- O.RenderWidgets.
        --
        -- Detail-arg construction (the buildDetail call + block
        -- enumeration) is DEFERRED into a closure stored on each
        -- item's `_lazyDetailBuild`. the picker evaluates
        -- this on first selection - so a page with N items only ever
        -- builds N=1's worth of detail tables initially, instead of
        -- doing N x buildDetail upfront on every render. That used to
        -- be one of BazUI's biggest transient allocators on first
        -- page open (multiple MB of intermediate Lua tables /
        -- closures captured by buildDetail bodies).
        local items = (config.getItems and config.getItems()) or {}
        local itemArgs = {}
        for i, item in ipairs(items) do
            local itemName = item.name or item.label or tostring(item.key or i)
            local capturedItem = item
            local capturedName = itemName

            local function BuildDetailArgs()
                local detailArgs = {}
                local idx = 0

                -- Auto-h1 page title - matches the User Manual's
                -- RenderPageContent which prepends
                -- `{ type="h1", text=page.title }` to every page's blocks.
                if detailTitleType then
                    idx = idx + 1
                    detailArgs["b_" .. idx] = {
                        order = idx,
                        type  = detailTitleType,
                        text  = capturedName,
                    }
                end

                -- buildDetail provides the per-item content blocks.
                -- Order is overwritten by array position so
                -- caller-supplied orders never collide with the auto-h1.
                local userBlocks = (config.buildDetail and config.buildDetail(capturedItem)) or {}
                for _, block in ipairs(userBlocks) do
                    idx = idx + 1
                    block.order = idx
                    detailArgs["b_" .. idx] = block
                end

                return detailArgs
            end

            local itemKey = tostring(item.key or i)
            itemArgs["item_" .. itemKey] = {
                order            = item.order or (i * 10),
                type             = "group",
                name             = itemName,
                source           = item.source,
                args             = nil,                -- lazy - filled on first selection
                _lazyDetailBuild = BuildDetailArgs,
                -- Stash the original item so the row's move handlers
                -- can hand it back to config.onMoveUp/onMoveDown - the
                -- inner group is what the picker sees, not
                -- the original getItems() entry.
                _item  = item,
            }
        end

        -- Wrap the caller's per-item onMove* hooks so they always
        -- receive the original `item` object, not the inner wrapper
        -- group the picker passes around. Keeps the public
        -- API symmetric with buildDetail (also gets the item).
        local wrappedMoveUp = config.onMoveUp and function(childGroup)
            if childGroup and childGroup._item then
                config.onMoveUp(childGroup._item)
            end
        end or nil
        local wrappedMoveDown = config.onMoveDown and function(childGroup)
            if childGroup and childGroup._item then
                config.onMoveDown(childGroup._item)
            end
        end or nil

        args.items = {
            order      = 10,
            type       = "group",
            name       = "",      -- empty so no header renders above the list/detail
            args       = itemArgs,
            onMoveUp   = wrappedMoveUp,
            onMoveDown = wrappedMoveDown,
        }

        return {
            name = config.pageName or addonName,
            type = "group",
            args = args,
        }
    end
end
