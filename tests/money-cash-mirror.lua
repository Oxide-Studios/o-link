-- Cash item mirror (modules/money/_shims_server.lua). With Config.Cash.mirrorItem on, adding or
-- removing cash changes the cash item by the same amount, both or neither; balances stay the
-- framework's; cents and offline cash are refused and logged with the caller. Off, missing or
-- without an item name, cash reaches the framework untouched.
-- Run from the o-link folder: lua tests/money-cash-mirror.lua
local rawprint = print
local passed, failed = 0, 0
local function check(name, ok)
    if ok then passed = passed + 1 else failed = failed + 1; rawprint('FAIL ' .. name) end
end

local printed = {}
print = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end

IsDuplicityVersion = function() return true end
GetResourceState = function(name) return name == 'qb-core' and 'started' or 'missing' end
local invoking
GetInvokingResource = function() return invoking end
local exportsByResource = {}
exports = setmetatable({}, {
    __call = function() end,
    __index = function(_, resource) return exportsByResource[resource] end,
})

local wallet, items, full, failing, warns, errors, alerts, toClient, offlineWrites
local function reset(cash, cashItems)
    wallet = { [1] = { cash = cash, bank = 500 }, [2] = { cash = 0, bank = 0 } }
    items = { [1] = { cash = cashItems }, [2] = {} }
    full, failing, warns, errors, alerts, toClient, offlineWrites = {}, {}, {}, {}, {}, {}, 0
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
                            AddMoney = function(account, amount)
                                if failing.frameworkAdd then return false end
                                if failing.frameworkAddErrors then error('framework exploded') end
                                money[account] = (money[account] or 0) + amount
                                return true
                            end,
                            RemoveMoney = function(account, amount)
                                if failing.frameworkRemove then return false end
                                money[account] = money[account] - amount
                                return true
                            end,
                        },
                    }
                end,
            },
        }
    end,
}

