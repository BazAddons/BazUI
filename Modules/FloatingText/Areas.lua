-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Floating Text: the areas, and what rises through them
--
-- An area is a frame you place once and then forget: text is handed to it
-- and it decides where in itself that text starts, how it moves and when
-- it goes. Everything else in the module hands work to one of these.
--
-- The frame is empty. It has a size so Edit Mode has something to grab
-- and so text can be placed inside it, and it draws nothing of its own -
-- outside of Edit Mode, where it shows its bounds, because a region you
-- cannot see is a region you cannot place.
--
-- Strings are pooled and never destroyed. A busy fight makes a few dozen
-- a minute and a font string is not free to build; more to the point,
-- building one mid-fight is the kind of thing that is fine until the one
-- time it is not.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("FloatingText")
if not addon then return end

local Areas = {}
addon.Areas = Areas

local Theme = BazUI.Skin and BazUI.Skin.Theme

local frames = {}    -- [key] = the area frame
local queued = {}    -- [key] = numbers waiting their turn to appear
local nextFree = {}  -- [key] = the earliest time the next one may appear
local live = {}      -- every string currently rising, in no order
local pool = {}      -- strings waiting to be used again
local driver         -- the one OnUpdate that moves all of them

-- How wide an area is, and how tall.
--
-- Not settings. The width is what a big crit needs and the height is how
-- far text travels, which IS a setting - so the frame is sized from the
-- travel distance and stays honest about the space it uses when you are
-- placing it.
local AREA_WIDTH = 220

local function TravelDistance()
    return tonumber(addon:GetSetting("travel")) or 140
end

---------------------------------------------------------------------------
-- The strings
---------------------------------------------------------------------------

local function Acquire(area)
    local fs = table.remove(pool)
    if not fs then
        fs = area:CreateFontString(nil, "OVERLAY")
    else
        fs:SetParent(area)
    end
    fs:ClearAllPoints()
    fs:Show()
    return fs
end

