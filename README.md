# o-link

`o-link` is Oxide Studios' cross-framework bridge resource for FiveM.

Its public API is organized into small namespaces such as `framework`, `character`, `job`, `money`, `inventory`, `vehicles`, `entity`, and `callback`. Each namespace is backed by a guard-clause adapter so the active implementation (QBCore, QBX, ESX, Oxide, etc.) is selected automatically.

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
ensure oxide-core
ensure oxide-inventory
ensure oxide-accounts
ensure oxide-vehicles

ensure o-link

ensure oxide-police
ensure oxide-shops
```

## Credits & License

`o-link` is derived from [community_bridge](https://github.com/TheOrderFivem/community_bridge) by TheOrderFivem and contributors, licensed under GPL v3. The bridge concept, module taxonomy (`modules/<namespace>/<implementation>/`), per-vendor adapter layout, and significant portions of the public API surface originate from community_bridge. The codebase has been modified for Oxide Studios' use.

`o-link` is licensed under GPL v3. See [`LICENSE`](./LICENSE).

Thanks to TheOrderFivem and the community_bridge contributors for the original design and for making the work available to the community.
