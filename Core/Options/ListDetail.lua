-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: Picker + form
--
-- Replaces the side list / detail split. A collection of editable items
-- (bars, drawers, widgets, bag categories, chat tabs, notification
-- sources) renders as one row at the top of the page:
--
--   Bar   [ Main bar               ▼ ]   [Up] [Down]   [New bar] [Reset]
--
-- with the selected item's form beneath it. It fits the Options canvas
-- at any width and scrolls with the rest of the page. The selection is
-- remembered per page on the long-lived content frame, so editing a
-- value (which re-renders the page) keeps the same item open.
--
-- Input shape is unchanged from the old list/detail: a group whose
-- args are one sub-group per item (optionally tagged with `source` for
-- grouped menus, with `_lazyDetailBuild` for deferred detail args), and
-- an optional list of execute options rendered as buttons on the row.
-- An item may carry `toggle = { name, get, set }`: an on/off switch for
-- the item itself, drawn on the picker row next to the dropdown. The
-- group may carry `itemActions`, a list of execute-shaped entries whose
-- `func` receives the selected item (Duplicate, Delete ...); they render
-- as buttons after the page's own actions. `confirmText` and
-- `disabled` may be functions of the item.
---------------------------------------------------------------------------

local O = BazUI._Options

local function ItemLabel(child)
    return child.name or child._key or "?"
end

