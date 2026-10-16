-- The placement Entity picker never outlines a ped: an outline on a ped crashes the game client
-- (citizenfx/fivem#1425). An aimed ped gets a ring on the ground; objects and vehicles keep the
-- outline, and moving the aim off an outlined entity clears it.
local rawprint = print
local PLAYER, PED, CAR, PROP = 1, 101, 202, 303
local entityTypes = { [PLAYER] = 1, [PED] = 1, [CAR] = 2, [PROP] = 3 }
local aimed, clicked, outlines, markers, threads = nil, false, {}, {}, {}

Config = { Debug = false, Overrides = {} }
IsDuplicityVersion = function() return false end
GetResourceState = function() return 'missing' end
exports = setmetatable({}, { __call = function() end })
print = function() end

local vec = {}
vec.__index = vec
vec.__add = function(a, b) return vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
vec.__mul = function(a, s) return vector3(a.x * s, a.y * s, a.z * s) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vec) end

promise = { new = function() return { resolve = function(self, value) self.done, self.value = true, value end } end }
Citizen = { Await = function(p) while not p.done do coroutine.yield() end return p.value end }
CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
Wait = function() coroutine.yield() end

locale = function(key) return key end
GetResourceKvpString = function() return nil end
SendNUIMessage = function() end
RegisterCommand = function() end
TriggerEvent = function() end
AddEventHandler = function() end
PlacementGizmo = { IsActive = function() return false end }

DisableControlAction = function() end
DisablePlayerFiring = function() end
PlayerId = function() return 0 end
PlayerPedId = function() return PLAYER end
GetGameplayCamCoord = function() return vector3(0.0, 0.0, 30.0) end
GetGameplayCamRot = function() return vector3(-10.0, 0.0, 0.0) end
StartShapeTestRay = function() return 1 end
GetShapeTestResult = function()
    if not aimed then return 2, false, vector3(0.0, 0.0, 0.0), nil, 0 end
    return 2, true, vector3(1.0, 2.0, 3.0), nil, aimed
end
DoesEntityExist = function(entity) return entityTypes[entity] ~= nil end
GetEntityType = function(entity) return entityTypes[entity] or 0 end
GetEntityCoords = function() return vector3(10.0, 20.0, 31.0) end
GetEntityHeading = function() return 90.0 end
GetEntityHeightAboveGround = function() return 1.0 end
SetEntityDrawOutline = function(entity, on)
    if on and GetEntityType(entity) == 1 then error('SetEntityDrawOutline reached a ped') end
    outlines[entity] = on or nil
end
SetEntityDrawOutlineColor = function() end
SetEntityDrawOutlineShader = function() end
DrawMarker = function(kind, x, y, z) markers[#markers + 1] = { kind = kind, z = z } end
IsDisabledControlJustPressed = function(_, control) return control == 24 and clicked end
IsControlJustPressed = function() return false end

dofile('core/shared.lua')
dofile('core/defaults_client.lua')
dofile('modules/placement/client.lua')

local function step()
    for i = #threads, 1, -1 do
        local ok, err = coroutine.resume(threads[i])
        if not ok then error(err, 0) end
        if coroutine.status(threads[i]) == 'dead' then table.remove(threads, i) end
    end
end

local function frame(target)
    aimed, markers = target, {}
    step()
end

local function ringDrawn()
    for _, m in ipairs(markers) do
        if m.kind == 25 then return m end
    end
end

local result
local picker = coroutine.create(function() result = olink.placement.Entity() end)
assert(coroutine.resume(picker))

frame(PED)
local ring = ringDrawn()
assert(ring, 'an aimed ped gets a ring on the ground')
assert(math.abs(ring.z - 30.03) < 1e-6, 'the ring sits on the ground under the ped')
assert(next(outlines) == nil, 'no outline on an aimed ped')

frame(PROP)
assert(outlines[PROP] and not ringDrawn(), 'an aimed object is outlined, with no ring')

frame(PED)
assert(outlines[PROP] == nil and next(outlines) == nil, 'aiming from the object to a ped clears its outline')

frame(CAR)
assert(outlines[CAR], 'an aimed vehicle is outlined')

frame(PED)
clicked = true
frame(PED)
assert(coroutine.resume(picker))
assert(coroutine.status(picker) == 'dead', 'the picker returns once a ped is selected')
assert(result and result.x == 10.0 and result.z == 31.0 and result.w == 90.0, 'selecting a ped returns its origin and heading')
assert(next(outlines) == nil, 'nothing stays outlined after the pick')

print = rawprint
print('Placement Entity picker passed: ped ground ring, object and vehicle outlines, no ped outline.')
