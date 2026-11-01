-- Default inventory fallback (client).

if not olink._guardImpl('Inventory', '_default', false) then return end
if not olink._hasOverride('Inventory') and GetResourceState('codem-inventory') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('codem-inventoryv2') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('core_inventory') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('hex_4_inventory') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('jpr-inventory') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('origen_inventory') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('ox_inventory') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('ps-inventory') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('qb-inventory') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('qs-inventory') == 'started' then return end
if not olink._hasOverride('Inventory') and GetResourceState('tgiann-inventory') == 'started' then return end

olink._registerDefault('inventory', {
    GetResourceName = function() return '_default' end,

    HasItem = function() return false end,
    GetItemCount = function() return 0 end,
    GetItemInfo = function() return nil end,
    GetPlayerInventory = function() return {} end,
    Items = function() return {} end,

    GetImagePath = function() return 'https://avatars.githubusercontent.com/u/47620135' end,
    StripPNG = function(item) return (item:gsub('%.png$', '')) end,
    StripWebp = function(item) return (item:gsub('%.webp$', '')) end,
})
