-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Commands Module
-- Declarative slash command framework with auto-generated help
---------------------------------------------------------------------------

local BRAND_COLOR = "3399ff"
local CMD_COLOR   = "00ff00"

---------------------------------------------------------------------------
-- Command Registration
---------------------------------------------------------------------------

function BazUI:RegisterCommands(addonName, config)
    if not config.slash or #config.slash == 0 then return end

    local displayName = config.title or addonName
    local commands = config.commands or {}
    local primarySlash = config.slash[1]

    -- `settings` and `help` are answered below before anything the module
    -- registered is looked at, so a module command by either name is
    -- simply unreachable - and silently so, which cost an afternoon once:
    -- a new /baz settings opened the options panel instead of running,
    -- and nothing anywhere said why. Say it at registration, where the
    -- person who can fix it is looking.
    for _, reserved in ipairs({ "settings", "help" }) do
        if commands[reserved] then
            print(("|cffff4444BazUI:|r %s registered '%s', which %s answers itself."
                .. " Rename it; it can never run."):format(
                addonName, reserved, primarySlash))
            commands[reserved] = nil
        end
    end

    -- Build the slash handler
    local function HandleSlash(msg)
        local cmd, args = strmatch(msg, "^(%S+)%s*(.*)")
        cmd = cmd and strlower(cmd) or ""
        args = args or ""

        -- Built-in: settings
        if cmd == "settings" then
            BazUI:OpenOptionsPanel(addonName)
            return
        end

        -- Built-in: help
        if cmd == "help" then
            BazUI:PrintCommandHelp(addonName, config)
            return
        end

        -- Empty input: default handler or open settings
        if cmd == "" then
            if config.defaultHandler then
                config.defaultHandler()
            elseif BazUI.OpenOptionsPanel then
                BazUI:OpenOptionsPanel(addonName)
            else
                BazUI:OpenOptionsPanel(addonName)
            end
            return
        end

        -- User-defined commands
        local cmdDef = commands[cmd]
        if cmdDef and cmdDef.handler then
            cmdDef.handler(args)
            return
        end

        -- Unknown command
        print(string.format(
            "|cff%s%s|r: Unknown command '|cff%s%s|r'. Type |cff%s%s help|r",
            BRAND_COLOR, displayName, "ff4444", cmd, CMD_COLOR, primarySlash
        ))
    end

    -- Register all slash variants
    local slashBase = strupper(addonName:gsub("[^%w]", ""))
    for i, slash in ipairs(config.slash) do
        _G["SLASH_" .. slashBase .. i] = slash
    end
    SlashCmdList[slashBase] = HandleSlash
end

---------------------------------------------------------------------------
-- Help Output
---------------------------------------------------------------------------

function BazUI:PrintCommandHelp(addonName, config)
    local displayName = config.title or addonName
    local primarySlash = config.slash[1]
    local commands = config.commands or {}

    print(string.format("|cff%s%s|r commands:", BRAND_COLOR, displayName))

    -- User-defined commands (sorted alphabetically)
    local sorted = {}
    for name, def in pairs(commands) do
        table.insert(sorted, { name = name, def = def })
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)

    for _, entry in ipairs(sorted) do
        local usage = entry.def.usage and (" " .. entry.def.usage) or ""
        local desc = entry.def.desc or ""
        print(string.format(
            "  |cff%s%s %s%s|r - %s",
            CMD_COLOR, primarySlash, entry.name, usage, desc
        ))
    end

    -- Built-in commands
    print(string.format("  |cff%s%s settings|r - Open settings", CMD_COLOR, primarySlash))
    print(string.format("  |cff%s%s help|r - Show this help", CMD_COLOR, primarySlash))
end
