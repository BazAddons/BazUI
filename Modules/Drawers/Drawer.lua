-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers: Drawer frame
-- Full-height slide-out side panel. The tab handle hangs outside the
-- drawer's inner edge so that when the drawer is fully slid off-screen,
-- only the handle remains visible. Backdrop uses a standard tooltip
-- border so it scales cleanly at any height.

local addon = BazUI:GetModule("Drawers")

local Drawer = {}
addon.Drawer = Drawer

-- Helper: check if the mouse is over the drawer, toggle button, or tab strip
function Drawer:IsHovered()
    local f = self.frame
    if not f then return false end
    if f:IsMouseOver() then return true end
    if f.toggleButton and f.toggleButton:IsShown() and f.toggleButton:IsMouseOver() then return true end
    if self._tabStrip and self._tabStrip:IsShown() then
        for _, tab in ipairs(self._tabStrip._tabs) do
            if tab:IsShown() and tab:IsMouseOver() then return true end
        end
    end
    return false
end

local MIN_WIDTH = 120
local MAX_WIDTH = 400
local DEFAULT_WIDTH = 222

local function GetWidth()
    local w = addon:GetSetting("width") or DEFAULT_WIDTH
    if w < MIN_WIDTH then w = MIN_WIDTH end
    if w > MAX_WIDTH then w = MAX_WIDTH end
    return w
end

Drawer.MIN_WIDTH = MIN_WIDTH
Drawer.MAX_WIDTH = MAX_WIDTH
Drawer.DEFAULT_WIDTH = DEFAULT_WIDTH

-- Pixels the visible edge sits inside the frame's logical edge. The tab
-- is pushed inward by this much so it butts against the edge instead of
-- hanging in a small gap.
local TAB_BORDER_INSET = 2

---------------------------------------------------------------------------
-- Atlas helpers (hoisted so the toggle button's OnEnter/OnLeave closures
-- can capture them as locals at definition time)
---------------------------------------------------------------------------

-- Apply an atlas to a texture with optional horizontal flip. We can't just
-- SetAtlas + SetTexCoord because SetAtlas resets texcoords, so for the
-- flipped case we look up the atlas manually via C_Texture.GetAtlasInfo
-- and set the texture file + flipped texcoords directly.
local function ApplyAtlasToTexture(tex, atlas, flipH)
    if not tex or not atlas then return end
    if flipH then
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
        if info and info.file then
            tex:SetTexture(info.file)
            local l = info.leftTexCoord  or 0
            local r = info.rightTexCoord or 1
            local t = info.topTexCoord   or 0
            local b = info.bottomTexCoord or 1
            tex:SetTexCoord(r, l, t, b)  -- swap left/right
            return
        end
    end
    tex:SetAtlas(atlas)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

