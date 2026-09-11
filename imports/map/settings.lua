if Config.MapMode == nil then Config.MapMode = 'inherit' end
local schema = WeatherSettingsSchema or SettingsSchema
if schema and schema.byKey then
    local field = {
        key = 'MapMode', group = WeatherSettingsSchema and 'Broadcast' or 'General', tier = 'basic', type = 'select',
        label = locale('map.mode'), help = locale('map.help'),
        meta = { options = {
            { value = 'inherit', label = locale('map.inherit') },
            { value = 'combined', label = locale('map.combined') },
            { value = 'separate', label = locale('map.separate') },
            { value = 'disabled', label = locale('map.disabled') },
        } },
    }
    schema.fields[#schema.fields + 1] = field
    schema.byKey.MapMode = field
end
