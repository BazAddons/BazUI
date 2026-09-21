-- SPDX-License-Identifier: GPL-2.0-or-later
local Codex = BazUI.Codex
local addon = BazUI:GetModule("Codex")

local function Get(key) return function() return addon:GetSetting(key) end end
local function Set(key)
    return function(_, value)
        addon:SetSetting(key, value)
        Codex:ApplySettings()
    end
end

local function IndexCount()
    local n = 0
    for _ in pairs(addon:GetSetting("itemIndex") or {}) do n = n + 1 end
    return n
end

BazUI:RegisterSettingsSpec("Codex", {
    sections = {
        window = { label = "Window", order = 1 },
        items  = { label = "Item Lookup", order = 2 },
    },
    entries = {
        { key = "scale", label = "Scale", type = "slider", section = "window", order = 1,
          min = 0.6, max = 1.6, step = 0.05, format = "percent",
          get = Get("scale"), set = Set("scale") },
        { key = "opacity", label = "Background opacity", type = "slider", section = "window", order = 2,
          min = 0.3, max = 1, step = 0.05, format = "percent",
          get = Get("opacity"), set = Set("opacity") },
        { key = "reset", label = "Reset position", type = "execute", section = "window", order = 3,
          func = function()
              addon:SetSetting("position", nil)
              Codex:ApplySettings()
          end },
        { key = "open", label = "Open the codex", type = "execute", section = "window", order = 4,
          func = function() Codex:Show() end },

        { key = "indexItems", label = "Remember items this character meets", type = "toggle",
          section = "items", order = 1, get = Get("indexItems"), set = Set("indexItems") },
        { key = "indexNote", type = "note", section = "items", order = 2,
          text = "The list you see before you type is what this character has met: carried, worn, banked or looked up. On WoW: Forever, typing a name searches every item in the game; elsewhere it searches that list. A link or an item number looks up anything, anywhere, and needs none of this." },
        { key = "clearIndex", label = "Forget remembered items", type = "execute", section = "items", order = 3,
          confirm = true,
          confirmText = "Empty the list of items this character has met? Lookups by link or number are unaffected.",
          func = function()
              local count = IndexCount()
              addon:SetSetting("itemIndex", {})
              if Codex.Panel then Codex.Panel:QueueRefresh() end
              BazUI:Print(("Codex: forgot %d remembered %s."):format(
                  count, count == 1 and "item" or "items"))
          end },
    },
})

BazUI:QueueForModule("Codex", function()
    BazUI:RegisterOptionsTable("Codex", function()
        return BazUI:BuildOptionsTableFromSpec("Codex", { name = "Codex" })
    end)
    BazUI:AddToSettings("Codex", "Codex")
end)
