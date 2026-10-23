-- Underscore prefix keeps this out of the `**/client.lua` adapter glob so it
-- loads once via its explicit fxmanifest entry, after the money and inventory adapters.
--
-- With Config.Cash.mode = 'item', the local player's cash is the cash item count:
-- GetBalance('cash') reads it, the framework's own cash updates are dropped, and
-- olink:client:moneyChanged reports the item count instead.

if not olink.money then return end

local item = olink._cashItem()

-- _registerDefault leaves the namespace's provider and real/fallback status as they are.
olink._registerDefault('money', {
    ---@return string|false
    GetCashItem = function() return item or false end,
})

if not item then return end

local function isCash(accountType)
    return accountType == 'cash' or accountType == 'money'
end

local function itemCount()
    return tonumber(olink.inventory.GetItemCount(item)) or 0
end

local realGetBalance = olink.money.GetBalance
olink._registerDefault('money', {
    GetBalance = function(accountType)
        if isCash(accountType) then return itemCount() end
        return realGetBalance(accountType)
    end,
})

local realChanged = olink._moneyChanged
function olink._moneyChanged(accountType, balance)
    if isCash(accountType) then return end
    realChanged(accountType, balance)
end

local last

local function report()
    if not olink.framework.GetIsPlayerLoaded() then return end
    local balance = itemCount()
    if balance == last then return end
    last = balance
    TriggerEvent('olink:client:moneyChanged', 'cash', balance)
end

-- Cash moved through o-link reports straight away.
RegisterNetEvent('o-link:client:inventory:updateInventory', function(data)
    if type(data) == 'table' and data.item == item then report() end
end)

AddEventHandler('olink:client:playerReady', function()
    last = nil
    report()
end)

AddEventHandler('olink:client:playerUnload', function()
    last = nil
end)

-- Catches what no event reports: items dropped, traded or moved by other scripts.
CreateThread(function()
    while true do
        Wait(1000)
        report()
    end
end)
