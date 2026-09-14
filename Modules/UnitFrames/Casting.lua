-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI:GetModule("UnitFrames")
local C = {}
addon.Casting = C
local colors = { gold = {1, .68, .16}, arcane = {.65, .35, 1}, frost = {.25, .75, 1}, jade = {.25, 1, .55} }
local stockParents = {}
local function Enabled() return addon:GetSetting("enabled") ~= false and addon:GetSetting("castEnabled") ~= false end
local function Setting(key, fallback) local n = tonumber(addon:GetSetting(key)); return n or fallback end

function C:Clear()
    self.state = nil
    self.frame:Hide()
    self.frame:SetScript("OnUpdate", nil)
    self.name:SetAlpha(1)
end

function C:Finish(result)
    local s = self.state
    if not s then return end
    s.result, s.fade = result, GetTime()
end

function C:Draw()
    local s = self.state
    if not s then return end
    local now = GetTime()
    if not s.fade and now >= s.finish then self:Finish("complete") end
    local remaining = math.max(0, s.finish - now)
    local fraction = math.max(0, math.min(1, (now - s.start) / (s.finish - s.start)))
    if s.channel then fraction = 1 - fraction end
    if s.fade then
        if now - s.fade >= .45 then self:Clear(); return end
        self.frame:SetAlpha(1 - (now - s.fade) / .45)
        if s.result == "complete" then fraction = s.channel and 0 or 1 end
    else self.frame:SetAlpha(1) end
    local opacity = math.max(.05, math.min(.75, Setting("castOpacity", .42)))
    local intensity = math.max(0, math.min(1, Setting("castSwirl", .75)))
    local rgb = colors[addon:GetSetting("castColor")] or colors.gold
    if s.result == "interrupted" then rgb = {1, .12, .08}; fraction = math.max(.5, fraction) end
    self.base:SetVertexColor(rgb[1], rgb[2], rgb[3], opacity)
    -- Light and dark currents remain legible against the translucent body.
    self.swirl:SetVertexColor(.55 + rgb[1] * .45, .55 + rgb[2] * .45, .55 + rgb[3] * .45, opacity * intensity * .95)
    self.swirl2:SetVertexColor(rgb[1] * .4, rgb[2] * .4, rgb[3] * .4, opacity * intensity * .8)
    self.swirl:SetRotation(now * .95 * intensity)
    self.swirl2:SetRotation(-now * .65 * intensity + 1.7)
    -- Stretch and slide the ripple together with its matching crest. This
    -- changes the visible wavelength as well as phase, instead of moving a
    -- rigid line upward. Overscan keeps the mask edges outside the aperture.
    local width = self.side * (1.4 + .16 * math.sin(now * 1.9) * intensity)
    local height = self.side * (1.16 + .08 * math.sin(now * 2.3 + .8) * intensity)
    local x = (self.side - width) / 2 + math.sin(now * 2.5) * .07 * intensity * self.side
    local bob = math.sin(now * 3.1) * .008 * intensity * math.sin(fraction * math.pi)
    local y = (fraction - 1 + .04 + bob) * self.side
    self.liquidMask:SetSize(width, height)
    self.crest:SetSize(width, height)
    self.liquidMask:ClearAllPoints()
    self.liquidMask:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
    self.crest:ClearAllPoints()
    self.crest:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
    local shimmer = .85 + .15 * math.sin(now * 4.3) * intensity
    self.crest:SetVertexColor(.6 + rgb[1] * .4, .6 + rgb[2] * .4, .6 + rgb[3] * .4, math.min(.8, opacity * 1.65) * shimmer)
    local showLiquid = fraction > .001
    self.base:SetShown(showLiquid); self.swirl:SetShown(showLiquid); self.swirl2:SetShown(showLiquid)
    self.crest:SetShown(fraction > .01 and fraction < .99)
    local flash = s.fade and s.result ~= "cancelled" and .3 * (1 - (now - s.fade) / .45) or 0
    self.flash:SetVertexColor(rgb[1], rgb[2], rgb[3], flash)
    local showText = addon:GetSetting("castText") ~= false
    self.name:SetAlpha(showText and 0 or 1)
    self.label:SetShown(showText); self.timer:SetShown(showText)
    self.label:SetText(s.result == "interrupted" and "Interrupted" or s.name)
    self.timer:SetText(s.fade and "" or string.format("%.1f", remaining))
end

function C:Start(name, startMS, endMS, channel, guid)
    if not Enabled() or not name or not startMS or not endMS or endMS <= startMS then return end
    self.state = {name = name, start = startMS / 1000, finish = endMS / 1000, channel = channel, guid = guid}
    self.frame:Show()
    local elapsed = 0
    self.frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 1 / 30 then elapsed = 0; self:Draw() end
    end)
    self:Draw()
end

function C:Sync(guid)
    local name, _, _, startMS, endMS, _, castID = UnitCastingInfo("player")
    if name then self:Start(name, startMS, endMS, false, guid or castID); return end
    name, _, _, startMS, endMS = UnitChannelInfo("player")
    if name then self:Start(name, startMS, endMS, true, guid) end
end