function Drawer:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "BazUIDrawerFrame", UIParent, "BackdropTemplate")
    f:SetWidth(GetWidth())
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)

    -- Motion-only: the drawer frame itself needs to receive OnEnter/OnLeave
    -- so the fade controller can detect hover, but clicks must pass through
    -- to the game world so the player can target mobs / click NPCs in the
    -- area the drawer occupies. Widgets have their own click handlers.
    if f.SetMouseClickEnabled then
        f:SetMouseClickEnabled(false)
    end
    if f.SetMouseMotionEnabled then
        f:SetMouseMotionEnabled(true)
    elseif f.EnableMouseMotion then
        f:EnableMouseMotion(true)
    end

    BazUI.Skin.Theme.ApplyFlatPanel(f)
    BazUI.Skin.Theme.SetFlatPanelAlpha(f, addon:GetSetting("backgroundOpacity") or 0.9, 1)

    -- Display frame - holds all content (hidden when collapsed)
    local display = CreateFrame("Frame", "BazUIDrawerDisplayFrame", f)
    display:SetPoint("TOPLEFT", 8, -8)
    display:SetPoint("BOTTOMRIGHT", -8, 8)
    f.displayFrame = display

    -- Chrome group: holds the title bar elements (label, count, info)
    -- so they can fade as a unit along with the backdrop/border/tab
    -- without affecting the sibling widget host. Anchored to the BOTTOM
    -- of the display so widgets can use the full top area of the drawer.
    local chrome = CreateFrame("Frame", nil, display)
    chrome:SetPoint("BOTTOMLEFT", 0, 0)
    chrome:SetPoint("BOTTOMRIGHT", 0, 0)
    chrome:SetHeight(30)
    display.chromeGroup = chrome

    display.label = BazUI.Skin.Theme.FontString(chrome, "ARTWORK", "GameFontNormalSmall")
    display.label:SetPoint("LEFT", 4, 0)
    display.label:SetText("BAZWIDGETDRAWERS")

    -- Lock button - parented to chromeGroup so it fades with the rest
    -- of the chrome (label, count, info button). When locked, the chrome
    -- is hidden but the lock gets its own hover-based visibility via
    -- ApplyLockUI.
    display.lockButton = CreateFrame("Button", nil, chrome)
    display.lockButton:SetSize(22, 22)
    display.lockButton:SetFrameLevel((chrome:GetFrameLevel() or 0) + 2)
    display.lockButton:SetPoint("RIGHT", chrome, "RIGHT", -4, 0)
    display.lockButton.icon = display.lockButton:CreateTexture(nil, "ARTWORK")
    display.lockButton.icon:SetAllPoints()
    display.lockButton:SetScript("OnClick", function()
        Drawer:ToggleLock()
    end)
    display.lockButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if addon:GetSetting("locked") then
            GameTooltip:SetText("Drawer Locked")
            GameTooltip:AddLine("Click to unlock. Toggling and edge-hover are disabled while locked.", 1, 1, 1, true)
        else
            GameTooltip:SetText("Drawer Unlocked")
            GameTooltip:AddLine("Click to lock. Prevents the drawer from collapsing/expanding via click or edge hover.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    display.lockButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- A gear, not Blizzard's round "i": this opens the drawer's settings,
    -- and an information icon on a settings button is the sort of thing
    -- that only makes sense to whoever put it there.
    display.infoButton = BazUI.Skin.Theme.CreateSettingsButton(chrome, {
        size = 20,
        tooltip = "Drawer Settings",
        onClick = function()
            if BazUI.OpenOptionsPanel then
                BazUI:OpenOptionsPanel("Drawers")
            end
        end,
    })
    display.infoButton:SetPoint("RIGHT", display.lockButton, "LEFT", -4, 0)

    display.countLabel = chrome:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
    display.countLabel:SetPoint("RIGHT", display.infoButton, "LEFT", -6, 0)
    display.countLabel:SetJustifyH("RIGHT")
    display.countLabel:SetText("0")

    -- Widget host - takes the full top area, leaves room for the chrome
    -- group at the bottom.
    local host = CreateFrame("Frame", "BazUIDrawerWidgetHost", display)
    host:SetPoint("TOPLEFT", 4, -4)
    host:SetPoint("BOTTOMRIGHT", -4, 34)
    f.widgetHost = host

    if addon.WidgetHost then
        addon.WidgetHost:Initialize(host)
    end

    -- Legacy toggle button (hidden - replaced by tab strip)
    f.toggleButton = self:BuildToggleButton("BazUIDrawerToggleButton", f)
    f.toggleButton:Hide()

    self.frame = f

    -- Tab strip replaces the pull-tab
    self:BuildTabStrip()

    -- Keep drawer sized to screen height on display changes
    f:RegisterEvent("DISPLAY_SIZE_CHANGED")
    f:RegisterEvent("UI_SCALE_CHANGED")
    f:SetScript("OnEvent", function() Drawer:ApplySide() end)
    self:ApplySide()
    self:SetupEdgeHotZone()
    self:SetupFadeController()
    self:ApplyLockUI()
    return f
end

function Drawer:BuildToggleButton(name, parent)
    local btn = CreateFrame("Button", name, parent)
    btn:SetSize(16, 35)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel((parent:GetFrameLevel() or 0) + 5)

    btn:SetScript("OnClick", function() Drawer:Toggle() end)
    btn:SetScript("OnEnter", function(self)
        ApplyAtlasToTexture(self:GetNormalTexture(), self._hoverAtlas, self._flipH)
    end)
    btn:SetScript("OnLeave", function(self)
        ApplyAtlasToTexture(self:GetNormalTexture(), self._normalAtlas, self._flipH)
    end)
    return btn
end

---------------------------------------------------------------------------
-- ApplySide - re-anchors frame, tab buttons, and swaps tab atlases based
-- on the current side setting. Called on build, on collapse/expand, and
-- when the user changes the side in settings.
---------------------------------------------------------------------------

function Drawer:ApplySide()
    local f = self.frame; if not f then return end
    local side = addon:GetSetting("side") or "right"
    local width = GetWidth()

    f:SetWidth(width)

    local topPoint, bottomPoint, expandedX, collapsedX
    local tabSelf, tabRelative, tabXOffset

    local EDGE_HIDE = 8  -- push frame off-screen to hide the border edge

    if side == "left" then
        topPoint, bottomPoint = "TOPLEFT", "BOTTOMLEFT"
        expandedX = -EDGE_HIDE
        collapsedX = -width
        tabSelf = "LEFT"                    -- tab's left anchors to drawer's right edge
        tabRelative = "RIGHT"
        tabXOffset = -TAB_BORDER_INSET      -- push tab left into the border
    else -- right
        topPoint, bottomPoint = "TOPRIGHT", "BOTTOMRIGHT"
        expandedX = EDGE_HIDE
        collapsedX = width
        tabSelf = "RIGHT"                   -- tab's right anchors to drawer's left edge
        tabRelative = "LEFT"
        tabXOffset = TAB_BORDER_INSET       -- push tab right into the border
    end

    -- Arrow direction (after any flip):
    -- Expanded > click collapses drawer toward its edge (arrow toward edge).
    -- Collapsed > click expands drawer toward screen center.
    --
    -- Store computed positions for the slide animation
    self._topPoint = topPoint
    self._bottomPoint = bottomPoint
    self._expandedX = expandedX
    self._collapsedX = collapsedX

    local x = self.collapsed and collapsedX or expandedX

    -- Anchor both corners so the drawer spans the full screen height
    f:ClearAllPoints()
    f:SetPoint(topPoint, UIParent, topPoint, x, 0)
    f:SetPoint(bottomPoint, UIParent, bottomPoint, x, 0)

    -- Legacy toggle button - kept for structure but hidden (tabs replace it)
    f.toggleButton:ClearAllPoints()
    f.toggleButton:SetPoint(tabSelf, f, tabRelative, tabXOffset, 0)
    f.toggleButton:Hide()

    -- Refresh tab strip positioning for the current side
    self:RefreshTabs()
end

---------------------------------------------------------------------------
-- Expand / Collapse / Toggle (with slide animation)
---------------------------------------------------------------------------

local SLIDE_DURATION = 0.25  -- seconds for slide animation

function Drawer:SlideToX(targetX, onFinish)
    local f = self.frame; if not f then return end
    local topPoint = self._topPoint or "TOPRIGHT"
    local bottomPoint = self._bottomPoint or "BOTTOMRIGHT"

    -- Get current X from anchor
    local _, _, _, startX = f:GetPoint(1)
    if not startX then startX = targetX end

    -- Cancel any running slide
    if self._slideTimer then
        self._slideTimer:Cancel()
        self._slideTimer = nil
    end
    if self._slideFrame then
        self._slideFrame:SetScript("OnUpdate", nil)
    end

    if math.abs(startX - targetX) < 1 then
        -- Already at target
        f:ClearAllPoints()
        f:SetPoint(topPoint, UIParent, topPoint, targetX, 0)
        f:SetPoint(bottomPoint, UIParent, bottomPoint, targetX, 0)
        if onFinish then onFinish() end
        return
    end

    if not self._slideFrame then
        self._slideFrame = CreateFrame("Frame")
    end

    local elapsed = 0
    self._slideFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        local progress = math.min(elapsed / SLIDE_DURATION, 1)
        -- Smooth ease-out
        local eased = 1 - (1 - progress) * (1 - progress)
        local x = startX + (targetX - startX) * eased

        f:ClearAllPoints()
        f:SetPoint(topPoint, UIParent, topPoint, x, 0)
        f:SetPoint(bottomPoint, UIParent, bottomPoint, x, 0)

        if progress >= 1 then
            self._slideFrame:SetScript("OnUpdate", nil)
            if onFinish then onFinish() end
        end
    end)
