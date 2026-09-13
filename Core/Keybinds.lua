-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: Keybinds Module
-- Override keybinding framework with capture UI
---------------------------------------------------------------------------

local activeBindings = {} -- [addonName] = { [bindId] = { key, action, frame } }

---------------------------------------------------------------------------
-- Binding Management
---------------------------------------------------------------------------

function BazUI:RegisterKeybind(addonName, bindId, action, buttonFrame)
    if not activeBindings[addonName] then
        activeBindings[addonName] = {}
    end
    activeBindings[addonName][bindId] = {
        action = action,
        frame = buttonFrame,
        key = nil,
    }
end

function BazUI:SetKeybind(addonName, bindId, key)
    local bindings = activeBindings[addonName]
    if not bindings or not bindings[bindId] then return false end

    local binding = bindings[bindId]

    -- Clear old override if exists
    if binding.key and binding.frame then
        ClearOverrideBindings(binding.frame)
    end

    binding.key = key

    if key and binding.frame then
        if InCombatLockdown() then return false end
        local btnName = binding.frame:GetName()
        if btnName then
            SetOverrideBindingClick(binding.frame, true, key, btnName, "LeftButton")
        end
    end

    -- Save to addon's SV if available
    local config = BazUI.addons[addonName]
    if config and config.savedVariable then
        local sv = _G[config.savedVariable]
        if sv then
            sv.keybinds = sv.keybinds or {}
            sv.keybinds[bindId] = key
        end
    end

    BazUI:Fire("BAZ_KEYBIND_CHANGED", addonName, bindId, key)
    return true
end

function BazUI:ClearKeybind(addonName, bindId)
    return BazUI:SetKeybind(addonName, bindId, nil)
end

function BazUI:GetKeybind(addonName, bindId)
    local bindings = activeBindings[addonName]
    if not bindings or not bindings[bindId] then return nil end
    return bindings[bindId].key
end

-- Restore all saved keybinds for an addon (call on PLAYER_LOGIN)
function BazUI:RestoreKeybinds(addonName)
    if InCombatLockdown() then return end
    local config = BazUI.addons[addonName]
    if not config or not config.savedVariable then return end
    local sv = _G[config.savedVariable]
    if not sv or not sv.keybinds then return end

    local bindings = activeBindings[addonName]
    if not bindings then return end

    for bindId, key in pairs(sv.keybinds) do
        if bindings[bindId] then
            BazUI:SetKeybind(addonName, bindId, key)
        end
    end
end

-- Clear all override bindings for an addon
function BazUI:ClearAllKeybinds(addonName)
    if InCombatLockdown() then return end
    local bindings = activeBindings[addonName]
    if not bindings then return end
    for bindId, binding in pairs(bindings) do
        if binding.key and binding.frame then
            ClearOverrideBindings(binding.frame)
        end
        binding.key = nil
    end
end

---------------------------------------------------------------------------
-- Keybind Capture UI
-- Modal popup that captures the next key press
---------------------------------------------------------------------------

local captureFrame = nil

local function EnsureCaptureFrame()
    if captureFrame then return captureFrame end

    local f = CreateFrame("Frame", "BazUIKeybindCapture", UIParent, "BackdropTemplate")
    f:SetSize(300, 100)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop(BazUI.backdrop)
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    f:SetBackdropBorderColor(0.3, 0.6, 1.0, 0.8)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Press a key...")
    title:SetTextColor(0.2, 0.6, 1.0)
    f.title = title

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("CENTER", 0, -5)
    hint:SetText("Press ESC to cancel, DELETE to unbind")
    hint:SetTextColor(0.5, 0.5, 0.5)

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("BOTTOM", 0, 16)
    label:SetText("")
    f.label = label

    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(false)

    captureFrame = f
    return f
end

-- Key name normalization
local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true,
    LCTRL = true, RCTRL = true,
    LALT = true, RALT = true,
}

local function BuildKeyCombo(key)
    if MODIFIER_KEYS[key] then return nil end -- ignore bare modifiers

    local combo = ""
    if IsControlKeyDown() then combo = combo .. "CTRL-" end
    if IsAltKeyDown() then combo = combo .. "ALT-" end
    if IsShiftKeyDown() then combo = combo .. "SHIFT-" end
    combo = combo .. key

    return combo
end

function BazUI:CaptureKeybind(callback, label)
    local f = EnsureCaptureFrame()
    f.label:SetText(label or "")
    f:Show()
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
            callback(nil) -- cancelled
            return
        end

        if key == "DELETE" or key == "BACKSPACE" then
            self:Hide()
            callback(false) -- clear binding
            return
        end

        local combo = BuildKeyCombo(key)
        if combo then
            self:Hide()
            callback(combo)
        end
    end)
end
