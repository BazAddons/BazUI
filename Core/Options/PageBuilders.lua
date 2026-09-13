-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: Page Builders
-- Standardized page generators: Landing, Modules, GlobalOptions, ManagedList
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- CreateLandingPage
-- Builds a standardized landing/manual page with description, features,
-- quick guide, and slash commands sections.
---------------------------------------------------------------------------

function BazUI:CreateLandingPage(addonName, content)
    local args = {}
    local order = 1

    if content.description then
        args.desc = {
            order = order,
            type = "description",
            name = content.description,
        }
        order = order + 1
    end

    if content.features then
        args.featuresHeader = {
            order = order,
            type = "header",
            name = "Features",
        }
        order = order + 1
        -- Colorize all-caps lines as gold sub-headers
        local featText = content.features:gsub("([^\n]*)\n", function(line)
            if line:match("^%u[%u%s%&%-]+$") then
                return "|cffffd700" .. line .. "|r\n"
            end
            return line .. "\n"
        end)
        args.features = {
            order = order,
            type = "description",
            name = featText,
            fontSize = "small",
        }
    end

    if content.guide then
        args.guideHeader = {
            order = 20,
            type = "header",
            name = "Quick Guide",
        }

        local guideLines = {}
        for _, entry in ipairs(content.guide) do
            -- Strip leading numbers like "1. " or "13. "
            local title = entry[1]:upper():gsub("^%d+%.%s*", "")
            guideLines[#guideLines + 1] = "|cffffd700" .. title .. "|r\n" .. entry[2]
        end
        local guideText = table.concat(guideLines, "\n\n")
        args.guideText = {
            order = 21,
            type = "description",
            name = guideText,
            fontSize = "small",
        }
    end

    -- Slash Commands
    if content.commands then
        args.commandsHeader = {
            order = 40,
            type = "header",
            name = "Slash Commands",
        }
        local cmdLines = {}
        for _, cmd in ipairs(content.commands) do
            cmdLines[#cmdLines + 1] = "|cff00ff00" .. cmd[1] .. "|r - " .. cmd[2]
        end
        args.commandsList = {
            order = 41,
            type = "description",
            name = table.concat(cmdLines, "\n"),
        }
    end

    return {
        name = addonName,
        type = "group",
        args = args,
    }
end

---------------------------------------------------------------------------
-- CreateModulesPage
-- Flat list of enable/disable toggles for modules/widgets.
---------------------------------------------------------------------------

function BazUI:CreateModulesPage(addonName, config)
    local args = {}

    if config.description then
        args.desc = {
            order = 1,
            type = "description",
            name = config.description,
            fontSize = "small",
        }
    end

    local modules = config.getModules and config.getModules() or {}
    table.sort(modules, function(a, b)
        return (a.name or a.id or "") < (b.name or b.id or "")
    end)

    for i, mod in ipairs(modules) do
        local id = mod.id
        args["mod_" .. id] = {
            order = 10 + i,
            type = "toggle",
            name = mod.name or id,
            desc = mod.desc,
            get = function()
                if config.isEnabled then return config.isEnabled(id) end
                return true
            end,
            set = function(_, val)
                if config.setEnabled then config.setEnabled(id, val) end
            end,
        }
    end

    return {
        name = config.title or "Modules",
        type = "group",
        args = args,
    }
end

---------------------------------------------------------------------------
-- CreateGlobalOptionsPage
-- Per-key override toggles that cascade to all widgets/modules.
---------------------------------------------------------------------------

function BazUI:CreateGlobalOptionsPage(addonName, config)
    local args = {}
    local order = 1

    args.desc = {
        order = order,
        type = "description",
        name = "Global overrides apply to all widgets at once. Enable an override to force its value across every widget, regardless of per-widget settings.",
        fontSize = "small",
    }
    order = order + 1

    for _, def in ipairs(config.overrides or {}) do
        local key = def.key

        args["hdr_" .. key] = {
            order = order,
            type = "header",
            name = def.label or key,
        }
        order = order + 1

        args["enable_" .. key] = {
            order = order,
            type = "toggle",
            name = "Override all modules",
            desc = "When enabled, this value overrides the per-widget setting for '" .. (def.label or key) .. "'.",
            get = function()
                local overrides = config.getOverrides()
                return overrides[key] and overrides[key].enabled or false
            end,
            set = function(_, val)
                config.setOverride(key, "enabled", val)
                BazUI:RefreshOptions(addonName .. "-GlobalOptions")
            end,
        }
        order = order + 1

        if def.type == "toggle" then
            args["val_" .. key] = {
                order = order,
                type = "toggle",
                name = def.label or key,
                get = function()
                    local overrides = config.getOverrides()
                    if overrides[key] and overrides[key].value ~= nil then
                        return overrides[key].value
                    end
                    return def.default
                end,
                set = function(_, val)
                    config.setOverride(key, "value", val)
                end,
                disabled = function()
                    local overrides = config.getOverrides()
                    return not (overrides[key] and overrides[key].enabled)
                end,
            }
        elseif def.type == "range" then
            args["val_" .. key] = {
                order = order,
                type = "range",
                name = def.label or key,
                min = def.min or 0,
                max = def.max or 100,
                step = def.step or 1,
                get = function()
                    local overrides = config.getOverrides()
                    if overrides[key] and overrides[key].value ~= nil then
                        return overrides[key].value
                    end
                    return def.default or def.min or 0
                end,
                set = function(_, val)
                    config.setOverride(key, "value", val)
                end,
                disabled = function()
                    local overrides = config.getOverrides()
                    return not (overrides[key] and overrides[key].enabled)
                end,
            }
        end
        order = order + 1
    end

    return {
        name = "Global Options",
        type = "group",
        args = args,
    }
end

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
-- Internally produces the wrapper-group shape that BuildListDetailPanel
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
--                        --   greyed out so the affordance is still visible.
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
        -- LEFT list inside BuildListDetailPanel.
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

        -- Resolve the auto-h1 detail title behaviour up front.
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
        -- per item. BuildListDetailPanel scans the wrapper, treats
        -- each sub-group as a list row (clicking selects it), and
        -- renders the selected sub-group's args in the detail pane via
        -- O.RenderWidgets.
        --
        -- Detail-arg construction (the buildDetail call + block
        -- enumeration) is DEFERRED into a closure stored on each
        -- item's `_lazyDetailBuild`. BuildListDetailPanel evaluates
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
                -- inner group is what BuildListDetailPanel sees, not
                -- the original getItems() entry.
                _item  = item,
            }
        end

        -- Wrap the caller's per-item onMove* hooks so they always
        -- receive the original `item` object, not the inner wrapper
        -- group BuildListDetailPanel passes around. Keeps the public
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
