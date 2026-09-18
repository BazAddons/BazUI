-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: SecureActionPopup
--
-- Generic primitive for "popup grid of secure action buttons" - the
-- chrome + layout + secure right-click-toggle wiring used by BazBars
-- flyouts, intended to be reused by any future Baz addon that needs a
-- popup whose cells cast spells / use items / fire macros.
--
-- Bars' flyouts are the consumer this was written for; anything else
-- that needs a popup of castable cells can use it without knowing
-- what a flyout is.
--
-- The primitive is domain-agnostic: it knows nothing about flyouts,
-- spells, or BazBars' Action registry. Consumers pass cell *data* (an
-- opaque list) plus callbacks for "apply this cell's secure attributes",
-- "icon for cell N", "cell N was clicked", and "something was dropped
-- on cell N". The popup handles:
--
--   * The suite's flat chrome around the grid (colors overridable
--     per-popup)
--   * Grid layout from rows × cols, with extra cells filling remaining
--     positions in row-major order
--   * Direction-aware anchoring relative to the trigger button (UP /
--     DOWN / LEFT / RIGHT - the popup pops out *away* from the trigger
--     in the given direction)
--   * Secure right-click toggle on the trigger, through a hidden
--     proxy button, so the trigger needs no template of its own
--   * Auto-hide when the cursor leaves both trigger and popup
--   * Combat-safe: cells stay shown if they're already shown when
--     combat starts, and any rebuilds defer until PLAYER_REGEN_ENABLED
--
-- Public API:
--   BazUI:CreateSecureActionPopup(opts) -> popup frame
--   popup:Configure(opts)              -- updates direction/grid/cells
--   popup:Show() / popup:Hide()        -- normal frame methods. The popup
--                                         parents secure cells, so WoW
--                                         treats it as protected: only
--                                         call these out of combat.
--   popup:SafeHide()                   -- Hide() that defers to
--                                         PLAYER_REGEN_ENABLED in combat.
--                                         Hide-on-cast runs in the secure
--                                         environment and works mid-combat;
--                                         click-outside uses SafeHide.
--
-- opts shape:
--   {
--     parent       = <Button>,         -- the trigger button (REQUIRED).
--                                      -- No template requirement: the
--                                      -- toggle goes through a hidden
--                                      -- proxy and the trigger's own
--                                      -- type2/clickbutton2, because
--                                      -- mixing SecureHandlerClick-
--                                      -- Template into a SecureAction-
--                                      -- Button would override its
--                                      -- OnClick and break every cast
--                                      -- on the bar. See WireSecureToggle.
--     toggleButton = "RightButton",    -- which mouse button on trigger
--                                      -- toggles the popup. nil disables
--                                      -- secure auto-toggle (consumer
--                                      -- shows/hides manually).
--     toggleShift  = false,            -- if true, only toggle when shift
--                                      -- is held during the click.
--     direction    = "UP",             -- UP / DOWN / LEFT / RIGHT
--     rows         = 1,
--     cols         = 6,
--     cells        = { ... },          -- opaque list of cell data
--     cellSize     = 36,
--     cellSpacing  = 4,
--     padding      = 6,
--
--     applyCell    = function(cellBtn, cellIndex, cellData) end,
--                                      -- set type/spell/item/etc. on
--                                      -- the secure cell button. Called
--                                      -- out-of-combat only.
--     iconForCell  = function(cellData) -> textureID|texturePath end,
--     countForCell = function(cellData) -> string|nil end,
--                                      -- stack count or charges, drawn
--                                      -- in the cell's bottom corner
--     onCellClick  = function(cellIndex, cellData, mouseBtn, popup) end,
--                                      -- fires from PostClick (insecure)
--                                      -- after the secure cast.
--     onCellDrag   = function(cellIndex, popup) end,
--                                      -- fires from OnReceiveDrag.
--     emptyIcon    = textureID,        -- shown for cells with nil data
--     hideOnCast   = true,             -- auto-hide popup after a click
--     chrome       = {                 -- color overrides; omit for the
--       bgColor   = { r, g, b, a },    -- suite's own panel colors
--       edgeColor = { r, g, b, a },
--     },
--   }
---------------------------------------------------------------------------

BazUI = BazUI or {}

local DEFAULT_CELL_SIZE    = 36
local DEFAULT_CELL_SPACING = 4
local DEFAULT_PADDING      = 6

