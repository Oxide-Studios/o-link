-- Server needs on Oxide Core: the oxide-needs adapter loads whether oxide-needs starts before or
-- after o-link, reads oxide-needs at call time, and stays out of the way on other frameworks.
-- Run from the [oxide] folder: bash oxide-phone/tests/lua.sh o-link tests/needs-server.lua
local rawprint = print
local output, states, exportsByResource = {}, {}, {}

Config = { Debug = false, Overrides = {} }
IsDuplicityVersion = function() return true end
GetResourceState = function(name) return states[name] or 'missing' end
print = function(...) output[#output + 1] = table.concat({ ... }, ' ') end

exports = setmetatable({}, {
    __call = function() end,
    __index = function(_, resource)
        return setmetatable({}, {
            __index = function(_, fn)
                return function(_, ...)
                    local res = exportsByResource[resource]
                    if not res or not res[fn] then error(('No such export %s in resource %s'):format(fn, resource)) end
                    return res[fn](...)
                end
            end,
        })
    end,
})

local needs = {}
exportsByResource['oxide-needs'] = {
    GetNeed = function(src, needType) return needs[src] and needs[src][needType] end,
    SetNeed = function(src, needType, value)
        if not needs[src] then return false end
        needs[src][needType] = value
        return true
    end,
    ModifyNeed = function(src, needType, amount)
        if not needs[src] then return false end
        needs[src][needType] = needs[src][needType] + amount
        return true
    end,
}
exportsByResource['qb-core'] = {
    GetCoreObject = function()
        return { Functions = { GetPlayer = function() return { PlayerData = { metadata = { hunger = 42 } } } end } }
    end,
}

local ADAPTERS = { 'es_extended', 'oxide-needs', 'qb-core', 'qbx_core' }

---@param scenario table<string, string> resource states when o-link loads
local function Load(scenario)
    states, output = scenario, {}
    dofile('core/shared.lua')
    dofile('core/defaults_server.lua')
    for _, impl in ipairs(ADAPTERS) do dofile(('modules/needs/%s/server.lua'):format(impl)) end
end

local function Provider()
    local caps = olink._getCapabilities().needs
    return caps and caps.kind, caps and caps.provider
end

-- Oxide Core, oxide-needs starting after o-link (it depends on o-link-started resources) -------
Load({ ['oxide-core'] = 'started', ['oxide-needs'] = 'stopped' })
local kind, provider = Provider()
assert(kind == 'real' and provider == 'oxide-needs', 'the adapter loads before oxide-needs has started')
needs[1] = { hunger = 80, thirst = 60, stress = 10 }
assert(olink.needs.GetNeed(1, 'hunger') == nil, 'nothing is read while oxide-needs is stopped')
assert(olink.needs.SetNeed(1, 'hunger', 50) == false and needs[1].hunger == 80, 'nothing is written while oxide-needs is stopped')

states['oxide-needs'] = 'started'
assert(olink.needs.GetNeed(1, 'hunger') == 80, 'GetNeed reads oxide-needs once it is running')
assert(olink.needs.SetNeed(1, 'thirst', 25) == true and needs[1].thirst == 25, 'SetNeed writes through')
assert(olink.needs.ModifyNeed(1, 'stress', 5) == true and needs[1].stress == 15, 'ModifyNeed writes through')
assert(olink.needs.SetNeed(2, 'hunger', 10) == false, 'a player oxide-needs does not know reads false')
assert(olink.needs.GetNeed(2, 'hunger') == nil, 'and has no needs')

local saved = exportsByResource['oxide-needs']
exportsByResource['oxide-needs'] = nil
assert(olink.needs.GetNeed(1, 'hunger') == nil and olink.needs.ModifyNeed(1, 'hunger', 1) == false, 'an export error reads as nothing')
exportsByResource['oxide-needs'] = saved
assert(#output == 0, 'no fallback warnings on Oxide Core: ' .. table.concat(output, ' | '))

-- Oxide Core, oxide-needs already running when o-link loads ---------------------------------------
Load({ ['oxide-core'] = 'started', ['oxide-needs'] = 'started' })
kind, provider = Provider()
assert(kind == 'real' and provider == 'oxide-needs', 'the adapter loads when oxide-needs started first')
assert(olink.needs.GetNeed(1, 'thirst') == 25, 'and reads it')

-- Oxide Core without oxide-needs -------------------------------------------------------------------
Load({ ['oxide-core'] = 'started' })
kind = Provider()
assert(kind == 'fallback', 'no oxide-needs leaves the fallback defaults')

-- QBCore with an oxide-needs folder present but not running ---------------------------------------
Load({ ['qb-core'] = 'started', ['oxide-needs'] = 'stopped' })
assert(olink.needs.GetNeed(1, 'hunger') == 42, 'qb-core owns needs when oxide-core is not running')

print = rawprint
print('Server needs passed: oxide-needs before or after o-link, export failures, no oxide-needs, other frameworks.')
