-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications
local BNC = addon.API

local DEDUPE_WINDOW = 5  -- seconds

-- Recent-window dedupe cache keyed by "module|title". Replaces an O(n)
-- linear scan of addon.notifications on every Push. Burst events
-- (looting a trash pull, multi-quest turn-ins) used to scan up to 50
-- entries per push; now it's a single hash lookup.
--
-- Entries are lazily evicted: if a lookup hits an expired entry we
-- drop it. We also clean stale entries opportunistically when the
-- cache grows past CLEAN_THRESHOLD.
local dedupeCache = {}
local CLEAN_THRESHOLD = 64

local function DedupeKey(module, title)
    return module .. "\31" .. (title or "")
end

local function DedupeLookup(key, now)
    local hit = dedupeCache[key]
    if not hit then return nil end
    if (now - hit.timestamp) >= DEDUPE_WINDOW then
        dedupeCache[key] = nil
        return nil
    end
    return hit.notif
end

local function DedupeRemember(key, notif)
    dedupeCache[key] = { notif = notif, timestamp = notif.timestamp }
    -- Opportunistic eviction so the cache doesn't grow unbounded over
    -- a long session. Cheap to scan a small dict; rare to fire.
    local count = 0
    for _ in pairs(dedupeCache) do count = count + 1 end
    if count > CLEAN_THRESHOLD then
        local now = GetTime()
        for k, v in pairs(dedupeCache) do
            if (now - v.timestamp) >= DEDUPE_WINDOW then
                dedupeCache[k] = nil
            end
        end
    end
end


---------------------------------------------------------------------------
-- The chat box as a destination
--
-- Printed the way the game prints its own lines, so a notification sent
-- here reads as part of the stream rather than as an addon shouting in
-- it: the source's name in gold, then the title, then the detail.
---------------------------------------------------------------------------

function BNC.PrintToChat(notification)
    local frame = DEFAULT_CHAT_FRAME
    if not frame then return end

    local moduleName = notification.module
    local moduleDef = addon.modules and addon.modules[notification.module]
    if moduleDef and moduleDef.name then moduleName = moduleDef.name end

    local line = ("|cffffd700%s:|r %s"):format(moduleName or "BazUI",
        notification.title or "")
    if notification.message and notification.message ~= "" then
        line = line .. " |cffd9c7a0" .. notification.message .. "|r"
    end
    frame:AddMessage(line)
end

