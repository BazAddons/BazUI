-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazChat Replica: Chrome (NineSlice frame chrome)
--
-- Wraps each chat window in a sibling NineSlice frame so the visible
-- gold-bordered chrome sits OUTSIDE the chat's text-rendering area
-- (the chat would otherwise touch the border and clip mid-word at
-- the right edge for long lines). Uses the CharacterCreateDropdown
-- layout, which gives the modern dark/gold panel look.
--
-- :ApplyDefault(f) hides the inherited FloatingBorderedFrame textures
-- so they don't compete with our chrome. :Apply(f) builds the wrapper
-- (lazily, once per frame) and applies the NineSlice layout to it.
--
-- Public API (on addon.Chrome):
--   :ApplyDefault(f)    -- hide the FloatingBorderedFrame textures
--   :Apply(f)           -- build/refresh the NineSlice wrapper for f
---------------------------------------------------------------------------

local addon   = BazUI.Chat            -- Chat's private namespace

local Chrome = {}
addon.Chrome = Chrome

-- The single layout we ship. Previous builds had a /bc nine slash
-- command that cycled through every NineSliceLayout for previewing;
-- that's gone. CharacterCreateDropdown is what we settled on.
local LAYOUT = "CharacterCreateDropdown"

-- Insets between the chat's bounds and the chrome wrapper's bounds.
-- Chrome extends OUTWARD this many pixels on each side, so chat text
-- (rendered to the chat's full bounds) ends up with this much padding
-- inside the visible gold border. Top is smaller than bottom: that
-- pushes text UP within the chrome, which reads as centered to the eye
-- (symmetric 20/20 felt bottom-heavy in testing). Right is wider so
-- the scrollbar sits in its own column outside the text area.
local INSET_LEFT   = 10
local INSET_RIGHT  = 26
local INSET_TOP    = 11
local INSET_BOTTOM = 29

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
-- :Apply — wrap f in the NineSlice chrome (lazy-create, then refresh).
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

    if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
        pcall(NineSliceUtil.ApplyLayoutByName, f._bcChromeFrame, LAYOUT)
    end
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
