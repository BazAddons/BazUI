-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: AddonListButton
--
-- Adds an "Addon Options" button to Blizzard's AddOn List window, sitting
-- to the left of the "Reload UI / Okay" button. Clicking it closes the
-- AddOn List and opens the in-game Settings panel so the user can jump
-- to any addon's options page without reopening menus.
---------------------------------------------------------------------------

local function OpenAddonOptions()
    HideUIPanel(AddonList)
    -- Open directly to BazUI's options category - puts the user on the
    -- correct Settings tab with the Baz Suite sidebar expanded and ready.
    if BazUI.OpenOptionsPanel then
        BazUI:OpenOptionsPanel("BazUI")
        return
    end
    -- Fallback if OptionsPanel module isn't loaded
    if SettingsPanel and SettingsPanel.Open then
        SettingsPanel:Open()
    end
end

local function AttachAddonOptionsButton()
    if not AddonList or not AddonList.OkayButton then return end
    if AddonList.BazUIAddonOptionsButton then return end

    local btn = BazUI.Skin.Theme.CreateButton(AddonList, { name = "BazUIAddonOptionsButton" })
    btn:SetText("Addon Options")
    btn:SetSize(AddonList.OkayButton:GetWidth() + 60, AddonList.OkayButton:GetHeight())
    btn:SetPoint("RIGHT", AddonList.OkayButton, "LEFT", -4, 0)
    btn:SetScript("OnClick", OpenAddonOptions)

    AddonList.BazUIAddonOptionsButton = btn
end

-- AddonList may be load-on-demand depending on the client version. Try at
-- login and also when the Blizzard_AddonList addon loads.
BazUI:QueueForLogin(AttachAddonOptionsButton)
EventUtil.ContinueOnAddOnLoaded("Blizzard_AddonList", AttachAddonOptionsButton)
