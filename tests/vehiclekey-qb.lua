-- The qb-vehiclekeys adapter (modules/vehiclekey/qb-vehiclekeys): the client asks the server for
-- keys by network id, and the server grants them through qb-vehiclekeys' GiveKeys export, which
-- works before and after 1.6.0. Keys go only to a requester who owns the vehicle or stands within
-- 7.5 m, always for the plate the server sees; the client's plate only says when to stop waiting.
-- Run from the o-link folder: lua tests/vehiclekey-qb.lua
local passed, failed = 0, 0
local function check(name, ok)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL ' .. name) end
end

local vec = {}
vec.__index = vec
vec.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vec) end
vec.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function v3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vec) end

local now = 0
local started = { ['qb-vehiclekeys'] = true }
local entities, peds, netHandlers, granted = {}, {}, {}, {}

GetGameTimer = function() return now end
GetResourceState = function(name) return started[name] and 'started' or 'missing' end
Wait = function(ms) coroutine.yield(ms) end
RegisterNetEvent = function(name, fn) netHandlers[name] = fn end
NetworkGetEntityFromNetworkId = function(netId) return entities[netId] and netId or 0 end
DoesEntityExist = function(e) return entities[e] ~= nil end
GetEntityType = function(e) return entities[e] and entities[e].type or 0 end
NetworkGetEntityOwner = function(e) return entities[e] and entities[e].owner or -1 end
GetEntityCoords = function(e) return entities[e] and entities[e].coords or peds[e] end
GetPlayerPed = function(src) return peds[src] and src or 0 end
GetVehicleNumberPlateText = function(e) return entities[e] and entities[e].plate end
Entity = function(e) return { state = entities[e] and entities[e].bags or {} } end

