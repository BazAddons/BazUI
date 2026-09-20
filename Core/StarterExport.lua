-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: export the arrangement as a starter profile
--
-- Core/StarterProfile.lua is the layout a fresh install begins with. It has
-- been written by hand, which is fine for three bars and tedious for a real
-- arrangement - and on a client that will not read saved variables back, the
-- starter profile is the only thing anyone actually gets.
--
-- /baz export prints the active profile as Lua, shaped to paste straight
-- into StarterProfile.lua. Two things happen on the way out:
--
--   Positions are re-expressed against the nearest screen anchor. A frame
--   dragged to the bottom middle is saved as CENTER/BOTTOM with a small
--   offset rather than 1476 pixels from the bottom-left corner, so the
--   layout lands in the same place on a different monitor. This is the rule
--   StarterProfile's own header states; the export is where it is enforced.
--
--   Anything belonging to one character is dropped: bar payloads, keybinds,
--   warnings already shown, migration marks. A starter profile is a shape,
--   not somebody's save file.
---------------------------------------------------------------------------

-- Keys that never belong in a starter profile, dropped wherever they turn
-- up. A starter profile is a shape, not somebody's save file.
local PERSONAL = {
    keybinds = true,
    globalOverrides = true,
    keyDownWarningShown = true,
    _bbCharButtonsMigrated = true,
    buttons = true,
    minimap = true,

    -- Another addon's data, which we do not ship on principle. The order
    -- of the minimap buttons is a list of whatever happened to be
    -- installed - LibDBIcon10_BugSack and friends - and means nothing to
    -- anyone else.
    buttonOrder = true,

    -- Collected by playing, not by arranging. The Codex item index can run
    -- to thousands of rows, and a wish list is as personal as it gets.
    itemIndex = true,
    wishlist = true,

    -- What was said and what was typed. A chat window keeps its own
    -- scrollback and the box above it keeps every slash command that went
    -- through it, which is nine kilobytes of somebody's evening per
    -- window and nobody else's business. The header has always claimed
    -- chat history stays out; this is where that becomes true.
    history = true,
    typedHistory = true,

    -- Which thing happened to be open or folded shut when the export was
    -- taken. Not layout, just where the session had got to.
    collapsed = true,
    widgetCollapsed = true,
    sectionCollapsed = true,
    activeTab = true,
    activeDrawer = true,
}

-- The same idea where the key is not a fixed name but a shape. A broker
-- widget is created per LibDataBroker source that happens to be installed -
-- bazdrawer_ldb_BugSack - so these turn up as keys inside widgetEnabled and
-- its neighbours rather than as a table of their own. Nobody else has the
-- same addons, and we do not ship another addon's data.
local PERSONAL_PATTERNS = {
    "^bazdrawer_ldb_",
}

local function IsPersonal(key)
    if PERSONAL[key] then return true end
    for _, pattern in ipairs(PERSONAL_PATTERNS) do
        if key:find(pattern) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Positions
--
-- A saved position is point/relPoint/x/y against UIParent. When relPoint is
-- already a screen anchor the numbers are small and mean what they say; when
-- it is a corner with hundreds of pixels of offset - which is what grid
-- snapping produces - it is rewritten against whichever third of the screen
-- the frame actually sits in.
---------------------------------------------------------------------------

local function ScreenAnchor(x, y)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local vertical, horizontal

    if y < h / 3 then
        vertical = "BOTTOM"
    elseif y > h * 2 / 3 then
        vertical = "TOP"
    else
        vertical = ""
    end

    if x < w / 3 then
        horizontal = "LEFT"
    elseif x > w * 2 / 3 then
        horizontal = "RIGHT"
    else
        horizontal = ""
    end

    local anchor = vertical .. horizontal
    if anchor == "" then anchor = "CENTER" end
    return anchor
end

-- Where UIParent's own named points sit, so an absolute position can be
-- turned into an offset from the nearest one.
local function AnchorOrigin(anchor)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local x = (anchor:find("LEFT") and 0) or (anchor:find("RIGHT") and w) or w / 2
    local y = (anchor:find("BOTTOM") and 0) or (anchor:find("TOP") and h) or h / 2
    return x, y
end

local function Rounded(n)
    return math.floor(n * 10 + 0.5) / 10
end

-- SetPoint offsets are in the anchored frame's own units, not UIParent's,
-- so a bar at scale 0.7 that sits 384 points from the right edge stores
-- -548.6. Converting to a screen anchor means going out to UIParent's
-- space and back, and both trips have to carry the scale - without it the
-- anchor is chosen from the wrong arithmetic and the frame lands about a
-- seventh of the screen away from where it was left.
local function NormalisePosition(pos, scale)
    if type(pos) ~= "table" then return pos end
    scale = (type(scale) == "number" and scale > 0) and scale or 1

    local originX, originY, absX, absY

    if pos.relPoint then
        originX, originY = AnchorOrigin(pos.relPoint)
        absX = originX + (pos.x or 0) * scale
        absY = originY + (pos.y or 0) * scale
    elseif pos.x and pos.y then
        -- Edit Mode's other shape: the frame's centre as a screen-pixel
        -- offset from the centre of the screen, with no anchor at all.
        -- Left alone it would put a 4K arrangement three hundred pixels
        -- off the top of a smaller monitor, which is the whole reason
        -- this conversion exists.
        local ui = UIParent:GetEffectiveScale()
        absX = UIParent:GetWidth() / 2 + pos.x / ui
        absY = UIParent:GetHeight() / 2 + pos.y / ui
    else
        return pos
    end

    local anchor = ScreenAnchor(absX, absY)
    local newOriginX, newOriginY = AnchorOrigin(anchor)

    return {
        point    = pos.point or "CENTER",
        relPoint = anchor,
        x        = Rounded((absX - newOriginX) / scale),
        y        = Rounded((absY - newOriginY) / scale),
    }
