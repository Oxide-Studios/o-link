-- Which inventory adapter binds with Codem Inventory V2 started, and what the ox_inventory adapter
-- calls on it. The V2 side is stubbed from Codem's documentation: no V2 copy was available. Every
-- case without V2 pins the selection and calls as they were before V2 support.
-- Run from the o-link folder: lua tests/inventory-codem-v2.lua
local passed, failed = 0, 0
local function check(name, ok)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL ' .. name) end
end

local ADAPTERS = {
    ox = 'ox_inventory',
    qb = 'qb-inventory',
    default = '_default',
    v1 = 'codem-inventory',
}

local calls, responses, files, bound, impl

local function resetCalls()
    calls = {}
    responses = {}
    files = {}
end

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

local function lastCall(fn)
    for i = #calls, 1, -1 do
        if calls[i].fn == fn then return calls[i] end
    end
end

-- Mirrors the check in core/shared.lua: an override picks the adapter by name, otherwise the named
-- resource has to be started.
local function stubWorld(started, override)
    bound, impl = {}, {}
    GetResourceState = function(name) return started[name] and 'started' or 'missing' end
    GetResourceMetadata = function() return nil end
    GetGameTimer = function() return 0 end
    RegisterNetEvent = function() end
    LoadResourceFile = function(resource, path) return files[resource .. '/' .. path] end
    exports = setmetatable({}, { __index = function(_, name)
        if name == 'qb-core' then
            return { GetCoreObject = function()
                return { Functions = { GetPlayer = function() end, GetPlayerData = function() return {} end } }
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

local function loadAdapter(key, side)
    local register = function(namespace, def)
        if namespace ~= 'inventory' then return end
        bound[key] = true
        impl = def
    end
    olink._register = register
    olink._registerDefault = register
    dofile(('modules/inventory/%s/%s.lua'):format(ADAPTERS[key], side))
end

local function boundList(started, override, side)
    resetCalls()
    stubWorld(started, override)
    for _, key in ipairs({ 'default', 'v1', 'ox', 'qb' }) do loadAdapter(key, side) end
    local names = {}
    for _, key in ipairs({ 'default', 'v1', 'ox', 'qb' }) do
        if bound[key] then names[#names + 1] = key end
    end
    return table.concat(names, ',')
end

for _, side in ipairs({ 'server', 'client' }) do
    local function case(name, started, override, expected)
        local got = boundList(started, override, side)
        check(('%s %s: expected %s, got %s'):format(side, name, expected, got), got == expected)
    end

    -- No V2: the selection stays as it was.
    case('nothing started', {}, nil, 'default')
    case('ox_inventory alone', { ox_inventory = true }, nil, 'ox')
    case('qb-inventory alone', { ['qb-inventory'] = true }, nil, 'qb')
    case('qb-inventory beats ox_inventory', { ox_inventory = true, ['qb-inventory'] = true }, nil, 'qb')
    case('V1 alone', { ['codem-inventory'] = true }, nil, 'v1')
    case('override picks ox over qb', { ox_inventory = true, ['qb-inventory'] = true }, 'ox_inventory', 'ox')

    -- V2 answers to ox_inventory, and on qb-core codem-inventory-qbcompat carries qb-inventory.
    local onQbCore = { ['codem-inventoryv2'] = true, ox_inventory = true, ['qb-inventory'] = true }
    case('V2 on qb-core', onQbCore, nil, 'ox')
    case('V2 on qbx or esx', { ['codem-inventoryv2'] = true, ox_inventory = true }, nil, 'ox')
    case('V2 when its aliases do not resolve', { ['codem-inventoryv2'] = true }, nil, 'ox')
    case('V2 with the ox_inventory override', onQbCore, 'ox_inventory', 'ox')
    case('V2 with an explicit qb-inventory override', onQbCore, 'qb-inventory', 'qb')
end

-- Server, V2 --------------------------------------------------------------------------------------
resetCalls()
stubWorld({ ['codem-inventoryv2'] = true, ox_inventory = true, ['qb-inventory'] = true }, nil)
loadAdapter('ox', 'server')
local inv = impl

responses.GetItemCount = 3
check('GetItemCount reads V2', inv.GetItemCount(1, 'meth_table') == 3)
local call = lastCall('GetItemCount')
check('calls go to V2 by its own name', call.resource == 'codem-inventoryv2')
check('GetItemCount passes source and item', call.args[1] == 1 and call.args[2] == 'meth_table')

responses.CanCarryItem = true
responses.AddItem = function() return true, { slot = 5 } end
local meta = { purity = 'High' }
check('AddItem reports success', inv.AddItem(1, 'crystal_meth', 2, 5, meta) == true)
call = lastCall('AddItem')
check('AddItem puts metadata before slot', call.args[4] == meta and call.args[5] == 5)

responses.RemoveItem = true
check('RemoveItem reports success', inv.RemoveItem(1, 'crystal_meth', 1, 7, meta) == true)
call = lastCall('RemoveItem')
check('RemoveItem puts metadata before slot', call.args[4] == meta and call.args[5] == 7)

responses.GetSlot = { name = 'water', count = 2, slot = 4, metadata = {}, weight = 100 }
responses.Items = function(item) if item then return { label = 'Water ' .. item } end end
local slot = inv.GetItemBySlot(1, 4)
check('a slot with no label takes it from the item', slot.label == 'Water water' and slot.count == 2)

responses.GetInventoryItems = { [4] = { name = 'water', count = 2, slot = 4 } }
local list = inv.GetPlayerInventory(1)
check('GetPlayerInventory reads the count and fills the label',
    #list == 1 and list[1].count == 2 and list[1].label == 'Water water')

responses.Items = function() return { label = 'Water', client = { image = 'bottle.png' } } end
local info = inv.GetItemInfo('water')
check('GetItemInfo names the item when V2 leaves name out', info.name == 'water')
check('GetItemInfo uses the item\'s own picture from V2\'s folder',
    info.image == 'nui://codem-inventory-images/images/bottle.png')

files['codem-inventory-images/images/water.png'] = 'x'
files['codem-inventory-images/images/bread.webp'] = 'x'
check('png pictures', inv.GetImagePath('water') == 'nui://codem-inventory-images/images/water.png')
check('webp pictures', inv.GetImagePath('bread') == 'nui://codem-inventory-images/images/bread.webp')
check('no picture', inv.GetImagePath('nope') == 'https://avatars.githubusercontent.com/u/47620135')

calls = {}
inv.OpenShop(2, 'Tools')
call = lastCall('forceOpenInventory')
check('OpenShop force-opens, since V2 documents openInventory on the client only',
    call and call.args[1] == 2 and call.args[2] == 'shop' and call.args[3].type == 'Tools')
check('OpenShop does not call openInventory', lastCall('openInventory') == nil)

inv.RegisterShop('Tools', { { name = 'water', price = 5 } })
call = lastCall('RegisterShop')
check('RegisterShop gives V2 the shop name', call.args[2].name == 'Tools' and #call.args[2].inventory == 1)

inv.ClearStash('ABC123', 'glovebox', 77)
check('the glovebox id is spelled out and by plate', lastCall('ClearInventory').args[1] == 'gloveboxABC123')
inv.GetTrunkItems('ABC123', 77)
check('the trunk id is by plate', lastCall('GetInventoryItems').args[1] == 'trunkABC123')
responses.AddItem = true
check('AddTrunkItems writes by plate', inv.AddTrunkItems('ABC123', { { name = 'water', count = 1 } }, 77) == true)
check('AddTrunkItems targets the trunk', lastCall('AddItem').args[1] == 'trunkABC123')

-- V2 ids a stash's inventory as stash-<name>, so the guard must still see the guarded name.
check('GuardStash is on', inv.GuardStash('crate_1') == true)
local hook = lastCall('registerHook').args[2]
local function open(src, id) return hook({ source = src, inventoryId = id, inventoryType = 'stash' }) end
check('a guarded stash refuses a client open', open(1, 'stash-crate_1') == false)
inv.OpenStash(1, 'crate_1')
check('OpenStash approves one open', open(1, 'stash-crate_1') == true)
check('the approval is used up', open(1, 'stash-crate_1') == false)
check('other stashes are untouched', open(1, 'stash-other') == true)

-- Server, real ox_inventory: the calls stay as they were ---------------------------------------------
resetCalls()
stubWorld({ ox_inventory = true }, nil)
loadAdapter('ox', 'server')
inv = impl

responses.GetItemCount = 1
inv.GetItemCount(1, 'water')
check('calls go to ox_inventory', lastCall('GetItemCount').resource == 'ox_inventory')

responses.Items = function() return { label = 'Water' } end
info = inv.GetItemInfo('water')
check('ox_inventory image path is unchanged', info.image == 'nui://ox_inventory/web/images/water.png')
check('ox_inventory item name is not filled in', info.name == nil)

files['ox_inventory/web/images/water.png'] = 'x'
files['ox_inventory/web/images/bread.webp'] = 'x'
check('ox_inventory picture path is unchanged', inv.GetImagePath('water') == 'nui://ox_inventory/web/images/water.png')
check('ox_inventory does not look for webp', inv.GetImagePath('bread') == 'https://avatars.githubusercontent.com/u/47620135')

responses.GetSlot = { name = 'water', count = 1, slot = 2 }
check('ox_inventory labels are not filled in', inv.GetItemBySlot(1, 2).label == nil)

inv.OpenShop(2, 'Tools')
check('ox_inventory OpenShop is unchanged', lastCall('openInventory').args[3].type == 'Tools')
inv.RegisterShop('Tools', {})
check('ox_inventory RegisterShop is unchanged', lastCall('RegisterShop').args[2].name == nil)

inv.ClearStash('ABC123', 'glovebox', 77)
local target = lastCall('ClearInventory').args[1]
check('ox_inventory vehicle ids keep the entity form',
    type(target) == 'table' and target.id == 'gloveABC123' and target.netid == 77)

inv.GuardStash('crate_1')
hook = lastCall('registerHook').args[2]
check('ox_inventory stash ids are not rewritten', open(1, 'stash-crate_1') == true and open(1, 'crate_1') == false)

-- Client ----------------------------------------------------------------------------------------------
resetCalls()
stubWorld({ ['codem-inventoryv2'] = true, ox_inventory = true, ['qb-inventory'] = true }, nil)
loadAdapter('ox', 'client')
inv = impl

responses.GetItemCount = 2
check('client GetItemCount reads V2', inv.GetItemCount('water') == 2)
check('client calls go to V2 by its own name', lastCall('GetItemCount').resource == 'codem-inventoryv2')
responses.GetPlayerItems = { [4] = { name = 'water', count = 2, slot = 4 } }
responses.Items = function(item) if item then return { label = 'Water' } end end
list = inv.GetPlayerInventory()
check('client inventory reads the count and fills the label', list[1].count == 2 and list[1].label == 'Water')
check('client GetItemInfo names the item', inv.GetItemInfo('water').name == 'water')
files['codem-inventory-images/images/water.png'] = 'x'
check('client pictures come from V2\'s folder', inv.GetImagePath('water') == 'nui://codem-inventory-images/images/water.png')

resetCalls()
stubWorld({ ox_inventory = true }, nil)
loadAdapter('ox', 'client')
inv = impl
files['ox_inventory/web/images/water.png'] = 'x'
check('client ox_inventory picture path is unchanged', inv.GetImagePath('water') == 'nui://ox_inventory/web/images/water.png')
responses.GetPlayerItems = { [1] = { name = 'water', count = 1, slot = 1 } }
responses.Items = function() error('labels must not be looked up on ox_inventory') end
check('client ox_inventory labels are not filled in', inv.GetPlayerInventory()[1].label == nil)

print(('inventory-codem-v2: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
