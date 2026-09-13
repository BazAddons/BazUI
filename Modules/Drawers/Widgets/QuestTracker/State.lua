-- SPDX-License-Identifier: GPL-2.0-or-later
-- QuestTracker: Shared Mutable State
-- Single source of truth for all cross-file state (pools, items list,
-- scroll position, frame refs). Initialized once at file load.

local addon = BazUI:GetModule("Drawers")
if not addon then return end
local QT = addon.QT

-- Frame pools
QT.blockPool     = {}
QT.activeBlocks  = {}
QT.headerPool    = {}
QT.activeHeaders = {}

-- Display state
QT.items          = {}   -- flat list: { frame, height, gap, kind, topPad }
QT.scrollIndex    = 0
QT._desiredHeight = QT.C.MIN_HEIGHT
QT._count         = 0

-- Frame refs (set by Init.lua:Build)
QT.frame      = nil
QT.scrollChild = nil