local function Load(cash)
    reset(100, 100)
    printed = {}
    Config = { Debug = false, Overrides = {}, Cash = cash }
    dofile('core/shared.lua')
    dofile('core/defaults_server.lua')
    dofile('modules/money/qb-core/server.lua')
    olink._register('inventory', {
        GetItemCount = function(src, item) return items[src][item] or 0 end,
        AddItem = function(src, item, count)
            if full[src] then return false end
            items[src][item] = (items[src][item] or 0) + count
            return true
        end,
        RemoveItem = function(src, item, count)
            if failing.removeItem or (items[src][item] or 0) < count then return false end
            items[src][item] = items[src][item] - count
            return true
        end,
    }, 'fake')
    olink._register('character', { GetIdentifier = function(src) return ({ 'ABC1', 'DEF2' })[src] end }, 'fake')
    olink._register('framework', {
        GetPlayers = function() return { 1, 2 } end,
        IsAdmin = function(src) return src == 2 end,
    }, 'fake')
    olink._register('notify', { Send = function(src, message) alerts[#alerts + 1] = { src = src, message = message } end }, 'fake')
    olink._register('logger', {
        Warn = function(_, _, message, data) warns[#warns + 1] = { message = message, data = data } end,
        Error = function(_, _, message, data) errors[#errors + 1] = { message = message, data = data } end,
    }, 'fake')
    dofile('modules/inventory/_shims_server.lua')
    dofile('modules/money/_shims_server.lua')
end

local function state() return wallet[1].cash, items[1].cash end

-- mirror on -----------------------------------------------------------------------------------
Load({ mirrorItem = true, item = 'cash' })
local money = olink.money
check('the balance is the framework cash, not the items', money.GetBalance(1, 'cash') == 100)
items[1].cash = 30
check('even when the items differ', money.GetBalance(1, 'cash') == 100)
items[1].cash = 100

check('adding cash adds framework cash and items', money.Add(1, 'cash', 20, 'pay') == true and wallet[1].cash == 120 and items[1].cash == 120)
check('the client hears about the item', #toClient == 1 and toClient[1].data.item == 'cash' and toClient[1].data.count == 20)
check('removing cash takes both', money.Remove(1, 'cash', 50, 'buy') == true and wallet[1].cash == 70 and items[1].cash == 70)
check('ESX money is cash too', money.Add(1, 'money', 5) == true and wallet[1].cash == 75 and items[1].cash == 75)

reset(100, 100)
full[1] = true
check('a full inventory refuses the payment', money.Add(1, 'cash', 20) == false)
local c, i = state()
check('and nothing moves', c == 100 and i == 100)

reset(100, 100)
failing.frameworkAdd = true
check('a refused framework credit refuses the payment', money.Add(1, 'cash', 20) == false)
c, i = state()
check('and the items are taken back', c == 100 and i == 100 and #alerts == 0)

reset(100, 100)
failing.frameworkAddErrors = true
check('a framework credit that errors is refused too', money.Add(1, 'cash', 20) == false and items[1].cash == 100)

reset(100, 100)
failing.frameworkAdd, failing.removeItem = true, true
check('when the items cannot be taken back either', money.Add(1, 'cash', 20) == false and items[1].cash == 120)
check('the extra items are logged', #errors == 1 and errors[1].data.charId == 'ABC1' and errors[1].data.amount == 20)
check('and admins are told', #alerts == 1 and alerts[1].src == 2 and alerts[1].message:find('ABC1 has 20 cash items more', 1, true) ~= nil)

reset(100, 100)
check('removing more cash than the balance is refused', money.Remove(1, 'cash', 150) == false)
c, i = state()
check('with nothing moved', c == 100 and i == 100)

reset(100, 30)
invoking = 'oxide-banking'
check('removing more cash than the items held is refused', money.Remove(1, 'cash', 50) == false)
c, i = state()
check('with nothing moved, and logged with the caller', c == 100 and i == 30 and #warns == 1 and warns[1].data.caller == 'oxide-banking')
invoking = nil

reset(100, 100)
failing.removeItem = true
check('items that cannot be removed refuse the payment', money.Remove(1, 'cash', 40) == false)
c, i = state()
check('and the framework cash is put back', c == 100 and i == 100 and #alerts == 0)

reset(100, 100)
failing.removeItem, failing.frameworkAdd = true, true
check('when the cash cannot be put back either', money.Remove(1, 'cash', 40) == false and wallet[1].cash == 60)
check('the player is flagged as owed', #errors == 1 and errors[1].data.amount == 40 and errors[1].data.charId == 'ABC1')
check('and admins are told', #alerts == 1 and alerts[1].message:find('ABC1 is owed $40 cash', 1, true) ~= nil)

reset(100, 100)
failing.frameworkRemove = true
check('a refused framework debit refuses the payment', money.Remove(1, 'cash', 40) == false)
c, i = state()
check('without touching the items', c == 100 and i == 100)

reset(100, 100)
invoking = 'oxide-shops'
check('cents are refused on add', money.Add(1, 'cash', 2.5) == false)
check('cents are refused on remove', money.Remove(1, 'cash', 0.5) == false)
c, i = state()
check('nothing is rounded or moved', c == 100 and i == 100)
check('both refusals name the caller', #warns == 2 and warns[1].data.caller == 'oxide-shops' and warns[2].data.amount == 0.5)
invoking = nil
check('zero and negative amounts are refused quietly', money.Add(1, 'cash', 0) == false and money.Remove(1, 'cash', -5) == false and #warns == 2)

reset(100, 100)
check('bank is never mirrored', money.Add(1, 'bank', 5) == true and wallet[1].bank == 505 and items[1].cash == 100)

invoking = 'oxide-police'
check('offline cash cannot be paid', money.AddOffline('C1', 'cash', 10) == false and offlineWrites == 0)
check('offline cash cannot be taken', money.RemoveOffline('C1', 'cash', 10) == false and offlineWrites == 0)
check('offline refusals are errors naming the caller', #errors == 2 and errors[1].data.caller == 'oxide-police' and errors[1].data.identifier == 'C1')
invoking = nil
check('offline bank still reaches the framework', money.AddOffline('C1', 'bank', 10) == true and offlineWrites == 1)
check('offline balances are the framework\'s', money.GetBalanceOffline('C1', 'cash') == 42)

-- the refund flag used by the impound adapters ---------------------------------------------------
reset(100, 100)
olink._flagRefundOwed(1, 'ABC1', 'bank', 250, 'impound release failed')
check('a failed refund is logged and shown to admins', #errors == 1 and errors[1].data.account == 'bank'
    and #alerts == 1 and alerts[1].message:find('ABC1 is owed $250 bank', 1, true) ~= nil)

-- mirror off, missing, or misnamed --------------------------------------------------------------
Load({ mirrorItem = false, item = 'cash' })
check('mirror off: cash is the framework alone', olink.money.Add(1, 'cash', 20) == true and wallet[1].cash == 120 and items[1].cash == 100)
check('mirror off: removing leaves the items', olink.money.Remove(1, 'cash', 50) == true and wallet[1].cash == 70 and items[1].cash == 100)
check('mirror off: cents reach the framework as before', olink.money.Add(1, 'cash', 2.5) == true and wallet[1].cash == 72.5 and #warns == 0)
check('mirror off: offline cash reaches the framework', olink.money.AddOffline('C1', 'cash', 10) == true and offlineWrites == 1)

Load(nil)
check('a config.lua without Cash is mirror off, quietly', olink.money.Add(1, 'cash', 20) == true and items[1].cash == 100 and #printed == 0)

Load({ mirrorItem = 'yes', item = 'cash' })
check('only true turns the mirror on', olink.money.Add(1, 'cash', 20) == true and items[1].cash == 100)

Load({ mirrorItem = true, item = '' })
check('mirror on without an item warns once at load', #printed == 1 and printed[1]:find('mirrorItem', 1, true) ~= nil)
check('and stays off', olink.money.Add(1, 'cash', 20) == true and items[1].cash == 100)

print = rawprint
print(('[money-cash-mirror] %d passed, %d failed'):format(passed, failed))
if failed > 0 then error('money-cash-mirror failed') end
