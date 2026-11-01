-- Codem Inventory V2 binds this adapter too: see the note in server.lua.
local codemV2 = GetResourceState('codem-inventoryv2') == 'started'

if not olink._guardImpl('Inventory', 'ox_inventory', codemV2 and 'codem-inventoryv2' or 'ox_inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end
if not codemV2 and not olink._hasOverride('Inventory') and GetResourceState('qb-inventory') == 'started' then return end

local ox_inventory = codemV2 and exports['codem-inventoryv2'] or exports.ox_inventory

local IMAGE_RESOURCE = codemV2 and 'codem-inventory-images' or 'ox_inventory'
local IMAGE_FOLDER = codemV2 and 'images' or 'web/images'
local IMAGE_URL = ('nui://%s/%s/'):format(IMAGE_RESOURCE, IMAGE_FOLDER)

---@param slot table
---@return string|nil
local function slotLabel(slot)
    if slot.label or not codemV2 then return slot.label end
    local def = ox_inventory:Items(slot.name)
    return def and def.label
end

olink._register('inventory', {
    ---@return table[] SlotData[]
    GetPlayerInventory = function()
        local items = ox_inventory:GetPlayerItems()
        if not items then return {} end
        local result = {}
        for _, item in pairs(items) do
            result[#result + 1] = {
                name     = item.name,
                label    = slotLabel(item),
                count    = item.count,
                slot     = item.slot,
                weight   = item.weight,
                metadata = item.metadata or {},
            }
        end
        return result
    end,

    ---@param item string
    ---@return number
    GetItemCount = function(item)
        return ox_inventory:GetItemCount(item, nil, false) or 0
    end,

    ---@param item string
    ---@param count number|nil
    ---@return boolean
    HasItem = function(item, count)
        return (ox_inventory:GetItemCount(item, nil, false) or 0) >= (count or 1)
    end,

    ---@param item string
    ---@return table {name, label, weight, description}
    GetItemInfo = function(item)
        local data = ox_inventory:Items(item)
        if not data then return {} end
        return { name = data.name or (codemV2 and item or nil), label = data.label, weight = data.weight, description = data.description }
    end,

    ---@param item string
    ---@return string
    GetImagePath = function(item)
        item = olink._stripExt(item)
        local file = LoadResourceFile(IMAGE_RESOURCE, ('%s/%s.png'):format(IMAGE_FOLDER, item))
        if file then return ('%s%s.png'):format(IMAGE_URL, item) end
        if codemV2 and LoadResourceFile(IMAGE_RESOURCE, ('%s/%s.webp'):format(IMAGE_FOLDER, item)) then
            return ('%s%s.webp'):format(IMAGE_URL, item)
        end
        return ''
    end,

    ---@return table All item definitions
    Items = function()
        return ox_inventory:Items() or {}
    end,
})
