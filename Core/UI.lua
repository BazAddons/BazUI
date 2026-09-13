-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: UI Module
-- Colors, branded print, backdrop, fade, tooltip, draggable, status bar
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Color Palette
---------------------------------------------------------------------------

BazUI.colors = {
    brand       = { 0.2, 0.6, 1.0 },
    brandHex    = "3399ff",
    bg          = { 0.05, 0.05, 0.08, 0.88 },
    border      = { 0.3, 0.3, 0.35, 0.8 },
    dim         = { 0.5, 0.5, 0.55 },
    success     = { 0.3, 0.85, 0.3 },
    error       = { 1.0, 0.3, 0.3 },
    warning     = { 1.0, 0.8, 0.2 },
    white       = { 1.0, 1.0, 1.0 },
    tank        = { 0.3, 0.5, 1.0 },
    healer      = { 0.3, 0.9, 0.3 },
    dps         = { 0.9, 0.3, 0.3 },
}

-- Standard backdrop definition used across Baz addons
BazUI.backdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

---------------------------------------------------------------------------
-- Branded Print
---------------------------------------------------------------------------

local AddonMixin = BazUI.AddonMixin

function AddonMixin:Print(...)
    local displayName = self.config.title or self.name
    local msg = table.concat({...}, " ")
    print(string.format("|cff%s%s|r: %s", BazUI.colors.brandHex, displayName, msg))
end

function AddonMixin:Printf(fmt, ...)
    local displayName = self.config.title or self.name
    local msg = string.format(fmt, ...)
    print(string.format("|cff%s%s|r: %s", BazUI.colors.brandHex, displayName, msg))
end

-- Static print (not tied to an addon)
function BazUI:Print(...)
    local msg = table.concat({...}, " ")
    print(string.format("|cff%sBazUI|r: %s", self.colors.brandHex, msg))
end

---------------------------------------------------------------------------
-- Panel Factory
-- Creates a BackdropTemplate frame with the standard Baz dark theme
---------------------------------------------------------------------------

function BazUI:CreatePanel(parent, width, height)
    local frame = CreateFrame("Frame", nil, parent or UIParent, "BackdropTemplate")
    if width and height then
        frame:SetSize(width, height)
    end
    frame:SetBackdrop(self.backdrop)
    frame:SetBackdropColor(unpack(self.colors.bg))
    frame:SetBackdropBorderColor(unpack(self.colors.border))
    return frame
end

---------------------------------------------------------------------------
-- Fade Helpers
---------------------------------------------------------------------------

function BazUI:FadeIn(frame, duration, toAlpha)
    duration = duration or 0.3
    toAlpha = toAlpha or 1.0
    if not frame.bazFadeAG then
        frame.bazFadeAG = frame:CreateAnimationGroup()
        frame.bazFadeAnim = frame.bazFadeAG:CreateAnimation("Alpha")
        frame.bazFadeAG:SetScript("OnFinished", function()
            frame:SetAlpha(frame.bazFadeTarget or 1.0)
        end)
    end
    frame.bazFadeAG:Stop()
    frame.bazFadeTarget = toAlpha
    frame.bazFadeAnim:SetFromAlpha(frame:GetAlpha())
    frame.bazFadeAnim:SetToAlpha(toAlpha)
    frame.bazFadeAnim:SetDuration(duration)
    frame.bazFadeAnim:SetSmoothing("IN_OUT")
    frame.bazFadeAG:Play()
end

function BazUI:FadeOut(frame, duration, onComplete)
    duration = duration or 0.3
    if not frame.bazFadeAG then
        frame.bazFadeAG = frame:CreateAnimationGroup()
        frame.bazFadeAnim = frame.bazFadeAG:CreateAnimation("Alpha")
        frame.bazFadeAG:SetScript("OnFinished", function()
            frame:SetAlpha(frame.bazFadeTarget or 0)
            if frame.bazFadeOnComplete then
                frame.bazFadeOnComplete()
                frame.bazFadeOnComplete = nil
            end
        end)
    end
    frame.bazFadeAG:Stop()
    frame.bazFadeTarget = 0
    frame.bazFadeOnComplete = onComplete
    frame.bazFadeAnim:SetFromAlpha(frame:GetAlpha())
    frame.bazFadeAnim:SetToAlpha(0)
    frame.bazFadeAnim:SetDuration(duration)
    frame.bazFadeAnim:SetSmoothing("IN_OUT")
    frame.bazFadeAG:Play()
end