end

function Drawer:Expand()
    self.collapsed = false

    local targetX = self._expandedX or 0

    self:SlideToX(targetX, function()
        -- Show content AFTER slide completes to avoid child frame lag
        local display = self.frame and self.frame.displayFrame
        if display then
            display:Show()
            display:SetAlpha(0)
            UIFrameFade(display, {
                mode = "IN",
                timeToFade = 0.15,
                startAlpha = 0,
                endAlpha = 1,
            })
        end
        addon:SetDrawerCollapsed(nil, false)
        if self._edgeHotZone then self._edgeHotZone:Hide() end
        if self.EvaluateFade then self:EvaluateFade(true) end
        self:RefreshTabs()
    end)

    -- Refresh tabs immediately so the active tab colors update
    self:RefreshTabs()
end

function Drawer:Collapse()
    -- Locked drawers cannot be collapsed by user interaction.
    if addon:GetSetting("locked") then return end
    self.collapsed = true

    local targetX = self._collapsedX or 0

    -- Refresh tabs immediately so all tabs show
    self:RefreshTabs()

    -- Fade out content quickly, then slide
    local display = self.frame and self.frame.displayFrame
    if display then
        UIFrameFade(display, {
            mode = "OUT",
            timeToFade = 0.1,
            startAlpha = display:GetAlpha(),
            endAlpha = 0,
            finishedFunc = function()
                display:Hide()
                display:SetAlpha(1)
            end,
        })
    end

    self:SlideToX(targetX, function()
        addon:SetDrawerCollapsed(nil, true)
        if self._edgeHotZone then self._edgeHotZone:Show() end
        if self.EvaluateFade then self:EvaluateFade(true) end
    end)
