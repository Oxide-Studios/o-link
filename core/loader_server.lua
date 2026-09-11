-- Server loader: prints startup summary after all modules have self-registered via globs
local caps = olink._getCapabilities()

print('^2[o-link] Server modules loaded:^0')
local modules = { 'callback', 'map', 'framework', 'character', 'multichar', 'job', 'money', 'inventory', 'vehicles', 'vehicleOwnership', 'banking', 'notify', 'phone', 'clothing', 'dispatch', 'doorlock', 'housing', 'bossmenu', 'skills', 'entity', 'death', 'needs', 'gang', 'jobcount', 'helptext', 'logger', 'tablet', 'weather' }
for _, ns in ipairs(modules) do
    local state = caps[ns]
    if state and state.loaded then
        if state.kind == 'fallback' then
            print(('  ^5%-12s^0 : ^3fallback^0'):format(ns))
        else
            print(('  ^5%-12s^0 : ^2loaded^0'):format(ns))
        end
    elseif Config.Debug then
        print(('  ^5%-12s^0 : ^1not loaded^0'):format(ns))
    end
end

-- The updater never overwrites config.lua, so a customer who updates keeps the
-- config they first installed with and silently misses every setting added since.
-- Code defaults cover them, but naming the gap here turns a silent difference into
-- something they can act on. ImageBaseUrl is deliberately absent from this list:
-- it ships as nil, so a missing key and the shipped value are indistinguishable.
local EXPECTED = { 'Overrides', 'Debug', 'CheckForUpdates', 'AutoDownloadUpdates', 'Diag' }
local missing = {}
for _, key in ipairs(EXPECTED) do
    if rawget(Config, key) == nil then missing[#missing + 1] = key end
end

if #missing > 0 then
    print(('^3[o-link] Your config.lua does not have these settings yet: %s^0'):format(table.concat(missing, ', ')))
    print('^3[o-link] Nothing is broken -- o-link is using its built-in defaults for them.^0')
    print('^3[o-link] To change them, copy those sections from the config.lua in the latest o-link download.^0')
end

print('^2[o-link] Server initialization complete.^0')
