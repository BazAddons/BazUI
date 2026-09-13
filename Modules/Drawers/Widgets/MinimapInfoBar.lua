-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Drawers Widget: Minimap Info Bar
--
-- Horizontal bar that combines the Blizzard clock button, the
-- calendar/game-time button, the minimap tracking button, and a
-- mail indicator on the left that only appears when you have
-- unread mail. More left-side info buttons (bag count, gold,
-- fps/ms, etc.) can be added over time.

local addon = BazUI:GetModule("Drawers")
if not addon then return end

local WIDGET_ID     = "bazdrawer_minimap_infobar"
local DESIGN_WIDTH  = 220
local DESIGN_HEIGHT = 28
local PAD           = 6

local InfoBarWidget = {}
addon.InfoBarWidget = InfoBarWidget

local wrapper
local widgetInfo
local isAttached = false

---------------------------------------------------------------------------
-- Attach the three native frames into the wrapper in the layout:
--   [ ...empty left side...     Clock  Calendar  Tracking ]
-- Left side is intentionally empty so additional info buttons (bag
-- count, mail, gold, fps/ms, etc.) can be added later without
-- disturbing the existing right cluster.
---------------------------------------------------------------------------

local function AttachFrames()
    if isAttached or not wrapper then return end

    local iconSize = DESIGN_HEIGHT - 4

    -- Tracking button on the far right
    local trackingBtn
    -- Retail keeps tracking in MinimapCluster.Tracking; Classic flavours
    -- have the standalone MiniMapTracking frame.
    local trackingSrc = (MinimapCluster and MinimapCluster.Tracking) or MiniMapTracking
    if trackingSrc then
        trackingBtn = trackingSrc
        trackingBtn:SetParent(wrapper)
        trackingBtn:ClearAllPoints()
        trackingBtn:SetPoint("RIGHT", wrapper, "RIGHT", -PAD, 0)
        trackingBtn:SetSize(iconSize, iconSize)
        trackingBtn:Show()
    end

    -- Calendar proxy button. We do NOT reparent GameTimeFrame - it's a
    -- secure/protected button and reparenting it taints Blizzard code
    -- paths (notably Edit Mode and any scroll list that inspects frame
    -- attributes downstream). Instead we build a plain Button that
    -- mimics its behaviour: day-of-month label + click to open calendar
    -- + red glow when invites are pending.
    local calendarBtn = CreateFrame("Button", nil, wrapper)
    calendarBtn:SetSize(iconSize, iconSize)
    -- Tight gap between calendar and tracking - they're visually paired
    -- via the shared `ui-hud-minimap-button` background, so they read
    -- better snug together rather than with the full PAD between them.
    local CAL_TRACK_GAP = 1
    if trackingBtn then
        calendarBtn:SetPoint("RIGHT", trackingBtn, "LEFT", -CAL_TRACK_GAP, 0)
    else
        calendarBtn:SetPoint("RIGHT", wrapper, "RIGHT", -PAD, 0)
    end

    -- Background frame - same rounded bevel atlas used behind the
    -- minimap tracking button, so both icons share the same chrome.
    calendarBtn.bg = calendarBtn:CreateTexture(nil, "BACKGROUND")
    calendarBtn.bg:SetAllPoints()
    BazUI.SetAtlasOrTexture(calendarBtn.bg, "ui-hud-minimap-button", "Interface\\Minimap\\UI-Minimap-Background", false)

    -- Day-of-month label centered on the button. Color #A29580 - warm
    -- desaturated tan that matches the minimap-button bevel chrome.
    calendarBtn.text = calendarBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    calendarBtn.text:SetPoint("CENTER", 0, 0)
    calendarBtn.text:SetTextColor(0xA2 / 255, 0x95 / 255, 0x80 / 255)

    -- Pending-invite overlay - only shown when C_Calendar reports invites
    calendarBtn.pending = calendarBtn:CreateTexture(nil, "OVERLAY")
    calendarBtn.pending:SetAllPoints()
    BazUI.SetAtlasOrTexture(calendarBtn.pending, "Calendar-PendingInvite", nil, false)
    calendarBtn.pending:Hide()

    local function RefreshCalendar()
        local day
        if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
            local t = C_DateAndTime.GetCurrentCalendarTime()
            if t and t.monthDay then day = t.monthDay end
        end
        calendarBtn.text:SetText(day or "?")

        local pending = 0
        if C_Calendar and C_Calendar.GetNumPendingInvites then
            pending = C_Calendar.GetNumPendingInvites() or 0
        end
        calendarBtn.pending:SetShown(pending > 0)
    end

    calendarBtn:SetScript("OnClick", function()
        if ToggleCalendar then ToggleCalendar() end
    end)
    calendarBtn:SetScript("OnEnter", function(self)
        -- Hover color #BA9B51 - a slightly brighter warm gold than the
        -- at-rest #A29580 tan so the button reads as interactive.
        if self.text then
            self.text:SetTextColor(0xBA / 255, 0x9B / 255, 0x51 / 255)
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Calendar")
        GameTooltip:AddLine("Click to open the calendar", 1, 1, 1, true)
        local pending = (C_Calendar and C_Calendar.GetNumPendingInvites and C_Calendar.GetNumPendingInvites()) or 0
        if pending > 0 then
            GameTooltip:AddLine(pending .. " pending invite" .. (pending > 1 and "s" or ""), 1, 0.4, 0.4)
        end
        GameTooltip:Show()
    end)
    calendarBtn:SetScript("OnLeave", function(self)
        -- Restore the at-rest tan color
        if self.text then
            self.text:SetTextColor(0xA2 / 255, 0x95 / 255, 0x80 / 255)
        end
        GameTooltip:Hide()
    end)

    -- Event-driven refresh + periodic fallback (every 60s) for the day rollover
    local ev = CreateFrame("Frame", nil, calendarBtn)
    ev:RegisterEvent("CALENDAR_UPDATE_PENDING_INVITES")
    ev:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", RefreshCalendar)
    C_Timer.NewTicker(60, RefreshCalendar)
    RefreshCalendar()

    -- Small pocket-watch icon flush to the left edge of the bar; the
    -- clock text anchors to its right. Visually pairs the icon + time
    -- so the user reads them as one element rather than a floating
    -- number.
    local clockIconSize = DESIGN_HEIGHT - 8
    local clockIcon = wrapper:CreateTexture(nil, "ARTWORK")
    clockIcon:SetSize(clockIconSize, clockIconSize)
    clockIcon:SetPoint("LEFT", wrapper, "LEFT", PAD, 0)
    clockIcon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    -- Round the icon with a circle mask so it doesn't show the square
    -- icon border next to the other minimap-button-style icons.
    local mask = wrapper:CreateMaskTexture()
    mask:SetAllPoints(clockIcon)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
                    "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    clockIcon:AddMaskTexture(mask)

    -- Clock button. TimeManagerClockButton is load-on-demand; force-load
    -- its owning addon if it hasn't loaded yet and retry.
    local function AttachClock()
        local clock = TimeManagerClockButton
        if not clock then
            C_AddOns.LoadAddOn("Blizzard_TimeManager")
            clock = TimeManagerClockButton
        end
        if not clock then
            C_Timer.After(1, AttachClock)
            return
        end
        clock:SetParent(wrapper)
        clock:ClearAllPoints()
        -- Upscale the clock so it reads at the same visual weight as
        -- the tracking and calendar icons next to it. The clock is a
        -- compound frame (text + bevel), so SetScale is safer than
        -- SetSize here.
        clock:SetScale(1.25)
        -- The clock's internal text baseline sits a touch above the
        -- anchor y=0 midline, so it looked raised compared to the
        -- zone text. Small negative y nudge drops its baseline back
        -- in line with the zone text visually.
        local CLOCK_Y_OFFSET = -1
        -- Anchor clock to the right of the pocket-watch icon. Negative
        -- x offset compensates for the clock button's own internal left
        -- padding (it's a compound frame with centered text inside a
        -- wider box; at 1.25 scale the padding is chunky). Dialed so
        -- the visible "H:MM" sits snug against the icon.
        local CLOCK_X_OFFSET = -2
        clock:SetPoint("LEFT", clockIcon, "RIGHT", CLOCK_X_OFFSET, CLOCK_Y_OFFSET)
        clock:Show()
    end
    AttachClock()

    -- Mail indicator on the RIGHT side of the bar, snug against the
    -- calendar button. Always visible: subdued (dim icon) when there's
    -- no new mail, brightened and pulsing when new mail arrives.
    local mailBtn = CreateFrame("Button", nil, wrapper)
    mailBtn:SetSize(iconSize, iconSize)
    if calendarBtn then
        mailBtn:SetPoint("RIGHT", calendarBtn, "LEFT", -1, 0)
    elseif trackingBtn then
        mailBtn:SetPoint("RIGHT", trackingBtn, "LEFT", -1, 0)
    else
        mailBtn:SetPoint("RIGHT", wrapper, "RIGHT", -PAD, 0)
    end

    -- Same shared button chrome as calendar/tracking
    mailBtn.bg = mailBtn:CreateTexture(nil, "BACKGROUND")
    mailBtn.bg:SetAllPoints()
    BazUI.SetAtlasOrTexture(mailBtn.bg, "ui-hud-minimap-button", "Interface\\Minimap\\UI-Minimap-Background", false)

    -- Native mail icon - tracking atlas gives us a clean mailbox glyph
    mailBtn.icon = mailBtn:CreateTexture(nil, "ARTWORK")
    mailBtn.icon:SetPoint("CENTER", 0, 0)
    mailBtn.icon:SetSize(math.floor(iconSize * 0.70), math.floor(iconSize * 0.70))
    mailBtn.icon:SetTexture("Interface\\Minimap\\Tracking\\Mailbox")

    -- Subtle pulse when new mail comes in - AnimationGroup looping a
    -- short alpha in/out on a tint texture overlay.
    mailBtn.pulse = mailBtn:CreateTexture(nil, "OVERLAY")
    mailBtn.pulse:SetAllPoints()
    BazUI.SetAtlasOrTexture(mailBtn.pulse, "ui-hud-minimap-button", "Interface\\Minimap\\UI-Minimap-Background", false)
    mailBtn.pulse:SetVertexColor(1.0, 0.85, 0.3, 0)
    mailBtn.pulse:SetBlendMode("ADD")
    mailBtn.pulseAnim = mailBtn:CreateAnimationGroup()
    mailBtn.pulseAnim:SetLooping("BOUNCE")
    local pulseIn = mailBtn.pulseAnim:CreateAnimation("Alpha")
    pulseIn:SetTarget(mailBtn.pulse)
    pulseIn:SetFromAlpha(0)
    pulseIn:SetToAlpha(0.6)
    pulseIn:SetDuration(0.6)
    pulseIn:SetSmoothing("IN_OUT")

    mailBtn:SetScript("OnClick", function()
        -- Best-effort - no-op if not near a mailbox
        if ToggleMailFrame then ToggleMailFrame() end
    end)
    mailBtn:SetScript("OnEnter", function(self)
        local has = HasNewMail and HasNewMail() or false
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if has then
            GameTooltip:SetText(HAVE_MAIL or "You have unread mail")
            if GetLatestThreeSenders then
                local s1, s2, s3 = GetLatestThreeSenders()
                local senders = {}
                if s1 then senders[#senders + 1] = s1 end
                if s2 then senders[#senders + 1] = s2 end
                if s3 then senders[#senders + 1] = s3 end
                if #senders > 0 then
                    GameTooltip:AddLine("From: " .. table.concat(senders, ", "), 1, 1, 1, true)
                end
            end
        else
            GameTooltip:SetText("Mailbox")
            GameTooltip:AddLine("No new mail.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    mailBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function RefreshMail()
        local has = HasNewMail and HasNewMail() or false
        if has then
            -- Bright icon + gentle pulse
            mailBtn.icon:SetAlpha(1.0)
            mailBtn.icon:SetVertexColor(1, 1, 1)
            mailBtn.bg:SetAlpha(1.0)
            if not mailBtn.pulseAnim:IsPlaying() then
                mailBtn.pulseAnim:Play()
            end
        else
            -- Subdued: dim icon + no pulse + slightly darkened chrome
            mailBtn.icon:SetAlpha(0.35)
            mailBtn.icon:SetVertexColor(0.7, 0.7, 0.7)
            mailBtn.bg:SetAlpha(0.55)
            if mailBtn.pulseAnim:IsPlaying() then
                mailBtn.pulseAnim:Stop()
                mailBtn.pulse:SetAlpha(0)
            end
        end
    end

    local mailEvents = CreateFrame("Frame", nil, mailBtn)
    mailEvents:RegisterEvent("UPDATE_PENDING_MAIL")
    mailEvents:RegisterEvent("MAIL_INBOX_UPDATE")
    mailEvents:RegisterEvent("MAIL_SHOW")
    mailEvents:RegisterEvent("MAIL_CLOSED")
    mailEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
    mailEvents:SetScript("OnEvent", RefreshMail)
    RefreshMail()

    isAttached = true
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function InfoBarWidget:Init()
    if wrapper then return end

    wrapper = CreateFrame("Frame", "BazUIDrawerMinimapInfoBarWrapper", UIParent)
    wrapper:SetSize(DESIGN_WIDTH, DESIGN_HEIGHT)

    widgetInfo = {
        id           = WIDGET_ID,
        label        = "Info Bar",
        designWidth  = DESIGN_WIDTH,
        designHeight = DESIGN_HEIGHT,
        frame        = wrapper,
        OnDock       = function() AttachFrames() end,
        GetStatusText = function()
            local h, m = GetGameTime()
            return string.format("%d:%02d", h, m), 0.8, 0.8, 0.8
        end,
    }

    BazUI:RegisterDockableWidget(widgetInfo)

    -- Attach frames immediately so they're ready before the first reflow
    AttachFrames()
end

BazUI:QueueForLogin(function()
    C_Timer.After(0.2, function() InfoBarWidget:Init() end)
end)
