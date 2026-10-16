if not olink._guardImpl('Inventory', 'hex_4_inventory', 'hex_4_inventory') then return end
if not olink._hasOverride('Inventory') and GetResourceState('oxide-inventory') == 'started' then return end

-- hex_4_inventory is a UI layer over the framework's own item store. Its ESX
-- integration reads xPlayer.getInventory()/getLoadout() and writes through
-- addInventoryItem/addWeapon (hex's own server/framework/esx.lua), so item and
-- weapon mutations go through the framework core here too. Hex's exports only
-- cover plate changes and opening arbitrary inventories.
local RESOURCE = 'hex_4_inventory'
local ICON_DIR = 'dist/img/icons'
local FALLBACK_ICON = 'https://avatars.githubusercontent.com/u/47620135'
local DEFAULT_AMMO = 30

local hex = exports[RESOURCE]
local ESX = GetResourceState('es_extended') == 'started' and exports['es_extended']:getSharedObject() or nil
local QBCore = not ESX and GetResourceState('qb-core') == 'started' and exports['qb-core']:GetCoreObject() or nil
local stashes = {}
local weaponIndex
local iconCache = {}

---Weapons live in the ESX loadout, not the `items` table. Index ESX's own
---weapon list, which is also what hex renders its weapon slots from.
---@return table<string, table>
local function getWeaponIndex()
    if weaponIndex and next(weaponIndex) then return weaponIndex end
    weaponIndex = {}
    if not ESX or ESX.GetWeaponList == nil then return weaponIndex end

    local ok, list = pcall(ESX.GetWeaponList)
    if not ok or type(list) ~= 'table' then return weaponIndex end

    for key, data in pairs(list) do
        local name = type(data) == 'table' and (data.name or (type(key) == 'string' and key)) or nil
        if type(name) == 'string' and name ~= '' and name:upper() ~= 'WEAPON_UNARMED' then
            weaponIndex[name:lower()] = { native = name:upper(), label = data.label or name }
        end
    end
    return weaponIndex
end

---@param item string
---@return string|nil native, string|nil label
local function resolveWeapon(item)
    if type(item) ~= 'string' or item == '' then return nil end
    local key = item:lower()
    local entry = getWeaponIndex()[key]
    if entry then return entry.native, entry.label end

    -- A real `items` row wins: servers do ship craftable parts named
    -- weapon_something, and those belong in the item store.
    if ESX and ESX.Items and ESX.Items[item] then return nil end

    -- ESX builds can expose an empty or partial weapon list while still using
    -- the loadout API, so trust the weapon_ prefix as a fallback.
    if key ~= 'weapon_unarmed' and key:match('^weapon_[%w_]+$') then
        return key:upper(), item
    end
    return nil
end

---ESX builds disagree on the casing they store loadout names in; hex checks
---both for the same reason. Returns the casing that actually matched.
---@param xPlayer table
---@param native string
---@return boolean, string|nil
local function playerHasWeapon(xPlayer, native)
    if xPlayer.hasWeapon == nil then return false end
    for _, name in ipairs({ native:upper(), native:lower() }) do
        local ok, has = pcall(xPlayer.hasWeapon, name)
        if ok and has then return true, name end
    end
    return false
end

---@param src number
---@param item string
---@return number
local function getTotalCount(src, item)
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return 0 end
        local native = resolveWeapon(item)
        if native then return playerHasWeapon(xPlayer, native) and 1 or 0 end
        local data = xPlayer.getInventoryItem(item)
        return (data and data.count) or 0
    end
    if QBCore then
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return 0 end
        local total = 0
        for _, v in pairs(player.PlayerData.items or {}) do
            if v and v.name == item then
                total = total + (v.amount or v.count or 0)
            end
        end
        return total
    end
    return 0
end

---@param item string
---@return table|nil
local esxItems = nil

local function getItemDefinition(item)
    if ESX then
        local native, label = resolveWeapon(item)
        if native then
            return { name = item, label = label, weight = 0, type = 'weapon', unique = true }
        end
        -- ESX fills its item list from the database after it starts, so the copy in the shared
        -- object taken when this file loaded is empty; ask ESX for the live list instead.
        if not esxItems or esxItems[item] == nil then
            local ok, items = pcall(ESX.GetItems)
            if ok and type(items) == 'table' and next(items) ~= nil then esxItems = items end
        end
        return esxItems and esxItems[item] or (ESX.Items and ESX.Items[item])
    end
    if QBCore then
        return QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[item]
    end
    return nil
end

olink._register('inventory', {
    -- GetStashItems cannot read contents here, so an empty list proves nothing.
    CanReadStashes = function() return false end,
    ---@return string
    GetResourceName = function()
        return RESOURCE
    end,

    ---@param src number
    ---@param item string
    ---@return number
    GetItemCount = function(src, item)
        return getTotalCount(src, item)
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    AddItem = function(src, item, count, slot, metadata)
        if ESX then
            local xPlayer = ESX.GetPlayerFromId(src)
            if not xPlayer then return false end

            local native = resolveWeapon(item)
            if native then
                -- The ESX loadout holds one of each weapon.
                if playerHasWeapon(xPlayer, native) then return false end

                local ammo = tonumber(metadata and (metadata.ammo or metadata.ammoCount)) or DEFAULT_AMMO
                local ok, err = pcall(xPlayer.addWeapon, native, ammo)
                if not ok then
                    print(('^1[o-link] hex_4_inventory: ESX addWeapon failed for %s (player %s): %s^0')
                        :format(native, tostring(src), tostring(err)))
                    return false
                end

                if not playerHasWeapon(xPlayer, native) then
                    print(('^1[o-link] hex_4_inventory: ESX did not add %s to player %s loadout.^0')
                        :format(native, tostring(src)))
                    return false
                end
                return true
            end

            if xPlayer.canCarryItem and not xPlayer.canCarryItem(item, count) then return false end
            xPlayer.addInventoryItem(item, count)
            return true
        end
        if QBCore then
            local player = QBCore.Functions.GetPlayer(src)
            if not player then return false end
            local success = player.Functions.AddItem(item, count, slot, metadata)
            return success and true or false
        end
        return false
    end,

    ---@param src number
    ---@param item string
    ---@param count number
    ---@param slot number|nil
    ---@param metadata table|nil
    ---@return boolean
    RemoveItem = function(src, item, count, slot, metadata)
        if ESX then
            local xPlayer = ESX.GetPlayerFromId(src)
            if not xPlayer then return false end

            local native = resolveWeapon(item)
            if native then
                local has, matched = playerHasWeapon(xPlayer, native)
                if not has then return false end
                local ok, err = pcall(xPlayer.removeWeapon, matched)
                if not ok then
                    print(('^1[o-link] hex_4_inventory: ESX removeWeapon failed for %s (player %s): %s^0')
                        :format(native, tostring(src), tostring(err)))
                    return false
                end
                return not playerHasWeapon(xPlayer, native)
            end

            local data = xPlayer.getInventoryItem(item)
            if ((data and data.count) or 0) < count then return false end
            xPlayer.removeInventoryItem(item, count)
            return true
        end
        if QBCore then
            local player = QBCore.Functions.GetPlayer(src)
            if not player then return false end
            local success = player.Functions.RemoveItem(item, count, slot)
            return success and true or false
        end
        return false
    end,

    ---@param src number
    ---@param slot number
    ---@return table|nil SlotData (base ESX has no slot storage; QB only)
    GetItemBySlot = function(src, slot)
        if not QBCore then return nil end
        local player = QBCore.Functions.GetPlayer(src)
        local data = player and player.PlayerData.items and player.PlayerData.items[slot]
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
        local result = olink.framework.GetPlayerInventory(src) or {}
        if not ESX then return result end

        -- ESX keeps weapons in the loadout, so they are absent from the
        -- framework's item list. Append them as unique slots.
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer or xPlayer.getLoadout == nil then return result end

        local ok, loadout = pcall(xPlayer.getLoadout)
        if not ok or type(loadout) ~= 'table' then return result end

        for _, weapon in pairs(loadout) do
            if weapon and type(weapon.name) == 'string' then
                local metadata = {
                    ammo = tonumber(weapon.ammo) or 0,
                    components = weapon.components or {},
                    tintIndex = weapon.tintIndex or 0,
                }
                result[#result + 1] = {
                    name     = weapon.name:lower(),
                    label    = weapon.label or weapon.name,
                    count    = 1,
                    slot     = #result + 1,
                    weight   = 0,
                    metadata = metadata,
                    type     = 'weapon',
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
        return getTotalCount(src, item) >= (count or 1)
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
        -- 'fraction' is hex's documented type for arbitrary named shared storage.
        -- weight = false disables hex's cap; hex weight units are undocumented,
        -- so registered stash weights are not forwarded.
        hex:OpenInventory(src, {
            id     = stashId,
            type   = 'fraction',
            title  = tbl.label or stashId,
            weight = false,
        })
    end,

    ---Open another player's inventory alongside the caller's own — the police
    ---search flow. 'player' is hex's documented type for this, keyed by the
    ---target's server id. Hex resolves the player object from that id, so it is
    ---passed as a number rather than a string.
    ---@param src number Player doing the searching
    ---@param targetSrc number Player being searched
    ---@return boolean
    OpenPlayerInventory = function(src, targetSrc)
        src, targetSrc = tonumber(src), tonumber(targetSrc)
        if not src or not targetSrc then return false end
        if GetPlayerName(targetSrc) == nil then return false end

        local ok, result = pcall(function()
            return hex:OpenInventory(src, {
                id    = targetSrc,
                type  = 'player',
                title = GetPlayerName(targetSrc) or tostring(targetSrc),
            })
        end)
        if not ok then
            print(('^1[o-link] hex_4_inventory: OpenInventory failed for player %s: %s^0')
                :format(tostring(targetSrc), tostring(result)))
            return false
        end
        -- Hex returns a success boolean; treat only an explicit false as failure
        -- so an undocumented nil return does not report a search that did open.
        return result ~= false
    end,

    ---@param item string
    ---@return table
    GetItemInfo = function(item)
        local data = getItemDefinition(item)
        if not data then return {} end
        return {
            name = data.name or item,
            label = data.label,
            weight = data.weight,
            description = data.description,
            stack = data.unique == nil and true or (not data.unique),
            image = olink.inventory.GetImagePath and olink.inventory.GetImagePath(item) or nil,
        }
    end,

    ---@param item string
    ---@return string
    GetImagePath = function(item)
        item = olink._stripExt(item)
        local cached = iconCache[item]
        if cached then return cached end

        -- Hex ships weapon icons uppercase (WEAPON_PISTOL.png) and item icons
        -- lowercase. Filenames are case-sensitive on Linux hosts, so try the
        -- name as given plus both casings before giving up.
        local seen, path = {}, nil
        for _, name in ipairs({ item, item:upper(), item:lower() }) do
            if not seen[name] then
                seen[name] = true
                local rel = ('%s/%s.png'):format(ICON_DIR, name)
                if LoadResourceFile(RESOURCE, rel) then
                    path = ('nui://%s/%s'):format(RESOURCE, rel)
                    break
                end
            end
        end

        path = path or FALLBACK_ICON
        iconCache[item] = path
        return path
    end,

    ---@return table All item definitions
    Items = function()
        if QBCore then return (QBCore.Shared and QBCore.Shared.Items) or {} end
        if not ESX then return {} end

        local items = {}
        for name, data in pairs(ESX.Items or {}) do
            if type(data) == 'table' then items[name] = data end
        end

        -- Weapons are not in the `items` table, so consumers that build item
        -- pickers or validate configured names never see them otherwise.
        for name, entry in pairs(getWeaponIndex()) do
            if not items[name] then
                items[name] = { name = name, label = entry.label, weight = 0, type = 'weapon', unique = true }
            end
        end
        return items
    end,

    ---@param src number
    ---@param item string
    ---@param count number|nil
    ---@return boolean
    CanCarryItem = function(src, item, count)
        if ESX then
            -- A missing xPlayer stays permissive, as it did before weapons
            -- were handled here; AddItem still fails on its own.
            local xPlayer = ESX.GetPlayerFromId(src)
            if not xPlayer then return true end
            local native = resolveWeapon(item)
            if native then return not playerHasWeapon(xPlayer, native) end
            if xPlayer.canCarryItem then
                return xPlayer.canCarryItem(item, count or 1) == true
            end
        end
        return true
    end,

    ---@param oldPlate string
    ---@param newPlate string
    ---@return boolean
    UpdatePlate = function(oldPlate, newPlate)
        hex:ChangeInventoryPlate(oldPlate, newPlate)
        if GetResourceState('jg-mechanic') == 'started' then
            exports['jg-mechanic']:vehiclePlateUpdated(oldPlate, newPlate)
        end
        return true
    end,

    -- Unsupported features (no documented hex export; base framework has no path)
    SetMetadata = function() return false end,
    GetStashItems = function() return {} end,
    RemoveStashItem = function() return false end,
    ClearStash = function() return false end,
    AddTrunkItems = function() return false end,
    OpenShop = function() end,
    RegisterShop = function() return false end,
})
