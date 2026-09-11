# o-link Support Matrix

This matrix is rebuilt from the current filesystem under `o-link/modules` and `o-link/lifecycle`.

It lists implementation folders that exist today. It does not guarantee every implementation is bug-free; it only verifies that the bridge ships that adapter in the current tree.

## Core and Framework Namespaces

| Namespace | Side | Implementation folders |
|-----------|------|------------------------|
| `callback` | shared | built-in shared module |
| `framework` | server + client | `es_extended`, `oxide-core`, `qb-core`, `qbx_core` |
| `character` | server + client | `es_extended`, `oxide-core`, `qb-core`, `qbx_core` |
| `multichar` | server + client | `es_extended`, `oxide-core`, `qb-core`, `qbx_core` |
| `job` | server + client | `es_extended`, `oxide-core`, `qb-core`, `qbx_core` |
| `money` | server | `es_extended`, `oxide-accounts`, `qb-core`, `qbx_core` |
| `license` | server | `es_extended`, `oxide-core`, `qb-core`, `qbx_core` |
| `inventory` | server + client | `ak47_qb_inventory`, `codem-inventory`, `core_inventory`, `hex_4_inventory`, `jpr-inventory`, `origen_inventory`, `oxide-inventory`, `ox_inventory`, `ps-inventory`, `qb-inventory`, `qs-inventory`, `tgiann-inventory` |
| `vehicles` | server | `esx_vehicleshop`, `oxide-vehicles`, `qb-garages`, `qbx_vehicles` |
| `vehicleproperties` | client | `modules/vehicles/properties` |
| `entity` | server + client | built-in framework-agnostic module |
| `map` | server + client + NUI | built-in shared atlas, mode settings and coordinate helpers |
| `jobcount` | server | built-in framework-agnostic module |

### `inventory.AddTrunkItems` / `inventory.GetTrunkItems`

Reading and writing a vehicle trunk is not uniform across inventories. Callers must
gate on the **return value** -- `olink.supports()` cannot be used here, because the
default stub is itself callable and would report the namespace as available.

| Adapter | Write | Read | Container |
|---------|-------|------|-----------|
| `ox_inventory` | yes | yes | native trunk `trunk<plate>`, resolved from the vehicle entity |
| `oxide-inventory` | yes | yes | native vehicle storage (`vehicle_storages` / `vehicle_storage_items`) |
| `qb-inventory` | yes | yes | `trunk-<plate>` (v2 `CreateInventory`, v1 `inventory:server:addTrunkItems`) |
| `ak47_qb_inventory` | yes | yes | `trunk-<plate>` |
| `origen_inventory` | yes | yes | stash `trunk_<plate>` |
| `tgiann-inventory` | yes | **no** | native secondary inventory `trunk` |
| `codem-inventory`, `core_inventory`, `hex_4_inventory`, `jpr-inventory`, `ps-inventory`, `qs-inventory`, `_default` | no | no | -- |

**`GetTrunkItems` returns `nil` when it cannot read, never `{}`.** An empty table would
be indistinguishable from an empty trunk, and a caller that persists whatever it reads
would erase its own record the first time it ran against an inventory that cannot read.
Treat a non-table return as "unknown", not as "empty".

