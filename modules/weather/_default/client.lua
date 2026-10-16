-- Default weather fallback.
-- Uses GTA native clock/weather readers when no dedicated sync resource is running.

local weatherNames = {
    [`EXTRASUNNY`] = 'EXTRASUNNY',
    [`CLEAR`] = 'CLEAR',
    [`NEUTRAL`] = 'NEUTRAL',
    [`SMOG`] = 'SMOG',
    [`FOGGY`] = 'FOGGY',
    [`OVERCAST`] = 'OVERCAST',
    [`CLOUDS`] = 'CLOUDS',
    [`CLEARING`] = 'CLEARING',
    [`RAIN`] = 'RAIN',
    [`THUNDER`] = 'THUNDER',
    [`SNOW`] = 'SNOW',
    [`BLIZZARD`] = 'BLIZZARD',
    [`SNOWLIGHT`] = 'SNOWLIGHT',
    [`XMAS`] = 'XMAS',
    [`HALLOWEEN`] = 'HALLOWEEN',
}

-- Rain and cover are engine reads that the sync resources leave alone, so they are
-- registered under every provider, before the provider guards below. oxide-weather
-- implements them itself and overwrites these keys. The fallback IsRainingAt reads
-- the engine's current weather type and ignores coords.
local rainWeathers = { [`RAIN`] = true, [`THUNDER`] = true, [`CLEARING`] = true }

local function toPoint(coords)
    if coords == nil then return GetEntityCoords(PlayerPedId()) end
    local kind = type(coords)
    if kind ~= 'table' and kind ~= 'vector3' and kind ~= 'vector4' then return nil end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not (x and y and z) then return nil end
    return vector3(x + 0.0, y + 0.0, z + 0.0)
end

-- Upward line-of-sight probe against world and object collision, the same test
-- oxide-weather runs. nil when collision is not streamed here or the probe never resolves.
local function probeCover(at)
    local ped = PlayerPedId()
    if #(GetEntityCoords(ped) - at) > 150.0 or not HasCollisionLoadedAroundEntity(ped) then return nil end
    local handle = StartShapeTestLosProbe(at.x, at.y, at.z + 0.25, at.x, at.y, at.z + 80.0, 17, ped, 7)
    for _ = 1, 25 do
        local status, hit = GetShapeTestResult(handle)
        if status == 2 then return hit == 1 or hit == true end
        if status == 0 then return nil end
        Wait(10)
    end
    return nil
end

local current = olink._getCapabilities().weather
if not (current and current.provider == 'oxide-weather') then
    olink._registerDefault('weather', {
        IsRainingAt = function()
            return rainWeathers[GetPrevWeatherTypeHashName()] == true
        end,

        IsCovered = function(coords)
            local at = toPoint(coords)
            if not at then return nil end
            return probeCover(at)
        end,

        GetExposureAt = function(coords)
            local at = toPoint(coords)
            local covered = nil
            if at then covered = probeCover(at) end
            return { known = covered ~= nil, covered = covered }
        end,
    })
end

-- A weather-only hold for this player: a resource asks for, say, clear weather while the player
-- stands in a walk-in space that is not a real interior, and the clock keeps running. Every sync
-- provider's own pause also moves the clock (qb-weathersync jumps to 18:00, Renewed-Weathersync to
-- 21:00 and freezes it, oxide-weather drops its clock override), so the hold reads the clock and its
-- minute length first and puts both back once the provider has paused. Holds belong to the
-- resource that asked; the last release resumes the provider. Registered under every provider,
-- including none, before the provider guards below.
local dryWeathers = { EXTRASUNNY = true, CLEAR = true, NEUTRAL = true, SMOG = true, FOGGY = true, OVERCAST = true, CLOUDS = true }
local holds = {}            -- [resource] = weather type name
local holdOrder = {}        -- resources in the order they held, the newest last
local holding = false
local holdGeneration = 0
local savedWeather = nil
local HOLD_OWNER = 'o-link:localweather'

