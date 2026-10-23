-- Underscore prefix keeps this out of the `**/server.lua` adapter glob so it
-- loads once via its explicit fxmanifest entry, after the money and inventory adapters.
--
-- With Config.Cash.mode = 'item', cash ('cash', or ESX's 'money') is an inventory item
-- worth $1 each for every resource that moves money through o-link. Other accounts, and
-- cash in account mode, go to the money adapter as before.

if not olink.money then return end

local cfg = Config and Config.Cash
if type(cfg) == 'table' and cfg.mode ~= nil and cfg.mode ~= 'account' and not olink._cashItem() then
    print("^3[o-link]^7 Config.Cash needs mode 'account', or mode 'item' with an item name. Cash is the framework's balance.")
end

local real = {
    Add = olink.money.Add,
    Remove = olink.money.Remove,
    GetBalance = olink.money.GetBalance,
    AddOffline = olink.money.AddOffline,
    RemoveOffline = olink.money.RemoveOffline,
    GetBalanceOffline = olink.money.GetBalanceOffline,
}

local function cashItem(accountType)
    if accountType ~= 'cash' and accountType ~= 'money' then return nil end
    return olink._cashItem()
end

local function refuse(fn, why, data)
    data.caller = GetInvokingResource() or 'o-link'
    olink.logger.Warn('o-link', 'money', ('cash %s refused: %s'):format(fn, why), data)
    return false
end

-- Items are counted in whole units, so an amount with cents is refused, never rounded.
local function itemCount(fn, amount, data)
    local n = tonumber(amount)
    if not n or n <= 0 then return nil end
    if n ~= math.floor(n) or n > 9007199254740991 then
        data.amount = amount
        refuse(fn, 'cash items move in whole dollars', data)
        return nil
    end
    return n
end

-- _registerDefault leaves the namespace's provider and real/fallback status as they are.
olink._registerDefault('money', {
    ---@return string|false
    GetCashItem = function()
        return olink._cashItem() or false
    end,

    Add = function(src, accountType, amount, reason)
        local item = cashItem(accountType)
        if not item then return real.Add(src, accountType, amount, reason) end
        local count = itemCount('Add', amount, { src = src, reason = reason })
        if not count then return false end
        return olink.inventory.AddItem(src, item, count) and true or false
    end,

    Remove = function(src, accountType, amount, reason)
        local item = cashItem(accountType)
        if not item then return real.Remove(src, accountType, amount, reason) end
        local count = itemCount('Remove', amount, { src = src, reason = reason })
        if not count then return false end
        if (tonumber(olink.inventory.GetItemCount(src, item)) or 0) < count then return false end
        return olink.inventory.RemoveItem(src, item, count) and true or false
    end,

    GetBalance = function(src, accountType)
        local item = cashItem(accountType)
        if not item then return real.GetBalance(src, accountType) end
        return tonumber(olink.inventory.GetItemCount(src, item)) or 0
    end,

    AddOffline = function(identifier, accountType, amount, reason)
        if not cashItem(accountType) then return real.AddOffline(identifier, accountType, amount, reason) end
        return refuse('AddOffline', 'an offline player has no loaded inventory', { identifier = identifier, amount = amount, reason = reason })
    end,

    RemoveOffline = function(identifier, accountType, amount, reason)
        if not cashItem(accountType) then return real.RemoveOffline(identifier, accountType, amount, reason) end
        return refuse('RemoveOffline', 'an offline player has no loaded inventory', { identifier = identifier, amount = amount, reason = reason })
    end,

    GetBalanceOffline = function(identifier, accountType)
        if not cashItem(accountType) then return real.GetBalanceOffline(identifier, accountType) end
        return 0
    end,
})