-- Hide from insecure code. The popup is the parent of SecureActionButton
-- cells, which makes it a protected frame: Hide() from addon code in
-- combat raises ADDON_ACTION_BLOCKED. Defer until combat ends instead.
-- The secure right-click toggle is unaffected and still closes the
-- popup instantly mid-combat (hardware click -> secure snippet).
local function SafeHide(popup)
    if InCombatLockdown() then
        popup._hidePending = true
        popup:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    popup:Hide()
end

-- Forward-declared: defined with the secure toggle code below, but the
-- cells need the proxy as their wrap-script header at creation time.
local GetOrCreateProxy

-- Popups stay open until the user explicitly dismisses them: clicking a
-- cell (hideOnCast), right-clicking the trigger again (toggle), or
-- clicking somewhere outside both the popup and trigger. Hover-leaving
-- on its own no longer dismisses - the user pointed out that the old
-- auto-hide-on-leave fired the moment the cursor crossed the gap from
-- trigger to popup, which read as "the popup closed instantly".

-- The popup wears the suite's flat chrome, the same interior and
-- one-pixel gold edge as the tooltips and every panel. Consumers can
-- override either color; there is no nine-slice to swap because the
-- theme draws the frame itself.
local Theme = BazUI.Skin and BazUI.Skin.Theme

---------------------------------------------------------------------------
-- Direction helpers
---------------------------------------------------------------------------

local function AnchorFor(direction)
    -- Returns (popupAnchor, parentAnchor, xOff, yOff) such that the
    -- popup sits *away* from the parent in the given direction with
    -- a small gap.
    if direction == "DOWN"  then return "TOP",    "BOTTOM", 0,  -4 end
    if direction == "LEFT"  then return "RIGHT",  "LEFT",  -4,   0 end
    if direction == "RIGHT" then return "LEFT",   "RIGHT",  4,   0 end
    return "BOTTOM", "TOP", 0, 4 -- default UP
end

---------------------------------------------------------------------------
-- Cell construction
---------------------------------------------------------------------------

local cellSerial = 0

