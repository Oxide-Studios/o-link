if not olink._guardImpl('Inventory', 'origen_inventory', 'origen_inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('ox_inventory') == 'started' then return end

local origin = exports.origen_inventory
local stashes = {}

olink._register('inventory', {
    -- GetStashItems cannot read contents here, so an empty list proves nothing.
    CanReadStashes = function() return false end,
    ---@param src number
    ---@param item string
    ---@return number
    GetItemCount = function(src, item)
        return origin:getItemCount(src, item, nil, false) or 0
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    AddItem = function(src, item, count, slot, metadata)
        if not origin:canCarryItem(src, item, count) then return false end
        local success = origin:addItem(src, item, count, metadata, slot, false)
        return success == true
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    RemoveItem = function(src, item, count, slot, metadata)
        local success = origin:removeItem(src, item, count, metadata, slot, false)
        return success == true
    end,

    ---@param src number
    ---@param slot number
    ---@return table|nil SlotData
    GetItemBySlot = function(src, slot)
        local inv = olink.inventory.GetPlayerInventory(src) or {}
        for _, v in pairs(inv) do
            if v.slot == slot then return v end
        end
        return nil
    end,

    ---@param src number
    ---@return table[] SlotData[]
    GetPlayerInventory = function(src)
        local playerInv = origin:GetInventory(src)
        local inv = (playerInv and playerInv.inventory) or {}
        local result = {}
        for _, v in pairs(inv) do
            if v.slot then
                result[#result + 1] = {
                    name     = v.name,
                    label    = v.label or v.name,
                    count    = v.amount or v.count,
                    slot     = v.slot,
                    metadata = v.metadata or v.info or {},
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
        return (origin:getItemCount(src, item, nil, false) or 0) >= (count or 1)
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
        stashes[id] = { id = id, label = label, slots = slots, weight = weight, owner = owner }
        origin:registerStash(id, label, slots, weight, owner)
        return true
    end,

    ---@param src number
    ---@param stashId string
    OpenStash = function(src, stashId)
        origin:OpenInventory(src, 'stash', tostring(stashId))
    end,

    ---@param src number
    ---@param targetSrc number
    ---@return boolean
    OpenPlayerInventory = function(src, targetSrc)
        assert(src, 'OpenPlayerInventory: src is required')
        assert(targetSrc, 'OpenPlayerInventory: targetSrc is required')
        origin:OpenInventory(src, 'otherplayer', targetSrc)
        return true
    end,

    ---@param item string
    ---@return table
    GetItemInfo = function(item)
        local data = origin:Items(item)
        if not data then return {} end
        return {
            name = data.name,
            label = data.label,
            weight = data.weight or 0,
            description = data.description,
            stack = data.unique == nil and true or (not data.unique),
            image = data.image or (olink.inventory.GetImagePath and olink.inventory.GetImagePath(item) or nil),
        }
    end,

    ---@param src number
    ---@param item string
    ---@param slot number
    ---@param metadata table
    ---@return boolean
    SetMetadata = function(src, item, slot, metadata)
        origin:setMetadata(src, slot, metadata)
        return true
    end,

    ---@param item string
    ---@return string
    GetImagePath = function(item)
        item = olink._stripExt(item)
        local file = LoadResourceFile('origen_inventory', ('html/images/%s.png'):format(item))
        if file then return ('nui://origen_inventory/html/images/%s.png'):format(item) end
        return 'https://avatars.githubusercontent.com/u/47620135'
    end,

    ---@return table All item definitions
    Items = function()
        return origin:Items() or {}
    end,

    ---@param src number
    ---@param item string
    ---@param count number|nil
    ---@return boolean
    CanCarryItem = function(src, item, count)
        return origin:canCarryItem(src, item, count or 1) == true
    end,

    ---@param identifier string plate or trunk identifier
    ---@param items table[]
    ---@return boolean
    -- origen's "trunk" is a stash it registers, so it reads back as one.
    ---@param identifier string plate
    ---@return table[]|nil
    GetTrunkItems = function(identifier)
        local ok, items = pcall(function()
            return origin:getInventory('trunk_' .. tostring(identifier), 'stash')
        end)
        if not ok or type(items) ~= 'table' then return nil end
        return items.inventory or items
    end,

    AddTrunkItems = function(identifier, items)
        if type(items) ~= 'table' then return false end
        local id = 'trunk_' .. identifier
        local self = olink.inventory
        if self and self.RegisterStash then
            self.RegisterStash(id, identifier, 20, 10000, nil)
        end
        local repack = {}
        for _, v in pairs(items) do
            repack[#repack + 1] = {
                name     = v.item or v.name,
                amount   = v.count or v.amount,
                metadata = v.metadata or v.info or {},
            }
        end
        if #repack == 0 then return false end
        origin:addItems(id, repack)
        return true
    end,

    ---@param id string
    ---@param _type string|nil 'stash', 'trunk', 'glovebox'
    ---@return boolean
    ClearStash = function(id, _type)
        if type(id) ~= 'string' then return false end
        if stashes[id] then stashes[id] = nil end
        local fullId = id
        if _type == 'trunk' then
            fullId = 'trunk_' .. id
        elseif _type == 'glovebox' then
            fullId = 'glovebox_' .. id
        elseif _type == 'stash' then
            fullId = 'stash_' .. id
        end
        local inv = origin:getInventory(fullId, _type)
        if not inv then return false end
        for _, v in pairs(inv.inventory or {}) do
            if v.slot then
                origin:removeItem(fullId, v.name, v.amount, nil, v.slot)
            end
        end
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

    -- Unsupported features
    GetStashItems = function() return {} end,
    RemoveStashItem = function() return false end,
    OpenShop = function() end,
    RegisterShop = function() end,
})
