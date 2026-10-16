if not olink._guardImpl('Inventory', 'qb-inventory', 'qb-inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end

local qbInventory = exports['qb-inventory']
local QBCore = exports['qb-core']:GetCoreObject()

local stashes = {}
local shopData = {}

---Detect qb-inventory v2+ by checking the version metadata
---@return boolean
local function isV2()
    local v = GetResourceMetadata('qb-inventory', 'version', 0)
    return v ~= nil and tonumber(string.sub(v, 1, 1)) >= 2
end

local v2 = isV2()

olink._register('inventory', {
    -- GetStashItems reads real contents on v2 only.
    CanReadStashes = function() return v2 end,
    ---@param src number
    ---@param item string
    ---@return number
    GetItemCount = function(src, item)
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return 0 end
        local items = player.PlayerData.items
        if not items then return 0 end
        local total = 0
        for _, v in pairs(items) do
            if v and v.name == item then
                total = total + (v.amount or 0)
            end
        end
        return total
    end,

    ---@param src number
    ---@param item string
    ---@param count number|nil
    ---@return boolean
    HasItem = function(src, item, count)
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return false end
        local items = player.PlayerData.items
        if not items then return false end
        local total = 0
        for _, v in pairs(items) do
            if v and v.name == item then
                total = total + (v.amount or 0)
            end
        end
        return total >= (count or 1)
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    AddItem = function(src, item, count, slot, metadata)
        if v2 and not qbInventory:CanAddItem(src, item, count) then return false end
        local success = qbInventory:AddItem(src, item, count, slot, metadata, 'o-link')
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
        local success = qbInventory:RemoveItem(src, item, count, slot, 'o-link')
        if not success then return false end
        local itemData = QBCore.Shared.Items[item]
        if itemData then
            TriggerClientEvent('qb-inventory:client:ItemBox', src, itemData, 'remove', count)
        end
        return true
    end,

    ---@param src number
    ---@param slot number
    ---@return table|nil SlotData {name, label, count, slot, weight, metadata}
    GetItemBySlot = function(src, slot)
        local data = qbInventory:GetItemBySlot(src, slot)
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
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return {} end
        local items = player.PlayerData.items
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
        qbInventory:OpenInventory(src, targetSrc)
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
        if v2 then
            if not qbInventory:GetInventory(id) then
                qbInventory:CreateInventory(id, { label = label, slots = slots, maxweight = weight })
            end
        end
        return true
    end,

    ---@param src number
    ---@param stashId string
    ---@return nil
    OpenStash = function(src, stashId)
        stashId = tostring(stashId)
        if v2 then
            qbInventory:OpenInventory(src, stashId)
        else
            local tbl = stashes[stashId] or {}
            TriggerClientEvent('o-link:inventory:qb:openStash', src, stashId, {
                weight = tbl.weight or 5000,
                slots  = tbl.slots or 20,
            })
        end
    end,

    ---@param id string
    ---@param items table[] { item, count, metadata }
    ---@return boolean
    AddStashItems = function(id, items)
        if type(items) ~= 'table' then return false end
        if not v2 then
            print('[o-link] qb-inventory v1 does not support AddStashItems')
            return false
        end
        local success = false
        for _, item in pairs(items) do
            success = qbInventory:AddItem(id, item.item, item.count or item.amount, nil,
                item.metadata or item.info, 'o-link: adding items to stash')
        end
        return success == true
    end,

    ---@param id string
    ---@param item string
    ---@param count number
    ---@param metadata table|nil
    ---@return boolean
    AddStashItem = function(id, item, count, metadata)
        if not v2 then
            print('[o-link] qb-inventory v1 does not support AddStashItem')
            return false
        end
        local success = qbInventory:AddItem(tostring(id), item, count or 1, nil, metadata,
            'o-link: adding item to stash')
        return success == true
    end,

    ---@param identifier string plate or trunk identifier
    ---@param items table[]
    ---@return boolean

    ---@param identifier string plate
    ---@return table[] items
    GetTrunkItems = function(identifier)
        local ok, inv = pcall(function()
            return qbInventory:GetInventory('trunk-' .. tostring(identifier))
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
        if v2 then
            if not qbInventory:GetInventory(trunkId) then
                qbInventory:CreateInventory(trunkId, { label = trunkId, slots = 15, maxweight = 10000 })
            end
            Wait(100)
            for i = 1, #items do
                qbInventory:AddItem(trunkId, items[i].name or items[i].item, items[i].amount or items[i].count,
                    items[i].slot, items[i].info or items[i].metadata or {}, 'o-link: adding items to trunk')
            end
            return true
        end
        TriggerEvent('inventory:server:addTrunkItems', trunkId, items)
        return true
    end,

    ---@param id string
    ---@param _type string|nil 'stash', 'trunk', 'glovebox'
    ---@return boolean
    ClearStash = function(id, _type)
        if type(id) ~= 'string' then return false end
        if stashes[id] then stashes[id] = nil end
        if not v2 then
            print('[o-link] qb-inventory v1 does not support ClearStash')
            return false
        end
        if _type == 'trunk' then
            id = 'trunk-' .. id
        elseif _type == 'glovebox' then
            id = 'glovebox-' .. id
        end
        if not qbInventory:GetInventory(id) then return true end
        qbInventory:ClearStash(id)
        return true
    end,

    ---@param oldPlate string
    ---@param newPlate string
    ---@return boolean
    UpdatePlate = function(oldPlate, newPlate)
        if v2 then
            local glovebox = qbInventory:GetInventory('glovebox-' .. oldPlate) or { slots = 5, maxweight = 10000, items = {} }
            local trunk = qbInventory:GetInventory('trunk-' .. oldPlate) or { slots = 5, maxweight = 10000, items = {} }
            qbInventory:ClearStash('glovebox-' .. oldPlate)
            qbInventory:ClearStash('trunk-' .. oldPlate)
            qbInventory:CreateInventory('glovebox-' .. newPlate, {
                label = 'glovebox-' .. newPlate,
                slots = glovebox.slots,
                maxweight = glovebox.maxweight,
            })
            qbInventory:SetInventory('glovebox-' .. newPlate, glovebox.items, 'o-link: plate migration')
            qbInventory:CreateInventory('trunk-' .. newPlate, {
                label = 'trunk-' .. newPlate,
                slots = trunk.slots,
                maxweight = trunk.maxweight,
            })
            qbInventory:SetInventory('trunk-' .. newPlate, trunk.items, 'o-link: plate migration')
        else
            MySQL.transaction.await({
                'UPDATE inventory_glovebox SET plate = @newplate WHERE plate = @oldplate',
                'UPDATE inventory_trunk SET plate = @newplate WHERE plate = @oldplate',
            }, { newplate = newPlate, oldplate = oldPlate })
        end
        if GetResourceState('jg-mechanic') == 'started' then
            exports['jg-mechanic']:vehiclePlateUpdated(oldPlate, newPlate)
        end
        return true
    end,

    ---@param src number
    ---@param shopTitle string
    OpenShop = function(src, shopTitle)
        if v2 then
            qbInventory:OpenShop(src, shopTitle)
            return
        end
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

        if v2 then
            shopData[shopTitle] = { inventory = repackedItems, coords = shopCoords, groups = shopGroups }
            qbInventory:CreateShop({ name = shopTitle, label = shopTitle, coords = shopCoords, items = repackedItems })
        else
            shopData[shopTitle] = { label = shopTitle, items = repackedItems, slots = #repackedItems }
        end
        return true
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
        -- Without the slot qb-inventory writes to the first item of that name, which is
        -- the wrong one when the player carries two.
        local ok = qbInventory:SetItemData(src, item, 'info', metadata, slot)
        return ok ~= false
    end,

    ---@param item string
    ---@return string
    GetImagePath = function(item)
        item = olink._stripExt(item)
        local file = LoadResourceFile('qb-inventory', ('html/images/%s.png'):format(item))
        if file then return ('nui://qb-inventory/html/images/%s.png'):format(item) end
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
        if v2 then return qbInventory:CanAddItem(src, item, count or 1) == true end
        return true
    end,

    ---@param id string
    ---@return table[]
    GetStashItems = function(id)
        if v2 then
            local inv = qbInventory:GetInventory(tostring(id))
            return (inv and inv.items) or {}
        end
        return {}
    end,

    ---@param id string
    ---@param item string
    ---@param count number
    ---@return boolean
    RemoveStashItem = function(id, item, count)
        if v2 then
            local success = qbInventory:RemoveItem(tostring(id), item, count, nil, 'o-link: stash remove')
            return success == true
        end
        return false
    end,
})
