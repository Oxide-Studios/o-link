if not olink._guardImpl('Inventory', 'tgiann-inventory', 'tgiann-inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end

local tgiann = exports['tgiann-inventory']
local stashes = {}

olink._register('inventory', {
    -- GetStashItems cannot read contents here, so an empty list proves nothing.
    CanReadStashes = function() return false end,
    -- No way to stop a client opening a stash by id here.
    GuardStash = function() return false end,
    ---@param src number
    ---@param item string
    ---@return number
    GetItemCount = function(src, item)
        local data = tgiann:GetItemByName(src, item)
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
        if not tgiann:CanCarryItem(src, item, count) then return false end
        local success = tgiann:AddItem(src, item, count, slot, metadata, false)
        return success == true
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    RemoveItem = function(src, item, count, slot, metadata)
        local success = tgiann:RemoveItem(src, item, count, slot, metadata)
        return success == true
    end,

    ---@param src number
    ---@param slot number
    ---@return table|nil SlotData
    GetItemBySlot = function(src, slot)
        local data = tgiann:GetItemBySlot(src, slot)
        if not data then return nil end
        return {
            name     = data.name,
            label    = data.label or data.name,
            count    = data.amount or data.count,
            slot     = slot,
            weight   = data.weight,
            metadata = data.info or data.metadata or {},
        }
    end,

    ---@param src number
    ---@return table[] SlotData[]
    GetPlayerInventory = function(src)
        local inventory = tgiann:GetPlayerItems(src)
        local result = {}
        for k, v in pairs(inventory or {}) do
            if tonumber(k) then
                result[#result + 1] = {
                    name     = v.name,
                    label    = v.name,
                    count    = v.amount,
                    slot     = v.slot,
                    metadata = v.info or v.metadata or {},
                }
            end
        end
        return result
    end,

    ---@param src number
    ---@param item string
    ---@param count number|nil
    ---@return boolean
    HasItem = function(src, item, count)
        return tgiann:HasItem(src, item, count or 1) == true
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
        local tbl = stashes[stashId] or { weight = 1000000, slots = 50, label = 'Stash' }
        tgiann:ForceOpenInventory(src, 'stash', stashId, {
            maxWeight = tbl.weight,
            slots     = tbl.slots,
            label     = tbl.label,
        })
    end,

    ---@param src number
    ---@param targetSrc number
    ---@return boolean
    OpenPlayerInventory = function(src, targetSrc)
        assert(src, 'OpenPlayerInventory: src is required')
        assert(targetSrc, 'OpenPlayerInventory: targetSrc is required')
        tgiann:OpenInventoryById(src, targetSrc)
        return true
    end,

    ---@param item string
    ---@return table {name, label, weight, description}
    GetItemInfo = function(item)
        local items = tgiann:GetItemList()
        if not items or not items[item] then return {} end
        local data = items[item]
        return { name = data.name, label = data.label, weight = data.weight, description = data.description }
    end,

    ---@param src number
    ---@param item string
    ---@param slot number
    ---@param metadata table
    ---@return boolean
    SetMetadata = function(src, item, slot, metadata)
        tgiann:UpdateItemMetadata(src, item, slot, metadata)
        return true
    end,

    ---@param item string
    ---@return string
    GetImagePath = function(item)
        item = olink._stripExt(item)
        local png = LoadResourceFile('inventory_images', ('images/%s.png'):format(item))
        if png then return ('nui://inventory_images/images/%s.png'):format(item) end
        local webp = LoadResourceFile('inventory_images', ('images/%s.webp'):format(item))
        if webp then return ('nui://inventory_images/images/%s.webp'):format(item) end
        return ''
    end,

    ---@return table All item definitions
    Items = function()
        return tgiann:GetItemList() or {}
    end,

    ---@param src number
    ---@param item string
    ---@param count number|nil
    ---@return boolean
    CanCarryItem = function(src, item, count)
        return tgiann:CanCarryItem(src, item, count or 1) == true
    end,

    ---@param id string
    ---@return table[]
    GetStashItems = function(id)
        return {}
    end,

    ---@param id string
    ---@param item string
    ---@param count number
    ---@return boolean
    RemoveStashItem = function(id, item, count)
        return false
    end,

    ---@param id string
    ---@param _type string|nil 'stash', 'trunk', 'glovebox'
    ---@return boolean
    ClearStash = function(id, _type)
        if type(id) ~= 'string' then return false end
        tgiann:DeleteInventory(_type or 'stash', id)
        return true
    end,

    ---@param identifier string plate or trunk identifier
    ---@param items table[]
    ---@return boolean
    AddTrunkItems = function(identifier, items)
        if type(items) ~= 'table' then return false end
        for _, v in pairs(items) do
            tgiann:AddItemToSecondaryInventory('trunk', identifier, v.item or v.name, v.count or v.amount, nil, v.metadata or v.info)
        end
        return true
    end,

    ---@param oldPlate string
    ---@param newPlate string
    ---@return boolean
    UpdatePlate = function(oldPlate, newPlate)
        MySQL.transaction.await({
            'UPDATE tgiann_inventory_trunkitems SET plate = @newplate WHERE plate = @oldplate',
            'UPDATE tgiann_inventory_gloveboxitems SET plate = @newplate WHERE plate = @oldplate',
        }, { newplate = newPlate, oldplate = oldPlate })
        tgiann:UpdateVehicle(oldPlate, newPlate)
        if GetResourceState('jg-mechanic') == 'started' then
            exports['jg-mechanic']:vehiclePlateUpdated(oldPlate, newPlate)
        end
        return true
    end,

    ---@param src number
    ---@param shopTitle string
    OpenShop = function(src, shopTitle)
    end,

    ---@param shopTitle string
    ---@param shopInventory table
    ---@param shopCoords table|nil
    ---@param shopGroups table|nil
    RegisterShop = function(shopTitle, shopInventory, shopCoords, shopGroups)
    end,
})
