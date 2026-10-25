if not olink._guardImpl('VehicleKey', 'qb-vehiclekeys', 'qb-vehiclekeys') then return end
if not olink._hasOverride('VehicleKey') and GetResourceState('oxide-vehicles') == 'started' then return end
-- qbx_vehiclekeys provides qb-vehiclekeys, and its adapter owns this event on Qbox.
if not olink._hasOverride('VehicleKey') and GetResourceState('qbx_vehiclekeys') == 'started' then return end

-- qb-vehiclekeys 1.6.0 only lets a client claim keys within 7.5 m of the vehicle.
local GRANT_DISTANCE = 7.5
local GRANT_WAIT_MS = 5000

---@param value string|nil
---@return string|nil
local function trim(value)
    return value and value:match('^%s*(.-)%s*$') or nil
end

---@param value string
---@return string
local function comparable(value)
    return (value:gsub('%s+', '')):upper()
end

-- Oxide fleet vehicles spawn server-side and take their plate from the first
-- client that decorates them, so the server-written oxide:plate bag is right
-- before the native is.
---@param vehicle number Entity handle
---@return string|nil
local function vehiclePlate(vehicle)
    local plate = Entity(vehicle).state['oxide:plate']
    if type(plate) ~= 'string' or plate == '' then
        plate = GetVehicleNumberPlateText(vehicle)
    end
    plate = trim(plate)
    return plate ~= '' and plate or nil
end

-- The requester must network-own the vehicle or stand within qb-vehiclekeys'
-- own distance, so this does not reopen the any-plate grant 1.6.0 closed.
---@param src number
---@param netId number
---@return number|nil vehicle
local function grantableVehicle(src, netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    if GetEntityType(vehicle) ~= 2 then return nil end
    if NetworkGetEntityOwner(vehicle) == src then return vehicle end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= GRANT_DISTANCE then return vehicle end
    return nil
end

-- A vehicle the client just spawned or checked out can reach the server after
-- this event, and its owner and plate can follow later still, so wait briefly.
-- The client's plate only decides when to stop waiting; keys always go to the
-- plate the server sees.
RegisterNetEvent('o-link:server:vehiclekey:give', function(netId, expectedPlate)
    local src = source
    if type(netId) ~= 'number' or netId == 0 then return end
    local wanted = type(expectedPlate) == 'string' and comparable(expectedPlate) or nil

    local plate
    local deadline = GetGameTimer() + GRANT_WAIT_MS
    repeat
        local vehicle = grantableVehicle(src, netId)
        plate = vehicle and vehiclePlate(vehicle) or nil
        if plate and (not wanted or comparable(plate) == wanted) then break end
        Wait(250)
    until GetGameTimer() >= deadline

    if not plate then return end
    exports['qb-vehiclekeys']:GiveKeys(src, plate)
end)
