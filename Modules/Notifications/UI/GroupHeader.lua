-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications
local BNC = addon.API

local Colors = addon.Colors
local HEADER_HEIGHT = 24
local HEADER_PADDING = 8

local function CreateGroupHeader(index)
    local header = CreateFrame("Frame", "BazUINotifGroupHeader" .. index, UIParent)
    header:SetSize(addon.CARD_WIDTH, HEADER_HEIGHT)
    header:Hide()

    -- Module icon
    header.icon = header:CreateTexture(nil, "ARTWORK")
    header.icon:SetSize(14, 14)
    header.icon:SetPoint("LEFT", header, "LEFT", HEADER_PADDING, 0)
    header.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Module name
    header.label = header:CreateFontString(nil, "OVERLAY")
    header.label:SetFontObject(GameFontNormalSmall)
    header.label:SetTextColor(unpack(Colors.groupHeader))
    header.label:SetJustifyH("LEFT")
    header.label:SetPoint("LEFT", header.icon, "RIGHT", 4, 0)

    -- Clear button
    header.clearBtn = CreateFrame("Button", nil, header)
    header.clearBtn:SetSize(40, HEADER_HEIGHT)
    header.clearBtn:SetPoint("RIGHT", header, "RIGHT", -HEADER_PADDING, 0)

    header.clearBtn.text = header.clearBtn:CreateFontString(nil, "OVERLAY")
    header.clearBtn.text:SetFontObject(GameFontNormalSmall)
    header.clearBtn.text:SetText("Clear")
    header.clearBtn.text:SetTextColor(unpack(Colors.textMuted))
    header.clearBtn.text:SetAllPoints()

    header.clearBtn:SetScript("OnEnter", function(self)
        self.text:SetTextColor(unpack(Colors.accent))
    end)
    header.clearBtn:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(Colors.textMuted))
    end)

    -- Divider line at bottom
    header.divider = header:CreateTexture(nil, "ARTWORK")
    header.divider:SetHeight(1)
    header.divider:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", HEADER_PADDING, 0)
    header.divider:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -HEADER_PADDING, 0)
    header.divider:SetColorTexture(unpack(Colors.divider))

    return header
end

local function ResetGroupHeader(header)
    header:Hide()
    header:SetParent(UIParent)
    header:ClearAllPoints()
    header.moduleId = nil
end

addon.GroupHeaderPool = BazUI:CreateObjectPool(CreateGroupHeader, ResetGroupHeader)

function addon.SetupGroupHeader(header, moduleId)
    local module = addon.modules[moduleId]
    if not module then return end

    header.moduleId = moduleId

    if module.icon then
        header.icon:SetTexture(module.icon)
        header.icon:Show()
    else
        header.icon:Hide()
    end

    header.label:SetText(module.name:upper())

    header.clearBtn:SetScript("OnClick", function()
        BNC:DismissAll(moduleId)
    end)

    return header
end

addon.GROUP_HEADER_HEIGHT = HEADER_HEIGHT