function O.RenderPickerGroup(container, groupOpt, contentWidth, yOffset, executeArgs, stateHost)
    contentWidth = math.min(contentWidth, O.CONTENT_MAX)
    stateHost = stateHost or container:GetParent() or container
    local stateKey = "_bazPicker_" .. tostring(groupOpt._key or groupOpt.name or "items")
    local state = stateHost[stateKey]
    if type(state) ~= "table" then
        state = {}
        stateHost[stateKey] = state
    end

    local children = {}
    for _, child in ipairs(O.SortedArgs(groupOpt.args)) do
        if child.type == "group" then children[#children + 1] = child end
    end

    local hasSources = false
    for _, c in ipairs(children) do
        if c.source then hasSources = true break end
    end

    -- Selection is remembered by the item's args key, so renaming an
    -- item keeps it selected.
    local function ItemKey(child) return child._key or ItemLabel(child) end
    local function FindByKey(key)
        for _, c in ipairs(children) do
            if ItemKey(c) == key then return c end
        end
    end
    local selected = FindByKey(state.selected) or children[1]
    state.selected = selected and ItemKey(selected) or nil

    ------------------------------------------------------------------
    -- Picker row
    ------------------------------------------------------------------
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(contentWidth, O.PICKER_H)
    row:SetPoint("TOPLEFT", container, "TOPLEFT", O.PAD, yOffset)

    local label = row:CreateFontString(nil, "OVERLAY", O.LABEL_FONT)
    label:SetPoint("LEFT", O.ROW_PAD, 0)
    label:SetText(groupOpt.pickerLabel or "Select")
    label:SetTextColor(unpack(O.TEXT_DESC))

    -- Buttons on the right: move arrows (when the page supports
    -- ordering) then the page's own actions (Create, Reset ...).
    local rightEdge = row
    local rightX = -O.ROW_PAD
    local function AddButton(text, width, onClick, danger)
        local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btn:SetSize(width, 22)
        btn:SetPoint("RIGHT", rightEdge, rightEdge == row and "RIGHT" or "LEFT", rightX, 0)
        btn:SetText(text)
        local fs = btn:GetFontString()
        if fs then
            fs:SetFontObject("GameFontHighlightSmall")
            if danger then fs:SetTextColor(1, 0.45, 0.45) end
        end
        btn:SetScript("OnClick", onClick)
        rightEdge, rightX = btn, -6
        return btn
    end

    -- Page actions (Create, Reset ...) then the group's item actions,
    -- which act on the selected item.
    local actions = {}
    for _, exec in ipairs(executeArgs or {}) do actions[#actions + 1] = { exec = exec } end
    for _, act in ipairs(groupOpt.itemActions or {}) do actions[#actions + 1] = { exec = act, item = true } end
    -- Rightmost button first, so actions read left to right in order.
    for i = #actions, 1, -1 do
        local exec, forItem = actions[i].exec, actions[i].item
        local probe = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        probe:SetText(exec.name or "")
        local w = math.max(70, math.min(160, (probe:GetStringWidth() or 60) + 24))
        probe:Hide()
        local danger = exec.style == "danger" or exec.confirmStyle == "destructive"
        local function Run()
            if not exec.func then return end
            if forItem then
                if selected then exec.func(selected) end
            else
                exec.func()
            end
        end
        local btn = AddButton((exec.name or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), w, function()
            if exec.confirm and BazUI.Confirm then
                local body = exec.confirmText
                if type(body) == "function" then body = body(selected) end
                BazUI:Confirm({
                    title = exec.confirmTitle or "Confirm", body = body or "Are you sure?",
                    acceptLabel = exec.confirmAcceptLabel or "Yes", cancelLabel = exec.confirmCancelLabel or "No",
                    acceptStyle = exec.confirmStyle or "primary",
                    onAccept = Run,
                })
            else
                Run()
            end
        end, danger)
        if forItem then
            local off = not selected
            if not off and type(exec.disabled) == "function" then off = exec.disabled(selected) and true or false end
            if off then btn:Disable() end
        end
    end

    if selected and (groupOpt.onMoveUp or groupOpt.onMoveDown) then
        local idx
        for i, c in ipairs(children) do if c == selected then idx = i end end
        local down = AddButton("Down", 54, function() if groupOpt.onMoveDown then groupOpt.onMoveDown(selected) end end)
        local up   = AddButton("Up", 44, function() if groupOpt.onMoveUp then groupOpt.onMoveUp(selected) end end)
        if not idx or idx == 1 then up:Disable() end
        if not idx or idx == #children then down:Disable() end
    end

    -- The selected item's own on/off switch, if it has one.
    if selected and type(selected.toggle) == "table" then
        local tg = selected.toggle
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(O.CHECK_W, O.CHECK_W)
        cb:SetPoint("RIGHT", rightEdge, rightEdge == row and "RIGHT" or "LEFT", rightEdge == row and -O.ROW_PAD or -8, 0)
        cb:SetChecked(tg.get and tg.get() or false)
        cb:SetScript("OnClick", function(self)
            if tg.set then tg.set(nil, self:GetChecked() and true or false) end
        end)
        local tl = row:CreateFontString(nil, "OVERLAY", O.LABEL_FONT)
        tl:SetPoint("RIGHT", cb, "LEFT", -4, 0)
        tl:SetText(tg.name or "Enabled")
        rightEdge, rightX = tl, -12
    end

    -- The dropdown fills the space between the label and the buttons.
    local dd = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    dd:SetHeight(22)
    dd:SetPoint("LEFT", label, "RIGHT", 10, 0)
    dd:SetPoint("RIGHT", rightEdge, rightEdge == row and "RIGHT" or "LEFT", rightEdge == row and -O.ROW_PAD or -12, 0)
    dd:SetDefaultText(selected and ItemLabel(selected) or "Nothing to show")

    local function Select(child)
        state.selected = ItemKey(child)
        -- Re-render the whole page so the form below reflects the pick.
        if stateHost._bazRefresh then stateHost._bazRefresh() end
    end

    dd:SetupMenu(function(_, root)
        if hasSources then
            local order, bySource = {}, {}
            for _, c in ipairs(children) do
                local src = c.source or "Other"
                if not bySource[src] then bySource[src] = {}; order[#order + 1] = src end
                table.insert(bySource[src], c)
            end
            for _, src in ipairs(order) do
                root:CreateTitle(src)
                for _, c in ipairs(bySource[src]) do
                    local child = c
                    root:CreateRadio(ItemLabel(child), function() return child == selected end, function() Select(child) end)
                end
            end
        else
            for _, c in ipairs(children) do
                local child = c
                root:CreateRadio(ItemLabel(child), function() return child == selected end, function() Select(child) end)
            end
        end
    end)
    if #children == 0 then dd:Disable() end

    local rule = row:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", O.ROW_PAD, 0)
    rule:SetPoint("BOTTOMRIGHT", -O.ROW_PAD, 0)
    rule:SetColorTexture(unpack(O.HEADER_LINE))
    row:Show()
    yOffset = yOffset - O.PICKER_H - O.SPACING

    ------------------------------------------------------------------
    -- Form for the selected item
    ------------------------------------------------------------------
    if selected then
        if not selected.args and selected._lazyDetailBuild then
            selected.args = selected._lazyDetailBuild()
            selected._lazyDetailBuild = nil
        end
        if selected.args then
            -- Managed lists prepend an h1 with the item's name; the picker
            -- already shows it, so that heading is redundant here.
            for key, opt in pairs(selected.args) do
                if type(opt) == "table" and (opt.type == "h1" or opt.type == "h2") and opt.text == ItemLabel(selected) then
                    selected.args[key] = nil
                end
            end
            yOffset = O.RenderWidgets(container, selected.args, contentWidth, nil, yOffset)
        end
    elseif groupOpt.emptyText then
        local fs = container:CreateFontString(nil, "OVERLAY", O.DESC_FONT)
        fs:SetPoint("TOPLEFT", container, "TOPLEFT", O.PAD + O.ROW_PAD, yOffset)
        fs:SetWidth(contentWidth - O.ROW_PAD * 2)
        fs:SetJustifyH("LEFT")
        fs:SetText(groupOpt.emptyText)
        fs:SetTextColor(unpack(O.TEXT_DESC))
        yOffset = yOffset - (fs:GetStringHeight() or 12) - O.SPACING
    end
    return yOffset
end
