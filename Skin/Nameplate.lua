-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- The name plate
--
-- A panel with a name on it, sized to the name: the zone text uses one,
-- and anything else that wants a label with a border around it can.
--
-- Drawn rather than painted. It used to be a picture cut into three
-- pieces, a fixed end cap at each side and the middle stretched to fit,
-- which is the usual way to make a plate of any width out of one image.
-- It was also the last thing pointing at the unit frame artwork, and
-- went green the day that artwork was retired: a missing texture in this
-- game is bright green, which is at least easy to spot.
--
-- What replaces it is the border every bar and every round button wears,
-- as a rectangle: two pixels of dark, one of gold, one of dark, around a
-- dark interior. Nothing to ship, nothing to scale, and it cannot go
-- missing.
---------------------------------------------------------------------------

local Theme = BazUI.Skin.Theme

-- parent   where the plate's pieces live
-- root     what the plate is positioned against
-- layout   { namePlate = {x, y, w, h}, name = {x, y, w, h} } in design pixels
-- ratio    design pixels to screen pixels
-- fontSize the name's size
-- tint     kept for callers; the border does not take one
function Theme.CreateNameplate(parent, root, layout, ratio, fontSize, tint)
    -- layout.name is no longer read: the name is centered on the plate,
    -- and the plate is sized to the name.
    local box = layout.namePlate
    local minimum = box.w * ratio
    local maximum = minimum * 2
    local height  = box.h * ratio
    local padding = 10
    local centerY = -(box.y + box.h / 2) * ratio

    -- The plate is a frame rather than loose textures so the border can
    -- be put around it the same way it is put around anything else.
    local plate = CreateFrame("Frame", nil, parent)
    plate:SetSize(minimum, height)
    Theme.ApplyBorder(plate, { fill = Theme.colors.bg })

    -- On the plate, not on the parent. A child frame draws over its
    -- parent's regions, so a font string belonging to the parent ends up
    -- behind the plate no matter which layer it claims.
    local text = plate:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", plate, "CENTER", 0, 0)
    text:SetFont(Theme.FontFile(), fontSize, "OUTLINE")
    text:SetTextColor(unpack(Theme.colors.goldSoft))
    text:SetWordWrap(false)

    local lastName, lastWidth
    local function Update(name, containerWidth)
        name = name or ""
        if name == lastName and containerWidth == lastWidth then return end
        lastName, lastWidth = name, containerWidth

        local limit = containerWidth and math.min(maximum, containerWidth) or maximum
        limit = math.max(padding * 2 + 16, limit)

        text:SetWidth(0)
        text:SetText(name)

        local width = math.min(limit,
            math.max(minimum, math.ceil(text:GetStringWidth()) + padding * 2))
        local available = width - padding * 2

        if text:GetStringWidth() > available then
            -- Trim whole UTF-8 characters, so an accented name loses a
            -- letter rather than half of one.
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
        plate:SetSize(width, height)
        plate:ClearAllPoints()
        plate:SetPoint("CENTER", root, "TOPLEFT",
            containerWidth and containerWidth / 2 or (box.x + box.w / 2) * ratio,
            centerY)
    end

    Update("")
    return text, Update, plate
end
