if not olink._guardImpl('Inventory', 'ak47_qb_inventory', 'ak47_qb_inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end

local ak47 = exports['ak47_qb_inventory']
local QBCore = exports['qb-core']:GetCoreObject()

-- A stash registered without a size gets what it had on ak47 before this adapter bound.
local DEFAULT_STASH_SLOTS, DEFAULT_STASH_WEIGHT = 20, 5000
-- Size of a trunk filled before any player opened it: ak47's shipped size for emergency vehicles,
-- the police fleet being what fills trunks. ak47 keeps this size when a player opens the trunk.
local TRUNK_SLOTS, TRUNK_WEIGHT = 35, 60000

local stashes = {}
local shopData = {}

-- ak47 reads an inventory only while it is in memory. LoadInventory without data loads a saved
-- one and never creates one.
local function isLoaded(id)
    if ak47:GetInventory(id) then return true end
    local ok, result = pcall(function() return ak47:LoadInventory(id) end)
    return ok and result == true
end

-- A registered stash that was never saved, or that ak47 dropped from memory, is loaded again
-- with its registered size.
local function ensureStash(id)
    if isLoaded(id) then return true end
    local stash = stashes[id]
    if not stash then return false end
    local ok, result = pcall(function()
        return ak47:LoadInventory(id, { label = stash.label, slots = stash.slots, maxWeight = stash.weight, type = 'stash' })
    end)
    return ok and result == true
end

-- ak47 names vehicle storage 'trunk:<plate>' and 'glovebox:<plate>', with the plate's padding trimmed.
local function vehicleInv(kind, plate)
    return ('%s:%s'):format(kind, tostring(plate):match('^%s*(.-)%s*$'))
end

-- ak47 lists every slot, empty ones as {}, under qb key names. Return the occupied slots with
-- both key spellings.
local function occupied(items)
    local out = {}
    for _, item in pairs(items or {}) do
        if type(item) == 'table' and item.name then
            out[#out + 1] = {
                name     = item.name,
                label    = item.label or item.name,
                count    = item.amount,
                amount   = item.amount,
                slot     = item.slot,
                weight   = item.weight,
                metadata = item.info or {},
                info     = item.info or {},
            }
        end
    end
    return out
end

olink._register('inventory', {
    -- GetStashItems reads real contents.
    CanReadStashes = function() return true end,
    -- No way to stop a client opening a stash by id here.
    GuardStash = function() return false end,
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
        if not data or not data.name then return nil end
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
        -- ak47 refuses to load a stash with no slots or maxWeight.
        stashes[id] = {
            label  = label or id,
            slots  = tonumber(slots) or DEFAULT_STASH_SLOTS,
            weight = tonumber(weight) or DEFAULT_STASH_WEIGHT,
            owner  = owner,
        }
        return ensureStash(id)
    end,

    ---@param src number
    ---@param stashId string
    OpenStash = function(src, stashId)
        stashId = tostring(stashId)
        if not ensureStash(stashId) then return end
        ak47:OpenInventory(src, stashId)
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
        local file = LoadResourceFile('ak47_qb_inventory', ('web/build/images/%s.png'):format(item))
        if file then return ('nui://ak47_qb_inventory/web/build/images/%s.png'):format(item) end
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
        id = tostring(id)
        if not ensureStash(id) then return {} end
        return occupied(ak47:GetInventory(id).items)
    end,

    ---@param id string
    ---@param item string
    ---@param count number
    ---@return boolean
    RemoveStashItem = function(id, item, count)
        id = tostring(id)
        -- ak47 raises an error when the inventory is not in memory.
        if not ensureStash(id) then return false end
        local ok, success = pcall(function() return ak47:RemoveItem(id, item, count) end)
        return ok and success == true
    end,

    ---@param id string
    ---@param item string
    ---@param count number
    ---@param metadata table|nil
    ---@return boolean
    AddStashItem = function(id, item, count, metadata)
        id = tostring(id)
        if not ensureStash(id) then return false end
        local ok, success = pcall(function() return ak47:AddItem(id, item, count or 1, nil, metadata) end)
        return ok and success == true
    end,

    ---@param id string
    ---@param items table[] { item, count, metadata }
    ---@return boolean true when every item was stored
    AddStashItems = function(id, items)
        if type(items) ~= 'table' then return false end
        id = tostring(id)
        if not ensureStash(id) then return false end
        local stored = true
        for _, item in pairs(items) do
            local ok, success = pcall(function()
                return ak47:AddItem(id, item.item or item.name, item.count or item.amount or 1, nil,
                    item.metadata or item.info)
            end)
            if not (ok and success == true) then stored = false end
        end
        return stored
    end,

    ---@param id string stash id, or the plate with 'trunk'/'glovebox'
    ---@param _type string|nil 'stash', 'trunk', 'glovebox'
    ---@return boolean
    ClearStash = function(id, _type)
        if type(id) ~= 'string' then return false end
        if _type == 'trunk' or _type == 'glovebox' then id = vehicleInv(_type, id) end
        -- Nothing is saved under this id, so there is nothing to clear.
        if not isLoaded(id) then return true end
        local ok = pcall(function() ak47:ClearInventory(id) end)
        return ok
    end,

    ---@param identifier string plate
    ---@return table[]|nil items, nil when the trunk is not loaded or saved
    GetTrunkItems = function(identifier)
        local trunkId = vehicleInv('trunk', identifier)
        local ok, loaded = pcall(isLoaded, trunkId)
        if not (ok and loaded) then return nil end
        return occupied(ak47:GetInventory(trunkId).items)
    end,

    ---@param identifier string plate
    ---@param items table[] { name|item, count|amount, metadata|info }
    ---@return boolean true when at least one item was stored
    AddTrunkItems = function(identifier, items)
        if type(items) ~= 'table' then return false end
        if #items == 0 then return true end
        local trunkId = vehicleInv('trunk', identifier)
        if not isLoaded(trunkId) then
            local ok, created = pcall(function()
                return ak47:LoadInventory(trunkId, { label = trunkId:upper(), slots = TRUNK_SLOTS, maxWeight = TRUNK_WEIGHT, type = 'trunk' })
            end)
            if not (ok and created == true) then return false end
        end
        local stored = false
        for i = 1, #items do
            local entry = items[i]
            local ok, success = pcall(function()
                return ak47:AddItem(trunkId, entry.name or entry.item, entry.amount or entry.count or 1,
                    entry.slot, entry.info or entry.metadata or {})
            end)
            if ok and success == true then stored = true end
        end
        return stored
    end,

    ---@param oldPlate string
    ---@param newPlate string
    ---@return boolean
    UpdatePlate = function(oldPlate, newPlate)
        local ok = pcall(function() ak47:OnChangeVehiclePlate(oldPlate, newPlate) end)
        if not ok then
            -- No OnChangeVehiclePlate: copy each container to the new plate, then empty the old one.
            for _, kind in ipairs({ 'glovebox', 'trunk' }) do
                local from, to = vehicleInv(kind, oldPlate), vehicleInv(kind, newPlate)
                if isLoaded(from) then
                    local inv = ak47:GetInventory(from)
                    local ready = isLoaded(to) or ak47:LoadInventory(to, {
                        label = to:upper(), slots = inv.slots, maxWeight = inv.maxWeight, type = kind,
                    }) == true
                    if ready then
                        for _, item in pairs(inv.items or {}) do
                            if item.name then ak47:AddItem(to, item.name, item.amount, item.slot, item.info) end
                        end
                        ak47:ClearInventory(from)
                    end
                end
            end
        end
        if GetResourceState('jg-mechanic') == 'started' then
            exports['jg-mechanic']:vehiclePlateUpdated(oldPlate, newPlate)
        end
        return true
    end,

    ---@param src number
    ---@param shopTitle string
    OpenShop = function(src, shopTitle)
        shopTitle = tostring(shopTitle)
        local inv = ak47:GetInventory(shopTitle)
        if not inv or inv.type ~= 'shop' then return end
        ak47:OpenInventory(src, shopTitle)
    end,

    ---@param shopTitle string
    ---@param shopInventory table
    ---@param shopCoords table|nil not used by ak47
    ---@param shopGroups table|nil not used by ak47
    ---@return boolean
    RegisterShop = function(shopTitle, shopInventory, shopCoords, shopGroups)
        if not shopTitle or not shopInventory then return false end
        shopTitle = tostring(shopTitle)
        if shopData[shopTitle] then return true end

        -- An item without a count is sold without a stock limit.
        local items = {}
        for _, v in pairs(shopInventory) do
            items[#items + 1] = {
                item     = v.name,
                buyPrice = v.price,
                amount   = v.count or v.amount,
                info     = v.metadata or v.info,
            }
        end

        local ok = pcall(function() ak47:CreateShop(shopTitle, shopTitle, items, 'cash') end)
        if not ok then return false end
        shopData[shopTitle] = { coords = shopCoords, groups = shopGroups }
        return true
    end,
})
