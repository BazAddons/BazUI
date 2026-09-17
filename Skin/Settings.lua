-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Skin: the Skin tab
--
-- Pick a skin, or change a color and be on your own. The rows are built
-- from Theme.colors rather than written out, so a color added to the
-- theme turns up here on its own - labelled if Skins.lua has a label for
-- it, under its own name if not.
---------------------------------------------------------------------------

local Skin  = BazUI.Skin
local Theme = Skin.Theme

---------------------------------------------------------------------------
-- Rebuilding the page
--
-- Changing a color puts you on the custom skin, which the dropdown at the
-- top has to start saying. Rebuilding the page while the color picker is
-- open would pull the swatch out from under the drag that is driving it,
-- so a rebuild waits for the picker to close.
---------------------------------------------------------------------------

local refreshPending, hookedPicker = false, false

local function RefreshPage()
    refreshPending = false
    if BazUI.RefreshOptions then BazUI:RefreshOptions("BazUI-Skin") end
end

local function RefreshAfterPicker()
    local picker = _G.ColorPickerFrame
    if not (picker and picker:IsShown()) then
        RefreshPage()
        return
    end
    refreshPending = true
    if not hookedPicker then
        hookedPicker = true
        picker:HookScript("OnHide", function()
            if refreshPending then C_Timer.After(0, RefreshPage) end
        end)
    end
end

---------------------------------------------------------------------------
-- The colors, in groups
---------------------------------------------------------------------------

