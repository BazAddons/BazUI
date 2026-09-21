-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazBars Bar Module
-- Handles bar creation, layout, Edit Mode dragging, and visual presentation

local BazBars = BazUI.Bars   -- module namespace (was the BazBars global)
local addon = BazUI:GetModule("Bars")
local Bar = {}
local Masque = LibStub and LibStub("Masque", true) -- optional dependency
addon.Bar = Bar

-- Localized globals
local pairs = pairs
local type = type
local math = math
local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local RegisterStateDriver = RegisterStateDriver
local UnregisterStateDriver = UnregisterStateDriver

local bars = {}
Bar.bars = bars

local buttonCount = 0

---------------------------------------------------------------------------
-- Bar Creation
---------------------------------------------------------------------------

function Bar:Create(barData)
    local id = barData.id
    local name = "BazUIBarsBar" .. id

    -- Main container: invisible frame, buttons float on their own
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")
    frame.barID = id
    frame.barData = barData
    frame.buttons = {}

    -- Masque group for this bar
    if Masque then
        frame.masqueGroup = Masque:Group("BazUI", "Bar " .. id)
    end

    -- Scale
    frame:SetScale(BazBars.GetBarSetting(barData, "scale") or BazBars.DEFAULT_SCALE)

    -- Create buttons grid
    Bar:CreateButtons(frame, barData)

    -- Layout buttons
    Bar:LayoutButtons(frame, barData)

    -- Endcap textures (Alliance gryphon / Horde wyvern). Has to run
    -- after LayoutButtons so the frame's height is known for sizing.
    Bar:ApplyEndcaps(frame)

    -- Position: restore saved or default
    Bar:RestorePosition(frame, barData)

    -- Register with BazUI Edit Mode framework
    Bar:RegisterEditMode(frame, barData)

    bars[id] = frame
    frame:Show()

    -- Anything can dock to an action bar: a health bar under it, a cast
    -- bar under that. The dock only needs a stable name for it.
    if BazUI.Dock then
        BazUI.Dock:RegisterHost("bar:" .. id, frame,
            barData.name or ("Bar " .. id), 10 + id)
    end

    return frame
end

---------------------------------------------------------------------------
-- Button Grid
---------------------------------------------------------------------------