function BNC:Push(data)
    if not data or not data.module then return end

    -- Check module exists and is enabled
    if not addon.modules[data.module] then return end
    if not BNC:IsModuleEnabled(data.module) then return end

    local realTime = time()
    local now = GetTime()

    -- Deduplication: O(1) hash lookup against the recent-window cache.
    local key = DedupeKey(data.module, data.title)
    local existing = DedupeLookup(key, now)
    if existing then
        -- Update existing notification instead of creating a duplicate
        existing.message = data.message or existing.message
        existing.timestamp = now
        existing.realTime = realTime
        existing.dupeCount = (existing.dupeCount or 1) + 1
        existing.priority = data.priority or existing.priority
        dedupeCache[key].timestamp = now  -- refresh window

        -- Save to persistent history even for deduped entries
        if addon.History_AppendEntries then
            addon.History_AppendEntries({
                {
                    module = existing.module,
                    title = existing.title,
                    message = existing.message,
                    icon = existing.icon,
                    priority = existing.priority,
                    realTime = realTime,
                },
            })
        end

        addon.Events:Trigger("NOTIFICATION_UPDATED", existing)
        return existing
    end

    addon.notificationCounter = addon.notificationCounter + 1

    local notification = {
        id = addon.notificationCounter,
        module = data.module,
        title = data.title or "",
        message = data.message or "",
        icon = data.icon or addon.modules[data.module].icon,
        priority = data.priority or "normal",
        timestamp = now,
        realTime = realTime,
        onClick = data.onClick,
        read = false,
        dismissed = false,
        silent = data.silent or false,
        duration = data.duration,
        waypoint = data.waypoint,
        itemLink = data.itemLink,
        dupeCount = 1,
    }

    -- Where this one goes. A source names the event it came from, and
    -- the three destination switches for that event decide the rest. A
    -- source that names nothing keeps the old behavior: the panel, and
    -- a toast unless it asked to be silent.
    local def = data.event and BNC:GetEventDef(data.module, data.event) or nil
    local toPanel = true
    local toChat  = false
    if def then
        -- A toast and a line in the history are one destination: this
        -- module. Chat is the other.
        toPanel = BNC:GetEventDestination(data.module, def, "toast")
        toChat  = BNC:GetEventDestination(data.module, def, "chat")
        if not toPanel then notification.silent = true end
    end

    if toChat then BNC.PrintToChat(notification) end

    if not toPanel then
        -- Not kept, but it may still have a toast or a sound to raise,
        -- so the rest of this runs.
        if not notification.silent then
            local enabled = not addon.db or addon.db.toastsEnabled ~= false
            if enabled and not (addon.IsDND and addon.IsDND()) then
                addon.Events:Trigger("TOAST_REQUESTED", notification)
            end
        end
        return notification
    end

    -- Insert at beginning (newest first)
    table.insert(addon.notifications, 1, notification)

    -- Register in dedupe cache so a follow-up duplicate within the
    -- window collapses onto this notification.
    DedupeRemember(key, notification)

    -- Trim to max notifications in panel
    if addon.db then
        local max = addon.db.maxHistory or 50
        while #addon.notifications > max do
            table.remove(addon.notifications)
        end
    end

    -- Save to persistent history
    if addon.History_AppendEntries then
        addon.History_AppendEntries({
            {
                module = notification.module,
                title = notification.title,
                message = notification.message,
                icon = notification.icon,
                priority = notification.priority,
                realTime = realTime,
            },
        })
    end

    -- Notify UI
    addon.Events:Trigger("NOTIFICATION_ADDED", notification)

    -- A toast needs both the global switch and the source's own, and
    -- so does a sound. A source may also pick its own sound, or none.
    local moduleSettings = addon.db and addon.db.modules[data.module]
    local toastsEnabled = not addon.db or addon.db.toastsEnabled ~= false
    local soundEnabled  = not addon.db or addon.db.soundEnabled ~= false
    local soundChoice   = "default"
    if moduleSettings then
        if moduleSettings.toastsEnabled == false then toastsEnabled = false end
        if moduleSettings.soundEnabled == false then soundEnabled = false end
        if moduleSettings.sound ~= nil then soundChoice = moduleSettings.sound end
    end
    if soundChoice == 0 or soundChoice == "none" then soundEnabled = false end

    -- Do Not Disturb suppresses toasts and sounds (notifications still logged)
    local dnd = addon.IsDND and addon.IsDND()

    if not notification.silent and toastsEnabled and not dnd then
        addon.Events:Trigger("TOAST_REQUESTED", notification)
    end

    -- The source's own sound, else one by priority, with a cooldown.
    if not notification.silent and soundEnabled and not dnd then
        local soundNow = GetTime()
        if not addon.lastSoundTime or (soundNow - addon.lastSoundTime) > 1.0 then
            addon.lastSoundTime = soundNow
            local soundID
            if type(soundChoice) == "number" then
                soundID = soundChoice
            elseif notification.priority == "high" then
                soundID = addon.db and addon.db.soundHigh or 8959
            elseif notification.priority == "low" then
                soundID = addon.db and addon.db.soundLow or 0
            else
                soundID = addon.db and addon.db.soundNormal or 3175
            end
            if soundID and soundID > 0 then
                PlaySound(soundID, "SFX")
            end
        end
    end

    return notification
end

function BNC:DismissNotification(id)
    for i, notif in ipairs(addon.notifications) do
        if notif.id == id then
            -- Drop from dedupe cache so a follow-up duplicate spawns a
            -- fresh notification rather than updating the dismissed one
            -- (which has been removed from the array).
            dedupeCache[DedupeKey(notif.module, notif.title)] = nil
            table.remove(addon.notifications, i)
            addon.Events:Trigger("NOTIFICATION_DISMISSED", id)
            return true
        end
    end
    return false
end

function BNC:DismissAll(moduleId)
    if moduleId then
        for i = #addon.notifications, 1, -1 do
            if addon.notifications[i].module == moduleId then
                local n = addon.notifications[i]
                dedupeCache[DedupeKey(n.module, n.title)] = nil
                table.remove(addon.notifications, i)
            end
        end
    else
        wipe(addon.notifications)
        wipe(dedupeCache)
    end
    addon.Events:Trigger("NOTIFICATIONS_CLEARED", moduleId)
end

function BNC:GetNotifications(moduleFilter)
    if not moduleFilter then
        return addon.notifications
    end

    local filtered = {}
    for _, notif in ipairs(addon.notifications) do
        if notif.module == moduleFilter then
            table.insert(filtered, notif)
        end
    end
    return filtered
end

function BNC:GetUnreadCount()
    return #addon.notifications
end

function BNC:GetNotificationsByModule()
    local grouped = {}
    local order = {}
    for _, notif in ipairs(addon.notifications) do
        if not grouped[notif.module] then
            grouped[notif.module] = {}
            table.insert(order, notif.module)
        end
        table.insert(grouped[notif.module], notif)
    end
    return grouped, order
end

function BNC:ClearHistory()
    addon.History_PurgeAll()
    addon.Events:Trigger("HISTORY_CLEARED")
end
