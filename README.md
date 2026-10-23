# o-link

`o-link` is Oxide Studios' cross-framework bridge resource for FiveM.

Its public API is organized into small namespaces such as `framework`, `character`, `job`, `money`, `inventory`, `vehicles`, `entity`, and `callback`. Each namespace is backed by a guard-clause adapter so the active implementation (QBCore, Qbox, ESX, etc.) is selected automatically.

## Current State

- The resource is real and substantial. It ships 42 top-level module folders under [`modules`](./modules), 4 lifecycle adapters under [`lifecycle`](./lifecycle), and internal docs under [`docs`](./docs).
- The bridge exports a single shared object through `exports('olink', ...)` in [`core/shared.lua`](./core/shared.lua).
- Module implementations are loaded by `fxmanifest.lua` glob patterns and self-register with `olink._register(...)`.
- `Config.Debug` is implemented and controls loader logging.
- `Config.Overrides` is implemented and can force a specific implementation per namespace.

## Start Here

- API surface: [`docs/API.md`](./docs/API.md)
- Architecture: [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md)
- Verified module and implementation matrix: [`docs/SUPPORT-MATRIX.md`](./docs/SUPPORT-MATRIX.md)
- Standalone server integration guide: [`docs/STANDALONE-INTEGRATION.md`](./docs/STANDALONE-INTEGRATION.md)
- Placing your UI around a server HUD (`olink.hud.AddPanel`): [`docs/HUD.md`](./docs/HUD.md)

## Minimal Usage

```lua
olink = exports['o-link']:olink()
Callback = olink.callback
```

```lua
dependencies {
    'ox_lib',
    'oxmysql',
    'o-link',
}
```

## Load Order

Ensure framework and detected dependencies before `o-link`, then ensure resources that consume `o-link` after it.

Example:

```cfg
ensure ox_lib
ensure oxmysql
ensure qb-core          # or qbx_core, or es_extended
ensure ox_inventory     # and your target, phone, fuel and other scripts

ensure o-link

ensure oxide-police
ensure oxide-shops
```

## Updating

When the server starts, o-link checks for a newer version and prints a notice in the server console. With `Config.AutoDownloadUpdates = true` in `config.lua` it downloads the new files itself; they apply on the next full server restart.

The automatic download cannot create new folders. When a release adds folders, it prints `this release must be installed manually` and changes nothing.

- **On 1.12.0 or newer:** 1.12.1, 1.12.2 and 1.12.3 add no folders, so the automatic download applies them. Without `AutoDownloadUpdates`, install it by hand as below.
- **On 1.11.0 or older:** 1.12.0 added 14 folders, so install by hand once. That takes you straight to the latest version.

To install by hand:

1. Download the latest version: on [github.com/Oxide-Studios/o-link](https://github.com/Oxide-Studios/o-link), click **Code**, then **Download ZIP**.
2. Stop your server.
3. Copy your `o-link/config.lua` somewhere safe.
4. Delete your `o-link` folder and put the new one in its place. The folder inside the zip is called `o-link-main`: rename it to `o-link`.
5. Put your `config.lua` back. Settings added since your copy have defaults, so it keeps working.
6. Start your server. The update notice is gone.

Always restart the whole server after updating, never o-link on its own: the resources that use o-link would stop working until they restart too.

## Credits & License

`o-link` is derived from [community_bridge](https://github.com/TheOrderFivem/community_bridge) by TheOrderFivem and contributors, licensed under GPL v3. The bridge concept, module taxonomy (`modules/<namespace>/<implementation>/`), per-vendor adapter layout, and significant portions of the public API surface originate from community_bridge. The codebase has been modified for Oxide Studios' use.

`o-link` is licensed under GPL v3. See [`LICENSE`](./LICENSE).

Thanks to TheOrderFivem and the community_bridge contributors for the original design and for making the work available to the community.
