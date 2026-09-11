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
