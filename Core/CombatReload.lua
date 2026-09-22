-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: reloading in the middle of a fight
--
-- Almost everything this addon does to the interface is refused during
-- combat. Frames the game protects cannot be moved, reparented, shown or
-- hidden; the widget host will not run a layout; secure buttons cannot be
-- built. So a /reload while something is hitting you comes back up as a
-- half-arranged interface: Blizzard's minimap in its own corner, their
-- action bars visible, widgets wherever they were left.
--
-- All of that sorts itself out the moment the fight ends - every piece of
-- it is parked and replayed on PLAYER_REGEN_ENABLED. The problem is the
-- thirty seconds in between, which look exactly like the addon having
-- broken, and a player whose interface appears to have fallen apart mid
-- fight is not in a position to go reading documentation about it.
--
-- So: say so. A small notice, out of the way, that leaves when the reason
-- for it leaves.
--
-- It is built only if it is ever needed. A player who never reloads mid
-- fight never pays for this file beyond one event registration.
---------------------------------------------------------------------------

local notice

local function Build()
    if notice then return notice end

    local Theme = BazUI.Skin and BazUI.Skin.Theme
    if not Theme then return nil end

    local f = CreateFrame("Frame", "BazUICombatReloadNotice", UIParent)
    f:SetSize(260, 1)

    -- Left, and a third of the way down: out of the way of the middle of
    -- the screen, which is where the fight is, and clear of the chat frame
    -- in the bottom left, which is where the player will look next.
    f:SetPoint("LEFT", UIParent, "LEFT", 24, 80)

    -- Above everything. The whole point is to be readable on top of an
    -- interface that is currently in the wrong places.
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)

    Theme.ApplyFlatPanel(f, { 0.06, 0.05, 0.04, 0.94 }, Theme.colors.gold)

    f.title = Theme.FontString(f, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -11)
    f.title:SetPoint("TOPRIGHT", -12, -11)
    f.title:SetJustifyH("LEFT")
    f.title:SetTextColor(unpack(Theme.colors.gold))
    f.title:SetText("Reloaded during combat")

    f.body = Theme.FontString(f, "OVERLAY", "GameFontHighlightSmall")
    f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -7)
    f.body:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.body:SetJustifyH("LEFT")
    f.body:SetTextColor(unpack(Theme.colors.text))
    f.body:SetText("The game will not let an addon move, hide or build most "
        .. "of the interface while you are fighting, so some of it is "
        .. "sitting where the game left it.\n\nNothing is wrong and there "
        .. "is nothing to fix - it arranges itself the moment combat ends.")

    f.hint = Theme.FontString(f, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -8)
    f.hint:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.hint:SetJustifyH("LEFT")
    f.hint:SetText("Click to dismiss.")

    -- Sized to its words rather than to a guess, so a change of font or a
    -- translation cannot crop the last line.
    f:SetHeight(11 + f.title:GetStringHeight() + 7 + f.body:GetStringHeight()
        + 8 + f.hint:GetStringHeight() + 12)

    f:EnableMouse(true)
    f:SetScript("OnMouseUp", function(self) self:Hide() end)

    notice = f
    return f
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")

        -- Asked twice, a second apart.
        --
        -- PLAYER_LOGIN was the obvious place and the wrong one: the
        -- client has not necessarily worked out that you are in a fight
        -- by then, so InCombatLockdown answers no and the notice never
        -- appears - on precisely the reload it exists for. Entering the
        -- world is later, and a second after that is later still.
        local function Consider()
            if not InCombatLockdown() then return end
            if notice and notice:IsShown() then return end

            local f = Build()
            if not f then return end
            f:Show()

            -- Added only now. Leaving the fight is the end of the reason
            -- for the notice, so it is also the end of the notice.
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        end

        Consider()
        C_Timer.After(1, Consider)
        return
    end

    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if not notice then return end

    -- A moment after the fight, not the instant it ends: everything that
    -- was parked replays on this same event, and the notice should be the
    -- last thing to go rather than leaving while the interface is still
    -- visibly rearranging itself behind it.
    C_Timer.After(1, function()
        if notice and not InCombatLockdown() then notice:Hide() end
    end)
end)
