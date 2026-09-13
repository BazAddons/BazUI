-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: SettingsSpec
--
-- A unified settings-spec format that lets each Baz Suite addon define
-- its settings ONCE and have BazUI generate both:
--   * an Options page (via Options/Registration.lua)
--   * an Edit Mode panel (via EditMode.lua)
--
-- Without this, each addon hand-writes the same settings twice (once
-- per surface) and the two surfaces drift apart over time. The spec
-- format is deliberately minimal: a list of sections + a list of
-- entries, with each entry tagged with which surfaces it appears in.
--
-- Public API (BazUI:):
--   :RegisterSettingsSpec(addonName, spec)
--   :GetSettingsSpec(addonName)             -- returns the registered spec
--   :BuildOptionsTableFromSpec(addonName, opts)
--                                            -- -> { name, args = {...} }
--   :BuildEditModeArrayFromSpec(addonName)
--                                            -- -> array of EditMode setting defs
--
-- The Build* functions return tables ready to feed straight into the
-- existing RegisterOptionsTable / RegisterEditModeFrame APIs - so an
-- addon's wiring becomes a thin "pass spec to BazUI, hand result to
-- the existing register call."
--
-- Spec format:
--   {
--       sections = {
--           appearance = { label = "Appearance", order = 10 },
--           behavior   = { label = "Behavior",   order = 20 },
--           timestamps = { label = "Timestamps", order = 30 },
--       },
--       entries = {
--           { key, label, desc, type, section, order, surfaces, ... },
--           ...
--       },
--   }
--
-- Entry fields:
--   key        - unique within the addon (used as the args[] key)
--   label      - display name in the panel
--   desc       - optional help text
--   type       - canonical type: slider | toggle | select | input
--                | header | note | nudge | execute
--   section    - section key (matches a sections[] entry)
--   order      - within-section ordering (defaults to insertion order)
--   surfaces   - { options = true|false, editMode = true|false }
--                (default: { options = true } - explicit opt-in for editMode)
--
-- Type-specific fields:
--   slider:    min, max, step, format (string|function)
--   toggle:    -
--   select:    values = { key = "Label", ... }
--   input:     -
--   note:      style = "info"|"tip"|"warn", text = "..."
--   execute:   func, confirm, confirmText, width
--   header:    -
--   nudge:     - (editMode-only)
--
-- Common fields:
--   get        - function() -> current value
--   set        - function(_, value) -- save the new value
--   disabled   - function() -> bool (live grey-out check)
--   disabledLabel - string shown in editMode dropdowns when disabled
--
-- Format helpers:
--   format = "percent"  -> "0%" .. "100%" (assumes 0..1 range)
--   format = "seconds"  -> "Ns"
--   format = "px"       -> "Npx"
--   format = function(v) -> custom string
--   format = nil        -> raw number
---------------------------------------------------------------------------

BazUI = BazUI or {}

local specs = BazUI._SettingsSpecs or {}
BazUI._SettingsSpecs = specs

---------------------------------------------------------------------------
-- Format helpers
---------------------------------------------------------------------------

-- Format presets exist in TWO shapes because the Options page's range
-- widget calls string.format(opt.format, val) (printf-string semantics)
-- while the EditMode slider calls opt.format(val) (function semantics).
-- Same preset name, different output type per surface.
local FORMAT_PRESETS_FN = {
    percent = function(v) return math.floor((v or 0) * 100 + 0.5) .. "%" end,
    seconds = function(v) return string.format("%.1fs", v or 0) end,
    px      = function(v) return math.floor((v or 0) + 0.5) .. " px" end,
    integer = function(v) return tostring(math.floor((v or 0) + 0.5)) end,
}

-- printf-style format strings for the Options page's string.format()
-- code path. `percent` is omitted because Options has its own
-- isPercent=true flag for that case.
local FORMAT_PRESETS_PRINTF = {
    seconds = "%.1fs",
    px      = "%d px",
    integer = "%d",
}

