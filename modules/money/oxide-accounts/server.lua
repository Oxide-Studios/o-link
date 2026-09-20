if not olink._guardImpl('Money', 'oxide-accounts', 'oxide-core') then return end
if GetResourceState('oxide-accounts') == 'missing' then return end

local Oxide = exports['oxide-core']:Core()

---@param src number
---@return number|nil
local function GetCharId(src)
    local player = Oxide.Functions.GetPlayer(src)
    if not player then return nil end
    local character = player.GetCharacter()
    if not character then return nil end
    return character.charId
end

---Normalize account type names across frameworks
---@param accountType string
---@return string
local function NormalizeType(accountType)
    if accountType == 'money' then return 'cash' end
    return accountType
end

---Resolve a stateId or charId to the numeric charId needed by oxide-accounts
---@param identifier string stateId or charId
---@return number|nil
local function ResolveCharId(identifier)
    local num = tonumber(identifier)
    if num then return num end
    local row = MySQL.scalar.await('SELECT char_id FROM characters WHERE state_id = ? AND deleted_at IS NULL', { identifier })
    return tonumber(row)
end

olink._register('money', {
    ---@param src number
    ---@param accountType string 'cash'|'bank'
    ---@param amount number
    ---@return boolean
    Add = function(src, accountType, amount, reason)
        if amount <= 0 then return false end
        local charId = GetCharId(src)
        if not charId then return false end
        local balance = exports['oxide-accounts']:AddMoney(charId, NormalizeType(accountType), amount, reason or 'o-link', reason or 'o-link')
        return balance ~= nil
    end,

    ---@param src number
    ---@param accountType string 'cash'|'bank'
    ---@param amount number
    ---@param reason string|nil
    ---@return boolean
    Remove = function(src, accountType, amount, reason)
        if amount <= 0 then return false end
        local charId = GetCharId(src)
        if not charId then return false end
        local balance = exports['oxide-accounts']:RemoveMoney(charId, NormalizeType(accountType), amount, reason or 'o-link', reason or 'o-link')
        return balance ~= nil
    end,

    ---@param src number
    ---@param accountType string 'cash'|'bank'
    ---@return number
    GetBalance = function(src, accountType)
        local charId = GetCharId(src)
        if not charId then return 0 end
        return exports['oxide-accounts']:GetBalance(charId, NormalizeType(accountType)) or 0
    end,

    ---@param identifier string stateId or charId
    ---@param accountType string 'cash'|'bank'
    ---@param amount number
    ---@param reason string|nil
    ---@return boolean
    AddOffline = function(identifier, accountType, amount, reason)
        if amount <= 0 then return false end
        local charId = ResolveCharId(identifier)
        if not charId then return false end
        local result = exports['oxide-accounts']:AddMoney(charId, NormalizeType(accountType), amount, reason or 'o-link', reason or 'o-link')
        return result ~= nil
    end,

    ---@param identifier string stateId or charId
    ---@param accountType string 'cash'|'bank'
    ---@param amount number
    ---@param reason string|nil
    ---@return boolean
    RemoveOffline = function(identifier, accountType, amount, reason)
        if amount <= 0 then return false end
        local charId = ResolveCharId(identifier)
        if not charId then return false end
        local result = exports['oxide-accounts']:RemoveMoney(charId, NormalizeType(accountType), amount, reason or 'o-link', reason or 'o-link')
        return result ~= nil
    end,

    ---@param identifier string stateId or charId
    ---@param accountType string 'cash'|'bank'
    ---@return number
    GetBalanceOffline = function(identifier, accountType)
        local charId = ResolveCharId(identifier)
        if not charId then return 0 end
        return exports['oxide-accounts']:GetBalance(charId, NormalizeType(accountType)) or 0
    end,
})