---------------------------------------------------------------------------
-- Tooltip Helper
-- Attaches tooltip show/hide to a frame
---------------------------------------------------------------------------

function BazUI:Tooltip(frame, text, anchor)
    anchor = anchor or "ANCHOR_TOP"

    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor)
        -- Support multi-line via \n
        local lines = { strsplit("\n", text) }
        GameTooltip:SetText(lines[1] or "", 1, 1, 1)
        for i = 2, #lines do
            GameTooltip:AddLine(lines[i], 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)

    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

---------------------------------------------------------------------------
-- Draggable Helper
-- Makes a frame movable with position persistence via BazUI settings
---------------------------------------------------------------------------

function BazUI:MakeDraggable(frame, opts)
    -- opts.addonName  (string) addon name for settings
    -- opts.lockKey    (string) setting key for lock state
    -- opts.posXKey    (string) setting key for X position
    -- opts.posYKey    (string) setting key for Y position

    local addonName = opts.addonName
    local lockKey = opts.lockKey
    local posXKey = opts.posXKey or "posX"
    local posYKey = opts.posYKey or "posY"

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)

    frame:SetScript("OnDragStart", function(self)
        if lockKey and BazUI:GetSetting(addonName, lockKey) then return end
        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        BazUI:SetSetting(addonName, posXKey, x - ux)
        BazUI:SetSetting(addonName, posYKey, y - uy)
    end)

    -- Restore position on show
    frame:HookScript("OnShow", function(self)
        local x = BazUI:GetSetting(addonName, posXKey)
        local y = BazUI:GetSetting(addonName, posYKey)
        if x and y then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end
    end)
end

---------------------------------------------------------------------------
-- Resize Handle
-- Adds a drag-to-resize grip to any frame
---------------------------------------------------------------------------

function BazUI:MakeResizable(frame, opts)
    -- opts.minScale    (number) minimum scale percentage (default 30)
    -- opts.maxScale    (number) max scale percentage, nil = screen cap
    -- opts.getScale    (function) returns current scale percentage
    -- opts.setScale    (function(pct)) called with new scale percentage
    -- opts.onResize    (function(pct)) called during drag
    -- opts.anchor      (string) "BOTTOMRIGHT" (default) or "BOTTOMLEFT"
    -- opts.parent      (frame) parent for the handle (default = frame)

    local minScale = opts.minScale or 30
    local anchor = opts.anchor or "BOTTOMRIGHT"
    local parent = opts.parent or frame

    local resizer = CreateFrame("Button", nil, parent)
    resizer:SetSize(16, 16)
    resizer:SetPoint(anchor, parent, anchor, anchor == "BOTTOMRIGHT" and -1 or 1, 1)
    resizer:SetFrameStrata("TOOLTIP")
    resizer:SetFrameLevel(999)
    resizer:EnableMouse(true)
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    local lastX, lastY, currentScale

    resizer:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        lastX, lastY = GetCursorPosition()
        currentScale = opts.getScale and opts.getScale() or 100

        self:SetScript("OnUpdate", function()
            local cx, cy = GetCursorPosition()
            local dx = cx - lastX
            local dy = lastY - cy
            lastX, lastY = cx, cy
            local delta = (dx + dy) * 0.05

            local maxPct = opts.maxScale
            if not maxPct then
                local w, h = frame:GetSize()
                local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
                if w > 0 and h > 0 then
                    maxPct = math.floor(math.min(screenW / w, screenH / h) * 100)
                else
                    maxPct = 200
                end
            end

            currentScale = math.max(minScale, math.min(maxPct, currentScale + delta))
            local rounded = math.floor(currentScale + 0.5)

            if opts.setScale then
                opts.setScale(rounded)
            end
            if opts.onResize then
                opts.onResize(rounded)
            end
        end)
    end)

    resizer:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        if opts.onStop then
            opts.onStop(currentScale and math.floor(currentScale + 0.5) or 100)
        end
    end)

    frame._bazResizer = resizer
    return resizer
end

---------------------------------------------------------------------------
-- Scale From Center
-- Sets a frame's scale while keeping its visual center in the same
-- screen position. Use this instead of raw frame:SetScale().
---------------------------------------------------------------------------

