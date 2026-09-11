-- Isolated tests for the map setting lifecycle and NUI replication.
local db, queue, commands, callbacks, handlers, messages = {}, {}, {}, {}, {}, {}
local current, inserts, denied = 'o-link', 0, 0
Config = { MapMode = 'combined' }
GlobalState = {}
lib = { locale = function() end }
locale = function(key) return key end
GetCurrentResourceName = function() return current end
LoadResourceFile = function() return 'catalog' end
json = {
    decode = function(value)
        if value == 'catalog' then return { maps = {}, regions = {} } end
        if type(value) == 'string' and value:sub(1, 1) == '"' then return value:sub(2, -2) end
        error('Invalid JSON')
    end,
    encode = function(value) return '"' .. value .. '"' end,
}
olink = {
    framework = { IsAdmin = function(source) return source == 1 end },
    notify = { Send = function() denied = denied + 1 end },
}
olink._register = function(name, methods) olink[name] = methods end
exports = { ['o-link'] = { olink = function() return olink end } }
CreateThread = function(fn) queue[#queue + 1] = fn end
Wait = function() error('Unexpected wait in ready fixture') end
RegisterCommand = function(name, fn) commands[name] = fn end
RegisterNUICallback = function(name, fn) callbacks[name] = fn end
AddStateBagChangeHandler = function(key, _, fn) handlers[key] = fn end
SendNUIMessage = function(message) messages[#messages + 1] = message end
MySQL = { query = { await = function(sql, params)
    if sql:find('CREATE TABLE', 1, true) then return end
    local value = db[params[1] .. ':' .. params[2]]
    return value and { { value = value } } or {}
end }, insert = { await = function(_, params)
    inserts = inserts + 1
    db[params[1] .. ':' .. params[2]] = params[3]
end } }
local function RunThreads()
    local pending = queue
    queue = {}
    for _, fn in ipairs(pending) do fn() end
end
local function Command(name, source, mode)
    assert(commands[name], name)(source, mode and { mode } or {})
end

dofile('modules/map/shared.lua')
dofile('modules/map/server.lua')
assert(not olink.map.GetConfig().ready)
RunThreads()
assert(GlobalState['o-link:map:mode'] == 'combined')
Command('olink:mapmode', 0, 'separate')
assert(db['o-link:MapMode'] == '"separate"')
local before = inserts
Command('olink:mapmode', 2, 'disabled')
Command('olink:mapmode', 0, 'inherit')
assert(inserts == before and denied == 1)
Config.MapMode = 'combined'
dofile('modules/map/server.lua')
RunThreads()
assert(Config.MapMode == 'separate', 'Saved default must survive restart')

for _, resource in ipairs({ 'oxide-carplayer', 'oxide-dispatch', 'oxide-vending' }) do
    current, Config = resource, { MapMode = 'inherit' }
    SettingsSchema, WeatherSettingsSchema = nil, nil
    dofile('imports/map/server.lua')
    RunThreads()
    assert(GlobalState[resource .. ':config:MapMode'] == 'inherit')
    Command(resource .. ':mapmode', 1, 'disabled')
    assert(db[resource .. ':MapMode'] == '"disabled"')
    local count = inserts
    Command(resource .. ':mapmode', 2, 'combined')
    assert(inserts == count)
    Config.MapMode = 'inherit'
    dofile('imports/map/server.lua')
    RunThreads()
    assert(Config.MapMode == 'disabled')
end

for _, resource in ipairs({ 'oxide-shops', 'oxide-gangs', 'oxide-police', 'oxide-weather' }) do
    current, Config = resource, { MapMode = 'separate' }
    SettingsSchema = resource ~= 'oxide-weather' and { fields = {}, byKey = {} } or nil
    WeatherSettingsSchema = resource == 'oxide-weather' and { fields = {}, byKey = {} } or nil
    dofile('imports/map/settings.lua')
    local schema = WeatherSettingsSchema or SettingsSchema
    assert(schema.byKey.MapMode and #schema.byKey.MapMode.meta.options == 4)
    local calls = 0
    Settings = { ready = true, Set = function(key, mode)
        assert(key == 'MapMode')
        calls = calls + 1
        Config[key] = mode
        return true
    end }
    local count = inserts
    dofile('imports/map/server.lua')
    RunThreads()
    assert(inserts == count, 'Full settings engine must retain database ownership')
    Command(resource .. ':mapmode', 1, 'disabled')
    assert(calls == 1 and Config.MapMode == 'disabled')
end

current, Config = 'oxide-shops', { MapMode = 'inherit' }
GlobalState['oxide-shops:config:MapMode'] = 'inherit'
dofile('modules/map/client.lua')
dofile('imports/map/client.lua')
local response
callbacks['olink:map:getConfig']({}, function(value) response = value end)
assert(response.mode == 'separate' and response.ready and response.version == 0)
-- Handler values win even before GlobalState reflects the change.
handlers['oxide-shops:config:MapMode']('global', nil, 'disabled')
assert(messages[#messages].data.mode == 'disabled' and messages[#messages].data.version == 1)
handlers['oxide-shops:config:MapMode']('global', nil, 'inherit')
handlers['o-link:map:mode']('global', nil, 'combined')
assert(messages[#messages].data.mode == 'combined' and messages[#messages].data.version == 3)
print('Map settings passed: seeding, restart persistence, authorization, full-engine delegation and ordered NUI updates.')