**Pass the netId whenever you have one.** `AddTrunkItems(plate, items, netId)`,
`GetTrunkItems(plate, netId)` and `ClearStash(plate, 'trunk', netId)` all accept it.
ox_inventory resolves a vehicle inventory through the entity, and with only a plate it
scans world vehicles comparing `GetVehicleNumberPlateText` -- which is unreliable
server-side for entities created with `CreateVehicleServerSetter`
(citizenfx/fivem#2838). A job fleet vehicle has its plate stamped by the client, so
that scan never matches and the call fails until someone opens the trunk in game.

**Vehicles the framework does not own have no persistent trunk on ox_inventory.** It
saves against the owned-vehicle row (`UPDATE player_vehicles SET trunk = ? WHERE id = ?`)
using an id the framework supplies, and a job fleet vehicle has no such row -- so the
write matches nothing and the read comes back empty. A resource that wants storage to
survive on such a vehicle has to keep the contents itself and push them back on spawn.

Item entries accept either key spelling: `name` or `item`, and `count` or `amount`.

`ClearStash(plate, 'trunk')` empties the same container these write to.


## UI and Interaction

| Namespace | Side | Implementation folders |
|-----------|------|------------------------|
| `notify` | server + client | `brutal_notify`, `confirm`, `fl-notify`, `lation_ui`, `mythic_notify`, `okokNotify`, `oxide-core`, `oxide-notify`, `ox_lib`, `pNotify`, `r_notify`, `t-notify`, `wasabi_notify`, `zsxui` |
| `helptext` | server + client | server relay plus `cd_drawtextui`, `jg-textui`, `lab-HintUI`, `lation_ui`, `okokTextUI`, `ox_lib`, `zsxui` |
| `target` | client | `oxide-target`, `ox_target`, `qb-target`, `sleepless_interact`, `tgiann-target` |
| `progressbar` | client | `esx_progressbar`, `keep-progressbar`, `lation_ui`, `oxide-progressbar`, `ox_lib`, `qb-progressbar`, `wasabi_uikit`, `zsxui` |
| `input` | client | `lation_ui`, `ox_lib`, `qb-input` |
| `menu` | client | `lation_ui`, `oxide-menu`, `ox_lib`, `qb-menu`, `wasabi_uikit` |
| `radial` | client | `oxide-menu`, `ox_lib` |
| `zones` | client | `oxlib`, `polyzone` |
| `placement` | client | `modules/placement` |
| `tablet` | server + client | `oxide-tablet` (no `_default`: the stubs return falsy so consumers fall back to their own UI). Hosts apps, home-screen widgets and push notifications |

`notify` auto-detection selects one renderer. `ox_lib` is fallback-only unless
forced with `Config.Overrides.Notify = 'ox_lib'`; if multiple non-`ox_lib`
notify resources are running, set `Config.Overrides.Notify`.

`radial` auto-detection prefers `oxide-menu` as the full provider. The `ox_lib`
adapter remains available as a fallback/global registration provider; private
radials opened through `olink.radial.Open(data)` are exposed as global submenus.
Direct `lib.addRadialItem(...)` calls are not intercepted.

## Gameplay Systems

| Namespace | Side | Implementation folders |
|-----------|------|------------------------|
| `fuel` | client | `bigDaddy-Fuel`, `cdn-fuel`, `esx-sna-fuel`, `lc_fuel`, `legacyfuel`, `okokGasStation`, `oxide-vehicles`, `ox_fuel`, `ps-fuel`, `qb-fuel`, `qs-fuelstations`, `renewed-Fuel`, `ti_fuel`, `x-fuel` |
| `weather` | client; server v2 with `oxide-weather` | `cd_easytime`, `night_natural_disasters`, `oxide-weather`, `qb-weathersync`, `renewed-weathersync` |
| `vehiclekey` | client | `cd_garage`, `f_realcarkeyssystem`, `jacksam`, `mk_vehiclekeys`, `mrnewbvehiclekeys`, `mVehicle`, `okokGarage`, `oxide-vehicles`, `qb-vehiclekeys`, `qbx_vehiclekeys`, `qs-vehiclekeys`, `renewed-vehiclekeys`, `t1ger_keys`, `wasabi_carlock` |
| `vehicleOwnership` | server | `esx_vehicleshop`, `oxide-vehicles`, `qb-garages`, `qbx_vehicles` |
| `death` | server + client | `_default`, `es_extended`, `oxide-death`, `qb-core`, `qbx_core` (all emit `olink:*:playerDied/Downed/Revived/Respawned/playerDeathStateChanged` — see API.md for per-provider caveats; client `SetSuppressed` is honoured by `oxide-death` only, stub `false` elsewhere) |
| `medical` | server + client | `oxide-medical` |
| `needs` | server | `es_extended`, `oxide-needs`, `qb-core`, `qbx_core` |
| `gang` | server + client | `es_extended`, `oxide-core`, `qb-core`, `qbx_core` |

## Economy, Services, and World

| Namespace | Side | Implementation folders |
|-----------|------|------------------------|
| `banking` | server | `fd_banking`, `kartik-banking`, `okokBanking`, `oxide-banking`, `qb-banking`, `renewed-banking`, `tgg-banking`, `tgiann-bank`, `wasabi_banking` |
| `phone` | server + client | `gksphone`, `lb-phone`, `okokPhone`, `oxide-phone`, `qb-phone`, `qs-smartphone`, `yseries` |
| `clothing` | shared + server + client | `esx_skin`, `fivem-appearance`, `illenium-appearance`, `oxide-clothing`, `oxide-identity`, `qb-clothing`, `rcore_clothing` |
| `dispatch` | server + client | `_default`, `bub-mdt`, `cd_dispatch`, `emergencydispatch`, `fd_dispatch`, `kartik-mdt`, `lb-tablet`, `linden_outlawalert`, `origen_police`, `oxide-dispatch`, `piotreq_gpt`, `ps-dispatch`, `qs_dispatch`, `redutzu-mdt`, `tk_dispatch`, `wasabi_mdt` |
| `doorlock` | server + client | `doors_creator`, `ox_doorlock`, `qb-doorlock`, `rcore_doorlock` |
| `housing` | server + client | `bcs-housing`, `esx_property`, `ps-housing`, `qb-apartments` (+ `qb-houses`), `qbx_properties` |
| `bossmenu` | server + client | `esx_society`, `qb-management`, `qbx_management` |
| `skills` | server + client | `_default`, `evolent_skills`, `ot_skills`, `pickle_xp` |
| `logger` | server + client | `ox_lib` (default), `oxide-logger` (optional, free; overrides ox_lib when installed) |

## Lifecycle Adapters

| Framework | Files |
|-----------|-------|
| `oxide-core` | `lifecycle/oxide-core/server.lua`, `lifecycle/oxide-core/client.lua` |
| `qb-core` | `lifecycle/qb-core/server.lua`, `lifecycle/qb-core/client.lua` |
| `qbx_core` | `lifecycle/qbx_core/server.lua`, `lifecycle/qbx_core/client.lua` |
| `es_extended` | `lifecycle/es_extended/server.lua`, `lifecycle/es_extended/client.lua` |