local function CreateCell(popup, index)
    cellSerial = cellSerial + 1
    local btn = CreateFrame("Button",
        "BazUISecureActionPopupCell" .. cellSerial,
        popup, "SecureActionButtonTemplate")
    btn:RegisterForClicks("AnyUp", "LeftButtonDown", "RightButtonDown")
    btn:RegisterForDrag("LeftButton")

    -- Hide-on-cast runs in the secure environment so it works in combat:
    -- the popup is protected (it parents these secure cells), so an
    -- insecure Hide() after a mid-combat cast would be blocked. The
    -- pre-body returns a message only so the post-body runs; the post-
    -- body hides on the up-click unless this click is a drop (PreClick
    -- marks those, out of combat only) or hideOnCast is off. The header
    -- is the popup's secure toggle proxy, which carries the popup ref.
    if BazUI.SecureSnippetsUsable() then
        SecureHandlerWrapScript(btn, "OnClick", GetOrCreateProxy(popup), [[
            return nil, "click"
        ]], [[
            if down then return end
            if self:GetAttribute("bazDropPending") then return end
            local popup = owner:GetFrameRef("bazPopup")
            if popup and popup:IsShown() and popup:GetAttribute("bazHideOnCast") then
                popup:Hide()
            end
        ]])
    else
        -- No snippets on this client. Out of combat the popup is an
        -- ordinary frame and can be hidden from a plain handler; in
        -- combat it parents secure cells and cannot, so it stays up
        -- until the cursor leaves it.
        btn:HookScript("PostClick", function(self, _, down)
            if down or InCombatLockdown() then return end
            if self:GetAttribute("bazDropPending") then return end
            if popup:IsShown() and popup:GetAttribute("bazHideOnCast") then
                popup:Hide()
            end
        end)
    end

    btn.icon = btn:CreateTexture(nil, "BACKGROUND")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)

    -- Standard action-button border so it visually matches BazBars'
    -- own slots and Blizzard's spellbook entries.
    btn.border = btn:CreateTexture(nil, "OVERLAY")
    btn.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    btn.border:SetTexCoord(0.18, 0.82, 0.18, 0.82)
    btn.border:SetVertexColor(0.55, 0.45, 0.25, 1)
    btn.border:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
    btn.border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)

    -- Stack counts, in the corner a bar slot puts them, so a stack of
    -- reagents in a flyout reads the same as one on the bar.
    btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.count:SetJustifyH("RIGHT")
    btn.count:SetPoint("BOTTOMRIGHT", -3, 3)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    btn.highlight:SetBlendMode("ADD")

    btn._cellIndex = index
    btn._popup = popup

    btn:HookScript("OnEnter", function(self)
        if self._popup and self._popup._opts.onCellEnter then
            self._popup._opts.onCellEnter(self._cellIndex, self._cellData, self)
        end
    end)
    btn:HookScript("OnLeave", function()
        GameTooltip_Hide()
    end)
    -- Drop-with-click protocol. SAB's click dispatcher fires on mouse
    -- down for the cell's secure type/spell attribute - if the cursor
    -- has contents at that moment, SAB consumes the click trying to
    -- (silently) cast, and OnReceiveDrag never fires. Same pattern
    -- BazBars Bar.lua uses for its slots: PreClick stashes the type
    -- when cursor has contents so SAB has nothing to dispatch, then
    -- PostClick manually triggers the drop callback on the up event.
    btn:HookScript("PreClick", function(self)
        if not self._popup then return end
        if InCombatLockdown() then return end
        if GetCursorInfo() then
            self._stashedType = self:GetAttribute("type") or false
            self:SetAttribute("type", nil)
            -- Tell the secure hide-on-cast wrap this click is a drop.
            self:SetAttribute("bazDropPending", true)
        end
    end)

    -- PostClick fires twice for cells (down-click and up-click) because
    -- they're registered for both events. Acting on the down-click
    -- would hide the popup the moment the user presses the mouse,
    -- which kills drag-out: by the time OnDragStart is ready to pick
    -- up the cell, the popup is already gone. Only react to the up
    -- event so a drag (whose up never fires on the original cell)
    -- leaves the popup open.
    btn:HookScript("PostClick", function(self, mouseButton, down)
        if down then return end
        if not self._popup then return end
        local opts = self._popup._opts

        -- Drop path: cursor has contents at click time -> trigger the
        -- drag callback as if OnReceiveDrag had fired, then bail. The
        -- stashed type is irrelevant now since the cell is being
        -- replaced; the next applyCell will set the right attributes.
        if self._stashedType ~= nil then
            self._stashedType = nil
            if not InCombatLockdown() then
                self:SetAttribute("bazDropPending", nil)
            end
            if GetCursorInfo() and opts.onCellDrag then
                opts.onCellDrag(self._cellIndex, self._popup)
            end
            return
        end

        if opts.onCellClick then
            opts.onCellClick(self._cellIndex, self._cellData, mouseButton, self._popup)
        end
        -- The secure OnClick wrap has normally hidden the popup by now;
        -- this is the fallback for anything that slipped past it.
        if opts.hideOnCast ~= false and self._popup:IsShown() then
            SafeHide(self._popup)
        end
    end)
    btn:SetScript("OnReceiveDrag", function(self)
        if not self._popup then return end
        local opts = self._popup._opts
        if opts.onCellDrag then
            opts.onCellDrag(self._cellIndex, self._popup)
        end
    end)
    btn:SetScript("OnDragStart", function(self)
        if not self._popup then return end
        local opts = self._popup._opts
        if opts.onCellDragStart then
            opts.onCellDragStart(self._cellIndex, self._cellData, self._popup)
        end
    end)

    return btn
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function LayoutCells(popup)
    local opts = popup._opts
    local rows = math.max(1, opts.rows or 1)
    local cols = math.max(1, opts.cols or 1)
    local size = opts.cellSize or DEFAULT_CELL_SIZE
    local gap  = opts.cellSpacing or DEFAULT_CELL_SPACING
    local pad  = opts.padding or DEFAULT_PADDING

    local total = rows * cols
    while #popup._cells < total do
        popup._cells[#popup._cells + 1] = CreateCell(popup, #popup._cells + 1)
    end
    -- Hide leftover cells from a previous larger grid.
    for i = total + 1, #popup._cells do
        popup._cells[i]:Hide()
        popup._cells[i]:ClearAllPoints()
    end

    for i = 1, total do
        local cell = popup._cells[i]
        cell._cellIndex = i
        local r = math.floor((i - 1) / cols)
        local c = (i - 1) % cols
        cell:SetSize(size, size)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", popup, "TOPLEFT",
            pad + c * (size + gap),
            -(pad + r * (size + gap)))
        cell:Show()
    end

    local w = pad * 2 + cols * size + (cols - 1) * gap
    local h = pad * 2 + rows * size + (rows - 1) * gap
    popup:SetSize(w, h)
end