function Bar:CreateSingleButton(frame, barData, r, c)
    buttonCount = buttonCount + 1
    local btnName = "BazUIBarsButton" .. buttonCount
    local btn = CreateFrame("Button", btnName, frame, "BazUIBarsButtonTemplate")
    btn:RegisterForDrag("LeftButton")
    -- Match Blizzard's ActionButton click registration exactly (see
    -- Blizzard_ActionBar/Shared/ActionButton.lua:458). Registering for
    -- AnyUp + the two main-button down events means the secure
    -- dispatcher fires correctly in both modes of the global
    -- `ActionButtonUseKeyDown` CVar:
    --   CVar=0 > dispatch on key-up, drag-drop works on plain click-drag
    --            (the mouseup is consumed by the active drag so the
    --            secure cast is never triggered)
    --   CVar=1 > dispatch on LeftButton/RightButton down, matching
    --            Blizzard's default bars. Plain click-drag would fire
    --            the spell before the drag started, so Shift+drag is
    --            required to pick up buttons - shift-type1/shift-type2
    --            are set to "noop" in Registry.lua so shift-click /
    --            shift-drag never dispatches anything.
    btn:RegisterForClicks("AnyUp", "LeftButtonDown", "RightButtonDown")

    -- Prevent the secure action from firing when the cursor has contents.
    -- Without this, clicking a button with something on the cursor would
    -- both cast/use the button's action AND trigger OnReceiveDrag. We stash
    -- the type attribute in PreClick and restore it in PostClick.
    -- Custom SecureActionButtons don't auto-fire OnReceiveDrag on click
    -- when the cursor has contents, the way Blizzard's action buttons do.
    -- We intercept the click: PreClick clears the type attribute to prevent
    -- the secure cast, and PostClick manually triggers the drop handling.
    -- A flyout being moved between slots rides on our own carry rather
    -- than the game's cursor, since the cursor cannot hold one. It
    -- counts as an incoming drop all the same.
    local function HasIncomingDrop()
        if GetCursorInfo() ~= nil then return true end
        local Flyout = addon.FlyoutHandler
        return (Flyout and Flyout.HasPending and Flyout.HasPending()) or false
    end

    -- A click is two halves, and the drop belongs to the first one.
    --
    -- The button is registered for the down event as well as the up one,
    -- so a click that places something is delivered twice. Both halves
    -- used to be treated as a drop, and both went wrong:
    --
    --   Dropping on an empty slot used the thing you dropped. The down
    --   half placed it; by the up half the cursor was empty, so nothing
    --   was stashed and the secure action fired - the action being the
    --   one just placed. Drop a healing potion on a bar, drink it.
    --
    --   Dropping on a full slot did nothing at all. The down half
    --   swapped, leaving the old action on the cursor, and the up half
    --   saw a full cursor and swapped straight back.
    --
    -- So the down half claims the drop and the up half that follows it
    -- is swallowed: no cast, no second drop. The window is there
    -- because the up may never arrive on this button - the mouse can
    -- move between the two halves - and a flag left standing would eat
    -- an honest click much later.
    local DROP_CLICK_WINDOW = 1.0

    local function Stash(self)
        self._bazStashedType = self:GetAttribute("type") or false
        self:SetAttribute("type", nil)
    end

    btn:HookScript("PreClick", function(self, _, down)
        if InCombatLockdown() then return end

        -- The up half of a click that already dropped something.
        if not down and self._bazDropAt then
            local recent = (GetTime() - self._bazDropAt) < DROP_CLICK_WINDOW
            self._bazDropAt = nil
            if recent then
                self._bazDropDispatch = false
                Stash(self)
                return
            end
        end

        if HasIncomingDrop() then
            self._bazDropDispatch = true
            self._bazDropAt = down and GetTime() or nil
            Stash(self)
        end
    end)

    btn:HookScript("PostClick", function(self)
        if InCombatLockdown() then return end

        if self._bazStashedType ~= nil then
            local stashed = self._bazStashedType
            local dispatch = self._bazDropDispatch
            self._bazStashedType, self._bazDropDispatch = nil, nil

            if dispatch and HasIncomingDrop() then
                -- ReceiveDrag sets the type itself, through
                -- SetActionFromHandler.
                addon.Button:ReceiveDrag(self)
            elseif stashed then
                -- Nothing was dropped after all, so the slot goes back
                -- to being what it was. Left nil, the button would be
                -- dead until something else set an action on it.
                self:SetAttribute("type", stashed)
            end
        end
    end)

    btn.bbBarID = barData.id
    btn.bbBarData = barData
    btn.bbRow = r
    btn.bbCol = c
    btn.action = nil
    btn.bbShowEmpty = false

    -- Start clean (template provides SlotBackground, SlotArt, NormalTexture, mask)
    btn.icon:Hide()
    btn.cooldown:Hide()
    btn.Count:SetText("")

    -- Direct event handler (avoids taint from AceEvent callbacks)
    btn:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    btn:RegisterEvent("BAG_UPDATE")
    btn:RegisterEvent("BAG_UPDATE_COOLDOWN")
    btn:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    btn:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    btn:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    btn:RegisterEvent("SPELL_UPDATE_USABLE")

    btn:SetScript("OnEvent", function(self, event, arg1)
        if not self.action then return end

        -- Route events to generic update functions; they check the action
        -- handler internally.
        if event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
            addon.Button:UpdateCooldown(self)
        elseif event == "BAG_UPDATE" then
            addon.Button:UpdateCount(self)
            addon.Button:UpdateUsable(self)
        elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
            or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
            addon.Button:UpdateGlow(self)
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            addon.Button:UpdateEquipped(self)
        elseif event == "SPELL_UPDATE_USABLE" then
            addon.Button:UpdateUsable(self)
        end
    end)

    frame.buttons[r] = frame.buttons[r] or {}
    frame.buttons[r][c] = btn

    -- Register with Masque
    if frame.masqueGroup then
        frame.masqueGroup:AddButton(btn, {
            Icon = btn.icon,
            Cooldown = btn.cooldown,
            Normal = btn.NormalTexture,
            Pushed = btn.PushedTexture,
            Highlight = btn.HighlightTexture,
            Count = btn.Count,
            HotKey = btn.HotKey,
            SlotBackground = btn.SlotBackground,
            SlotArt = btn.SlotArt,
        }, "Action")
    end

    return btn
end

function Bar:CreateButtons(frame, barData)
    for r = 1, barData.rows do
        for c = 1, barData.cols do
            Bar:CreateSingleButton(frame, barData, r, c)
        end
    end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- The bar's own panel
--
-- The same chrome the flyout popup wears, which is the suite's dialog
-- look: the shared border and a dark fill. A bar without it is what the
-- game gives you, buttons floating on the world; a bar with it reads as
-- a thing rather than a row.
--
-- A frame of its own, filling the bar exactly, sitting a level below it
-- so the buttons are always in front - and a child, so the bar's own
-- opacity, fading and hiding carry it along without anything else having
-- to know it is there.
--
-- The panel does NOT hang off the edges of the bar. It used to, by six
-- pixels, and the bar then measured smaller than it looked: the edges
-- stuck out past where the bar said it ended, and anything docked to it
-- lined up with the buttons rather than with the panel it could see.
-- Instead the bar grows to make room for it (see LayoutButtons), so the
-- frame and what you see are the same rectangle again.
---------------------------------------------------------------------------

local BACKDROP_PAD = 6

