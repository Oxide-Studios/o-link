-- Which server inventory adapter binds with ak47_qb_inventory started, and how it calls ak47.
-- ak47 declares `provides { 'qb-inventory' }`, so FXServer answers 'started' for qb-inventory
-- whenever ak47 runs; the world below models that. The fake ak47 follows what
-- ak47_qb_inventory 12.2 did on a QBCore test server:
--   * an inventory is readable only while it is in memory;
--   * LoadInventory(id) loads a saved inventory and never creates one; with data it creates a
--     missing one, but only when data has slots and maxWeight;
--   * every slot is listed, an empty one as {}, under qb key names (amount, info);
--   * RemoveItem raises an error for an inventory not in memory, AddItem returns false;
--   * CreateInventory errors without maxWeight; CreateShop takes (id, label, items, account);
--     there is no OpenShop export; trunks are 'trunk:<plate>'.
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

local calls, bound, impls, ak

local function callsTo(fn)
    local out = {}
    for _, c in ipairs(calls) do
        if c.fn == fn then out[#out + 1] = c end
    end
    return out
end

-- Fake ak47 ------------------------------------------------------------------------------------------
local function newAk47()
    local self = { memory = {}, saved = {}, opened = {}, shops = {} }

    local function blank(data)
        local items = {}
        for slot = 1, data.slots do items[slot] = {} end
        return { label = data.label, slots = data.slots, maxWeight = data.maxWeight, type = data.type, items = items }
    end

    local api = {}
    function api.GetInventory(id) return self.memory[id] end
    function api.LoadInventory(id, data)
        if self.memory[id] then return true end
        if self.saved[id] then self.memory[id] = self.saved[id]; return true end
        if not data or not data.slots or not data.maxWeight then return false end
        self.memory[id] = blank(data)
        return true
    end
    function api.CreateInventory(_, data)
        if not data.maxWeight then error('attempt to perform arithmetic on a nil value (field \'maxWeight\')') end
    end
    function api.AddItem(id, item, amount, slot, info)
        local inv = self.memory[id]
        if not inv then return false end
        if self.refuse == item then return false end
        for s = 1, inv.slots do
            if not inv.items[s].name then
                inv.items[s] = { name = item, amount = amount, slot = s, info = info or {}, label = item }
                return true
            end
        end
        return false
    end
    function api.RemoveItem(id, item, amount)
        local inv = self.memory[id]
        if not inv then error('nil') end
        for s = 1, inv.slots do
            local entry = inv.items[s]
            if entry.name == item and entry.amount >= amount then
                entry.amount = entry.amount - amount
                if entry.amount == 0 then inv.items[s] = {} end
                return true
            end
        end
        return false
    end
    function api.ClearInventory(id)
        local inv = self.memory[id]
        if not inv then return end
        for s = 1, inv.slots do inv.items[s] = {} end
    end
    function api.OpenInventory(src, id) self.opened[#self.opened + 1] = { src = src, id = id } end
    function api.CreateShop(id, label, items, account)
        if type(id) ~= 'string' then error('nil') end
        self.shops[id] = { label = label, items = items, account = account }
        self.memory[id] = { type = 'shop', label = label, items = {} }
    end
    function api.GetSlot(_, slot) return slot == 1 and { name = 'water_bottle', amount = 2, slot = 1 } or {} end
    function api.OnChangeVehiclePlate(old, new)
        for _, kind in ipairs({ 'trunk:', 'glovebox:' }) do
            self.memory[kind .. new], self.memory[kind .. old] = self.memory[kind .. old], nil
        end
    end

    -- Unload drops an inventory from memory and keeps what was saved.
    function self.unload(id)
        self.saved[id] = self.memory[id]
        self.memory[id] = nil
    end

    self.proxy = setmetatable({}, { __index = function(_, fn)
        local impl = api[fn]
        if not impl then error(('No such export %s in resource ak47_qb_inventory'):format(fn)) end
        return function(_, ...)
            calls[#calls + 1] = { fn = fn, args = table.pack(...) }
            return impl(...)
        end
    end })
    return self
end

local function stubWorld(started, override)
    calls, bound, impls = {}, {}, {}
    ak = newAk47()
    GetResourceState = function(name) return started[name] and 'started' or 'missing' end
    GetResourceMetadata = function(name, key)
        if key == 'version' and name == 'qb-inventory' and started.ak47_qb_inventory then return '12.2' end
        return nil
    end
    LoadResourceFile = function(resource, path)
        if resource == 'ak47_qb_inventory' and path == 'web/build/images/water_bottle.png' then return 'png' end
        return nil
    end
    RegisterNetEvent = function() end
    TriggerClientEvent = function() end
    Wait = function() end
    exports = setmetatable({}, { __index = function(_, name)
        if name == 'qb-core' then
            return { GetCoreObject = function()
                return { Shared = { Items = {} }, Functions = { GetPlayer = function() end } }
            end }
        end
        if name == 'ak47_qb_inventory' then return ak.proxy end
        return setmetatable({}, { __index = function() return function() end end })
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

local function names(list)
    local out = {}
    for _, item in ipairs(list or {}) do out[#out + 1] = ('%s:%s'):format(item.name, item.count) end
    return table.concat(out, ',')
end

-- Selection ---------------------------------------------------------------------------------------
local ak47World = { ak47_qb_inventory = true, ['qb-inventory'] = true }
case('ak47 started (qb-inventory answers through provides)', ak47World, nil, 'ak47')
case('qb-inventory alone', { ['qb-inventory'] = true }, nil, 'qb')
case('nothing started', {}, nil, 'default')
case('ak47 with an explicit qb-inventory override', ak47World, 'qb-inventory', 'qb')
case('ak47 with the ak47 override', ak47World, 'ak47_qb_inventory', 'ak47')
case('oxide-inventory wins over ak47', { ak47_qb_inventory = true, ['qb-inventory'] = true, ['oxide-inventory'] = true }, nil, '')

loadAll(ak47World, nil)
local inv = impls.ak47
check('ak47 adapter bound', inv ~= nil)
check('ak47 adapter can read stashes', inv.CanReadStashes() == true)

-- RegisterStash -----------------------------------------------------------------------------------
check('RegisterStash creates a missing stash', inv.RegisterStash('police_jail_locker_ABC', 'Jail Locker ABC', 50, 500000, 'ABC') == true)
local loads = callsTo('LoadInventory')
local data = loads[#loads] and loads[#loads].args[2] or {}
check('LoadInventory maxWeight', data.maxWeight == 500000)
check('LoadInventory slots', data.slots == 50)
check('LoadInventory label', data.label == 'Jail Locker ABC')
check('LoadInventory type stash', data.type == 'stash')
check('CreateInventory never called', #callsTo('CreateInventory') == 0)

local before = #callsTo('LoadInventory')
inv.RegisterStash('police_jail_locker_ABC', 'Jail Locker ABC', 50, 500000, 'ABC')
check('a stash in memory is not loaded again', #callsTo('LoadInventory') == before)

-- A caller passing no size still gets a usable stash, and nothing raises.
local okNil, nilResult = pcall(inv.RegisterStash, 'weed_tote_1', 'Storage Tote', nil, nil)
check('RegisterStash with nil slots and weight does not raise', okNil)
check('RegisterStash with nil slots and weight registers', nilResult == true)
check('nil size gets the default slots', ak.memory.weed_tote_1 and ak.memory.weed_tote_1.slots == 20)
check('nil size gets the default weight', ak.memory.weed_tote_1 and ak.memory.weed_tote_1.maxWeight == 5000)
check('string sizes are read as numbers', inv.RegisterStash('trash_1', 'Trash', '10', '50000') == true and ak.memory.trash_1.slots == 10)

-- Stash reads ---------------------------------------------------------------------------------------
check('empty stash reads as empty', next(inv.GetStashItems('police_jail_locker_ABC')) == nil)
check('AddStashItem true', inv.AddStashItem('police_jail_locker_ABC', 'water_bottle', 2, { a = 1 }) == true)
local items = inv.GetStashItems('police_jail_locker_ABC')
check('GetStashItems lists only occupied slots', #items == 1)
check('GetStashItems gives count and amount', items[1].count == 2 and items[1].amount == 2)
check('GetStashItems gives metadata and info', items[1].metadata.a == 1 and items[1].info.a == 1)
check('GetStashItems gives the slot', items[1].slot == 1)

-- A stash ak47 dropped from memory is read and written after loading it again.
ak.unload('police_jail_locker_ABC')
check('unloaded stash is read from what was saved', names(inv.GetStashItems('police_jail_locker_ABC')) == 'water_bottle:2')
ak.unload('police_jail_locker_ABC')
check('RemoveStashItem on an unloaded stash loads it and removes', inv.RemoveStashItem('police_jail_locker_ABC', 'water_bottle', 1) == true)
ak.unload('police_jail_locker_ABC')
check('AddStashItem on an unloaded stash loads it and adds', inv.AddStashItem('police_jail_locker_ABC', 'sandwich', 1) == true)
check('both changes kept', names(inv.GetStashItems('police_jail_locker_ABC')) == 'water_bottle:1,sandwich:1')

-- A registered stash that was never saved is created again with its registered size.
ak.memory.trash_1 = nil
check('registered stash comes back after it was dropped unsaved', inv.AddStashItem('trash_1', 'water_bottle', 1) == true and ak.memory.trash_1.slots == 10)

-- An id nobody registered and nothing saved: no stash is created and nothing raises.
local okRemove, removed = pcall(inv.RemoveStashItem, 'never_registered', 'water_bottle', 1)
check('RemoveStashItem on an unknown id does not raise', okRemove and removed == false)
check('AddStashItem on an unknown id is refused', inv.AddStashItem('never_registered', 'water_bottle', 1) == false)
check('GetStashItems on an unknown id is empty', next(inv.GetStashItems('never_registered')) == nil)
check('no stash created for an unknown id', ak.memory.never_registered == nil)

-- AddStashItems reports whether every item was stored.
check('AddStashItems all stored', inv.AddStashItems('police_jail_locker_ABC', { { item = 'radio', count = 1 }, { name = 'lockpick', amount = 2 } }) == true)
ak.refuse = 'phone'
check('AddStashItems false when one is refused', inv.AddStashItems('police_jail_locker_ABC', { { item = 'radio', count = 1 }, { item = 'phone', count = 1 } }) == false)
ak.refuse = nil

-- OpenStash -----------------------------------------------------------------------------------------
ak.unload('police_jail_locker_ABC')
inv.OpenStash(1, 'police_jail_locker_ABC')
check('OpenStash loads an unloaded stash and opens it', ak.opened[1] and ak.opened[1].id == 'police_jail_locker_ABC' and ak.memory.police_jail_locker_ABC ~= nil)
inv.OpenStash(1, 'never_registered')
check('OpenStash does not open an unknown id', #ak.opened == 1)

-- ClearStash ----------------------------------------------------------------------------------------
check('ClearStash empties a stash', inv.ClearStash('police_jail_locker_ABC') == true and next(inv.GetStashItems('police_jail_locker_ABC')) == nil)
ak.saved.police_trash_2 = { slots = 2, maxWeight = 1000, type = 'stash', items = { { name = 'water_bottle', amount = 1, slot = 1 }, {} } }
check('ClearStash empties a saved stash not in memory', inv.ClearStash('police_trash_2') == true and ak.memory.police_trash_2.items[1].name == nil)
check('ClearStash on an unknown id has nothing to clear', inv.ClearStash('never_registered') == true and ak.memory.never_registered == nil)

-- Trunks --------------------------------------------------------------------------------------------
check('GetTrunkItems is nil for a trunk ak47 has not loaded', inv.GetTrunkItems('ABC123') == nil)
check('AddTrunkItems stores', inv.AddTrunkItems('ABC123', { { item = 'armor', count = 2 }, { name = 'medkit', amount = 1 } }) == true)
local trunk = ak.memory['trunk:ABC123']
check('trunk id is trunk:<plate>', trunk ~= nil and ak.memory['trunk-ABC123'] == nil)
check('trunk created with maxWeight and type trunk', trunk and trunk.maxWeight == 60000 and trunk.type == 'trunk' and trunk.slots == 35)
check('GetTrunkItems reads it back', names(inv.GetTrunkItems('ABC123')) == 'armor:2,medkit:1')
check('AddTrunkItems with nothing to add', inv.AddTrunkItems('ABC123', {}) == true)
ak.refuse = 'armor'
check('AddTrunkItems false when nothing was stored', inv.AddTrunkItems('ABC123', { { item = 'armor', count = 1 } }) == false)
ak.refuse = nil
check('ClearStash trunk clears trunk:<plate>', inv.ClearStash('ABC123', 'trunk') == true and next(inv.GetTrunkItems('ABC123')) == nil)
check('GetTrunkItems on an emptied trunk is an empty list', type(inv.GetTrunkItems('ABC123')) == 'table')
check('CreateInventory still never called', #callsTo('CreateInventory') == 0)

-- GTA pads a short plate (' LS 456 '); ak47 trims it.
check('padded plate maps to the trimmed trunk', inv.AddTrunkItems(' LS 456 ', { { item = 'armor', count = 1 } }) == true and ak.memory['trunk:LS 456'] ~= nil)
check('trimmed and padded plates read the same trunk', names(inv.GetTrunkItems('LS 456')) == 'armor:1')
ak.memory['glovebox:LS 456'] = { slots = 1, maxWeight = 1000, type = 'glovebox', items = { { name = 'radio', amount = 1, slot = 1 } } }
check('ClearStash glovebox clears glovebox:<plate>', inv.ClearStash(' LS 456 ', 'glovebox') == true and ak.memory['glovebox:LS 456'].items[1].name == nil)

inv.AddTrunkItems('OLD1', { { item = 'armor', count = 1 } })
check('UpdatePlate moves the trunk', inv.UpdatePlate('OLD1', 'NEW1') == true and names(inv.GetTrunkItems('NEW1')) == 'armor:1' and inv.GetTrunkItems('OLD1') == nil)

-- Shops ---------------------------------------------------------------------------------------------
check('RegisterShop', inv.RegisterShop('t_shop', { { name = 'water_bottle', price = 5 }, { name = 'sandwich', price = 7, count = 10 } }) == true)
local shop = ak.shops.t_shop
check('CreateShop gets id, label, items and account', shop and shop.label == 't_shop' and shop.account == 'cash')
check('shop items in ak47 shape', shop and shop.items[1].item == 'water_bottle' and shop.items[1].buyPrice == 5 and shop.items[1].amount == nil and shop.items[2].amount == 10)
inv.OpenShop(1, 't_shop')
check('OpenShop opens the shop', ak.opened[#ak.opened].id == 't_shop')
local opened = #ak.opened
inv.OpenShop(1, 'police_jail_locker_ABC')
check('OpenShop does not open a stash', #ak.opened == opened)

-- Other reads ---------------------------------------------------------------------------------------
check('GetItemBySlot of an empty slot is nil', inv.GetItemBySlot(1, 2) == nil)
check('GetItemBySlot of an item', inv.GetItemBySlot(1, 1).count == 2)
check('GetImagePath points at ak47 images', inv.GetImagePath('water_bottle') == 'nui://ak47_qb_inventory/web/build/images/water_bottle.png')

print(('[inventory-ak47] %d passed, %d failed'):format(passed, failed))
if failed > 0 then error(('%d checks failed'):format(failed)) end
