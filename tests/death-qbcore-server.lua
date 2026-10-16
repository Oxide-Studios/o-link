-- The QBCore server death relay: it reports what the sender's metadata holds once the hospital
-- event's handlers have run, never the event's argument; a bleed-out goes from downed to dead
-- without a revive; reads are queued once per player per tick and capped per player.
-- Run from the o-link folder: lua tests/death-qbcore-server.lua
local rawprint = print
local netHandlers, handlers, emitted, timers, players = {}, {}, {}, {}, {}
local clock = 0

Config = { Debug = false, Overrides = {} }
IsDuplicityVersion = function() return true end
GetResourceState = function(name) return name == 'qb-core' and 'started' or 'missing' end
GetGameTimer = function() return clock end
print = function() end

local QBCore = { Functions = { GetPlayer = function(src) return players[src] end } }
exports = setmetatable({}, {
    __call = function() end,
    __index = function(_, resource)
        if resource ~= 'qb-core' then error(('No such export resource %s'):format(resource)) end
        return { GetCoreObject = function() return QBCore end }
    end,
})

RegisterNetEvent = function(name, fn) if fn then netHandlers[name] = fn end end
AddEventHandler = function(name, fn) handlers[name] = fn end
TriggerEvent = function(name, ...)
    if name:find('^olink:server:') then emitted[#emitted + 1] = { name = name, args = { ... } } end
end
SetTimeout = function(ms, fn) timers[#timers + 1] = { ms = ms, fn = fn } end

dofile('core/shared.lua')
dofile('core/defaults_server.lua')
dofile('modules/death/qb-core/server.lua')

local function Player(src)
    players[src] = { PlayerData = { source = src, metadata = { isdead = false, inlaststand = false } } }
    return players[src].PlayerData.metadata
end

-- A client event from `src`. The ambulance resource's own handler writes the metadata first.
local function Report(src, event, write)
    if write then write() end
    source = src
    netHandlers[event](true)
    source = nil
end

-- Run the queued next-tick reads; with `settle`, the waiting 'alive' timers as well.
local function Tick(settle)
    local due = timers
    timers = {}
    for _, t in ipairs(due) do
        if t.ms == 0 or settle then t.fn() else timers[#timers + 1] = t end
    end
end

local function States(src)
    local out = {}
    for _, e in ipairs(emitted) do
        if e.name == 'olink:server:playerDeathStateChanged' and e.args[1] == src then
            out[#out + 1] = e.args[3] .. '>' .. e.args[2]
        end
    end
    return table.concat(out, ' ')
end

local function Revives()
    local n = 0
    for _, e in ipairs(emitted) do if e.name == 'olink:server:playerRevived' then n = n + 1 end end
    return n
end

assert(netHandlers['hospital:server:SetDeathStatus'] and netHandlers['hospital:server:SetLaststandStatus'], 'both hospital events are heard')

-- Down, then bleed out in two separate ticks: no revive in between.
local meta = Player(5)
Report(5, 'hospital:server:SetLaststandStatus', function() meta.inlaststand = true end)
assert(States(5) == '', 'nothing is reported before the next tick')
Tick()
assert(States(5) == 'alive>downed', 'downed once the metadata is read')
Report(5, 'hospital:server:SetLaststandStatus', function() meta.inlaststand = false end)
Tick()
Report(5, 'hospital:server:SetDeathStatus', function() meta.isdead = true end)
Tick()
Tick(true)
assert(States(5) == 'alive>downed downed>dead' and Revives() == 0, 'a bleed-out goes from downed to dead')

-- The same two events in one tick: one read, straight to dead.
emitted = {}
meta = Player(6)
Report(6, 'hospital:server:SetLaststandStatus', function() meta.inlaststand = true end)
Tick()
Report(6, 'hospital:server:SetLaststandStatus', function() meta.inlaststand = false end)
Report(6, 'hospital:server:SetDeathStatus', function() meta.isdead = true end)
assert(#timers == 1, 'two events in one tick queue one read')
Tick()
Tick(true)
assert(States(6) == 'alive>downed downed>dead' and Revives() == 0, 'one tick, straight to dead')

-- A revive from downed still arrives once it has settled; a revive from dead arrives at once.
emitted = {}
meta = Player(7)
Report(7, 'hospital:server:SetLaststandStatus', function() meta.inlaststand = true end)
Tick()
Report(7, 'hospital:server:SetLaststandStatus', function() meta.inlaststand = false end)
Tick()
assert(States(7) == 'alive>downed', 'alive after downed waits')
Tick(true)
assert(States(7) == 'alive>downed downed>alive' and Revives() == 1, 'the revive from downed arrives')
Report(7, 'hospital:server:SetDeathStatus', function() meta.isdead = true end)
Tick()
Report(7, 'hospital:server:SetDeathStatus', function() meta.isdead = false end)
Tick()
assert(States(7) == 'alive>downed downed>alive alive>dead dead>alive', 'a revive from dead is not held')

-- The argument is never trusted: an event the metadata does not back reports nothing.
emitted = {}
meta = Player(8)
Report(8, 'hospital:server:SetDeathStatus')
Report(8, 'hospital:server:SetLaststandStatus')
Tick()
Tick(true)
assert(#emitted == 0, 'a claim the metadata does not hold is ignored')

-- Only loaded players are read, and only the sender.
players[9] = nil
Report(9, 'hospital:server:SetDeathStatus')
assert(#timers == 0, 'a sender with no loaded character is ignored')
source = nil
netHandlers['hospital:server:SetDeathStatus'](true)
assert(#timers == 0, 'an event with no sender is ignored')

-- The rate limit: 20 reads per player in 10 seconds, then nothing until the window moves on.
meta = Player(10)
local reads = 0
for _ = 1, 25 do
    Report(10, 'hospital:server:SetDeathStatus')
    reads = reads + #timers
    Tick()
end
assert(reads == 20, 'capped at 20 reads in the window')
clock = clock + 10000
Report(10, 'hospital:server:SetDeathStatus', function() meta.isdead = true end)
Tick()
assert(States(10) == 'alive>dead', 'reads resume once the window has passed')

-- A player who leaves starts over.
source = 10
handlers.playerDropped()
source = nil
emitted = {}
meta = Player(10)
meta.isdead = true
Report(10, 'hospital:server:SetDeathStatus')
Tick()
assert(States(10) == 'alive>dead', 'state is forgotten when the player drops')

print = rawprint
print('QBCore server death relay passed: metadata over arguments, bleed-out, settle, coalescing, rate limit, drop.')
