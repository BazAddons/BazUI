-- SPDX-License-Identifier: GPL-2.0-or-later
-- QuestTracker: Block Creation, Population & Pool
-- Creates quest/scenario/achievement block frames, renders data into
-- them via PopulateBlock, and manages the block acquisition/release pool.

local addon = BazUI:GetModule("Drawers")
if not addon then return end
local QT = addon.QT
local C  = QT.C

---------------------------------------------------------------------------
-- Block creation - builds one reusable block frame with all subcomponents
---------------------------------------------------------------------------

function QT.CreateBlock()
    local block = CreateFrame("Frame", nil, QT.scrollChild or QT.frame)
    block:SetWidth(C.DESIGN_WIDTH - C.PAD * 2)

    -- Decorative scenario-stage background texture (the purple block).
    -- For the final stage Blizzard layers a second decorative filigree
    -- texture on top of the regular stageBg - a glowing gem with
    -- ornamental flourishes. We mirror that with stageFinalBg, hidden
    -- by default and shown only when currentStage == numStages.
    block.stageBg = block:CreateTexture(nil, "BORDER")
    block.stageBg:Hide()

    block.stageFinalBg = block:CreateTexture(nil, "BORDER", nil, 1)
    block.stageFinalBg:Hide()

    -- UIWidget container for scenario-specific widgets (Delve tier, deaths, affixes)
    local widgetOk, widgetContainer = pcall(CreateFrame, "Frame", nil, block, "UIWidgetContainerTemplate")
    if widgetOk and widgetContainer then
        widgetContainer:Hide()
        local sizeChangePending = false
        widgetContainer:SetScript("OnSizeChanged", function()
            if sizeChangePending then return end
            sizeChangePending = true
            C_Timer.After(0.1, function()
                sizeChangePending = false
                if QT.ApplyLayout then QT.ApplyLayout() end
            end)
        end)
        block.widgetContainer = widgetContainer
    end

    -- Title button
    local title = CreateFrame("Button", nil, block)
    title:SetPoint("TOPLEFT", block, "TOPLEFT", C.POI_SIZE + C.POI_GAP, 0)
    title:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0)
    title:SetHeight(C.TITLE_HEIGHT)
    title:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    block.title = title

    -- POI super-track button
    local poi
    local ok = pcall(function()
        poi = CreateFrame("Button", nil, block, "POIButtonTemplate")
    end)
    if ok and poi then
        poi:SetPoint("RIGHT", title, "LEFT", -C.POI_GAP, 0)
        poi:SetSize(C.POI_SIZE, C.POI_SIZE)
        block.poi = poi
    end

    -- Title text. We disable wrap here and rely on FitStringToWidth
    -- (called per-render in PopulateBlock) to scale long titles down
    -- so they fit one line - wrapping looked cramped at the drawer's
    -- 260 px column width.
    title.text = title:CreateFontString(nil, "OVERLAY")
    -- Blizzard's tracker font in our face, falling back when this
    -- client has no tracker font of its own.
    title.text:SetFontObject(BazUI.Skin.Theme.FontObject(C.TITLE_FONT)
        or BazUI.Skin.Theme.FontObject("GameFontNormal"))
    title.text:SetPoint("LEFT", title, "LEFT", 0, 0)
    title.text:SetPoint("RIGHT", title, "RIGHT", 0, 0)
    title.text:SetJustifyH("LEFT")
    title.text:SetJustifyV("MIDDLE")
    title.text:SetWordWrap(false)

    -- Optional "Stage X" label that sits inside the purple scenario
    -- stage box, above title.text. Hidden for non-scenario blocks.
    -- Mirrors Blizzard's Blizzard_ScenarioObjectiveTracker.xml - Stage
    -- uses the Game18Font family (FRIZQT at 18pt) in cream
    -- (1, 0.914, 0.682) with a 1px shadow. We call SetFont explicitly
    -- rather than SetFontObject so we don't rely on Game18Font being
    -- exposed as a Lua global; FontFamily definitions sometimes are
    -- and sometimes aren't, depending on the load environment.
    title.stageLabel = title:CreateFontString(nil, "OVERLAY")
    title.stageLabel:SetFont(BazUI.Skin.Theme.FontFile(), 18, "")
    title.stageLabel:SetJustifyH("LEFT")
    title.stageLabel:SetTextColor(1.0, 0.914, 0.682)
    title.stageLabel:SetShadowColor(0, 0, 0, 1)
    title.stageLabel:SetShadowOffset(1, -1)
    title.stageLabel:SetWordWrap(false)
    title.stageLabel:Hide()

    -- Title click handler
    title:SetScript("OnClick", function(self, button)
        local kind = block._kind or "quest"
        if kind == "scenario" then return end
        if not block._questID then return end

        -- Combat guard. Every action this handler performs ends up
        -- triggering Blizzard's QuestDataProvider:RefreshAllData
        -- (via Supertracking.OnChanged for SetSuperTrackedQuestID,
        -- via QUEST_WATCH_LIST_CHANGED for RemoveQuestWatch, via the
        -- map open path for ShowQuestDetails). Refresh ends up calling
        -- SetPassThroughButtons on quest pins, which is taint-blocked
        -- during combat once BazMap (or any other map addon) has
        -- touched WorldMapFrame's attribute table. The block fails
        -- with ADDON_ACTION_BLOCKED and the click does nothing useful
        -- - so we just bail in combat. A right-click in combat to
        -- abandon a watch is an unusual case; the user can re-click
        -- after combat.
        if InCombatLockdown() then return end

        if kind == "achievement" then
            if button == "LeftButton" then
                if not _G.AchievementFrame then
                    C_AddOns.LoadAddOn("Blizzard_AchievementUI")
                end
                if AchievementFrame_ToggleAchievementFrame then
                    if not AchievementFrame or not AchievementFrame:IsShown() then
                        AchievementFrame_ToggleAchievementFrame()
                    end
                end
                if AchievementFrame_SelectAchievement then
                    pcall(AchievementFrame_SelectAchievement, block._questID)
                end
            elseif button == "RightButton" then
                if C_ContentTracking and C_ContentTracking.StopTracking
                   and Enum and Enum.ContentTrackingType
                   and Enum.ContentTrackingStopType then
                    pcall(C_ContentTracking.StopTracking,
                          Enum.ContentTrackingType.Achievement,
                          block._questID,
                          Enum.ContentTrackingStopType.Manual)
                end
            end
            return
        end

        if kind == "recipe" then
            if button == "LeftButton" then
                if not _G.ProfessionsFrame and _G.ProfessionsFrame_LoadUI then
                    _G.ProfessionsFrame_LoadUI()
                end
                if _G.C_TradeSkillUI and _G.C_TradeSkillUI.OpenRecipe then
                    pcall(_G.C_TradeSkillUI.OpenRecipe, block._questID)
                end
            elseif button == "RightButton" then
                if _G.C_TradeSkillUI and _G.C_TradeSkillUI.SetRecipeTracked then
                    pcall(_G.C_TradeSkillUI.SetRecipeTracked,
                          block._questID, false, block._isRecraft and true or false)
                end
            end
            return
        end

        -- Quest
        if button == "LeftButton" then
            -- Auto-complete quests: open the turn-in dialog directly
            if block._isAutoComplete and block._isComplete and ShowQuestComplete then
                ShowQuestComplete(block._questID)
                return
            end
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                C_SuperTrack.SetSuperTrackedQuestID(block._questID)
            end
            -- Toggle behavior: clicking the quest that's currently
            -- showing in the detail panel closes the whole map. Any
            -- other click routes through Blizzard's standard tracker-
            -- click entry point so the side panel and detail view
            -- come up exactly the way they do from Blizzard's own
            -- objective tracker.
            local mapOpen = WorldMapFrame and WorldMapFrame:IsShown()
            local details = QuestMapFrame and QuestMapFrame.DetailsFrame
            local showingThisQuest = mapOpen
                and details and details:IsShown()
                and details.questID == block._questID

            if showingThisQuest then
                WorldMapFrame:Hide()
            else
                -- Use Blizzard's proper click-tracked-quest entry point.
                -- This is exactly what Blizzard's own objective tracker
                -- calls on a quest-title click, so anything they do
                -- (open the side panel, set the detail mode, focus the
                -- supertracked quest, etc.) Just Works. Earlier versions
                -- of this widget tried to avoid ShowUIPanel by calling
                -- WorldMapFrame:Show + QuestMapFrame_ShowQuestDetails
                -- directly, but that bypasses the side-panel show flow
                -- entirely (you got the map but not the quest log) -
                -- and once BazMap stopped routing through UIPanelLayout
                -- properly, ShowUIPanel on a detached frame is safe.
                if QuestMapFrame_OpenToQuestDetails then
                    QuestMapFrame_OpenToQuestDetails(block._questID)
                elseif QuestLogFrame then
                    -- Classic flavours: the standalone quest log, keyed
                    -- by quest log index.
                    local idx = block._questLogIndex
                        or (GetQuestLogIndexByID and GetQuestLogIndexByID(block._questID))
                    if not QuestLogFrame:IsShown() and ToggleQuestLog then
                        ToggleQuestLog()
                    end
                    if idx and idx > 0 then
                        if QuestLog_SetSelection then
                            QuestLog_SetSelection(idx)
                        elseif SelectQuestLogEntry then
                            SelectQuestLogEntry(idx)
                        end
                    end
                end
            end
        elseif button == "RightButton" then
            if C_QuestLog.RemoveQuestWatch then
                C_QuestLog.RemoveQuestWatch(block._questID)
            elseif RemoveQuestWatch then
                -- Classic flavours: the watch list is keyed by log index.
                local idx = block._questLogIndex
                    or (GetQuestLogIndexByID and GetQuestLogIndexByID(block._questID))
                if idx and idx > 0 then
                    RemoveQuestWatch(idx)
                    if QT.QueueRefresh then QT.QueueRefresh() end
                end
            end
        end
    end)

    title:SetScript("OnEnter", function(self)
        if title.text then title.text:SetTextColor(QT.GetTitleHiColor()) end
    end)
    title:SetScript("OnLeave", function()
        if title.text then title.text:SetTextColor(QT.GetTitleColor()) end
    end)

    -- Quest item button. The template defaults to a 26x26 button with
    -- chrome (border + highlight textures) sized for that footprint.
    -- SetSize alone would shrink the icon texture but leave the chrome
    -- at 26 - so the visible button "frame" appears bigger than the
    -- icon. Scaling the whole button proportionally shrinks chrome +
    -- icon together; we use a scale that lands the button at our
    -- target SPECIAL_ITEM_SIZE (matching the title row's height).
    local itemOk, itemBtn = pcall(CreateFrame, "Button", nil, block, "QuestObjectiveItemButtonTemplate")
    if itemOk and itemBtn then
        itemBtn:SetSize(C.SPECIAL_ITEM_TEMPLATE_SIZE, C.SPECIAL_ITEM_TEMPLATE_SIZE)
        itemBtn:SetScale(C.SPECIAL_ITEM_SIZE / C.SPECIAL_ITEM_TEMPLATE_SIZE)
        itemBtn:SetPoint("TOPRIGHT", block, "TOPRIGHT", -C.SPECIAL_ITEM_RIGHT_PAD, 0)
        itemBtn:Hide()
        -- The block's title Button spans the full width including
        -- under the item icon, intercepting clicks before they reach
        -- the item. Bump our frame level above the title so hover and
        -- click on the icon land on the item button (same fix the
        -- find-group eye uses below).
        itemBtn:SetFrameLevel((block:GetFrameLevel() or 0) + 10)
        block.itemButton = itemBtn
    end

    -- Find Group ("green eye") button - same Blizzard template the
    -- BonusObjectiveTracker uses. Mixin handles the OnClick > opens
    -- the Premade Group Finder filtered for that WQ.
    local fgOk, findGroupBtn = pcall(CreateFrame, "Button", nil, block, "QuestObjectiveFindGroupButtonTemplate")
    if fgOk and findGroupBtn then
        findGroupBtn:SetPoint("TOPRIGHT", block, "TOPRIGHT", 5, 2)
        findGroupBtn:Hide()
        -- The block's title Button spans the full width including under
        -- the eye, intercepting clicks. Bump our frame level above it
        -- so we get hover/click on the entire eye, not just the bottom.
        findGroupBtn:SetFrameLevel((block:GetFrameLevel() or 0) + 10)
        -- Use the template's default UI-Common-MouseHilight for hover -
        -- matches Blizzard's native look.
        block.findGroupBtn = findGroupBtn
    end

    -- Progress bar - matches Blizzard's bonus-objective bar.
    -- Atlases (bonusobjectives-bar-frame-5 + bonusobjectives-bar-ring)
    -- have segment positions baked in. We scale them down ~80% to fit
    -- our narrower widget while keeping the segments crisp.
    local SCALE = 0.95
    local barW = math.floor(191 * SCALE)        -- ~181
    local barH = math.floor(17 * SCALE)         -- ~16
    local frameW = math.floor(207 * SCALE)      -- atlas native ~207
    local frameH = math.floor(38 * SCALE)       -- atlas native ~38

    local bar = CreateFrame("StatusBar", nil, block)
    bar:SetSize(barW, barH)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.26, 0.42, 1.00, 1)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.04, 0.07, 0.18, 1)

    -- Force the status fill texture down to a low layer so our frame
    -- overlay can sit cleanly on top of it.
    local statusTex = bar:GetStatusBarTexture()
    if statusTex and statusTex.SetDrawLayer then
        statusTex:SetDrawLayer("ARTWORK", -8)
    end

    -- Decorative segmented frame, scaled to fit the bar. useAtlasSize=false
    -- + explicit Size lets us downscale while keeping the baked segments.
    bar.frame = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    pcall(bar.frame.SetAtlas, bar.frame, "bonusobjectives-bar-frame-5", false)
    bar.frame:SetSize(frameW, frameH)
    bar.frame:SetPoint("LEFT", -math.floor(8 * SCALE), -1)

    -- Crystal ring endcap on the right. useAtlasSize=true preserves the
    -- atlas's native aspect ratio so the ring stays round; we use
    -- SetScale to size it down to match the scaled bar frame.
    bar.endcap = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    pcall(bar.endcap.SetAtlas, bar.endcap, "bonusobjectives-bar-ring", true)
    bar.endcap:SetScale(SCALE)
    bar.endcap:SetPoint("RIGHT", bar.frame, "RIGHT", 0, 0)

    -- Reward icon inside the ring. Anchored directly to the bar's
    -- RIGHT edge (not the scaled endcap, which seems to have wonky
    -- anchor math when SetScale is applied). The ring sits at the
    -- bar's right edge anyway, so this lands the icon dead-center.
    local iconSize = math.floor(28 * SCALE)
    bar.icon = bar:CreateTexture(nil, "OVERLAY", nil, 6)
    bar.icon:SetSize(iconSize, iconSize)
    -- The atlas has internal padding that puts its visible ring further
    -- LEFT than the anchor's RIGHT edge. Empirical offset to land the
    -- icon inside the visible ring.
    bar.icon:SetPoint("CENTER", bar.frame, "RIGHT", -24, 2)
    bar.iconMask = bar:CreateMaskTexture(nil, "OVERLAY")
    bar.iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
                            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    bar.iconMask:SetAllPoints(bar.icon)
    bar.icon:AddMaskTexture(bar.iconMask)
    bar.icon:Hide()

    bar.text = bar:CreateFontString(nil, "OVERLAY")
    bar.text:SetFontObject(BazUI.Skin.Theme.FontObject("GameFontHighlightSmall"))
    -- Center on the actual fill area, not the whole bar+endcap. The
    -- ring on the right pulls the visual center off; offset left to
    -- compensate.
    bar.text:SetPoint("CENTER", -14, -1)
    bar.text:SetTextColor(1, 1, 1)
    bar:Hide()
    block.progressBar = bar


    block.objectives = {}
    return block
