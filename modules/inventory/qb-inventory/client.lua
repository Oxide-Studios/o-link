if not olink._guardImpl('Inventory', 'qb-inventory', 'qb-inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end
-- Codem Inventory V2 carries this resource name on qb-core; it binds the ox_inventory adapter.
if not olink._hasOverride('Inventory') and GetResourceState('codem-inventoryv2') == 'started' then return end

local qb = exports['qb-inventory']
local QBCore = exports['qb-core']:GetCoreObject()

-- qb-inventory exposes no client GetPlayerItems export; the player's items live on
-- the qb-core client PlayerData.
local function getItems()
    local data = QBCore.Functions.GetPlayerData()
    return data and data.items or {}
end

-- v1 legacy stash open support
RegisterNetEvent('o-link:inventory:qb:openStash', function(id, data)
    if source ~= 65535 then return end
    TriggerEvent('inventory:client:SetCurrentStash', id)
    TriggerServerEvent('inventory:server:OpenInventory', 'stash', id, {
        maxweight = data.weight,
        slots     = data.slots,
    })
end)

olink._register('inventory', {
    ---@return table[] SlotData[]
    GetPlayerInventory = function()
        local items = getItems()
        if not items then return {} end
        local result = {}
        for _, item in pairs(items) do
            if item and item.name then
                result[#result + 1] = {
                    name     = item.name,
                    label    = item.label or item.name,
                    count    = item.amount,
                    slot     = item.slot,
                    weight   = item.weight,
                    metadata = item.info or {},
                }
            end
        end
        return result
    end,

    ---@param item string
    ---@return number
    GetItemCount = function(item)
        local items = getItems()
        if not items then return 0 end
        local total = 0
        for _, slot in pairs(items) do
            if slot and slot.name == item then
                total = total + (slot.amount or 1)
            end
        end
        return total
    end,

    ---@param item string
    ---@param count number|nil
    ---@return boolean
    HasItem = function(item, count)
        return qb:HasItem(item, count or 1) == true
    end,

    ---@param item string
    ---@return table {name, label, weight, description}
    GetItemInfo = function(item)
        local data = QBCore and QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[item]
        if not data then return {} end
        return { name = data.name, label = data.label, weight = data.weight, description = data.description }
    end,

    ---@param item string
    ---@return string
    GetImagePath = function(item)
        item = olink._stripExt(item)
        local file = LoadResourceFile('qb-inventory', ('html/images/%s.png'):format(item))
        if file then return ('nui://qb-inventory/html/images/%s.png'):format(item) end
        return ''
    end,

    ---@return table All item definitions
    Items = function()
        local core = QBCore and QBCore.Shared and QBCore.Shared.Items
        return core or {}
    end,
})