function BazUI:SetScaleFromCenter(frame, newScale, minScale, maxScale)
    minScale = minScale or 0.5
    maxScale = maxScale or 3.0
    newScale = math.max(minScale, math.min(maxScale, newScale))

    -- Capture center in screen pixels
    local cx, cy = frame:GetCenter()
    local oldScale = frame:GetScale()
    if cx and cy then
        cx = cx * oldScale
        cy = cy * oldScale
    end

    frame:SetScale(newScale)

    -- Re-anchor so center stays at the same screen position
    if cx and cy then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / newScale, cy / newScale)
    end

    return newScale
end

---------------------------------------------------------------------------
-- StatusBar Factory
-- Creates a styled status bar with optional label and value text
---------------------------------------------------------------------------

function BazUI:CreateStatusBar(parent, opts)
    opts = opts or {}
    local width = opts.width or 200
    local height = opts.height or 14
    local color = opts.color or { 0.3, 0.85, 0.3 }
    local bgColor = opts.bgColor or { 0.1, 0.1, 0.12, 0.8 }
    local texture = opts.texture or "Interface\\TargetingFrame\\UI-StatusBar"
    local minVal = opts.min or 0
    local maxVal = opts.max or 1

    local bar = CreateFrame("StatusBar", nil, parent or UIParent)
    bar:SetSize(width, height)
    bar:SetStatusBarTexture(texture)
    bar:SetStatusBarColor(unpack(color))
    bar:SetMinMaxValues(minVal, maxVal)
    bar:SetValue(opts.value or minVal)

    -- Background
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(bgColor))
    bar.bg = bg

    -- Optional label (left side)
    if opts.label then
        local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", 4, 0)
        label:SetText(opts.label)
        label:SetTextColor(1, 1, 1)
        bar.label = label
    end

    -- Optional value text (right side)
    if opts.valueText then
        local valText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valText:SetPoint("RIGHT", -4, 0)
        valText:SetTextColor(1, 1, 1)
        bar.valueText = valText
    end

    -- Convenience: update color
    function bar:SetColor(r, g, b)
        self:SetStatusBarColor(r, g, b)
    end

    -- Convenience: update value text
    function bar:SetValueText(text)
        if self.valueText then
            self.valueText:SetText(text)
        end
    end

    return bar
end

---------------------------------------------------------------------------
-- Portrait Window
--
-- Spawns a Frame using Blizzard's PortraitFrameFlatTemplate - the same
-- gold-ornate-bordered window with a portrait circle in the top-left
-- corner that the combined bag, character pane, and most major
-- Blizzard panels use. Centralised here so any Baz addon wanting a
-- Blizzard-styled window gets:
--
--   * Title bar with portrait icon + close button
--   * Drag-by-frame movement
--   * Optional position persistence (per-addon setting key)
--   * Optional ESC-close via UISpecialFrames
--
-- Usage:
--   local f = BazUI:CreatePortraitWindow("BazFooFrame", {
--       title          = "Foo",
--       portrait       = 5160585,            -- texture path or fileID
--       width          = 360,
--       height         = 400,
--       savedAddon     = addon,              -- BazUI addon handle for persistence
--       savedKey       = "position",         -- setting key on that addon
--       uiSpecialFrame = true,               -- register for ESC close
--       strata         = "MEDIUM",           -- optional, defaults MEDIUM
--
--       -- Optional portrait interactivity. Setting either of these
--       -- enables a click-overlay sized to the portrait circle:
--       portraitTooltip = {
--           title  = "Foo",
--           anchor = "ANCHOR_LEFT",          -- optional, defaults LEFT
--                                            -- (so the tooltip clears the
--                                            -- popup space above-right of
--                                            -- the portrait)
--           lines = {                         -- one per row
--               "|cffffd700Right-click|r to change bags",
--               "|cffffd700Drag|r to move",
--           },
--       },
--       portraitOnClick = function(self, button) ... end,
--   })
--
-- Returns the Frame ready to populate.
---------------------------------------------------------------------------