local function ApplyChrome(popup)
    local theme = Theme or (BazUI.Skin and BazUI.Skin.Theme)
    if not (theme and theme.ApplyDialog) then return end
    -- The grid floats over the bars, so it wears the dialog chrome: the
    -- suite's border rather than a one-pixel edge. A caller's edgeColor
    -- has nothing to sit on any more - the border is the border - so only
    -- the interior is still its to choose.
    local chrome = popup._opts.chrome or {}
    theme.ApplyDialog(popup, chrome.bgColor)
end

local function ApplyAnchor(popup)
    local parent = popup._opts.parent
    if not parent then return end
    local pa, ta, x, y = AnchorFor(popup._opts.direction or "UP")
    popup:ClearAllPoints()
    popup:SetPoint(pa, parent, ta, x, y)
end

---------------------------------------------------------------------------
-- Cell content refresh
---------------------------------------------------------------------------

local function ApplyCellContent(popup)
    local opts = popup._opts
    local cells = opts.cells or {}
    for i, cellBtn in ipairs(popup._cells) do
        if not cellBtn:IsShown() then break end
        local cellData = cells[i]
        cellBtn._cellData = cellData

        if opts.applyCell and not InCombatLockdown() then
            -- Clear known attributes before re-applying so stale state
            -- doesn't linger across configurations.
            cellBtn:SetAttribute("type",  nil)
            cellBtn:SetAttribute("spell", nil)
            cellBtn:SetAttribute("item",  nil)
            cellBtn:SetAttribute("macro", nil)
            cellBtn:SetAttribute("macrotext", nil)
            opts.applyCell(cellBtn, i, cellData)
        end

        local tex
        if cellData and opts.iconForCell then
            tex = opts.iconForCell(cellData)
        end
        if not tex then tex = opts.emptyIcon end
        if tex then
            cellBtn.icon:SetTexture(tex)
            cellBtn.icon:Show()
        else
            cellBtn.icon:Hide()
        end

        local count
        if cellData and opts.countForCell then count = opts.countForCell(cellData) end
        cellBtn.count:SetText(count or "")
    end
end

---------------------------------------------------------------------------
-- Click-outside dismissal
--
-- GLOBAL_MOUSE_UP (not _DOWN) is the right signal for this:
--   * MOUSE_DOWN fires before pickup handlers run - mounts, in
--     particular, only set the cursor on OnDragStart (after the mouse
--     moves), so even a one-frame defer after MOUSE_DOWN sees an
--     empty cursor and dismisses the popup mid-drag.
--   * MOUSE_UP fires only on actual button release. During an in-
--     progress drag (button held, item on cursor) UP doesn't fire,
--     so the popup stays open the entire drag. When UP eventually
--     fires the cursor either still has contents (drop landed nowhere
--     - leave open) or is empty (clean click-outside - dismiss).
-- Registered only while the popup is shown.
---------------------------------------------------------------------------

local function MouseIsOver(frame)
    return frame and frame.IsMouseOver and frame:IsMouseOver()
end

local function HandleGlobalMouseUp(popup)
    -- Sticky mode pins the popup open regardless of where the user
    -- clicks - used when the config form is open and field changes
    -- (slider clicks, dropdown picks) would otherwise be read as
    -- "click outside" and dismiss the flyout that's serving as a live
    -- preview. The consumer flips this off when the form closes.
    if popup._sticky then return end
    if MouseIsOver(popup) then return end
    if MouseIsOver(popup._opts.parent) then return end
    if GetCursorInfo and GetCursorInfo() then return end -- mid-drag
    SafeHide(popup)
end

---------------------------------------------------------------------------
-- Secure right-click toggle on the trigger
---------------------------------------------------------------------------

-- The toggle snippet runs on the proxy button, not the trigger. The
-- proxy is hidden, parented to UIParent, and inherits SecureHandler-
-- ClickTemplate so its OnClick natively fires the _onclick snippet in
-- the secure environment.
local TOGGLE_SNIPPET = [[
    local popup = self:GetFrameRef("bazPopup")
    if not popup then return end
    if popup:IsShown() then
        popup:Hide()
    else
        popup:Show()
    end
]]

-- We *cannot* mix SecureHandlerClickTemplate into the trigger button -
-- it would override SecureActionButtonTemplate's OnClick handler and
-- break every cast on the bar. We also can't SecureHandlerWrapScript
-- the trigger directly: SAB's OnClick dispatcher sits at a different
-- layer and the wrap silently fails to fire on right-click.
--
-- Canonical pattern instead: SAB's type="click" attribute. We create a
-- per-popup hidden proxy button (SecureHandlerClickTemplate, so its
-- OnClick natively runs the snippet), wire the trigger so type2="click"
-- + clickbutton=<proxy>. On right-click, SAB calls proxy:Click(),
-- which fires the snippet, which toggles the popup. Works in combat,
-- doesn't conflict with the trigger's existing OnClick dispatch.
local proxySerial = 0