end

function Drawer:Toggle()
    -- Locked: ignore click/key requests to toggle.
    if addon:GetSetting("locked") then return end
    if self.collapsed then self:Expand() else self:Collapse() end
end

---------------------------------------------------------------------------
-- Tab strip - vertical stack of text tabs on the drawer edge.
--
-- When all drawers are collapsed: all tabs visible (pick which to open).
-- When one is open: only that drawer's tab visible (click to close).
-- Tabs fade with the drawer chrome and are hidden when locked.
---------------------------------------------------------------------------

function Drawer:BuildTabStrip()
    local f = self.frame; if not f then return end

    if not self._tabStrip then
        self._tabStrip = CreateFrame("Frame", nil, f)
        self._tabStrip:SetFrameStrata("MEDIUM")
        self._tabStrip:SetFrameLevel((f:GetFrameLevel() or 0) + 6)
        self._tabStrip._tabs = {}
    end

    self:RefreshTabs()
end

function Drawer:RefreshTabs()
    local f = self.frame; if not f then return end
    local strip = self._tabStrip; if not strip then return end

    -- Hide all existing tabs
    for _, tab in ipairs(strip._tabs) do
        tab:Hide()
    end

    local sorted = addon:GetSortedDrawers()
    local activeId = addon:GetActiveDrawerId()
    local isExpanded = not self.collapsed
    local locked = addon:GetSetting("locked")

    local side = addon:GetSetting("side") or "right"
    local flipTab = (side == "left")
    local tabSelf, tabRelative, tabXOffset
    if side == "left" then
        tabSelf = "TOPLEFT"
        tabRelative = "TOPRIGHT"
        tabXOffset = -2
    else
        tabSelf = "TOPRIGHT"
        tabRelative = "TOPLEFT"
        tabXOffset = 2
    end

    local TAB_SIZE = 32
    local TAB_BORDER_SIZE = 64
    local TAB_ICON_SIZE = 30
    local TAB_GAP = 12

    -- Calculate total strip height to center vertically
    local totalTabs = #sorted
    local totalStripH = (totalTabs * TAB_SIZE) + ((totalTabs - 1) * TAB_GAP)
    local frameH = f:GetHeight() or 0
    local tabY = -(frameH / 2) + (totalStripH / 2)

    for i, entry in ipairs(sorted) do
        local drawerId = entry.id
        local def = entry.def
        local isActive = (drawerId == activeId)

        -- When expanded, only show the active tab but still
        -- advance tabY so the active tab stays in its natural position.
        if isExpanded and not isActive then
            tabY = tabY - TAB_SIZE - TAB_GAP
        else
            local tab = strip._tabs[i]
            if not tab then
                tab = CreateFrame("CheckButton", nil, strip)
                tab:SetSize(TAB_SIZE, TAB_SIZE)
                tab:SetFrameLevel((strip:GetFrameLevel() or 0) + 1)

                -- SpellBook-SkillLineTab border (same as guild/communities side tabs)
                -- Flipped horizontally when on the right side so the tab
                -- hangs off the drawer's inner edge correctly.
                tab.border = tab:CreateTexture(nil, "BORDER")
                tab.border:SetSize(TAB_BORDER_SIZE, TAB_BORDER_SIZE)
                tab.border:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")

                -- Icon centered
                tab.icon = tab:CreateTexture(nil, "ARTWORK")
                tab.icon:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
                tab.icon:SetPoint("CENTER", 0, 0)
                tab.icon:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)

                -- Proc glow on hover (Blizzard's animated overlay glow)


                tab:SetScript("OnEnter", function(self)
                    BazUI:ShowGlow(self)
                    self.icon:SetDesaturated(false)
                    self.icon:SetAlpha(1.0)
                    if not addon:GetSetting("locked") then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(self._label or "")
                        GameTooltip:Show()
                    end
                end)
                tab:SetScript("OnLeave", function(self)
                    BazUI:HideGlow(self)
                    -- Only stay colored if this is the active tab AND drawer is open
                    if not (self._isActive and not Drawer.collapsed) then
                        self.icon:SetDesaturated(true)
                        self.icon:SetAlpha(0.6)
                    end
                    GameTooltip:Hide()
                end)

                strip._tabs[i] = tab
            end

            tab._drawerId = drawerId
            tab._isActive = isActive
            tab._label = def.label or drawerId

            -- Update border flip for current side (runs every refresh)
            tab.border:ClearAllPoints()
            if flipTab then
                -- Left side drawer: tab hangs to the right (native SpellBook orientation)
                tab.border:SetPoint("TOPLEFT", -3, 11)
                tab.border:SetTexCoord(0, 1, 0, 1)
            else
                -- Right side drawer: flip horizontally so tab hangs to the left
                tab.border:SetPoint("TOPRIGHT", 3, 11)
                tab.border:SetTexCoord(1, 0, 0, 1)
            end

            -- Set icon
            local iconPath = def.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
            tab.icon:SetTexture(iconPath)

            -- Color logic:
            -- Active + expanded = full color always
            -- Everything else (inactive, or active but collapsed) = desaturated
            -- Hover overrides to full color (handled in OnEnter/OnLeave)
            if isActive and isExpanded then
                tab.icon:SetDesaturated(false)
                tab.icon:SetAlpha(1.0)
            else
                tab.icon:SetDesaturated(true)
                tab.icon:SetAlpha(0.6)
            end

            tab:SetScript("OnClick", function()
                if drawerId == activeId then
                    -- Clicking active tab toggles expand/collapse
                    Drawer:Toggle()
                else
                    -- Switch to a different drawer
                    addon:SetActiveDrawer(drawerId)
                    if Drawer.collapsed then
                        -- All drawers collapsed - just expand the new one
                        Drawer:Expand()
                    else
                        -- Another drawer is open - swap content instantly
                        -- (the drawer is already in position)
                        local display = f.displayFrame
                        if display then
                            UIFrameFade(display, {
                                mode = "OUT",
                                timeToFade = 0.1,
                                startAlpha = display:GetAlpha(),
                                endAlpha = 0,
                                finishedFunc = function()
                                    -- Reflow with new drawer's widgets
                                    if addon.WidgetHost and addon.WidgetHost.Reflow then
                                        addon.WidgetHost:Reflow()
                                    end
                                    -- Fade back in
                                    UIFrameFade(display, {
                                        mode = "IN",
                                        timeToFade = 0.15,
                                        startAlpha = 0,
                                        endAlpha = 1,
                                    })
                                end,
                            })
                        end
                        Drawer:RefreshTabs()
                        if Drawer.EvaluateFade then Drawer:EvaluateFade(true) end
                    end
                end
            end)

            tab:ClearAllPoints()
            tab:SetPoint(tabSelf, f, tabRelative, tabXOffset, tabY)
            tab:Show()

            tabY = tabY - TAB_SIZE - TAB_GAP
        end
    end

    -- Size the strip to contain all visible tabs
    strip:SetSize(TAB_SIZE, math.abs(tabY))

    -- Hide tabs when locked
    if locked then
        strip:Hide()
    else
        strip:Show()
    end
end

---------------------------------------------------------------------------
-- Lock system
--
-- When locked:
--   * Toggle button clicks and edge-hover auto-expand are ignored.
--   * The chrome title-bar contents (label, count, info button) are
--     hidden. Only the lock button remains, and only while the drawer
--     is being hovered by the cursor.
--   * Fade/opacity settings are grayed out in the options panel.
---------------------------------------------------------------------------

-- Atlas pair for the lock icon. Both are stock Blizzard atlases.
local LOCK_ATLAS_LOCKED   = "activities-icon-lock"
local LOCK_ATLAS_UNLOCKED = "QuestSharing-Padlock"
-- Classic flavours lack these atlases; plain textures every client ships.
local LOCK_FILE_LOCKED    = "Interface\\Buttons\\LockButton-Locked-Up"
local LOCK_FILE_UNLOCKED  = "Interface\\Buttons\\LockButton-Unlocked-Up"

function Drawer:ApplyLockUI(skipFade)
    local f = self.frame; if not f then return end
    local display = f.displayFrame; if not display then return end

    local locked = addon:GetSetting("locked") and true or false
    local hovered = Drawer:IsHovered()

    -- Swap the lock icon's atlas based on state
    local lb = display.lockButton
    if lb and lb.icon then
        BazUI.SetAtlasOrTexture(lb.icon,
            locked and LOCK_ATLAS_LOCKED or LOCK_ATLAS_UNLOCKED,
            locked and LOCK_FILE_LOCKED or LOCK_FILE_UNLOCKED, false)
    end

    -- Hide/show the rest of the chrome based on the lock state.
    -- When locked, only the lock button stays - and even that only
    -- shows while the cursor is over the drawer.
    local showChrome = not locked
    if display.label      then display.label:SetShown(showChrome)      end
    if display.countLabel then display.countLabel:SetShown(showChrome) end
    if display.infoButton then display.infoButton:SetShown(showChrome) end

    -- Lock visibility:
    -- Unlocked: parented to chromeGroup, fades with chrome automatically.
    -- Locked: reparent to display so it's independent of chrome, show on hover only.
    if lb then
        if locked then
            lb:SetParent(display)
            lb:SetShown(true)
            local targetAlpha = hovered and 1 or 0
            local currentAlpha = lb:GetAlpha()
            if math.abs(currentAlpha - targetAlpha) > 0.01 then
                local duration = addon:GetSetting("fadeDuration") or 0.3
                UIFrameFade(lb, {
                    mode = targetAlpha > currentAlpha and "IN" or "OUT",
                    timeToFade = duration,
                    startAlpha = currentAlpha,
                    endAlpha = targetAlpha,
                })
            end
        else
            lb:SetParent(display.chromeGroup)
            lb:SetShown(true)
            -- Alpha is inherited from chromeGroup automatically
        end
    end
end

function Drawer:ToggleLock()
    local cur = addon:GetSetting("locked") and true or false
    addon:SetSetting("locked", not cur)
    self:ApplyLockUI()
    -- Reflow so widget slot heights collapse or expand to match the
    -- new title-bar visibility.
    if addon.WidgetHost and addon.WidgetHost.Reflow then
        addon.WidgetHost:Reflow()
    end
    -- Re-run fade evaluation so any gating logic picks up the new state
    if self.EvaluateFade then self:EvaluateFade(true) end
end

function Drawer:SetSide(side)
    if side ~= "left" and side ~= "right" then return end
    addon:SetSetting("side", side)
    self:ApplySide()
    if self.ApplyEdgeHotZone then self:ApplyEdgeHotZone() end
end

function Drawer:SetWidth(width)
    width = tonumber(width)
    if not width then return end
    if width < MIN_WIDTH then width = MIN_WIDTH end
    if width > MAX_WIDTH then width = MAX_WIDTH end
    addon:SetSetting("width", width)
    self:ApplySide()
    -- Re-scale docked widgets to match the new width
    if addon.WidgetHost and addon.WidgetHost.Reflow then
        addon.WidgetHost:Reflow()
    end
end

---------------------------------------------------------------------------
-- Appearance - background color + frame opacity
---------------------------------------------------------------------------

function Drawer:ApplyAppearance()
    local f = self.frame; if not f then return end
    -- Background + border are driven entirely by the fade controller -
    -- they tween between the user's "full" values (backgroundOpacity /
    -- frameOpacity) and the faded values, so just re-evaluate.
    if self.EvaluateFade then self:EvaluateFade(true) end
