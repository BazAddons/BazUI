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
-- Resize Handle
-- Adds a drag-to-resize grip to any frame

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
--       portrait       = "Interface\\Icons\\INV_Misc_Bag_08",  -- texture path (or a fileID the client ships)
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
    --
    -- opts.textured asks for the rock-and-gold frame the talents and the
    -- character sheet come in, on any client that has it: a window that
    -- wants to look like the game's own panels rather than the flat
    -- chrome.
    local template = opts.textured and "PortraitFrameTemplate" or "PortraitFrameFlatTemplate"
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

    -- Title + portrait.
    --
    -- SetTitle is not trusted here, and this is why: the font string
    -- lives at TitleContainer.TitleText on one of these templates and at
    -- TitleText on another, and the mixin that provides SetTitle reads
    -- whichever one its own flavour expects. Where those disagree the
    -- call quietly writes to a font string nobody can see - no error, no
    -- change on screen, nothing to chase.
    --
    -- So the font string is found once, by looking in all the places it
    -- is known to live, and SetWindowTitle writes to it directly. Every
    -- window gets a title it can change afterwards rather than only at
    -- birth.
    f.bazTitleText = (f.TitleContainer and f.TitleContainer.TitleText)
        or f.TitleText
        or (globalName and _G[globalName .. "TitleText"])
        or (f.GetTitleText and f:GetTitleText())
        or nil

    function f:SetWindowTitle(text)
        if self.bazTitleText then
            self.bazTitleText:SetText(text or "")
        elseif self.SetTitle then
            self:SetTitle(text or "")
        end
    end

    if opts.title then
        f:SetWindowTitle(opts.title)
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
    -- Without them the frame is just centered and drag is ephemeral.
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

    -- ESC closes by watching the key ourselves. UISpecialFrames makes
    -- Blizzard's panel manager read our global, which taints it.
    if opts.uiSpecialFrame and globalName then
        BazUI.CloseOnEscape(f)
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
    if opts.slotAtlas or opts.slotTexture then
        btn.SlotBackground = btn:CreateTexture(nil, "BACKGROUND")
        BazUI.SetAtlasOrTexture(btn.SlotBackground, opts.slotAtlas, opts.slotTexture)
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
    -- Blizzard's ItemButton uses; vertex-tinted per quality color.
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

---------------------------------------------------------------------------
-- An arrow, pointing wherever it is asked to
--
-- One corner of the game's flyout button sheet, which is the only arrow
-- in the client that is a plain shape rather than a framed button. The
-- action bars have drawn their flyout arrows with it since the start;
-- this is that, made lendable, because a second place wanted the same
-- arrow and a second copy of the corner numbers would be a second place
-- to get them wrong.
--
-- Turning it is done by handing SetTexCoord the four corners rather than
-- by SetRotation. Rotation happens in the texture's own space and only
-- comes out true on a square, which is what stretched the sideways
-- arrows; naming the corners maps the art onto the frame directly, so a
-- quarter turn keeps its proportions.
--
-- Corner order is upper-left, lower-left, upper-right, lower-right.
---------------------------------------------------------------------------

local ARROW_FILE = "Interface\\Buttons\\ActionBarFlyoutButton"

-- The arrow's corner of the sheet, pointing up.
local AL, AR = 0.625, 0.984375
local AT, AB = 0.7421875, 0.828125

local ARROW_COORDS = {
    UP    = { AL, AT, AL, AB, AR, AT, AR, AB },
    DOWN  = { AL, AB, AL, AT, AR, AB, AR, AT },
    LEFT  = { AR, AT, AL, AT, AR, AB, AL, AB },
    RIGHT = { AL, AB, AR, AB, AL, AT, AR, AT },
}

-- Twice as wide as it is deep, which is the shape the art is drawn in.
BazUI.ARROW_LENGTH = 26

-- Point a texture, and size it to match. Hands back the width and height
-- it took, for a caller that has to make room for it.
function BazUI.SetArrowTexture(tex, direction, length)
    if not tex then return 0, 0 end

    -- Named in any case the caller likes. A direction that does not
    -- match falls back to up, which used to happen silently and drew two
    -- up arrows where an up and a down were wanted.
    direction = type(direction) == "string" and direction:upper() or "UP"
    direction = ARROW_COORDS[direction] and direction or "UP"
    length = length or BazUI.ARROW_LENGTH
    local depth = length / 2

    local sideways = (direction == "LEFT" or direction == "RIGHT")
    local w, h = length, depth
    if sideways then w, h = depth, length end

    tex:SetTexture(ARROW_FILE)
    tex:SetTexCoord(unpack(ARROW_COORDS[direction]))
    -- The art is already the colour it should be; tinting it only ever
    -- made it darker, since a texture's colour multiplies its vertex
    -- colour and grey art cannot be brightened into gold.
    tex:SetVertexColor(1, 1, 1)
    tex:SetSize(w, h)
    return w, h
end

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