function BazUI:CreatePortraitWindow(globalName, opts)
    opts = opts or {}

    -- Retail ships the flat Dragonflight portrait chrome; Classic flavours
    -- only have the classic PortraitFrameTemplate. Same SetTitle contract,
    -- different portrait plumbing (handled below).
    local template = "PortraitFrameFlatTemplate"
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(template)) then
        template = "PortraitFrameTemplate"
    end
    local f = CreateFrame("Frame", globalName, UIParent, template)
    f:SetSize(opts.width or 360, opts.height or 400)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata(opts.strata or "MEDIUM")
    f:SetToplevel(true)
    f:RegisterForDrag("LeftButton")
    f:Hide()

    -- Title + portrait. PortraitFrameMixin adds these as methods on
    -- frames that inherit from PortraitFrameBaseTemplate.
    if opts.title and f.SetTitle then
        f:SetTitle(opts.title)
    end
    if opts.portrait and f.SetPortraitToAsset then
        f:SetPortraitToAsset(opts.portrait)
    elseif opts.portrait then
        -- Classic PortraitFrameTemplate has no SetPortraitToAsset; its
        -- portrait texture is the `portrait` parentKey on the frame.
        local tex = f.portrait or (f.GetPortrait and f:GetPortrait())
        if tex then
            if SetPortraitToTexture then SetPortraitToTexture(tex, opts.portrait) else tex:SetTexture(opts.portrait) end
        end
    end

    -- Position handling. With savedAddon + savedKey we restore the
    -- last-used position on creation and persist on drag-stop.
    -- Without them the frame is just centred and drag is ephemeral.
    local savedAddon = opts.savedAddon
    local savedKey   = opts.savedKey
    do
        f:ClearAllPoints()
        local saved = savedAddon and savedKey and savedAddon:GetSetting(savedKey) or nil
        if saved and saved.point then
            f:SetPoint(saved.point, UIParent, saved.relPoint or saved.point,
                       saved.x or 0, saved.y or 0)
        else
            f:SetPoint("CENTER")
        end
    end

    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if savedAddon and savedKey then
            local point, _, relPoint, x, y = self:GetPoint()
            savedAddon:SetSetting(savedKey, {
                point    = point,
                relPoint = relPoint,
                x        = x,
                y        = y,
            })
        end
    end)

    -- ESC closes via Blizzard's UISpecialFrames mechanism.
    if opts.uiSpecialFrame and globalName then
        tinsert(UISpecialFrames, globalName)
    end

    -- Portrait interactivity - adds a click overlay on top of the
    -- circular portrait so the consumer can hook clicks (typically
    -- right-click > menu/popup) and a tooltip on hover. Only creates
    -- the overlay when one of the two opts is set.
    -- Retail keeps the portrait in f.PortraitContainer; Classic exposes it
    -- via the mixin's GetPortrait(). Resolve whichever exists.
    local portraitTex = (f.PortraitContainer and f.PortraitContainer.portrait)
        or f.portrait or (f.GetPortrait and f:GetPortrait())
    if (opts.portraitTooltip or opts.portraitOnClick) and portraitTex then
        local hitParent = f.PortraitContainer or f
        local hit = CreateFrame("Button", nil, hitParent)
        hit:SetAllPoints(portraitTex)
        hit:SetFrameLevel((hitParent:GetFrameLevel() or 400) + 1)
        hit:RegisterForClicks("LeftButtonUp", "MiddleButtonUp", "RightButtonUp")

        if opts.portraitOnClick then
            hit:SetScript("OnClick", opts.portraitOnClick)
        end

        local tt = opts.portraitTooltip
        if tt then
            -- ANCHOR_LEFT by default: the portrait sits at the window's
            -- top-left, and consumers (e.g. BazBags) often hang an
            -- action popup above-right of the portrait via the
            -- portraitOnClick handler. Sending the tooltip RIGHT would
            -- land it on top of that popup; LEFT puts it in the empty
            -- space outside the window. Override via tt.anchor when
            -- the consumer's layout calls for something different.
            local anchor = tt.anchor or "ANCHOR_LEFT"
            hit:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, anchor)
                if tt.title and tt.title ~= "" then
                    GameTooltip:SetText(tt.title)
                end
                if tt.lines then
                    for _, line in ipairs(tt.lines) do
                        GameTooltip:AddLine(line, 1, 1, 1, true)
                    end
                end
                GameTooltip:Show()
            end)
            hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        f.PortraitClick = hit  -- expose for consumers who want to extend
    end

    return f
end

