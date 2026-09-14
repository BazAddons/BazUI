-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: MinimapButton Module
--
-- One button on the minimap for the whole suite. Left-click opens the
-- codex, right-click opens the settings, and that is the whole of it.
-- Modules still register an entry to say they want the button to exist;
-- the button wears the icon of whichever module owns the left click.
---------------------------------------------------------------------------

local BUTTON_SIZE = 31
local BUTTON_RADIUS_OFFSET = 10  -- extra pixels beyond minimap edge
local DEFAULT_ANGLE = 225

-- The module the button opens, and so the module whose icon it wears.
local PRIMARY = "Codex"
local FALLBACK_ICON = "Interface\\Icons\\INV_Gizmo_GoblingTonkController"

local minimapEntries = {} -- { addonName = { label, icon, onClick } }
local button = nil

local function ButtonIcon()
    local primary = minimapEntries[PRIMARY]
    return (primary and primary.icon) or FALLBACK_ICON
end

---------------------------------------------------------------------------
-- Position Math
---------------------------------------------------------------------------

local function GetMinimapRadius()
    return (Minimap:GetWidth() / 2) + BUTTON_RADIUS_OFFSET
end

local function UpdateButtonPosition(angle)
    if not button then return end
    local radius = GetMinimapRadius()
    local rad = math.rad(angle)
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

---------------------------------------------------------------------------
-- Button Creation
---------------------------------------------------------------------------

local function CreateButton()
    if button then return end

    local btn = CreateFrame("Button", "BazUIMinimapButton", Minimap)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetClampedToScreen(true)

    -- Background circle
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetVertexColor(0.1, 0.1, 0.15, 0.8)

    -- Icon - masked to a circle so it blends into the minimap-button
    -- tracking border instead of showing as a square inside a ring.
    -- SetMask uses the alpha channel of the mask texture to clip the
    -- icon; `TempPortraitAlphaMask` is Blizzard's standard circular
    -- portrait mask and produces a clean round icon.
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(ButtonIcon())
    icon:SetMask("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    btn.icon = icon

    -- Border ring
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Highlight
    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    highlight:SetPoint("CENTER")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    -- Two clicks, both of them useful: the codex on the left, the
    -- settings on the right. There used to be a menu listing every
    -- module here, but most of its entries only opened an options page,
    -- and all of those pages sit a click apart in the one settings
    -- window that right-click already opens.
    btn:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            BazUI:OpenOptionsPanel("BazUI")
        elseif BazUI.Codex and BazUI.Codex.Toggle then
            BazUI.Codex:Toggle()
        else
            BazUI:OpenOptionsPanel("BazUI")
        end
    end)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("BazUI", 0.2, 0.6, 1.0)
        GameTooltip:AddLine("Version " .. BazUI.VERSION, 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click for the codex", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Right-click for settings", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Dragging around minimap edge
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            UpdateButtonPosition(angle)
            -- Save angle
            BazUIDB = BazUIDB or {}
            BazUIDB.minimapAngle = angle
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button = btn

    -- Restore saved position
    BazUIDB = BazUIDB or {}
    local angle = BazUIDB.minimapAngle or DEFAULT_ANGLE
    UpdateButtonPosition(angle)

    -- Respect hide setting on load
    if BazUIDB.minimap and BazUIDB.minimap.hide then
        btn:Hide()
    end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function BazUI:RegisterMinimapEntry(addonName, minimapConfig)
    minimapEntries[addonName] = minimapConfig

    -- The button wears the icon of whatever it opens, so a module that
    -- registers after the button exists still lands on the art.
    if button and button.icon then button.icon:SetTexture(ButtonIcon()) end

    -- Create button on first registration, defer to PLAYER_LOGIN
    if not button then
        BazUI:QueueForLogin(function()
            CreateButton()
        end)
    end
end

function BazUI:ShowMinimapButton()
    if button then button:Show() end
end

function BazUI:HideMinimapButton()
    if button then button:Hide() end
end

