-- SPDX-License-Identifier: GPL-2.0-or-later
-- BazUI Notifications: shared namespace. Every file in this module fetches
-- `addon` from here (the old addon-private table) and `addon.API` is the
-- notification API other modules and addons call (the old BNC global).
local addon = BazUI.Notifications or {}
BazUI.Notifications = addon
addon.API = addon.API or {}