end

---------------------------------------------------------------------------
-- Fade controller
--
-- Two inputs drive the fade state:
--   1. A 0.1s poll on the drawer frame that checks MouseIsOver(drawer)
--      and MouseIsOver(tab) - used while the drawer is expanded.
--   2. A dedicated "edge hot zone" frame anchored to the full active
--      screen edge that fires OnEnter/OnLeave when the cursor touches
--      anywhere along that edge. This way "moving to the edge" reveals
--      the tab even if your cursor is nowhere near the tab's own hitbox.
--
-- Target alphas are computed in ComputeFadeTargets() and applied to
-- displayFrame (panel) and toggleButton (tab) independently via
-- UIFrameFade. The drawer frame itself stays at alpha 1.0; we control
-- visibility through its children so the backdrop border stays clean.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Edge hot zone - full-height strip on the active screen edge
---------------------------------------------------------------------------

function Drawer:SetupEdgeHotZone()
    if self._edgeHotZone then return end
    local hz = CreateFrame("Frame", "BazUIDrawerEdgeHotZone", UIParent)
    hz:SetFrameStrata("BACKGROUND")

    -- Motion-only so clicks pass through to the game world
    if hz.SetMouseMotionEnabled then
        hz:SetMouseMotionEnabled(true)
    elseif hz.EnableMouseMotion then
        hz:EnableMouseMotion(true)
    else
        hz:EnableMouse(true)  -- fallback (may block clicks on the strip)
    end

    hz:SetScript("OnEnter", function()
        -- Locked drawers ignore edge hover (no auto-reveal).
        if addon:GetSetting("locked") then return end
        Drawer._edgeHovered = true
        Drawer:EvaluateFade(true)
    end)
    hz:SetScript("OnLeave", function()
        Drawer._edgeHovered = false
        Drawer:EvaluateFade()
    end)

    self._edgeHotZone = hz
    self:ApplyEdgeHotZone()
