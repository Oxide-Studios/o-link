if not olink._guardImpl('Money', 'oxide-accounts', 'oxide-core') then return end
if GetResourceState('oxide-accounts') == 'missing' then return end

-- oxide-accounts publishes each synced balance on its own `oxide:<account>` player bag.
local ACCOUNTS = { 'cash', 'bank' }
local current = {}

---Normalize account type names across frameworks
---@param accountType string
---@return string
local function NormalizeType(accountType)
    if accountType == 'money' then return 'cash' end
    return accountType
end

olink._register('money', {
    GetResourceName = function() return 'oxide-accounts' end,

    ---@param accountType string 'cash'|'bank'
    ---@return number
    GetBalance = function(accountType)
        if type(accountType) ~= 'string' then return 0 end
        return tonumber(LocalPlayer.state['oxide:' .. NormalizeType(accountType)]) or 0
    end,
}, 'oxide-accounts')

for _, accountType in ipairs(ACCOUNTS) do
    AddStateBagChangeHandler('oxide:' .. accountType, ('player:%s'):format(cache.serverId), function(_, _, value)
        local balance = tonumber(value)
        if balance == nil then
            current[accountType] = nil
            return
        end
        if balance == current[accountType] then return end
        current[accountType] = balance
        olink._moneyChanged(accountType, balance)
    end)
end
