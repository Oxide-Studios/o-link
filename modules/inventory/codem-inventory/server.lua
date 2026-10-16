if not olink._guardImpl('Inventory', 'codem-inventory', 'codem-inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end

local codem = exports['codem-inventory']
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
        return codem:GetItemsTotalAmount(src, item) or 0
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    AddItem = function(src, item, count, slot, metadata)
        local success = codem:AddItem(src, item, count, slot, metadata)
        return success ~= nil and success ~= false
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
        local success = codem:RemoveItem(src, item, count, slot)
        return success ~= nil and success ~= false
    end,

    ---@param src number
    ---@param slot number
    ---@return table|nil SlotData
    GetItemBySlot = function(src, slot)
        local data = codem:GetItemBySlot(src, slot)
        if not data then return nil end
        return {
            name     = data.name,
            label    = data.label or data.name,
            count    = data.amount or data.count,
            slot     = data.slot,
            weight   = data.weight,
            metadata = data.info or data.metadata or {},
        }
    end,

    ---@param src number
    ---@return table[] SlotData[]
    GetPlayerInventory = function(src)
        local identifier = olink.character.GetIdentifier(src)
        if not identifier then return {} end
        local playerItems = codem:GetInventory(identifier, src)
        local result = {}
        for _, v in pairs(playerItems or {}) do
            result[#result + 1] = {
                name     = v.name,
                label    = v.label,
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
        local has = codem:HasItem(src, item, count or 1)
        return has ~= nil and has ~= false
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
        stashes[id] = { label = label, slots = slots, weight = weight }
        return true
    end,

    ---@param src number
    ---@param stashId string
    OpenStash = function(src, stashId)
        stashId = tostring(stashId)
        TriggerClientEvent('codem-inventory:client:openStash', src, stashId)
    end,

    ---@param id string
    ---@param items table[] { item, count, metadata }
    ---@return boolean
    AddStashItems = function(id, items)
        if type(items) ~= 'table' then return false end
        local repack = {}
        local getInfo = olink.inventory.GetItemInfo or function() return { weight = 0 } end
        for _, v in pairs(items) do
            repack[#repack + 1] = {
                item        = v.item,
                amount      = v.count or v.amount,
                info        = v.metadata or v.info or {},
                unique      = v.unique or v.stack or false,
                description = v.description or 'none',
                weight      = (getInfo(v.item) or {}).weight or 0,
                type        = 'item',
                slot        = #repack + 1,
            }
        end
        codem:UpdateStash(id, repack)
        return true
    end,

    ---@param id string
    ---@param _type string|nil unused with codem
    ---@return boolean
    ClearStash = function(id, _type)
        if type(id) ~= 'string' then return false end
        if stashes[id] then stashes[id] = nil end
        codem:UpdateStash(id, {})
        return true
    end,

    ---@param src number
    ---@param targetSrc number
    ---@return boolean
    OpenPlayerInventory = function(src, targetSrc)
        assert(src, 'OpenPlayerInventory: src is required')
        assert(targetSrc, 'OpenPlayerInventory: targetSrc is required')
        codem:OpenInventory(src, targetSrc)
        return true
    end,

    ---@param item string
    ---@return table
    GetItemInfo = function(item)
        local items = codem:GetItemList()
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
        codem:SetItemMetadata(src, slot, metadata)
        return true
    end,

    ---@param item string
    ---@return string
    GetImagePath = function(item)
        item = olink._stripExt(item)
        local file = LoadResourceFile('codem-inventory', ('html/itemimages/%s.png'):format(item))
        if file then return ('nui://codem-inventory/html/itemimages/%s.png'):format(item) end
        return 'https://avatars.githubusercontent.com/u/47620135'
    end,

    ---@return table All item definitions
    Items = function()
        return codem:GetItemList() or {}
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
            'UPDATE trunkitems SET plate = @newplate WHERE plate = @oldplate',
            'UPDATE gloveboxitems SET plate = @newplate WHERE plate = @oldplate',
        }, { newplate = newPlate, oldplate = oldPlate })
        if GetResourceState('jg-mechanic') == 'started' then
            exports['jg-mechanic']:vehiclePlateUpdated(oldPlate, newPlate)
        end
        return true
    end,

    -- Unsupported features
    GetStashItems = function() return {} end,
    RemoveStashItem = function() return false end,
    AddTrunkItems = function() return false end,
    OpenShop = function() end,
    RegisterShop = function() end,
})
