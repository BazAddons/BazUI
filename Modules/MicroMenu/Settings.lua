-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Micro Menu: settings
--
-- Widget options, not a module page.
--
-- The micro menu is a drawer widget, so its settings belong where every
-- other widget's are: Drawers > Widgets > Micro Menu, and the same list
-- again in the Edit Mode popup when you click it. One table feeds both,
-- because the host builds the popup from GetOptionsArgs.
--
-- Everything reads and writes through addon:Opt / addon:SetOpt, which put
-- the values in the drawer's per-widget store and fall back to this
-- module's old settings while a profile still has them. See Bar.lua.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("MicroMenu")

local function Toggle(order, name, key, default, desc)
    return {
        order = order, type = "toggle", name = name, desc = desc, width = "full",
        get = function() return addon:Opt(key, default) ~= false end,
        set = function(_, value) addon:SetOpt(key, value and true or false) end,
    }
end

function addon:WidgetOptions()
    local args = {
        layoutHeader = { order = 10, type = "header", name = "Layout" },

        orientation = {
            order = 11, type = "select", name = "Orientation",
            desc = "Which way the buttons run. Rows become columns when it "
                .. "is vertical.",
            values = { horizontal = "Horizontal", vertical = "Vertical" },
            get = function() return addon:Opt("orientation", "horizontal") end,
            set = function(_, value) addon:SetOpt("orientation", value) end,
        },

        rows = {
            order = 12, type = "range", name = "Rows",
            desc = "Wrap the buttons over more than one row. Ten buttons in "
                .. "two rows is five and five - the rows are filled evenly "
                .. "rather than filling one and leaving a stub.",
            min = 1, max = 4, step = 1,
            get = function() return addon:Opt("rows", 1) end,
            set = function(_, value) addon:SetOpt("rows", value) end,
        },

        buttonSize = {
            order = 13, type = "range", name = "Button size",
            min = 16, max = 64, step = 1,
            get = function() return addon:Opt("buttonSize", 30) end,
            set = function(_, value) addon:SetOpt("buttonSize", value) end,
        },

        spacing = {
            order = 14, type = "range", name = "Spacing",
            min = 0, max = 24, step = 1,
            get = function() return addon:Opt("spacing", 6) end,
            set = function(_, value) addon:SetOpt("spacing", value) end,
        },

        appearanceHeader = { order = 20, type = "header", name = "Appearance" },

        skin = Toggle(21, "BazUI skin", "skin", true,
            "Round icons in the suite's ring, which is how the rest of the "
            .. "addon draws a button. Off leaves Blizzard's own art alone - "
            .. "the buttons still sit on this widget and still move with it, "
            .. "they simply keep the shape the game drew them. They are not "
            .. "square, so an unskinned row is sized by height and each "
            .. "button keeps its own width."),

        hideBlizzard = Toggle(22, "Hide Blizzard's micro menu", "hideBlizzard",
            true,
            "Park the stock micro menu container in the bottom right. Its "
            .. "buttons live on this widget either way."),

        buttonsHeader = { order = 30, type = "header", name = "Buttons" },
    }

    -- Only the buttons this client actually has.
    --
    -- These used to be listed for both clients with the absent ones grayed
    -- out, on the usual rule that a setting which does not apply is
    -- disabled in place rather than hidden - so nobody goes hunting for a
    -- row that moved.
    --
    -- That rule is about a setting that does not apply *right now*:
    -- something another switch has turned off, which you could turn back
    -- on. It does not cover a button this client will never have. Forever
    -- has no Achievements, no Housing, no Social; a switch for them is not
    -- a choice you could ever make, and four dead rows in a list of
    -- fourteen is not honesty, it is clutter that reads as broken.
    --
    -- addon:Buttons() is the client's own answer, already in the order the
    -- client puts them in, so the list here matches the bar exactly.
    for index, listed in ipairs(addon:Buttons()) do
        local def = listed.def
        args["btn_" .. def.key] = {
            order = 30 + index, type = "toggle", name = def.label, width = "full",
            desc = "Whether this button is on the bar.",
            get = function()
                local prefs = addon:Opt("buttons", nil)
                return not prefs or prefs[def.key] ~= false
            end,
            set = function(_, value)
                local prefs = addon:Opt("buttons", nil) or {}
                prefs[def.key] = value and true or false
                addon:SetOpt("buttons", prefs)
            end,
        }
    end

    return args
end