end

function Drawer:ApplyEdgeHotZone()
    local hz = self._edgeHotZone
    if not hz then return end
    local reveal = math.max(addon:GetSetting("edgeRevealPx") or 8, 2)
    local side = addon:GetSetting("side") or "right"

    hz:ClearAllPoints()
    if side == "left" then
        hz:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        hz:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    else
        hz:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
        hz:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
    end
    hz:SetWidth(reveal)

    -- Only relevant while the drawer is collapsed
    hz:SetShown(self.collapsed == true)
end

---------------------------------------------------------------------------
-- Chrome tween. The frame's own alpha would take the widgets with it,
-- so the interior and the edge are faded on their own instead.
---------------------------------------------------------------------------

local function Lerp(a, b, t)
    return a + (b - a) * t
end

function Drawer:InitBackdropTween()
    if self._backdropTween then return end
    local tween = CreateFrame("Frame")
    tween:Hide()
    tween._elapsed = 0
    tween:SetScript("OnUpdate", function(self, dt)
        self._elapsed = self._elapsed + dt
        local dur = math.max(self._duration or 0.3, 0.01)
        local t = math.min(self._elapsed / dur, 1)
        local f = Drawer.frame
        if f then
            local bg = Lerp(self._fromBg, self._toBg, t)
            local border = Lerp(self._fromBorder, self._toBorder, t)
            BazUI.Skin.Theme.SetFlatPanelAlpha(f, bg, border)
        end
        if t >= 1 then self:Hide() end
    end)
    self._backdropTween = tween
