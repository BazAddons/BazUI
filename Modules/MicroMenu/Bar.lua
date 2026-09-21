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
    -- Forever's own, and on no other client: the legacy adventure tree.
    { key = "legacy",      frame = "LegacyMicroButton",       label = "Legacy",         icon = "Interface\\Icons\\Achievement_Legacy_Classic_01" },
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

local WIDGET_ID = "bazdrawer_micromenu"
addon.WIDGET_ID = WIDGET_ID

---------------------------------------------------------------------------
-- Settings
--
-- In the drawer's per-widget store, not this module's own, because the
-- micro menu is a widget: its settings belong on the same page as every
-- other widget's rather than on a module page of their own.
--
-- Read falls back to the old module setting when the new one is unset, so
-- a profile that predates the move keeps its answers without a migration
-- pass, and the first change writes to the new home. Nothing has to be
-- converted and nothing is lost if this is rolled back.
---------------------------------------------------------------------------

function addon:Opt(key, default)
    local drawers = BazUI:GetModule("Drawers")
    if drawers and drawers.GetWidgetSetting then
        local value = drawers:GetWidgetSetting(WIDGET_ID, key)
        if value ~= nil then return value end
    end
    local legacy = self:GetSetting(key)
    if legacy ~= nil then return legacy end
    return default
end

function addon:SetOpt(key, value)
    local drawers = BazUI:GetModule("Drawers")
    if drawers and drawers.SetWidgetSetting then
        drawers:SetWidgetSetting(WIDGET_ID, key, value)
    else
        self:SetSetting(key, value)
    end
    self:ApplySettings()
end

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

-- Which buttons this client actually uses, and in what order.
--
-- Both clients define every button either of them has - Forever ships
-- Mainline's micro menu code, so Achievements and the retail spellbook
-- exist there as frames whether or not the game has any use for them.
-- Testing whether the frame exists therefore answers "does this client
-- have the code", not "does this client have the button", which is why a
-- Forever bar came up wearing retail's arrangement.
--
-- The client already works out the real answer for itself.
-- MicroMenuMixin:InitializeButtons asks an override - there is one per
-- game type - for the list, drops whichever the game rules have turned
-- off, and stamps a layoutIndex on each survivor as it adds it. So a
-- button wearing a layoutIndex is one this client decided to show, and
-- the number is where it goes. Asking that is better than a list of our
-- own for the same reason it is better than a client check: Blizzard
-- changes the set, and then ours is wrong and theirs is not.
--
-- The stamp survives us taking the button, because it is a field on the
-- frame rather than something recomputed from its parent.
local function ClientOrder(def)
    local button = _G[def.frame]
    return button and tonumber(button.layoutIndex) or nil
end

-- Whether the client has said anything at all yet.
--
-- If the micro menu has not loaded, nothing is stamped, and a bar of no
-- buttons is a worse answer than the old one. In that case every button
-- that exists is taken, which is what this did before.
local function ClientHasSpoken()
    for _, def in ipairs(DEFS) do
        if ClientOrder(def) then return true end
    end
    return false
end

