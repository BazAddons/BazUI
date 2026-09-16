-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI Options: User Manual
--
-- One User Manual for the whole addon, sitting at the foot of the module
-- list with a tab per module across the top of it. Any BazUI-compatible
-- addon can add to it with BazUI:RegisterUserGuide(addonName, guide), and
-- gets a tab of its own.
--
-- A guide is one scrolling page, built from the same blocks and drawn by
-- the same code as every other page in the options window: headings,
-- paragraphs, lists, notes, tables.
--
-- It used to be a tree of pages with a list of links down the left, which
-- made the manual the one part of the settings that neither looked nor
-- behaved like the settings - and made finding a sentence a matter of
-- clicking through twenty links to see which page held it. Scrolling one
-- page and reading the headings is quicker, and it is what the reader is
-- already doing everywhere else in this window.
--
-- Guide format:
--
--   {
--       title = "Bags",                   -- optional; defaults to the name
--       intro = "One line about it.",     -- optional; opens the page
--       pages = {
--           {
--               title  = "Display Modes", -- becomes a heading
--               blocks = {
--                   { type = "paragraph", text = "..." },
--                   { type = "list", items = { "...", "..." } },
--                   { type = "note", text = "..." },
--               },
--               children = { { title = "...", blocks = { ... } } },
--           },
--       },
--   }
--
-- A page's title becomes a heading sized by how deep it sits: h1 for a
-- top-level page, h2 for its children, h3 below that. That is the whole
-- navigation, and it is why a page is worth a title even when it holds
-- two sentences.
--
-- Guides written the old way still work. A page carrying `text` or
-- `sections` instead of `blocks` is converted, and a block list that
-- nests a collapsible is flattened into a heading and what was inside it -
-- a page you scroll has no use for things that fold.
--
-- Text supports WoW escape codes (|cffxxxxxx...|r for colors).
---------------------------------------------------------------------------

local guides = {}      -- [addonName] = guide table

---------------------------------------------------------------------------
-- A guide, flattened into one page of blocks
---------------------------------------------------------------------------

