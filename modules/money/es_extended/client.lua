if not olink._guardImpl('Money', 'es_extended', 'es_extended') then return end

local ESX = exports['es_extended']:getSharedObject()

local current = {}

---o-link calls the cash account 'cash'; ESX calls it 'money'.
---@param accountType string
---@return string
local function ToEsx(accountType)
    if accountType == 'cash' then return 'money' end
    return accountType
end

---@param name string
---@return string
local function FromEsx(name)
    if name == 'money' then return 'cash' end
    return name
end

---@param account table ESX account `{ name, money, label }`
local function Update(account)
    if type(account) ~= 'table' or type(account.name) ~= 'string' then return end
    local accountType = FromEsx(account.name)
    local balance = tonumber(account.money)
    if balance and balance ~= current[accountType] then
        current[accountType] = balance
        TriggerEvent('olink:client:moneyChanged', accountType, balance)
    end
end

olink._register('money', {
    GetResourceName = function() return 'es_extended' end,

    ---@param accountType string 'cash'|'bank'
    ---@return number
    GetBalance = function(accountType)
        local playerData = ESX.GetPlayerData()
        local accounts = playerData and playerData.accounts
        if type(accounts) ~= 'table' then return 0 end
        local name = ToEsx(accountType)
        for _, account in pairs(accounts) do
            if type(account) == 'table' and account.name == name then
                return tonumber(account.money) or 0
            end
        end
        return 0
    end,
}, 'es_extended')

RegisterNetEvent('esx:setAccountMoney', function(account)
    Update(account)
end)

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    if type(xPlayer) ~= 'table' or type(xPlayer.accounts) ~= 'table' then return end
    for _, account in pairs(xPlayer.accounts) do
        Update(account)
    end
end)

AddEventHandler('olink:client:playerUnload', function()
    current = {}
end)