function Bar:ApplyBackground(frame)
    local bd = frame and frame.barData
    if not bd then return end
    local Theme = BazUI.Skin and BazUI.Skin.Theme
    local wanted = BazBars.GetBarSetting(bd, "background") == true

    if not wanted then
        if frame.bbBackground then frame.bbBackground:Hide() end
        return
    end
    if not Theme or not Theme.ApplyDialog then return end

    local bg = frame.bbBackground
    if not bg then
        bg = CreateFrame("Frame", nil, frame)
        bg:SetFrameLevel(math.max((frame:GetFrameLevel() or 2) - 1, 0))
        bg:SetAllPoints(frame)
        frame.bbBackground = bg
    end
    Theme.ApplyDialog(bg)
    bg:Show()
end

function Bar:LayoutButtons(frame, barData)
    local size = BazBars.DEFAULT_BUTTON_SIZE
    local spacing = BazBars.GetBarSetting(barData, "spacing") or BazBars.DEFAULT_SPACING
    local rows = barData.rows
    local cols = barData.cols
    local vertical = (barData.orientation == "vertical")

    -- The frame is exactly the buttons, with nothing spare around the
    -- outside. Anything docked to a bar takes the frame's width and sits
    -- against its edge, so a margin here would push a health bar wider
    -- than the row it is under and a couple of pixels further away than
    -- the gap asked for.
    --
    -- The one exception is the background panel, which needs room to
    -- stand clear of the outer icons. That room is added to the frame
    -- rather than taken outside it, so the bar still measures what it
    -- looks like: the panel's edge is the bar's edge, and a bar docked
    -- underneath lines up with the panel rather than with the buttons
    -- inside it. The buttons are anchored to the frame's centre, so they
    -- do not move when the room appears.
    local pad = (BazBars.GetBarSetting(barData, "background") == true)
        and BACKDROP_PAD or 0

    -- For vertical: swap how rows/cols map to screen axes
    local gridW, gridH
    if vertical then
        gridW = rows * size + (rows - 1) * spacing
        gridH = cols * size + (cols - 1) * spacing
    else
        gridW = cols * size + (cols - 1) * spacing
        gridH = rows * size + (rows - 1) * spacing
    end
    frame:SetSize(gridW + pad * 2, gridH + pad * 2)
    Bar:ApplyBackground(frame)

    local startX = -gridW / 2
    local startY = gridH / 2

    for r = 1, rows do
        for c = 1, cols do
            local btn = frame.buttons[r] and frame.buttons[r][c]
            if btn then
                btn:SetSize(size, size)
                btn:ClearAllPoints()
                local xOff, yOff
                if vertical then
                    xOff = startX + (r - 1) * (size + spacing)
                    yOff = startY - (c - 1) * (size + spacing)
                else
                    xOff = startX + (c - 1) * (size + spacing)
                    yOff = startY - (r - 1) * (size + spacing)
                end
                btn:SetPoint("TOPLEFT", frame, "CENTER", xOff, yOff)
                btn:Show()
            end
        end
    end

    -- Hide buttons outside current grid
    for r, row in pairs(frame.buttons) do
        for c, btn in pairs(row) do
            if r > rows or c > cols then
                btn:Hide()
                btn:ClearAllPoints()
            end
        end
    end
end

---------------------------------------------------------------------------
-- Edit Mode Registration (via BazUI EditMode framework)
---------------------------------------------------------------------------

