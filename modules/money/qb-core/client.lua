if not olink._guardImpl('Money', 'qb-core', 'qb-core') then return end
if not olink._hasOverride('Money') and GetResourceState('qbx_core') == 'started' then return end

local QBCore = exports['qb-core']:GetCoreObject()

local current = {}

---Normalize account type names across frameworks
---@param accountType string
---@return string
local function NormalizeType(accountType)
    if accountType == 'money' then return 'cash' end
    return accountType
end

---Fire `olink:client:moneyChanged` for every account whose balance moved.
---@param money table|nil PlayerData.money
local function Update(money)
    if type(money) ~= 'table' then return end
    for accountType, balance in pairs(money) do
        balance = tonumber(balance)
        if balance and balance ~= current[accountType] then
            current[accountType] = balance
            TriggerEvent('olink:client:moneyChanged', accountType, balance)
        end
    end
end

olink._register('money', {
    GetResourceName = function() return 'qb-core' end,

    ---@param accountType string 'cash'|'bank'
    ---@return number
    GetBalance = function(accountType)
        local playerData = QBCore.Functions.GetPlayerData()
        local money = playerData and playerData.money
        return type(money) == 'table' and tonumber(money[NormalizeType(accountType)]) or 0
    end,
}, 'qb-core')

-- Current qb-core pushes money edits as a single field; older builds resend the whole PlayerData.
RegisterNetEvent('QBCore:Player:UpdatePlayerDataField', function(key, value)
    if key == 'money' then Update(value) end
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(playerData)
    if type(playerData) == 'table' then Update(playerData.money) end
end)

AddEventHandler('olink:client:playerUnload', function()
    current = {}
end)
