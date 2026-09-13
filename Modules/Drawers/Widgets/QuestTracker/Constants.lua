-- SPDX-License-Identifier: GPL-2.0-or-later
-- QuestTracker: Constants & Color Helpers
-- Shared layout constants, font references, and Blizzard color lookups.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

-- Create the shared QuestTracker namespace
addon.QT = addon.QT or {}
local QT = addon.QT

-- Constants sub-table
local C = {}
QT.C = C

-- Identity
C.WIDGET_ID    = "bazdrawer_questtracker"

-- Layout
C.DESIGN_WIDTH       = 260
C.MAX_HEIGHT_DEFAULT = 400
C.PAD                = 8
C.BLOCK_SPACING      = 10
C.HEADER_AFTER_GAP   = 8
-- Was 18, which combined with the previous block's BLOCK_SPACING
-- (10) gave a 28 px gap between e.g. a scenario's last bullet and
-- the "Quests" header below it - visibly larger than Blizzard's
-- tracker. 4 brings the total gap down to ~14 px which matches the
-- default closely.
C.GROUP_GAP          = 4
C.TITLE_HEIGHT       = 18
C.OBJ_INDENT         = 14
C.OBJ_LINE_GAP       = 2
C.OBJ_RIGHT_PAD      = 10
C.POI_SIZE           = 20
C.POI_GAP            = 8
C.SCENARIO_OBJ_GAP       = 6
-- Used to be 10, which left a noticeably larger gap below the stage
-- box than Blizzard's tracker. 4 keeps a bit of breathing room without
-- the "this objective is floating" feel.
C.SCENARIO_OBJ_LINE_GAP  = 4
C.NUB_SIZE           = 14
C.NUB_TEXT_GAP       = 5

-- Special-item button (the clickable usable item icon on a quest).
--
--   TEMPLATE_SIZE   QuestObjectiveItemButtonTemplate's natural size
--                   (button + chrome textures are baked at this).
--   SIZE            visible edge length in px after scaling. Matches
--                   TITLE_HEIGHT so the whole button fits inside the
--                   title row without dipping into the description.
--   RIGHT_PAD       inset from the block's right edge so the icon
--                   doesn't sit flush against the chrome.
--   TEXT_GAP        horizontal breathing room between the icon's left
--                   edge and the title / first-objective text.
C.SPECIAL_ITEM_TEMPLATE_SIZE = 26
C.SPECIAL_ITEM_SIZE          = C.TITLE_HEIGHT
C.SPECIAL_ITEM_RIGHT_PAD     = 4
C.SPECIAL_ITEM_TEXT_GAP      = 6
C.HEADER_HEIGHT      = 32
C.TOP_HEADER_HEIGHT  = 32
C.MIN_HEIGHT         = C.PAD * 2 + C.TOP_HEADER_HEIGHT

-- Blizzard widget set IDs (from Blizzard_ScenarioObjectiveTracker.lua)
C.SCENARIO_TRACKER_WIDGET_SET     = 252
C.SCENARIO_TRACKER_TOP_WIDGET_SET = 514

-- Fonts
C.TITLE_FONT     = "ObjectiveTrackerHeaderFont"
C.OBJECTIVE_FONT = "ObjectiveTrackerLineFont"

---------------------------------------------------------------------------
-- Color helpers - read Blizzard's OBJECTIVE_TRACKER_COLOR table with
-- fallback values so the tracker works even if the table isn't loaded.
---------------------------------------------------------------------------

function QT.BlizzColor(key, fallbackR, fallbackG, fallbackB)
    local c = _G.OBJECTIVE_TRACKER_COLOR and _G.OBJECTIVE_TRACKER_COLOR[key]
    if c then return c.r, c.g, c.b end
    return fallbackR, fallbackG, fallbackB
end

function QT.GetTitleColor()      return QT.BlizzColor("Header",          1.00, 0.82, 0.00) end
function QT.GetTitleHiColor()    return QT.BlizzColor("HeaderHighlight", 1.00, 1.00, 1.00) end
function QT.GetObjectiveColor()  return QT.BlizzColor("Normal",          0.80, 0.80, 0.80) end
function QT.GetObjectiveDone()   return QT.BlizzColor("Complete",        0.60, 0.60, 0.60) end

---------------------------------------------------------------------------
-- FitStringToWidth - shrink a FontString just enough to fit one line.
--
-- Blizzard's tracker has plenty of room to render long titles like
-- "The Legend of Wey'nan's Ward" on a single line. Our drawer is a
-- 260 px column, so the same text wraps to two lines and looks
-- cramped. Calling this on a FontString first resets its scale to
-- 1.0, measures the natural width, then shrinks the scale (down to a
-- readable floor) so the whole string fits on one line.
--
-- The caller is responsible for SetWordWrap(false) on the FontString
-- - without that, scaling fights the text engine's wrap logic.
--
-- Args:
--   fs        FontString to fit (no-op if nil)
--   maxWidth  pixels available for the rendered text
--   minScale  optional floor (default 0.65 - below this gets unreadable)
---------------------------------------------------------------------------

function QT.FitStringToWidth(fs, _maxWidth, minScale)
    if not fs then return end

    local floor = minScale or 0.55

    -- Mirrors Blizzard's AutoScalingFontStringMixin:ScaleTextToFit
    -- (Blizzard_SharedXML/SecureUtil.lua). The previous implementation
    -- used GetStringWidth, but on a FontString constrained by LEFT+RIGHT
    -- anchors GetStringWidth returns the *constrained* width, so the
    -- "w > maxWidth" branch never fired and the text just truncated.
    -- IsTruncated reports the visible state directly: true when the
    -- text is being clipped/elided at the current scale, false when it
    -- fits - exactly the signal we want to drive a shrink loop.
    local function tryFit()
        fs:SetTextScale(1.0)
        if not fs:IsTruncated() then return end
        local scale = 1.0
        while fs:IsTruncated() and scale > floor + 0.001 do
            scale = math.max(scale - 0.05, floor)
            fs:SetTextScale(scale)
        end
    end

    tryFit()
    -- Retry next frame: pooled FontStrings occasionally report
    -- IsTruncated() = false on the first call after SetText (the
    -- text engine hasn't measured the new string yet), then truncate
    -- on the next frame anyway. Re-running once after a frame settle
    -- catches that case.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, tryFit)
    end
end