function Bar:RegisterEditMode(frame, barData)
    local bd = barData

    BazUI:RegisterEditModeFrame(frame, {
        label = Bar:GetDisplayName(frame),
        addonName = "Bars",
        positionKey = false, -- BazBars manages its own barData.pos

        -- Edit Mode override: force every BazBars bar visible while
        -- Edit Mode is open, regardless of the bar's visibility macro.
        -- An "in combat only" bar (or any other conditional) is
        -- otherwise invisible the moment you try to configure it -
        -- you'd see the overlay but not the bar underneath. We
        -- unregister the state driver on enter and re-apply it on
        -- exit so the macro takes over again as soon as you leave
        -- Edit Mode. Blizzard's Edit Mode itself is gated to out-of-
        -- combat, so the :Show call here can't trigger ADDON_ACTION
        -- _BLOCKED.
        onEnter = function(f)
            -- Same protection as ApplyVisibility. Edit Mode is opened out
            -- of combat, so this normally goes through; the guard is for
            -- the case where something re-enters it during a fight.
            if not InCombatLockdown() then
                UnregisterStateDriver(f, "visibility")
            end
            f:Show()
        end,
        onExit = function(f)
            Bar:ApplyVisibility(f)
        end,

        settings = {
            -- Layout
            { type = "input", key = "customName", label = "Bar Name", section = "Layout",
              get = function() return bd.customName or "" end,
              set = function(v)
                  Bar:SetCustomName(frame, v)
              end },
            { type = "dropdown", key = "orientation", label = "Orientation", section = "Layout",
              options = { { label = "Horizontal", value = "horizontal" }, { label = "Vertical", value = "vertical" } },
              get = function() return bd.orientation or "horizontal" end,
              set = function(v)
                  bd.orientation = v
                  addon.db.profile.bars[bd.id].orientation = v
                  Bar:LayoutButtons(frame, bd)
              end },
            { type = "slider", key = "rows", label = "# of Rows", section = "Layout",
              min = 1, max = BazBars.MAX_ROWS, step = 1,
              get = function() return bd.rows end,
              set = function(v)
                  Bar:Resize(frame, v, bd.cols, bd.spacing)
              end },
            { type = "slider", key = "cols", label = "# of Icons", section = "Layout",
              min = 1, max = BazBars.MAX_COLS, step = 1,
              get = function() return bd.cols end,
              set = function(v)
                  Bar:Resize(frame, bd.rows, v, bd.spacing)
              end },
            { type = "slider", key = "scale", label = "Icon Size", section = "Layout",
              min = 50, max = 250, step = 5,
              format = function(v) return math.floor(v + 0.5) .. "%" end,
              get = function() return (BazBars.GetBarSetting(bd, "scale") or 1) * 100 end,
              set = function(v)
                  Bar:SetScale(frame, v / 100)
              end },
            { type = "slider", key = "spacing", label = "Icon Padding", section = "Layout",
              min = 0, max = 20, step = 1,
              get = function() return BazBars.GetBarSetting(bd, "spacing") end,
              set = function(v)
                  Bar:Resize(frame, bd.rows, bd.cols, v)
              end },
            { type = "nudge", section = "Layout" },

            -- Appearance
            { type = "checkbox", key = "alwaysShowButtons", label = "Always Show Buttons", section = "Appearance",
              get = function() return BazBars.GetBarSetting(bd, "alwaysShowButtons") ~= false end,
              set = function(v)
                  bd.alwaysShowButtons = v
                  addon.db.profile.bars[bd.id].alwaysShowButtons = v
                  Bar:UpdateButtonVisibility(frame)
              end },
            { type = "checkbox", key = "background", label = "Background Panel", section = "Appearance",
              desc = "Draws the suite's panel behind this bar, the same one the flyout wears.",
              get = function() return BazBars.GetBarSetting(bd, "background") == true end,
              set = function(v)
                  bd.background = v
                  addon.db.profile.bars[bd.id].background = v
                  -- The panel is inside the bar, so switching it changes
                  -- the bar's size - which anything docked to it is
                  -- measured against.
                  Bar:LayoutButtons(frame, bd)
                  if BazUI.Dock and BazUI.Dock.Relayout then BazUI.Dock:Relayout() end
              end },
            { type = "checkbox", key = "showSlotArt", label = "Show Slot Art", section = "Appearance",
              get = function() return BazBars.GetBarSetting(bd, "showSlotArt") ~= false end,
              set = function(v)
                  bd.showSlotArt = v
                  addon.db.profile.bars[bd.id].showSlotArt = v
                  Bar:UpdateSlotArt(frame)
              end },
            { type = "slider", key = "alpha", label = "Bar Opacity", section = "Appearance",
              min = 0, max = 100, step = 5,
              format = function(v) return math.floor(v + 0.5) .. "%" end,
              get = function() return (BazBars.GetBarSetting(bd, "alpha") or 1.0) * 100 end,
              set = function(v)
                  Bar:SetBarAlpha(frame, v / 100)
              end },
            { type = "checkbox", key = "mouseoverFade", label = "Mouseover Fade", section = "Appearance",
              get = function() return BazBars.GetBarSetting(bd, "mouseoverFade") or false end,
              set = function(v)
                  bd.mouseoverFade = v
                  addon.db.profile.bars[bd.id].mouseoverFade = v
                  Bar:ApplyMouseoverFade(frame)
              end },
            { type = "dropdown", key = "endcaps", label = "Side Endcaps", section = "Appearance",
              options = {
                  { label = "None",             value = "off"      },
                  { label = "Alliance Gryphons", value = "alliance" },
                  { label = "Horde Wyverns",     value = "horde"    },
              },
              get = function() return BazBars.GetBarSetting(bd, "endcaps") or "off" end,
              set = function(v)
                  bd.endcaps = v
                  addon.db.profile.bars[bd.id].endcaps = v
                  Bar:ApplyEndcaps(frame)
              end },
            { type = "checkbox", key = "endcapsAutoScale",
              label = "Scale Endcaps with Bar Height", section = "Appearance",
              get = function() return BazBars.GetBarSetting(bd, "endcapsAutoScale") or false end,
              set = function(v)
                  bd.endcapsAutoScale = v
                  addon.db.profile.bars[bd.id].endcapsAutoScale = v
                  Bar:ApplyEndcaps(frame)
              end },
            { type = "slider", key = "endcapsScale",
              label = "Endcap Size", section = "Appearance",
              min = 50, max = 200, step = 5,
              format = function(v) return math.floor(v + 0.5) .. "%" end,
              get = function()
                  return (BazBars.GetBarSetting(bd, "endcapsScale") or 1.0) * 100
              end,
              set = function(v)
                  bd.endcapsScale = v / 100
                  addon.db.profile.bars[bd.id].endcapsScale = v / 100
                  Bar:ApplyEndcaps(frame)
              end },
            { type = "dropdown", key = "visibilityMacro", label = "Bar Visible", section = "Appearance",
              options = {
                  { label = "Always Visible", value = "" },
                  { label = "In Combat", value = "[combat] show; hide" },
                  { label = "Out of Combat", value = "[nocombat] show; hide" },
                  { label = "With Target", value = "[exists] show; hide" },
                  { label = "While Shift is held", value = "[mod:shift] show; hide" },
                  { label = "Custom",                value = "custom" },
              },
              -- A macro this list has no entry for still has to show as
              -- something, and "Always Visible" would be a lie. The
              -- dropdown says Custom and the box under it says what.
              get = function()
                  local macro = bd.visibilityMacro or ""
                  for _, opt in ipairs({ "", "[combat] show; hide", "[nocombat] show; hide",
                      "[exists] show; hide", "[mod:shift] show; hide" }) do
                      if macro == opt then return macro end
                  end
                  return "custom"
              end,
              set = function(v)
                  -- Picking Custom is asking for the box, not for a
                  -- macro that literally reads "custom".
                  if v == "custom" then v = bd.visibilityMacro or "" end
                  Bar:SetVisibilityMacro(frame, v)
              end },

            -- Anything the five above cannot say.
            --
            -- This was the one thing the old Bar Options page could do
            -- that the inspector could not: the same setting, but as a
            -- box rather than a list. The page is gone, so the box is
            -- here - otherwise removing the page would have quietly
            -- taken every macro condition past those five with it.
            { type = "input", key = "visibilityMacroText", label = "Show When", section = "Appearance",
              desc = "A macro condition, such as [combat] show; hide. "
                  .. "Anything the game understands works: [stance:1], [group], "
                  .. "[stealth], [mod:shift]. Empty means always.",
              get = function() return bd.visibilityMacro or "" end,
              set = function(v)
                  Bar:SetVisibilityMacro(frame, v or "")
                  BazUI:RefreshVisibleOptions()
              end },

            -- Behavior
            { type = "checkbox", key = "locked", label = "Lock Buttons", section = "Behavior",
              get = function() return bd.locked or false end,
              set = function(v)
                  bd.locked = v
                  addon.db.profile.bars[bd.id].locked = v
              end },
            { type = "checkbox", key = "rightClickSelfCast", label = "Right-Click Self-Cast", section = "Behavior",
              get = function() return bd.rightClickSelfCast or false end,
              set = function(v)
                  bd.rightClickSelfCast = v
                  addon.db.profile.bars[bd.id].rightClickSelfCast = v
                  addon.Button:ApplySelfCast(frame)
              end },
            { type = "checkbox", key = "clickThrough", label = "Click-Through", section = "Behavior",
              get = function() return BazBars.GetBarSetting(bd, "clickThrough") or false end,
              set = function(v)
                  bd.clickThrough = v
                  addon.db.profile.bars[bd.id].clickThrough = v
                  Bar:ApplyClickThrough(frame)
              end },
        },

        actions = {
            { label = "Revert Changes", builtin = "revert" },
            { label = "Reset Position", builtin = "resetPosition" },
            { label = "Quick Keybind Mode", onClick = function() addon.Keybinds:EnterMode() end },
            { label = "Edit Button Macrotext", onClick = function()
                if addon.Dialogs then addon.Dialogs:OpenMacrotextEditor(frame) end
            end },
            { label = "BazUIBars Settings", onClick = function() addon.Options:Open() end },
            { label = "Export Bar Config", onClick = function()
                local str = addon:ExportBar(bd.id)
                if str and addon.Dialogs then addon.Dialogs:ShowExportString(str) end
            end },
            { label = "Duplicate This Bar", onClick = function()
                local newID = addon:DuplicateBar(bd.id)
                if newID then
                    addon:Print(("Duplicated Bar %d as Bar %d."):format(bd.id, newID))
                end
            end },
            { label = "|cffff4444Delete This Bar|r", onClick = function()
                -- Same confirm UX as the Options-page Delete button
                -- (which uses confirm=true on its execute opt). One
                -- click here used to wipe the bar with no undo.
                if BazUI.Confirm then
                    BazUI:Confirm({
                        title       = "Delete bar?",
                        body        = "Delete Bar " .. tostring(bd.id) .. "? This removes the bar and every button on it. Can't be undone.",
                        acceptLabel = "Delete",
                        acceptStyle = "destructive",
                        onAccept    = function()
                            BazUI:DeselectEditFrame(frame)
                            addon:DeleteBar(bd.id)
                        end,
                    })
                end
            end },
        },

        onPositionChanged = function(f) Bar:SavePosition(f) end,
    })
