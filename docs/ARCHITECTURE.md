# o-link Architecture

## Overview

`o-link` is a bridge resource that normalizes framework- and dependency-specific APIs behind a single exported object:

```lua
olink = exports['o-link']:olink()
```

The current resource targets Oxide, QBCore, QBX, and ESX-related ecosystems, plus a large number of inventory, notify, dispatch, phone, housing, clothing, and utility resources.

## Core Pattern

The runtime model is:

1. `fxmanifest.lua` loads broad glob patterns.
2. Each implementation file immediately checks whether its dependency is available.
3. Matching files self-register a namespace through `olink._register(namespace, impl)`.
4. Consumers call `olink.<namespace>.<function>`.

Example from the current manifest:

```lua
server_scripts {
    'modules/framework/**/server.lua',
    'modules/character/**/server.lua',
    'modules/job/**/server.lua',
    'modules/inventory/**/server.lua',
    'lifecycle/**/server.lua',
    'core/loader_server.lua',
}
```

Example guard-clause structure:

```lua
if GetResourceState('qb-core') == 'missing' then return end
if GetResourceState('qbx_core') == 'started' then return end

olink._register('framework', {
    GetName = function()
        return 'qb-core'
    end,
})
```

## Registration Model

The shared core lives in [`../core/shared.lua`](../core/shared.lua):

```lua
olink = {}

function olink._register(namespace, impl)
    olink[namespace] = impl
end

function olink.supports(path)
    -- dot-path capability check
end
```

`o-link` stores namespaces directly on one exported object rather than building a nested module tree.

## Circular Provider/Consumer Pattern

A "circular" resource declares `o-link` in its `dependencies { ... }` AND provides an o-link namespace (today: `oxide-vehicles`, `oxide-dispatch`, `oxide-banking`, `oxide-tablet`).

### The cross-VM snapshot trap

Each FiveM resource has its own Lua VM. When consumers run `olink = exports['o-link']:olink()`, FiveM marshals the table across the VM boundary — function values inside become bound function references at marshal time, NOT live key lookups. After o-link's internal `olink.<ns>.<fn>` is mutated, consumer snapshots do NOT see the change; their references stay frozen to whatever function objects existed at snapshot time.

This rules out two patterns that look correct but aren't:
1. **Self-registration in the consumer's own scripts** — runs after o-link, after consumers have already snapshotted, so other consumers hold stub refs forever.
2. **Deferred registration via `onResourceStart`** — fires when the consumer starts. Any other consumer that snapshotted olink before the deferred handler ran is permanently stale. (oxide-police starts before oxide-vehicles in our boot order, so its snapshot of `olink.vehicles.GetByPlate` would be a stub forever.)

### The fix: register immediately

Adapters for circular resources MUST register synchronously at o-link load time. Wrappers gate on `GetResourceState(resource) == 'started'` and `pcall` the export at CALL time. Pass `false` as the third arg to `_guardImpl` to skip the resource-state check (the consumer isn't started yet — that's the whole point).

Adapter file template at `o-link/modules/<namespace>/<resourceName>/(server|client).lua`:

```lua
local RESOURCE = '<resourceName>'

-- Pure adapter: bail if the resource isn't installed so other providers or
-- the namespace's _default fallback own this namespace as normal.
if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('<Namespace>', RESOURCE, false) then return end

local res = exports[RESOURCE]

local function isStarted()
    return GetResourceState(RESOURCE) == 'started'
end

olink._register('<namespace>', {
    GetResourceName = function() return RESOURCE end,
    Fn = function(...)
        if not isStarted() then return <default> end
        local ok, result = pcall(function() return res:Fn(...) end)
        return ok and result or <default>
    end,
}, RESOURCE)
```

Worked examples in this codebase: `modules/vehicles/oxide-vehicles/server.lua`, `modules/dispatch/oxide-dispatch/server.lua`, `modules/banking/oxide-banking/server.lua`.

Adapter wrappers MUST call `exports['<resource>']:Fn(...)` only — never reference Lua identifiers from the consumer's file scope (those are nil from o-link's resource scope). Every wrapped function must be a real `exports('Fn', ...)` declared in the consumer.

Every function name registered by an adapter must also be present in `core/defaults_(server|client).lua` stubs so consumers that bypass `olink.supports()` get the friendly fallback warning instead of a nil-field crash.

## What Is Verified Today

- `o-link` uses glob-loaded implementation files, not runtime `load()` or `LoadResourceFile(...)` evaluation for bridge bootstrapping.
- Lifecycle adapters exist for `oxide-core`, `qb-core`, `qbx_core`, and `es_extended`.
- Loader summaries exist on both server and client.
- The client loader explicitly tracks `vehicleproperties` as its own namespace even though its file lives under `modules/vehicles/properties/client.lua`.
- Server-only relay modules exist for `notify` and `helptext`.
- `jobcount` is implemented as an internal `GlobalState`-backed counting module.

