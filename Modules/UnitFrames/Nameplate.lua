-- SPDX-License-Identifier: GPL-2.0-or-later
local module = BazUI:GetModule("UnitFrames")

-- Only artwork and text resize; secure unit hit areas stay unchanged in combat.
function module:CreateNameplate(parent, root, layout, ratio, fontSize, tint)
    local style = BazUI.Skin.Theme.nameplate
    local box, label = layout.namePlate, layout.name
    local minimum = box.w * ratio
    local maximum = minimum * 2
    local height = box.h * ratio
    local cap = minimum * style.capPixels / style.width
    local padding = cap + 5
    local centerX = (box.x + box.w / 2) * ratio
    local centerY = -(box.y + box.h / 2) * ratio
    local pieces = {}
    local cuts = { 0, style.capPixels, style.width - style.capPixels, style.width }
    for i = 1, 3 do
        local texture = parent:CreateTexture(nil, "ARTWORK")
        texture:SetTexture(BazUI.Skin.PLAYER_NAMEPLATE)
        texture:SetVertexColor(tint, tint, tint)
        texture:SetTexCoord(cuts[i] / style.textureWidth, cuts[i + 1] / style.textureWidth,
            0, style.height / style.textureHeight)
        pieces[i] = texture
    end
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", root, "TOPLEFT", (label.x + label.w / 2) * ratio,
        -(label.y + label.h / 2) * ratio)
    text:SetHeight(label.h * ratio)
    text:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    text:SetTextColor(unpack(BazUI.Skin.Theme.colors.goldSoft))
    text:SetWordWrap(false)
    local lastName
    local function Update(name)
        name = name or ""
        if name == lastName then return end
        lastName = name
        text:SetWidth(0)
        text:SetText(name)
        local width = math.min(maximum, math.max(minimum, math.ceil(text:GetStringWidth()) + padding * 2))
        local available = width - padding * 2
        if text:GetStringWidth() > available then
            -- Trim whole UTF-8 characters, including accented player names.
            local chars = {}
            for char in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                chars[#chars + 1] = char
            end
            repeat
                chars[#chars] = nil
                text:SetText(table.concat(chars) .. "...")
            until text:GetStringWidth() <= available or #chars == 0
        end
        text:SetWidth(available)
        local widths = { cap, width - cap * 2, cap }
        local x = centerX - width / 2
        for i, texture in ipairs(pieces) do
            texture:ClearAllPoints()
            texture:SetPoint("LEFT", root, "TOPLEFT", x, centerY)
            texture:SetSize(widths[i], height)
            x = x + widths[i]
        end
    end
    Update("")
    return text, Update
end
