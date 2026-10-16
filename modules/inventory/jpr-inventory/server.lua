if not olink._guardImpl('Inventory', 'jpr-inventory', 'jpr-inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end

local jpr = exports['jpr-inventory']
local QBCore = GetResourceState('qb-core') == 'started' and exports['qb-core']:GetCoreObject() or nil
local stashes = {}
local registeredShops = {}

olink._register('inventory', {
    -- GetStashItems cannot read contents here, so an empty list proves nothing.
    CanReadStashes = function() return false end,
    -- No way to stop a client opening a stash by id here.
    GuardStash = function() return false end,
    ---@param src number
    ---@param item string
    ---@return number
    GetItemCount = function(src, item)
        local data = jpr:GetItemByName(src, item)
        if not data then return 0 end
        return data.amount or 0
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    AddItem = function(src, item, count, slot, metadata)
        local success = jpr:AddItem(src, item, count, slot, metadata, 'o-link')
        return success == true
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    RemoveItem = function(src, item, count, slot, metadata)
        local success = jpr:RemoveItem(src, item, count, slot, 'o-link')
        return success == true
    end,

    ---@param src number
    ---@param slot number
    ---@return table|nil SlotData
    GetItemBySlot = function(src, slot)
        local data = jpr:GetItemBySlot(src, slot)
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
        return jpr:HasItem(src, item, count or 1) == true
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
        local tbl = stashes[stashId] or { weight = 1000000, slots = 50 }
        TriggerClientEvent('o-link:inventory:jpr:openStash', src, stashId, { weight = tbl.weight, slots = tbl.slots })
    end,

    ---@param src number
    ---@param targetSrc number
    ---@return boolean
    OpenPlayerInventory = function(src, targetSrc)
        assert(src, 'OpenPlayerInventory: src is required')
        assert(targetSrc, 'OpenPlayerInventory: targetSrc is required')
        local identifier = olink.character.GetIdentifier(targetSrc)
        if not identifier then return false end
        jpr:OpenInventory(src, identifier)
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
        local file = LoadResourceFile('jpr-inventory', ('html/images/%s.png'):format(item))
        if file then return ('nui://jpr-inventory/html/images/%s.png'):format(item) end
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
            'UPDATE gloveboxitems SET plate = @newplate WHERE plate = @oldplate',
            'UPDATE trunkitems SET plate = @newplate WHERE plate = @oldplate',
        }, { newplate = newPlate, oldplate = oldPlate })
        if GetResourceState('jg-mechanic') == 'started' then
            exports['jg-mechanic']:vehiclePlateUpdated(oldPlate, newPlate)
        end
        return true
    end,

    ---@param src number
    ---@param shopTitle string
    OpenShop = function(src, shopTitle)
        jpr:OpenShop(src, shopTitle)
    end,

    ---@param shopTitle string
    ---@param shopInventory table
    ---@param shopCoords table|nil
    ---@param shopGroups table|nil
    ---@return boolean
    RegisterShop = function(shopTitle, shopInventory, shopCoords, shopGroups)
        if not shopTitle or not shopInventory or not shopCoords then return false end
        if registeredShops[shopTitle] then return true end

        local repackItems = {}
        for k, v in pairs(shopInventory) do
            repackItems[#repackItems + 1] = {
                name   = v.name,
                price  = v.price or 1000,
                amount = v.count or v.amount or 1,
                slot   = k,
            }
        end

        jpr:CreateShop({
            name   = shopTitle,
            label  = shopTitle,
            coords = shopCoords,
            items  = repackItems,
            slots  = #shopInventory,
        })
        registeredShops[shopTitle] = true
        return true
    end,

    -- Unsupported features (not exposed by jpr-inventory)
    GetStashItems = function() return {} end,
    RemoveStashItem = function() return false end,
    ClearStash = function() return false end,
    AddTrunkItems = function() return false end,
})