local function Release(fs)
    fs:Hide()
    fs:SetText("")
    pool[#pool + 1] = fs
end

-- The face, at the size this one string wants.
--
-- SetFont rather than a font object, because the size is per string: a
-- crit is drawn larger than the hit beside it, and a font object would
-- mean one object per size per outline. Theme.FontFile is the suite's
-- face, so the numbers match everything else BazUI draws.
local function Dress(fs, size, outline)
    local file = Theme and Theme.FontFile and Theme.FontFile()
    if not file then
        -- No face to be had. GameFontNormal is not the right look but it
        -- is a look, and a number nobody can read is worse than one in
        -- the wrong font.
        fs:SetFontObject("GameFontNormalHuge")
        return
    end
    fs:SetFont(file, size, outline ~= "NONE" and outline or nil)
end

---------------------------------------------------------------------------
-- Movement
--
-- One OnUpdate for every string on screen rather than one each. The
-- driver runs only while something is rising and stops itself the moment
-- the last one has gone, so an idle fight costs nothing.
--
-- Linear travel, and the fade held back until the last stretch. Fading
-- from the start reads as "this is already over" on a number that has
-- only just appeared, which is exactly backwards for the biggest hit of
-- the fight.
---------------------------------------------------------------------------

local FADE_FROM = 0.6      -- of its life, before which it is fully opaque

-- Declared here because Step drains the queue through both of them, and
-- Step is written above where either is built. A local is only visible
-- to code written after it.
local Spawn, ReleaseGap

local function Step()
    local now = GetTime()
    local any = false

    -- Anything that had to wait, released as soon as there is room for it.
    for key, q in pairs(queued) do
        if #q > 0 then
            any = true
            if (nextFree[key] or 0) <= now then
                local item = table.remove(q, 1)
                nextFree[key] = now + ReleaseGap(item.size)
                Spawn(key, item.text, item.color, item.size, item.outline)
            end
        end
    end

    for i = #live, 1, -1 do
        local item = live[i]
        local elapsed = now - item.born
        local progress = elapsed / item.duration

        if progress >= 1 then
            Release(item.fs)
            table.remove(live, i)
        else
            any = true
            local rise = item.travel * progress * item.sign
            item.fs:SetPoint("CENTER", item.area, "BOTTOM", item.drift, rise)

            if progress > FADE_FROM then
                local left = (1 - progress) / (1 - FADE_FROM)
                item.fs:SetAlpha(left)
            else
                item.fs:SetAlpha(1)
            end
        end
    end

    if not any and driver then driver:Hide() end
end

local function Driving()
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", Step)
    end
    driver:Show()
end

---------------------------------------------------------------------------
-- The areas themselves
---------------------------------------------------------------------------

local function Build(def)
    if frames[def.key] then return frames[def.key] end

    local f = CreateFrame("Frame", "BazUIFloatingText" .. def.key, UIParent)
    f:SetSize(AREA_WIDTH, TravelDistance())
    f:SetFrameStrata("HIGH")

    -- Visible only while arranging. An area is a space, not a panel, so
    -- the rest of the time there is nothing to see but the numbers.
    f.bounds = f:CreateTexture(nil, "BACKGROUND")
    f.bounds:SetAllPoints()
    f.bounds:SetColorTexture(1, 1, 1, 0.07)
    f.bounds:Hide()

    f.label = Theme and Theme.FontString and Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    if f.label then
        f.label:SetPoint("TOP", f, "TOP", 0, -4)
        f.label:SetText(def.label)
        f.label:Hide()
    end

    frames[def.key] = f

    if BazUI.RegisterEditModeFrame then
        BazUI:RegisterEditModeFrame(f, {
            label       = "Floating Text: " .. def.label,
            addonName   = "FloatingText",
            positionKey = "pos_" .. def.key,
            actions = {
                {
                    label = "Reset position",
                    callback = function()
                        addon:SetSetting("pos_" .. def.key, nil)
                        Areas:Place(def)
                    end,
                },
            },
        })
    end

    return f
end

-- Where it sits.
--
-- Saved figures are screen pixels - Edit Mode's SavePosition multiplies
-- the frame's centre offset by its effective scale - and SetPoint takes
-- the frame's own coordinate space, so the saved number is only correct
-- when that scale is 1. On a 4K screen with UI Scale off it is well
-- under. Dividing undoes it, the same as everywhere else that reads one
-- of these back.
function Areas:Place(def)
    local f = frames[def.key]
    if not f then return end

    local saved = addon:GetSetting("pos_" .. def.key)
    local x, y = def.x, def.y
    if type(saved) == "table" and saved.x and saved.y then
        local scale = f:GetEffectiveScale()
        if not scale or scale == 0 then scale = 1 end
        x, y = saved.x / scale, saved.y / scale
    end

    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function Areas:Initialize()
    for _, def in ipairs(addon.AREAS) do
        Build(def)
    end
    -- Placed once the saved variables are real. Reading a position before
    -- Persist has adopted them gets the default every time, and the area
    -- appears to move on every reload while in fact never having been
    -- restored once.
    BazUI:QueueForVariables(function() Areas:ApplyAll() end)
end

function Areas:ApplyAll()
    local on = addon:GetSetting("enabled") == true
    local editing = BazUI.IsEditMode and BazUI:IsEditMode()
    local travel = TravelDistance()

    for _, def in ipairs(addon.AREAS) do
        local f = frames[def.key]
        if f then
            f:SetSize(AREA_WIDTH, travel)
            self:Place(def)
            f:SetShown(on)
            if f.bounds then f.bounds:SetShown(on and editing) end
            if f.label then f.label:SetShown(on and editing) end
        end
    end
end

function Areas:Frame(key)
    return frames[key]
end

---------------------------------------------------------------------------
-- Letting them through one at a time
--
-- Three hits landing in the same instant used to be drawn in the same
-- instant, and since every number rises at the same speed from the same
-- line they then stayed exactly parallel for their whole life. What you
-- read was 1414iss: two fourteens and a miss, on top of each other,
-- forever.
--
-- Scattering them sideways cannot fix that - the text is wider than any
-- sane amount of drift, and a number thrown far enough sideways to clear
-- its neighbour no longer looks like it belongs to the fight.
--
-- So they are spaced in TIME instead, and the rise does the separating.
-- The gap is worked out from the numbers themselves rather than picked:
-- at travel/duration pixels a second, waiting one line height puts the
-- next number exactly one line above the last. Change the size, the
-- speed or the distance and the spacing still comes out right.
---------------------------------------------------------------------------

-- A ceiling, so an AoE pull does not queue up numbers that arrive long
-- after the thing that caused them. Past this the oldest waiting ones are
-- dropped: late is worse than missing.
local QUEUE_CAP = 12

function ReleaseGap(size)
    local duration = tonumber(addon:GetSetting("duration")) or 1.8
    local travel = TravelDistance()
    if travel <= 0 or duration <= 0 then return 0.1 end
    local perSecond = travel / duration
    -- A little over one line, so they clear rather than touch.
    return (size * 1.15) / perSecond
end

---------------------------------------------------------------------------
-- Putting something on the screen
--
-- text is already formatted, because what a number should read as is the
-- event's business rather than the area's. Everything here is about where
-- it starts and how it leaves.
---------------------------------------------------------------------------

function Spawn(key, text, color, size, outline)
    local area = frames[key]
    if not area then return end

    local fs = Acquire(area)
    Dress(fs, size or 22, outline or "OUTLINE")
    fs:SetText(text)
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    fs:SetAlpha(1)

    -- Nudged apart, not scattered.
    --
    -- Two numbers landing in the same instant have to not be drawn on
    -- top of each other, and the first version answered that by putting
    -- every number anywhere across the full width of the area. That
    -- reads as numbers arriving from nowhere in particular - there is no
    -- line to follow, so nothing looks like it belongs to anything.
    --
    -- A small nudge either side of the middle keeps the column readable
    -- and still separates a simultaneous pair. Zero is allowed, and
    -- means a single hard column.
    local spread = tonumber(addon:GetSetting("scatter")) or 30
    local drift = (spread > 0) and math.random(-spread, spread) or 0

    live[#live + 1] = {
        fs       = fs,
        area     = area,
        born     = GetTime(),
        duration = tonumber(addon:GetSetting("duration")) or 1.8,
        travel   = TravelDistance(),
        drift    = drift,
        sign     = 1,
    }
    fs:SetPoint("CENTER", area, "BOTTOM", drift, 0)
    Driving()
end

-- Straight through if the last one has had time to get out of the way,
-- otherwise it waits its turn. Step drains the queue.
function Areas:Show(key, text, color, size, outline)
    local area = frames[key]
    if not (area and area:IsShown() and text and text ~= "") then return end

    size = size or 22
    local now = GetTime()
    if (nextFree[key] or 0) <= now then
        nextFree[key] = now + ReleaseGap(size)
        Spawn(key, text, color, size, outline)
        return
    end

    local q = queued[key]
    if not q then q = {}; queued[key] = q end
    q[#q + 1] = { text = text, color = color, size = size, outline = outline }
    while #q > QUEUE_CAP do table.remove(q, 1) end
    Driving()
end

-- Everything on screen, gone. For turning the module off, and for a
-- profile switch, where leaving somebody else's numbers rising would be
-- the module's last word on the subject.
function Areas:Clear()
    for i = #live, 1, -1 do
        Release(live[i].fs)
        live[i] = nil
    end
    wipe(queued)
    wipe(nextFree)
    if driver then driver:Hide() end
end
