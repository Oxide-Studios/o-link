-- Cash as an inventory item (modules/money/_shims_server.lua, _shims_client.lua). Item mode: the
-- 'cash' account is the configured item, cents and offline cash are refused and logged with the
-- caller, other accounts reach the framework. Account mode and a missing setting leave the money
-- adapter alone. Client: GetBalance and moneyChanged follow the item, by event and by poll.
-- Run from the o-link folder: lua tests/money-cash-item.lua
local rawprint = print
local passed, failed = 0, 0
local function check(name, ok)
    if ok then passed = passed + 1 else failed = failed + 1; rawprint('FAIL ' .. name) end
end

local printed = {}
print = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end

local isServer = true
IsDuplicityVersion = function() return isServer end
GetResourceState = function(name) return (name == 'qb-core' or name == 'qbx_core') and 'started' or 'missing' end
local invoking
GetInvokingResource = function() return invoking end
local exportsByResource = {}
exports = setmetatable({}, {
    __call = function() end,
    __index = function(_, resource) return exportsByResource[resource] end,
})

-- ============================================================================================
-- Server
-- ============================================================================================

local wallet, items, full, warns, toClient, offlineWrites
local function reset()
    wallet = { [1] = { cash = 100, bank = 500 } }
    items = { [1] = { cash = 30 } }
    full, warns, toClient, offlineWrites, printed = {}, {}, {}, 0, {}
end

