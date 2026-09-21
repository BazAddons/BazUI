-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: the Profiles page
--
-- One profile picked at the top; everything below acts on that one. The
-- rows are grouped by what somebody came to the page to do rather than by
-- what kind of widget they are - which is what the old page was missing.
-- It had the right structure and the wrong contents.
--
-- Four rules it follows, each learned from the page it replaces:
--
--   A button says what it does. "Active Profile" was a button whose label
--   was a state, grayed out and unpressable, which is a status line
--   pretending to be a control. It reads "Use this profile" now, and the
--   dropdown says which one is in use.
--
--   A switch shows what it is set to. Auto-assignment was three buttons
--   you pressed and got no answer from, so the only way to find out what
--   a character was pinned to was to log in as it. They are toggles now,
--   labelled with the character, spec and class they actually mean.
--
--   Nothing is said twice. The note at the top repeated the two facts the
--   dropdown label already carried.
--
--   It is one addon. The old page talked about "all Baz Suite addons at
--   once", which stopped being true when the suite became BazUI.
--
-- Split out of Core/Profiles.lua, which is the profile system rather than
-- a page about it, and was two thirds page by the end.
---------------------------------------------------------------------------

-- The profile that cannot be deleted or renamed, asked of the profile
-- system rather than named here so the two cannot drift apart.
local function DefaultProfile()
    return (BazUI.GetFallbackProfile and BazUI:GetFallbackProfile()) or "BazUI"
end

