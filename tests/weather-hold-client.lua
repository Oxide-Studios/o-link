-- The local weather hold (modules/weather/_default/client.lua): a hold pauses the provider's sync,
-- puts the clock back after the provider moves it, keeps the held weather and stops the rain; holds
-- belong to the calling resource; the last release resumes the provider; a stopping resource's hold
-- is released.
-- Run from the [oxide] folder: bash oxide-phone/tests/lua.sh o-link tests/weather-hold-client.lua
local passed, failed = 0, 0
local function check(name, ok)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL ' .. name) end
end

-- A tiny scheduler: CreateThread runs coroutines, Wait yields for game milliseconds.
local now, threads = 0, {}
GetGameTimer = function() return now end
CreateThread = function(fn) threads[#threads + 1] = { co = coroutine.create(fn), at = now } end
Wait = function(ms) coroutine.yield(ms or 0) end
local function run(ms)
    local stop = now + ms
    while now <= stop do
        for i = #threads, 1, -1 do
            local t = threads[i]
            if coroutine.status(t.co) == 'dead' then table.remove(threads, i)
            elseif t.at <= now then
                local ok, delay = coroutine.resume(t.co)
                if not ok then error(delay) end
                t.at = now + (delay or 0)
            end
        end
        now = now + 10
    end
end

joaat = function(name)
    local h = 0
    for i = 1, #name do h = (h * 31 + name:upper():byte(i)) % 4294967296 end
    return h
end
GetHashKey = joaat

local clock = { h = 14, m = 30, s = 0 }
local msPerMinute = 2000
local weather, rain, persist = joaat('RAIN'), 0.6, nil
local invoker = 'oxide-containers'
local syncCalls = {}
local handlers = {}

Config = { Debug = false, Overrides = {} }
IsDuplicityVersion = function() return false end
GetResourceState = function() return 'missing' end
GetInvokingResource = function() return invoker end
GetCurrentResourceName = function() return 'o-link' end
GetClockHours = function() return clock.h end
GetClockMinutes = function() return clock.m end
GetClockSeconds = function() return clock.s end
GetMillisecondsPerGameMinute = function() return msPerMinute end
NetworkOverrideClockTime = function(h, m, s) clock = { h = h, m = m, s = s } end
NetworkOverrideClockMillisecondsPerGameMinute = function(ms) msPerMinute = ms end
GetPrevWeatherType = function() return weather end
GetPrevWeatherTypeHashName = function() return weather end
SetWeatherTypeNowPersist = function(name) weather, persist = joaat(name), name end
ClearWeatherTypePersist = function() persist = nil end
SetRainLevel = function(v) rain = v end
PlayerPedId = function() return 1 end
AddEventHandler = function(name, fn)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], fn)
end
exports = function() end

dofile('core/shared.lua')
dofile('core/defaults_client.lua')

-- o-link loads _default first (the glob sorts it ahead of the providers), then the provider.
local handle = assert(io.open('modules/weather/_default/client.lua', 'r'))
local source = handle:read('a')
handle:close()
source = source:gsub('`([^`]+)`', function(name) return ('joaat(%q)'):format(name) end)
assert(load(source, '@modules/weather/_default/client.lua'))()

-- A provider whose pause moves the clock to 18:00, as qb-weathersync's DisableSync does.
olink._register('weather', {
    GetResourceName = function() return 'qb-weathersync' end,
    ToggleSync = function(enabled, owner)
        syncCalls[#syncCalls + 1] = { enabled = enabled, owner = owner }
        if not enabled then clock = { h = 18, m = 0, s = 0 } end
    end,
}, 'qb-weathersync')

local W = olink.weather
check('hold and release are registered', type(W.HoldLocalWeather) == 'function' and type(W.ReleaseLocalWeather) == 'function')
check('an unknown weather type is refused', W.HoldLocalWeather('PURPLE') == false)

check('hold accepted', W.HoldLocalWeather() == true)
run(1200)
check('the provider was paused once, by o-link', #syncCalls == 1 and syncCalls[1].enabled == false and syncCalls[1].owner == 'o-link:localweather')
check('the clock is back near where it was, not 18:00', clock.h == 14 and clock.m >= 30 and clock.m <= 31)
check('minute length kept', msPerMinute == 2000)
check('clear weather held', persist == 'EXTRASUNNY')
check('rain stopped', rain == 0.0)

invoker = 'other-resource'
check('a second resource holds too', W.HoldLocalWeather('CLOUDS') == true)
run(1100)
check('the newest hold shows', persist == 'CLOUDS')
check('no second pause', #syncCalls == 1)

invoker = 'oxide-containers'
check('first resource releases', W.ReleaseLocalWeather() == true)
run(1100)
check('still held by the other resource', persist == 'CLOUDS' and #syncCalls == 1)
check('releasing twice says false', W.ReleaseLocalWeather() == false)

for _, fn in ipairs(handlers.onClientResourceStop or {}) do fn('other-resource') end
run(100)
check('a stopping resource releases its hold and the provider resumes', #syncCalls == 2 and syncCalls[2].enabled == true and syncCalls[2].owner == 'o-link:localweather')
check('rain level handed back', rain == -1.0)
check('persist cleared', persist == nil)

print(('[weather-hold] %d passed, %d failed'):format(passed, failed))
if failed > 0 then error('weather hold tests failed') end