function C:Event(event, unit, guid)
    if unit ~= "player" then return end
    local s = self.state
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        self:Sync(guid)
    elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        if not s or not guid or not s.guid or guid == s.guid then self:Sync(guid) end
    elseif s and (not guid or not s.guid or guid == s.guid) then
        if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then self:Finish("interrupted")
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if not s.channel then self:Finish("complete") end
        elseif not s.fade then self:Finish(GetTime() >= s.finish - .15 and "complete" or "cancelled") end
    end
end

function C:Preview()
    if not self.frame or not Enabled() then addon:Print("Enable the player frame and portrait casting first."); return end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return end
    self:Start("Liquid casting preview", GetTime() * 1000, (GetTime() + 5) * 1000, false, "preview")
end

function C:Apply()
    if not self.frame then return end
    -- Upgrade untouched original defaults once, preserving custom choices.
    local version = addon:GetSetting("castMotionVersion") or 0
    if version < 1 then
        if addon:GetSetting("castOpacity") == .28 then addon:SetSetting("castOpacity", .42) end
        if addon:GetSetting("castSwirl") == .55 then addon:SetSetting("castSwirl", .75) end
    end
    if version < 2 then
        -- Only moves a value still sitting on the old default: anyone who
        -- set their own keeps it.
        if addon:GetSetting("castOpacity") == .42 then addon:SetSetting("castOpacity", .55) end
    end
    if version < 2 then addon:SetSetting("castMotionVersion", 2) end
    -- Called by the player's combat-deferred ApplySettings, never from cast events.
    for _, key in ipairs({"CastingBarFrame", "PlayerCastingBarFrame"}) do
        local stock = _G[key]
        if stock then
            if Enabled() and not stockParents[stock] then
                stockParents[stock] = stock:GetParent() or UIParent
                stock:SetParent(self.hidden)
            elseif not Enabled() and stockParents[stock] then
                stock:SetParent(stockParents[stock]); stockParents[stock] = nil
                if stock.OnEvent then stock:OnEvent("PLAYER_ENTERING_WORLD") end
            end
        end
    end
    if not Enabled() then self:Clear()
    elseif self.state then self:Draw()
    else self:Sync() end
end

function C:Create(parent, name)
    if self.frame then return end
    local L = addon.Layout
    local ratio = 640 / L.width
    self.side = math.min(L.portrait.w, L.portrait.h) * ratio
    self.name = name
    self.hidden = CreateFrame("Frame"); self.hidden:Hide()
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    f:SetFrameLevel(parent:GetFrameLevel() + 7)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", L.portrait.x * ratio, -L.portrait.y * ratio)
    f:SetSize(self.side, self.side); f:EnableMouse(false)
    local circle = f:CreateMaskTexture()
    circle:SetAllPoints(f)
    circle:SetTexture(BazUI.Skin.ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    self.liquidMask = f:CreateMaskTexture()
    self.liquidMask:SetSize(self.side * 1.2, self.side * 1.1)
    self.liquidMask:SetTexture(BazUI.Skin.CAST_LIQUID_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    local function Texture(path, layer, liquid)
        local t = f:CreateTexture(nil, layer)
        t:SetAllPoints(f)
        if path then t:SetTexture(path) else t:SetColorTexture(1, 1, 1, 1) end
        t:AddMaskTexture(circle)
        if liquid then t:AddMaskTexture(self.liquidMask) end
        return t
    end
    self.base = Texture(nil, "BACKGROUND", true)
    self.swirl = Texture(BazUI.Skin.CAST_SWIRL, "ARTWORK", true)
    self.swirl2 = Texture(BazUI.Skin.CAST_SWIRL, "ARTWORK", true)
    self.crest = Texture(BazUI.Skin.CAST_CREST, "OVERLAY", false)
    self.crest:ClearAllPoints(); self.crest:SetSize(self.side * 1.2, self.side * 1.1)
    self.flash = Texture(nil, "OVERLAY", false)
    self.label = f:CreateFontString(nil, "OVERLAY")
    self.label:SetAllPoints(name)
    self.label:SetFont(BazUI.Skin.Theme.FontFile(), 10, "OUTLINE")
    self.label:SetTextColor(1, .84, .5); self.label:SetWordWrap(false)
    -- The count sits in the middle of the portrait, over the liquid, and
    -- is sized from the portrait itself so it holds its proportions at
    -- any frame scale rather than shrinking into the artwork.
    self.timer = f:CreateFontString(nil, "OVERLAY")
    self.timer:SetPoint("CENTER", f, "CENTER", 0, 0)
    self.timer:SetFont(BazUI.Skin.Theme.FontFile(),
        math.max(13, math.floor(self.side * 0.30)), "OUTLINE")
    f:Hide()
    -- A dedicated event receiver avoids replacing UnitFrames' existing
    -- PLAYER_DEAD / PLAYER_ENTERING_WORLD handlers in BazUI's event registry.
    for _, event in ipairs({"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP"}) do
        f:RegisterUnitEvent(event, "player")
    end
    f:RegisterEvent("PLAYER_DEAD"); f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, event, unit, guid)
        if event == "PLAYER_DEAD" then self:Clear()
        elseif event == "PLAYER_ENTERING_WORLD" then self:Clear(); self:Sync()
        else self:Event(event, unit, guid) end
    end)
end
