if not olink._guardImpl('Inventory', 'ox_inventory', 'ox_inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('qb-inventory') == 'started' then return end

local ox_inventory = exports.ox_inventory

local stashes = {}

-- ox resolves a vehicle inventory through the entity. Given only a plate it
-- scans world vehicles comparing GetVehicleNumberPlateText, which is unreliable
-- server-side for entities created with CreateVehicleServerSetter
-- (citizenfx/fivem#2838) -- a job fleet vehicle has its plate stamped by the
-- client, so the scan never matches and the load fails. Passing the netid lets
-- ox take the entity directly; Inventory() accepts this table form.
---@param plate string
---@param netId number|nil
---@param kind string 'trunk'|'glove'
---@return table|string
local function vehicleInv(plate, netId, kind)
    local id = ('%s%s'):format(kind, tostring(plate))
    if type(netId) ~= 'number' or netId <= 0 then return id end
    return { id = id, netid = netId, type = kind == 'glove' and 'glovebox' or 'trunk' }
end

-- Guarded stashes open only through OpenStash: ox_inventory lets a client open any stash whose id it
-- has seen, so the hook refuses opens of a guarded id that the server did not start just before.
local guarded, approved = {}, {}
local GUARD_WINDOW_MS = 5000
local hooked = false

local function hookGuard()
    if hooked then return end
    hooked = true
    ox_inventory:registerHook('openInventory', function(payload)
        local id = payload.inventoryId and tostring(payload.inventoryId)
        if not id or not guarded[id] then return true end
        local key = ('%s:%s'):format(payload.source, id)
        local at = approved[key]
        approved[key] = nil
        return at ~= nil and GetGameTimer() - at <= GUARD_WINDOW_MS
    end, { typeFilter = { stash = true } })
end

olink._register('inventory', {
    -- GetStashItems reads real contents.
    CanReadStashes = function() return true end,
    ---@param id string
    ---@return boolean
    GuardStash = function(id)
        guarded[tostring(id)] = true
        hookGuard()
        return true
    end,
    ---@param src number
    ---@param item string
    ---@return number
    GetItemCount = function(src, item)
        return ox_inventory:GetItemCount(src, item, nil, false) or 0
    end,

    ---@param src number
    ---@param item string
    ---@param count number|nil
    ---@return boolean
    HasItem = function(src, item, count)
        local total = ox_inventory:GetItemCount(src, item, nil, false) or 0
        return total >= (count or 1)
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    AddItem = function(src, item, count, slot, metadata)
        if not ox_inventory:CanCarryItem(src, item, count, metadata) then return false end
        local success = ox_inventory:AddItem(src, item, count, metadata, slot)
        return success == true
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    RemoveItem = function(src, item, count, slot, metadata)
        local success = ox_inventory:RemoveItem(src, item, count, metadata, slot)
        return success == true
    end,

    ---@param src number
    ---@param slot number
    ---@return table|nil SlotData {name, label, count, slot, weight, metadata}
    GetItemBySlot = function(src, slot)
        local data = ox_inventory:GetSlot(src, slot)
        if not data then return nil end
        return {
            name     = data.name,
            label    = data.label,
            count    = data.count,
            slot     = data.slot,
            weight   = data.weight,
            metadata = data.metadata or {},
        }
    end,

    ---@param src number
    ---@return table[] SlotData[]
    GetPlayerInventory = function(src)
        local items = ox_inventory:GetInventoryItems(src, false)
        if not items then return {} end
        local result = {}
        for _, item in pairs(items) do
            result[#result + 1] = {
                name     = item.name,
                label    = item.label,
                count    = item.count,
                slot     = item.slot,
                weight   = item.weight,
                metadata = item.metadata or {},
            }
        end
        return result
    end,

    ---@param src number
    ---@param targetSrc number
    ---@return boolean
    OpenPlayerInventory = function(src, targetSrc)
        assert(src, 'OpenPlayerInventory: src is required')
        assert(targetSrc, 'OpenPlayerInventory: targetSrc is required')
        ox_inventory:forceOpenInventory(src, 'player', targetSrc)
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
        stashes[id] = true
        ox_inventory:RegisterStash(id, label, slots, weight, owner)
        return true
    end,

    ---@param src number
    ---@param stashId string
    ---@return nil
    OpenStash = function(src, stashId)
        local id = tostring(stashId)
        if guarded[id] then approved[('%s:%s'):format(src, id)] = GetGameTimer() end
        ox_inventory:forceOpenInventory(src, 'stash', id)
    end,

    ---@param item string
    ---@return table
    GetItemInfo = function(item)
        local data = ox_inventory:Items(item)
        if not data then return {} end
        return {
            name = data.name,
            label = data.label,
            weight = data.weight,
            description = data.description,
            stack = data.stack,
            image = ('nui://ox_inventory/web/images/%s'):format(
                (data.client and data.client.image) or ('%s.png'):format(item)),
        }
    end,

    ---@param src number
    ---@param item string
    ---@param slot number
    ---@param metadata table
    ---@return boolean
    SetMetadata = function(src, item, slot, metadata)
        ox_inventory:SetMetadata(src, slot, metadata)
        return true
    end,

    ---@param item string
    ---@return string
    GetImagePath = function(item)
        item = olink._stripExt(item)
        local file = LoadResourceFile('ox_inventory', ('web/images/%s.png'):format(item))
        if file then return ('nui://ox_inventory/web/images/%s.png'):format(item) end
        return 'https://avatars.githubusercontent.com/u/47620135'
    end,

    ---@return table All item definitions
    Items = function()
        return ox_inventory:Items() or {}
    end,

    ---@param src number
    ---@param item string
    ---@param count number|nil
    ---@return boolean
    CanCarryItem = function(src, item, count)
        return ox_inventory:CanCarryItem(src, item, count or 1) == true
    end,

    ---@param id string
    ---@return table[]
    GetStashItems = function(id)
        return ox_inventory:GetInventoryItems(tostring(id), false) or {}
    end,

    ---@param id string
    ---@param item string
    ---@param count number
    ---@return boolean
    RemoveStashItem = function(id, item, count)
        local success = ox_inventory:RemoveItem(tostring(id), item, count)
        return success == true
    end,

    ---@param id string
    ---@param item string
    ---@param count number
    ---@param metadata table|nil
    ---@return boolean
    AddStashItem = function(id, item, count, metadata)
        local success = ox_inventory:AddItem(tostring(id), item, count or 1, metadata)
        return success == true
    end,

    -- With _type 'trunk' or 'glovebox', `id` is the plate: ox derives the
    -- inventory id by prefix and parses the plate back out as id:sub(6), so
    -- both prefixes are exactly five characters and carry no separator.
    ---@param id string stash id, or the plate when _type is trunk/glovebox
    ---@param _type string|nil 'stash', 'trunk', 'glovebox'
    ---@return boolean
    ClearStash = function(id, _type, netId)
        if type(id) ~= 'string' then return false end
        local target = id
        if _type == 'trunk' or _type == 'glovebox' then
            target = vehicleInv(id, netId, _type == 'glovebox' and 'glove' or 'trunk')
        end
        ox_inventory:ClearInventory(target)
        return true
    end,

    -- ox's native trunk id is 'trunk'..plate with no separator -- it parses the
    -- plate back out as id:sub(6). A RegisterStash'd 'trunk_<plate>' is a
    -- separate stash-typed inventory the trunk keybind never opens. ox creates
    -- the real one lazily off the vehicle entity, so the vehicle must exist and
    -- be network-owned when this runs; if it isn't, AddItem returns
    -- 'invalid_inventory' and the false return lets the caller fall back.
    ---@param identifier string plate
    ---@param items table[] { name|item, count|amount, metadata|info }
    ---@return boolean

    ---@param identifier string plate
    ---@return table[] items
    GetTrunkItems = function(identifier, netId)
        local ok, items = pcall(function()
            return ox_inventory:GetInventoryItems(vehicleInv(identifier, netId, 'trunk'))
        end)
        return (ok and type(items) == 'table') and items or nil
    end,

    -- ox's native trunk id is 'trunk'..plate with no separator -- it parses the
    -- plate back out as id:sub(6). A RegisterStash'd 'trunk_<plate>' is a
    -- separate stash-typed inventory the trunk keybind never opens. ox creates
    -- the real one lazily off the vehicle entity, so the vehicle must exist and
    -- be network-owned when this runs; if it isn't, AddItem returns
    -- 'invalid_inventory' and the false return lets the caller fall back.
    ---@param identifier string plate
    ---@param items table[] { name|item, count|amount, metadata|info }
    ---@return boolean
    AddTrunkItems = function(identifier, items, netId)
        if type(items) ~= 'table' then return false end
        if #items == 0 then return true end

        local trunkId = vehicleInv(identifier, netId, 'trunk')
        local added = false
        for _, item in ipairs(items) do
            local name = item.name or item.item
            if name then
                local ok = ox_inventory:AddItem(trunkId, name,
                    item.count or item.amount or 1, item.metadata or item.info)
                if ok == true then added = true end
            end
        end
        return added
    end,

    ---@param oldPlate string
    ---@param newPlate string
    ---@return boolean
    UpdatePlate = function(oldPlate, newPlate)
        ox_inventory:UpdateVehicle(oldPlate, newPlate)
        if GetResourceState('jg-mechanic') == 'started' then
            exports['jg-mechanic']:vehiclePlateUpdated(oldPlate, newPlate)
        end
        return true
    end,

    ---@param id string
    ---@param items table[] { item, count, metadata }
    ---@return boolean
    AddStashItems = function(id, items)
        if type(items) ~= 'table' then return false end
        local success = false
        for _, v in pairs(items) do
            success = ox_inventory:AddItem(tostring(id), v.item, v.count or v.amount, v.metadata or v.info or {})
        end
        return success == true
    end,

    ---@param src number
    ---@param shopTitle string
    OpenShop = function(src, shopTitle)
        ox_inventory:openInventory(src, 'shop', { type = shopTitle })
    end,

    ---@param shopTitle string
    ---@param shopInventory table
    ---@param shopCoords table|nil
    ---@param shopGroups table|nil
    RegisterShop = function(shopTitle, shopInventory, shopCoords, shopGroups)
        ox_inventory:RegisterShop(shopTitle, { inventory = shopInventory })
    end,
})