local function ResolveFormatFn(fmt)
    if type(fmt) == "function" then return fmt end
    if type(fmt) == "string"   then return FORMAT_PRESETS_FN[fmt] end
    return nil
end

local function ResolveFormatPrintf(fmt)
    if type(fmt) == "string" then return FORMAT_PRESETS_PRINTF[fmt] end
    -- Function-format custom strings can't be expressed as printf;
    -- the Options widget falls back to default formatting in that case.
    return nil
end

---------------------------------------------------------------------------
-- :RegisterSettingsSpec — store a spec for later building
---------------------------------------------------------------------------

function BazUI:RegisterSettingsSpec(addonName, spec)
    if type(addonName) ~= "string" or type(spec) ~= "table" then return end
    specs[addonName] = spec
end

function BazUI:GetSettingsSpec(addonName)
    return specs[addonName]
end

---------------------------------------------------------------------------
-- Internal: spec validation / iteration
---------------------------------------------------------------------------

-- Returns sections in order. Falls back to a single "Default" section
-- if the spec has no sections defined.
local function GetSortedSections(spec)
    if type(spec.sections) ~= "table" or next(spec.sections) == nil then
        return { { key = "_default", label = "" } }
    end
    local out = {}
    for key, s in pairs(spec.sections) do
        out[#out + 1] = {
            key   = key,
            label = s.label or key,
            order = s.order or 100,
        }
    end
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return tostring(a.label) < tostring(b.label)
    end)
    return out
end