## File Layout

```text
o-link/
|-- fxmanifest.lua
|-- config.lua
|-- core/
|   |-- shared.lua
|   |-- defaults_server.lua
|   |-- defaults_client.lua
|   |-- loader_server.lua
|   |-- loader_client.lua
|   |-- version_check.lua
|   |-- known_providers.lua
|   `-- diag_server.lua
|-- lifecycle/
|   |-- oxide-core/
|   |-- qb-core/
|   |-- qbx_core/
|   `-- es_extended/
`-- modules/
    |-- callback/
    |-- framework/
    |-- character/
    |-- multichar/
    |-- job/
    |-- money/
    |-- license/
    |-- inventory/
    |-- vehicles/
    |-- notify/
    |-- helptext/
    |-- target/
    |-- progressbar/
    |-- vehiclekey/
    |-- fuel/
    |-- weather/
    |-- input/
    |-- menu/
    |-- radial/
    |-- zones/
    |-- placement/
    |-- entity/
    |-- banking/
    |-- phone/
    |-- clothing/
    |-- dispatch/
    |-- doorlock/
    |-- housing/
    |-- bossmenu/
    |-- skills/
    |-- vehicleOwnership/
    |-- death/
    |-- medical/
    |-- needs/
    |-- gang/
    |-- logger/
    |-- tablet/
    `-- jobcount/
```

## Event Naming

- Local bridge lifecycle events use the `olink:` prefix.
- Network relay events use the `o-link:` prefix.
- Callback transport uses `o-link:CS:Callback`, `o-link:SC:Callback`, `o-link:CSR:Callback`, and `o-link:SCR:Callback`.

## Configuration Status

Six config surfaces exist in [`../config.lua`](../config.lua):

- `Config.Debug`
- `Config.Overrides`
- `Config.CheckForUpdates`
- `Config.AutoDownloadUpdates`
- `Config.ImageBaseUrl`
- `Config.Diag`

`Config.Debug` controls loader logging.

`Config.CheckForUpdates` (default `true`) makes o-link check its public GitHub repo for a newer release on startup and print a notice to the server console. Only an explicit `false` disables it: the updater never overwrites `config.lua`, so an install that predates this key has no entry for it, and treating that as off would silence the notice on exactly the installs that are furthest behind.

The same key governs `core/catalogue_check.lua`, which covers every *other* Oxide resource on the server. Those ship through the Cfx.re Portal rather than a repository, so there is nothing for them to compare themselves against individually; instead o-link reads one published version list and prints a single block naming each installed resource that is behind. It runs once, after ten seconds of no resource starting — o-link boots early by design, so checking immediately would read a half-booted server. It is a notice only: escrowed assets cannot self-update the way o-link does. Both checks share `core/update_lib.lua` (version parsing, comparison, and the blocking GET), which loads before either.

Because of that same protection, a customer who updates keeps the `config.lua` they first installed with and is missing every key added since. Two things follow, and both are required of any new config surface: every key must default in code, and `core/loader_server.lua` prints a one-time console notice naming the keys their `config.lua` lacks. `Config.ImageBaseUrl` is excluded from that notice because it ships as `nil`, so absent and present are indistinguishable.

`Config.AutoDownloadUpdates` (default `false`) downloads a detected update and writes it over o-link's own files; the new files take effect on the next full server restart. It has no effect unless `Config.CheckForUpdates` is also true.

`Config.ImageBaseUrl` (default `nil`) sets the base URL that `olink.inventory.GetImagePath` resolves item images against.

`Config.Diag` configures the `/oxide:diag` support snapshot written by `core/diag_server.lua`: `RequireAce` (an extra ace that grants access alongside the framework admin check), `RecentErrors` (how many captured errors to include when oxide-logger is running), and `SnapshotDir` (a single-level directory, because `SaveResourceFile` only auto-creates one parent). Every key defaults in code, since the auto-updater never overwrites a customer's `config.lua`.

`Config.Overrides` is consumed during implementation selection. When an override is set for a namespace, only the matching implementation is allowed to load for that namespace and normal priority blocker guards are bypassed for that selected implementation.

## Ensure Order

Ensure framework/core dependencies first, then `o-link`, then consumers.

```cfg
ensure oxide-core
ensure oxide-inventory
ensure oxide-accounts
ensure oxide-vehicles

ensure o-link

ensure oxide-police
ensure oxide-shops
```
