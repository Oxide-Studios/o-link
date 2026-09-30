if not olink._guardImpl('Money', 'es_extended', 'es_extended') then return end

local ESX = exports['es_extended']:getSharedObject()

---@param src number
---@return table|nil xPlayer
local function GetPlayer(src)
    return ESX.GetPlayerFromId(src)
end

---Normalize account type: o-link uses 'cash', ESX uses 'money'
---@param accountType string
---@return string
local function NormalizeType(accountType)
    if accountType == 'cash' then return 'money' end
    return accountType
end

olink._register('money', {
    ---@param src number
    ---@param accountType string 'cash'|'bank'
    ---@param amount number
    ---@return boolean
    Add = function(src, accountType, amount, reason)
        if amount <= 0 then return false end
        local xPlayer = GetPlayer(src)
        if not xPlayer then return false end
        local esxType = NormalizeType(accountType)
        if not xPlayer.getAccount(esxType) then return false end
        xPlayer.addAccountMoney(esxType, amount, reason)
        return true
    end,

    ---@param src number
    ---@param accountType string 'cash'|'bank'
    ---@param amount number
    ---@param reason string|nil
    ---@return boolean
    Remove = function(src, accountType, amount, reason)
        if amount <= 0 then return false end
        local xPlayer = GetPlayer(src)
        if not xPlayer then return false end
        local esxType = NormalizeType(accountType)
        local account = xPlayer.getAccount(esxType)
        if not account or account.money < amount then return false end
        xPlayer.removeAccountMoney(esxType, amount, reason)
        return true
    end,

    ---@param src number
    ---@param accountType string 'cash'|'bank'
    ---@return number
    GetBalance = function(src, accountType)
        local xPlayer = GetPlayer(src)
        if not xPlayer then return 0 end
        local account = xPlayer.getAccount(NormalizeType(accountType))
        if not account then return 0 end
        return account.money or 0
    end,

    ---@param identifier string ESX identifier
    ---@param accountType string 'cash'|'bank'
    ---@param amount number
    ---@return boolean
    -- ESX stores users.accounts as a dict { [name] = money }, not an array.
    -- One UPDATE, so two credits at the same moment cannot overwrite each other.
    AddOffline = function(identifier, accountType, amount)
        if amount <= 0 then return false end
        local key = '$.' .. NormalizeType(accountType)
        local affected = MySQL.update.await(
            'UPDATE users SET accounts = JSON_SET(accounts, ?, COALESCE(JSON_EXTRACT(accounts, ?), 0) + ?) WHERE identifier = ? AND accounts IS NOT NULL',
            { key, key, amount, identifier })
        return affected ~= nil and affected > 0
    end,

    ---@param identifier string ESX identifier
    ---@param accountType string 'cash'|'bank'
    ---@param amount number
    ---@return boolean
    RemoveOffline = function(identifier, accountType, amount)
        if amount <= 0 then return false end
        local esxType = NormalizeType(accountType)
        local row = MySQL.single.await('SELECT accounts FROM users WHERE identifier = ?', { identifier })
        if not row or not row.accounts then return false end
        local accounts = json.decode(row.accounts) or {}
        local current = accounts[esxType] or 0
        if current < amount then return false end
        accounts[esxType] = current - amount
        MySQL.update.await('UPDATE users SET accounts = ? WHERE identifier = ?', { json.encode(accounts), identifier })
        return true
    end,

    ---@param identifier string ESX identifier
    ---@param accountType string 'cash'|'bank'
    ---@return number
    GetBalanceOffline = function(identifier, accountType)
        local esxType = NormalizeType(accountType)
        local row = MySQL.single.await('SELECT accounts FROM users WHERE identifier = ?', { identifier })
        if not row or not row.accounts then return 0 end
        local accounts = json.decode(row.accounts) or {}
        return accounts[esxType] or 0
    end,
})