end

---------------------------------------------------------------------------
-- Pool management
---------------------------------------------------------------------------

function QT.AcquireBlock()
    local block = table.remove(QT.blockPool)
    if not block then block = QT.CreateBlock() end
    block:Show()
    return block
end

function QT.ReleaseBlock(block)
    block:Hide()
    block:ClearAllPoints()
    block._questID = nil
    block._title = nil
    block._titleColor = nil
    block._kind = nil
    block._isAutoComplete = nil
    block._isComplete = nil
    for _, line in ipairs(block.objectives) do
        if line and line.Hide then line:Hide() end
    end
    if block.progressBar then block.progressBar:Hide() end
    if block.itemButton then block.itemButton:Hide() end
    if block.findGroupBtn then block.findGroupBtn:Hide() end
    if block.widgetContainer then
        block.widgetContainer:RegisterForWidgetSet(nil)
        block._registeredWidgetSetID = nil
        block.widgetContainer:Hide()
    end
    if block._bottomWidgetOrigParent then
        local blizzBottom = _G.ScenarioObjectiveTracker
            and _G.ScenarioObjectiveTracker.BottomWidgetContainerBlock
            and _G.ScenarioObjectiveTracker.BottomWidgetContainerBlock.WidgetContainer
        if blizzBottom then
            blizzBottom:SetParent(block._bottomWidgetOrigParent)
            blizzBottom:ClearAllPoints()
        end
        block._bottomWidgetOrigParent = nil
    end
    table.insert(QT.blockPool, block)
