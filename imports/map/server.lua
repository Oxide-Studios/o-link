-- Imported into the consumer: full settings engines keep ownership of their key.
local resource = GetCurrentResourceName()
local bridge = exports['o-link']:olink()
local key = 'MapMode'
local stateKey = resource .. ':config:' .. key
local fullSettings = (SettingsSchema and SettingsSchema.byKey and SettingsSchema.byKey[key])
    or (WeatherSettingsSchema and WeatherSettingsSchema.byKey and WeatherSettingsSchema.byKey[key])
local ready = false
local upsert = 'INSERT INTO oxide_settings (resource, setting_key, value) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE value = VALUES(value)'

CreateThread(function()
    if fullSettings then
        while not Settings or not Settings.ready do Wait(100) end
    else
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS oxide_settings (
            resource VARCHAR(60) NOT NULL, setting_key VARCHAR(100) NOT NULL, value JSON NOT NULL,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (resource, setting_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        local rows = MySQL.query.await('SELECT value FROM oxide_settings WHERE resource = ? AND setting_key = ?', { resource, key })
        local saved = rows and rows[1] and rows[1].value
        if type(saved) == 'string' then
            local ok, value = pcall(json.decode, saved)
            if ok then saved = value end
        end
        if bridge.map.IsMode(saved, true) then Config[key] = saved
        else
            if not bridge.map.IsMode(Config[key], true) then Config[key] = 'inherit' end
            MySQL.insert.await(upsert, { resource, key, json.encode(Config[key]) })
        end
        GlobalState[stateKey] = Config[key]
    end
    ready = true
end)

RegisterCommand(resource .. ':mapmode', function(source, args)
    if source ~= 0 and not bridge.framework.IsAdmin(source) then
        return bridge.notify.Send(source, locale('map.denied'), 'error')
    end
    if not ready then return end
    local value = args[1]
    if not value then
        print(('[%s] MapMode = %s'):format(resource, Config[key]))
        return
    end
    if not bridge.map.IsMode(value, true) then
        print(('[%s] %s'):format(resource, locale('map.usage_override')))
        return
    end
    if fullSettings then
        local ok = Settings.Set(key, value)
        if ok == false then return end
    else
        MySQL.insert.await(upsert, { resource, key, json.encode(value) })
        Config[key] = value
        GlobalState[stateKey] = value
    end
    print(('[%s] MapMode = %s'):format(resource, value))
end, false)
