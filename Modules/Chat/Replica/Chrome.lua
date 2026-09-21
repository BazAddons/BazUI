-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: Chrome
--
-- Wraps each chat window in a sibling frame so the visible
-- gold-bordered chrome sits OUTSIDE the chat's text-rendering area
-- (the chat would otherwise touch the border and clip mid-word at
-- the right edge for long lines). Uses the CharacterCreateDropdown
-- layout, which gives the modern dark/gold panel look.
--
-- :ApplyDefault(f) hides the inherited FloatingBorderedFrame textures
-- so they don't compete with our chrome. :Apply(f) builds the wrapper
-- (lazily, once per frame) and draws the suite's border on it.
--
-- Public API (on addon.Chrome):
--   :ApplyDefault(f)    -- hide the FloatingBorderedFrame textures
--   :Apply(f)           -- build/refresh the chrome wrapper for f
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

local Chrome = {}
addon.Chrome = Chrome

-- The chrome is drawn from the suite's own border recipe rather than
-- from a picture.
--
-- It used to wear Blizzard's CharacterCreateDropdown nine-slice, which
-- looked the part but made the chat the one big frame in the addon that
-- ignored the Skin page: change a border band or a color and every bar,
-- panel, nameplate and popup followed while the chat sat there in
-- somebody else's gold. ApplyDialog is what our popups are drawn with,
-- and it registers for redraws, so the chat follows a skin change
-- without a reload like everything else.

-- Insets between the chat's bounds and the chrome wrapper's bounds.
-- Chrome extends OUTWARD this many pixels on each side, so chat text
-- (rendered to the chat's full bounds) ends up with this much padding
-- inside the visible border. Right is wider so the scrollbar sits in its
-- own column outside the text area.
--
-- The bottom used to be 29, which was room for the thick decorated edge
-- the old nine-slice art drew there. The border is four pixels of flat
-- band now, so that inset was leaving a hand's width of empty panel
-- below the resize grip with nothing in it.
local INSET_LEFT   = 10
local INSET_RIGHT  = 26
local INSET_TOP    = 11
local INSET_BOTTOM = 12

-- Published because the tab strip lines its left edge up with the
-- window's, and a number copied over there would drift the first time
-- one of these changed.
Chrome.INSET_LEFT   = INSET_LEFT
Chrome.INSET_RIGHT  = INSET_RIGHT
Chrome.INSET_TOP    = INSET_TOP
Chrome.INSET_BOTTOM = INSET_BOTTOM

---------------------------------------------------------------------------
-- :ApplyDefault — hide the inherited FloatingBorderedFrame textures.
--
-- They render solid white by default since the XML doesn't apply any
-- color/alpha. Setting alpha 0 (rather than :Hide()) keeps them in
-- the render tree so any Blizzard-internal Show on a piece doesn't
-- bring the white plate back.
---------------------------------------------------------------------------

local CHAT_FRAME_BACKGROUND_TEXTURES = {
    "Background",
    "TopLeftTexture", "TopRightTexture",
    "BottomLeftTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture",
    "TopTexture", "BottomTexture",
}

function Chrome:ApplyDefault(frame)
    local name = frame:GetName()
    if not name then return end
    for _, suffix in ipairs(CHAT_FRAME_BACKGROUND_TEXTURES) do
        local tex = _G[name .. suffix]
        if tex then tex:SetAlpha(0) end
    end
end

---------------------------------------------------------------------------
-- :Apply — wrap f in the chrome wrapper (lazy-create, then refresh).
---------------------------------------------------------------------------

function Chrome:Apply(f)
    if not f._bcChromeFrame then
        local chrome = CreateFrame("Frame", nil, UIParent)
        chrome:SetPoint("TOPLEFT",     f, "TOPLEFT",     -INSET_LEFT,  INSET_TOP)
        chrome:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  INSET_RIGHT, -INSET_BOTTOM)
        chrome:SetFrameStrata(f:GetFrameStrata())
        chrome:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 5) - 1))
        f:HookScript("OnShow", function() chrome:Show() end)
        f:HookScript("OnHide", function() chrome:Hide() end)
        chrome:SetShown(f:IsShown())
        f._bcChromeFrame = chrome
    end

    BazUI.Skin.Theme.ApplyDialog(f._bcChromeFrame)
end

---------------------------------------------------------------------------
-- :SetAlpha — fade just the chrome panel (independent of chat text).
--
-- The chrome wrapper is a UIParent sibling of f, NOT a child, so
-- f:SetAlpha doesn't cascade into it. This lets the user tune the
-- background panel's prominence independently of the foreground
-- (chat text + scrollbar) which is what f's own alpha controls.
---------------------------------------------------------------------------

function Chrome:SetAlpha(f, alpha)
    if f and f._bcChromeFrame then
        f._bcChromeFrame:SetAlpha(alpha or 1)
    end
end
