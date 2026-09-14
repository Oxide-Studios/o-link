local RESOURCE='oxide-weather'
if GetResourceState(RESOURCE)=='missing' then return end
if not olink._guardImpl('Weather',RESOURCE,false) then return end
local function Available() return GetResourceState(RESOURCE)=='started' end
local function Call(method,...)
    if not Available() then return nil,'Weather provider unavailable' end
    local args=table.pack(...)
    local result=table.pack(pcall(function() return exports[RESOURCE][method](exports[RESOURCE],table.unpack(args,1,args.n)) end))
    if not result[1] then return nil,'Weather provider unavailable' end
    return table.unpack(result,2,result.n)
end
local api={GetResourceName=function() return Available() and RESOURCE or 'none' end,
    IsReady=function() return Available() and Call('IsReady')==true end}
for _,method in ipairs({'GetApiVersion', 'GetSetting', 'GetWeather', 'GetTime', 'GetTimeScale', 'IsTimeFrozen', 'IsBlackout', 'IsDynamicWeather', 'GetWeatherInterval', 'GetForecast', 'GetWeatherData', 'GetZones', 'GetZoneWeather', 'GetZoneForecast', 'GetZoneAt', 'GetSeason', 'GetClimateData', 'GetTemperature', 'GetTemperatureAt', 'GetSnowLevel', 'GetSnowLevelAt', 'GetFronts', 'GetWeatherAt', 'IsZoneBlackout', 'GetBlackouts', 'GetSceneLocks', 'GetWeatherAlerts', 'GenerateWeazelReport', 'GetConditionsAt', 'IsRainingAt', 'GetWindAt', 'IsSnowOnGround', 'GetExposureAt', 'GetPlayerExposure', 'GetRoadConditionsAt', 'GetRealWorldWeather'}) do
    api[method]=function(...) return Call(method,...) end
end
for _,method in ipairs({'SetWeather', 'SetSetting', 'SetTime', 'SetTimeScale', 'FreezeTime', 'SetBlackout', 'SetDynamicWeather', 'SetWeatherInterval', 'SetZoneWeather', 'SetZoneDynamicWeather', 'SetZoneWeatherInterval', 'SetSeason', 'SetHoliday', 'SpawnFront', 'RemoveFront', 'SetZoneBlackout', 'ScheduleBlackout', 'CancelBlackout', 'SetSceneLock', 'ClearSceneLock', 'SetForecast', 'SetClock', 'SetZoneTime'}) do
    api[method]=function(...)
        -- Capture the engine-provided caller before entering another export/yield.
        -- Consumers cannot supply or override their resource identity.
        local origin=GetInvokingResource()
        if not origin or origin==RESOURCE then return false,'Missing weather caller identity' end
        local ok,reason=Call('WeatherBridge',method,origin,...)
        return ok==true,reason
    end
end
for _,method in ipairs({'GetExposureAt','GetPlayerExposure'}) do
    api[method]=function(...)
        local origin=GetInvokingResource()
        if not origin then return nil end
        return Call('WeatherReadBridge',method,origin,...)
    end
end
olink._register('weather',api,RESOURCE)
for _,event in ipairs({'timeChanged','clockProgress','weatherChanged','zoneWeatherChanged','seasonChanged','blackoutChanged','alertsChanged'}) do
    AddEventHandler('oxide:weather:'..event,function(...)
        if Available() then TriggerEvent('olink:server:weather:'..event,...) end
    end)
end
AddEventHandler('onResourceStart',function(name)
    if name==RESOURCE then TriggerEvent('olink:server:weather:ready') end
end)
AddEventHandler('onResourceStop',function(name)
    if name==RESOURCE then TriggerEvent('olink:server:weather:stopped') end
end)
