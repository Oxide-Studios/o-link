local resource = GetCurrentResourceName()
local bridge = exports['o-link']:olink()
local stateKey = resource .. ':config:MapMode'
local pendingMode
local version = 0

local function GetConfig()
    local override = pendingMode or GlobalState[stateKey]
    local data = bridge.map.GetConfig(override or Config.MapMode or 'inherit')
    data.ready = data.ready and override ~= nil
    data.version = version
    return data
end

local function Push()
    SendNUIMessage({ action = 'olink:map:config', data = GetConfig() })
end

RegisterNUICallback('olink:map:getConfig', function(_, cb)
    cb(GetConfig())
end)

AddStateBagChangeHandler(stateKey, 'global', function(_, _, value)
    version = version + 1
    pendingMode = value
    Push()
end)

AddStateBagChangeHandler('o-link:map:mode', 'global', function(_, _, value)
    version = version + 1
    local override = pendingMode or GlobalState[stateKey]
    local data = bridge.map.GetConfig(override or Config.MapMode or 'inherit', value)
    data.ready = data.ready and override ~= nil
    data.version = version
    SendNUIMessage({ action = 'olink:map:config', data = data })
end)
