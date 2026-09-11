# Shared resource maps

o-link owns the calibrated atlas, map definitions, tile URLs, coordinate conversion
and the default map mode. Carplayer, shops, gangs, dispatch, police, vending and
weather render it inside their own interfaces. Each resource retains its markers,
overlays, editing actions and server authorization.

## Settings

The factory default is `Config.MapMode = 'combined'` in o-link. Each consumer has
`Config.MapMode = 'inherit'`.

| Value | Result |
| --- | --- |
| combined | Mainland and Cayo on the combined calibrated map. |
| separate | Independent mainland/Cayo views. Interactive maps have a region selector; compact GPS/alert previews choose the region from their focus coordinates. |
| disabled | Mainland artwork only. Cayo markers and Cayo-specific polygons are hidden. |
| inherit | Consumer only: follow o-link's default. |

These are presentation modes. The supplied calibration uses standard Cayo
coordinates; island loading, custom world transforms and routing buckets are
managed by the server's island resources.

Settings are stored in `oxide_settings`. Config files seed missing keys; saved
values remain authoritative across restarts. No manual SQL migration is required.
Shops, gangs, police and weather expose the override in their existing settings
menus. All seven also accept a namespaced command, available to framework admins
or the server console:

- `olink:mapmode combined|separate|disabled`
- `oxide-carplayer:mapmode inherit|combined|separate|disabled`
- `oxide-shops:mapmode inherit|combined|separate|disabled`
- `oxide-gangs:mapmode inherit|combined|separate|disabled`
- `oxide-dispatch:mapmode inherit|combined|separate|disabled`
- `oxide-police:mapmode inherit|combined|separate|disabled`
- `oxide-vending:mapmode inherit|combined|separate|disabled`
- `oxide-weather:mapmode inherit|combined|separate|disabled`

Prefix commands with `/` in game. Without a mode argument, the command prints the
current saved value in the server console. Mode changes reach open interfaces
through statebags and NUI messages. Each open map retains its own region selection.

## Resource integration

Consumers depend on o-link and oxmysql. Their manifests import:

- Shared: `@o-link/imports/map/settings.lua`, after config, locale initialization
  and any resource settings schema.
- Server: `@o-link/imports/map/server.lua`, after the MySQL import and the resource's
  settings engine. It delegates to the full settings engine where one exists;
  otherwise it owns only that resource's MapMode key.
- Client: `@o-link/imports/map/client.lua`.

NUI entry pages load `https://cfx-nui-o-link/web/map/runtime.js` and `runtime.css`.
This library provides `OxideMap.use(Vue, options)`; consumers supply their own
Vue instance. It reads the owning resource's `olink:map:getConfig` callback and
handles live mode changes. The resource's NUI focus and gameplay callbacks stay
with the resource.

The view exposes reactive dimensions/bounds, visible tile helpers, a region
selector, point/polygon visibility, and world/pixel conversion. Coordinate math
runs locally in the consumer's browser. Only assets and map configuration are
shared; private overlay data is never moved into o-link.

`olink.map.GetConfig(override?)` is available on client/server and returns the
resolved mode, default, catalog, asset base, readiness and translated map labels.
`olink.map.IsMode(value, allowInherit)` validates setting values. The optional
second client GetConfig argument is the just-received default mode, used by the
statebag handler before GlobalState reflects that update.

## Artwork and calibration

- `data/map-calibration.json`: measured source transforms and ocean blend recipe.
- `web/map/catalog.json`: combined, mainland and Cayo view definitions.
- `web/map/tiles/`: content-addressed WebP tiles, shared between variants.
- `web/map/runtime.js`: the common frontend implementation.

Each tile covers 256 logical pixels and carries up to 512 image pixels. Logical
view dimensions may include a half pixel at the last tile. Use the shared helpers
to handle partial edges.

The developer calibration tool publishes these files:

    python oxide-mapcalibrate/scripts/publish-map.py oxide-mapcalibrate/output/combined-map/calibration.json

Run that from the monorepo root. Source artwork remains in the developer
calibration resource; it is not a runtime dependency of o-link or the consumers.
World coordinates stored in shop, territory, dispatch and other records do not
need migration.

Update o-link and the consumers together, then perform a full server restart.
Do not restart o-link alone while consumers retain its exported function references.

## Verification

Offline checks cover calibrated landmarks, all three modes, independent view
selection, partial tiles, stale NUI responses, settings persistence and admin
authorization:

    node --test o-link/tests/map-runtime.test.mjs

The runtime test uses carplayer's installed Vue package. Run
`lua tests/map-settings.lua` from o-link for the isolated Lua lifecycle checks.

In game, verify both carplayer views, the shop admin map, gang territory editing,
dispatch alert thumbnails/hub/heatmap, both police MDT maps, vending markers and
the weather editor/public radar. Exercise all three default modes and a
resource override, including Cayo selection, recentering and polygon placement.
