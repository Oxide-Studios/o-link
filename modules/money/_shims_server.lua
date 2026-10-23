-- Underscore prefix keeps this out of the `**/server.lua` adapter glob so it
-- loads once via its explicit fxmanifest entry, after the money and inventory adapters.
--
-- Cash item mirror (Config.Cash.mirrorItem). Framework cash stays the money; for inventories
-- with a cash item they do not keep in step themselves, adding or removing 'cash' (or ESX's
-- 'money') through o-link changes the item by the same amount. Both change or neither does.
-- Balances are never read from the item.

local function alertAdmins(message)
    for _, playerId in ipairs(olink.framework.GetPlayers() or {}) do
        if olink.framework.IsAdmin(playerId) then
            olink.notify.Send(playerId, message, 'error')
        end
    end
end

---Report money taken from a player that could not be given back: an error log, and an alert
---to every admin online so it can be paid back by hand.
---@param src number
---@param charId string|nil
---@param account string
---@param amount number
---@param reason string
function olink._flagRefundOwed(src, charId, account, amount, reason)
    olink.logger.Error('o-link', 'money', 'refund failed, the player is owed this amount', {
        src = src, charId = charId, account = account, amount = amount, reason = reason,
    })
    alertAdmins(('[o-link] Refund failed: %s is owed $%s %s (%s).'):format(tostring(charId or src), amount, account, reason))
end

if not olink.money then return end

local cfg = Config and Config.Cash
if type(cfg) == 'table' and cfg.mirrorItem == true and (type(cfg.item) ~= 'string' or cfg.item == '') then
    print('^3[o-link]^7 Config.Cash.mirrorItem is on but no item is named, so the cash item mirror is off.')
end

---The cash item to keep in step, or nil when the mirror is off.
local function mirroredItem(accountType)
    if accountType ~= 'cash' and accountType ~= 'money' then return nil end
    local c = Config and Config.Cash
    if type(c) ~= 'table' or c.mirrorItem ~= true then return nil end
    if type(c.item) ~= 'string' or c.item == '' then return nil end
    return c.item
end

local real = {
    Add = olink.money.Add,
    Remove = olink.money.Remove,
    GetBalance = olink.money.GetBalance,
    AddOffline = olink.money.AddOffline,
    RemoveOffline = olink.money.RemoveOffline,
}

local function refuse(level, fn, why, data)
    data.caller = GetInvokingResource() or 'o-link'
    olink.logger[level]('o-link', 'money', ('cash %s refused: %s'):format(fn, why), data)
    return false
end

-- Items are counted in whole units, so while the mirror is on an amount with cents is
-- refused, never rounded.
local function wholeAmount(fn, amount, data)
    local n = tonumber(amount)
    if not n or n <= 0 then return nil end
    if n ~= math.floor(n) or n > 9007199254740991 then
        data.amount = amount
        refuse('Warn', fn, 'the cash item mirror moves whole dollars only', data)
        return nil
    end
    return n
end

local function tryCall(fn, ...)
    local ok, result = pcall(fn, ...)
    return ok and result and true or false
end

-- _registerDefault leaves the namespace's provider and real/fallback status as they are.
olink._registerDefault('money', {
    -- The item goes in first: a full inventory then fails with nothing to undo.
    Add = function(src, accountType, amount, reason)
        local item = mirroredItem(accountType)
        if not item then return real.Add(src, accountType, amount, reason) end
        local n = wholeAmount('Add', amount, { src = src, reason = reason })
        if not n then return false end

        if not olink.inventory.AddItem(src, item, n) then return false end
        if tryCall(real.Add, src, accountType, n, reason) then return true end

        if not olink.inventory.RemoveItem(src, item, n) then
            local charId = olink.character.GetIdentifier(src)
            olink.logger.Error('o-link', 'money', 'cash item mirror out of step: extra cash items', {
                src = src, charId = charId, item = item, amount = n, reason = reason,
            })
            alertAdmins(('[o-link] Cash out of step: %s has %s %s items more than their cash (%s).')
                :format(tostring(charId or src), n, item, tostring(reason)))
        end
        return false
    end,

    -- Framework cash leaves first: if the item cannot follow, the cash is put back.
    Remove = function(src, accountType, amount, reason)
        local item = mirroredItem(accountType)
        if not item then return real.Remove(src, accountType, amount, reason) end
        local n = wholeAmount('Remove', amount, { src = src, reason = reason })
        if not n then return false end

        if (tonumber(real.GetBalance(src, accountType)) or 0) < n then return false end
        if (tonumber(olink.inventory.GetItemCount(src, item)) or 0) < n then
            return refuse('Warn', 'Remove', 'the player holds fewer cash items than cash', { src = src, amount = n, reason = reason })
        end

        if not tryCall(real.Remove, src, accountType, n, reason) then return false end
        if olink.inventory.RemoveItem(src, item, n) then return true end

        if not tryCall(real.Add, src, accountType, n, 'cash item mirror refund') then
            olink._flagRefundOwed(src, olink.character.GetIdentifier(src), 'cash', n, 'the cash item could not be removed')
        end
        return false
    end,

    -- An offline player's inventory is not loaded, so the item cannot follow.
    AddOffline = function(identifier, accountType, amount, reason)
        if not mirroredItem(accountType) then return real.AddOffline(identifier, accountType, amount, reason) end
        return refuse('Error', 'AddOffline', 'an offline player\'s cash item cannot be changed', { identifier = identifier, amount = amount, reason = reason })
    end,

    RemoveOffline = function(identifier, accountType, amount, reason)
        if not mirroredItem(accountType) then return real.RemoveOffline(identifier, accountType, amount, reason) end
        return refuse('Error', 'RemoveOffline', 'an offline player\'s cash item cannot be changed', { identifier = identifier, amount = amount, reason = reason })
    end,
})
