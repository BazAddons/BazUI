-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Micro Menu: the bar
--
-- Blizzard creates the micro buttons once and parents them to its
-- MicroMenu grid; nothing re-parents them afterwards (vehicles move the
-- whole grid, not the buttons). So we can take the buttons, hide their
-- stock art, give each a round icon with the BazUI ring, and lay them
-- out on our own frame. UpdateMicroButtons still runs Blizzard's state
-- logic (pushed, disabled, shown), which we mirror after each call.
---------------------------------------------------------------------------

local addon = BazUI:GetModule("MicroMenu")
local Theme = BazUI.Skin.Theme

-- Vanilla's micro menu, in Blizzard's order. The character button shows
-- the player's portrait, like the unit frame, instead of a fixed icon.
local DEFS = {
    { key = "character", frame = "CharacterMicroButton", label = "Character", portrait = true },
    { key = "spellbook", frame = "SpellbookMicroButton", label = "Spellbook", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { key = "talents",   frame = "TalentMicroButton",    label = "Talents",   icon = "Interface\\Icons\\Ability_Marksmanship" },
    { key = "quests",    frame = "QuestLogMicroButton",  label = "Quest Log", icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "social",    frame = "SocialsMicroButton",   label = "Social",    icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing" },
    { key = "guild",     frame = "GuildMicroButton",     label = "Guild",     icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
    { key = "map",       frame = "WorldMapMicroButton",  label = "World Map", icon = "Interface\\Icons\\INV_Misc_Map_01" },
    { key = "menu",      frame = "MainMenuMicroButton",  label = "Game Menu", icon = "Interface\\Icons\\INV_Misc_Gear_01" },
    { key = "help",      frame = "HelpMicroButton",      label = "Help",      icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
}
addon.DEFS = DEFS

-- Stock art on the buttons that our icon and ring replace.
local CHROME_KEYS = { "Flash", "PerformanceIndicator", "NotificationOverlay", "texture" }
-- Blizzard's container, its legacy art strip, and the latency bar that
-- hides behind the main menu bar art (and pops out once that art goes).
local BLIZZARD_FRAMES = { "MicroMenuContainer", "MicroButtonAndBagsBar", "MainMenuBarPerformanceBarFrame" }

local FADE_TICK = 0.1
local FADE_IN, FADE_OUT = 0.15, 0.3

local bar, hiddenParent
local adopted = {}    -- key -> { button, def, icon, regions, origParent, origW, origH, active }

---------------------------------------------------------------------------
-- Adopting a button
---------------------------------------------------------------------------

local function Stash(entry, region)
    if region and region.GetAlpha and region.SetAlpha and entry.regions[region] == nil then
        entry.regions[region] = region:GetAlpha()
    end
end

local function CollectChrome(entry)
    local b = entry.button
    entry.regions = {}
    Stash(entry, b:GetNormalTexture())
    Stash(entry, b:GetPushedTexture())
    Stash(entry, b:GetHighlightTexture())
    Stash(entry, b:GetDisabledTexture())
    for _, key in ipairs(CHROME_KEYS) do Stash(entry, b[key]) end
    if entry.def.portrait then Stash(entry, _G.MicroButtonPortrait) end
end

local function SetChromeHidden(entry, hidden)
    for region, alpha in pairs(entry.regions) do
        region:SetAlpha(hidden and 0 or alpha)
    end
end

local function RefreshState(entry)
    if not entry.active then return end
    local pushed = entry.button:GetButtonState() == "PUSHED"
    Theme.SetRoundButtonHover(entry.button, pushed or entry.hovered)
end

local function UpdatePortrait(entry)
    if entry.def.portrait and entry.icon then
        SetPortraitTexture(entry.icon, "player")
    end
end

local function Adopt(def)
    local button = _G[def.frame]
    if not button or adopted[def.key] then return end
    local entry = {
        button = button, def = def,
        origParent = button:GetParent(),
        origW = button:GetWidth(), origH = button:GetHeight(),
    }
    adopted[def.key] = entry
    CollectChrome(entry)

    local icon = button:CreateTexture(nil, "ARTWORK")
    if def.portrait then
        SetPortraitTexture(icon, "player")
    else
        icon:SetTexture(def.icon)
        -- Crop before the round mask goes on: masked textures reject SetTexCoord.
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    entry.icon = icon

    button:HookScript("OnEnter", function() entry.hovered = true;  RefreshState(entry) end)
    button:HookScript("OnLeave", function() entry.hovered = false; RefreshState(entry) end)
end

-- Switch one adopted button between our bar and Blizzard's grid.
local function SetActive(entry, active, size)
    local b = entry.button
    if active then
        entry.active = true
        SetChromeHidden(entry, true)
        b:SetSize(size, size)
        Theme.ApplyRoundButton(b, entry.icon, { size = size })
        entry.icon:Show()
        b._bazRing:Show()
        b._bazDisc:Show()
        RefreshState(entry)
    else
        entry.active = false
        if b._bazRing then b._bazRing:Hide() end
        if b._bazDisc then b._bazDisc:Hide() end
        entry.icon:Hide()
        SetChromeHidden(entry, false)
        b:SetSize(entry.origW, entry.origH)
        if b:GetParent() ~= entry.origParent then b:SetParent(entry.origParent) end
        if entry.origParent and entry.origParent.MarkDirty then entry.origParent:MarkDirty() end
    end
end

---------------------------------------------------------------------------
-- Layout and position
---------------------------------------------------------------------------

function addon:Layout()
    if not bar then return end
    local size       = self:GetSetting("buttonSize") or 30
    local spacing    = self:GetSetting("spacing") or 6
    local horizontal = (self:GetSetting("orientation") or "horizontal") ~= "vertical"
    local prefs      = self:GetSetting("buttons") or {}

    local n = 0
    for _, def in ipairs(DEFS) do
        local entry = adopted[def.key]
        if entry and entry.active then
            local b = entry.button
            if prefs[def.key] == false then
                if b:GetParent() ~= hiddenParent then b:SetParent(hiddenParent) end
            else
                if b:GetParent() ~= bar then b:SetParent(bar) end
                -- Blizzard hides buttons the character can't use yet
                -- (talents before level 10, guild without a guild); skip those.
                if b:IsShown() then
                    b:ClearAllPoints()
                    if horizontal then
                        b:SetPoint("LEFT", bar, "LEFT", n * (size + spacing), 0)
                    else
                        b:SetPoint("TOP", bar, "TOP", 0, -n * (size + spacing))
                    end
                    n = n + 1
                end
            end
        end
    end

    local length = math.max(1, n * size + math.max(0, n - 1) * spacing)
    if horizontal then bar:SetSize(length, size) else bar:SetSize(size, length) end
end

-- Positions are stored the way BazUI Edit Mode saves them: the bar's
-- centre as a screen-pixel offset from the centre of UIParent.
local function ApplyPosition()
    bar:ClearAllPoints()
    local pos = addon:GetSetting("position")
    if pos and pos.x and pos.y then
        local es = bar:GetEffectiveScale()
        bar:SetPoint("CENTER", UIParent, "CENTER", pos.x / es, pos.y / es)
    else
        bar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -12, 12)
    end
end

function addon:ResetPosition()
    self:SetSetting("position", nil)
    if bar then ApplyPosition() end
end

---------------------------------------------------------------------------
-- Mouseover fade
--
-- With the option on, the bar sits at its faded opacity (fully hidden by
-- default) until the cursor is over it. IsMouseOver covers the child
-- buttons too, so moving between them never flickers. A short ticker
-- polls only while the option is on, and Edit Mode forces the bar
-- visible so it can still be found and dragged.
---------------------------------------------------------------------------

local editing = false

local function FadeTo(alpha)
    if bar._bazTargetAlpha == alpha then return end
    bar._bazTargetAlpha = alpha
    local current = bar:GetAlpha()
    if UIFrameFadeIn and UIFrameFadeOut then
        if alpha > current then
            UIFrameFadeIn(bar, FADE_IN, current, alpha)
        else
            UIFrameFadeOut(bar, FADE_OUT, current, alpha)
        end
    else
        bar:SetAlpha(alpha)
    end
end

local function UpdateFade()
    if not bar then return end
    if editing or not addon:GetSetting("mouseoverFade") then
        FadeTo(1)
        return
    end
    local faded = (addon:GetSetting("fadeAlpha") or 0) / 100
    FadeTo(bar:IsMouseOver(6, -6, -6, 6) and 1 or faded)
end

local function SetFadeTicker(on)
    if on then
        bar._bazFadeElapsed = 0
        bar:SetScript("OnUpdate", function(self, elapsed)
            self._bazFadeElapsed = self._bazFadeElapsed + elapsed
            if self._bazFadeElapsed < FADE_TICK then return end
            self._bazFadeElapsed = 0
            UpdateFade()
        end)
    else
        bar:SetScript("OnUpdate", nil)
    end
    UpdateFade()
end

function addon:SetEditing(value)
    editing = value and true or false
    UpdateFade()
end

local function SetBlizzardHidden(hide)
    for _, name in ipairs(BLIZZARD_FRAMES) do
        local f = _G[name]
        if f then
            if hide and not f._bazMicroParent then
                f._bazMicroParent = f:GetParent() or UIParent
                f:SetParent(hiddenParent)
            elseif not hide and f._bazMicroParent then
                f:SetParent(f._bazMicroParent)
                f._bazMicroParent = nil
            end
        end
    end
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function addon:ApplySettings()
    if not bar then return end
    local enabled = self:GetSetting("enabled") ~= false
    local size = self:GetSetting("buttonSize") or 30
    for _, def in ipairs(DEFS) do
        local entry = adopted[def.key]
        if entry then SetActive(entry, enabled, size) end
    end
    bar:SetShown(enabled)
    if enabled then
        self:Layout()
        ApplyPosition()
    end
    SetFadeTicker(enabled and self:GetSetting("mouseoverFade") and true or false)
    SetBlizzardHidden(enabled and self:GetSetting("hideBlizzard") ~= false)
end

function addon:UpdatePortraits()
    for _, entry in pairs(adopted) do UpdatePortrait(entry) end
end

-- After Blizzard's own UpdateMicroButtons: mirror pushed states and
-- re-run the layout in case a button was shown or hidden.
function addon:OnBlizzardUpdate()
    if not bar or self:GetSetting("enabled") == false then return end
    for _, entry in pairs(adopted) do RefreshState(entry) end
    self:Layout()
end

function addon:Initialize()
    if bar then return end
    hiddenParent = CreateFrame("Frame")
    hiddenParent:Hide()

    bar = CreateFrame("Frame", "BazUIMicroMenu", UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(50)
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:SetSize(1, 1)
    self.frame = bar

    for _, def in ipairs(DEFS) do Adopt(def) end

    BazUI:RegisterEditModeFrame(bar, {
        label       = "Micro Menu",
        addonName   = self.MODULE_NAME,
        positionKey = "position",
        settings    = BazUI:BuildEditModeArrayFromSpec(self.MODULE_NAME),
        onEnter     = function() addon:SetEditing(true) end,
        onExit      = function() addon:SetEditing(false) end,
    })

    hooksecurefunc("UpdateMicroButtons", function() addon:OnBlizzardUpdate() end)
    self:On("UNIT_PORTRAIT_UPDATE", function(_, unit)
        if unit == "player" then self:UpdatePortraits() end
    end)
    self:On("PLAYER_ENTERING_WORLD", function()
        self:UpdatePortraits()
        self:Layout()
    end)
    self:OnProfileChanged(function() self:ApplySettings() end)

    self:ApplySettings()
end
