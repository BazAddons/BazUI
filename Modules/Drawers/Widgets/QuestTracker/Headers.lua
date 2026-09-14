-- SPDX-License-Identifier: GPL-2.0-or-later
-- QuestTracker: Section Headers
-- Creates and pools the collapsible group headers (Campaign, Quests,
-- Achievements, Dungeon, etc.) with Blizzard's ornamental atlas.

local addon = BazUI:GetModule("Drawers")
if not addon then return end
local QT = addon.QT
local C  = QT.C

---------------------------------------------------------------------------
-- Section header with Blizzard's secondary objective header atlas,
-- collapse/expand chevron, and click-to-toggle.
---------------------------------------------------------------------------

function QT.CreateSectionHeader()
    local f = CreateFrame("Button", nil, QT.scrollChild or QT.frame)
    f:SetHeight(C.HEADER_HEIGHT)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAtlas("UI-QuestTracker-Secondary-Objective-Header", true)
    f.bg:SetPoint("CENTER", f, "CENTER", 0, 0)

    f.chevron = f:CreateTexture(nil, "OVERLAY")
    f.chevron:SetSize(16, 16)
    f.chevron:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    f.chevron:SetAtlas("ui-questtrackerbutton-secondary-collapse")

    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFontObject(BazUI.Skin.Theme.FontObject(C.TITLE_FONT)
        or BazUI.Skin.Theme.FontObject("GameFontNormal"))
    f.text:SetPoint("LEFT", f, "LEFT", 10, 0)
    f.text:SetPoint("RIGHT", f.chevron, "LEFT", -6, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetTextColor(QT.GetTitleColor())
    -- The drawer is too narrow for storyline headers like
    -- "The Legend of Wey'nan's Ward" to fit at full size, and
    -- wrapping looked cramped. Disable wrap and let
    -- AcquireHeader call FitStringToWidth instead.
    f.text:SetWordWrap(false)

    f:RegisterForClicks("LeftButtonUp")
    f:SetScript("OnClick", function(self)
        local label = self._label
        if not label then return end
        QT.SetGroupCollapsed(label, not QT.IsGroupCollapsed(label))
        QT.Refresh()
    end)
    f:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(1.2, 1.2, 1.2, 1)
    end)
    f:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(1, 1, 1, 1)
    end)

    return f
end

function QT.AcquireHeader(label)
    local h = table.remove(QT.headerPool)
    if not h then h = QT.CreateSectionHeader() end
    h._label = label
    h.text:SetText(label or "")
    -- Available text width inside the header row:
    --   total row width = DESIGN_WIDTH - PAD*2 (set by the layout)
    --   internal padding = 10 left + 6 text-to-chevron gap +
    --                      16 chevron + 8 right pad = 40
    QT.FitStringToWidth(h.text, (C.DESIGN_WIDTH - C.PAD * 2) - 40, 0.65)
    h.chevron:SetAtlas(QT.IsGroupCollapsed(label)
        and "ui-questtrackerbutton-secondary-expand"
        or  "ui-questtrackerbutton-secondary-collapse")
    h:Show()
    return h
end

function QT.ReleaseHeader(h)
    h:Hide()
    h:ClearAllPoints()
    table.insert(QT.headerPool, h)
end