end

---------------------------------------------------------------------------
-- Position Save / Restore
---------------------------------------------------------------------------

function Bar:SavePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint()
    local barData = frame.barData
    barData.pos = { point = point, relPoint = relPoint, x = x, y = y }

    -- Persist to DB
    local db = addon.db.profile.bars[barData.id]
    if db then
        db.pos = barData.pos
    end
end

function Bar:RestorePosition(frame, barData)
    frame:ClearAllPoints()
    if barData.pos then
        frame:SetPoint(
            barData.pos.point or "CENTER",
            UIParent,
            barData.pos.relPoint or "CENTER",
            barData.pos.x or 0,
            barData.pos.y or 0
        )
    else
        -- Default: center of screen, stagger by bar ID
        local offsetY = (barData.id - 1) * -60
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, offsetY)
    end
end

---------------------------------------------------------------------------
-- Edit Mode (delegated to BazUI)
---------------------------------------------------------------------------

function Bar:DeselectAll()
    local sel = BazUI:GetSelectedEditFrame()
    if sel then
        BazUI:DeselectEditFrame(sel)
    end
end

---------------------------------------------------------------------------
-- Resize (change rows/cols)
---------------------------------------------------------------------------

function Bar:Resize(frame, newRows, newCols, newSpacing)
    -- Resizing the bar moves its secure child buttons, which is
    -- protected while in combat. Bail with a user-facing print so
    -- the slider drag isn't silently lost (the next setting change
    -- after combat ends will go through normally).
    if InCombatLockdown() then
        if addon and addon.Print then
            addon:Print("Cannot resize bars during combat.")
        end
        return
    end

    local barData = frame.barData
    local oldRows = barData.rows
    local oldCols = barData.cols

    barData.rows = newRows or oldRows
    barData.cols = newCols or oldCols
    barData.spacing = newSpacing or barData.spacing

    -- Create new buttons if grid expanded
    for r = 1, barData.rows do
        for c = 1, barData.cols do
            if not (frame.buttons[r] and frame.buttons[r][c]) then
                Bar:CreateSingleButton(frame, barData, r, c)
            end
        end
    end

    -- Re-layout (also hides buttons outside grid)
    Bar:LayoutButtons(frame, barData)

    -- Bar height changed; rescale endcap textures.
    Bar:ApplyEndcaps(frame)

    -- Update DB
    local db = addon.db.profile.bars[barData.id]
    if db then
        db.rows = barData.rows
        db.cols = barData.cols
        db.spacing = barData.spacing
    end