function BazUI:GetProfileOptionsTable()
    local function Refresh()
        if BazUI.RefreshOptions then BazUI:RefreshOptions("BazUI-Profiles") end
    end

    -- Which profile the page is looking at, which is not necessarily the
    -- one in use: renaming or deleting a profile should not need you to
    -- wear it first.
    local function Viewing()
        local sv = BazUIDB
        local shown = sv and sv.profilePageSelection
        if shown and sv.profiles and sv.profiles[shown] then return shown end
        return BazUI:GetActiveProfile()
    end

    local function ProfileValues(excluding)
        local values, sorting = {}, {}
        for _, name in ipairs(BazUI:ListProfiles()) do
            if name ~= excluding then
                local label = name
                if name == BazUI:GetActiveProfile() then
                    label = label .. "  |cff00ff00(in use)|r"
                end
                values[name] = label
                sorting[#sorting + 1] = name
            end
        end
        return values, sorting
    end

    -- One auto-assign switch. The label is the thing itself - the
    -- character's name, the spec, the class - because "This class" tells
    -- you less than "Mage" at the moment you are deciding.
    local function AssignRow(scope, order)
        return {
            order = order,
            type  = "toggle",
            name  = BazUI:GetAssignmentLabel(scope) or ("This " .. scope),
            desc  = BazUI:GetAssignmentLabel(scope)
                and "Logging in here chooses this profile automatically."
                or  "Nothing to pin to yet - this character has no spec.",
            disabled = function() return BazUI:GetAssignmentLabel(scope) == nil end,
            get = function() return BazUI:GetAssignment(scope) == Viewing() end,
            set = function(_, value)
                BazUI:AssignProfile(scope, value and Viewing() or nil)
                Refresh()
            end,
        }
    end

    local shown     = Viewing()
    local isBuiltin = (shown == DefaultProfile())
    local isActive  = (shown == BazUI:GetActiveProfile())
    local isDefault = (shown == BazUI:GetDefaultProfile())

    local allValues, allSorting   = ProfileValues()
    local copyValues, copySorting = ProfileValues(shown)

    local presetValues, presetSorting = {}, {}
    for _, preset in ipairs(BazUI:GetPresets()) do
        presetValues[preset.id] = preset.name
        presetSorting[#presetSorting + 1] = preset.id
    end
    local noPresets = (#presetSorting == 0)

    return {
        name = "Profiles",
        type = "group",
        args = {
            intro = {
                order = 0.1, type = "lead",
                text = "A profile is your whole interface: where everything sits, "
                    .. "what color it is, how it behaves. Keep one, or keep "
                    .. "several and switch between them.",
            },

            pick = {
                order = 1, type = "select", name = "Profile",
                desc = "Which profile this page is about.",
                values = allValues, sorting = allSorting,
                get = function() return Viewing() end,
                set = function(_, value)
                    BazUIDB.profilePageSelection = value
                    Refresh()
                end,
            },
            newProfile = {
                order = 2, type = "execute", name = "New profile",
                desc = "Start a fresh one with the shipped layout.",
                func = function()
                    local name, n = "New Profile", 1
                    while BazUIDB.profiles[name] do
                        n = n + 1
                        name = "New Profile " .. n
                    end
                    BazUI:CreateProfile(name)
                    BazUIDB.profilePageSelection = name
                    BazUI:Print("Created profile: " .. name)
                    Refresh()
                end,
            },
            rename = {
                order = 3, type = "input", name = "Name",
                desc = isBuiltin
                    and "Default cannot be renamed. It is what BazUI falls back to."
                    or  "Rename this profile.",
                disabled = isBuiltin,
                get = function() return Viewing() end,
                set = function(_, value)
                    value = strtrim(tostring(value or ""))
                    if value == "" or value == Viewing() then return end
                    if BazUI:RenameProfile(Viewing(), value) then
                        BazUIDB.profilePageSelection = value
                        Refresh()
                    else
                        BazUI:Print("|cffff4444There is already a profile called "
                            .. value .. ".|r")
                    end
                end,
            },

            usingHeader = { order = 10, type = "header", name = "Using it" },
            use = {
                order = 11, type = "execute", name = "Use this profile",
                desc = isActive and "This is the one you are wearing."
                    or "Switch to it now. Everything on screen is rearranged.",
                disabled = isActive,
                func = function()
                    local name = Viewing()
                    BazUI:SetActiveProfile(name)
                    BazUI:Print("Switched to: " .. name)
                    Refresh()
                end,
            },
            makeDefault = {
                order = 12, type = "execute", name = "Use for new characters",
                desc = isDefault and "New characters already start on this one."
                    or "A character logging in for the first time starts here.",
                disabled = isDefault,
                func = function()
                    BazUI:SetDefaultProfile(Viewing())
                    Refresh()
                end,
            },
            assignNote = {
                order = 13, type = "note", style = "info",
                text = "Pin this profile to a character, spec or class and it is "
                    .. "chosen for you on login. The most specific pin wins: a "
                    .. "character beats a spec, and a spec beats a class.",
            },
            assignCharacter = AssignRow("character", 14),
            assignSpec      = AssignRow("spec", 15),
            assignClass     = AssignRow("class", 16),

            startHeader = { order = 20, type = "header", name = "Starting from something" },
            preset = {
                order = 21, type = "select", name = "Shipped layout",
                desc = noPresets
                    and "This build ships no layouts to choose from yet."
                    or  "One of the arrangements BazUI comes with. Picking one "
                     .. "makes a NEW profile and switches to it - nothing you "
                     .. "have is touched.",
                disabled = noPresets,
                values = presetValues, sorting = presetSorting,
                get = function() return nil end,
                set = function(_, value)
                    local made = BazUI:CreateProfileFromPreset(value)
                    if made then
                        BazUIDB.profilePageSelection = made
                        BazUI:Print("Created profile from layout: " .. made)
                    end
                    Refresh()
                end,
            },
            copyFrom = {
                order = 22, type = "select", name = "Copy another profile in",
                desc = "Overwrite this profile with everything from another one.",
                disabled = (#copySorting == 0),
                values = copyValues, sorting = copySorting,
                get = function() return nil end,
                set = function(_, value)
                    BazUI:CopyProfile(value, Viewing())
                    BazUI:Print("Copied " .. value .. " into " .. Viewing() .. ".")
                    Refresh()
                end,
            },

            shareHeader = { order = 30, type = "header", name = "Sharing" },
            export = {
                order = 31, type = "execute", name = "Export",
                desc = "A string holding this whole profile, to send to somebody else.",
                func = function()
                    local sv = BazUIDB
                    BazUI:OpenCopyDialog({
                        title    = "Export profile",
                        subtitle = Viewing() .. " - copy this and send it on.",
                        content  = BazUI:Serialize(sv.profiles[Viewing()]),
                        editable = true,
                        width    = 640, height = 420,
                    })
                end,
            },
            import = {
                order = 32, type = "execute", name = "Import",
                desc = "Paste a profile somebody sent you. It arrives as a new "
                    .. "profile; nothing you have is replaced.",
                func = function()
                    BazUI:OpenCopyDialog({
                        title    = "Import profile",
                        subtitle = "Paste a profile string here, then Import.",
                        content  = "",
                        editable = true,
                        width    = 640, height = 420,
                        acceptText = "Import",
                        onAccept = function(text)
                            local data = BazUI:Deserialize(text)
                            if type(data) ~= "table" then
                                BazUI:Print("|cffff4444That does not look like a BazUI profile.|r")
                                return
                            end
                            local name, n = "Imported", 1
                            while BazUIDB.profiles[name] do
                                n = n + 1
                                name = "Imported " .. n
                            end
                            BazUIDB.profiles[name] = data
                            BazUIDB.profilePageSelection = name
                            BazUI:Print("Imported as: " .. name)
                            Refresh()
                        end,
                    })
                end,
            },

            undoHeader = { order = 40, type = "header", name = "Starting over" },
            reset = {
                order = 41, type = "execute", name = "Reset to defaults",
                desc = "Put this profile back to the shipped layout. Anything "
                    .. "you changed in it is lost.",
                func = function()
                    BazUI:ResetProfile(Viewing())
                    BazUI:Print("Reset: " .. Viewing())
                    Refresh()
                end,
            },
            delete = {
                order = 42, type = "execute", name = "|cffff4444Delete|r",
                desc = isBuiltin
                    and "Default cannot be deleted. It is what BazUI falls back to."
                    or  "Delete it. Anything pinned to it falls back to Default.",
                disabled = isBuiltin,
                func = function()
                    local gone = Viewing()
                    BazUI:DeleteProfile(gone)
                    BazUIDB.profilePageSelection = nil
                    BazUI:Print("Deleted: " .. gone)
                    Refresh()
                end,
            },
        },
    }
end
