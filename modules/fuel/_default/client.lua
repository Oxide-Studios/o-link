-- Default fuel fallback.
-- Uses GTA native fuel level when no dedicated fuel resource is running.

if not olink._guardImpl('Fuel', '_default', false) then return end
if not olink._hasOverride('Fuel') and GetResourceState('BigDaddy-Fuel') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('bigDaddy-Fuel') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('cdn-fuel') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('esx-sna-fuel') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('lc_fuel') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('LegacyFuel') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('legacyfuel') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('okokGasStation') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('ox_fuel') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('oxide-vehicles') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('ps-fuel') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('qb-fuel') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('qs-fuelstations') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('Renewed-Fuel') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('ti_fuel') == 'started' then return end
if not olink._hasOverride('Fuel') and GetResourceState('x-fuel') == 'started' then return end

olink._registerDefault('fuel', {
    GetResourceName = function() return '_default' end,

    GetFuel = function(vehicle)
        if not DoesEntityExist(vehicle) then return 0.0 end
        return GetVehicleFuelLevel(vehicle)
    end,

    SetFuel = function(vehicle, fuel)
        if not DoesEntityExist(vehicle) then return end
        SetVehicleFuelLevel(vehicle, fuel + 0.0)
    end,
})
