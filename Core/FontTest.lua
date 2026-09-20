-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: does the text come out as letters?
--
-- A window of sample text in the alphabets the addon has to cope with,
-- each line drawn twice: once in the face BazUI is using, and once in
-- the game's own. Anything that reads as a row of boxes on the left and
-- as words on the right is text the addon would spoil.
--
-- It exists because the question cannot be answered from an English
-- client by reading the code. BazUI shipped a Latin-only face and used
-- it for every label, which drew the whole interface as boxes on a
-- Russian client - and the first fix for it was verified by inspection,
-- which was not enough: a player on a ruRU client reported it still
-- broken the same day.
--
-- So this shows the answer instead of arguing it, and it shows the
-- reasoning above it: the locale, whether the face can spell it, and
-- word by word which of the game's own strings that verdict was reached
-- from. A verdict of "yes it can" on a Russian client would be the bug,
-- and this is where it would be visible.
--
--   /baz fonts
---------------------------------------------------------------------------

local Theme = BazUI.Skin and BazUI.Skin.Theme

---------------------------------------------------------------------------
-- What to write
--
-- Real words rather than alphabet soup, because a missing character is
-- easier to see in something that is meant to read as a sentence. Kept
-- short so a narrow window still shows the whole line.
---------------------------------------------------------------------------

local SAMPLES = {
    { label = "English",   text = "The quick brown fox" },
    { label = "Latin-1",   text = "Grüße, Fähigkeit, Nähe, çaça, año" },
    { label = "Latin Ext", text = "Zażółć gęślą jaźń, Příliš žluťoučký" },
    { label = "Cyrillic",  text = "Привет, Персонаж, Заклинания" },
    { label = "Greek",     text = "Γειά σου Κόσμε" },
    { label = "Korean",    text = "안녕하세요 주문서" },
    { label = "Chinese",   text = "你好，法术书" },
    { label = "Japanese",  text = "こんにちは、呪文書" },
}

-- The game's own words the locale verdict is reached from. Kept in step
-- with LOCALE_WORDS in Skin/Theme.lua: if one of these does not exist on
-- a client, the verdict is reached without it, and a list where none of
-- them exist reaches no verdict at all - which is the failure this panel
-- is here to make visible.
local LOCALE_WORDS = {
    "CHARACTER", "SPELLBOOK", "GAMEOPTIONS_MENU",
    "INVENTORY_TOOLTIP", "COMBAT", "LOOT",
}

local ROW_H = 20
local PAD = 14

local panel

---------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------

local function AddLine(parent, y, text, color, indent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + (indent or 0), y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    if color then fs:SetTextColor(unpack(color)) end
    return fs, y - ROW_H
end

-- One sample, twice. Left is whatever BazUI would draw it with, right is
-- the game's own face - the comparison is the whole point, because a
-- line that is boxes in both is a client without that alphabet at all
-- and not something the addon can be blamed for or fix.
local function AddSample(parent, y, sample, width, rows)
    local name = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    name:SetWidth(80)
    name:SetJustifyH("LEFT")
    name:SetText(sample.label)
    name:SetTextColor(0.7, 0.7, 0.7)

    local half = math.max(120, (width - PAD * 2 - 90) / 2)

    local ours = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ours:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 90, y)
    ours:SetWidth(half)
    ours:SetJustifyH("LEFT")
    ours:SetText(sample.text)
    -- Deliberately not through Theme.SetText: this side is meant to show
    -- what the chosen face does with it, boxes and all.
    local face = Theme and Theme.FontFile and Theme.FontFile()
    if face then
        local _, size, flags = ours:GetFont()
        ours:SetFont(face, size or 12, flags or "")
    end

    -- The right hand side is the decision the addon would really make
    -- for this string, not simply the body font: a Cyrillic name in an
    -- English client needs a face the client keeps for Russian, because
    -- its English one has no Cyrillic in it either.
    local theirs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    theirs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 90 + half + 10, y)
    theirs:SetWidth(half)
    theirs:SetJustifyH("LEFT")
    theirs:SetText(sample.text)
    local chosen = Theme and Theme.FaceFor and Theme.FaceFor(sample.text)
    if chosen then
        local _, size, flags = theirs:GetFont()
        theirs:SetFont(chosen, size or 12, flags or "")
    end

    -- Which file that was, in small print underneath, because "it works"
    -- and "it works because the client had this one" are different
    -- answers and only the second one travels.
    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 90 + half + 10, y - 15)
    note:SetWidth(half)
    note:SetJustifyH("LEFT")
    note:SetTextColor(0.55, 0.55, 0.55)
    local script = Theme and Theme.ScriptFaceFor and Theme.ScriptFaceFor(sample.text)
    note:SetText(script and script:gsub(".*\\\\", "")
        or (chosen and chosen:gsub(".*\\\\", "")) or "")

    rows[#rows + 1] = name
    rows[#rows + 1] = ours
    rows[#rows + 1] = theirs
    rows[#rows + 1] = note
    return y - ROW_H - 18
end

local function Build()
    if panel then return panel end

    panel = BazUI:CreatePortraitWindow("BazUIFontTest", {
        title    = "Font check",
        portrait = "Interface\\Icons\\INV_Misc_Book_09",
        width    = 640,
        height   = 560,
        strata   = "DIALOG",
        uiSpecialFrame = true,
    })

    -- It scrolls, because how much there is to say depends on how many
    -- of the game's words this client has and how many samples are in
    -- the list, and a panel sized for today's answer is a panel that
    -- quietly cuts off tomorrow's.
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -30)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 10)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, (self.bazContentH or 0) - self:GetHeight())
        local next = (self:GetVerticalScroll() or 0) - delta * 30
        if next < 0 then next = 0 end
        if next > maxScroll then next = maxScroll end
        self:SetVerticalScroll(next)
    end)
    panel.scroll = scroll

    panel.body = CreateFrame("Frame", nil, scroll)
    panel.body:SetSize(1, 1)
    scroll:SetScrollChild(panel.body)

    return panel
