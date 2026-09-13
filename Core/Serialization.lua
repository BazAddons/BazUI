-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Serialization Module
-- Table serialization + Base64 encoding for import/export
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Base64
---------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- Cache string globals for hot paths
local strbyte = strbyte
local strsub = strsub
local strfind = strfind
local strchar = string.char
local floor = math.floor
local MAX_DEPTH = 20

local function Base64Encode(data)
    local out = {}
    local pad = 0

    for i = 1, #data, 3 do
        local a = strbyte(data, i)
        local b = strbyte(data, i + 1) or 0
        local c = strbyte(data, i + 2) or 0

        if i + 1 > #data then pad = pad + 1 end
        if i + 2 > #data then pad = pad + 1 end

        local n = a * 65536 + b * 256 + c

        table.insert(out, strsub(B64, floor(n / 262144) + 1, floor(n / 262144) + 1))
        table.insert(out, strsub(B64, floor(n / 4096) % 64 + 1, floor(n / 4096) % 64 + 1))
        table.insert(out, pad >= 2 and "=" or strsub(B64, floor(n / 64) % 64 + 1, floor(n / 64) % 64 + 1))
        table.insert(out, pad >= 1 and "=" or strsub(B64, n % 64 + 1, n % 64 + 1))
    end

    return table.concat(out)
end

-- Build reverse lookup
local B64_DECODE = {}
for i = 1, #B64 do
    B64_DECODE[strbyte(B64, i)] = i - 1
end
B64_DECODE[strbyte("=")] = 0

local function Base64Decode(data)
    -- Strip whitespace
    data = data:gsub("%s", "")

    local out = {}

    for i = 1, #data, 4 do
        local a = B64_DECODE[strbyte(data, i)] or 0
        local b = B64_DECODE[strbyte(data, i + 1)] or 0
        local c = B64_DECODE[strbyte(data, i + 2)] or 0
        local d = B64_DECODE[strbyte(data, i + 3)] or 0

        local n = a * 262144 + b * 4096 + c * 64 + d

        table.insert(out, strchar(floor(n / 65536) % 256))
        if strsub(data, i + 2, i + 2) ~= "=" then
            table.insert(out, strchar(floor(n / 256) % 256))
        end
        if strsub(data, i + 3, i + 3) ~= "=" then
            table.insert(out, strchar(n % 256))
        end
    end

    return table.concat(out)
end

---------------------------------------------------------------------------
-- Table Serializer
-- Compact format: type-prefixed values
--   s<len>:<string>  n<number>;  T  F  {key val key val}
---------------------------------------------------------------------------

local function SerializeValue(val, parts, depth)
    depth = depth or 0
    if depth > MAX_DEPTH then return end
    local t = type(val)
    if t == "string" then
        parts[#parts + 1] = "s"
        parts[#parts + 1] = tostring(#val)
        parts[#parts + 1] = ":"
        parts[#parts + 1] = val
    elseif t == "number" then
        parts[#parts + 1] = "n"
        -- Use integer format when possible for compactness
        if val == floor(val) and val > -2^31 and val < 2^31 then
            parts[#parts + 1] = tostring(val)
        else
            parts[#parts + 1] = string.format("%.17g", val)
        end
        parts[#parts + 1] = ";"
    elseif t == "boolean" then
        parts[#parts + 1] = val and "T" or "F"
    elseif t == "table" then
        parts[#parts + 1] = "{"
        for k, v in pairs(val) do
            SerializeValue(k, parts, depth + 1)
            SerializeValue(v, parts, depth + 1)
        end
        parts[#parts + 1] = "}"
    end
    -- nil, function, userdata are silently skipped
end

local function SerializeTable(tbl)
    local parts = {}
    SerializeValue(tbl, parts)
    return table.concat(parts)
end

---------------------------------------------------------------------------
-- Table Deserializer
---------------------------------------------------------------------------

local function DeserializeValue(data, pos, depth)
    depth = depth or 0
    if depth > MAX_DEPTH then return nil, pos end
    local tag = strsub(data, pos, pos)

    if tag == "s" then
        -- String: s<len>:<content>
        local colonPos = strfind(data, ":", pos + 1, true)
        if not colonPos then return nil, pos end
        local len = tonumber(strsub(data, pos + 1, colonPos - 1))
        if not len then return nil, pos end
        local str = strsub(data, colonPos + 1, colonPos + len)
        return str, colonPos + len + 1

    elseif tag == "n" then
        -- Number: n<digits>;
        local semicolonPos = strfind(data, ";", pos + 1, true)
        if not semicolonPos then return nil, pos end
        local num = tonumber(strsub(data, pos + 1, semicolonPos - 1))
        return num, semicolonPos + 1

    elseif tag == "T" then
        return true, pos + 1

    elseif tag == "F" then
        return false, pos + 1

    elseif tag == "{" then
        local tbl = {}
        local i = pos + 1
        while i <= #data do
            if strsub(data, i, i) == "}" then
                return tbl, i + 1
            end
            local key, val
            key, i = DeserializeValue(data, i, depth + 1)
            if key == nil then return nil, i end
            val, i = DeserializeValue(data, i, depth + 1)
            tbl[key] = val
        end
        return tbl, i
    end

    return nil, pos + 1
end

local function DeserializeTable(data)
    if not data or #data == 0 then return nil end
    local result, _ = DeserializeValue(data, 1)
    return result
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function BazUI:Serialize(tbl)
    if type(tbl) ~= "table" then return nil end
    local raw = SerializeTable(tbl)
    return Base64Encode(raw)
end

function BazUI:Deserialize(encoded)
    if not encoded or #encoded == 0 then return nil end
    local raw = Base64Decode(encoded)
    if not raw or #raw == 0 then return nil end
    return DeserializeTable(raw)
end

-- Raw access if needed
BazUI.Base64Encode = Base64Encode
BazUI.Base64Decode = Base64Decode
