-- Client loader: prints startup summary after all modules have self-registered via globs
if Config.Debug then
    local caps = olink._getCapabilities()
    print('^2[o-link] Client modules loaded:^0')
    local modules = { 'callback', 'map', 'framework', 'character', 'job', 'inventory', 'notify', 'helptext', 'target', 'progressbar', 'vehiclekey', 'fuel', 'weather', 'input', 'menu', 'radial', 'zones', 'placement', 'phone', 'clothing', 'dispatch', 'doorlock', 'housing', 'bossmenu', 'skills', 'entity', 'death', 'gang', 'vehicleproperties', 'logger', 'tablet' }
    for _, ns in ipairs(modules) do
        local state = caps[ns]
        if state and state.loaded then
            if state.kind == 'fallback' then
                print(('  ^5%-12s^0 : ^3fallback^0'):format(ns))
            else
                print(('  ^5%-12s^0 : ^2loaded^0'):format(ns))
            end
        else
            print(('  ^5%-12s^0 : ^1not loaded^0'):format(ns))
        end
    end
    print('^2[o-link] Client initialization complete.^0')
end
