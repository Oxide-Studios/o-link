-- The BigDaddy fuel adapter under both spellings of its resource name (BigDaddy-Fuel as shipped,
-- bigDaddy-Fuel renamed), and the _default fallback stepping aside for either.
-- Run from the [oxide] folder: bash oxide-phone/tests/lua.sh o-link tests/fuel-bigdaddy.lua
local rawprint = print
local states, exportsByResource, calls = {}, {}, {}

Config = { Debug = false, Overrides = {} }
IsDuplicityVersion = function() return false end
GetResourceState = function(name) return states[name] or 'missing' end
DoesEntityExist = function() return true end
GetVehicleFuelLevel = function() return 33.0 end
SetVehicleFuelLevel = function() end
print = function() end

exports = setmetatable({}, {
    __call = function() end,
    __index = function(_, resource)
        local res = exportsByResource[resource]
        if not res then error(('No such export resource %s'):format(resource)) end
        return res
    end,
})

local function fuelResource(name, level)
    exportsByResource[name] = {
        GetFuel = function(_, vehicle) calls[#calls + 1] = name return level end,
        SetFuel = function(_, vehicle, fuel) calls[#calls + 1] = name .. ':set' end,
    }
end

local function Load(scenario)
    states, calls = scenario, {}
    dofile('core/shared.lua')
    dofile('core/defaults_client.lua')
    dofile('modules/fuel/_default/client.lua')
    dofile('modules/fuel/bigDaddy-Fuel/client.lua')
end

fuelResource('BigDaddy-Fuel', 71.0)
fuelResource('bigDaddy-Fuel', 52.0)

Load({ ['BigDaddy-Fuel'] = 'started' })
assert(olink.fuel.GetResourceName() == 'BigDaddy-Fuel', 'the shipped name owns fuel')
assert(olink.fuel.GetFuel(1) == 71.0 and calls[1] == 'BigDaddy-Fuel', 'reads the shipped resource')
olink.fuel.SetFuel(1, 50.0)
assert(calls[2] == 'BigDaddy-Fuel:set', 'writes the shipped resource')

Load({ ['bigDaddy-Fuel'] = 'started' })
assert(olink.fuel.GetResourceName() == 'bigDaddy-Fuel', 'a renamed copy owns fuel')
assert(olink.fuel.GetFuel(1) == 52.0 and calls[1] == 'bigDaddy-Fuel', 'reads the renamed resource')

Load({})
assert(olink.fuel.GetResourceName() == '_default', 'neither running leaves the native fallback')
assert(olink.fuel.GetFuel(1) == 33.0, 'native fuel level')

print = rawprint
print('BigDaddy fuel passed: shipped name, renamed copy, native fallback.')