-- A page's content, whichever way it was written.
local function PageToBlocks(page)
    if not page then return {} end
    if page.blocks then return page.blocks end

    local blocks = {}
    if page.text and page.text ~= "" then
        blocks[#blocks + 1] = { type = "paragraph", text = page.text }
    end
    for _, section in ipairs(page.sections or {}) do
        if section.heading and section.heading ~= "" then
            blocks[#blocks + 1] = { type = "h3", text = section.heading }
        end
        if section.text and section.text ~= "" then
            blocks[#blocks + 1] = { type = "paragraph", text = section.text }
        end
    end
    return blocks
end

-- How far down a title sits decides how big it is drawn. Anything deeper
-- than the smallest heading stays at the smallest heading: a manual that
-- needs five levels needs rewriting, not a fifth size.
local HEADINGS = { "h1", "h2", "h3", "h4" }

local function Heading(depth)
    return HEADINGS[math.min(depth + 1, #HEADINGS)]
end

local AppendBlocks

function AppendBlocks(out, blocks, depth)
    for _, block in ipairs(blocks or {}) do
        if block.type == "collapsible" then
            if block.title and block.title ~= "" then
                out[#out + 1] = { type = block.style or Heading(depth), text = block.title }
            end
            AppendBlocks(out, block.blocks, depth + 1)
        else
            out[#out + 1] = block
        end
    end
end

local AppendPages

function AppendPages(out, pages, depth)
    for _, page in ipairs(pages or {}) do
        if page.title and page.title ~= "" then
            out[#out + 1] = { type = Heading(depth), text = page.title }
        end
        AppendBlocks(out, PageToBlocks(page), depth + 1)
        AppendPages(out, page.children, depth + 1)
    end
end

-- A guide written as a flat list of sections, read as pages.
local function NormalizeGuide(guide)
    if guide.pages and #guide.pages > 0 then return guide end
    if not (guide.sections and #guide.sections > 0) then return guide end

    local pages = {}
    for _, section in ipairs(guide.sections) do
        pages[#pages + 1] = { title = section.heading, text = section.text }
    end
    -- A copy: the caller's table is theirs.
    return { title = guide.title, intro = guide.intro, pages = pages }
end

-- The options table the page is drawn from.
--
-- Blocks are copied rather than handed straight over, because the
-- renderer writes a sort key onto every entry it is given and these
-- tables belong to whoever wrote the guide.
local function GuideOptions(addonName)
    local guide = NormalizeGuide(guides[addonName] or {})

    local blocks = {}
    if guide.intro and guide.intro ~= "" then
        blocks[#blocks + 1] = { type = "lead", text = guide.intro }
    end
    AppendPages(blocks, guide.pages, 0)

    local args = {}
    for index, block in ipairs(blocks) do
        local copy = {}
        for key, value in pairs(block) do copy[key] = value end
        copy.order = index
        args["block" .. index] = copy
    end

    return { name = guide.title or addonName, type = "group", args = args }
end

---------------------------------------------------------------------------
-- One manual, a tab per module
--
-- Every guide used to hang off the module it described, which put a User
-- Manual tab on eleven different pages and no single place to go and
-- read. They are collected into one entry of their own at the foot of the
-- list instead, with the modules as tabs across the top of it.
--
-- The entry is made after login rather than as guides register, and this
-- is the whole reason: the settings panel lists categories in the order
-- they were created, and guides are registered when their file loads -
-- long before the modules make their own. Made then, the manual would sit
-- at the top of the list. Made a frame after login, when every module has
-- had its turn, it sits at the bottom where it was asked for.
---------------------------------------------------------------------------

local MANUAL_KEY = "UserManual"
local registered, guideOrder, manualBuilt = {}, {}, false

-- What to call a module in the tab strip: what the settings call it, so
-- it reads "Micro Menu" rather than "MicroMenu".
local function GuideLabel(addonName)
    local config = BazUI.addons and BazUI.addons[addonName]
    if config and config.title then return config.title end
    local guide = guides[addonName]
    if guide and guide.title then return guide.title end
    return addonName
end

local function AddGuidePage(addonName)
    -- A module switched off in this profile has no settings showing, and
    -- a manual for something that is not running is the same noise.
    if BazUI.addons and BazUI.addons[addonName]
        and BazUI.IsModuleEnabled and not BazUI:IsModuleEnabled(addonName) then
        return
    end
    -- BazUI's own first; the rest fall through to alphabetical.
    local order = addonName == "BazUI" and 1 or nil
    BazUI:AddToSettings("UserGuide_" .. addonName, GuideLabel(addonName), MANUAL_KEY, order)
end

function BazUI:RegisterUserGuide(addonName, guide)
    if type(addonName) ~= "string" or addonName == "" then return end
    if type(guide) ~= "table" then return end

    guides[addonName] = guide

    local key = "UserGuide_" .. addonName
    local entry = BazUI._optionsTables[key] or {}
    entry.func = function() return GuideOptions(addonName) end
    entry.customRender = nil
    BazUI._optionsTables[key] = entry

    if not registered[addonName] then
        registered[addonName] = true
        guideOrder[#guideOrder + 1] = addonName
    end

    -- One that arrives after the manual has been built - another addon's,
    -- or a module loading late - takes its place straight away.
    if manualBuilt then
        AddGuidePage(addonName)
        if BazUI.RefreshOptions then BazUI:RefreshOptions(key) end
    end
end

BazUI:QueueForLogin(function()
    -- A frame after login: see above, this is what puts it last.
    C_Timer.After(0, function()
        if manualBuilt then return end

        BazUI:RegisterOptionsTable(MANUAL_KEY, function()
            return { name = "User Manual", type = "group", args = {} }
        end)
        BazUI:AddToSettings(MANUAL_KEY, "User Manual")
        manualBuilt = true

        for _, addonName in ipairs(guideOrder) do AddGuidePage(addonName) end
    end)
end)

BazUI._userGuides = guides

---------------------------------------------------------------------------
-- BazUI's own built-in user guide
---------------------------------------------------------------------------

BazUI:RegisterUserGuide("BazUI", {
    title = "BazUI",
    intro = "BazUI is one addon that replaces a stack of separate UI addons. Pick a topic on the left.",
    pages = {
        {
            title = "Welcome",
            blocks = {
                { type = "lead", text = "BazUI gathers the Baz Suite into a single addon built for World of Warcraft: Forever. Drawers hold the minimap, minimap buttons, quest tracker and info bar; chat and bags follow as modules." },
                { type = "h2", text = "Slash commands" },
                { type = "table",
                  columns = { "Command", "Effect" },
                  rows = {
                      { "/bazui",                 "Open BazUI in Options > AddOns" },
                      { "/bazui profile <name>",  "Switch to a profile" },
                      { "/bazui profiles",        "List profiles" },
                      { "/bazui default <name>",  "Set the profile new characters start on" },
                      { "/bui",                   "Short alias for /bazui" },
                  },
                },
                { type = "note", style = "tip", text = "BazUI lives in the standard Options > AddOns list. Each module is an entry under BazUI, and a module's pages are tabs across the top of its panel." },
            },
        },
        {
            title = "Profiles",
            blocks = {
                { type = "lead", text = "One profile covers every module. Switch profiles from the Profiles page or with /bazui profile, and assign profiles per character, class or specialisation." },
                { type = "list", items = {
                    "Create, copy, rename and delete profiles from the Profiles page.",
                    "A profile can be set as the default for new characters.",
                    "Modules react to profile changes immediately; no reload needed.",
                }},
            },
        },
    },
})
