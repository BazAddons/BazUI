-- SPDX-License-Identifier: GPL-2.0-or-later
local addon = BazUI.Notifications

local function errorHandler(err)
    return geterrorhandler()(err)
end

function addon.SafeCall(func, ...)
    if type(func) == "function" then
        return xpcall(func, errorHandler, ...)
    end
end
