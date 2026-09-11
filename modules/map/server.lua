local ready = false
local mode = Config.MapMode or 'combined'

olink._register('map', {
    GetConfig = function(override)
        return OlinkMap.GetConfig(override, ready and mode or nil)
    end,
    IsMode = OlinkMap.IsMode,
}, 'o-link')

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS oxide_settings (
        resource VARCHAR(60) NOT NULL, setting_key VARCHAR(100) NOT NULL, value JSON NOT NULL,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (resource, setting_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    local rows = MySQL.query.await('SELECT value FROM oxide_settings WHERE resource = ? AND setting_key = ?', { 'o-link', 'MapMode' })
    local saved = rows and rows[1] and rows[1].value
    if type(saved) == 'string' then
        local ok, value = pcall(json.decode, saved)
        if ok then saved = value end
    end
    if OlinkMap.IsMode(saved, false) then mode = saved
    else
        if not OlinkMap.IsMode(mode, false) then mode = 'combined' end
        MySQL.insert.await('INSERT INTO oxide_settings (resource, setting_key, value) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE value = VALUES(value)',
            { 'o-link', 'MapMode', json.encode(mode) })
    end
    ready = true
    Config.MapMode = mode
    GlobalState['o-link:map:mode'] = mode
end)

RegisterCommand('olink:mapmode', function(source, args)
    if source ~= 0 and not olink.framework.IsAdmin(source) then
        return olink.notify.Send(source, locale('map.denied'), 'error')
    end
    if not ready then return end
    local value = args[1]
    if not value then
        print(('[o-link] MapMode = %s'):format(mode))
        return
    end
    if not OlinkMap.IsMode(value, false) then
        print('[o-link] ' .. locale('map.usage_default'))
        return
    end
    MySQL.insert.await('INSERT INTO oxide_settings (resource, setting_key, value) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE value = VALUES(value)',
        { 'o-link', 'MapMode', json.encode(value) })
    mode, Config.MapMode = value, value
    GlobalState['o-link:map:mode'] = value
    print(('[o-link] MapMode = %s'):format(value))
end, false)