end

---------------------------------------------------------------------------
-- Scale
---------------------------------------------------------------------------

function Bar:SetScale(frame, scale)
    -- Same combat-protection story as Resize: SetScale on a parent of
    -- secure buttons is blocked during combat lockdown.
    if InCombatLockdown() then
        if addon and addon.Print then
            addon:Print("Cannot rescale bars during combat.")
        end
        return
    end
    scale = BazUI:SetScaleFromCenter(frame, scale, BazBars.MIN_SCALE, BazBars.MAX_SCALE)
    frame.barData.scale = scale
    Bar:SavePosition(frame)

    local db = addon.db.profile.bars[frame.barData.id]
    if db then
        db.scale = scale
    end
end

---------------------------------------------------------------------------
-- Bar Alpha
---------------------------------------------------------------------------

function Bar:SetBarAlpha(frame, alpha)
    alpha = math.max(0, math.min(1, alpha))
    frame.barData.alpha = alpha
    frame:SetAlpha(alpha)
    local db = addon.db.profile.bars[frame.barData.id]
    if db then
        db.alpha = alpha
    end
end

---------------------------------------------------------------------------
-- Mouseover Fade
---------------------------------------------------------------------------

function Bar:ApplyMouseoverFade(frame)
    local barData = frame.barData

    if BazBars.GetBarSetting(barData, "mouseoverFade") then
        local fadeAlpha = BazBars.GetBarSetting(barData, "mouseoverAlpha") or 0.3
        local fullAlpha = BazBars.GetBarSetting(barData, "alpha") or 1.0

        -- Start at faded alpha
        frame:SetAlpha(fadeAlpha)

        if not frame.bbFadeFrame then
            frame.bbFadeFrame = CreateFrame("Frame", nil, frame)
            frame.bbFadeFrame:SetAllPoints()
        end

        -- Animate alpha directly via OnUpdate. We deliberately avoid
        -- UIFrameFadeIn / UIFrameFadeOut here - those Blizzard helpers
        -- internally call frame:Show() to start the animation, which
        -- throws ADDON_ACTION_BLOCKED on a secure parent frame during
        -- combat (BazBars bars host SecureActionButtonTemplate buttons,
        -- so the bar itself is protected). Plain SetAlpha is not
        -- protected and works in combat without issue.
        frame.bbFadeFrame:SetScript("OnUpdate", function(_, elapsed)
            local target = frame:IsMouseOver() and fullAlpha or fadeAlpha
            local current = frame:GetAlpha()
            local diff = target - current
            if math.abs(diff) < 0.01 then
                if current ~= target then frame:SetAlpha(target) end
                return
            end
            -- Asymmetric speeds so fade-in feels snappier than fade-out,
            -- matching the original 0.2s-in / 0.3s-out timing roughly.
            local speed = (diff > 0) and 5.0 or 3.3
            frame:SetAlpha(current + diff * math.min(1, elapsed * speed))
        end)
    else
        -- Disable fade: restore full alpha, remove OnUpdate
        if frame.bbFadeFrame then
            frame.bbFadeFrame:SetScript("OnUpdate", nil)
        end
        frame.bbFadedIn = nil
        frame:SetAlpha(BazBars.GetBarSetting(barData, "alpha") or 1.0)
    end
