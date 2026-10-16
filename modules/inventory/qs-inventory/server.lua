if not olink._guardImpl('Inventory', 'qs-inventory', 'qs-inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end

local quasar = exports['qs-inventory']
local stashes = {}

olink._register('inventory', {
    -- GetStashItems cannot read contents here, so an empty list proves nothing.
    CanReadStashes = function() return false end,
    ---@param src number
    ---@param item string
    ---@return number
    GetItemCount = function(src, item)
        return quasar:GetItemTotalAmount(src, item) or 0
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    AddItem = function(src, item, count, slot, metadata)
        if not quasar:CanCarryItem(src, item, count) then return false end
        local success = quasar:AddItem(src, item, count, slot, metadata)
        return success == true
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    RemoveItem = function(src, item, count, slot, metadata)
        local success = quasar:RemoveItem(src, item, count, slot, metadata)
        return success == true
    end,

    ---@param src number
    ---@param slot number
    ---@return table|nil SlotData
    GetItemBySlot = function(src, slot)
        local playerItems = quasar:GetInventory(src)
        for _, v in pairs(playerItems or {}) do
            if v.slot == slot then
                return {
                    name     = v.name,
                    label    = v.label or v.name,
                    count    = v.amount or v.count,
                    slot     = slot,
                    weight   = v.weight,
                    metadata = v.info or v.metadata or {},
                }
            end
        end
        return nil
    end,

    ---@param src number
    ---@return table[] SlotData[]
    GetPlayerInventory = function(src)
        local playerItems = quasar:GetInventory(src)
        local result = {}
        for _, v in pairs(playerItems or {}) do
            result[#result + 1] = {
                name     = v.name,
                label    = v.label or v.name,
                count    = v.amount or v.count,
                slot     = v.slot,
                metadata = v.info or v.metadata or {},
            }
        end
        return result
    end,

    ---@param src number
    ---@param item string
    ---@param count number|nil
    ---@return boolean
    HasItem = function(src, item, count)
        local c = quasar:GetItemTotalAmount(src, item) or 0
        return c >= (count or 1)
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
        local tbl = stashes[stashId] or {}
        TriggerEvent('inventory:server:OpenInventory', 'stash', stashId, {
            maxweight = tbl.weight or 5000,
            slots     = tbl.slots or 20,
        })
        TriggerClientEvent('inventory:client:SetCurrentStash', src, stashId)
    end,

    ---@param src number
    ---@param targetSrc number
    ---@return boolean
    OpenPlayerInventory = function(src, targetSrc)
        assert(src, 'OpenPlayerInventory: src is required')
        assert(targetSrc, 'OpenPlayerInventory: targetSrc is required')
        quasar:OpenInventoryById(src, targetSrc)
        return true
    end,

    ---@param item string
    ---@return table {name, label, weight, description}
    GetItemInfo = function(item)
        local items = quasar:GetItemList()
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
        quasar:SetItemMetadata(src, slot, metadata)
        return true
    end,

    ---@param item string
    ---@return string
    GetImagePath = function(item)
        item = olink._stripExt(item)
        local file = LoadResourceFile('qs-inventory', ('html/images/%s.png'):format(item))
        if file then return ('nui://qs-inventory/html/images/%s.png'):format(item) end
        return ''
    end,

    ---@return table All item definitions
    Items = function()
        return quasar:GetItemList() or {}
    end,

    ---@param src number
    ---@param item string
    ---@param count number|nil
    ---@return boolean
    CanCarryItem = function(src, item, count)
        return quasar:CanCarryItem(src, item, count or 1) == true
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
        quasar:ClearOtherInventory(_type or 'stash', id)
        return true
    end,

    ---@param identifier string plate or trunk identifier
    ---@param items table[]
    ---@return boolean
    AddTrunkItems = function(identifier, items)
        return false
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
    end,

    ---@param shopTitle string
    ---@param shopInventory table
    ---@param shopCoords table|nil
    ---@param shopGroups table|nil
    RegisterShop = function(shopTitle, shopInventory, shopCoords, shopGroups)
    end,
})
