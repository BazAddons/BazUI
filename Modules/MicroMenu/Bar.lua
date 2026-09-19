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
-- Every micro button either client has, in the order they read best.
--
-- One list, not one per game. A frame that is not there is simply never
-- adopted, so the entries for the other client cost nothing - the same
-- rule the Blizzard-frame switches in Unit Frames use.
--
-- The clients overlap less than you would think. Only Character, Quest
-- Log, Guild, Game Menu and Help are called the same thing on both.
-- Retail split the spellbook into PlayerSpells and Profession, dropped
-- Socials into the communities frame and the world map onto a keybind,
-- and added Achievements, Housing, the dungeon finder, Collections, the
-- adventure guide and the store. Listing only Forever's nine left retail
-- showing five buttons.
--
-- Icons are file paths rather than the buttons' own art: theirs is atlas
-- artwork cut for a rounded square, and these sit in a circle. Each one
-- was checked against the client's own icon files rather than
-- remembered.
local DEFS = {
    { key = "character",   frame = "CharacterMicroButton",    label = "Character",      portrait = true },
    -- Forever keeps spells and talents in two buttons; retail has one
    -- PlayerSpells button for both, and a separate one for professions.
    { key = "spellbook",   frame = "SpellbookMicroButton",    label = "Spellbook",      icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { key = "spells",      frame = "PlayerSpellsMicroButton", label = "Spells",         icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { key = "professions", frame = "ProfessionMicroButton",   label = "Professions",    icon = "Interface\\Icons\\Trade_BlackSmithing" },
    { key = "talents",     frame = "TalentMicroButton",       label = "Talents",        icon = "Interface\\Icons\\Ability_Marksmanship" },
    { key = "achievements",frame = "AchievementMicroButton",  label = "Achievements",   icon = "Interface\\Icons\\Achievement_General" },
    { key = "quests",      frame = "QuestLogMicroButton",     label = "Quest Log",      icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "housing",     frame = "HousingMicroButton",      label = "Housing",        icon = "Interface\\Icons\\Garrison_Building_Barracks" },
    { key = "social",      frame = "SocialsMicroButton",      label = "Social",         icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing" },
    { key = "guild",       frame = "GuildMicroButton",        label = "Guild",          icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
    { key = "finder",      frame = "LFDMicroButton",          label = "Group Finder",   icon = "Interface\\Icons\\INV_Misc_GroupLooking" },
    { key = "collections", frame = "CollectionsMicroButton",  label = "Collections",    icon = "Interface\\Icons\\INV_Box_04" },
    { key = "journal",     frame = "EJMicroButton",           label = "Adventure Guide",icon = "Interface\\Icons\\INV_Misc_Book_17" },
    { key = "map",         frame = "WorldMapMicroButton",     label = "World Map",      icon = "Interface\\Icons\\INV_Misc_Map_01" },
    { key = "store",       frame = "StoreMicroButton",        label = "Shop",           icon = "Interface\\Icons\\INV_Misc_Coin_01" },
    { key = "menu",        frame = "MainMenuMicroButton",     label = "Game Menu",      icon = "Interface\\Icons\\INV_Misc_Gear_01" },
    { key = "help",        frame = "HelpMicroButton",         label = "Help",           icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
}
addon.DEFS = DEFS

-- Stock furniture that is a child FRAME rather than a region, so
-- GetRegions in CollectChrome does not return it and it has to be named.
-- Both clients' names are here; one that does not exist costs nothing.
local CHROME_KEYS = {
    -- Forever and the Classic family
    "Flash", "PerformanceIndicator", "texture",
    -- Retail
    "MainMenuBarPerformanceBar",
    -- Both
    "NotificationOverlay",
}
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

-- Stock art is moved onto the hidden holder rather than faded: Blizzard's
-- own updates set alpha back (CharacterMicroButton_SetNormal puts the
-- portrait at 1.0 on every refresh), but nothing reparents these again.
local function Stash(entry, region)
    if region and region.SetParent and region.GetParent and entry.regions[region] == nil then
        entry.regions[region] = region:GetParent() or entry.button
    end
end

local function CollectChrome(entry)
    local b = entry.button
    entry.regions = {}

    -- Everything the button draws, asked of the button rather than listed
    -- by name.
    --
    -- It was a list of four names, and those four were Forever's. The
    -- same buttons on retail carry a dozen regions called something else
    -- entirely - Background, PushedBackground, Shadow, PushedShadow,
    -- Emblem, HighlightEmblem and the rest - so Blizzard's rounded plate
    -- stayed on screen behind our round button. A ghost of the old shape,
    -- which is precisely what it was.
    --
    -- GetRegions answers for whichever client is running, so there is no
    -- list to keep in step with two games. It is called before our own
    -- icon, ring and disc are made, so everything it returns is theirs.
    for _, region in ipairs({ b:GetRegions() }) do Stash(entry, region) end

    -- The state textures as well. They are usually in GetRegions, and
    -- stashing one twice costs nothing - Stash keeps the first parent it
    -- was told and ignores the rest.
    Stash(entry, b:GetNormalTexture())
    Stash(entry, b:GetPushedTexture())
    Stash(entry, b:GetHighlightTexture())
    Stash(entry, b:GetDisabledTexture())

    for _, key in ipairs(CHROME_KEYS) do Stash(entry, b[key]) end
    -- Classic keeps the character portrait in a global of its own; retail
    -- keeps it on the button, where GetRegions already found it.
    if entry.def.portrait then Stash(entry, _G.MicroButtonPortrait) end
end

local function SetChromeHidden(entry, hidden)
    for region, parent in pairs(entry.regions) do
        region:SetParent(hidden and hiddenParent or parent)
    end
end

local function RefreshState(entry)
    if not entry.active then return end
    local pushed = entry.button:GetButtonState() == "PUSHED"
    Theme.SetRoundButtonHover(entry.button, pushed or entry.hovered or entry.pulsing)
    -- Through the ring rather than at one of its textures: how many
    -- bands there are and which one is the accent are the skin's to say,
    -- and a tint set this way is put back whenever it redraws.
    local ring = entry.button._bazRingObject
    if ring then
        if entry.pulsing then ring:SetTint(1, 0.92, 0.55) else ring:SetTint(1, 1, 1) end
    end
end

-- Blizzard's "you have something new" flash (talent points, guild
-- invites) drives the stock Flash texture, which now sits on the hidden
-- holder. Mirrored as a brighter ring and lit disc instead, read off
-- their FlashBorder by the ticker in OnBlizzardUpdate.

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
        if b._bazRingObject then b._bazRingObject:Show() end
        b._bazDisc:Show()
        RefreshState(entry)
    else
        entry.active = false
        if b._bazRingObject then b._bazRingObject:Hide() end
        if b._bazDisc then b._bazDisc:Hide() end
        entry.icon:Hide()
        SetChromeHidden(entry, false)
        b:SetSize(entry.origW, entry.origH)
        -- Drop the anchors that placed it on our bar, or it keeps drawing
        -- there after it is handed back; Blizzard's grid re-anchors it.
        b:ClearAllPoints()
        if b:GetParent() ~= entry.origParent then b:SetParent(entry.origParent) end
    end
end

-- Re-run Blizzard's own layout after buttons are handed back.
local function RelayoutBlizzard()
    local grid = _G.MicroMenu
    if grid and grid.Layout then grid:Layout() end
    local container = _G.MicroMenuContainer
    if container and container.Layout then container:Layout() end
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

-- Two position shapes: the starter profile anchors the bar to a screen
-- edge ({ point, relPoint, x, y }), and BazUI Edit Mode saves the bar's
-- center as a screen-pixel offset from the center of UIParent ({ x, y }).
local function ApplyPosition()
    bar:ClearAllPoints()
    local pos = addon:GetSetting("position")
    if pos and pos.point then
        bar:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    elseif pos and pos.x and pos.y then
        local es = bar:GetEffectiveScale()
        bar:SetPoint("CENTER", UIParent, "CENTER", pos.x / es, pos.y / es)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -4)
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
local fadeTarget = 1

-- The cursor counts as over the bar when it is over the bar's rect or
-- any button on it (a button can extend past the bar while it resizes).
local function Hovered()
    if bar:IsMouseOver(6, -6, -6, 6) then return true end
    for _, entry in pairs(adopted) do
        if entry.active and entry.button:GetParent() == bar and entry.button:IsMouseOver() then
            return true
        end
    end
    return false
end

local function WantedAlpha()
    if editing or not addon:GetSetting("mouseoverFade") then return 1 end
    if Hovered() then return 1 end
    return (addon:GetSetting("fadeAlpha") or 0) / 100
end

-- Alpha is eased toward the target every frame by this module alone, so
-- it always converges on what the settings say; nothing can leave the
-- bar stuck invisible.
local function StepFade(elapsed)
    local current = bar:GetAlpha()
    if current == fadeTarget then return end
    local duration = fadeTarget > current and FADE_IN or FADE_OUT
    local step = elapsed / duration
    if fadeTarget > current then
        bar:SetAlpha(math.min(fadeTarget, current + step))
    else
        bar:SetAlpha(math.max(fadeTarget, current - step))
    end
end

local function UpdateFade()
    if not bar then return end
    fadeTarget = WantedAlpha()
end

local function SetFadeTicker(on)
    if on then
        bar._bazFadeElapsed = FADE_TICK   -- poll on the first frame
        bar:SetScript("OnUpdate", function(self, elapsed)
            self._bazFadeElapsed = self._bazFadeElapsed + elapsed
            if self._bazFadeElapsed >= FADE_TICK then
                self._bazFadeElapsed = 0
                UpdateFade()
            end
            StepFade(elapsed)
        end)
    else
        bar:SetScript("OnUpdate", nil)
        fadeTarget = 1
        bar:SetAlpha(1)
    end
    UpdateFade()
end

function addon:SetEditing(value)
    editing = value and true or false
    UpdateFade()
    if bar and not bar:GetScript("OnUpdate") then bar:SetAlpha(1) end
end

-- /bazmicro debug: what the bar is doing right now.
function addon:PrintDebug()
    if not bar then self:Print("Micro menu bar not created yet."); return end
    local point, rel, relPoint, x, y = bar:GetPoint()
    local shown, active = 0, 0
    for _, entry in pairs(adopted) do
        if entry.active then active = active + 1 end
        if entry.active and entry.button:GetParent() == bar and entry.button:IsShown() then shown = shown + 1 end
    end
    self:Print(("bar shown=%s alpha=%.2f target=%.2f size=%dx%d anchor=%s/%s/%s %.0f,%.0f ticker=%s editing=%s buttons active=%d visible=%d"):format(
        tostring(bar:IsShown()), bar:GetAlpha(), fadeTarget, bar:GetWidth(), bar:GetHeight(),
        tostring(point), rel and rel:GetName() or "?", tostring(relPoint), x or 0, y or 0,
        tostring(bar:GetScript("OnUpdate") ~= nil), tostring(editing), active, shown))
    local pos = self:GetSetting("position")
    self:Print(("settings: enabled=%s mouseoverFade=%s fadeAlpha=%s size=%s spacing=%s position=%s"):format(
        tostring(self:GetSetting("enabled")), tostring(self:GetSetting("mouseoverFade")), tostring(self:GetSetting("fadeAlpha")),
        tostring(self:GetSetting("buttonSize")), tostring(self:GetSetting("spacing")),
        pos and (pos.point and ("%s %s %s,%s"):format(pos.point, pos.relPoint or pos.point, pos.x, pos.y) or ("center %.0f,%.0f"):format(pos.x or 0, pos.y or 0)) or "nil"))
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

    if not enabled then
        -- Bring Blizzard's container back first so its grid can lay the
        -- returned buttons out in their stock spot.
        SetBlizzardHidden(false)
        for _, def in ipairs(DEFS) do
            local entry = adopted[def.key]
            if entry then SetActive(entry, false, size) end
        end
        RelayoutBlizzard()
        bar:Hide()
        SetFadeTicker(false)
        return
    end

    for _, def in ipairs(DEFS) do
        local entry = adopted[def.key]
        if entry then SetActive(entry, true, size) end
    end
    bar:Show()
    self:Layout()
    ApplyPosition()
    SetFadeTicker(self:GetSetting("mouseoverFade") and true or false)
    SetBlizzardHidden(self:GetSetting("hideBlizzard") ~= false)
end

function addon:UpdatePortraits()
    for _, entry in pairs(adopted) do UpdatePortrait(entry) end
end

-- After Blizzard's own UpdateMicroButtons: mirror pushed states and
-- re-run the layout in case a button was shown or hidden.
function addon:OnBlizzardUpdate()
    if not bar or self:GetSetting("enabled") == false then return end
    for _, entry in pairs(adopted) do
        -- Whether a button is calling for attention, read rather than
        -- hooked. MicroButtonPulse flashes the button's own FlashBorder
        -- and MicroButtonPulseStop stops it, so the flag is already on
        -- their frame and does not need us to intercept the call.
        local flash = entry.button and entry.button.FlashBorder
        entry.pulsing = (flash and flash:IsShown()) and true or false
        RefreshState(entry)
    end
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

    -- Blizzard's own state, mirrored on a ticker rather than by hooking
    -- UpdateMicroButtons.
    --
    -- Even the string form of hooksecurefunc leaves the global counting
    -- as tainted on Forever, and EnterEditMode calls UpdateMicroButtons:
    -- the taint log showed that call, then ClearTarget blocked, then
    -- their compact party frames erroring on a secret colour, all in the
    -- one press. Watching instead of hooking costs a little latency on a
    -- button lighting up and taints nothing.
    local watcher, since = CreateFrame("Frame"), 0
    watcher:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < 0.2 then return end
        since = 0
        addon:OnBlizzardUpdate()
    end)

    self:On("UNIT_PORTRAIT_UPDATE", function(_, unit)
        if unit == "player" then self:UpdatePortraits() end
    end)
    self:On("PLAYER_ENTERING_WORLD", function()
        self:UpdatePortraits()
        self:Layout()
    end)
    -- Apply a profile switch one frame later, after every module has
    -- finished its own switch, so nothing we lay out is moved under us.
    self:OnProfileChanged(function()
        C_Timer.After(0, function() addon:ApplySettings() end)
    end)

    self:ApplySettings()
end