end

---------------------------------------------------------------------------
-- Writing it out
---------------------------------------------------------------------------

-- `bellAnchor` is here because it is a position that is not called one.
-- Left out, the notification bell shipped as its raw offset from the
-- bottom-left corner of the screen it was arranged on - which on a 4K
-- monitor is over a thousand pixels up, and off the top of anything
-- smaller. A key is a position because of what it holds, not what it is
-- called.
local POSITION_KEYS = {
    pos = true, position = true, targetPosition = true, bellAnchor = true,
}

-- Keys whose every child is a position. A window remembers where it was
-- dragged under its own name, so there is no one key to list.
local POSITION_CONTAINERS = { windowPositions = true }

-- Of those, the ones whose offsets are in a scaled frame's own units.
--
-- Only a bar is scaled. A profile that has picked up a `scale` key from
-- somewhere else must not lend it to anything nested inside: UnitFrames
-- carried one that nothing read, and inheriting it divided every status
-- bar's offsets by 0.8 and put the target bars a fifth of the screen from
-- where they were left. A scale is only a scale where some frame is
-- actually wearing it.
local SCALED_POSITION_KEYS = { pos = true }

local function Indent(depth)
    return string.rep("    ", depth)
end

-- The scale that applies to a position is the one on the table holding it,
-- never one inherited from further up: a module's setting called "scale"
-- has nothing to do with whether the frame under it is scaled.
local function Write(value, out, depth, key, scale)
    local t = type(value)

    if t == "table" then
        if key and POSITION_KEYS[key] then
            value = NormalisePosition(value, SCALED_POSITION_KEYS[key] and scale or 1)
        elseif key and POSITION_CONTAINERS[key] then
            local fixed = {}
            for name, child in pairs(value) do
                fixed[name] = (type(child) == "table")
                    and NormalisePosition(child, 1) or child
            end
            value = fixed
        end

        -- For the children: this table's own scale, if it has one.
        scale = type(value.scale) == "number" and value.scale or 1

        -- An empty table on one line reads better than three.
        if next(value) == nil then
            out[#out + 1] = "{}"
            return
        end

        out[#out + 1] = "{\n"

        -- Array part first, in order, then the named keys sorted so two
        -- exports of the same layout come out identical.
        for i = 1, #value do
            out[#out + 1] = Indent(depth + 1)
            Write(value[i], out, depth + 1, nil, scale)
            out[#out + 1] = ",\n"
        end

        local names = {}
        for k in pairs(value) do
            if type(k) == "string" and not IsPersonal(k) then names[#names + 1] = k end
        end
        table.sort(names)

        for _, name in ipairs(names) do
            out[#out + 1] = Indent(depth + 1)
            out[#out + 1] = name:match("^[%a_][%w_]*$")
                and (name .. " = ")
                or ("[\"" .. name .. "\"] = ")
            Write(value[name], out, depth + 1, name, scale)
            out[#out + 1] = ",\n"
        end

        out[#out + 1] = Indent(depth) .. "}"
    elseif t == "string" then
        -- The backslash goes first, or the escapes added after it get
        -- escaped in turn.
        --
        -- This mattered more than it looks. Texture paths are full of
        -- backslashes - Interface\Icons\INV_Misc_Gear_01 - and Lua 5.1 does
        -- not complain about an escape it does not recognise, it silently
        -- drops the backslash and keeps the letter. An unescaped path is
        -- therefore not a syntax error anybody would notice; it loads as
        -- InterfaceIconsINV_Misc_Gear_01 and the icon quietly never appears.
        local escaped = value
            :gsub("\\", "\\\\")
            :gsub("\"", "\\\"")
            :gsub("\n", "\\n")
            :gsub("\r", "\\r")
        out[#out + 1] = "\"" .. escaped .. "\""
    elseif t == "number" then
        out[#out + 1] = tostring(Rounded(value))
    else
        out[#out + 1] = tostring(value)
    end
end

function BazUI:ExportStarterProfile()
    local sv = _G.BazUIDB
    local profileName = sv and sv.activeProfile
    local profile = sv and sv.profiles and sv.profiles[profileName]
    if not profile then
        BazUI:Print("|cffff4444No active profile to export.|r")
        return
    end

    local out = { "BazUI.StarterProfile = " }
    Write(profile, out, 0)
    out[#out + 1] = "\n"

    local text = table.concat(out)

    -- Stashed in the saved variables as well as shown. Writing works on
    -- this client even though reading does not, so the file on disk is a
    -- reliable way to hand a finished layout out of the game without
    -- anybody copying anything: run this, reload, and the text is in
    -- SavedVariables/BazUI.lua under starterExport - screen anchors and
    -- all, which is the part only the running client can work out.
    _G.BazUIDB = _G.BazUIDB or {}
    _G.BazUIDB.starterExport = text
    _G.BazUIDB.starterExportScreen = {
        width  = Rounded(UIParent:GetWidth()),
        height = Rounded(UIParent:GetHeight()),
        when   = date("%Y-%m-%d %H:%M:%S"),
    }
    BazUI:Print("Layout written to the saved variables. |cffffd700/reload|r puts it on disk.")

    BazUI:OpenCopyDialog({
        title    = "Starter profile",
        subtitle = "The '" .. tostring(profileName) .. "' profile as Lua, for Core/StarterProfile.lua.",
        content  = text,
        editable = true,
        width    = 700,
        height   = 560,
    })
end
