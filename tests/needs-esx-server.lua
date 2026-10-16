-- Server needs on ESX: esx_status values on the 0-100 scale, and stress read like any other need,
-- so it is nil and cannot be set on stock ESX (as on the client) and real where a server
-- registers a `stress` status.
-- Run from the o-link folder: lua tests/needs-esx-server.lua
local rawprint = print
local players, sent = {}, {}

Config = { Debug = false, Overrides = {} }
IsDuplicityVersion = function() return true end
GetResourceState = function(name) return name == 'es_extended' and 'started' or 'missing' end
TriggerClientEvent = function(name, src, needType, value) sent[#sent + 1] = { name, src, needType, value } end
print = function() end

local ESX = {
    GetPlayerFromId = function(src)
        local status = players[src]
        if not status then return nil end
        return { get = function(key) if key == 'status' then return status end end }
    end,
}
exports = setmetatable({}, {
    __call = function() end,
    __index = function(_, resource)
        if resource ~= 'es_extended' then error(('No such export resource %s'):format(resource)) end
        return { getSharedObject = function() return ESX end }
    end,
})

dofile('core/shared.lua')
dofile('core/defaults_server.lua')
dofile('modules/needs/es_extended/server.lua')

-- Stock ESX: esx_basicneeds registers hunger and thirst only.
players[1] = { { name = 'hunger', val = 500000, percent = 50 }, { name = 'thirst', val = 250000, percent = 25 } }
assert(olink.needs.GetNeed(1, 'hunger') == 50 and olink.needs.GetNeed(1, 'thirst') == 25, 'hunger and thirst on the 0-100 scale')
assert(olink.needs.GetNeed(1, 'stress') == nil, 'stock ESX has no stress: nil, as on the client')
assert(olink.needs.SetNeed(1, 'stress', 40) == false and olink.needs.ModifyNeed(1, 'stress', 5) == false, 'and it cannot be set')
assert(#sent == 0, 'nothing is sent for a need the player has no status for')
assert(olink.needs.SetNeed(1, 'hunger', 80) == true and sent[1][1] == 'esx_status:set' and sent[1][4] == 800000, 'hunger is set on the esx scale')

-- A server that registers a stress status.
players[2] = { { name = 'hunger', val = 1000000 }, { name = 'thirst', val = 1000000 }, { name = 'stress', val = 300000 } }
assert(olink.needs.GetNeed(2, 'stress') == 30, 'a registered stress status reads its real value')
assert(olink.needs.ModifyNeed(2, 'stress', -10) == true and sent[#sent][1] == 'esx_status:remove' and sent[#sent][4] == 100000, 'and can be changed')

-- No player.
assert(olink.needs.GetNeed(3, 'hunger') == nil and olink.needs.GetNeed(3, 'stress') == nil, 'no player reads nil')

print = rawprint
print('ESX server needs passed: 0-100 scale, stress nil on stock ESX, real with a stress status.')
