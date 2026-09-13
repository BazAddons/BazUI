-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Menu Module
-- Declarative wrapper around MenuUtil.CreateContextMenu
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Menu Builder
-- Takes a flat definition table and builds a Dragonflight+ context menu
--
-- Definition format:
-- {
--   { text = "Option 1", onClick = function() end },
--   { text = "Toggle",   checked = true/function, onClick = function() end },
--   { text = "---" },  -- separator
--   { text = "Submenu", children = { ... } },
--   { text = "Title Text", isTitle = true },
-- }
---------------------------------------------------------------------------

local function BuildMenuItems(rootDescription, items)
    for _, item in ipairs(items) do
        -- Separator
        if item.text == "---" or item.separator then
            rootDescription:CreateDivider()

        -- Title / header
        elseif item.isTitle then
            rootDescription:CreateTitle(item.text)

        -- Submenu
        elseif item.children then
            local sub = rootDescription:CreateButton(item.text)
            BuildMenuItems(sub, item.children)

        -- Checkbox / toggle
        elseif item.checked ~= nil then
            local isChecked
            if type(item.checked) == "function" then
                isChecked = item.checked()
            else
                isChecked = item.checked
            end

            rootDescription:CreateCheckbox(item.text, function()
                return isChecked
            end, function()
                if item.onClick then item.onClick() end
            end)

        -- Radio option
        elseif item.radio ~= nil then
            rootDescription:CreateRadio(item.text, function()
                if type(item.radio) == "function" then
                    return item.radio()
                end
                return item.radio
            end, function()
                if item.onClick then item.onClick() end
            end)

        -- Standard button
        else
            local btn = rootDescription:CreateButton(item.text, function()
                if item.onClick then item.onClick() end
            end)

            -- Optional icon
            if item.icon then
                btn:AddInitializer(function(button)
                    local tex = button:AttachTexture()
                    if tex then
                        tex:SetSize(16, 16)
                        tex:SetTexture(item.icon)
                    end
                end)
            end

            -- Disabled state
            if item.disabled then
                btn:SetEnabled(false)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function BazUI:ShowMenu(anchor, items)
    if not anchor or not items then return end

    MenuUtil.CreateContextMenu(anchor, function(_, rootDescription)
        BuildMenuItems(rootDescription, items)
    end)
end

-- Reusable cursor anchor frame
local cursorAnchor = nil

-- Show menu at cursor position (no anchor needed)
function BazUI:ShowMenuAtCursor(items)
    if not items then return end

    if not cursorAnchor then
        cursorAnchor = CreateFrame("Frame", nil, UIParent)
        cursorAnchor:SetSize(1, 1)
    end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cursorAnchor:ClearAllPoints()
    cursorAnchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)

    MenuUtil.CreateContextMenu(cursorAnchor, function(_, rootDescription)
        BuildMenuItems(rootDescription, items)
    end)
end