end

---------------------------------------------------------------------------
-- PopulateBlock - render quest/scenario/achievement data into a block
---------------------------------------------------------------------------

function QT.PopulateBlock(block, quest)
    block._questID = quest.id
    block._title = quest.title
    block._kind = quest.kind or "quest"
    block._isAutoComplete = quest.isAutoComplete
    block._isComplete = quest.isComplete
    block._isRecraft = quest.isRecraft
    block._questLogIndex = quest.questLogIndex  -- Classic APIs key on this

    local isAchievement = (block._kind == "achievement")
    local isScenario    = (block._kind == "scenario")
    local isRecipe      = (block._kind == "recipe")
    local hideIcon      = isAchievement or isScenario or isRecipe

    -- Scenario stage block rendering
    local useWidgetSet = isScenario and quest.widgetSetID and block.widgetContainer
    if isScenario then
        if useWidgetSet then
            block.stageBg:Hide()
            block.stageFinalBg:Hide()
            block.widgetContainer:ClearAllPoints()
            block.widgetContainer:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
            block.widgetContainer:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0)
            block.widgetContainer:Show()
            if block._registeredWidgetSetID ~= quest.widgetSetID then
                block.widgetContainer:RegisterForWidgetSet(quest.widgetSetID)
                block._registeredWidgetSetID = quest.widgetSetID
            end
        else
            if block.widgetContainer then
                if block._registeredWidgetSetID then
                    block.widgetContainer:RegisterForWidgetSet(nil)
                    block._registeredWidgetSetID = nil
                end
                block.widgetContainer:Hide()
            end
            -- Atlas selection mirrors Blizzard's
            -- ScenarioObjectiveTrackerStageMixin:GetBGAtlases - try
            -- the textureKit-specific atlas first, fall back to the
            -- generic evergreen one.
            local textureKit = quest.textureKit or ""
            local atlas = textureKit .. "-trackerheader"
            local finalAtlas = textureKit .. "-trackerheader-final-filigree"
            if not C_Texture or not C_Texture.GetAtlasInfo
               or not C_Texture.GetAtlasInfo(atlas) then
                atlas      = "evergreen-scenario-trackerheader"
                finalAtlas = "evergreen-scenario-trackerheader-final-filigree"
            end
            block.stageBg:SetAtlas(atlas, true)
            block.stageBg:ClearAllPoints()
            block.stageBg:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
            block.stageBg:Show()

            -- Final-stage decorative filigree - only when the player
            -- is on the last stage. Blizzard anchors it at TOPLEFT
            -- (-10, 3) on top of stageBg, so the gem sticks out a
            -- touch to the left/up. The texture's :Show is what
            -- gates visibility; we always keep the atlas set so a
            -- pooled block doesn't briefly flash a stale texture.
            local isFinal = quest.currentStage and quest.numStages
                            and quest.numStages > 0
                            and quest.currentStage >= quest.numStages
            if isFinal and finalAtlas
               and C_Texture and C_Texture.GetAtlasInfo
               and C_Texture.GetAtlasInfo(finalAtlas) then
                block.stageFinalBg:SetAtlas(finalAtlas, true)
                block.stageFinalBg:ClearAllPoints()
                block.stageFinalBg:SetPoint("TOPLEFT", block.stageBg, "TOPLEFT", -10, 3)
                block.stageFinalBg:Show()
            else
                block.stageFinalBg:Hide()
            end
        end
    else
        block.stageBg:Hide()
        block.stageFinalBg:Hide()
        if block.widgetContainer then
            if block._registeredWidgetSetID then
                block.widgetContainer:RegisterForWidgetSet(nil)
                block._registeredWidgetSetID = nil
            end
            block.widgetContainer:Hide()
        end
    end

    -- POI button
    local isWorldQuest = (block._kind == "worldquest")
    if block.poi then
        if hideIcon then
            block.poi:Hide()
        elseif block.poi.SetQuestID then
            block.poi:SetQuestID(quest.id)
            if POIButtonUtil and POIButtonUtil.Style then
                local style
                if isWorldQuest then
                    -- WorldQuest style renders Blizzard's gold WQ marker
                    -- (the "dragon"/diamond icon you see in the default tracker)
                    style = POIButtonUtil.Style.WorldQuest
                elseif quest.isComplete then
                    style = POIButtonUtil.Style.QuestComplete
                else
                    style = POIButtonUtil.Style.QuestInProgress
                end
                if block.poi.SetStyle then block.poi:SetStyle(style) end
            end
            -- WQs should ping the world map when super-tracked
            if isWorldQuest and block.poi.SetPingWorldMap then
                block.poi:SetPingWorldMap(true)
            end
            if block.poi.SetSelected and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
                block.poi:SetSelected(C_SuperTrack.GetSuperTrackedQuestID() == quest.id)
            end
            if block.poi.UpdateButtonStyle then
                block.poi:UpdateButtonStyle()
            end
            block.poi:Show()
        end
    end

    -- Find Group ("green eye") button - same condition Blizzard's own
    -- tracker uses: QuestUtil.CanCreateQuestGroup(questID). That's
    -- the standard check for both world quests and regular quests with
    -- an LFG activity defined (elite group quests, world bosses, etc.).
    -- Restricting to isWorldQuest only would miss the regular quests
    -- that legitimately should show the eye, so we just delegate to
    -- the helper for every quest block.
    if block.findGroupBtn then
        local showFindGroup = false
        if quest.id and QuestUtil and QuestUtil.CanCreateQuestGroup then
            local ok, can = pcall(QuestUtil.CanCreateQuestGroup, quest.id)
            if ok and can then showFindGroup = true end
        end
        if showFindGroup then
            if block.findGroupBtn.SetUp then
                block.findGroupBtn:SetUp(quest.id)
            end
            block.findGroupBtn:Show()
        else
            block.findGroupBtn:Hide()
        end
    end

    -- Title anchoring
    block.title:ClearAllPoints()
    if useWidgetSet then
        block.title:Hide()
    elseif isScenario then
        block.title:SetPoint("TOPLEFT",  block.stageBg, "TOPLEFT",  16, -8)
        block.title:SetPoint("BOTTOMRIGHT", block.stageBg, "BOTTOMRIGHT", -16, 8)
        block.title:Show()
    else
        -- Room for the super-track button, but only where there is one to
        -- make room for.
        --
        -- It is built from a template the client may not have - Classic
        -- has no POIButtonTemplate at all - and the build is wrapped in a
        -- pcall, so on those clients there is simply no button. Reserving
        -- its width regardless pushed every quest title a quarter of the
        -- widget to the right, past an icon that was never going to be
        -- drawn, and left the tracker indented from every other widget in
        -- the drawer.
        local indent = (block.poi and not hideIcon)
            and (C.POI_SIZE + C.POI_GAP) or 0
        block.title:SetPoint("TOPLEFT", block, "TOPLEFT", indent, 0)
        block.title:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0)
        block.title:Show()
    end

    local titleIndent = (block.poi and not hideIcon)
        and (C.POI_SIZE + C.POI_GAP) or 0

    -- Title text
    if not useWidgetSet then
        block.title.text:SetText(quest.title)
        if isScenario then
            -- Scenario stage box: two stacked labels - mirrors
            -- Blizzard_ScenarioObjectiveTracker.xml exactly.
            --   stageLabel  Game18Font, color (1, 0.914, 0.682)
            --                "Stage X" (final stage uses
            --                SCENARIO_STAGE_FINAL - "Final Stage")
            --   text         GameFontNormal, color (1, 0.831, 0.380)
            --                stage name, e.g. "The Great Calamity"
            -- Blizzard never inlines "Stage X of Y" - the stage count
            -- shows up in the hover tooltip headline instead.
            local stageLbl
            if quest.currentStage and quest.numStages
               and quest.numStages > 0
               and quest.currentStage >= quest.numStages then
                stageLbl = _G.SCENARIO_STAGE_FINAL or "Final Stage"
            elseif quest.currentStage then
                local fmt = _G.SCENARIO_STAGE or "Stage %d"
                stageLbl = string.format(fmt, quest.currentStage)
            end

            -- Match Blizzard's stage-name font + color. The default
            -- title font (ObjectiveTrackerHeaderFont) was too big and
            -- colored wrong (we previously inherited the gold of
            -- regular quest titles).
            block.title.text:SetFontObject(
                BazUI.Skin.Theme.FontObject("GameFontNormal") or _G.GameFontNormal)
            block.title.text:SetTextColor(1.0, 0.831, 0.380)

            if stageLbl and stageLbl ~= "" then
                block.title.stageLabel:SetText(stageLbl)
                block.title.stageLabel:ClearAllPoints()
                -- Vertically center the (stageLabel + gap + text)
                -- stack inside block.title (which fills the inner
                -- area of stageBg with a 8 px inset). Anchoring both
                -- to title's LEFT/RIGHT (vertical mid-line) puts the
                -- stack symmetrically around the box's vertical
                -- center - Blizzard uses fixed pixel offsets from
                -- TOPLEFT, but their atlas dimensions don't match
                -- ours exactly, so a centered anchor adapts.
                local gap = 4
                block.title.stageLabel:SetPoint("BOTTOMLEFT",  block.title, "LEFT",  0, gap / 2)
                block.title.stageLabel:SetPoint("BOTTOMRIGHT", block.title, "RIGHT", 0, gap / 2)
                block.title.stageLabel:Show()

                block.title.text:ClearAllPoints()
                block.title.text:SetPoint("TOPLEFT",  block.title, "LEFT",  0, -(gap / 2))
                block.title.text:SetPoint("TOPRIGHT", block.title, "RIGHT", 0, -(gap / 2))
            else
                block.title.stageLabel:Hide()
                block.title.text:ClearAllPoints()
                block.title.text:SetPoint("LEFT",  block.title, "LEFT",  0, 0)
                block.title.text:SetPoint("RIGHT", block.title, "RIGHT", 0, 0)
            end
            block.title.text:SetJustifyH("LEFT")
            block.title.text:SetJustifyV("MIDDLE")
        else
            block.title.stageLabel:Hide()
            block.title.text:ClearAllPoints()
            block.title.text:SetPoint("LEFT",  block.title, "LEFT",  0, 0)
            block.title.text:SetPoint("RIGHT", block.title, "RIGHT", 0, 0)
            block.title.text:SetWidth(C.DESIGN_WIDTH - C.PAD * 2 - titleIndent - C.OBJ_RIGHT_PAD)
            block.title.text:SetTextColor(QT.GetTitleColor())
            -- Shrink long titles to fit one line. The drawer is narrow
            -- enough that names like "The Forgotten Champion of the
            -- Sundered Hall" used to wrap onto two lines; scaling
            -- down keeps them readable without breaking the row.
            QT.FitStringToWidth(
                block.title.text,
                C.DESIGN_WIDTH - C.PAD * 2 - titleIndent - C.OBJ_RIGHT_PAD,
                0.7
            )
        end
    end

    -- Hover tooltip on the scenario stage box. Default tracker shows
    -- the stage *description* (the lore line, e.g. "Assist the
    -- haranir as they battle against unknown attackers.") only on
    -- hover; we used to render it as an extra objective bullet, which
    -- was visually noisy and didn't match Blizzard's behavior.
    --
    -- The tooltip's anchor flips based on which edge the drawer is
    -- docked to: drawer on the right > tooltip pops to the LEFT
    -- (toward screen center), drawer on the left > tooltip pops to
    -- the RIGHT. Anchoring the same direction as the drawer would
    -- push the tooltip off-screen / off the edge of the drawer.
    -- Anchored to block.stageBg rather than block.title so the
    -- tooltip clears the entire purple block, not just the inner
    -- click target.
    if isScenario and not useWidgetSet then
        local desc      = quest.stageDescription
        local stageNum  = quest.currentStage
        local stageMax  = quest.numStages
        local stageName = quest.title
        block.title:SetScript("OnEnter", function()
            if not desc or desc == "" then return end
            local drawerSide = (addon and addon.GetSetting and addon:GetSetting("side")) or "right"
            local anchor = (drawerSide == "right") and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
            GameTooltip:SetOwner(block.stageBg, anchor)
            local headline = stageName or ""
            if stageNum and stageMax and stageMax > 1 then
                headline = string.format("Stage %d of %d: %s", stageNum, stageMax, headline)
            elseif stageNum then
                headline = string.format("Stage %d: %s", stageNum, headline)
            end
            GameTooltip:SetText(headline, 1.0, 0.82, 0.0)
            GameTooltip:AddLine(desc, 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        block.title:SetScript("OnLeave", function() GameTooltip:Hide() end)
    elseif not isScenario then
        -- Restore the title's hover-color script (set in CreateBlock)
        -- in case this block was previously a scenario.
        block.title:SetScript("OnEnter", function(self)
            if block.title.text then block.title.text:SetTextColor(QT.GetTitleHiColor()) end
        end)
        block.title:SetScript("OnLeave", function()
            if block.title.text then block.title.text:SetTextColor(QT.GetTitleColor()) end
        end)
    end

    -- Title height
    local titleH
    if useWidgetSet then
        titleH = block.widgetContainer:GetHeight()
        if not titleH or titleH < 60 then titleH = 60 end
        local wW = block.widgetContainer:GetWidth()
        if wW and wW > 0 then
            block:SetWidth(math.max(C.DESIGN_WIDTH - C.PAD * 2, wW))
        end
    elseif isScenario then
        titleH = block.stageBg:GetHeight() or 40
        if titleH < 40 then titleH = 40 end
        local atlasW = block.stageBg:GetWidth() or 0
        if atlasW > 0 then
            block:SetWidth(math.max(C.DESIGN_WIDTH - C.PAD * 2, atlasW))
        end
    else
        titleH = block.title.text:GetStringHeight() or C.TITLE_HEIGHT
        if titleH < C.TITLE_HEIGHT then titleH = C.TITLE_HEIGHT end
        if block.poi and titleH < C.POI_SIZE then titleH = C.POI_SIZE end
        block.title:SetHeight(titleH)
    end

    -- Objective anchor
    local anchorTo, anchorGap
    if useWidgetSet then
        anchorTo  = block.widgetContainer
        anchorGap = C.SCENARIO_OBJ_GAP
    elseif isScenario then
        anchorTo  = block.stageBg
        anchorGap = C.SCENARIO_OBJ_GAP
    else
        anchorTo  = block.title
        anchorGap = 0
    end

    local leftIndent = C.OBJ_INDENT
    local objWidth   = C.DESIGN_WIDTH - C.PAD * 2 - leftIndent - C.OBJ_RIGHT_PAD
    if isScenario then
        objWidth = objWidth - (C.NUB_SIZE + C.NUB_TEXT_GAP)
    end

    -- Special-item icon (the clickable usable item icon) is anchored
    -- below to the right side of the title. Reserve horizontal space
    -- on the FIRST objective line so the text doesn't run under the
    -- icon. Subsequent objective lines have no icon above them and
    -- stay at full width.
    local hasSpecialItem = quest.kind == "quest"
        and quest.questLogIndex and quest.specialItem and not isScenario
    local SPECIAL_ITEM_RESERVE = C.SPECIAL_ITEM_SIZE
        + C.SPECIAL_ITEM_RIGHT_PAD
        + C.SPECIAL_ITEM_TEXT_GAP

    local lineGap = isScenario and C.SCENARIO_OBJ_LINE_GAP or C.OBJ_LINE_GAP
    local objTotalH = anchorGap

    -- When a regular quest is COMPLETE (ready to turn in), Blizzard's
    -- own tracker (Blizzard_QuestObjectiveTracker.lua:289-318) replaces
    -- the original objectives with a single completion line:
    --   * isAutoComplete -> "Quest Complete" + "Click to Complete"
    --   * has completionText -> the completion text (e.g., "Return to NPC X")
    --   * neither -> "Ready for Turn-In"
    -- The replacement line uses no dash and no check (OBJECTIVE_DASH_STYLE_HIDE).
    -- Without this, our tracker keeps showing stale "Find X" objectives for
    -- quests the player has already finished, which clutters the panel
    -- and disagrees with the default tracker.
    --
    -- World quests, achievements, and scenarios keep their original
    -- objective rendering - only "kind == 'quest'" gets the substitution.
    local objectivesToRender = quest.objectives
    if quest.kind == "quest" and quest.isComplete then
        if quest.isAutoComplete then
            objectivesToRender = {
                { text = _G.QUEST_WATCH_QUEST_COMPLETE   or "Quest Complete",     finished = false, hideDash = true },
                { text = _G.QUEST_WATCH_CLICK_TO_COMPLETE or "Click to Complete", finished = false, hideDash = true },
            }
        elseif quest.completionText and quest.completionText ~= "" then
            objectivesToRender = {
                { text = quest.completionText, finished = false, hideDash = true },
            }
        else
            objectivesToRender = {
                { text = _G.QUEST_WATCH_QUEST_READY or "Ready for Turn-In", finished = false, hideDash = true },
            }
        end
    end

    for i, obj in ipairs(objectivesToRender) do
        local entry = block.objectives[i]
        if not entry or not entry.icon then
            local line = CreateFrame("Frame", nil, block)
            line.icon = line:CreateTexture(nil, "ARTWORK")
            line.icon:SetSize(C.NUB_SIZE, C.NUB_SIZE)

            line.text = line:CreateFontString(nil, "OVERLAY")
            line.text:SetFontObject(BazUI.Skin.Theme.FontObject(C.OBJECTIVE_FONT)
                or BazUI.Skin.Theme.FontObject("GameFontHighlightSmall"))
            line.text:SetJustifyH("LEFT")
            line.text:SetJustifyV("TOP")
            line.text:SetWordWrap(true)

            entry = line
            block.objectives[i] = entry
        end

        local line = entry
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", leftIndent, -(objTotalH + lineGap))

        line.text:ClearAllPoints()
        line.icon:ClearAllPoints()

        local function PositionCheckOrNub(atlas)
            line.icon:SetSize(C.NUB_SIZE, C.NUB_SIZE)
            line.icon:SetAtlas(atlas, false)
            local _, fontH = line.text:GetFont()
            fontH = fontH or 12
            line.icon:SetPoint("LEFT", line, "TOPLEFT", 0, -fontH / 2)
            line.icon:Show()
            line.text:SetPoint("TOPLEFT", line, "TOPLEFT", C.NUB_SIZE + C.NUB_TEXT_GAP, 0)
        end

        -- The special-item icon hovers over the FIRST objective row
        -- only (it's anchored level with the title). Carve out room
        -- on that row's text so the icon doesn't sit on top of it.
        local iconReserve = (hasSpecialItem and i == 1)
            and SPECIAL_ITEM_RESERVE or 0

        if isScenario then
            PositionCheckOrNub(obj.finished
                and "ui-questtracker-tracker-check"
                or  "ui-questtracker-objective-nub")
            line.text:SetWidth(objWidth - iconReserve)
            line.text:SetText(obj.text or "")
        elseif obj.hideDash then
            -- Completion lines (e.g., "Return to NPC X", "Ready for
            -- Turn-In", "Click to Complete") render as plain text with
            -- no dash prefix and no check icon - matches Blizzard's
            -- OBJECTIVE_DASH_STYLE_HIDE flag.
            line.icon:Hide()
            line.text:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
            line.text:SetWidth(objWidth - iconReserve)
            line.text:SetText(obj.text or "")
        elseif obj.finished then
            PositionCheckOrNub("ui-questtracker-tracker-check")
            line.text:SetWidth(objWidth - C.NUB_SIZE - C.NUB_TEXT_GAP - iconReserve)
            line.text:SetText(obj.text or "")
        else
            line.icon:Hide()
            line.text:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
            line.text:SetWidth(objWidth - iconReserve)
            -- Keep the inline "(XX%)" - Blizzard's default tracker
            -- shows it both in the objective text and on the bar.
            line.text:SetText("- " .. (obj.text or ""))
        end

        if obj.finished or obj.hideDash then
            -- Completion lines (hideDash) use the "Complete" color
            -- the same way Blizzard's tracker does.
            line.text:SetTextColor(QT.GetObjectiveDone())
        else
            line.text:SetTextColor(QT.GetObjectiveColor())
        end

        local lineH = line.text:GetStringHeight() or 12
        local hasIcon = isScenario or obj.finished
        if hasIcon and lineH < C.NUB_SIZE then lineH = C.NUB_SIZE end
        line:SetHeight(lineH)
        line:SetWidth(objWidth + (hasIcon and (C.NUB_SIZE + C.NUB_TEXT_GAP) or 0))
        line:Show()

        objTotalH = objTotalH + lineH + lineGap
    end

    -- Hide unused objective lines (use objectivesToRender, not the
    -- raw quest.objectives, since complete quests render a single
    -- substituted line and the rest of the original objectives need
    -- to be hidden).
    for i = #objectivesToRender + 1, #block.objectives do
        local stale = block.objectives[i]
        if stale then
            if stale.Hide then stale:Hide() end
        end
    end

    -- Progress bar - extra padding above and below so the bar doesn't
    -- crowd the objective text or the next element.
    if block.progressBar then
        if quest.progressBarPct and not isScenario then
            local barH = 13
            local barPad = 16  -- breathing room above and below the bar
            block.progressBar:ClearAllPoints()
            block.progressBar:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT",
                C.OBJ_INDENT, -(objTotalH + C.OBJ_LINE_GAP + barPad))
            block.progressBar:SetValue(quest.progressBarPct)
            block.progressBar.text:SetText(math.floor(quest.progressBarPct) .. "%")

            -- Reward icon inside the ring - same priority chain Blizzard
            -- uses in BonusObjectiveTrackerProgressBarMixin:UpdateReward
            local rewardTex
            if quest.id and HaveQuestRewardData and HaveQuestRewardData(quest.id) then
                if GetQuestLogRewardInfo then
                    local _, tex = pcall(function() return select(2, GetQuestLogRewardInfo(1, quest.id)) end)
                    rewardTex = tex
                end
                -- Currency fallback
                if not rewardTex and C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardCurrencies then
                    local ok, currencies = pcall(C_QuestInfoSystem.GetQuestRewardCurrencies, quest.id)
                    if ok and currencies and currencies[1] then
                        rewardTex = currencies[1].texture
                    end
                end
                -- Money fallback
                if not rewardTex and GetQuestLogRewardMoney and GetQuestLogRewardMoney(quest.id) > 0 then
                    rewardTex = "Interface\\Icons\\inv_misc_coin_02"
                end
                -- XP fallback
                if not rewardTex and GetQuestLogRewardXP and GetQuestLogRewardXP(quest.id) > 0
                   and IsPlayerAtEffectiveMaxLevel and not IsPlayerAtEffectiveMaxLevel() then
                    rewardTex = "Interface\\Icons\\xp_icon"
                end
            end
            if block.progressBar.icon then
                if rewardTex then
                    block.progressBar.icon:SetTexture(rewardTex)
                    block.progressBar.icon:Show()
                else
                    block.progressBar.icon:Hide()
                end
            end

            block.progressBar:Show()
            objTotalH = objTotalH + barH + C.OBJ_LINE_GAP + barPad * 2
        else
            block.progressBar:Hide()
        end
    end

    -- Quest special item button
    if block.itemButton then
        if quest.questLogIndex and quest.specialItem and not isScenario then
            -- Size in template (unscaled) coords; SetScale at creation
            -- shrinks the visible button to SPECIAL_ITEM_SIZE.
            block.itemButton:SetSize(C.SPECIAL_ITEM_TEMPLATE_SIZE,
                                     C.SPECIAL_ITEM_TEMPLATE_SIZE)
            if block.itemButton.SetUp then
                block.itemButton:SetUp(quest.questLogIndex)
            else
                SetItemButtonTexture(block.itemButton, quest.specialItem)
            end
            block.itemButton:ClearAllPoints()
            block.itemButton:SetPoint("TOPRIGHT", block.title, "TOPRIGHT",
                -C.SPECIAL_ITEM_RIGHT_PAD, 0)
            block.itemButton:Show()
            block.title.text:SetPoint("RIGHT", block.title, "RIGHT",
                -(C.SPECIAL_ITEM_SIZE + C.SPECIAL_ITEM_RIGHT_PAD
                  + C.SPECIAL_ITEM_TEXT_GAP), 0)
        else
            block.itemButton:Hide()
            -- Reset the title text's right edge: a previous quest in
            -- this reused block may have narrowed it to make room for
            -- the icon. Without this, quests that don't have a special
            -- item end up with their title artificially shortened.
            block.title.text:SetPoint("RIGHT", block.title, "RIGHT", 0, 0)
        end
    end

    -- Bottom scenario widgets (companion level badge)
    local blizzBottom = _G.ScenarioObjectiveTracker
        and _G.ScenarioObjectiveTracker.BottomWidgetContainerBlock
        and _G.ScenarioObjectiveTracker.BottomWidgetContainerBlock.WidgetContainer
    if blizzBottom then
        if isScenario then
            if not block._bottomWidgetOrigParent then
                block._bottomWidgetOrigParent = blizzBottom:GetParent()
            end
            blizzBottom:SetParent(block)
            blizzBottom:ClearAllPoints()
            blizzBottom:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT",
                0, -(objTotalH + C.SCENARIO_OBJ_GAP))
            blizzBottom:Show()
            local bwH = blizzBottom:GetHeight() or 0
            if bwH > 0 then
                objTotalH = objTotalH + C.SCENARIO_OBJ_GAP + bwH
            end
        end
    end

    local totalH = titleH + objTotalH
    block:SetHeight(totalH)
    return totalH
end
