if not olink._guardImpl('Money', 'qbx_core', 'qbx_core') then return end

local current = {}

---Normalize account type names across frameworks
---@param accountType string
---@return string
local function NormalizeType(accountType)
    if accountType == 'money' then return 'cash' end
    return accountType
end

olink._register('money', {
    GetResourceName = function() return 'qbx_core' end,

    ---@param accountType string 'cash'|'bank'
    ---@return number
    GetBalance = function(accountType)
        -- PlayerData is an empty table until a character loads.
        local playerData = exports.qbx_core:GetPlayerData()
        local money = playerData and playerData.money
        return type(money) == 'table' and tonumber(money[NormalizeType(accountType)]) or 0
    end,
}, 'qbx_core')

-- qbx_core resends the whole PlayerData on every update, money included.
RegisterNetEvent('QBCore:Player:SetPlayerData', function(playerData)
    local money = type(playerData) == 'table' and playerData.money
    if type(money) ~= 'table' then return end
    for accountType, balance in pairs(money) do
        balance = tonumber(balance)
        if balance and balance ~= current[accountType] then
            current[accountType] = balance
            olink._moneyChanged(accountType, balance)
        end
    end
end)

AddEventHandler('olink:client:playerUnload', function()
    current = {}
end)