---------------------------------------------------------------------------
-- BazUI:CreateItemButton(parent, opts) -> Button
--
-- Builds a vanilla Button frame styled like Blizzard's ItemButton -
-- icon, quality border, optional slot background, optional count and
-- cooldown - without inheriting any XML template. Both
-- ItemButtonTemplate and BagSlotButtonTemplate exist in retail
-- Midnight's XML but aren't exposed as runtime CreateFrame targets,
-- so any addon trying to inherit them throws "Couldn't find inherited
-- node". Going manual here keeps consumers off that landmine and
-- gives us one styling point for the suite.
--
-- opts (all optional):
--   size       number   button edge length, default 36
--   name       string   global name (omit for anonymous)
--   slotAtlas  string   atlas drawn behind the icon (e.g. the
--                       "bags-item-slot64" empty-slot artwork) - when
--                       no item is set the slot art shows through
--   quality    bool     create a quality border child (default true)
--   count      bool     create a stack-count fontstring (default false)
--   cooldown   bool     create a CooldownFrameTemplate child (default false)
--   highlight  bool     hover highlight texture (default true)
--   pushed     bool     click-down feedback texture (default true)
--
-- Methods on the returned button:
--   :SetIconTexture(texture)  show + set icon, or hide if texture is nil
--   :SetQuality(quality, link)  tint border for uncommon+, hide otherwise
--   :SetCount(n)              show if n > 1, hide otherwise
--
-- Children exposed for direct manipulation:
--   .SlotBackground  (only if slotAtlas was set)
--   .icon
--   .IconBorder      (only if quality wasn't disabled)
--   .Count           (only if count was enabled)
--   .Cooldown        (only if cooldown was enabled)
--
-- Click + drag handlers are deliberately NOT wired here - the caller
-- attaches whatever scripts make sense (PickupBagFromSlot,
-- UseContainerItem, custom popup logic, etc.).
---------------------------------------------------------------------------

function BazUI:CreateItemButton(parent, opts)
    opts = opts or {}
    local size = opts.size or 36

    local btn = CreateFrame("Button", opts.name, parent)
    btn:SetSize(size, size)

    -- Empty-slot artwork - drawn under the icon, so when no item is
    -- assigned the slot art shows through.
    if opts.slotAtlas then
        btn.SlotBackground = btn:CreateTexture(nil, "BACKGROUND")
        btn.SlotBackground:SetAtlas(opts.slotAtlas)
        btn.SlotBackground:SetAllPoints()
    end

    -- Item icon - 1 px inset on each side leaves room for the
    -- quality border + standard ItemButton bevel pattern.
    btn.icon = btn:CreateTexture(nil, "BORDER")
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon:SetPoint("TOPLEFT",     1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.icon:Hide()

    -- Quality border (default on). WhiteIconFrame is the same texture
    -- Blizzard's ItemButton uses; vertex-tinted per quality colour.
    if opts.quality ~= false then
        btn.IconBorder = btn:CreateTexture(nil, "OVERLAY")
        btn.IconBorder:SetTexture("Interface/Common/WhiteIconFrame")
        btn.IconBorder:SetAllPoints(btn.icon)
        btn.IconBorder:Hide()
    end

    -- Stack count text (opt in).
    if opts.count then
        btn.Count = btn:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
        btn.Count:SetPoint("BOTTOMRIGHT", -3, 2)
        btn.Count:Hide()
    end

    -- Cooldown sweep (opt in). Anchored to the icon so the swirl sits
    -- inside the button's bevel rather than the full frame.
    if opts.cooldown then
        btn.Cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        btn.Cooldown:SetAllPoints(btn.icon)
    end

    if opts.highlight ~= false then
        btn:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
    end
    if opts.pushed ~= false then
        btn:SetPushedTexture("Interface/Buttons/UI-Quickslot-Depress")
    end

    function btn:SetIconTexture(texture)
        if texture then
            self.icon:SetTexture(texture)
            self.icon:Show()
        else
            self.icon:Hide()
        end
    end

    function btn:SetQuality(quality, link)
        local border = self.IconBorder
        if not border then return end
        if quality and quality > 1 then
            local r, g, b = C_Item.GetItemQualityColor(quality)
            border:SetVertexColor(r, g, b)
            border:Show()
        else
            border:Hide()
        end
    end

    function btn:SetCount(n)
        if not self.Count then return end
        if n and n > 1 then
            self.Count:SetText(n)
            self.Count:Show()
        else
            self.Count:Hide()
        end
    end

    return btn
end

---------------------------------------------------------------------------
-- Atlas fallback
--
-- Atlas names differ between Retail and the Classic flavours, and
-- Texture:SetAtlas throws on a name this client doesn't know. Set the
-- atlas when it exists, otherwise a plain texture file (or clear the
-- texture when no fallback is given). Returns true when the atlas was used.
---------------------------------------------------------------------------

function BazUI.SetAtlasOrTexture(tex, atlas, fallbackFile, useAtlasSize)
    if not tex then return false end
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas, useAtlasSize)
        return true
    end
    if fallbackFile then
        tex:SetTexture(fallbackFile)
    else
        tex:SetTexture(nil)
    end
    return false
end
