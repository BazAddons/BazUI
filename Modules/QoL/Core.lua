-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Quality of Life
--
-- The small things: instant quest text, repairing without clicking the
-- anvil, selling the grey rubbish, a screenshot when you level.
--
-- None of them are a system of their own, and that is the point of
-- putting them together. What this module is, is a list: each tweak says
-- what it is called, which drawer of the settings page it belongs in, and
-- how to turn it on. The page is built from that list, so adding the
-- twentieth tweak is adding one entry rather than a setting, a handler
-- and a line in a page somebody has to remember to update.
--
-- Everything starts off. These change how the game behaves rather than
-- how it looks, and a module that quietly rewrote your settings the first
-- time it loaded would be a bad neighbour.
---------------------------------------------------------------------------

local addon
addon = BazUI:RegisterModule("QoL", {
    title = "Quality of Life",
    icon = "Interface\\Icons\\INV_Misc_Gear_01",
    minimap = { label = "Quality of Life", icon = "Interface\\Icons\\INV_Misc_Gear_01" },
    profiles = true,
    defaults = {
        -- Each tweak keeps its own switch under here, and the value it
        -- found in any CVar it changes, so turning it off puts back what
        -- was there rather than what we guessed was there.
        tweaks   = {},
        restores = {},
    },
    slash = { "/bazqol" },
    defaultHandler = function() BazUI:OpenOptionsPanel("QoL") end,
    onReady = function(self)
        self:ApplySettings()
        self:OnProfileChanged(function() self:ApplySettings() end)
    end,
})

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

addon.tweaks = {}

-- A tweak is:
--   key      what its switch is saved under
--   label    what the page calls it
--   desc     what it does, in the player's terms
--   section  which group on the page
--   order    within that group
--   cvar     for a tweak that is only a console setting
--   default  on before anybody has touched the switch. Absent means off,
--            which is what nearly all of these want - see the note at the
--            top. The windows are the exception: making one draggable
--            changes nothing about the game until you drag it.
--   on/off   the values that CVar takes (default "1" and "0")
--   OnApply  for a tweak that is code, called when it is switched on or
--            off with (enabled) - most do their work in an event handler
--            and only need this to catch up with the current state
function addon:RegisterTweak(def)
    if not (def and def.key) then return end
    self.tweaks[#self.tweaks + 1] = def
    return def
end

function addon:Tweak(key)
    for _, def in ipairs(self.tweaks) do
        if def.key == key then return def end
    end
end

---------------------------------------------------------------------------
-- Switches
---------------------------------------------------------------------------

-- Checked against nil rather than leaned on: `saved or default` would
-- turn every deliberate false back on, and SetEnabled writes a real false
-- for exactly that reason.
function addon:Enabled(key)
    local tweaks = self:GetSetting("tweaks") or {}
    local saved = tweaks[key]
    if saved ~= nil then return saved and true or false end
    local def = self:Tweak(key)
    return (def and def.default) and true or false
end

function addon:SetEnabled(key, on)
    local tweaks = self:GetSetting("tweaks") or {}
    -- An explicit false rather than nil, so a switch somebody turned off
    -- stays off if the default ever changes.
    tweaks[key] = on and true or false
    self:SetSetting("tweaks", tweaks)
    self:ApplyTweak(self:Tweak(key))
end

---------------------------------------------------------------------------
-- Console settings
--
-- Remembered before they are changed and put back when the tweak is
-- switched off, because the value that was there is the player's and we
-- are only borrowing it. Remembered once: turning a tweak off and on
-- again must not record our own value as though it were theirs.
---------------------------------------------------------------------------

local function ApplyCVar(def, enabled)
    if not (def.cvar and GetCVar and SetCVar) then return end
    local restores = addon:GetSetting("restores") or {}

    if enabled then
        if restores[def.cvar] == nil then
            restores[def.cvar] = GetCVar(def.cvar) or ""
            addon:SetSetting("restores", restores)
        end
        SetCVar(def.cvar, def.on or "1")
    else
        local previous = restores[def.cvar]
        if previous ~= nil and previous ~= "" then
            SetCVar(def.cvar, previous)
        elseif def.off then
            SetCVar(def.cvar, def.off)
        end
        restores[def.cvar] = nil
        addon:SetSetting("restores", restores)
    end
end

function addon:ApplyTweak(def)
    if not def then return end
    local enabled = self:Enabled(def.key)
    ApplyCVar(def, enabled)
    if def.OnApply then def.OnApply(enabled) end
end

-- Every console setting a tweak changes, and every call one makes. See
-- Core/Compat.lua: a renamed CVar is a switch that does nothing.
function addon:RegisterDependencies()
    for _, def in ipairs(self.tweaks) do
        if def.cvar then
            BazUI:RegisterDependency({
                module = "Quality of Life",
                label  = "CVar " .. def.cvar,
                why    = def.label .. " sets it.",
                check  = function() return BazUI.Has.CVar(def.cvar) end,
            })
        end
    end
end

function addon:ApplySettings()
    for _, def in ipairs(self.tweaks) do
        self:ApplyTweak(def)
    end
end