GetOrCreateProxy = function(popup)
    if popup._toggleProxy then return popup._toggleProxy end
    proxySerial = proxySerial + 1
    local proxy = CreateFrame("Button",
        "BazUISecureActionPopupProxy" .. proxySerial,
        UIParent, "SecureHandlerClickTemplate")
    proxy:Hide()
    proxy:SetFrameRef("bazPopup", popup)
    proxy:SetAttribute("_onclick", TOGGLE_SNIPPET)
    popup._toggleProxy = proxy
    return proxy
end

local function WireSecureToggle(popup)
    local opts = popup._opts
    local parent = opts.parent
    if not parent then return end
    if not opts.toggleButton then return end
    if not parent.SetAttribute then return end

    -- Without snippets the proxy is useless: clicking it raises inside
    -- Blizzard's compiler. The trigger is our own button, so a plain
    -- PostClick does the toggle out of combat, which is when the popup
    -- can legally be shown anyway.
    if not BazUI.SecureSnippetsUsable() then
        if parent._bazPopupToggleHooked then return end
        parent._bazPopupToggleHooked = true
        local wanted = opts.toggleButton
        parent:HookScript("PostClick", function(self, button, down)
            if down or button ~= wanted or InCombatLockdown() then return end
            if popup:IsShown() then popup:Hide() else popup:Show() end
        end)
        return
    end

    local proxy = GetOrCreateProxy(popup)
    proxy:SetFrameRef("bazPopup", popup)

    if opts.toggleButton == "RightButton" then
        parent:SetAttribute("type2", "click")
        parent:SetAttribute("clickbutton2", proxy)
        -- Some SAB builds read the unscoped clickbutton; set both so we
        -- work everywhere.
        parent:SetAttribute("clickbutton",  proxy)
    elseif opts.toggleButton == "LeftButton" then
        parent:SetAttribute("type", "click")
        parent:SetAttribute("clickbutton", proxy)
    end
end

---------------------------------------------------------------------------
-- Public factory
---------------------------------------------------------------------------

local popupSerial = 0

function BazUI:CreateSecureActionPopup(opts)
    assert(type(opts) == "table", "CreateSecureActionPopup: opts required")
    assert(opts.parent, "CreateSecureActionPopup: opts.parent required")

    popupSerial = popupSerial + 1
    local popup = CreateFrame("Frame",
        "BazUISecureActionPopup" .. popupSerial,
        opts.parent, "BackdropTemplate")
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:Hide()
    popup._cells = {}

    function popup:Configure(newOpts)
        self._opts = newOpts
        -- Read by the cells' secure hide-on-cast wrap.
        self:SetAttribute("bazHideOnCast", newOpts.hideOnCast ~= false)
        ApplyChrome(self)
        ApplyAnchor(self)
        LayoutCells(self)
        ApplyCellContent(self)
        WireSecureToggle(self)
    end

    function popup:RefreshCells()
        ApplyCellContent(self)
    end

    -- Pin the popup open across click-outside events. Used by config
    -- flows that rely on the popup as a live preview while another
    -- dialog is up.
    function popup:SetSticky(on)
        self._sticky = on and true or false
    end

    -- Hide() that insecure code may call in combat: defers to
    -- PLAYER_REGEN_ENABLED instead of tripping ADDON_ACTION_BLOCKED.
    function popup:SafeHide()
        SafeHide(self)
    end

    popup:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_UP" then
            HandleGlobalMouseUp(self)
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if self._hidePending then
                self._hidePending = nil
                self:Hide()
            end
        end
    end)
    popup:HookScript("OnShow", function(self)
        self:RegisterEvent("GLOBAL_MOUSE_UP")
        -- The toggle that opens this runs in the secure environment and
        -- never calls back into Lua, so opening the popup is the only
        -- moment we get to notice that the world changed while it was
        -- shut. Repaint the cells here or a stack count is whatever it
        -- was the last time the grid was built.
        ApplyCellContent(self)
    end)
    popup:HookScript("OnHide", function(self)
        self._hidePending = nil
        self:UnregisterEvent("GLOBAL_MOUSE_UP")
    end)

    popup:Configure(opts)
    return popup
end
