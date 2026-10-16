-- Default inventory fallback.
-- Provides stash bookkeeping and stubs for the full inventory API when no
-- dedicated inventory resource is running.

if not olink._guardImpl('Inventory', '_default', false) then return end
if not olink._hasOverride('Inventory') and GetResourceState('codem-inventory') == 'started' then return end
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

local stashes = {}

olink._registerDefault('inventory', {
    -- GetStashItems cannot read contents here, so an empty list proves nothing.
    CanReadStashes = function() return false end,
    GetResourceName = function() return '_default' end,
    Stashes = stashes,

    AddItem = function() return false end,
    RemoveItem = function() return false end,
    HasItem = function() return false end,
    GetItemCount = function() return 0 end,
    GetItemBySlot = function() return nil end,
    GetItemInfo = function() return nil end,
    GetPlayerInventory = function() return {} end,
    SetMetadata = function() return false end,
    CanCarryItem = function() return true end,
    AddTrunkItems = function() return false end,
    OpenStash = function() return false end,
    OpenPlayerInventory = function() return false end,
    UpdatePlate = function() return false end,
    OpenShop = function() return false end,
    RegisterShop = function() return false end,

    ClearStash = function(id)
        if stashes[id] then stashes[id] = nil end
        return false
    end,

    GetStashItems = function() return {} end,
    RemoveStashItem = function() return false end,

    RegisterStash = function(id, label, slots, weight, owner, groups, coords)
        if stashes[id] then return true, id end
        stashes[id] = {
            id = id, label = label, slots = slots, weight = weight,
            owner = owner, groups = groups, coords = coords,
        }
        return true, id
    end,

    Items = function() return {} end,

    GetImagePath = function() return 'https://avatars.githubusercontent.com/u/47620135' end,
    StripPNG = function(item) return (item:gsub('%.png$', '')) end,
    StripWebp = function(item) return (item:gsub('%.webp$', '')) end,
})