end

---------------------------------------------------------------------------
-- Bar Display Name
---------------------------------------------------------------------------

function Bar:GetDisplayName(frame)
    local barData = frame.barData
    if barData.customName and barData.customName ~= "" then
        return barData.customName
    end
    return "BazBar " .. barData.id
end

function Bar:SetCustomName(frame, name)
    frame.barData.customName = name
    local db = addon.db.profile.bars[frame.barData.id]
    if db then
        db.customName = name
    end
    BazUI:UpdateEditModeLabel(frame, Bar:GetDisplayName(frame))
end

---------------------------------------------------------------------------
-- Destroy
---------------------------------------------------------------------------

function Bar:Destroy(id)
    local frame = bars[id]
    if not frame then return false end

    -- Unregister from Edit Mode
    BazUI:UnregisterEditModeFrame(frame)

    -- Hide and clear all buttons
    for r, row in pairs(frame.buttons) do
        for c, btn in pairs(row) do
            btn:Hide()
            btn:SetParent(nil)
        end
    end

    frame:Hide()
    frame:SetParent(nil)
    bars[id] = nil
    if BazUI.Dock then BazUI.Dock:UnregisterHost("bar:" .. id) end

    return true
end

function Bar:DestroyAll()
    for id in pairs(bars) do
        Bar:Destroy(id)
    end
    -- Clear the table in place (don't reassign, Bar.bars references it)
    wipe(bars)
end

---------------------------------------------------------------------------
-- Button Visibility & Slot Art
---------------------------------------------------------------------------

function Bar:UpdateButtonVisibility(frame)
    local showEmpty = BazBars.GetBarSetting(frame.barData, "alwaysShowButtons") ~= false
    for r, row in pairs(frame.buttons) do
        for c, btn in pairs(row) do
            if r <= frame.barData.rows and c <= frame.barData.cols then
                if btn.action or showEmpty then
                    btn:Show()
                else
                    btn:Hide()
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Click-through: when enabled, the bar's buttons stop intercepting mouse
-- events so clicks pass through to whatever's underneath (the world,
-- units, the default action bar, etc.). Buttons stay rendered - icons,
-- cooldown sweeps, range tinting, charge counts, and proc glow all still
-- work because they're driven by data, not clicks. The user just can't
-- *click* them while click-through is on.
--
-- Useful for "always-visible cooldown reference" bars where the user
-- wants to see a spell's cooldown but cast via a different bar's keybind.
---------------------------------------------------------------------------

function Bar:ApplyClickThrough(frame)
    local clickThrough = BazBars.GetBarSetting(frame.barData, "clickThrough") and true or false
    for r, row in pairs(frame.buttons) do
        for c, btn in pairs(row) do
            btn:EnableMouse(not clickThrough)
        end
    end
end

function Bar:UpdateSlotArt(frame)
    local show = BazBars.GetBarSetting(frame.barData, "showSlotArt") ~= false
    for r, row in pairs(frame.buttons) do
        for c, btn in pairs(row) do
            -- Only toggle the eagle/slot art texture
            -- Keep SlotBackground (semi-transparent fill) always visible
            if btn.SlotArt then
                btn.SlotArt:SetShown(show)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Endcaps
--
-- Optional decorative gryphon (Alliance) or wyvern (Horde) textures
-- on the left and right sides of a bar, vertically centered. Same
-- atlases Blizzard's MainActionBar uses for its native endcaps.
-- Endcaps scale with the bar height so resizing the bar keeps them
-- proportional. Lazy-created on first use; just hidden when toggled
-- off so we don't churn texture objects.
---------------------------------------------------------------------------

local ENDCAP_HEIGHT_RATIO = 1.5   -- endcap height relative to bar height
local ENDCAP_OVERLAP      = 9     -- pixels endcap overlaps onto the bar
local ENDCAP_Y_OFFSET     = 5     -- pixels endcap is shifted UP from center

