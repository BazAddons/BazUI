-- SPDX-License-Identifier: GPL-2.0-or-later
---------------------------------------------------------------------------
-- BazUI: ObjectPool
-- Reusable object pool for efficient UI element recycling
---------------------------------------------------------------------------

local ObjectPool = {}
ObjectPool.__index = ObjectPool

function ObjectPool:Acquire(...)
    local obj = next(self.cache)
    if obj then
        self.cache[obj] = nil
    else
        self.count = self.count + 1
        obj = self.createFunc(self.count, ...)
    end
    self.active[obj] = true
    return obj
end

function ObjectPool:Release(obj)
    if not self.active[obj] then return end
    self.active[obj] = nil
    if self.resetFunc then
        self.resetFunc(obj)
    end
    self.cache[obj] = true
end

function ObjectPool:ReleaseAll()
    for obj in pairs(self.active) do
        self:Release(obj)
    end
end

function ObjectPool:GetNumActive()
    local count = 0
    for _ in pairs(self.active) do
        count = count + 1
    end
    return count
end

---------------------------------------------------------------------------
-- Factory
---------------------------------------------------------------------------

function BazUI:CreateObjectPool(createFunc, resetFunc)
    local pool = setmetatable({}, ObjectPool)
    pool.createFunc = createFunc
    pool.resetFunc = resetFunc
    pool.cache = {}
    pool.active = {}
    pool.count = 0
    return pool
end
