if not olink._guardImpl('Inventory', 'ak47_qb_inventory', 'ak47_qb_inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('qb-inventory') == 'started' then return end

local ak47 = exports['ak47_qb_inventory']
local QBCore = exports['qb-core']:GetCoreObject()

local stashes = {}
local shopData = {}

olink._register('inventory', {
    -- GetStashItems reads real contents.
    CanReadStashes = function() return true end,
    ---@param src number
    ---@param item string
    ---@return number
    GetItemCount = function(src, item)
        local amount = ak47:GetAmount(src, item)
        return tonumber(amount) or 0
    end,

    ---@param src number
    ---@param item string
    ---@param count number|nil
    ---@return boolean
    HasItem = function(src, item, count)
        local amount = tonumber(ak47:GetAmount(src, item)) or 0
        return amount >= (count or 1)
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    AddItem = function(src, item, count, slot, metadata)
        if not ak47:CanAddItem(src, item, count) then return false end
        local success = ak47:AddItem(src, item, count, slot, metadata)
        if not success then return false end
        local itemData = QBCore.Shared.Items[item]
        if itemData then
            TriggerClientEvent('qb-inventory:client:ItemBox', src, itemData, 'add', count)
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
        local success = ak47:RemoveItem(src, item, count, slot, false)
        if not success then return false end
        local itemData = QBCore.Shared.Items[item]
        if itemData then
            TriggerClientEvent('qb-inventory:client:ItemBox', src, itemData, 'remove', count)
        end
        return true
    end,

    ---@param src number
    ---@param slot number
    ---@return table|nil SlotData
    GetItemBySlot = function(src, slot)
        local data = ak47:GetSlot(src, slot)
        if not data then return nil end
        return {
            name     = data.name,
            label    = data.label or data.name,
            count    = data.amount,
            slot     = data.slot,
            weight   = data.weight,
            metadata = data.info or {},
        }
    end,

    ---@param src number
    ---@return table[] SlotData[]
    GetPlayerInventory = function(src)
        local items = ak47:GetInventoryItems(src)
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

    ---@param src number
    ---@param targetSrc number
    ---@return boolean
    OpenPlayerInventory = function(src, targetSrc)
        assert(src, 'OpenPlayerInventory: src is required')
        assert(targetSrc, 'OpenPlayerInventory: targetSrc is required')
        ak47:OpenInventory(src, targetSrc)
        return true
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
        if not ak47:GetInventory(id) then
            ak47:CreateInventory(id, { label = label, slots = slots, maxweight = weight })
        end
        return true
    end,

    ---@param src number
    ---@param stashId string
    OpenStash = function(src, stashId)
        ak47:OpenInventory(src, tostring(stashId))
    end,

    ---@param item string
    ---@return table {name, label, weight, description, image, stack}
    GetItemInfo = function(item)
        local data = QBCore.Shared.Items[item]
        if not data then return {} end
        return {
            name = data.name,
            label = data.label,
            weight = data.weight,
            description = data.description,
            stack = data.unique == nil and true or (not data.unique),
            image = olink.inventory.GetImagePath and olink.inventory.GetImagePath(data.image or data.name),
        }
    end,

    ---@param src number
    ---@param item string
    ---@param slot number
    ---@param metadata table
    ---@return boolean
    SetMetadata = function(src, item, slot, metadata)
        -- ak47's SetItemInfo replaces info wholesale; merge to preserve fields the caller didn't pass.
        local existing = ak47:GetSlot(src, slot)
        local merged = {}
        if existing and type(existing.info) == 'table' then
            for k, v in pairs(existing.info) do merged[k] = v end
        end
        if type(metadata) == 'table' then
            for k, v in pairs(metadata) do merged[k] = v end
        end
        ak47:SetItemInfo(src, slot, merged)
        return true
    end,

    ---@param item string
    ---@return string
    GetImagePath = function(item)
        item = olink._stripExt(item)
        local file = LoadResourceFile('ak47_qb_inventory', ('html/images/%s.png'):format(item))
        if file then return ('nui://ak47_qb_inventory/html/images/%s.png'):format(item) end
        return 'https://avatars.githubusercontent.com/u/47620135'
    end,

    ---@return table All item definitions
    Items = function()
        return QBCore.Shared.Items or {}
    end,

    ---@param src number
    ---@param item string
    ---@param count number|nil
    ---@return boolean
    CanCarryItem = function(src, item, count)
        return ak47:CanAddItem(src, item, count or 1) == true
    end,

    ---@param id string
    ---@return table[]
    GetStashItems = function(id)
        local inv = ak47:GetInventory(tostring(id))
        return (inv and inv.items) or {}
    end,

    ---@param id string
    ---@param item string
    ---@param count number
    ---@return boolean
    RemoveStashItem = function(id, item, count)
        local success = ak47:RemoveItem(tostring(id), item, count, nil, false)
        return success == true
    end,

    ---@param id string
    ---@param item string
    ---@param count number
    ---@param metadata table|nil
    ---@return boolean
    AddStashItem = function(id, item, count, metadata)
        local success = ak47:AddItem(tostring(id), item, count or 1, nil, metadata)
        return success == true
    end,

    ---@param id string
    ---@param items table[] { item, count, metadata }
    ---@return boolean
    AddStashItems = function(id, items)
        if type(items) ~= 'table' then return false end
        local success = false
        for _, item in pairs(items) do
            success = ak47:AddItem(id, item.item, item.count or item.amount, nil,
                item.metadata or item.info)
        end
        return success == true
    end,

    ---@param id string
    ---@param _type string|nil 'stash', 'trunk', 'glovebox'
    ---@return boolean
    ClearStash = function(id, _type)
        if type(id) ~= 'string' then return false end
        if stashes[id] then stashes[id] = nil end
        if _type == 'trunk' then
            id = 'trunk-' .. id
        elseif _type == 'glovebox' then
            id = 'glovebox-' .. id
        end
        if not ak47:GetInventory(id) then return true end
        ak47:ClearInventory(id)
        return true
    end,

    ---@param identifier string plate or trunk identifier
    ---@param items table[]
    ---@return boolean

    ---@param identifier string plate
    ---@return table[] items
    GetTrunkItems = function(identifier)
        local ok, inv = pcall(function()
            return ak47:GetInventory('trunk-' .. tostring(identifier))
        end)
        if not ok or type(inv) ~= 'table' then return nil end
        return inv.items or inv
    end,

    ---@param identifier string plate
    ---@param items table[] { name|item, count|amount, metadata|info }
    ---@return boolean
    AddTrunkItems = function(identifier, items)
        if type(items) ~= 'table' then return false end
        local trunkId = 'trunk-' .. identifier
        if not ak47:GetInventory(trunkId) then
            ak47:CreateInventory(trunkId, { label = trunkId, slots = 15, maxweight = 10000 })
        end
        Wait(100)
        for i = 1, #items do
            ak47:AddItem(trunkId, items[i].name or items[i].item, items[i].amount or items[i].count,
                items[i].slot, items[i].info or items[i].metadata or {})
        end
        return true
    end,

    ---@param oldPlate string
    ---@param newPlate string
    ---@return boolean
    UpdatePlate = function(oldPlate, newPlate)
        local ok = pcall(function() ak47:OnChangeVehiclePlate(oldPlate, newPlate) end)
        if ok then
            if GetResourceState('jg-mechanic') == 'started' then
                exports['jg-mechanic']:vehiclePlateUpdated(oldPlate, newPlate)
            end
            return true
        end

        local glovebox = ak47:GetInventory('glovebox-' .. oldPlate) or { slots = 5, maxweight = 10000, items = {} }
        local trunk = ak47:GetInventory('trunk-' .. oldPlate) or { slots = 5, maxweight = 10000, items = {} }
        ak47:ClearInventory('glovebox-' .. oldPlate)
        ak47:ClearInventory('trunk-' .. oldPlate)
        ak47:CreateInventory('glovebox-' .. newPlate, {
            label = 'glovebox-' .. newPlate,
            slots = glovebox.slots,
            maxweight = glovebox.maxweight,
        })
        ak47:CreateInventory('trunk-' .. newPlate, {
            label = 'trunk-' .. newPlate,
            slots = trunk.slots,
            maxweight = trunk.maxweight,
        })
        for _, item in pairs(glovebox.items or {}) do
            ak47:AddItem('glovebox-' .. newPlate, item.name, item.amount, item.slot, item.info)
        end
        for _, item in pairs(trunk.items or {}) do
            ak47:AddItem('trunk-' .. newPlate, item.name, item.amount, item.slot, item.info)
        end
        if GetResourceState('jg-mechanic') == 'started' then
            exports['jg-mechanic']:vehiclePlateUpdated(oldPlate, newPlate)
        end
        return true
    end,

    ---@param src number
    ---@param shopTitle string
    OpenShop = function(src, shopTitle)
        local ok = pcall(function() ak47:OpenShop(src, shopTitle) end)
        if ok then return end

        local data = shopData[shopTitle]
        if not data then return end
        TriggerClientEvent('inventory:client:OpenInventory', src, 'shop', shopTitle, data)
    end,

    ---@param shopTitle string
    ---@param shopInventory table
    ---@param shopCoords table|nil
    ---@param shopGroups table|nil
    ---@return boolean
    RegisterShop = function(shopTitle, shopInventory, shopCoords, shopGroups)
        if not shopTitle or not shopInventory then return false end
        if shopData[shopTitle] then return true end

        local repackedItems = {}
        for _, v in pairs(shopInventory) do
            repackedItems[#repackedItems + 1] = {
                name   = v.name,
                price  = v.price,
                amount = v.count or v.amount or 1000,
                info   = v.metadata or v.info or {},
                type   = 'item',
            }
        end

        shopData[shopTitle] = { inventory = repackedItems, coords = shopCoords, groups = shopGroups,
            label = shopTitle, items = repackedItems, slots = #repackedItems }

        local ok = pcall(function()
            ak47:CreateShop({ name = shopTitle, label = shopTitle, coords = shopCoords, items = repackedItems })
        end)
        if not ok then
            -- Fork doesn't expose CreateShop; cache shop data so OpenShop can fall back to legacy event
            return true
        end
        return true
    end,
})
