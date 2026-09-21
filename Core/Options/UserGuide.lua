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
    intro = "One addon in place of a shelf of them, built for World of "
        .. "Warcraft: Forever. Pick a module from the tabs above.",
    pages = {
        {
            title = "How it is put together",
            blocks = {
                { type = "paragraph", text = "BazUI is one addon made of modules, each replacing something you would otherwise have installed separately: action bars, unit frames, nameplates, auras, bags, chat, the minimap and its drawers, notifications, a micro menu, the tooltip, the codex, and a handful of quality of life tweaks." },
                { type = "paragraph", text = "They share one options window, one profile system and one look. That is the point of it being one addon rather than twelve: a color you change is changed everywhere, a profile you switch switches all of it, and nothing has to be kept in step by hand." },
                { type = "note", style = "tip", text = "BazUI sits in the standard |cffffd700Options > AddOns|r list. Each module is an entry under BazUI, and that module's pages are tabs across the top of its panel - including this manual, which has a tab per module." },
                { type = "h3", text = "The minimap button" },
                { type = "paragraph", text = "One button for the whole suite rather than one per module." },
                { type = "table", columns = { "You do this", "It does this" }, rows = {
                    { "Left-click", "Opens the codex." },
                    { "Right-click", "Opens these settings." },
                    { "Middle-click", "BazUI Edit Mode, for moving and resizing what BazUI draws. Not while you are fighting." },
                    { "Drag it", "Moves it round the minimap ring, and it stays where you put it." },
                } },
                { type = "note", text = "|cffffd700Show the minimap button|r on the General page takes it away. Every module it opens has a slash command as well, so nothing is lost with it." },
            },
        },
        {
            title = "Profiles",
            blocks = {
                { type = "paragraph", text = "|cffffd700One profile covers every module.|r Switch it and your bars, frames, bags, chat and drawers all move to what that profile says." },
                { type = "paragraph", text = "Everything happens on the |cffffd700Profiles|r page. The dropdown at the top picks which profile the page is |cffffd700about|r, which is not the same as which one you are using - |cffffd700Use this profile|r is what switches you." },
                { type = "table", columns = { "Control", "What it does" }, rows = {
                    { "New profile", "A fresh one with the shipped layout." },
                    { "Name", "Renames the one you are looking at." },
                    { "Use this profile", "Switches to it. Every module moves at once, with no reload." },
                    { "Use for new characters", "Makes it the one a character with no profile of its own starts on." },
                    { "Shipped layout", "Picking Classic or Modern makes a new profile from that layout and switches to it. It does not overwrite what you are looking at." },
                    { "Copy another profile in", "|cffffd700Overwrites|r the profile you are looking at with everything from another one." },
                    { "Export / Import", "The whole profile as a string you can paste to somebody. An import always arrives as a new profile, so it can never land on top of yours." },
                    { "Reset to defaults", "Back to shipped, for this profile." },
                    { "Delete", "Removes it. Anything pinned to it falls back to Default." },
                } },
                { type = "h3", text = "Picking one automatically" },
                { type = "paragraph", text = "|cffffd700Auto-assignment|r pins a profile to this character, this class or this spec, so logging in picks the right one. |cffffd700The most specific pin wins|r: a character beats a spec, and a spec beats a class." },
                { type = "note", text = "The |cffffd700Default|r profile cannot be renamed or deleted. Something has to be there to fall back to." },
            },
        },
        {
            title = "Settings that stay put",
            blocks = {
                { type = "paragraph", text = "On WoW: Forever, nothing an addon saves comes back. The client writes the file at every logout and never reads one, for every addon on your machine, which is why so much of your interface resets itself each time you reload." },
                { type = "paragraph", text = "BazUI keeps its settings somewhere the client does read. Nothing to switch on and nothing to set up: your layout, your bars, your profiles and your window positions simply come back, through a reload, a logout and a full restart." },
                { type = "note", style = "tip", text = "On a client that reads saved variables properly, BazUI uses those instead and tidies away anything it left behind. The day Forever is fixed, this stops mattering on its own." },
                { type = "h3", text = "Other addons" },
                { type = "paragraph", text = "The bug is not BazUI's and neither is the damage, so BazUI can carry another addon's settings the same way. You ask for it by name, one addon at a time." },
                { type = "table", columns = { "Command", "What it does" }, rows = {
                    { "/baz persist", "Lists what is being looked after." },
                    { "/baz persist add TomTom TomTomDB", "Starts keeping that addon's settings. Name the globals it saves; the client will not tell us." },
                    { "/baz persist remove TomTom", "Stops, and lets go of what was kept." },
                } },
                { type = "note", text = "|cffffd700Only addons that load after BazUI|r can be helped, because the settings have to be put back before that addon reads them. Alphabetically that is most of them, but not all. An addon that cannot be helped says so rather than pretending." },
                { type = "note", style = "tip", text = "The globals an addon saves are in its own .toc file, on the |cffffd700## SavedVariables|r line." },
            },
        },
        {
            title = "The look",
            blocks = {
                { type = "paragraph", text = "Almost everything BazUI draws is a plain texture tinted by a handful of colors, which means the whole look is a list of numbers rather than a folder of art. The |cffffd700Skin|r page is where you change it." },
                { type = "list", items = {
                    "|cffffd700Colors|r, grouped by what they are for, each with a picker.",
                    "|cffffd700Borders|r as a list of bands running outward from the fill. Change a color or a thickness, add as many bands as you like, or take them all off for a bare edge. Every edge follows: bars, panels, nameplates, round buttons, tooltips, popups and menus.",
                    "|cffffd700Bar fill|r - gloss, marble, flat, or a gradient worked out from each bar's own color. With LibSharedMedia installed, everything it knows about is in the list too.",
                } },
                { type = "paragraph", text = "Changes apply as you make them. A skin can be exported and imported as a string, and another addon can ship one." },
            },
        },
        {
            title = "Moving things around",
            blocks = {
                { type = "paragraph", text = "Drag one frame near another in Edit Mode and they join, so from then on they move as a stack and anything you do to the one above moves the one below with it. A green line shows where it is about to land before you let go." },
                { type = "h3", text = "When you do not want that" },
                { type = "paragraph", text = "Snapping is right nearly all of the time, which is exactly the problem with it: the one occasion you want two things a few pixels apart and |cffffd700not|r joined, there is no way to say so. There are two." },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Hold to move freely", "Hold this key while dragging and that one drag ignores everything it passes, however close. Let go and snapping is back. Alt by default." },
                    { "Snap frames together when dragging", "Off means nothing ever snaps, for placing everything by hand." },
                } },
                { type = "note", text = "The key is read while you drag, not when you started, so you can change your mind half way - the landing line goes out the moment you hold it and comes back when you let go. That is the quickest way to see which of the two you are getting." },
                { type = "paragraph", text = "Both are on |cffffd700BazUI > General|r, under Moving things, and they apply everywhere that docks: bars, unit frames, auras, drawers and the rest." },
            },
        },

        {
            title = "Turning modules off",
            blocks = {
                { type = "paragraph", text = "|cffffd700BazUI > General|r has a switch for each module that replaces something. Turn one off and the game's own version comes back - the stock bags, the stock chat, the stock nameplates. Turning a module on or off takes a reload, and you are asked for one when you do it." },
                { type = "note", text = "|cffffd700The codex and the tooltip have no switch.|r Neither takes anything away from the game: the codex is a window that only opens when you ask for it, and the tooltip module styles the game's own rather than replacing it. There would be nothing to come back." },
                { type = "h3", text = "What else is on that page" },
                { type = "table", columns = { "Setting", "What it does" }, rows = {
                    { "Show the minimap button", "The one button for the whole suite." },
                    { "Interface font", "The face BazUI writes in." },
                    { "Borrow the game's font where ours cannot spell", "BazUI's own face is Latin only. With this on, text in an alphabet it cannot write is drawn in a face from your client that can. |cffffd700/baz fonts|r shows what happens to eight alphabets." },
                    { "Hide the Issue Reporter", "Takes away the client's own bug window." },
                    { "Show welcome messages", "The line BazUI says when you log in." },
                } },
                { type = "note", text = "Blizzard's own frames are only hidden where you ask, on a switch per frame. Nothing is suppressed on your behalf." },
            },
        },
        {
            title = "Slash commands",
            blocks = {
                { type = "table",
                  columns = { "Command", "What it does" },
                  rows = {
                      { "/baz",                   "Opens BazUI in Options > AddOns. /bazui and /bui do the same." },
                      { "/baz check",           "Reports anything the addon expects from the game's own interface and cannot find. Worth running first on a new client build - it tells a real bug from a client that has moved something." },
                      { "/baz profile <name>",  "Switches profile. Bare, it says which one you are on." },
                      { "/baz profiles",        "Lists them." },
                      { "/baz default <name>",  "Sets the profile new characters start on." },
                      { "/baz edit",            "Opens Edit Mode, which is where nearly everything is moved and sized." },
                      { "/baz fonts",           "Writes sample text in eight alphabets, in BazUI's face and in the one it would borrow, naming the file each came from. The answer to text coming out as empty boxes." },
                      { "/baz errors",          "Shows what BazUI has caught going wrong." },
                      { "/baz taint",           "Names the game's own values BazUI has taken over. |cffffd700/baz taint all|r widens it. The thing to run when the game says an action was blocked." },
                      { "/baz audit [module]",  "Checks a module's settings against what it actually registered." },
                      { "/baz dock [snap]",     "Reports on the docking system, and on snapping." },
                      { "/baz atlas [names]",   "Looks up the game's own art by name." },
                      { "/baz export",          "Prints the profile you are on as text." },
                      { "/baz sv",              "Reports on saved variables, which on this client are written and never read back." },
                      { "/baz settings",        "Opens the settings. Every BazUI command takes this, and |cffffd700help|r." },
                  },
                },
                { type = "paragraph", text = "Each module has its own command too - |cffffd700/bb|r for bars, |cffffd700/bbg|r for bags, |cffffd700/bc|r for chat, |cffffd700/bwd|r for drawers, and so on. They are listed on each module's page of this manual." },
            },
        },
    },
})
