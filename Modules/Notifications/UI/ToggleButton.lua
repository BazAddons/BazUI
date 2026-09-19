-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications
local BNC = addon.API

local Colors = addon.Colors
local BUTTON_SIZE = 30
local BADGE_SIZE = 16

local button
local badge

local function CreateToggleButton()
    button = CreateFrame("Button", "BazUINotifToggleButton", UIParent)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel(100)
    button:SetClampedToScreen(true)
    button:SetMovable(true)  -- BazUI Edit Mode handles drag wiring
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Bell icon
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(18, 18)
    button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.icon:SetTexture("Interface\\Icons\\INV_Misc_Bell_01")
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Round ring-framed button, the same treatment as the minimap buttons.
    BazUI.Skin.Theme.ApplyRoundButton(button, button.icon)

    -- Badge
    badge = CreateFrame("Frame", nil, button, "BackdropTemplate")
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge:SetPoint("TOPRIGHT", button, "TOPRIGHT", 4, 4)
    badge:SetBackdrop(BazUI.Skin.Theme.BACKDROP_FLAT)
    badge:SetBackdropColor(unpack(Colors.badge))
    badge:SetBackdropBorderColor(unpack(Colors.panelBorder))
    badge:SetFrameLevel(button:GetFrameLevel() + 2)
    badge:EnableMouse(false)
    badge:Hide()

    badge.text = badge:CreateFontString(nil, "OVERLAY")
    badge.text:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontNormalSmall"))
    badge.text:SetTextColor(unpack(Colors.badgeText))
    badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)

    -- Left click toggles panel, right click clears all
    button:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            addon.DismissAllToasts()
            BNC:DismissAll()
        else
            addon.TogglePanel()
        end
    end)

    -- Hover + Tooltip
    button:SetScript("OnEnter", function(self)
        BazUI.Skin.Theme.SetRoundButtonHover(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")

        local anchorData = addon.GetAnchorData(addon.db.position)
        if anchorData.xDir > 0 then
            GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 4, 0)
        else
            GameTooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -4, 0)
        end

        GameTooltip:AddLine("Notifications")
        local count = BNC:GetUnreadCount()
        if count > 0 then
            GameTooltip:AddLine(count .. " notification" .. (count ~= 1 and "s" or ""), 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("No notifications", 0.5, 0.5, 0.5)
        end
        GameTooltip:AddLine("Click to toggle panel", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Right-click to clear all", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        BazUI.Skin.Theme.SetRoundButtonHover(self, false)
        GameTooltip:Hide()
    end)
end

local function UpdateBadge()
    if not badge then return end
    local count = BNC:GetUnreadCount()
    if count > 0 then
        badge.text:SetText(count > 999 and "999+" or tostring(count))
        -- Widen badge for larger numbers
        local textWidth = badge.text:GetStringWidth()
        badge:SetWidth(math.max(BADGE_SIZE, textWidth + 6))
        badge:Show()
    else
        badge:Hide()
    end
end

---------------------------------------------------------------------------
-- Position handling
--
-- The bell is the single movable frame for BNC. The notification panel
-- always anchors to the bell, and toast/panel growth direction comes
-- from a derived corner (which screen quadrant the bell sits in).
--
-- - bellAnchor saved > restore that absolute position on load.
-- - bellAnchor nil   > fall back to the default TOPLEFT margin.
--
-- After any (re)anchor, the derived position is recomputed so toasts
-- and the panel slide/grow toward screen-center rather than off-edge.
---------------------------------------------------------------------------

local function RecomputeDerivedPosition()
    if not button or not addon.db then return end
    local derived = addon.DerivePositionForFrame(button)
    if derived ~= addon.db.position then
        addon.db.position = derived
        addon.Events:Trigger("SETTING_CHANGED_position", derived)
    end
end

-- Exposed as well as local, so the module's ApplySettings can put the
-- bell back where the new profile says it goes. See Core/Init.lua.
local ApplyButtonPosition
function addon.ApplyButtonPosition() return ApplyButtonPosition() end

function ApplyButtonPosition()
    if not button or not addon.db then return end

    button:ClearAllPoints()
    local saved = addon.db.bellAnchor
    if saved and saved.point then
        button:SetPoint(
            saved.point,
            UIParent,
            saved.relPoint or saved.point,
            saved.x or 0,
            saved.y or 0
        )
    else
        addon.AnchorToCorner(button, addon.db.position or "TOPLEFT")
    end

    RecomputeDerivedPosition()
end

local function RegisterWithEditMode()
    if not button or not BazUI or not BazUI.RegisterEditModeFrame then return end
    if button._editModeRegistered then return end

    BazUI:RegisterEditModeFrame(button, {
        label = "Notification Bell",
        addonName = "Notifications",
        positionKey = false,  -- We persist manually so we can also re-derive position
        onPositionChanged = function()
            local point, _, relPoint, x, y = button:GetPoint()
            if point and addon.db then
                addon.db.bellAnchor = {
                    point    = point,
                    relPoint = relPoint,
                    x        = x or 0,
                    y        = y or 0,
                }
            end
            RecomputeDerivedPosition()
        end,
        -- Active toasts anchor to the bell at fixed offsets - they
        -- don't follow the bell while it's being dragged, which
        -- looks awkward (toast stays put, bell flies away). Dismiss
        -- them on Edit Mode entry so the user only sees the bell
        -- being repositioned.
        onEnter = function()
            if addon.DismissAllToasts then
                addon.DismissAllToasts()
            end
        end,
    })

    button._editModeRegistered = true
end

function addon.GetToggleButton()
    return button
end

-- Public: snap the bell back to a screen corner. Called from the
-- options page "Reset to Top Left" / "Reset to Top Right" buttons.
-- Pass a corner key like "TOPLEFT" or "TOPRIGHT". We clear the
-- saved bellAnchor *and* set db.position so ApplyButtonPosition
-- uses the requested corner rather than the previously derived one.
function addon.ResetBellPosition(corner)
    if not addon.db then return end
    corner = corner or "TOPLEFT"
    addon.db.bellAnchor = nil
    addon.db.position = corner
    ApplyButtonPosition()
    -- Notify panel/toast listeners even if RecomputeDerivedPosition
    -- inside ApplyButtonPosition didn't fire (corner unchanged case).
    addon.Events:Trigger("SETTING_CHANGED_position", corner)
end

-- Event listeners
addon.Events:Register("CORE_LOADED", function()
    CreateToggleButton()
    ApplyButtonPosition()
    RegisterWithEditMode()
    UpdateBadge()
end)

addon.Events:Register("NOTIFICATION_ADDED", UpdateBadge)
addon.Events:Register("NOTIFICATION_DISMISSED", UpdateBadge)
addon.Events:Register("NOTIFICATIONS_CLEARED", UpdateBadge)
addon.Events:Register("SETTING_CHANGED_scale", function(scale)
    if button then
        button:SetScale(scale or 1)
    end
end)