local function RolesByGroup()
    local labelled, byGroup = {}, {}

    for _, role in ipairs(Skin.COLOR_ROLES) do
        labelled[role.key] = true
        byGroup[role.group] = byGroup[role.group] or {}
        table.insert(byGroup[role.group], role)
    end

    -- A color the theme has that nobody has written a label for yet. It
    -- is still part of the look, so it is still editable; it just goes in
    -- under its own name.
    local unlabelled = {}
    for key, color in pairs(Theme.colors) do
        if type(color) == "table" and not labelled[key] then
            unlabelled[#unlabelled + 1] = { key = key, label = key, group = "other" }
        end
    end
    table.sort(unlabelled, function(a, b) return a.key < b.key end)
    if #unlabelled > 0 then byGroup.other = unlabelled end

    return byGroup
end

local function AddPalette(args, startOrder)
    local byGroup = RolesByGroup()
    local order = startOrder

    for _, group in ipairs(Skin.COLOR_GROUPS) do
        local roles = byGroup[group.key]
        if roles and #roles > 0 then
            args["head_" .. group.key] = {
                order = order, type = "header", name = group.label,
            }
            order = order + 1

            if group.desc then
                args["note_" .. group.key] = {
                    order = order, type = "description", name = group.desc,
                }
                order = order + 1
            end

            for _, role in ipairs(roles) do
                local key = role.key
                args["color_" .. key] = {
                    order    = order,
                    type     = "color",
                    name     = role.label,
                    desc     = role.desc,
                    hasAlpha = role.hasAlpha,
                    get      = function() return Theme.colors[key] end,
                    set      = function(_, r, g, b, a)
                        local forked = Skin.SetColor(key, r, g, b, a)
                        if forked then RefreshAfterPicker() end
                    end,
                }
                order = order + 1
            end
        end
    end

    return order
end

---------------------------------------------------------------------------
-- The fill
---------------------------------------------------------------------------

local function AddFill(args, startOrder)
    local order = startOrder

    args.fillHead = { order = order, type = "header", name = "Bars" }
    order = order + 1

    local fills = Skin.GetFills()
    local values, sorting = {}, {}
    for _, def in ipairs(fills) do
        values[def.id] = def.name
        sorting[#sorting + 1] = def.id
    end

    args.fill = {
        order   = order,
        type    = "select",
        name    = "Fill",
        desc    = "What the inside of every bar is drawn with. Gradient "
            .. "works the bar's own color up and down it rather than "
            .. "painting it evenly. If you have LibSharedMedia, everything "
            .. "it knows about is in here too.",
        values  = values,
        sorting = sorting,
        get     = function() return Skin.ActiveFill() end,
        set     = function(_, id)
            -- Only a rebuild if this was the change that put you on the
            -- custom skin, since that is the only thing on the page that
            -- another row is showing.
            if Skin.SetFill(id) then RefreshPage() end
        end,
    }

    return order + 1
end

---------------------------------------------------------------------------
-- A border band, as one row
--
-- Thickness, color and a way to take it off, side by side:
--
--   Band 2                            [-  1px  +]  [swatch]  [x]
--   the gold
--
-- A row of its own rather than three ordinary rows per band, because a
-- border of four bands would otherwise be twelve rows of settings for
-- something you are trying to look at rather than read. Built on the form
-- language's own scaffolding, so it lines up with every other row on the
-- page instead of nearly lining up.
---------------------------------------------------------------------------

local BAND_SWATCH_W, BAND_SWATCH_H = 44, 16
local STEP_W, NUM_W, REMOVE_W = 18, 30, 18

local function CreateBandWidget(parent, opt, contentWidth)
    local O = BazUI._Options
    local ctrlWidth = STEP_W * 2 + NUM_W + 14 + BAND_SWATCH_W + 10 + REMOVE_W
    local frame, h = O.BuildRow(parent, opt, contentWidth, ctrlWidth)

    local box = CreateFrame("Frame", nil, frame)
    O.AnchorControl(frame, box, ctrlWidth, 20)

    local function Band()
        return (opt.get and opt.get()) or { thickness = 1, color = { 1, 1, 1, 1 } }
    end

    -- Taking it off, at the right where a row ends.
    local remove = CreateFrame("Button", nil, box)
    remove:SetSize(REMOVE_W, REMOVE_W)
    remove:SetPoint("RIGHT", box, "RIGHT", 0, 0)
    local cross = remove:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cross:SetPoint("CENTER")
    cross:SetText("x")
    cross:SetTextColor(0.7, 0.65, 0.55)
    remove:SetScript("OnEnter", function() cross:SetTextColor(1, 0.45, 0.45) end)
    remove:SetScript("OnLeave", function() cross:SetTextColor(0.7, 0.65, 0.55) end)
    remove:SetScript("OnClick", function()
        if opt.onRemove then opt.onRemove(opt.index) end
    end)

    local swatch = O.CreateSwatch(box, BAND_SWATCH_W, BAND_SWATCH_H)
    swatch:SetPoint("RIGHT", remove, "LEFT", -10, 0)

    -- Thickness in whole pixels, stepped rather than dragged: a band is
    -- one, two or three of them, and a slider covering that range is a
    -- slider you have to aim.
    local number = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    number:SetPoint("RIGHT", swatch, "LEFT", -12, 0)
    number:SetWidth(NUM_W)
    number:SetJustifyH("CENTER")

    local function Step(label, relativeTo, dx, delta)
        local button = Theme.CreateButton(box)
        button:SetSize(STEP_W, 18)
        button:SetPoint("RIGHT", relativeTo, "LEFT", dx, 0)
        button:SetText(label)
        button:SetScript("OnClick", function()
            if opt.onThickness then
                opt.onThickness(opt.index, (tonumber(Band().thickness) or 1) + delta)
            end
            -- The page is not rebuilt for a thickness, so this row shows
            -- its own new number.
            if opt.refresh then opt.refresh() end
        end)
        return button
    end

    local plus = Step("+", number, -2, 1)
    Step("-", plus, -1, -1)

    local function Refresh()
        local band = Band()
        local c = band.color or { 1, 1, 1, 1 }
        swatch:SetColor(c[1], c[2], c[3], c[4] or 1)
        number:SetText(tostring(band.thickness or 1) .. "px")
    end

    swatch:SetScript("OnClick", function()
        local c = Band().color or { 1, 1, 1, 1 }
        O.OpenColorPicker(c[1], c[2], c[3], c[4] or 1, true, function(r, g, b, a)
            if opt.onColor then opt.onColor(opt.index, r, g, b, a) end
            Refresh()
        end)
    end)

    opt.refresh = Refresh
    frame:SetScript("OnShow", Refresh)
    Refresh()

    return frame, h
end

---------------------------------------------------------------------------
-- The border, band by band
---------------------------------------------------------------------------

local function BandLabel(index, count)
    if count == 1 then return "The only band" end
    if index == 1 then return "Band 1, against the fill" end
    if index == count then return ("Band %d, the outside edge"):format(index) end
    return ("Band %d"):format(index)
end

local function AddBorder(args, startOrder)
    local bands = Skin.GetBands()
    local order = startOrder

    args.borderHead = { order = order, type = "header", name = "Borders" }
    order = order + 1

    args.borderNote = {
        order = order, type = "description",
        name = "Every edge in the addon - a bar's, a panel's, a round "
            .. "button's - is these bands, laid one outside the next. Band 1 "
            .. "touches the fill. Take them all off and a bar is its fill and "
            .. "nothing else; add as many as you like. A band costs its "
            .. "thickness on every side, and the fill gets what is left.",
    }
    order = order + 1

    for index = 1, #bands do
        args["band" .. index] = {
            order = order,
            type  = "borderBand",
            name  = BandLabel(index, #bands),
            index = index,
            get   = function() return Skin.GetBands()[index] end,
            onColor = function(i, r, g, b, a)
                if Skin.SetBandColor(i, r, g, b, a) then RefreshAfterPicker() end
            end,
            onThickness = function(i, pixels)
                if Skin.SetBandThickness(i, pixels) then RefreshPage() end
            end,
            onRemove = function(i)
                Skin.RemoveBand(i)
                RefreshPage()
            end,
        }
        order = order + 1
    end

    if #bands == 0 then
        args.borderNone = {
            order = order, type = "description",
            name = "|cff9a8f7aNo border at all: every edge is a naked fill.|r",
        }
        order = order + 1
    end

    args.borderAdd = {
        order = order,
        type  = "execute",
        name  = #bands == 0 and "Add a border" or "Add another band",
        desc  = "Goes on the outside, as a copy of whatever is out there now.",
        func  = function()
            Skin.AddBand()
            RefreshPage()
        end,
    }

    return order + 1
end

---------------------------------------------------------------------------
-- Sharing
---------------------------------------------------------------------------

local function ExportDialog()
    local text = Skin.Export()
    if not text then return end
    BazUI:OpenCopyDialog({
        title    = "Export skin",
        subtitle = "Every color as it stands. Paste it somewhere, or hand it to somebody running BazUI.",
        content  = text,
        editable = true,
    })
end

local function ImportDialog()
    BazUI:OpenCopyDialog({
        title      = "Import skin",
        subtitle   = "Paste a skin string. It arrives as your custom skin, so nothing shipped is written over.",
        content    = "",
        acceptText = "Import",
        onAccept   = function(text)
            local ok, result = Skin.Import(text)
            if ok then
                BazUI:Print(("Skin imported: %s. Reload to repaint everything already on screen."):format(result))
                RefreshPage()
            else
                BazUI:Print("|cffff8800" .. tostring(result) .. "|r")
            end
        end,
    })
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function BuildOptions()
    local skinOrder = {}
    for _, skin in ipairs(Skin.GetSkins()) do skinOrder[#skinOrder + 1] = skin.id end

    local args = {
        intro = {
            order = 1,
            type  = "description",
            name  = "Nearly everything BazUI draws - panels, bars, borders, rings, "
                .. "plates - is a plain texture tinted by the colors below, so the "
                .. "look of the addon is this list. Change one and you are on your "
                .. "own skin; the shipped ones are never written over.",
        },
        skin = {
            order  = 2,
            type   = "select",
            name   = "Skin",
            desc   = "Skins added by other addons appear here too.",
            values = function()
                local values = {}
                for _, skin in ipairs(Skin.GetSkins()) do
                    values[skin.id] = skin.author
                        and ("%s - %s"):format(skin.name, skin.author)
                        or skin.name
                end
                return values
            end,
            -- Registration order rather than alphabetical, so BazUI's own
            -- is first and yours is second however either is named.
            sorting = skinOrder,
            get = function() return Skin.ActiveSkin() end,
            set = function(_, id)
                Skin.ApplySkin(id)
                RefreshPage()
                BazUI:PromptReload("Colors already painted onto something keep the old skin until the interface reloads.")
            end,
        },
        about = {
            order = 3,
            type  = "description",
            name  = "",
        },
        exportBtn = {
            order = 4,
            type  = "execute",
            name  = "Export",
            desc  = "The colors as a string you can pass on.",
            func  = ExportDialog,
        },
        importBtn = {
            order = 5,
            type  = "execute",
            name  = "Import",
            desc  = "Paste somebody else's.",
            func  = ImportDialog,
        },
        resetBtn = {
            order = 6,
            type  = "execute",
            name  = "Reset colors",
            desc  = "Back to what the skin you are on shipped with.",
            func  = function()
                Skin.ResetColors()
                RefreshPage()
                BazUI:PromptReload("Reload to repaint everything already on screen.")
            end,
        },
    }

    local skin = Skin.GetSkin(Skin.ActiveSkin())
    if skin then
        args.about.name = skin.desc or ""
    end

    local order = AddFill(args, 10)
    order = AddBorder(args, order + 10)
    order = AddPalette(args, order + 10)

    args.reloadNote = {
        order = order,
        type  = "description",
        name  = "The fill and the borders redraw the moment you change "
            .. "one. A color takes "
            .. "effect as things are drawn, so most of the addon follows at "
            .. "once and anything already on screen holds its old color until "
            .. "you reload. Two things a skin does not cover yet: "
            .. "this settings window, which has a palette of its own, and the "
            .. "art - the minimap's frame and the face BazUI ships. Those travel "
            .. "with a skin written as an addon, since a picture cannot be pasted "
            .. "into a text box.",
    }

    return { name = "Skin", type = "group", args = args }
end

BazUI:QueueForLogin(function()
    if not BazUI.RegisterOptionsTable then return end

    -- Registered here rather than at file scope: the form language builds
    -- its table of widget types when it loads, which is after this file.
    BazUI._Options.widgetFactories.borderBand = CreateBandWidget
    BazUI:RegisterOptionsTable("BazUI-Skin", BuildOptions)
    BazUI:AddToSettings("BazUI-Skin", "Skin", "BazUI")
end)
