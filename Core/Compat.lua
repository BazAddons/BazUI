-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: what we are leaning on
--
-- A good deal of this addon works by taking hold of the game's own
-- furniture: a frame by name, a template, a console setting, an entry in
-- one of the game's tables. None of that is API. It is whatever the
-- client happened to be built with, and a new client is free to build it
-- differently - a frame renamed, a template folded into another, a member
-- moved. When that happens nothing errors. A hook silently never fires, a
-- frame is never hidden, a switch does nothing, and it all looks like a
-- bug in our code.
--
-- So every one of those holds is declared next to the code that takes it,
-- and /bazui check reads the lot back:
--
--   BazUI:RegisterDependency{
--       module = "Nameplates",
--       label  = "C_NamePlate.GetNamePlateForUnit",
--       why    = "Finding the frame the game gave a unit.",
--       check  = function() return BazUI.Has.Member(C_NamePlate, "GetNamePlateForUnit") end,
--   }
--
-- Declared beside the code rather than in a list here, because a list
-- somewhere else is a list that goes stale the first time somebody
-- changes the code without remembering it exists.
---------------------------------------------------------------------------

local dependencies = {}

---------------------------------------------------------------------------
-- The kinds of thing worth asking about
---------------------------------------------------------------------------

BazUI.Has = {}

function BazUI.Has.Global(name)
    return _G[name] ~= nil
end

-- A frame by name. Distinct from a global because plenty of globals are
-- functions and the failure reads differently.
function BazUI.Has.Frame(name)
    local frame = _G[name]
    return frame ~= nil and type(frame) == "table" and frame.GetObjectType ~= nil
end

function BazUI.Has.Member(container, key)
    return type(container) == "table" and container[key] ~= nil
end

function BazUI.Has.Template(name)
    local info = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo(name)
    return info ~= nil
end

-- A console setting. GetCVar answers nil for one the client has never
-- heard of, which is what a renamed setting looks like.
function BazUI.Has.CVar(name)
    local get = C_CVar and C_CVar.GetCVar or _G.GetCVar
    if not get then return false end
    local ok, value = pcall(get, name)
    return ok and value ~= nil
end

---------------------------------------------------------------------------
-- Declaring and reading back
---------------------------------------------------------------------------

function BazUI:RegisterDependency(def)
    if not (def and def.label and def.check) then return end
    dependencies[#dependencies + 1] = def
end

-- Every declared hold, asked now. Returns the list and how many failed,
-- so something other than the slash command could show this later.
function BazUI:CheckDependencies()
    local results, missing = {}, 0

    for _, def in ipairs(dependencies) do
        -- A check that errors is a check that failed: whatever it was
        -- reaching for was not there to be reached.
        local ok, present = pcall(def.check)
        present = ok and present and true or false
        if not present then missing = missing + 1 end
        results[#results + 1] = {
            module  = def.module or "BazUI",
            label   = def.label,
            why     = def.why,
            present = present,
        }
    end

    table.sort(results, function(a, b)
        if a.module ~= b.module then return a.module < b.module end
        return a.label < b.label
    end)

    return results, missing
end

function BazUI:PrintDependencyReport()
    local results, missing = self:CheckDependencies()

    if #results == 0 then
        self:Print("Nothing is declared as a dependency yet.")
        return
    end

    self:Print(("Checking %d things the addon takes hold of in the game's own UI:"):format(#results))

    local lastModule
    for _, entry in ipairs(results) do
        if entry.module ~= lastModule then
            lastModule = entry.module
            print("  |cffffd700" .. entry.module .. "|r")
        end
        if entry.present then
            print("    |cff44ff44ok|r      " .. entry.label)
        else
            print("    |cffff4444MISSING|r " .. entry.label
                .. (entry.why and ("  - " .. entry.why) or ""))
        end
    end

    if missing == 0 then
        self:Print("|cff44ff44Everything is where we expect it.|r")
    else
        self:Print(("|cffff4444%d missing.|r Anything above marked MISSING will fail quietly rather than error, so start there."):format(missing))
    end
end
