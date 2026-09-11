lib.locale()
local ok, catalog = pcall(json.decode, LoadResourceFile('o-link', 'web/map/catalog.json') or 'null')
if not ok then catalog = nil end
local valid = { combined = true, separate = true, disabled = true, inherit = true }
OlinkMap = {}

function OlinkMap.IsMode(value, inherit)
    return type(value) == 'string' and valid[value] == true and (inherit or value ~= 'inherit')
end

function OlinkMap.GetConfig(override, defaultMode)
    local mode = OlinkMap.IsMode(defaultMode, false) and defaultMode or 'combined'
    if OlinkMap.IsMode(override, true) and override ~= 'inherit' then mode = override end
    return {
        ready = defaultMode ~= nil and catalog ~= nil,
        mode = mode,
        defaultMode = defaultMode,
        override = OlinkMap.IsMode(override, true) and override or 'inherit',
        assetBase = 'https://cfx-nui-o-link/web/map/tiles/',
        catalog = catalog,
        labels = {
            mainland = locale('map.mainland'), cayo = locale('map.cayo'),
            combined = locale('map.combined'), separate = locale('map.separate'),
            disabled = locale('map.disabled'), inherit = locale('map.inherit'),
            select = locale('map.select'), loading = locale('map.loading'),
            unavailable = locale('map.unavailable'),
        },
    }
end
