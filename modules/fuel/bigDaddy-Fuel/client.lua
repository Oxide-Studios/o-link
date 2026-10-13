-- The resource ships as BigDaddy-Fuel; some servers run it renamed to bigDaddy-Fuel. Resource
-- names are case-sensitive, so use whichever one is running.
local RESOURCE = 'BigDaddy-Fuel'
if GetResourceState(RESOURCE) ~= 'started' and GetResourceState('bigDaddy-Fuel') == 'started' then
    RESOURCE = 'bigDaddy-Fuel'
end

if not olink._guardImpl('Fuel', 'bigDaddy-Fuel', RESOURCE) then return end
if not olink._hasOverride('Fuel') and GetResourceState('oxide-vehicles') == 'started' then return end

olink._register('fuel', {
    ---@return string
    GetResourceName = function()
        return RESOURCE
    end,

    ---@param vehicle number
    ---@return number
    GetFuel = function(vehicle)
        if not DoesEntityExist(vehicle) then return 0.0 end
        return exports[RESOURCE]:GetFuel(vehicle)
    end,

    ---@param vehicle number
    ---@param fuel number
    ---@param type? string
    SetFuel = function(vehicle, fuel, type)
        if not DoesEntityExist(vehicle) then return end
        exports[RESOURCE]:SetFuel(vehicle, fuel)
    end,
})
