-- Exercise the real shared copy dialog's developer controls and reuse path.
local checks = 0
local function check(ok, label) assert(ok, label); checks = checks + 1 end
local F = {}
local function Noop() end
local function Frame()
    return setmetatable({ scripts = {}, visible = false, text = "", height = 300 },
        { __index = function(_, name)
            if F[name] then return F[name] end
            if name:match('^[A-Z]') then return Noop end
        end })
end
function F:SetScript(name, fn) self.scripts[name] = fn end
function F:SetText(text)
    self.text = text
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function F:GetText() return self.text end
function F:Show() self.visible = true end
function F:Hide() self.visible = false end
function F:SetEnabled(value) self.enabled = value end
function F:SetHeight(height) self.height = height end
function F:GetHeight() return self.height end
function F:GetFrameLevel() return 100 end
function F:GetFont() return 'Font.ttf', 13 end
function F:CreateFontString() return Frame() end
function F:SetFocus() self.focused = true end
function F:HighlightText() self.highlighted = true end
CreateFrame = function() return Frame() end
local theme = { colors = { edge = {} }, CreateButton = Frame, CreateCloseButton = Frame,
    ApplyDialog = Noop, ApplyFlatPanel = Noop, FontFile = function() return 'Font.ttf' end }
BazUI = { Skin = { Theme = theme }, CloseOnEscape = Noop, Print = function() error('unexpected copy truncation') end }
dofile('Core/CopyDialog.lua')
local clicked = 0
local f = BazUI:OpenCopyDialog({ title = 'Developer errors', content = 'First report', editable = false,
    actions = { { text = 'Previous', enabled = false, func = function() error('disabled') end },
        { text = 'Next', func = function() clicked = clicked + 1 end } } })
check(#f.actionButtons == 2 and not f.actionButtons[1].enabled and f.actionButtons[2].enabled, 'action enable state applied')
f.actionButtons[2].scripts.OnClick()
check(clicked == 1, 'action callback connected')
check(f.editBox:GetText() == 'First report' and f.editBox.focused and f.editBox.highlighted, 'report ready for Ctrl+C')
f.editBox.text = 'accidental edit'
f.editBox.scripts.OnTextChanged(f.editBox, true)
check(f.editBox:GetText() == 'First report', 'report remains read-only')
local nextFrame = BazUI:OpenCopyDialog({ content = 'Second report', editable = false,
    actions = { { text = 'Previous', func = function() clicked = clicked + 2 end } } })
check(nextFrame == f and f.editBox:GetText() == 'Second report', 'browsing replaces the displayed report')
check(f.actionButtons[1].visible and not f.actionButtons[2].visible, 'unused action buttons hidden')
f.actionButtons[1].scripts.OnClick()
check(clicked == 3, 'reused action receives its new callback')
BazUI:OpenCopyDialog({ content = 'Other module export' })
check(not f.actionButtons[1].visible and not f.actionButtons[2].visible, 'developer buttons do not leak into other copy dialogs')
check(f.editBox:GetText() == 'Other module export', 'normal copy dialog continues working')
print('Copy dialog: ' .. checks .. ' behavioral checks passed')
