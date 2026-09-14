-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications

local ANCHOR_DATA = {
    TOPLEFT = {
        point = "TOPLEFT",
        relPoint = "TOPLEFT",
        xDir = 1,
        yDir = -1,
        toastGrowth = -1,   -- toasts stack downward
        slideX = -1,        -- slides in from left
        slideY = 0,
    },
    TOPRIGHT = {
        point = "TOPRIGHT",
        relPoint = "TOPRIGHT",
        xDir = -1,
        yDir = -1,
        toastGrowth = -1,
        slideX = 1,
        slideY = 0,
    },
    BOTTOMLEFT = {
        point = "BOTTOMLEFT",
        relPoint = "BOTTOMLEFT",
        xDir = 1,
        yDir = 1,
        toastGrowth = 1,    -- toasts stack upward
        slideX = -1,
        slideY = 0,
    },
    BOTTOMRIGHT = {
        point = "BOTTOMRIGHT",
        relPoint = "BOTTOMRIGHT",
        xDir = -1,
        yDir = 1,
        toastGrowth = 1,
        slideX = 1,
        slideY = 0,
    },
}

function addon.GetAnchorData(position)
    return ANCHOR_DATA[position] or ANCHOR_DATA["TOPLEFT"]
end

local MARGIN = 10

function addon.AnchorToCorner(frame, position, xOffset, yOffset)
    local data = addon.GetAnchorData(position)
    local mx = (xOffset or 0) + MARGIN * data.xDir
    local my = (yOffset or 0) + MARGIN * data.yDir
    frame:ClearAllPoints()
    frame:SetPoint(data.point, UIParent, data.relPoint, mx, my)
end

-- Given an arbitrary frame, return the corner key
-- (TOPLEFT/TOPRIGHT/BOTTOMLEFT/BOTTOMRIGHT) that best matches the
-- frame's screen position. Used to pick a sensible toast growth and
-- panel anchor direction once the user moves the bell freely via
-- Edit Mode - we still want toasts to stack toward screen-center
-- and the panel to fall on the inside of the bell rather than off
-- the screen edge.
function addon.DerivePositionForFrame(frame)
    if not frame then return "TOPLEFT" end
    local cx, cy = frame:GetCenter()
    if not cx or not cy then return "TOPLEFT" end
    local screenW = UIParent:GetWidth()
    local screenH = UIParent:GetHeight()
    local left = cx <= screenW / 2
    local top  = cy >= screenH / 2
    if top and left then return "TOPLEFT" end
    if top and not left then return "TOPRIGHT" end
    if not top and left then return "BOTTOMLEFT" end
    return "BOTTOMRIGHT"
end