-- Returns the entries that belong to a given section + surface, sorted
-- by their `order` field (with insertion order as the tiebreaker).
local function GetEntriesFor(spec, sectionKey, surface)
    local out = {}
    for i, e in ipairs(spec.entries or {}) do
        if (e.section or "_default") == sectionKey then
            local surfaces = e.surfaces
            -- Default: options-only. Editmode is opt-in.
            local include
            if surfaces == nil then
                include = (surface == "options")
            else
                include = surfaces[surface] == true
            end
            if include then
                out[#out + 1] = { entry = e, _idx = i }
            end
        end
    end
    table.sort(out, function(a, b)
        local ao = a.entry.order or a._idx
        local bo = b.entry.order or b._idx
        return ao < bo
    end)
    local stripped = {}
    for i, w in ipairs(out) do stripped[i] = w.entry end
    return stripped
end

---------------------------------------------------------------------------
-- :BuildOptionsTableFromSpec
--
-- Translates the spec into the AceConfig-shaped table that
-- RegisterOptionsTable consumes:
--
--   {
--       name = ..., type = "group",
--       args = {
--           hdr_appearance     = { type = "header", name = "Appearance", order = 10 },
--           alpha              = { type = "range",  name = "Text opacity", ... },
--           ...
--       },
--   }
--
-- opts (optional): { name = "...", intro = "..." }
---------------------------------------------------------------------------

local function BuildOptionsArgsForEntry(e)
    local out = {
        name = e.label,
        desc = e.desc,
        get  = e.get,
        set  = e.set,
        disabled = e.disabled,
    }
    if e.type == "slider" then
        out.type   = "range"
        out.min    = e.min
        out.max    = e.max
        out.step   = e.step
        if e.format == "percent" then
            out.isPercent = true
        else
            -- Options' range widget consumes opt.format as a printf
            -- string via string.format(). Function-style formats can't
            -- be passed directly here; the widget falls back to its
            -- step-based default ("%.1f" for sub-1 steps, integer
            -- otherwise) which is good enough for custom-format cases.
            local fmt = ResolveFormatPrintf(e.format)
            if fmt then out.format = fmt end
        end
    elseif e.type == "toggle" then
        out.type  = "toggle"
        out.width = e.width or "full"
    elseif e.type == "select" then
        out.type   = "select"
        out.values = e.values
    elseif e.type == "input" then
        out.type = "input"
    elseif e.type == "header" then
        out.type = "header"
    elseif e.type == "note" then
        -- Closest Options analog is the description widget; we lose the
        -- style differentiation but keep the text inline.
        out.type = "description"
        out.name = e.text or e.label
    elseif e.type == "execute" then
        out.type        = "execute"
        out.func        = e.func
        out.confirm     = e.confirm
        out.confirmText = e.confirmText
        out.width       = e.width
    else
        return nil  -- unknown type; skip
    end
    return out
end

function BazUI:BuildOptionsTableFromSpec(addonName, opts)
    local spec = specs[addonName]
    if not spec then return nil end
    opts = opts or {}

    local args = {}
    local order = 1
    local intro = opts.intro or spec.intro

    if intro then
        args["_intro"] = { type = "lead", name = intro, order = 0 }
        order = order + 1
    end

    local sections = GetSortedSections(spec)
    for _, sec in ipairs(sections) do
        local entries = GetEntriesFor(spec, sec.key, "options")
        if #entries > 0 then
            -- Section header (skip when section has no label - "_default")
            if sec.label and sec.label ~= "" then
                args["_hdr_" .. sec.key] = {
                    type = "header", name = sec.label, order = order,
                }
                order = order + 1
            end
            for _, e in ipairs(entries) do
                local widget = BuildOptionsArgsForEntry(e)
                if widget then
                    widget.order = order
                    args[e.key] = widget
                    order = order + 1
                end
            end
        end
    end

    return {
        name = opts.name or addonName,
        type = "group",
        args = args,
    }
end

---------------------------------------------------------------------------
-- :BuildEditModeArrayFromSpec
--
-- Translates the spec into the array EditMode.lua's RegisterEditModeFrame
-- expects in its `settings = {...}` config field:
--
--   {
--       { type = "slider",   key = "alpha", label = "Text opacity",
--         section = "Appearance", min = 0, max = 1, step = 0.05,
--         format = function(v) ... end,
--         get = ..., set = ..., disabled = ..., disabledLabel = ... },
--       ...
--   }
--
-- Edit Mode reads the section field as a string (not key); we use the
-- section's display label so the popup renders cleanly grouped.
---------------------------------------------------------------------------

local function ValuesMapToArray(values)
    -- Edit Mode's dropdown widget wants an array of {label, value} pairs.
    -- The spec's `values` is a {key = label, ...} map. Translate.
    if type(values) ~= "table" then return {} end
    local out = {}
    for value, label in pairs(values) do
        out[#out + 1] = { label = label, value = value }
    end
    -- Stable ordering: alphabetical by label so the popup is consistent.
    table.sort(out, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return out
end

local function BuildEditModeWidgetForEntry(e, sectionLabel)
    local out = {
        key      = e.key,
        label    = e.label,
        section  = sectionLabel,
        get      = e.get,
        set      = e.set and function(v) e.set(nil, v) end,
        disabled = e.disabled,
        disabledLabel = e.disabledLabel,
    }
    if e.type == "slider" then
        out.type   = "slider"
        out.min    = e.min
        out.max    = e.max
        out.step   = e.step
        out.format = ResolveFormatFn(e.format)
    elseif e.type == "toggle" then
        out.type = "checkbox"
    elseif e.type == "select" then
        out.type    = "dropdown"
        out.options = ValuesMapToArray(e.values)
    elseif e.type == "input" then
        out.type = "input"
    elseif e.type == "nudge" then
        out.type = "nudge"
        out.key  = nil   -- nudge has no key
    else
        return nil  -- unknown / not-edit-mode type
    end
    return out
end

function BazUI:BuildEditModeArrayFromSpec(addonName)
    local spec = specs[addonName]
    if not spec then return {} end

    local out = {}
    local sections = GetSortedSections(spec)
    for _, sec in ipairs(sections) do
        local entries = GetEntriesFor(spec, sec.key, "editMode")
        for _, e in ipairs(entries) do
            local w = BuildEditModeWidgetForEntry(e, sec.label or "")
            if w then out[#out + 1] = w end
        end
    end
    return out
end