TriggerClientEvent = function(name, src, data) toClient[#toClient + 1] = { name = name, src = src, data = data } end
MySQL = {
    update = { await = function() offlineWrites = offlineWrites + 1; return 1 end },
    scalar = { await = function() return 42 end },
}

exportsByResource['qb-core'] = {
    GetCoreObject = function()
        return {
            Functions = {
                GetPlayer = function(src)
                    local money = wallet[src]
                    if not money then return nil end
                    return {
                        PlayerData = { money = money },
                        Functions = {
                            AddMoney = function(account, amount) money[account] = (money[account] or 0) + amount; return true end,
                            RemoveMoney = function(account, amount) money[account] = money[account] - amount; return true end,
                        },
                    }
                end,
            },
        }
    end,
}

local function LoadServer(cash)
    isServer = true
    reset()
    Config = { Debug = false, Overrides = {}, Cash = cash }
    dofile('core/shared.lua')
    dofile('core/defaults_server.lua')
    -- qbx_core reads as started for the client half; this adapter would step aside for it.
    GetResourceState = function(name) return name == 'qb-core' and 'started' or 'missing' end
    dofile('modules/money/qb-core/server.lua')
    olink._register('inventory', {
        GetItemCount = function(src, item) return items[src] and items[src][item] or 0 end,
        AddItem = function(src, item, count)
            if full[src] then return false end
            items[src][item] = (items[src][item] or 0) + count
            return true
        end,
        RemoveItem = function(src, item, count)
            if (items[src][item] or 0) < count then return false end
            items[src][item] = items[src][item] - count
            return true
        end,
    }, 'fake')
    olink._register('logger', {
        Warn = function(_, _, message, data) warns[#warns + 1] = { message = message, data = data } end,
    })
    dofile('modules/inventory/_shims_server.lua')
    dofile('modules/money/_shims_server.lua')
end

-- item mode -----------------------------------------------------------------------------------
LoadServer({ mode = 'item', item = 'cash' })
local money = olink.money
check('GetCashItem names the item', money.GetCashItem() == 'cash')
check('cash reads the item count', money.GetBalance(1, 'cash') == 30 and money.GetBalance(1, 'money') == 30)
check('bank still reads the framework', money.GetBalance(1, 'bank') == 500)

check('adding cash adds items', money.Add(1, 'cash', 20, 'pay') == true and items[1].cash == 50)
check('the framework cash balance is left alone', wallet[1].cash == 100)
check('the client hears about the item move', #toClient == 1 and toClient[1].name == 'o-link:client:inventory:updateInventory'
    and toClient[1].data.item == 'cash' and toClient[1].data.count == 20)
check('removing cash takes items', money.Remove(1, 'cash', 40) == true and items[1].cash == 10)
check('removing more than held is refused', money.Remove(1, 'cash', 11) == false and items[1].cash == 10)
check('ESX money is cash too', money.Add(1, 'money', 5) == true and items[1].cash == 15)

invoking = 'oxide-shops'
check('cents are refused on add', money.Add(1, 'cash', 2.5, 'tip') == false and items[1].cash == 15)
check('the refusal names the caller', #warns == 1 and warns[1].data.caller == 'oxide-shops' and warns[1].data.amount == 2.5)
check('cents are refused on remove', money.Remove(1, 'cash', 0.5) == false and items[1].cash == 15 and #warns == 2)
invoking = nil
check('zero and negative amounts are refused quietly', money.Add(1, 'cash', 0) == false and money.Remove(1, 'cash', -5) == false and #warns == 2)
check('nothing is rounded', items[1].cash == 15)

full[1] = true
check('a full inventory refuses cash', money.Add(1, 'cash', 10) == false and items[1].cash == 15)
full[1] = nil

check('other accounts reach the framework', money.Add(1, 'bank', 5) == true and wallet[1].bank == 505
    and money.Remove(1, 'bank', 10) == true and wallet[1].bank == 495)

warns = {}
check('offline cash cannot be paid', money.AddOffline('C1', 'cash', 10) == false and offlineWrites == 0)
check('offline cash cannot be taken', money.RemoveOffline('C1', 'cash', 10) == false and offlineWrites == 0)
check('offline refusals are logged', #warns == 2 and warns[1].data.identifier == 'C1' and warns[1].data.caller == 'o-link')
check('offline cash reads 0', money.GetBalanceOffline('C1', 'cash') == 0)
check('offline bank still reaches the framework', money.AddOffline('C1', 'bank', 10) == true and offlineWrites == 1
    and money.GetBalanceOffline('C1', 'bank') == 42)

-- account mode ----------------------------------------------------------------------------------
LoadServer({ mode = 'account', item = 'cash' })
money = olink.money
check('account mode has no cash item', money.GetCashItem() == false)
check('account mode reads framework cash', money.GetBalance(1, 'cash') == 100)
check('account mode moves framework cash', money.Add(1, 'cash', 20) == true and wallet[1].cash == 120 and items[1].cash == 30)
check('account mode takes framework cash', money.Remove(1, 'cash', 50) == true and wallet[1].cash == 70)
check('account mode offline cash reaches the framework', money.AddOffline('C1', 'cash', 10) == true and offlineWrites == 1)
check('account mode logs nothing', #warns == 0)

-- missing or mistyped setting -------------------------------------------------------------------
LoadServer(nil)
check('a config.lua without Cash is account mode, quietly', olink.money.GetCashItem() == false and #printed == 0
    and olink.money.GetBalance(1, 'cash') == 100)

LoadServer({ mode = 'items', item = 'cash' })
check('a mistyped mode warns once at load', #printed == 1 and printed[1]:find('Config.Cash', 1, true) ~= nil)
check('a mistyped mode is account mode', olink.money.GetCashItem() == false and olink.money.GetBalance(1, 'cash') == 100)

LoadServer({ mode = 'item', item = '' })
check('item mode without an item warns and is account mode', #printed == 1 and olink.money.GetCashItem() == false)

-- ============================================================================================
-- Client
-- ============================================================================================

local netHandlers, handlers, threads, emitted, playerData, clientItems, loaded
RegisterNetEvent = function(name, fn) if fn then netHandlers[name] = netHandlers[name] or {}; table.insert(netHandlers[name], fn) end end
AddEventHandler = function(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end
TriggerEvent = function(name, ...)
    emitted[#emitted + 1] = { name = name, args = { ... } }
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end
CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
Wait = function(ms) coroutine.yield(ms) end
exportsByResource.qbx_core = { GetPlayerData = function() return playerData end }

local function Net(name, ...) for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end end
local function Tick() for _, t in ipairs(threads) do if coroutine.status(t) ~= 'dead' then assert(coroutine.resume(t)) end end end
local function CashEvents()
    local out = {}
    for _, e in ipairs(emitted) do
        if e.name == 'olink:client:moneyChanged' and e.args[1] == 'cash' then out[#out + 1] = e.args[2] end
    end
    return out
end
local function BankEvents()
    local n = 0
    for _, e in ipairs(emitted) do if e.name == 'olink:client:moneyChanged' and e.args[1] == 'bank' then n = n + 1 end end
    return n
end

local function LoadClient(cash)
    isServer = false
    netHandlers, handlers, threads, emitted, printed = {}, {}, {}, {}, {}
    playerData, clientItems, loaded = {}, { cash = 30 }, true
    GetResourceState = function(name) return name == 'qbx_core' and 'started' or 'missing' end
    Config = { Debug = false, Overrides = {}, Cash = cash }
    dofile('core/shared.lua')
    dofile('core/defaults_client.lua')
    dofile('modules/money/qbx_core/client.lua')
    olink._register('framework', { GetIsPlayerLoaded = function() return loaded end }, 'fake')
    olink._register('inventory', { GetItemCount = function(item) return clientItems[item] or 0 end }, 'fake')
    dofile('modules/inventory/_shims_client.lua')
    dofile('modules/money/_shims_client.lua')
    -- Threads start on the next tick and run to their first Wait.
    Tick()
end

-- item mode -----------------------------------------------------------------------------------
LoadClient({ mode = 'item', item = 'cash' })
check('client GetCashItem names the item', olink.money.GetCashItem() == 'cash')
playerData = { money = { cash = 100, bank = 500 } }
check('client cash reads the item count', olink.money.GetBalance('cash') == 30 and olink.money.GetBalance('money') == 30)
check('client bank reads the framework', olink.money.GetBalance('bank') == 500)

Net('QBCore:Player:SetPlayerData', { money = { cash = 100, bank = 500 } })
check('the framework cash update is dropped', #CashEvents() == 0)
check('the framework bank update still reports', BankEvents() == 1)

TriggerEvent('olink:client:playerReady')
check('a loaded character reports its cash items', #CashEvents() == 1 and CashEvents()[1] == 30)

clientItems.cash = 45
Net('o-link:client:inventory:updateInventory', { action = 'add', item = 'cash', count = 15 })
check('an o-link item move reports at once', #CashEvents() == 2 and CashEvents()[2] == 45)
Net('o-link:client:inventory:updateInventory', { action = 'add', item = 'bread', count = 1 })
check('other items are ignored', #CashEvents() == 2)

clientItems.cash = 12
check('the poll waits for its second', #CashEvents() == 2)
Tick()
check('a change no event reported shows up on the poll', #CashEvents() == 3 and CashEvents()[3] == 12)
Tick()
check('an unchanged count is not reported again', #CashEvents() == 3)

TriggerEvent('olink:client:playerUnload')
loaded = false
clientItems.cash = 99
Tick()
check('nothing is reported while no character is loaded', #CashEvents() == 3)
loaded = true
TriggerEvent('olink:client:playerReady')
check('the next character reports its cash straight away', #CashEvents() == 4 and CashEvents()[4] == 99)

-- account mode ----------------------------------------------------------------------------------
LoadClient({ mode = 'account', item = 'cash' })
playerData = { money = { cash = 100, bank = 500 } }
check('client account mode has no cash item', olink.money.GetCashItem() == false)
check('client account mode reads framework cash', olink.money.GetBalance('cash') == 100)
Net('QBCore:Player:SetPlayerData', { money = { cash = 100, bank = 500 } })
check('client account mode reports framework cash', #CashEvents() == 1 and CashEvents()[1] == 100)
check('client account mode starts no poll', #threads == 0)

LoadClient(nil)
playerData = { money = { cash = 7, bank = 1 } }
check('no Cash setting on the client is account mode', olink.money.GetBalance('cash') == 7 and #threads == 0)

print = rawprint
print(('[money-cash-item] %d passed, %d failed'):format(passed, failed))
if failed > 0 then error('money-cash-item failed') end
