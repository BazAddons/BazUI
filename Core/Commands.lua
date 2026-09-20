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

    -- Second names for a command.
    --
    -- `aliases` is a list on the command itself, and the help line is
    -- built from it, so the two can never disagree. They used to: the
    -- `usage` field was carrying "dup, copy" purely so the help would
    -- print it, and nothing dispatched those names - /bb help advertised
    -- three commands that answered "Unknown command".
    --
    -- Resolved at registration rather than at dispatch: one table lookup
    -- either way, and the alias table is the answer to "what can I
    -- type", which is a question the help asks too.
    local aliasOf = {}
    for name, def in pairs(commands) do
        for _, alias in ipairs((type(def) == "table" and def.aliases) or {}) do
            alias = strlower(alias)
            if commands[alias] then
                print(("|cffff4444BazUI:|r %s aliases '%s' to '%s', but that"
                    .. " is a command of its own. The alias is ignored."):format(
                    addonName, alias, name))
            else
                aliasOf[alias] = name
            end
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
        local cmdDef = commands[cmd] or commands[aliasOf[cmd] or ""]
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
        if entry.def.aliases and #entry.def.aliases > 0 then
            usage = usage .. " (or " .. table.concat(entry.def.aliases, ", ") .. ")"
        end
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
