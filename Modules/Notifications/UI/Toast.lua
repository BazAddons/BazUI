-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications
local BNC = addon.API

local Colors = addon.Colors
local TOAST_WIDTH = 300
local TOAST_MIN_HEIGHT = 58
local TOAST_SPACING = 4
local MAX_TOASTS = 5

local BACKDROP_TOAST = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local activeToasts = {}

---------------------------------------------------------------------------
-- Toast frame
--
-- A toast is the floating, auto-dismissing counterpart to a NotificationCard.
-- The visual body (icon, module label, title, message, priority bar) is
-- built by addon.CreateNotificationBody so that any future layout change
-- applies to both cards and toasts. Toasts differ from cards only in:
--   • they show the module label inline (cards have GroupHeader instead)
--   • they fade in/out and auto-dismiss
--   • click falls through to opening the panel when no other action fires
---------------------------------------------------------------------------

local function CreateToast(index)
    local toast = CreateFrame("Button", "BazUINotifToast" .. index, UIParent, "BackdropTemplate")
    toast:SetSize(TOAST_WIDTH, TOAST_MIN_HEIGHT)
    toast:SetBackdrop(BACKDROP_TOAST)
    toast:SetBackdropColor(unpack(Colors.toastBg))
    toast:SetBackdropBorderColor(unpack(Colors.toastBorder))
    toast:SetFrameStrata("HIGH")
    toast:SetFrameLevel(5)
    toast:SetClampedToScreen(true)
    toast:EnableMouse(true)
    toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    toast:Hide()

    -- Shared body: icon, moduleLabel, title, message, priorityBar
    addon.CreateNotificationBody(toast)

    -- Hover effect + item tooltip + pause auto-dismiss
    toast:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(Colors.cardHover))
        if self._timer then
            self._timer:Cancel()
            self._timer = nil
        end
        local notif = self._notification
        if notif and notif.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(notif.itemLink)
            GameTooltip:Show()
        end
    end)

    toast:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(Colors.toastBg))
        -- Resume auto-dismiss
        self._timer = C_Timer.NewTimer(2, function()
            addon.DismissToast(self)
        end)
        GameTooltip:Hide()
    end)

    -- Click: ctrl-click dressing room, shift-click chat link, else run action
    toast:SetScript("OnClick", function(self, button)
        local notif = self._notification
        local handled = false

        if notif then
            if notif.itemLink then
                if IsControlKeyDown() then
                    DressUpItemLink(notif.itemLink)
                    addon.DismissToast(self)
                    return
                end
                if IsShiftKeyDown() then
                    ChatEdit_InsertLink(notif.itemLink)
                    addon.DismissToast(self)
                    return
                end
            end
            if notif.onClick then
                pcall(notif.onClick, notif)
                handled = true
            end
            if notif.waypoint and BNC:HasTomTom() then
                BNC:SetWaypoint(notif.waypoint)
                handled = true
            end
        end

        addon.DismissToast(self)

        -- Fall back to opening the panel if no action was taken
        if not handled then
            if addon.TogglePanel and not addon.IsPanelShown() then
                addon.TogglePanel()
            end
        end
    end)

    return toast
end

local function ResetToast(toast)
    toast:Hide()
    toast:ClearAllPoints()
    toast.priorityBar:Hide()
    toast.moduleLabel:Hide()
    toast._notification = nil
    if toast._timer then
        toast._timer:Cancel()
        toast._timer = nil
    end
end

local toastPool = BazUI:CreateObjectPool(CreateToast, ResetToast)

local function ReanchorToasts()
    if not addon.db then return end
    local anchorData = addon.GetAnchorData(addon.db.position)
    local margin = 10
    local buttonOffset = 32  -- space for the toggle button

    -- If the panel is open, stack toasts below/above the panel instead
    local panelOffset = 0
    if addon.IsPanelShown and addon.IsPanelShown() and addon.panel then
        panelOffset = addon.panel:GetHeight() + 4
    end

    local cumulativeHeight = 0
    for i, toast in ipairs(activeToasts) do
        toast:ClearAllPoints()

        local yOff = cumulativeHeight + buttonOffset + panelOffset
        local xBase = margin * anchorData.xDir
        local yBase = (margin + yOff) * anchorData.yDir

        toast:SetPoint(anchorData.point, UIParent, anchorData.relPoint, xBase, yBase)
        cumulativeHeight = cumulativeHeight + toast:GetHeight() + TOAST_SPACING
    end
end

function addon.DismissToast(toast)
    -- Remove from active list
    for i, t in ipairs(activeToasts) do
        if t == toast then
            table.remove(activeToasts, i)
            break
        end
    end

    addon.Animations.FadeOut(toast, 0.15, function()
        toastPool:Release(toast)
        ReanchorToasts()
    end)
end

function addon.DismissAllToasts()
    while #activeToasts > 0 do
        local toast = activeToasts[1]
        table.remove(activeToasts, 1)
        if toast._timer then toast._timer:Cancel() end
        addon.Animations.StopAll(toast)
        toastPool:Release(toast)
    end
end

local function ShowToast(notification)
    -- Limit active toasts
    while #activeToasts >= MAX_TOASTS do
        local oldest = activeToasts[#activeToasts]
        addon.DismissToast(oldest)
    end

    local toast = toastPool:Acquire()
    toast._notification = notification

    -- Populate via the shared helper (showing the inline module label)
    local totalHeight = addon.PopulateNotification(toast, notification, TOAST_WIDTH, {
        showModuleLabel = true,
    })
    toast:SetHeight(math.max(TOAST_MIN_HEIGHT, totalHeight))

    -- Insert at beginning of active list
    table.insert(activeToasts, 1, toast)
    ReanchorToasts()

    -- Animate in
    addon.Animations.FadeIn(toast, 0.2)

    -- Auto-dismiss timer
    local duration = notification.duration or (addon.db and addon.db.toastDuration) or 5
    toast._timer = C_Timer.NewTimer(duration, function()
        addon.DismissToast(toast)
    end)
end

-- Listen for toast requests
addon.Events:Register("TOAST_REQUESTED", ShowToast)
addon.Events:Register("SETTING_CHANGED_position", ReanchorToasts)
addon.Events:Register("PANEL_SHOWN", ReanchorToasts)
addon.Events:Register("PANEL_HIDDEN", ReanchorToasts)