local function heldWeather()
    local owner = holdOrder[#holdOrder]
    return owner and holds[owner] or nil
end

-- The provider is paused and resumed from o-link's own thread, so every provider sees the same
-- owner whichever resource asked.
local function setProviderSync(enabled)
    CreateThread(function()
        local api = olink.weather
        if api and api.ToggleSync then pcall(api.ToggleSync, enabled, HOLD_OWNER) end
    end)
end

local function restoreClock(hours, minutes, seconds, msPerMinute, startedAt)
    local elapsedMinutes = msPerMinute > 0 and (GetGameTimer() - startedAt) / msPerMinute or 0
    local total = ((hours * 60 + minutes + seconds / 60 + elapsedMinutes) % 1440)
    local h = math.floor(total / 60)
    local m = math.floor(total % 60)
    local s = math.floor((total * 60) % 60)
    NetworkOverrideClockTime(h, m, s)
    if msPerMinute > 0 then NetworkOverrideClockMillisecondsPerGameMinute(msPerMinute) end
end

local function startHold()
    holding = true
    holdGeneration = holdGeneration + 1
    local generation = holdGeneration
    savedWeather = weatherNames[GetPrevWeatherType()]
    local hours, minutes, seconds = GetClockHours(), GetClockMinutes(), GetClockSeconds()
    local msPerMinute = GetMillisecondsPerGameMinute()
    local startedAt = GetGameTimer()
    setProviderSync(false)
    CreateThread(function()
        -- The providers move the clock as they pause, some a frame later; put it back after both.
        for _, delay in ipairs({ 50, 950 }) do
            Wait(delay)
            if not holding or holdGeneration ~= generation then return end
            restoreClock(hours, minutes, seconds, msPerMinute, startedAt)
        end
    end)
    CreateThread(function()
        while holding and holdGeneration == generation do
            local weather = heldWeather()
            if weather then
                SetWeatherTypeNowPersist(weather)
                if dryWeathers[weather] then SetRainLevel(0.0) end
            end
            Wait(1000)
        end
    end)
end

local function stopHold()
    holding = false
    holdGeneration = holdGeneration + 1
    SetRainLevel(-1.0)
    if savedWeather then SetWeatherTypeNowPersist(savedWeather) end
    ClearWeatherTypePersist()
    savedWeather = nil
    setProviderSync(true)
end

local function release(owner)
    if not holds[owner] then return false end
    holds[owner] = nil
    for i = #holdOrder, 1, -1 do
        if holdOrder[i] == owner then table.remove(holdOrder, i) end
    end
    if holding and #holdOrder == 0 then stopHold() end
    return true
end

olink._registerDefault('weather', {
    ---@param weather string|nil weather type name, EXTRASUNNY by default
    ---@return boolean
    HoldLocalWeather = function(weather)
        local owner = GetInvokingResource() or GetCurrentResourceName()
        weather = type(weather) == 'string' and weather:upper() or 'EXTRASUNNY'
        if not weatherNames[GetHashKey(weather)] then return false end
        if not holds[owner] then holdOrder[#holdOrder + 1] = owner end
        holds[owner] = weather
        if not holding then startHold() end
        return true
    end,

    ---@return boolean
    ReleaseLocalWeather = function()
        return release(GetInvokingResource() or GetCurrentResourceName())
    end,
})

AddEventHandler('onClientResourceStop', function(stopped)
    if holds[stopped] then release(stopped) end
end)

if not olink._guardImpl('Weather', '_default', false) then return end
if not olink._hasOverride('Weather') and GetResourceState('cd_easytime') == 'started' then return end
if not olink._hasOverride('Weather') and GetResourceState('night_natural_disasters') == 'started' then return end
if not olink._hasOverride('Weather') and GetResourceState('oxide-weather') == 'started' then return end
if not olink._hasOverride('Weather') and GetResourceState('qb-weathersync') == 'started' then return end
if not olink._hasOverride('Weather') and GetResourceState('Renewed-Weathersync') == 'started' then return end
if not olink._hasOverride('Weather') and GetResourceState('renewed-weathersync') == 'started' then return end

olink._registerDefault('weather', {
    GetResourceName = function() return '_default' end,

    ToggleSync = function() end,

    GetWeather = function()
        return weatherNames[GetPrevWeatherType()] or 'CLEAR'
    end,

    GetTime = function()
        return { hour = GetClockHours(), minute = GetClockMinutes() }
    end,
})