function Bar:ApplyEndcaps(frame)
    if not frame then return end
    local mode = BazBars.GetBarSetting(frame.barData, "endcaps") or "off"

    if mode == "off" or not BazBars.ENDCAP_ATLASES[mode] then
        if frame.endcapLeft  then frame.endcapLeft:Hide()  end
        if frame.endcapRight then frame.endcapRight:Hide() end
        return
    end

    -- Holder frame at a high frame level so the endcap textures render
    -- ABOVE the buttons (button frames inherit a level above their
    -- parent and would otherwise occlude textures parented to the
    -- bar frame directly).
    if not frame.endcapHolder then
        local holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        holder:SetFrameLevel((frame:GetFrameLevel() or 0) + 50)
        frame.endcapHolder = holder
    end

    if not frame.endcapLeft then
        frame.endcapLeft = frame.endcapHolder:CreateTexture(nil, "OVERLAY")
    end
    if not frame.endcapRight then
        frame.endcapRight = frame.endcapHolder:CreateTexture(nil, "OVERLAY")
    end

    local atlases   = BazBars.ENDCAP_ATLASES[mode]
    local autoScale = BazBars.GetBarSetting(frame.barData, "endcapsAutoScale")
    local barH      = frame:GetHeight() or 50
    -- Scaling vs fixed: "fixed" (default) sizes the endcaps to a
    -- single button row so multi-row bars don't get giant gryphons;
    -- "auto" scales them to the full bar height for users who want
    -- the endcaps to grow with the bar. The user-scale multiplier
    -- only applies in fixed-size mode (auto-scale follows the bar
    -- and ignores the slider).
    local refH = autoScale and barH or BazBars.DEFAULT_BUTTON_SIZE
    local mult = autoScale and 1.0
        or (BazBars.GetBarSetting(frame.barData, "endcapsScale") or 1.0)
    local size = math.max(16, refH * ENDCAP_HEIGHT_RATIO * mult)

    -- Anchor to the bar frame's edges (not the holder, even though the
    -- holder is parent) so the inset is measured against the visual
    -- bar, not the holder.
    BazUI.SetAtlasOrTexture(frame.endcapLeft, atlases.left, nil, false)
    frame.endcapLeft:SetSize(size, size)
    frame.endcapLeft:ClearAllPoints()
    frame.endcapLeft:SetPoint("RIGHT", frame, "LEFT",
        ENDCAP_OVERLAP, ENDCAP_Y_OFFSET)
    frame.endcapLeft:Show()

    BazUI.SetAtlasOrTexture(frame.endcapRight, atlases.right, nil, false)
    frame.endcapRight:SetSize(size, size)
    frame.endcapRight:ClearAllPoints()
    frame.endcapRight:SetPoint("LEFT", frame, "RIGHT",
        -ENDCAP_OVERLAP, ENDCAP_Y_OFFSET)
    frame.endcapRight:Show()
end


---------------------------------------------------------------------------
-- Visibility State Driver
---------------------------------------------------------------------------

function Bar:SetVisibilityMacro(frame, macro)
    frame.barData.visibilityMacro = macro
    local db = addon.db.profile.bars[frame.barData.id]
    if db then
        db.visibilityMacro = macro
    end
    Bar:ApplyVisibility(frame)
end

-- Bars whose visibility could not be applied because a fight was on.
-- Weak-keyed: a bar deleted before combat ends is not worth remembering.
Bar.pendingVisibility = setmetatable({}, { __mode = "k" })

function Bar:ApplyVisibility(frame)
    -- Registering or clearing a state driver writes an attribute onto
    -- Blizzard's SecureStateDriverManager, which is protected in combat.
    --
    -- Reachable from Edit Mode: you can open it standing still and be
    -- attacked before you close it, and closing re-applies every bar's
    -- visibility. That is exactly how this was found.
    if InCombatLockdown() then
        Bar.pendingVisibility[frame] = true
        return
    end
    Bar.pendingVisibility[frame] = nil

    local macro = frame.barData.visibilityMacro
    -- Unregister any existing driver
    UnregisterStateDriver(frame, "visibility")

    if macro and macro ~= "" then
        -- RegisterStateDriver with "visibility" attribute natively understands "show"/"hide"
        RegisterStateDriver(frame, "visibility", macro)
    else
        -- Default: always visible
        frame:Show()
    end
end

---------------------------------------------------------------------------
-- Load all bars from DB
---------------------------------------------------------------------------

function Bar:LoadAll()
    local dbBars = addon.db.profile.bars
    if not dbBars then return end

    for id, barData in pairs(dbBars) do
        if type(barData) == "table" and barData.id then
            local frame = Bar:Create(barData)
            -- Load button assignments
            for r, row in pairs(frame.buttons) do
                for c, btn in pairs(row) do
                    addon.Button:LoadButton(btn)
                end
            end
            -- Apply settings
            Bar:ApplyVisibility(frame)
            Bar:UpdateSlotArt(frame)
            Bar:UpdateButtonVisibility(frame)
            Bar:SetBarAlpha(frame, BazBars.GetBarSetting(barData, "alpha") or 1.0)
            Bar:ApplyMouseoverFade(frame)
            Bar:ApplyClickThrough(frame)
        end
    end
end

---------------------------------------------------------------------------
-- Get bar by ID
---------------------------------------------------------------------------

function Bar:Get(id)
    return bars[id]
end

function Bar:GetAll()
    return bars
end

function Bar:GetNextID()
    local maxID = 0
    for id in pairs(addon.db.profile.bars) do
        if type(id) == "number" and id > maxID then maxID = id end
    end
    return maxID + 1
end