end

function Drawer:TweenBackdropTo(bgTarget, borderTarget, duration)
    local f = self.frame
    if not f or not self._backdropTween then return end
    local _, _, _, curBg = f:GetBackdropColor()
    local _, _, _, curBorder = f:GetBackdropBorderColor()
    local tween = self._backdropTween
    tween._fromBg = curBg or 0
    tween._fromBorder = curBorder or 1
    tween._toBg = bgTarget
    tween._toBorder = borderTarget
    tween._duration = duration or 0.3
    tween._elapsed = 0
    tween:Show()
end

---------------------------------------------------------------------------
-- Fade controller setup + polling
---------------------------------------------------------------------------

function Drawer:SetupFadeController()
    local f = self.frame; if not f then return end

    -- Safety: pin the non-chrome children at full alpha so no stale state
    -- from earlier versions of the fade controller can make widgets fade.
    f.displayFrame:SetAlpha(1.0)
    if f.widgetHost then f.widgetHost:SetAlpha(1.0) end

    self:InitBackdropTween()
    self._fadeState = { bg = nil, border = nil, tab = nil, chrome = nil }
    self._fadeTimer = nil

    local poller = CreateFrame("Frame", nil, f)
    self._fadePoller = poller
    poller._elapsed = 0
    local POLL_INTERVAL = 0.1

    poller:SetScript("OnUpdate", function(_, dt)
        poller._elapsed = poller._elapsed + dt
        if poller._elapsed < POLL_INTERVAL then return end
        poller._elapsed = 0
        Drawer:EvaluateFade(false)
    end)

    self:EvaluateFade(true)
end

---------------------------------------------------------------------------
-- Target computation
--
-- Returns (bgTarget, borderTarget, tabTarget) - the three chrome elements
-- that fade together. Widgets (inside the widget host) are NOT fade
-- targets: they always stay at full alpha so the content is always
-- readable even when the drawer chrome has faded down.
---------------------------------------------------------------------------

function Drawer:ComputeFadeTargets()
    local bgBase    = addon:GetSetting("backgroundOpacity") or 0.9
    local frameBase = addon:GetSetting("frameOpacity")      or 1.0
    local fadedA    = addon:GetSetting("fadedOpacity")      or 0.3

    local function FullState()
        return bgBase, frameBase, frameBase
    end

    local function FadedState()
        -- Scale the background down proportionally so a user with
        -- bgBase < 1 still gets a relative fade.
        local bgFaded = bgBase * (fadedA / math.max(frameBase, 0.01))
        return bgFaded, fadedA, fadedA
    end

    -- Locked drawers always return the faded state - hover is ignored
    -- for the backdrop/border so the drawer never un-fades on mouseover.
    -- (The lock icon's hover visibility is handled separately in
    -- ApplyLockUI, and docked widget content still stays at full alpha.)
    if addon:GetSetting("locked") then
        return FadedState()
    end

    if not addon:GetSetting("fadeEnabled") then return FullState() end
    if addon:GetSetting("disableFadeInCombat") and InCombatLockdown() then
        return FullState()
    end

    local hovered = Drawer:IsHovered()
    if hovered then return FullState() end

    if self.collapsed then
        if self._edgeHovered then return FullState() end
        local fadeTab = addon:GetSetting("fadeTabWhenClosed")
        if fadeTab == false then return FullState() end
        -- Panel doesn't matter visually (display is hidden), but we keep
        -- the bg/border fade targets consistent so re-expanding is smooth.
        local bg, border, _ = FadedState()
        return bg, border, fadedA
    end

    -- Expanded and not hovered > fade chrome
    return FadedState()
