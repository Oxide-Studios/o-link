fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'o-link'
author 'Oxide Studios'
description 'Oxide Studios framework bridge'
version '1.9.1'

escrow_ignore {
    'config.lua',
    'locales/*.json',
    'imports/map/*.lua',
}

ui_page 'web/index.html'

files {
    'imports/map/client.lua',
    'imports/map/settings.lua',
    'locales/*.json',
    'web/map/tiles/*.webp',
    'web/map/runtime.css',
    'web/map/runtime.js',
    'web/map/catalog.json',
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'core/shared.lua',
    'modules/map/shared.lua',
    'modules/notify/shared.lua',
    'modules/callback/shared.lua',
    'modules/clothing/**/shared.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'core/defaults_server.lua',
    'modules/map/server.lua',
    'modules/framework/**/server.lua',
    'modules/framework/server.lua',
    'modules/character/**/server.lua',
    'modules/character/server.lua',
    'modules/multichar/**/server.lua',
    'modules/job/**/server.lua',
    'modules/job/server.lua',
    'modules/money/**/server.lua',
    'modules/license/**/server.lua',
    'modules/inventory/**/server.lua',
    'modules/inventory/_shims_server.lua',
    'modules/vehicles/**/server.lua',
    'modules/vehicles/server.lua',
    'modules/vehiclekey/**/server.lua',
    'modules/notify/server.lua',
    'modules/entity/server.lua',
    'modules/banking/**/server.lua',
    'modules/phone/**/server.lua',
    'modules/clothing/**/server.lua',
    'modules/dispatch/**/server.lua',
    'modules/doorlock/**/server.lua',
    'modules/housing/**/server.lua',
    'modules/housing/server.lua',
    'modules/bossmenu/**/server.lua',
    'modules/skills/**/server.lua',
    'modules/vehicleOwnership/**/server.lua',
    'modules/death/**/server.lua',
    'modules/needs/**/server.lua',
    'modules/medical/**/server.lua',
    'modules/gang/**/server.lua',
    'modules/gang/server.lua',
    'modules/jobcount/server.lua',
    'modules/helptext/**/server.lua',
    'modules/helptext/server.lua',
    'modules/logger/**/server.lua',
    'modules/tablet/**/server.lua',
    'modules/weather/**/server.lua',
    'lifecycle/**/server.lua',
    'core/loader_server.lua',
    'core/update_lib.lua',
    'core/version_check.lua',
    'core/catalogue_check.lua',
    'core/known_providers.lua',
    'core/diag_server.lua',
}

client_scripts {
    'core/defaults_client.lua',
    'modules/map/client.lua',
    'modules/framework/**/client.lua',
    'modules/character/**/client.lua',
    'modules/multichar/**/client.lua',
    'modules/job/**/client.lua',
    'modules/inventory/**/client.lua',
    'modules/inventory/_shims_client.lua',
    'modules/notify/**/client.lua',
    'modules/notify/relay_client.lua',
    'modules/helptext/**/client.lua',
    'modules/target/**/client.lua',
    'modules/progressbar/**/client.lua',
    'modules/vehiclekey/**/client.lua',
    'modules/vehiclekey/client.lua',
    'modules/fuel/**/client.lua',
    'modules/weather/**/client.lua',
    'modules/input/**/client.lua',
    'modules/menu/**/client.lua',
    'modules/menu/client.lua',
    'modules/radial/**/client.lua',
    'modules/zones/**/client.lua',
    'modules/placement/**/client.lua',
    'modules/entity/client.lua',
    'modules/phone/**/client.lua',
    'modules/clothing/**/client.lua',
    'modules/dispatch/**/client.lua',
    'modules/doorlock/**/client.lua',
    'modules/housing/**/client.lua',
    'modules/bossmenu/**/client.lua',
    'modules/skills/**/client.lua',
    'modules/death/**/client.lua',
    'modules/medical/**/client.lua',
    'modules/gang/**/client.lua',
    'modules/vehicles/**/client.lua',
    'modules/logger/**/client.lua',
    'modules/tablet/**/client.lua',
    'lifecycle/**/client.lua',
    'core/loader_client.lua',
}

dependencies {
    '/server:6116',
    '/onesync',
    'ox_lib',
    'oxmysql',
}