-- The buttons to put on the bar, in the client's own order.
function addon:Buttons()
    local known = ClientHasSpoken()
    local out = {}
    for index, def in ipairs(DEFS) do
        local order = ClientOrder(def)
        if order or (not known and _G[def.frame]) then
            out[#out + 1] = { def = def, order = order or (100 + index) }
        end
    end
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.def.key < b.def.key
    end)
    return out
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
local function SetActive(entry, active, size, skinned)
    local b = entry.button
    if active and skinned then
        entry.active = true
        SetChromeHidden(entry, true)
        b:SetSize(size, size)
        Theme.ApplyRoundButton(b, entry.icon, { size = size })
        entry.icon:Show()
        if b._bazRingObject then b._bazRingObject:Show() end
        b._bazDisc:Show()
        RefreshState(entry)
    elseif active then
        -- On our bar, wearing its own clothes.
        --
        -- Adopted so we still lay it out, but none of the skinning: the
        -- stock chrome stays up, our ring and disc stay down, and the
        -- button keeps the shape Blizzard drew it. Sized by height alone
        -- so the row lines up, with the width following the art rather
        -- than squashed square - a micro button is not square and forcing
        -- it to be looks like a bug rather than a choice.
        entry.active = true
        SetChromeHidden(entry, false)
        if b._bazRingObject then b._bazRingObject:Hide() end
        if b._bazDisc then b._bazDisc:Hide() end
        entry.icon:Hide()
        local scale = (entry.origH and entry.origH > 0) and (size / entry.origH) or 1
        b:SetSize((entry.origW or size) * scale, size)
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
    local size       = self:Opt("buttonSize", 30)
    local spacing    = self:Opt("spacing", 6)
    local horizontal = self:Opt("orientation", "horizontal") ~= "vertical"
    local rows       = math.max(1, math.floor(tonumber(self:Opt("rows", 1)) or 1))
    local prefs      = self:Opt("buttons", nil) or {}

    -- Which buttons are actually going on the bar, gathered before any of
    -- them is placed. The wrapping below needs the count first, and
    -- Blizzard hides buttons the character cannot use yet - talents before
    -- level ten, guild without a guild - so the number is not known until
    -- they have all been asked.
    local shown = {}
    for _, listed in ipairs(addon:Buttons()) do
        local entry = adopted[listed.def.key]
        if entry and entry.active then
            local b = entry.button
            if prefs[listed.def.key] == false then
                if b:GetParent() ~= hiddenParent then b:SetParent(hiddenParent) end
            else
                if b:GetParent() ~= bar then b:SetParent(bar) end
                if b:IsShown() then shown[#shown + 1] = b end
            end
        end
    end

    local n = #shown
    if n == 0 then
        bar:SetSize(1, size)
        return
    end

    -- Rows, filled evenly rather than filling one and leaving a stub.
    -- Ten buttons in two rows is five and five, not eight and two.
    rows = math.min(rows, n)
    local perLine = math.ceil(n / rows)

    -- Measured rather than assumed, because an unskinned button keeps its
    -- own width and those differ from each other.
    local lineLength, longest = 0, 0
    local line, placed = 0, 0

    for index, b in ipairs(shown) do
        if placed == perLine then
            longest = math.max(longest, lineLength - spacing)
            lineLength, placed = 0, 0
            line = line + 1
        end

        b:ClearAllPoints()
        local across = line * (size + spacing)
        if horizontal then
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", lineLength, -across)
        else
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", across, -lineLength)
        end

        local run = horizontal and (b:GetWidth() or size) or (b:GetHeight() or size)
        lineLength = lineLength + run + spacing
        placed = placed + 1
        if index == n then longest = math.max(longest, lineLength - spacing) end
    end

    local lines = line + 1
    local across = lines * size + math.max(0, lines - 1) * spacing
    local w, h = math.max(1, longest), across
    if not horizontal then w, h = across, math.max(1, longest) end
    bar:SetSize(w, h)

    -- Tell the drawer what shape we are now.
    --
    -- A widget declares the size it was drawn for and the host scales it
    -- to the shelf: scale = usableWidth / designWidth. Ours is not fixed -
    -- nine buttons at 30 is a different object from five at 44, two rows
    -- is a different object again, and turning the menu vertical swaps the
    -- axes entirely - so the numbers are re-declared whenever the layout
    -- changes rather than once at registration.
    local widget = BazUI.GetDockableWidget and BazUI:GetDockableWidget(WIDGET_ID)
    if widget and (widget.designWidth ~= w or widget.designHeight ~= h) then
        widget.designWidth  = w
        widget.designHeight = h

        -- Only a widget on a shelf needs the shelf laid out again.
        --
        -- A reflow re-places every floating widget at its saved position,
        -- and this runs from a ticker every fifth of a second - so asking
        -- for one here meant that any flicker in a button's visibility
        -- yanked the frame back out from under a drag in progress. Dragging
        -- it upward felt like the screen was fighting you, because it was.
        --
        -- A floating widget is anchored by its own centre and does not care
        -- what size it is; nothing needs re-laying out. A docked one shares
        -- a row with its neighbours and does.
        if not widget._floating then
            local drawers = BazUI:GetModule("Drawers")
            if drawers and drawers.WidgetHost and drawers.WidgetHost.Reflow then
                drawers.WidgetHost:Reflow()
            end
        end
    end
end

---------------------------------------------------------------------------
-- Position, fade and Edit Mode
--
-- All three used to live here: a position setting with two shapes, a
-- mouseover fade with its own ticker and easing, and an Edit Mode
-- registration. None of it does any more.
--
-- The micro menu is a drawer widget now, so the drawer owns where it
-- sits, whether it floats, how it fades and what its handle says. That
-- is not tidiness - it is nine fixed round buttons with one correct size,
-- which is exactly what a drawer widget is and exactly what an action bar
-- is not. See DESIGN-elements.md.
--
-- What is left in this file is the part nobody else can do: taking
-- Blizzard's buttons, keeping them working, and arranging them.
---------------------------------------------------------------------------

-- /bazmicro debug: what the bar is doing right now.
function addon:PrintDebug()
    if not bar then self:Print("Micro menu bar not created yet."); return end
    local point, rel, relPoint, x, y = bar:GetPoint()
    local shown, active = 0, 0
    for _, entry in pairs(adopted) do
        if entry.active then active = active + 1 end
        if entry.active and entry.button:GetParent() == bar and entry.button:IsShown() then shown = shown + 1 end
    end
    self:Print(("bar shown=%s alpha=%.2f size=%dx%d anchor=%s/%s/%s %.0f,%.0f buttons active=%d visible=%d"):format(
        tostring(bar:IsShown()), bar:GetAlpha(), bar:GetWidth(), bar:GetHeight(),
        tostring(point), rel and rel:GetName() or "?", tostring(relPoint), x or 0, y or 0,
        active, shown))
    self:Print(("settings: enabled=%s size=%s spacing=%s orientation=%s"):format(
        tostring(self:GetSetting("enabled")), tostring(self:GetSetting("buttonSize")),
        tostring(self:GetSetting("spacing")), tostring(self:GetSetting("orientation"))))
    -- Where it sits and how it fades are the drawer's business now, and
    -- /bazdrawers has the answer for every widget rather than this one.
    self:Print("Placement is the drawer's: see /bazdrawers.")
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
    local size = self:Opt("buttonSize", 30)
    local skinned = self:Opt("skin", true) ~= false

    if not enabled then
        -- Bring Blizzard's container back first so its grid can lay the
        -- returned buttons out in their stock spot.
        SetBlizzardHidden(false)
        for _, def in ipairs(DEFS) do
            local entry = adopted[def.key]
            if entry then SetActive(entry, false, size, skinned) end
        end
        RelayoutBlizzard()
        bar:Hide()
        return
    end

    -- Only the buttons this client uses. One that exists but has no place
    -- here is handed back rather than dressed up and left nowhere: a
    -- button we never lay out is one the player cannot see and cannot
    -- get to, which is worse than not taking it at all.
    local wanted = {}
    for _, listed in ipairs(self:Buttons()) do wanted[listed.def.key] = true end
    for _, def in ipairs(DEFS) do
        local entry = adopted[def.key]
        if entry then SetActive(entry, wanted[def.key] == true, size, skinned) end
    end
    bar:Show()
    self:Layout()
    SetBlizzardHidden(self:Opt("hideBlizzard", true) ~= false)
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

    -- A drawer widget, not a frame of our own to place.
    --
    -- Everything the suite already knows how to do to a placeable thing -
    -- float it, dock it into a drawer, scale it, fade it on mouseover,
    -- give it a handle in Edit Mode and a settings popup - is the
    -- drawer's, and it does all of it better than the copy that used to
    -- be in this file.
    self:Layout()
    BazUI:RegisterDockableWidget({
        id           = WIDGET_ID,
        label        = "Micro Menu",
        designWidth  = math.max(1, bar:GetWidth() or 1),
        designHeight = math.max(1, bar:GetHeight() or 1),
        frame        = bar,
        GetDesiredHeight = function() return math.max(1, bar:GetHeight() or 1) end,
        GetStatusText    = function()
            local shown = 0
            for _, entry in pairs(adopted) do
                if entry.active and entry.button:GetParent() == bar then
                    shown = shown + 1
                end
            end
            return shown .. " buttons"
        end,
        GetOptionsArgs = function() return addon:WidgetOptions() end,
    })

    -- Blizzard's own state, mirrored on a ticker rather than by hooking
    -- UpdateMicroButtons.
    --
    -- Even the string form of hooksecurefunc leaves the global counting
    -- as tainted on Forever, and EnterEditMode calls UpdateMicroButtons:
    -- the taint log showed that call, then ClearTarget blocked, then
    -- their compact party frames erroring on a secret color, all in the
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
