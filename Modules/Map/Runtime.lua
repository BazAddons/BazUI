-- SPDX-License-Identifier: GPL-2.0-or-later
-- Small adapter for the MIT-licensed OpenMap rendering core. It has no
-- independent addon, settings database, slash commands or module loader.
local R = { modules = {}, loadMs = { parts = {} }, name = "BazUI" }
BazUI.MapRuntime = R
R.Media = { tex = "Interface\\AddOns\\BazUI\\Modules\\Map\\Assets\\Forever\\" }
R.L = setmetatable({}, { __index = function(_, key) return key end })

function R:NewModule(key, spec) self.modules[key] = spec; return spec end
function R:GetModule(key) return self.modules[key] end
function R:Print(message, ...)
    BazUI:Print("Map: " .. (select("#", ...) > 0 and message:format(...) or message))
end

local function IsSecret(value) return issecretvalue and issecretvalue(value) or false end
R.Safe = {}
function R.Safe.IsSecret(value) return IsSecret(value) end
function R.Safe.Value(value) if not IsSecret(value) then return value end end
function R.Safe.Call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and not IsSecret(value) then return value end
end
function R.Safe.XY(vector)
    if IsSecret(vector) or type(vector) ~= "table" then return end
    local ok, x, y = pcall(function()
        if vector.GetXY then return vector:GetXY() end
        return vector.x, vector.y
    end)
    if ok and not IsSecret(x) and not IsSecret(y) then return x, y end
end

local events, handlers = CreateFrame("Frame"), {}
events:SetScript("OnEvent", function(_, event, ...)
    for owner, fn in pairs(handlers[event] or {}) do
        local ok, err = pcall(fn, owner, event, ...)
        if not ok then geterrorhandler()(err) end
    end
end)
function R.RegisterEvent(owner, event, fn)
    if not handlers[event] then
        if not pcall(events.RegisterEvent, events, event) then return false end
        handlers[event] = {}
    end
    handlers[event][owner] = fn or owner[event]
    return true
end
function R.UnregisterEvent(owner, event)
    local list = handlers[event]
    if not list then return end
    list[owner] = nil
    if not next(list) then handlers[event] = nil; events:UnregisterEvent(event) end
end
