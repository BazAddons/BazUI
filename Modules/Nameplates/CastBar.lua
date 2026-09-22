-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Nameplates: the cast bar
--
-- What the mob is casting, and - the point of the thing - whether you can
-- do anything about it right now.
--
-- Three states, in one colour:
--
--   green   interruptible, and your interrupt is off cooldown. Go.
--   amber   interruptible, but your interrupt is not ready. Not yet.
--   red     not interruptible. Never.
--
-- The awkward part is that those three facts belong to two different
-- owners. Whether YOUR kick is ready is ours and perfectly readable.
-- Whether the cast can be interrupted is the client's, and it is secret:
--
--   SecretWhenUnitSpellCastRestricted - produce secret values if the unit
--   being queried is not the player or their pet.
--
-- So `if notInterruptible then` is refused, and no amount of care with the
-- comparison helps, because the value may not be compared at all.
--
-- The way through is not to compare it. There is a family of setters that
-- ACCEPT a secret and do the branching inside the engine, and
-- SetVertexColorFromBoolean is the one that matters here:
--
--   fill:SetVertexColorFromBoolean(notInterruptible, ifTrue, ifFalse)
--
-- We never learn which colour was used. We only choose the PAIR, and that
-- is where our own half goes: with the interrupt ready we hand it red and
-- green, and with it on cooldown we hand it red and amber. Three states,
-- one bar, and nothing read. See [[forever-secret-safe-setters]].
--
-- The timings are secret too, and go the same way: SetMinMaxValues takes
-- the cast's own start and end, and SetValue is given an ordinary clock
-- reading. The engine works out the fraction. We never hold a duration,
-- so a cast bar is drawn for a cast we are not allowed to know about.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("Nameplates")
if not addon then return end

local CastBar = {}
addon.CastBar = CastBar

local function Setting(key) return addon:GetSetting(key) end

---------------------------------------------------------------------------
-- Your interrupt, and the colours that follow from it
--
-- Both live in Core/Interrupt.lua, because the dockable target cast bar
-- asks the same questions and two copies would be two copies that drift -
-- one of them learning about a class's interrupt and the other not. This
-- file only says which colours to use.
---------------------------------------------------------------------------

local function Colors()
    return {
        never = Setting("castColorNever"),
        now   = Setting("castColorNow"),
        wait  = Setting("castColorWait"),
        none  = Setting("castColorNone"),
    }
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------

function CastBar.Build(plate)
    if plate.cast then return plate.cast end

    -- The suite's bar, like every other bar in the addon.
    --
    -- The first version was a bare StatusBar, on the reasoning that this
    -- one is driven by values we may not look at and a wrapper of ours
    -- might do arithmetic on the way past. That was wrong twice: it wore
    -- Blizzard's plain texture instead of the skin, and it would not have
    -- followed a skin change either.
    --
    -- The wrapper is only in the way if you go through it. Its inner
    -- StatusBar is bar.fill, and the secret-taking setters are called on
    -- that directly - so the chrome, the border and the fill art are the
    -- suite's, and the values still never pass through our hands.
    local bar = BazUI.CreateStatusBar(nil, plate, {
        height   = tonumber(Setting("castHeight")) or 6,
        width    = tonumber(Setting("width")) or 110,
        textMode = "always",
        spark    = false,
    })
    bar:SetFrameLevel((plate:GetFrameLevel() or 1) + 2)
    bar:Hide()

    plate.cast = bar
    return bar
end

-- Everything the bar needs, none of which we are allowed to read.
local function Fill(bar, unit)
    local name, _, _, startMs, endMs, _, _, notInterruptible = UnitCastingInfo(unit)
    local channel = false
    if name == nil then
        name, _, _, startMs, endMs, _, notInterruptible = UnitChannelInfo(unit)
        channel = true
    end
    if name == nil then return false end

    -- On the inner bar, not the wrapper. SetMinMaxValues takes the secret
    -- times; the value is an ordinary clock reading of ours, and the
    -- engine works out where between them that falls. So the bar fills
    -- correctly for a cast whose length we never learn.
    bar.fill:SetMinMaxValues(startMs, endMs)
    bar.fill:SetValue(GetTime() * 1000)
    bar.channel = channel

    -- SetFormattedText, not SetText. The plain one refuses a secret; this
    -- one is declared to take one and marks the string's Text aspect
    -- secret, so the engine draws a name we are not shown. The suite's
    -- bar already has this, and it picks the right face on the way.
    if Setting("castSpellName") ~= false then
        bar:SetFormattedText("%s", name)
    else
        bar:SetText("")
    end

    -- The interrupt colour goes on the fill's own texture. Set after the
    -- value, because RefreshFill puts the skin's colour back whenever the
    -- skin changes and this has to be the last word.
    BazUI.Interrupt.PaintFill(bar.fill, notInterruptible, Colors())

    return true
end

-- Kept in step with the setting, which is where the player edits it.
function CastBar.SyncOverride()
    BazUI.Interrupt.SetOverride(Setting("interruptSpell"))
end

function CastBar.Update(plate)
    local bar = plate and plate.cast
    local unit = plate and plate.unit
    if not bar then return end

    if not (unit and Setting("castBar") ~= false and addon:UnitWants(unit, "showPlate")) then
        bar:Hide()
        return
    end

    if Fill(bar, unit) then
        bar:Show()
    else
        bar:Hide()
    end
end

-- Driven while anything is casting. One ticker for every plate rather
-- than one each, and it stops itself when nothing is casting.
local ticker

local function Tick()
    local any = false
    for _, plate in pairs(addon.Plates:Active()) do
        local bar = plate.cast
        if bar and bar:IsShown() then
            any = true
            bar.fill:SetValue(GetTime() * 1000)
        end
    end
    if not any and ticker then ticker:Hide() end
end

function CastBar.Driving()
    if not ticker then
        ticker = CreateFrame("Frame")
        ticker:SetScript("OnUpdate", Tick)
    end
    ticker:Show()
end

---------------------------------------------------------------------------
-- Where it sits, and how big
---------------------------------------------------------------------------

function CastBar.Layout(plate)
    local bar = plate and plate.cast
    if not bar then return end

    -- Sized the way every other bar in the suite is: what is set is the
    -- fill, and the border is added around it. So a cast bar set to six
    -- pixels is six pixels of bar, the same as a health bar set to six.
    local width = tonumber(Setting("width")) or 110
    local height = tonumber(Setting("castHeight")) or 6
    bar:SetBarSize(width, height)

    bar:ClearAllPoints()
    bar:SetPoint("TOP", plate.health, "BOTTOM", 0, -2)
    -- Through SetTextStyle, which is how every bar in the suite sets its
    -- writing: the size, the outline and the alignment arrive together
    -- and the theme picks the face.
    bar:SetTextStyle({
        size    = tonumber(Setting("castTextSize")) or 8,
        outline = "THIN",
        align   = "CENTER",
    })
end