end

-- Evaluate current state and transition if needed. `force` bypasses the
-- delay timer so setting changes take effect immediately.
function Drawer:EvaluateFade(force)
    local f = self.frame; if not f then return end

    -- Refresh the lock icon atlas and chrome visibility (but NOT the
    -- lock fade - that's handled inside Apply so it shares the delay).
    self:ApplyLockUI(true)

    local bgTarget, borderTarget, tabTarget = self:ComputeFadeTargets()
    -- The title-bar chrome (label + count + info) uses the same target
    -- as the backdrop border and tab so all drawer chrome fades together.
    local chromeTarget = borderTarget
    local state = self._fadeState
    local duration = addon:GetSetting("fadeDuration") or 0.3

    -- Determine direction: "going up" means any chrome element is becoming
    -- more visible. Fade-in is immediate; fade-out waits for fadeDelay.
    local goingUp =
        (bgTarget    >= (state.bg     or 0)) and
        (borderTarget >= (state.border or 0)) and
        (tabTarget    >= (state.tab    or 0)) and
        (chromeTarget >= (state.chrome or 0))

    local function Apply()
        if self._fadeTimer then self._fadeTimer:Cancel(); self._fadeTimer = nil end

        if state.bg ~= bgTarget or state.border ~= borderTarget then
            self:TweenBackdropTo(bgTarget, borderTarget, duration)
            state.bg = bgTarget
            state.border = borderTarget
        end

        if state.tab ~= tabTarget then
            local tab = f.toggleButton
            UIFrameFade(tab, {
                mode = (tabTarget > (tab:GetAlpha() or 1)) and "IN" or "OUT",
                timeToFade = duration,
                startAlpha = tab:GetAlpha() or 1,
                endAlpha = tabTarget,
            })
            -- Fade the tab strip in sync
            if Drawer._tabStrip then
                UIFrameFade(Drawer._tabStrip, {
                    mode = (tabTarget > (Drawer._tabStrip:GetAlpha() or 1)) and "IN" or "OUT",
                    timeToFade = duration,
                    startAlpha = Drawer._tabStrip:GetAlpha() or 1,
                    endAlpha = tabTarget,
                })
            end
            state.tab = tabTarget
        end

        -- Title bar chrome (label + count + info button)
        local chrome = f.displayFrame and f.displayFrame.chromeGroup
        if chrome and state.chrome ~= chromeTarget then
            UIFrameFade(chrome, {
                mode = (chromeTarget > (chrome:GetAlpha() or 1)) and "IN" or "OUT",
                timeToFade = duration,
                startAlpha = chrome:GetAlpha() or 1,
                endAlpha = chromeTarget,
            })
            state.chrome = chromeTarget
        end

        -- Lock button: when unlocked, it's parented to chromeGroup so
        -- it fades automatically with the chrome. When locked, ApplyLockUI
        -- handles its visibility via hover detection.

        -- Widget slot title bars and backgrounds (per-widget settings,
        -- with global overrides). These aren't tweened per-slot - they
        -- snap to the current chrome target because the drawer's own
        -- backdrop/chrome is already smoothly animating to it.
        local fullA = addon:GetSetting("frameOpacity") or 1.0
        if addon.WidgetHost and addon.WidgetHost.ApplyFadeTargets then
            addon.WidgetHost:ApplyFadeTargets(chromeTarget, fullA)
        end
    end

    if force or goingUp then
        Apply()
    else
        if not self._fadeTimer then
            local delay = addon:GetSetting("fadeDelay") or 1.0
            self._fadeTimer = C_Timer.NewTimer(delay, function()
                self._fadeTimer = nil
                local b2, bd2, t2 = self:ComputeFadeTargets()
                local c2 = bd2
                if  b2  <= (state.bg     or 1)
                and bd2 <= (state.border or 1)
                and t2  <= (state.tab    or 1)
                and c2  <= (state.chrome or 1) then
                    bgTarget, borderTarget, tabTarget, chromeTarget = b2, bd2, t2, c2
                    Apply()
                end
            end)
        end
    end
end

---------------------------------------------------------------------------
-- Accessors used by the widget host
---------------------------------------------------------------------------

function Drawer:GetHost()
    return self.frame and self.frame.widgetHost or nil
end

function Drawer:SetWidgetCount(n)
    if self.frame and self.frame.displayFrame and self.frame.displayFrame.countLabel then
        self.frame.displayFrame.countLabel:SetText(tostring(n or 0))
    end
end