end

-- Thrown away and made again every time it opens, because every line of
-- it is a reading taken at that moment and a stale one would be worse
-- than none.
local function Fill()
    local body = panel.body
    if body.rows then
        for _, fs in ipairs(body.rows) do fs:Hide() end
    end
    body.rows = {}

    local width = panel:GetWidth()
    local y = -PAD
    local fs

    ------------------------------------------------------------------
    -- The verdict
    ------------------------------------------------------------------
    local locale = (GetLocale and GetLocale()) or "?"
    local drawable = Theme and Theme.IsLocaleDrawable and Theme.IsLocaleDrawable()
    local face = (Theme and Theme.FontFile and Theme.FontFile()) or "?"
    local override = Theme and Theme.FaceOverride and Theme.FaceOverride()

    fs, y = AddLine(body, y, "Client language: |cffffd700" .. locale .. "|r")
    body.rows[#body.rows + 1] = fs

    fs, y = AddLine(body, y, "BazUI's face can spell it: "
        .. (drawable and "|cff73c773yes|r" or "|cffff6060no|r"))
    body.rows[#body.rows + 1] = fs

    fs, y = AddLine(body, y, "Drawing with: |cffffd700" .. tostring(face) .. "|r")
    body.rows[#body.rows + 1] = fs

    fs, y = AddLine(body, y, "Forcing a face: "
        .. (override and ("|cffffd700" .. override .. "|r") or "no, text keeps its own"))
    body.rows[#body.rows + 1] = fs

    local custom = Theme and Theme.CustomFontFile and Theme.CustomFontFile()
    fs, y = AddLine(body, y, "Your own font: " .. (custom
        and "|cff73c773loaded|r"
        or "|cff888888none - there is a note in the addon's Fonts folder "
           .. "saying what to put there and which one to get|r"))
    body.rows[#body.rows + 1] = fs

    y = y - 6

    ------------------------------------------------------------------
    -- How that verdict was reached
    ------------------------------------------------------------------
    fs, y = AddLine(body, y, "Read from the game's own words:", { 0.8, 0.8, 0.8 })
    body.rows[#body.rows + 1] = fs

    local found = 0
    for _, key in ipairs(LOCALE_WORDS) do
        local word = _G[key]
        local line
        if type(word) ~= "string" or word == "" then
            line = "|cff888888" .. key .. " - this client has not got it|r"
        else
            found = found + 1
            local can = Theme and Theme.CanDraw and Theme.CanDraw(word)
            line = key .. " = |cffffd700" .. word .. "|r  "
                .. (can and "|cff73c773can draw|r" or "|cffff6060cannot draw|r")
        end
        fs, y = AddLine(body, y, line, nil, 12)
        body.rows[#body.rows + 1] = fs
    end

    if found == 0 then
        fs, y = AddLine(body, y,
            "|cffff6060None of them exist here, so nothing was read and the answer "
            .. "above is a guess.|r", nil, 12)
        body.rows[#body.rows + 1] = fs
    end

    y = y - 10

    ------------------------------------------------------------------
    -- The samples
    ------------------------------------------------------------------
    fs, y = AddLine(body, y, "Left: BazUI's face.    Right: the game's.", { 0.8, 0.8, 0.8 })
    body.rows[#body.rows + 1] = fs
    y = y - 4

    for _, sample in ipairs(SAMPLES) do
        y = AddSample(body, y, sample, width, body.rows)
    end

    body:SetSize(width - 10, math.abs(y) + PAD)
    panel.scroll.bazContentH = math.abs(y) + PAD
    panel.scroll:SetVerticalScroll(0)

end

function BazUI:ShowFontTest()
    if not Theme then
        BazUI:Print("The skin is not up yet.")
        return
    end
    Build()
    Fill()
    panel:Show()
end
