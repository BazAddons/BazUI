-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Module Registry
--
-- Modules under Modules/ end with:
--
--   BazChat:RegisterModule({
--       id      = "copyChat",
--       label   = "Copy Chat",
--       Init    = function() ... end,   -- one-time hookup
--       Refresh = function() ... end,   -- re-read settings, re-paint
--   })
--
-- BazChat:InitModules() is called once at PLAYER_LOGIN by Init.lua's
-- onReady. The Options page calls BazChat:RefreshAll() (or a single
-- module's Refresh) when settings change.
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace
local BazChat = addon.API             -- module API (the old BazChat global)

function BazChat:RegisterModule(spec)
    if not spec or type(spec.id) ~= "string" then return end
    addon.modules[#addon.modules + 1] = spec
    addon.modules[spec.id] = spec     -- also keyed by id for direct lookup
end

function BazChat:GetModule(id)
    return addon.modules[id]
end

function BazChat:InitModules()
    if not (addon.core and addon.core:GetSetting("enabled")) then return end
    for _, module in ipairs(addon.modules) do
        if module.Init then
            local ok, err = pcall(module.Init, module)
            if not ok and addon.core then
                addon.core:Print("|cffff4444Module init error (" ..
                    tostring(module.id) .. "):|r " .. tostring(err))
            end
        end
    end
end

function BazChat:RefreshAll()
    for _, module in ipairs(addon.modules) do
        if module.Refresh then
            pcall(module.Refresh, module)
        end
    end
end

function BazChat:RefreshModule(id)
    local module = addon.modules[id]
    if module and module.Refresh then
        pcall(module.Refresh, module)
    end
end