local qbKeys = {}
function qbKeys:GiveKeys(src, plate) granted[#granted + 1] = { src = src, plate = plate } end
exports = { ['qb-vehiclekeys'] = qbKeys }

olink = {
    _guardImpl = function() return true end,
    _hasOverride = function() return false end,
    _register = function() end,
}

-- Runs the grant event as `src`. Each Wait advances the clock; `world(t)` changes the world first.
local function Request(src, netId, plate, world)
    granted = {}
    now = 0
    if world then world(0) end
    local co = coroutine.create(function()
        source = src
        netHandlers['o-link:server:vehiclekey:give'](netId, plate)
    end)
    local ok, ms = coroutine.resume(co)
    while ok and coroutine.status(co) ~= 'dead' do
        now = now + (ms or 0)
        if world then world(now) end
        ok, ms = coroutine.resume(co)
    end
    if not ok then error(ms) end
    return granted, now
end

local function Vehicle(netId, fields)
    entities[netId] = {
        type = 2, owner = fields.owner or -1, coords = fields.coords or v3(0, 0, 0),
        plate = fields.plate, bags = fields.bags or {},
    }
end

dofile('modules/vehiclekey/qb-vehiclekeys/server.lua')
check('the grant event is registered on QBCore', netHandlers['o-link:server:vehiclekey:give'] ~= nil)

peds[1] = v3(0, 0, 0)
peds[2] = v3(500, 0, 0)

-- An EMS or police fleet unit: spawned server-side, owned by the medic, plate in the oxide:plate bag
-- while the native still holds GTA's random plate.
Vehicle(10, { owner = 1, plate = '46EEK123', bags = { ['oxide:plate'] = 'EMS4X7Q2' } })
local g, t = Request(1, 10, 'EMS4X7Q2')
check('a fleet unit grants the oxide:plate bag plate at once', #g == 1 and g[1].src == 1 and g[1].plate == 'EMS4X7Q2' and t == 0)

-- A gig-job van the client just spawned, padded plate, before the server knows the entity.
entities[11] = nil
g, t = Request(1, 11, 'PIZZA', function(ms)
    if ms >= 750 and not entities[11] then Vehicle(11, { owner = 1, plate = 'PIZZA   ' }) end
end)
check('a vehicle that reaches the server late still gets keys, trimmed', #g == 1 and g[1].plate == 'PIZZA' and t == 750)

-- A dealership car: the client stamps the plate after the server spawned it, so the native lags.
Vehicle(12, { owner = 1, plate = 'OLDPLATE' })
g, t = Request(1, 12, 'NEW 123', function(ms)
    if ms >= 1000 then entities[12].plate = 'NEW 123 ' end
end)
check('a plate change in flight is waited for', #g == 1 and g[1].plate == 'NEW 123' and t == 1000)

-- Ownership of a server-spawned unit reaches the medic a moment later.
Vehicle(13, { owner = -1, coords = v3(30, 0, 0), bags = { ['oxide:plate'] = 'EMSLATE1' } })
g, t = Request(1, 13, 'EMSLATE1', function(ms)
    if ms >= 500 then entities[13].owner = 1 end
end)
check('late ownership is waited for', #g == 1 and g[1].plate == 'EMSLATE1' and t == 500)

-- Not the owner, but standing next to it: qb-vehiclekeys' own rule.
Vehicle(14, { owner = 3, coords = v3(5, 0, 0), plate = 'NEAR1234' })
g = Request(1, 14, 'NEAR1234')
check('a requester within 7.5 m gets keys', #g == 1 and g[1].plate == 'NEAR1234')

-- Somebody else's car across the map.
Vehicle(15, { owner = 3, coords = v3(0, 0, 0), plate = 'VICTIM01' })
g, t = Request(2, 15, 'VICTIM01')
check('a far requester who does not own it gets nothing', #g == 0 and t >= 5000)

-- A cheater next to their own car asking for another plate gets that car's plate, nothing else.
Vehicle(16, { owner = 1, plate = 'MYCAR123' })
g, t = Request(1, 16, 'VICTIM01')
check('a claimed plate is never granted', #g == 1 and g[1].plate == 'MYCAR123' and t >= 5000)

Vehicle(17, { owner = 1, plate = 'PED12345' })
entities[17].type = 1
g = Request(1, 17, 'PED12345')
check('only vehicles grant keys', #g == 0)

g = Request(1, 'MYCAR123', nil)
check('a plate in place of a network id is refused', #g == 0)
g = Request(1, 0, nil)
check('network id 0 is refused', #g == 0)

g = Request(1, 16, nil)
check('without a plate the server plate is granted at once', #g == 1 and g[1].plate == 'MYCAR123')

-- On Qbox, qbx_vehiclekeys provides qb-vehiclekeys, and its own adapter owns the event.
netHandlers = {}
started.qbx_vehiclekeys = true
dofile('modules/vehiclekey/qb-vehiclekeys/server.lua')
check('the adapter stands down for qbx_vehiclekeys', netHandlers['o-link:server:vehiclekey:give'] == nil)
started.qbx_vehiclekeys = nil

-- Client side: Give sends the network id and plate to that event.
local sent, impl = {}, nil
olink._register = function(namespace, i) if namespace == 'vehiclekey' then impl = i end end
TriggerServerEvent = function(name, ...) sent[#sent + 1] = { name = name, args = { ... } } end
NetworkGetNetworkIdFromEntity = function(e) return entities[e] and e or 0 end
entities[20] = { type = 2, plate = 'EMS4X7Q2' }
dofile('modules/vehiclekey/qb-vehiclekeys/client.lua')
impl.Give(20, 'EMS4X7Q2')
check('Give asks o-link with the network id', #sent == 1 and sent[1].name == 'o-link:server:vehiclekey:give'
    and sent[1].args[1] == 20 and sent[1].args[2] == 'EMS4X7Q2')
sent = {}
impl.Give(20)
check('Give without a plate sends the vehicle plate', sent[1].args[2] == 'EMS4X7Q2')

print(('[vehiclekey-qb] %d passed, %d failed'):format(passed, failed))
if failed > 0 then error('vehiclekey-qb failed') end
