-- Which server inventory adapter binds with ak47_qb_inventory started, and how its RegisterStash
-- calls ak47. ak47 declares `provides { 'qb-inventory' }`, so FXServer answers 'started' for
-- qb-inventory whenever ak47 runs; the world below models that. ak47's side is stubbed from what
-- ak47_qb_inventory 12.2 did on a QBCore test server: CreateInventory errors without `maxWeight`,
-- LoadInventory(id, data) loads a saved inventory or creates it and returns true.
-- Run from the [oxide] folder: bash oxide-phone/tests/lua.sh o-link tests/inventory-ak47.lua
local passed, failed = 0, 0
local function check(name, ok)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL ' .. name) end
end

local ADAPTERS = {
    default = '_default',
    ak47 = 'ak47_qb_inventory',
    qb = 'qb-inventory',
}
local ORDER = { 'default', 'ak47', 'qb' }

local calls, responses, bound, impls

local function proxy(resource)
    return setmetatable({}, { __index = function(_, fn)
        return function(_, ...)
            calls[#calls + 1] = { resource = resource, fn = fn, args = table.pack(...) }
            local response = responses[fn]
            if type(response) == 'function' then return response(...) end
            return response
        end
    end })
end

local function callsTo(fn)
    local out = {}
    for _, c in ipairs(calls) do
        if c.fn == fn then out[#out + 1] = c end
    end
    return out
end

local function stubWorld(started, override)
    calls, responses, bound, impls = {}, {}, {}, {}
    GetResourceState = function(name) return started[name] and 'started' or 'missing' end
    GetResourceMetadata = function(name, key)
        if key == 'version' and name == 'qb-inventory' and started.ak47_qb_inventory then return '12.2' end
        return nil
    end
    LoadResourceFile = function() return nil end
    RegisterNetEvent = function() end
    TriggerClientEvent = function() end
    Wait = function() end
    exports = setmetatable({}, { __index = function(_, name)
        if name == 'qb-core' then
            return { GetCoreObject = function()
                return { Shared = { Items = {} }, Functions = { GetPlayer = function() end } }
            end }
        end
        return proxy(name)
    end })
    olink = {
        _hasOverride = function() return override ~= nil end,
        _guardImpl = function(_, implName, resourceName)
            if override and override ~= implName then return false end
            if resourceName == false then return true end
            return started[resourceName or implName] == true
        end,
        _stripExt = function(item) return (item:gsub('%.%w+$', '')) end,
    }
end

local function loadAll(started, override)
    stubWorld(started, override)
    for _, key in ipairs(ORDER) do
        local register = function(namespace, def)
            if namespace ~= 'inventory' then return end
            bound[#bound + 1] = key
            impls[key] = def
        end
        olink._register = register
        olink._registerDefault = register
        dofile(('modules/inventory/%s/server.lua'):format(ADAPTERS[key]))
    end
    return table.concat(bound, ',')
end

local function case(name, started, override, expected)
    local got = loadAll(started, override)
    check(('%s: expected %s, got %s'):format(name, expected, got), got == expected)
end

-- Selection ---------------------------------------------------------------------------------------
local ak47World = { ak47_qb_inventory = true, ['qb-inventory'] = true }
case('ak47 started (qb-inventory answers through provides)', ak47World, nil, 'ak47')
case('qb-inventory alone', { ['qb-inventory'] = true }, nil, 'qb')
case('nothing started', {}, nil, 'default')
case('ak47 with an explicit qb-inventory override', ak47World, 'qb-inventory', 'qb')
case('ak47 with the ak47 override', ak47World, 'ak47_qb_inventory', 'ak47')
case('oxide-inventory wins over ak47', { ak47_qb_inventory = true, ['qb-inventory'] = true, ['oxide-inventory'] = true }, nil, '')

-- The adapter that binds with ak47 reads stashes and stores into them.
loadAll(ak47World, nil)
local inv = impls.ak47
check('ak47 adapter bound', inv ~= nil)
check('ak47 adapter can read stashes', inv.CanReadStashes() == true)

-- RegisterStash -----------------------------------------------------------------------------------
-- Not in memory (a fresh stash, or any stash after a restart): LoadInventory with ak47's field names.
responses.GetInventory = nil
responses.LoadInventory = true
responses.CreateInventory = function() error('attempt to perform arithmetic on a nil value (field \'maxWeight\')') end
check('RegisterStash loads a missing stash', inv.RegisterStash('police_jail_locker_ABC', 'Jail Locker ABC', 50, 500000, 'ABC') == true)
local loads = callsTo('LoadInventory')
check('LoadInventory called once', #loads == 1)
local data = loads[1] and loads[1].args[2] or {}
check('LoadInventory id', loads[1] and loads[1].args[1] == 'police_jail_locker_ABC')
check('LoadInventory maxWeight', data.maxWeight == 500000)
check('LoadInventory slots', data.slots == 50)
check('LoadInventory label', data.label == 'Jail Locker ABC')
check('LoadInventory type stash', data.type == 'stash')
check('CreateInventory never called', #callsTo('CreateInventory') == 0)

-- Registered once per id.
inv.RegisterStash('police_jail_locker_ABC', 'Jail Locker ABC', 50, 500000, 'ABC')
check('second RegisterStash is cached', #callsTo('LoadInventory') == 1)

-- Already in memory: nothing is loaded over it.
responses.GetInventory = { identifier = 'police_jail_locker_DEF', items = {} }
check('RegisterStash with the stash in memory', inv.RegisterStash('police_jail_locker_DEF', 'Jail Locker DEF', 50, 500000) == true)
check('in-memory stash not reloaded', #callsTo('LoadInventory') == 1)

-- A failed load reports false and is retried on the next call.
responses.GetInventory = nil
responses.LoadInventory = false
check('failed load returns false', inv.RegisterStash('police_jail_locker_GHI', 'Jail Locker GHI', 50, 500000) == false)
responses.LoadInventory = true
check('failed load retried', inv.RegisterStash('police_jail_locker_GHI', 'Jail Locker GHI', 50, 500000) == true)
check('retry loaded again', #callsTo('LoadInventory') == 3)

-- Stash reads and writes go to ak47 by id.
responses.AddItem = true
check('AddStashItem true', inv.AddStashItem('police_jail_locker_ABC', 'water_bottle', 2, { a = 1 }) == true)
local add = callsTo('AddItem')[1]
check('AddStashItem args', add and add.args[1] == 'police_jail_locker_ABC' and add.args[2] == 'water_bottle' and add.args[3] == 2 and add.args[5].a == 1)
responses.AddItem = false
check('AddStashItem refused is false', inv.AddStashItem('police_jail_locker_ABC', 'water_bottle', 2) == false)
responses.GetInventory = { items = { { name = 'water_bottle', amount = 2, slot = 1 }, {} } }
local items = inv.GetStashItems('police_jail_locker_ABC')
check('GetStashItems returns the slot table', items[1].name == 'water_bottle' and items[1].amount == 2)

print(('[inventory-ak47] %d passed, %d failed'):format(passed, failed))
if failed > 0 then error(('%d checks failed'):format(failed)) end
