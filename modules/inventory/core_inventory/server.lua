if not olink._guardImpl('Inventory', 'core_inventory', 'core_inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end

local core = exports.core_inventory
local stashes = {}

olink._register('inventory', {
    -- GetStashItems cannot read contents here, so an empty list proves nothing.
    CanReadStashes = function() return false end,
    -- No way to stop a client opening a stash by id here.
    GuardStash = function() return false end,
    ---@param src number
    ---@param item string
    ---@param metadata table|nil
    ---@return number
    GetItemCount = function(src, item, metadata)
        if metadata then
            local inv = olink.inventory.GetPlayerInventory(src) or {}
            local total = 0
            for _, v in pairs(inv) do
                if v.name == item and v.metadata == metadata then
                    total = total + (v.count or 0)
                end
            end
            return total
        end
        return core:getItemCount(src, item) or 0
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    AddItem = function(src, item, count, slot, metadata)
        local success = core:addItem(src, item, count, metadata)
        return success ~= false and success ~= nil
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    RemoveItem = function(src, item, count, slot, metadata)
        if not slot and metadata then
            local inv = olink.inventory.GetPlayerInventory(src) or {}
            for _, v in pairs(inv) do
                if v.name == item and v.metadata == metadata then
                    slot = v.slot
                    break
                end
            end
        end
        if slot then
            local identifier = olink.character.GetIdentifier(src)
            if identifier then
                identifier = string.gsub(identifier, ':', '')
                return core:removeItemExact('content-' .. identifier, slot, count) ~= false
            end
        end
        core:removeItem(src, item, count)
        return true
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
        local playerItems = core:getInventory(src) or {}
        local result = {}
        for _, v in pairs(playerItems) do
            -- Items with metadata and count > 1 need to be fetched deeply to get
            -- per-slot metadata, because core_inventory stacks them by name.
            if (v.metadata or v.info) and (v.count or v.amount or 0) > 1 then
                local deep = core:getItems(src, v.name)
                if deep then
                    for _, item in pairs(deep) do
                        result[#result + 1] = {
                            name     = v.name,
                            label    = v.label or v.name,
                            count    = item.count or item.amount,
                            slot     = item.id or item.slot,
                            metadata = item.metadata or item.info or {},
                        }
                    end
                end
            else
                result[#result + 1] = {
                    name     = v.name,
                    label    = v.label or v.name,
                    count    = v.count or v.amount,
                    slot     = v.id or v.slot,
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
        local c = core:getItemCount(src, item) or 0
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
        -- core_inventory divides slots/weight by 2 per documentation quirk
        local half = (slots or 30) / 2
        stashes[id] = { label = label, slots = half, weight = half, owner = owner }
        return true
    end,

    ---@param src number
    ---@param stashId string
    OpenStash = function(src, stashId)
        stashId = tostring(stashId)
        local tbl = stashes[stashId] or { slots = 15, weight = 25000 }
        core:openInventory(src, stashId, 'stash', tbl.slots, tbl.weight, true, nil, false)
    end,

    ---@param src number
    ---@param targetSrc number
    ---@return boolean
    OpenPlayerInventory = function(src, targetSrc)
        assert(src, 'OpenPlayerInventory: src is required')
        assert(targetSrc, 'OpenPlayerInventory: targetSrc is required')
        local identifier = olink.character.GetIdentifier(targetSrc)
        if not identifier then return false end
        core:openInventory(src, 'stash-' .. string.gsub(identifier, ':', ''), 'stash', nil, nil, true, nil, false)
        return true
    end,

    ---@param item string
    ---@return table
    GetItemInfo = function(item)
        local items = core:getItemsList()
        local data = items and items[item]
        if not data then return {} end
        return {
            name = data.name or item,
            label = data.label or item,
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
        core:setMetadata(src, slot, metadata)
        return true
    end,

    ---@param item string
    ---@return string
    GetImagePath = function(item)
        item = olink._stripExt(item)
        local file = LoadResourceFile('core_inventory', ('html/img/%s.png'):format(item))
        if file then return ('nui://core_inventory/html/img/%s.png'):format(item) end
        return 'https://avatars.githubusercontent.com/u/47620135'
    end,

    ---@return table All item definitions
    Items = function()
        return core:getItemsList() or {}
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
            'UPDATE coreinventories SET name = @newplate WHERE name = @oldplate',
            'UPDATE coreinventories SET name = @newplate WHERE name = @glovebox_oldplate',
            'UPDATE coreinventories SET name = @newplate WHERE name = @trunk_oldplate',
        }, {
            newplate          = newPlate,
            oldplate          = oldPlate,
            glovebox_oldplate = 'glovebox-' .. oldPlate,
            trunk_oldplate    = 'trunk-' .. oldPlate,
        })
        if GetResourceState('jg-mechanic') == 'started' then
            exports['jg-mechanic']:vehiclePlateUpdated(oldPlate, newPlate)
        end
        return true
    end,

    -- Unsupported features
    GetStashItems = function() return {} end,
    RemoveStashItem = function() return false end,
    ClearStash = function() return false end,
    AddTrunkItems = function() return false end,
    OpenShop = function() end,
    RegisterShop = function() end,
})
