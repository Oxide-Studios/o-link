if not olink._guardImpl('Inventory', 'ps-inventory', 'ps-inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end

local ps = exports['ps-inventory']
local QBCore = GetResourceState('qb-core') == 'started' and exports['qb-core']:GetCoreObject() or nil
local stashes = {}

---@param src number
---@param metadata table
---@return boolean, number|nil
local function findSlotByMetadata(src, metadata)
    if not olink.inventory or not olink.inventory.GetPlayerInventory then return false end
    local inv = olink.inventory.GetPlayerInventory(src) or {}
    for _, v in pairs(inv) do
        if v.metadata and v.metadata == metadata then
            return true, v.slot
        end
    end
    return false
end

olink._register('inventory', {
    -- GetStashItems cannot read contents here, so an empty list proves nothing.
    CanReadStashes = function() return false end,
    ---@param src number
    ---@param item string
    ---@return number
    GetItemCount = function(src, item)
        local itemData = ps:GetItemByName(src, item)
        if not itemData then return 0 end
        return itemData.amount or 0
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    AddItem = function(src, item, count, slot, metadata)
        local success = ps:AddItem(src, item, count, slot, metadata, 'o-link')
        if not success then return false end
        local itemData = QBCore and QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[item]
        if itemData then
            TriggerClientEvent('ps-inventory:client:ItemBox', src, itemData, 'add', count)
        end
        return true
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    RemoveItem = function(src, item, count, slot, metadata)
        if metadata and not slot then
            local found, foundSlot = findSlotByMetadata(src, metadata)
            if found then slot = foundSlot end
        end
        local success = ps:RemoveItem(src, item, count, slot, 'o-link')
        if not success then return false end
        local itemData = QBCore and QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[item]
        if itemData then
            TriggerClientEvent('ps-inventory:client:ItemBox', src, itemData, 'remove', count)
        end
        return true
    end,

    ---@param src number
    ---@param slot number
    ---@return table|nil SlotData
    GetItemBySlot = function(src, slot)
        local data = ps:GetItemBySlot(src, slot)
        if not data then return nil end
        return {
            name     = data.name,
            label    = data.label or data.name,
            count    = data.amount,
            slot     = slot,
            weight   = data.weight,
            metadata = data.info or data.metadata or {},
        }
    end,

    ---@param src number
    ---@return table[] SlotData[]
    GetPlayerInventory = function(src)
        return olink.framework.GetPlayerInventory(src) or {}
    end,

    ---@param src number
    ---@param item string
    ---@param count number|nil
    ---@return boolean
    HasItem = function(src, item, count)
        return ps:HasItem(src, item, count or 1) == true
    end,

    ---@param id string
    ---@param label string
    ---@param slots number
    ---@param weight number
    ---@param owner string|nil
    ---@return boolean
    RegisterStash = function(id, label, slots, weight, owner)
        id = tostring(id)
        if stashes[id] then return true end
        stashes[id] = { label = label, slots = slots, weight = weight, owner = owner }
        return true
    end,

    ---@param src number
    ---@param stashId string
    OpenStash = function(src, stashId)
        stashId = tostring(stashId)
        ps:OpenInventory('stash', stashId, nil, src)
    end,

    ---@param src number
    ---@param targetSrc number
    ---@return boolean
    OpenPlayerInventory = function(src, targetSrc)
        assert(src, 'OpenPlayerInventory: src is required')
        assert(targetSrc, 'OpenPlayerInventory: targetSrc is required')
        ps:OpenInventoryById(src, targetSrc)
        return true
    end,

    ---@param item string
    ---@return table
    GetItemInfo = function(item)
        local data = QBCore and QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[item]
        if not data then return {} end
        return {
            name = data.name,
            label = data.label,
            weight = data.weight,
            description = data.description,
            stack = data.unique == nil and true or (not data.unique),
            image = olink.inventory.GetImagePath and olink.inventory.GetImagePath(item) or nil,
        }
    end,

    ---@param item string
    ---@return string
    GetImagePath = function(item)
        item = olink._stripExt(item)
        local file = LoadResourceFile('ps-inventory', ('html/images/%s.png'):format(item))
        if file then return ('nui://ps-inventory/html/images/%s.png'):format(item) end
        return 'https://avatars.githubusercontent.com/u/47620135'
    end,

    ---@return table All item definitions
    Items = function()
        return (QBCore and QBCore.Shared and QBCore.Shared.Items) or {}
    end,

    ---@param src number
    ---@param item string
    ---@param count number|nil
    ---@return boolean
    CanCarryItem = function(src, item, count)
        return true
    end,

    ---@param oldPlate string
    ---@param newPlate string
    ---@return boolean
    UpdatePlate = function(oldPlate, newPlate)
        MySQL.transaction.await({
            'UPDATE inventory_trunk SET plate = @newplate WHERE plate = @oldplate',
            'UPDATE inventory_glovebox SET plate = @newplate WHERE plate = @oldplate',
        }, { newplate = newPlate, oldplate = oldPlate })
        if GetResourceState('jg-mechanic') == 'started' then
            exports['jg-mechanic']:vehiclePlateUpdated(oldPlate, newPlate)
        end
        return true
    end,

    ---@param src number
    ---@param shopTitle string
    OpenShop = function(src, shopTitle)
        ps:OpenShop(src, shopTitle)
    end,

    ---@param shopTitle string
    ---@param shopInventory table
    ---@param shopCoords table|nil
    ---@param shopGroups table|nil
    ---@return boolean
    RegisterShop = function(shopTitle, shopInventory, shopCoords, shopGroups)
        if not shopTitle or not shopInventory or not shopCoords then return false end

        local repackItems = {}
        for k, v in pairs(shopInventory) do
            repackItems[#repackItems + 1] = {
                name   = v.name,
                price  = v.price or 1000,
                amount = v.amount or v.count or 1,
                slot   = k,
            }
        end

        ps:CreateShop({
            name   = shopTitle,
            label  = shopTitle,
            coords = shopCoords,
            items  = repackItems,
            slots  = #shopInventory,
        })
        return true
    end,

    -- Unsupported features
    GetStashItems = function() return {} end,
    RemoveStashItem = function() return false end,
    ClearStash = function() return false end,
    AddTrunkItems = function() return false end,
})
