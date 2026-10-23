# o-link API Reference

This file documents the public surface that has been verified against the current codebase.

For implementation coverage by resource name, see [`SUPPORT-MATRIX.md`](./SUPPORT-MATRIX.md).
For standalone server wiring, see [`STANDALONE-INTEGRATION.md`](./STANDALONE-INTEGRATION.md).
For shared NUI maps, mode settings and calibrated coordinate helpers, see [`MAPS.md`](./MAPS.md).

## Consuming o-link

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

## Capability Checks

```lua
olink.supports('character')
olink.supports('character.SetBoss')
olink.supports('vehicles.GetByOwner')
olink.supports('vehicleproperties.GetVehicleProperties')
```

## Module: callback (shared)

### Server
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Register(name, handler)` | `name: string, handler: function(src, ...)` | `nil` | Register a server callback |
| `Trigger(name, target, ...)` | `name: string, target: number\|number[], ...` | `any` | Trigger a client callback. If no Lua callback arg is passed, this awaits and returns the response. |

### Client
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Register(name, handler)` | `name: string, handler: function(...)` | `nil` | Register a client callback |
| `Trigger(name, ...)` | `name: string, ...` | `any` | Trigger a server callback. If no Lua callback arg is passed, this awaits and returns the response. |

## Module: framework (server + client)

### Server
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetName()` | | `string` | Framework name: `'qb-core'`, `'qbx_core'`, or `'es_extended'` |
| `GetIsPlayerLoaded(src)` | `src: number` | `boolean` | Whether the player currently has an active character/session |
| `GetPlayers()` | | `number[]` | Online player source IDs |
| `GetJobs()` | | `table[]` | Framework jobs list. Oxide currently returns `{}`. |
| `IsAdmin(src)` | `src: number` | `boolean` | Binary admin check. Each framework adapter accepts the stock framework admin (QBCore/QBX: the `command` or `admin` ACE; ESX also honors `xPlayer.isAdmin()`) or the Oxide convention `admin` ACE (`add_ace group.admin admin allow`). Gate admin commands on this, registered non-restricted — never `RegisterCommand(..., true)`. |
| `RegisterUsableItem(itemName, cb)` | `itemName: string, cb: function(src, itemData)` | `nil` | Register item use callback through the active framework |
| `Logout(src)` | `src: number` | `boolean` | Trigger the framework-specific logout flow |
| `ItemList()` | | `table` | Passthrough to the active inventory's item definitions |
| `GetStatus(src, column)` | `src: number, column: string` | `any\|nil` | Read a framework status column. Delegates hunger/thirst/stress to `needs.GetNeed`; returns `nil` otherwise. |

### Client
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetName()` | | `string` | Framework name |
| `GetIsPlayerLoaded()` | | `boolean` | Whether the local player is loaded |

## Module: character (server + client)

### Server
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetIdentifier(src)` | `src: number` | `string\|nil` | Normalized character identifier |
| `GetName(src)` | `src: number` | `string\|nil, string\|nil` | `firstName, lastName` |
| `GetMetadata(src, key)` | `src: number, key: string` | `any\|nil` | Metadata value |
| `SetMetadata(src, key, value)` | `src: number, key: string, value: any` | `boolean` | Set metadata |
| `GetAllMetadata(src)` | `src: number` | `table\|nil` | Full metadata table |
| `SetBoss(src, isBoss)` | `src: number, isBoss: boolean` | `boolean` | Set boss state |
| `IsBoss(src)` | `src: number` | `boolean` | Get boss state |
| `Search(query, limit?)` | `query: string, limit?: number` | `table[]` | Search offline character records |
| `GetOffline(identifier)` | `identifier: string` | `table\|nil` | Get offline character data |
| `GetDob(src)` | `src: number` | `string\|nil` | Convenience wrapper for the player's date of birth |
| `GetAccountCharacterIdentifiers(identifier)` | `identifier: string` | `string[]` | All character identifiers tied to the same game account. Returns `{identifier}` on ESX (identifier == license); on QB/QBX resolves via the `players.license` column. |

### Client
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetIdentifier()` | | `string\|nil` | Local player's identifier |
| `GetName()` | | `string\|nil, string\|nil` | `firstName, lastName` |
| `GetMetadata(key)` | `key: string` | `any\|nil` | Metadata value |

## Module: multichar (server + client)

Character lifecycle (list/create/select/delete) for a framework-agnostic multicharacter resource. The provider is the framework core (`qbx_core`, `qb-core`, or `es_extended`). When no provider is installed the defaults return empty results.

### Server
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `List(src)` | `src: number` | `table[]` | Player's character slot DTOs (`charId, stateId, firstName, lastName, fullName, dob, gender, position, lastPlayed`) |
| `Create(src, data)` | `src: number, data: { firstName, lastName, dob, gender }` | `{ ok: boolean, charId?, error? }` | Create a character (enforces slot limit) |
| `Select(src, charId)` | `src: number, charId: any` | `{ ok: boolean, position?, error? }` | Load + activate a character; `position` is returned when the consumer should teleport (Oxide has no spawn manager) |
| `Delete(src, charId)` | `src: number, charId: any` | `boolean` | Delete a character slot (never the active one) |
| `GetSlotInfo(src)` | `src: number` | `{ used: number, max: number }` | Slot usage |
| `Logout(src)` | `src: number` | `boolean` | Clear the active character and return the client to selection |

### Client
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetResourceName()` | | `string` | Active provider name |
| `OnboardNewCharacter(charId, opts, onDone)` | `charId: any, opts: { gender: 0\|1 }, onDone: fun(success: boolean)` | `nil` | Post-creation onboarding for a fresh character. The adapter runs whatever the framework natively does here — apartment selector, spawn picker, appearance editor — in the framework-native order. Called by the multichar resource once after `Create` + `Select` + spawn. |

The client adapter bridges the framework's native "show character selection" trigger to a unified `olink:client:startCharacterSelect` event (fired after `Logout`, and on boot when `oxide-multichar` is on the server). The boot trigger is a takeover: on QBCore, Qbox and ESX it turns off spawnmanager's auto-spawn, closes the loading screen and then fires the event. Without `oxide-multichar` it does none of that, so the server's own character screen keeps its loading screen and spawn.

`OnboardNewCharacter` is the single onboarding seam — it folds together apartment selection (QBX `apartments:client:setupSpawnUI`, QB `qb-spawn:client:setupSpawns`), default-spawn selection, and first-character clothing (`qb-clothes:client:CreateFirstCharacter`) per framework.

## Module: job (server + client)

### Server
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Get(src)` | `src: number` | `JobData\|nil` | Get normalized job data |
| `Set(src, jobName, grade)` | `src: number, jobName: string, grade: string\|number` | `boolean` | Set player job |
| `SetDuty(src, status)` | `src: number, status: boolean` | `boolean` | Set duty state |
| `GetDuty(src)` | `src: number` | `boolean` | Get duty state |
| `GetPlayersWithJob(jobName)` | `jobName: string` | `number[]` | Online players with the job |
| `DoesPlayerHaveJob(src, jobName, minGrade?)` | `src: number, jobName: string, minGrade: number\|nil` | `boolean` | True if player holds the job (optionally at or above the given grade) |

### Client
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Get()` | | `JobData\|nil` | Local player's normalized job data |
| `GetDuty()` | | `boolean` | Local duty state |

**JobData shape**

```lua
{
    name       = string,
    label      = string,
    grade      = string,
    gradeLabel = string,
    rank       = number,
    isBoss     = boolean,
    onDuty     = boolean,
}
```

## Module: money (server + client)

### Server
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Add(src, accountType, amount, reason?)` | `src: number, accountType: string, amount: number, reason?: string` | `boolean` | Add money to an online player |
| `Remove(src, accountType, amount, reason?)` | `src: number, accountType: string, amount: number, reason?: string` | `boolean` | Remove money from an online player |
| `GetBalance(src, accountType)` | `src: number, accountType: string` | `number` | Online balance |
| `AddOffline(identifier, accountType, amount, reason?)` | `identifier: string, accountType: string, amount: number, reason?: string` | `boolean` | Add money offline. `reason` labels the transaction on backends that keep a ledger; frameworks that write the balance directly ignore it |
| `RemoveOffline(identifier, accountType, amount, reason?)` | `identifier: string, accountType: string, amount: number, reason?: string` | `boolean` | Remove money offline. Same `reason` handling as `AddOffline` |
| `GetBalanceOffline(identifier, accountType)` | `identifier: string, accountType: string` | `number` | Offline balance |
| `GetCashItem()` | | `string\|false` | The cash item's name when `Config.Cash.mode` is `'item'`, otherwise `false`. Older o-link versions do not have this function; nil-check it before calling |

### Client
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetResourceName()` | | `string` | Active provider: `'qb-core'`, `'qbx_core'`, `'es_extended'`, or `'_default'` (no framework; every balance reads `0`) |
| `GetBalance(accountType)` | `accountType: string` | `number` | Local player's balance. `'cash'` and `'bank'` work on every provider (`'money'` is accepted for cash); other names are the framework's own accounts (`'crypto'`, `'black_money'`). `0` when unknown |
| `GetCashItem()` | | `string\|false` | Same as the server function |

| Event | Side | Args | Description |
|-------|------|------|-------------|
| `olink:client:moneyChanged` | client | `(accountType, balance)` | A local balance moved. `accountType` is `'cash'` or `'bank'` (ESX `money` is reported as `'cash'`), or the framework's name for any other account it reports. Only accounts that changed fire; the first update after a character loads reports every account |

Sources: QB and QBX read `PlayerData.money` (QB `QBCore:Player:UpdatePlayerDataField` and `SetPlayerData`, QBX `SetPlayerData`), ESX reads `PlayerData.accounts` (`esx:setAccountMoney`, `esx:playerLoaded`).

### Cash as an inventory item

`Config.Cash = { mode = 'account' | 'item', item = 'cash' }` in `config.lua` decides what cash is for every caller. `'account'` (also when the key is missing) is the framework's cash balance. With `'item'`, the `'cash'` account (and ESX's `'money'`) is the inventory item `item`, worth $1 each; every other account is unchanged.

- `Add`, `Remove` and `GetBalance` move and read the item through the inventory bridge. `Remove` checks the item count first.
- Amounts must be whole dollars. An amount with cents is refused (`false`) and logged with the calling resource; it is never rounded.
- `AddOffline` and `RemoveOffline` for cash return `false` (logged), and `GetBalanceOffline` returns `0`: an offline player's inventory is not loaded. Hold such payments until the player is online.
- Client: `GetBalance('cash')` is the item count, and `olink:client:moneyChanged` reports `'cash'` from the item. Moves made through o-link report straight away; other inventory changes within a second.

## Module: needs (server + client)

Hunger, thirst and stress on a 0-100 scale. Stock ESX (`esx_status`) has no stress, so on ESX it reads `nil` and cannot be set, on the server and the client, unless the server registers a `stress` status.

### Server
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetNeed(src, needType)` | `src: number, needType: 'hunger'\|'thirst'\|'stress'` | `number\|nil` | Current value; `nil` when the provider doesn't track it (ESX stress) |
| `SetNeed(src, needType, value)` | `src: number, needType: string, value: number` | `boolean` | Set a need (clamped 0-100); `false` when the provider doesn't track it |
| `ModifyNeed(src, needType, amount)` | `src: number, needType: string, amount: number` | `boolean` | Add or subtract from a need; `false` when the provider doesn't track it |

### Client
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetResourceName()` | | `string` | Active provider: `'qb-core'`, `'qbx_core'`, `'es_extended'`, or `'_default'` (no needs system) |
| `Get(needType)` | `needType: 'hunger'\|'thirst'\|'stress'` | `number\|nil` | Local player's need. `nil` when the provider doesn't track it (ESX stress, `_default`) or hasn't reported yet (ESX before the first `esx_status` tick) |
| `GetAll()` | | `{ hunger?, thirst?, stress? }` | All three; untracked needs are absent |

| Event | Side | Args | Description |
|-------|------|------|-------------|
| `olink:client:needsChanged` | client | `(needs)` | Any need moved. `needs` is the full `{ hunger?, thirst?, stress? }` snapshot after the change |

Sources: QB reads `PlayerData.metadata` (`hud:client:UpdateNeeds` / `UpdateStress`, `QBCore:Player:UpdatePlayerDataField`, `SetPlayerData`), QBX reads the `hunger` / `thirst` / `stress` player bags, ESX normalizes `esx_status:onTick` (about once a second).

## Module: license (server only)

Licenses are bool flags keyed by license type (`'driver'`, `'weapon'`, `'business'`, etc.). The bridge does not validate type names — the consumer (e.g. oxide-police) owns the type catalogue. On QB and QBX, types are arbitrary strings stored in player metadata. On ESX, types must exist in the `licenses` table (`esx_license`) for ESX-aware UIs to label them; the bridge will still write rows for unknown types but server owners should seed the table for consistency.

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetResourceName()` | | `string` | Active provider name, or `'none'` when no license backend is loaded |
| `Has(src, type)` | `src: number, type: string` | `boolean` | Whether the online player has this license |
| `Grant(src, type)` | `src: number, type: string` | `boolean` | Grant the license to an online player |
| `Revoke(src, type)` | `src: number, type: string` | `boolean` | Revoke the license from an online player |
| `GetAll(src)` | `src: number` | `table` | All licenses for an online player as `{ [type]=true\|false }` |
| `HasOffline(identifier, type)` | `identifier: string, type: string` | `boolean` | Whether the offline character has this license |
| `GrantOffline(identifier, type)` | `identifier: string, type: string` | `boolean` | Grant the license to an offline character |
| `RevokeOffline(identifier, type)` | `identifier: string, type: string` | `boolean` | Revoke the license from an offline character |
| `GetAllOffline(identifier)` | `identifier: string` | `table` | All licenses for an offline character |

`identifier` matches `character.GetIdentifier(src)` — citizenid on QB/QBX, ESX identifier on es_extended.

Storage:
- **qb-core / qbx_core** — `players.metadata.licences` (British spelling) as `{ [type]=bool }`.
- **es_extended** — rows in `user_licenses` keyed by player identifier.

## Module: inventory (server + client)

### Server
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetItemCount(src, item)` | `src: number, item: string` | `number` | Count item |
| `HasItem(src, item, count?)` | `src: number, item: string, count?: number` | `boolean` | Inventory check |
| `AddItem(src, item, count, slot?, metadata?)` | | `boolean` | Add item |
| `RemoveItem(src, item, count, slot?, metadata?)` | | `boolean` | Remove item |
| `GetItemBySlot(src, slot)` | | `table\|nil` | Slot data |
| `GetPlayerInventory(src)` | | `table[]` | Full inventory |
| `OpenPlayerInventory(src, targetSrc)` | | `boolean` | Open another player's inventory |
| `RegisterStash(id, label, slots, weight, owner?)` | | `boolean` | Register stash |
| `OpenStash(src, stashId)` | | `nil` | Open stash |
| `GetItemInfo(item)` | `item: string` | `table` | Item definition or `{}` |
| `CanCarryItem(src, item, count?)` | | `boolean` | Room check. **Stub default is `false`** — an adapter that omits it will refuse everything, so treat a false return as "unknown" rather than gating on it. |
| `GetImagePath(item)` | `item: string` | `string` | Image path. When `Config.ImageBaseUrl` is set in `o-link/config.lua`, always returns `<base>/<item>.png`; otherwise returns the adapter's path or `''`. |
| `SetMetadata(src, item, slot, metadata)` | | `boolean` | Overwrite an item's metadata |
| `Items()` | | `table` | Active inventory's item definitions |

#### Containers (server)
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `RegisterStash(id, label, slots, weight, owner?)` | | `boolean` | Register a stash |
| `OpenStash(src, stashId)` | | `nil` | Open a stash for a player |
| `GetStashItems(id)` | `id: string` | `table[]` | Contents of a stash |
| `CanReadStashes()` | | `boolean` | Whether `GetStashItems` reports a stash's real contents on this inventory: `true` on ox_inventory, qb-inventory v2 and ak47_qb_inventory. Everywhere else `GetStashItems` returns `{}` for any stash, so an empty list proves nothing; gate "is it empty?" checks on this |
| `GuardStash(id)` | `id: string` | `boolean` | Make a registered stash open only through `OpenStash`, so a client cannot reopen it by an id it saw earlier. `true` on ox_inventory (an `openInventory` hook refuses opens the server did not start); `false` where the inventory gives no way to refuse them |
| `AddStashItem(id, item, count, metadata?)` | | `boolean` | Add one item to a stash |
| `AddStashItems(id, items)` | `items: { item, count\|amount, metadata\|info }[]` | `boolean` | Add several |
| `RemoveStashItem(id, item, count)` | | `boolean` | Remove from a stash |
| `ClearStash(id, type?, netId?)` | `type?: 'stash'\|'trunk'\|'glovebox'` | `boolean` | Empty a container. With `'trunk'`/`'glovebox'`, `id` is the **plate** and the adapter derives the container id. |
| `AddTrunkItems(plate, items, netId?)` | `items: { item, count\|amount, metadata\|info }[]` | `boolean` | Put items in a vehicle's trunk |
| `GetTrunkItems(plate, netId?)` | `plate: string, netId?: number` | `table[]\|nil` | Read a trunk's contents. **`nil` when the inventory cannot read one** -- never `{}`, which would be indistinguishable from an empty trunk. |
| `UpdatePlate(oldPlate, newPlate)` | | `boolean` | Move vehicle storage to a new plate |
| `OpenShop(src, shopId)` / `RegisterShop(...)` | | `boolean` | Shop passthrough |

**Trunk support is not universal.** `AddTrunkItems` / `GetTrunkItems` are real on
`ox_inventory`, `qb-inventory`, `ak47_qb_inventory` and (add only)
`tgiann-inventory` and `origen_inventory`; everything else returns `false` / `{}`. See
[SUPPORT-MATRIX.md](SUPPORT-MATRIX.md#inventoryaddtrunkitems). Gate on the **return value** —
`olink.supports()` cannot be used here, because the fallback stub is itself callable.

On `ox_inventory` the trunk is resolved through the vehicle **entity**, so **pass `netId`**
whenever you have one. Without it ox scans world vehicles by plate, which fails for
entities made with `CreateVehicleServerSetter`. ox also cannot persist a trunk for a
vehicle the framework does not own -- see
[SUPPORT-MATRIX.md](SUPPORT-MATRIX.md#inventoryaddtrunkitems--inventorygettrunkitems).

Item entries accept either key spelling: `item` or `name`, and `count` or `amount`.

### Client
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetPlayerInventory()` | | `table[]` | Local inventory |
| `GetItemCount(item)` | `item: string` | `number` | Count item |
| `HasItem(item, count?)` | `item: string, count?: number` | `boolean` | Inventory check |
| `GetItemInfo(item)` | `item: string` | `table` | Item definition or `{}` |
| `GetImagePath(item)` | `item: string` | `string` | Image path. When `Config.ImageBaseUrl` is set in `o-link/config.lua`, always returns `<base>/<item>.png`; otherwise returns the adapter's path or `''`. |

## Module: vehicles (server only)

Providers: `qbx_vehicles` (Qbox), `qb-garages` (QBCore) and `esx_vehicleshop` (ESX). Generic helpers `IsOwnedBy` / `GetOwnedPlates` come from [`../modules/vehicles/server.lua`](../modules/vehicles/server.lua). Keys and locks are in [vehiclekey](#module-vehiclekey-client-only), shared job and gang vehicles in `vehicleOwnership`.

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `SearchByPlate(plate, limit?)` | `plate: string, limit?: number` | `table[]` | Fuzzy plate search joined with owner record |
| `GetByPlate(plate)` | `plate: string` | `table\|nil` | Vehicle record + owner fields (`charId`, `ownerFirst`, `ownerStateId`, etc.) |
| `GetByOwner(identifier)` | `identifier: string` (the owner's `character.GetIdentifier`) | `table[]` | Vehicles for an owner |
| `IsOwnedBy(src, plate)` | `src: number, plate: string` | `boolean` | Whether the plate belongs to the calling player |
| `GetOwnedPlates(src)` | `src: number` | `string[]` | Plates owned by the calling player |
| `GeneratePlate()` |  | `string` | Generate a unique plate per resource conventions |
| `RegisterVehicle(charId, model, plate, props?, type?)` | | `boolean` | Insert an owned vehicle row |
| `UnregisterVehicle(plate)` | `plate: string` | `boolean` | Delete an owned vehicle row |
| `ImpoundVehicle(plate, fee?, lot?)` | | `boolean` | Impound the vehicle |
| `ReleaseImpound(plate)` | | `boolean` | Release from impound (admin/no-fee) |
| `GetImpoundedVehicles(charId, lot?)` | `charId: string\|number, lot?: string` | `table[]` | List vehicles in impound owned by `charId`, optionally filtered to `lot`. Each row: `{ id, plate, model, vehicleType, fee, props, lot }`. `fee = nil` means the framework has no fee column — caller must apply its own fee policy. |
| `RetrieveImpounded(src, vehicleId, lot?)` | `src: number, vehicleId: number\|string, lot?: string` | `boolean, errorReason?` | Validate ownership, deduct any framework-native fee, flip state out of impound. Caller spawns the vehicle from `props` returned by the prior `GetImpoundedVehicles` call. When the framework has no fee column (ESX), the bridge skips fee deduction and the caller is responsible. |
| `GetVehicleState(plate)` | | `any` | Internal state snapshot |
| `SaveVehicleProps(plate, propsJson)` | | `boolean` | Persist serialized properties |

## Module: vehicleproperties (client only)

Registered from [`../modules/vehicles/properties/client.lua`](../modules/vehicles/properties/client.lua).

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetVehicleProperties(vehicle)` | `vehicle: number` | `table\|nil` | Serialize GTA vehicle properties |
| `SetVehicleProperties(vehicle, props)` | `vehicle: number, props: table` | `boolean` | Apply serialized properties |

## Module: placement (client only)

Registered from [`../modules/placement/client.lua`](../modules/placement/client.lua).

In-world placement builder for admin/editor tools (coordinate capture, ghost-preview entity placement, polygon zone authoring). **Await-style — each builder blocks until the admin confirms/cancels and returns the captured value** (a Lua callback argument can't marshal across the o-link VM boundary). Call from a coroutine/callback thread; the consumer manages its own NUI focus around the call — except during the fine-tune gizmo, where o-link briefly takes and always restores NUI focus itself.

On-screen help renders as a styled hint card in o-link's own NUI page (`web/`), showing the current mode, phase, step size, and key hints.

Controls — aim phase: mouse to aim, scroll wheel to rotate heading (LSHIFT = fine 1°), LMB confirm, RMB / ESC / Backspace cancel. **Enter opens the fine-tune gizmo**: mouse-drag the colored axes (X red / Y green / Z blue in the default palette) to slide the preview, scroll to rotate (Shift fine), arrow keys nudge (Ctrl+Up/Down = height, Space cycles the step 0.01/0.05/0.25/1.0m), Enter confirms, Backspace re-aims, ESC cancels. **RMB during fine-tune enters look mode** — NUI focus is released so the admin can move/look freely without losing the session; RMB or Enter resumes the gizmo. `Coord` gets a translate-only gizmo (no rotation). Screen placements additionally support **tilt** (Ctrl+Scroll pitches the panel ±90° in both phases) and show **gold edge handles** on the quad — drag them (or Shift+arrows) to resize width/height during fine-tune, on top of the aim-phase arrow-key resize. MLO interior props are unreliable ray targets — aim near the spot and use the gizmo to land exactly. Polygon builder is a freecam authoring tool (Enter place, arrows nudge, Space save).

Colors — every color the builders draw comes from a palette, resolved once at load and again when it changes (never per frame). Each player can pick their own palette with `/olink:placementcolors default|colorblind|reset` (no permission needed; it only changes what that player sees, and is saved on their client). Without a personal choice, the server palette applies: `Config.Placement.Palette` with any `Config.Placement.Colors` overrides on top. If `Config.Placement` is missing (installs that updated keep their old `config.lua`), the default palette applies. Colors are `{ r, g, b }` from 0 to 255.

| Role | Draws | `default` | `colorblind` |
|------|-------|-----------|--------------|
| `Marker` | Coord sphere + dot, GhostPed ground ring, GhostScreen quad, Entity outline, ped ground ring and markers, Polygon points/edges/fill, screen resize handles, `SetMarkers` color when none is given | 232, 176, 68 (amber) | 240, 228, 66 (yellow) |
| `Valid` | GhostObject outline where it can be placed | 80, 220, 120 (green) | 86, 180, 233 (sky blue) |
| `Invalid` | GhostObject outline out of `maxDistance` or off a snap point with `snapOnly` | 230, 70, 70 (red) | 213, 94, 0 (vermillion) |
| `Selected` | Selected Polygon point | 255, 220, 0 | 204, 121, 167 (reddish purple) |
| `Cursor` | Polygon freecam aim point | 0, 200, 255 | 0, 200, 255 |
| `AxisX` / `AxisY` / `AxisZ` | Fine-tune gizmo axes | 235, 70, 60 / 80, 210, 70 / 80, 140, 255 | 213, 94, 0 / 86, 180, 233 / 255, 255, 255 |

`colorblind` uses the Okabe-Ito colors, so the valid/invalid outline and the X/Y axes differ in brightness as well as hue and stay distinguishable under protanopia, deuteranopia and tritanopia.

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Coord(opts?)` | `opts?: { initialCoords? }` | `{x,y,z}\|nil` | Raycast point picker (no preview entity). Aim marker is a translucent sphere + center dot on the hit point |
| `Entity()` | | `{x,y,z,w}\|nil` | Raycast entity picker — the entity under the crosshair highlights with an outline (a ped gets a ring on the ground instead, because an outline on a ped crashes the game client); LMB snaps to its center (returns the entity origin + heading). For points that belong to a prop/ped/vehicle already in the world (stashes, doors, machines). No fine-tune gizmo — LMB select, RMB/ESC cancel |
| `GhostPed(opts)` | `opts: { model, initialHeading?, anim?, zOffset? }` | `{x,y,z,w}\|nil` | Place a translucent ghost ped; `w` = heading. `anim = { dict, clip }` previews a looped pose with **per-frame pelvis compensation** — the visible body (not the ped origin) stays centered on the aim point, and the RETURNED coords are the compensated entity transform (replay via `TaskPlayAnim` + `SetEntityCoordsNoOffset` at those coords to reproduce the preview). Without `anim`, coords are the raw surface hit (preview lifted `zOffset`, default 1.0) |
| `GhostVehicle(opts)` | `opts: { model, initialHeading? }` | `{x,y,z,w}\|nil` | Place a translucent ghost vehicle; `w` = heading |
| `GhostObject(opts)` | `opts: { model?, objects?, initialHeading?, zOffset?, maxDistance?, snaps?, snapOnly?, snapRadius? }` | `{x,y,z,w,snap?}\|nil` | Place a translucent ghost prop, or a rigid group of props via `objects = { { model, offset?, rotation?, quat? }, ... }` (`offset` in local metres, `rotation` local degrees applied X then Y then Z, `quat` a local `{x,y,z,w}` that overrides `rotation`). Returns the group anchor (surface hit + `zOffset`) and heading, so spawning each member at `anchor + offset` rotated by `w` reproduces the preview. With `maxDistance`, an anchor farther than that from the player outlines the ghost in the `Invalid` color (red by default) and confirm is ignored. `snaps = { { x, y, z, w, id }, ... }` locks the ghost to the nearest snap point within `snapRadius` (default 0.75m), taking its position and heading, and the result carries that point's `id` as `snap`; with `snapOnly = true` only a snapped position can be confirmed and fine-tune is disabled. Returns `nil` if no model loads |
| `GhostScreen(opts)` | `opts: { width?, height?, pitch?, zOffset?, initialHeading? }` | `{x,y,z,w,width,height,pitch}\|nil` | Place a translucent quad **centered on the crosshair** — aim directly at where the panel should float. Arrow keys resize while aiming (LSHIFT fine), Ctrl+Scroll tilts (±90°), and the fine-tune gizmo adds draggable gold edge handles for width/height; the chosen size/tilt is returned (`width`/`height`/`pitch` also seed re-picks). The returned `z` is the anchor below the quad center by `zOffset`, so `CreateScreen` with the returned coords/size/pitch + the same `zOffset` reproduces the preview exactly |
| `Polygon(opts?)` | `opts?: { existing? }` | `{ shape, minZ, maxZ }\|nil` | Freecam polygon zone authoring |
| `IsActive()` | | `boolean` | Whether a builder is currently running |
| `Cancel()` | | `nil` | Cancel the active builder (resolves it as `nil`) |
| `SetMarkers(id, markers)` | `id: string, markers: { coords, color?, label?, scale? }[]` | `boolean` | Replace a named group of persistent overlay markers (ground cylinders + floating labels for editor tools). `coords` accepts `{x,y,z}` or a vector; `color` is `{r,g,b,a?}`. nil/empty markers clears the group |
| `ClearMarkers(id?)` | `id?: string` | `nil` | Clear one overlay group, or all groups when omitted |
| `CreateScreen(opts)` | `opts: { id, url, coords, heading?, pitch?, width?, height?, zOffset?, resolution? }` | `boolean` | Paint an NUI page onto a world-space quad via DUI (no prop, no NUI focus). `url` is any `nui://` or web URL; `heading` = direction the panel faces (deg); `pitch` = tilt (deg, ±90); `width`/`height` in meters (1.6×0.9 default); `resolution` = `{w,h}` px (1280×720 default). Same `id` replaces the screen. Draws within 50m, both faces |
| `SendScreenMessage(id, data)` | `id: string, data: table` | `boolean` | Push a JSON payload to the screen's page (arrives as a window message, same channel as `SendNUIMessage`) |
| `DestroyScreen(id)` | `id: string` | `boolean` | Destroy one screen and its DUI |
| `ClearScreens()` | | `nil` | Destroy every screen (also runs automatically on o-link stop) |

Example:
```lua
local coords = olink.placement.GhostPed({ model = 'a_m_y_business_03' })
if coords then print(coords.x, coords.y, coords.z, coords.w) end
```

## Module: notify (server + client)

Notify uses one selected client adapter for both server-relayed and client-local
notifications. Auto-detection treats `ox_lib` as the fallback notify adapter
because it is an `o-link` dependency. If multiple non-`ox_lib` notify resources
are started, set `Config.Overrides.Notify` to the implementation folder name you
want to use.

### Server
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Send(src, message, type?, duration?, title?, props?)` | `src: number, message: string, type?: string, duration?: number, title?: string, props?: table` | `nil` | Send notification to a client. `title` is surfaced by adapters that support it (okokNotify, ox_lib, t-notify, r_notify, pNotify, lation_ui, zsxui, brutal_notify, FL-Notify, oxide-notify). `props` are merged for adapters that accept extra fields (ox_lib, oxide-notify). |
| `SendNotification(src, title, message, type?, duration?, props?)` | | `nil` | Alias accepting `title` as the first data argument. Same event under the hood as `Send`. |
| `Confirm(src, options, callback)` | `src: number, options: table, callback: function(accepted)` | `nil` | Open client confirm UI and resolve through callback |

### Client
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Send(message, type?, duration?, title?, props?)` | | `nil` | Show notification locally. Adapters that don't support `title`/`props` silently ignore them. |

## Module: helptext (server + client)

`message` is either a string or a structured prompt:

```lua
olink.helptext.Show('[E] Open Trunk')

olink.helptext.Show({
    id = 'trunk',                       -- optional: lets one resource keep several prompts open
    title = 'Vehicle',                  -- optional
    icon = 'fa-solid fa-car',           -- optional, Font Awesome class
    text = 'Parked outside',            -- optional
    keys = {
        { key = 'E', label = 'Open Trunk', control = 38 },  -- control: badge shows the player's binding
        { key = 'G', label = 'Lock' },
    },
    position = 'right-center',          -- optional, overrides the position argument
})
olink.helptext.Hide('trunk')
```

Positions: `right-center`, `left-center`, `top-center`, `bottom-center`, `top-left`, `top-right`, `bottom-left`, `bottom-right` (short `left`/`right`/`top`/`bottom` also work on `oxide-helptext`).

With `oxide-helptext`, prompts belong to the resource that showed them: `Hide()` with no id clears only the calling resource's prompts, prompts from different resources stack, and a resource's prompts disappear when it stops. Strings such as `[E] Open`, `[E] - Open`, `[E] Smoke · [H] Stop` and `[E] Open | [G] Lock` render with key badges. Every other provider shows one prompt at a time and receives structured prompts flattened to `Title: text  |  [E] Open Trunk  |  [G] Lock`; `Hide(id)` hides whatever is showing.

### Server
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Show(src, message, position?)` | `src: number, message: string\|table, position?: string` | `nil` | Relay helptext to a client. The prompt is owned by the calling server resource. |
| `Hide(src, id?)` | `src: number, id?: any` | `nil` | Hide the calling resource's prompt with this `id`, or all of its prompts when omitted |

### Client
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Show(message, position?)` | `message: string\|table, position?: string` | `nil` | Show or update a prompt. On `oxide-helptext`, repeating an identical call is free (safe every frame) and an empty message hides the prompt. |
| `Hide(id?)` | `id?: any` | `nil` | Hide the calling resource's prompt with this `id`, or all of its prompts when omitted |

## Module: target (client only)

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetResourceName()` | | `string` | Name of the active target resource |
| `DisableTargeting(bool)` | `bool: boolean` | `nil` | Toggle targeting on/off (ox_target only; no-op on others) |
| `AddBoxZone(name, coords, size, heading, options, debug?)` | | `any` | Add box zone (returns adapter-specific id) |
| `AddSphereZone(name, coords, radius, options, debug?)` | | `any` | Add sphere zone |
| `RemoveZone(name)` | `name: string` | `nil` | Remove zone |
| `AddLocalEntity(entity, options)` | | `nil` | Add local entity target |
| `RemoveLocalEntity(entity, optionNames?)` | | `nil` | Remove local entity target |
| `AddModel(models, options)` | | `nil` | Add model target |
| `RemoveModel(model)` | | `nil` | Remove model target |
| `AddGlobalPed(options)` | `options: table` | `nil` | Add options to every NPC ped |
| `RemoveGlobalPed(optionNames)` | `optionNames: string[]` | `nil` | Remove global ped options |
| `AddGlobalPlayer(options)` | `options: table` | `nil` | Add options to every player ped |
| `RemoveGlobalPlayer(optionNames?)` | `optionNames?: string[]` | `nil` | Remove global player options |
| `AddGlobalVehicle(options)` | `options: table` | `nil` | Add global vehicle options |
| `RemoveGlobalVehicle(options)` | `options: table\|string[]` | `nil` | Remove global vehicle options. Accepts an options table (names are extracted) or a raw name list. |
| `AddNetworkedEntity(netId, options)` | `netId: number\|number[], options: table` | `nil` | Add target options to a networked entity |
| `RemoveNetworkedEntity(netId, optionNames?)` | `netId: number\|number[], optionNames?: string\|string[]` | `nil` | Remove target options from a networked entity |

Zones created through `AddBoxZone` / `AddSphereZone` are tracked per calling resource and cleaned up automatically when that resource stops.

## Module: progressbar (client only)

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Open(options, callback?, isQBInput?)` | `options: table, callback?: function, isQBInput?: boolean` | `boolean` | Open progress UI. When `isQBInput` is true, `options` is treated as QB-format (`controlDisables`, `animation`, `prop`/`propTwo`) and converted internally. The `qb-progressbar` adapter takes a `qbFormat` boolean with the inverse meaning (skip conversion because options are already QB-shaped). |

## Module: menu (client only)

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetResourceName()` | | `string` | Active menu resource |
| `Open(data, useQb?)` | `data: table, useQb?: boolean` | `string` | Open a context menu (returns the menu id). Auto-generates `data.id` if not provided. |
| `OpenMenu(id, data, useQBinput?)` | `id: string, data: table, useQBinput?: boolean` | `string` | Alias for `Open` that takes `id` as the first argument and assigns it to `data.id`. |

## Module: radial (client only)

`oxide-menu` is the full provider and supports private immediate-open radials.
`ox_lib` is a fallback/global registration provider; when `Open(data)` receives
a private radial definition it registers that radial as an ox_lib submenu and
adds/updates a global radial entry for it. Direct `lib.addRadialItem` calls
continue to use ox_lib unchanged.

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetResourceName()` | | `string` | Active radial resource |
| `Register(menu)` | `menu: table` | `boolean` | Register a reusable radial menu |
| `Unregister(id)` | `id: string` | `boolean` | Unregister a radial menu where supported |
| `Open(idOrData, options?)` | `idOrData: string\|table, options?: table` | `string\|false` | Open a private radial immediately when supported. Providers without private open support may expose it as a global radial submenu instead. |
| `Close()` | | `boolean` | Close the active radial |
| `IsOpen()` | | `boolean` | Whether a radial is open when the provider can report it |
| `GetCurrentId()` | | `string\|nil` | Current radial id when known |
| `AddItem(items)` | `items: table\|table[]` | `boolean` | Add one or more global radial items |
| `RemoveItem(id)` | `id: string` | `boolean` | Remove a global radial item |
| `ClearItems()` | | `boolean` | Remove all bridge-added global radial items |
| `Disable(state)` | `state: boolean` | `boolean` | Enable or disable radial opening |
| `Refresh()` | | `boolean` | Refresh the open radial where supported |

Ox-style aliases are available under `olink.radial`: `RegisterRadial`,
`AddRadialItem`, `RemoveRadialItem`, `ClearRadialItems`, `HideRadial`,
`DisableRadial`, and `GetCurrentRadialId`.

## Module: vehiclekey (client only)

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetResourceName()` | | `string` | Active vehicle key resource |
| `Give(vehicle, plate?)` | `vehicle: number, plate?: string` | `nil` | Give keys to the local player |
| `Remove(vehicle, plate?)` | `vehicle: number, plate?: string` | `nil` | Remove keys from the local player |
| `GiveKeys(vehicle, plate?)` | | `nil` | Alias for `Give` |
| `RemoveKeys(vehicle, plate?)` | | `nil` | Alias for `Remove` |

## Module: seatbelt (client only)

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetResourceName()` | | `string` | Active provider: `'qbx_seatbelt'`, `'qb-smallresources'`, or `'_default'` (no seatbelt system; always off) |
| `IsOn()` | | `boolean` | Local player's seatbelt is fastened |

| Event | Side | Args | Description |
|-------|------|------|-------------|
| `olink:client:seatbeltChanged` | client | `(isOn)` | The local seatbelt was fastened or released, including the release when the player leaves the vehicle |

Sources: the `seatbelt` and `harness` player bags set by `qbx_seatbelt` (a harness counts as buckled, as on `qb-smallresources`), and `qb-smallresources` (`HasSeatbeltOn` export, `seatbelt:client:ToggleSeatbelt`). With both installed, pick one with `Config.Overrides.Seatbelt`.

## Module: voice (client only)

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetResourceName()` | | `string` | Active provider: `'pma-voice'`, `'saltychat'`, or `'_default'` (FiveM's built-in voice chat) |
| `GetState()` | | `VoiceState` | Local player's voice state, read at call time. Poll it; there is no change event |

**VoiceState shape**

```lua
{
    connected = boolean,      -- the voice system is connected and usable
    talking   = boolean,
    range = {
        index    = number|nil, -- 1-based proximity mode
        label    = string|nil, -- the provider's name for the mode (pma-voice: 'Whisper', 'Normal', 'Shouting')
        distance = number|nil, -- metres
        count    = number|nil, -- number of modes, when the provider reports it
    },
    radio = {
        active  = boolean,          -- transmitting on the radio right now
        channel = number|string|nil, -- current radio channel; nil when off the radio
    },
}
```

| Provider | `connected` | `talking` | `range` | `radio` |
|----------|-------------|-----------|---------|---------|
| `pma-voice` | `MumbleIsConnected` | `MumbleIsPlayerTalking` | `proximity` bag: `index`, `label` (`mode`), `distance`; `voice_defaultVoiceMode` until set | `radioChannel` bag (`0` = none), `radioActive` bag |
| `saltychat` | `SaltyChat_PluginStateChanged` = in game (assumed until the first event) | `SaltyChat_TalkStateChanged` (needs `RequestTalkStates`) | `GetVoiceRange` export for `distance`; `index` and `count` from `SaltyChat_VoiceRangeChanged`; no labels | `GetRadioChannel(true)` export, transmit from `SaltyChat_RadioTrafficStateChanged` |
| `_default` | `MumbleIsConnected` | `NetworkIsPlayerTalking` | one mode, `distance` from `MumbleGetTalkerProximity` | never |

`pma-voice` and `saltychat` register while installed and read their state at call time, so a voice resource that starts after o-link (or after its consumer) is picked up without a restart. With both installed, set `Config.Overrides.Voice` to choose one.

## Module: entity (server + client)

### Server
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Create(data)` | `data: table` | `table` | Create tracked entity record |
| `Destroy(id)` | `id: string\|number` | `nil` | Destroy entity |
| `Get(id)` | `id: string\|number` | `table\|nil` | Get entity |
| `Set(id, data)` | `id: string\|number, data: table` | `boolean` | Merge or update entity |

### Client
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Create(entityData)` | `entityData: table` | `table` | Create client entity wrapper |
| `Destroy(id)` | `id: string\|number` | `nil` | Destroy entity |
| `Get(id)` | `id: string\|number` | `table\|nil` | Get entity |
| `GetAll()` | | `table` | All entities |
| `SetOnCreate(propertyKey, handler)` | `propertyKey: string, handler: function` | `nil` | Register create hook |

## Module: jobcount (server only)

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetJobCount(jobName)` | `jobName: string` | `number` | Count online players for a job |
| `GetJobCountTotal(tbl)` | `tbl: string[]` | `number` | Sum counts across jobs |
| `AddJobCount(src, jobName)` | `src: number, jobName: string` | `nil` | Force-add or update a job count entry |
| `RemoveJobCount(src, jobName?)` | `src: number, jobName?: string` | `nil` | Remove a source from tracking |
| `SearchJobCountBySource(src)` | `src: number` | `string\|nil` | Get tracked job name for a source |

## Module: banking (server only)

Adapter selection follows the standard priority: an explicit `Config.Overrides.Banking` wins; otherwise the first started banking resource registers via its adapter. The `oxide-banking` adapter at [`../modules/banking/oxide-banking/server.lua`](../modules/banking/oxide-banking/server.lua) registers immediately at o-link load time and gates per-call on `IsReady()` / `GetResourceState`.

The universal society/job-account surface (`AddAccountMoney`, `GetAccountMoney`, `RemoveAccountMoney`, `GetManagmentName`, `GetResourceName`) is implemented by every adapter and routes to the appropriate society/job/shared account in each backend. The richer surface below is currently exposed only by the `oxide-banking` adapter; other adapters may not implement it — guard with `olink.supports('banking.<Fn>')`. Account creation (`CreateJobAccount`, `CreatePlayerAccount`) is intentionally oxide-only because other frameworks define jobs/accounts in their own core resource.

### Note on init timing
oxide-banking takes 1-5s after its resource starts to finish DB load (accounts, statements, credit scores, cards). The adapter registers immediately on `'started'` but read-side functions (`GetAccountMoney`, `GetAccount`, `GetCreditScore`, `CanAfford`, `GetPlayerAccounts`, `GetPlayerBankingData`) early-return safe defaults until `IsReady()` returns true. Write-side functions (`AddAccountMoney`, `RemoveAccountMoney`, `CreatePlayerAccount`, `CreateJobAccount`) defer to oxide-banking's own internal guards.

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetResourceName()` | | `string` | Active provider, e.g. `'oxide-banking'` |
| `GetManagmentName()` | | `string` | qb-banking compat surface — same as `GetResourceName` for oxide-banking |
| `GetAccountMoney(accountName)` | `accountName: string` | `number` | Account balance (0 if missing or not ready) |
| `AddAccountMoney(accountName, amount, reason?)` | | `boolean` | Add funds to an account |
| `RemoveAccountMoney(accountName, amount, reason?)` | | `boolean` | Remove funds from an account |
| `IsReady()` | | `boolean` | True once DB load completes (oxide-banking only) |
| `GetAccount(accountName)` | `accountName: string` | `table\|nil` | Account record (oxide-banking only) |
| `CreatePlayerAccount(citizenid, accountName, balance?, users?)` | | `boolean` | Create a new player account (oxide-banking only) |
| `CreateJobAccount(accountName, balance?)` | | `boolean` | Create a new shared job account (oxide-banking only) |
| `GetPlayerAccounts(citizenid)` | `citizenid: string` | `table[]` | All accounts the player has access to (oxide-banking only) |
| `GetPlayerBankingData(citizenid)` | `citizenid: string` | `table\|nil` | Bundled profile (tier, limits, history) (oxide-banking only) |
| `GetCreditScore(citizenid)` | `citizenid: string` | `number` | Credit score (default 600 if missing/not ready) (oxide-banking only) |
| `CanAfford(citizenid, amount, accountName?)` | | `boolean` | Whether the player can withdraw `amount` (oxide-banking only) |

## Module: dispatch (server + client)

The base `SendAlert` contract is supported by every adapter. Adapters backed by
`oxide-dispatch` additionally expose persistent alert management — read/respond/close
— callable from both sides. When a non-persistent adapter is active, the extension
functions return empty results; guard with `olink.supports('dispatch.GetActiveAlerts')`.

The oxide-dispatch adapter at [`../modules/dispatch/oxide-dispatch/(server|client).lua`](../modules/dispatch/oxide-dispatch/server.lua) registers immediately at o-link load time and gates per-call on `GetResourceState`.

### Client

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `SendAlert(data)` | `data: table` | `nil` | Submit a new alert. `data = { code?, title?, message?, priority?, icon?, jobs?, coords?, vehicle_model?, vehicle_plate?, blipData?, expireMinutes?, source_type? }` |
| `GetActiveAlerts(jobFilter?)` | `jobFilter?: string\|string[]` | `table[]` | Active alerts, optionally scoped to a responder group (`'police'`, `'ems'`, `'fire'`) or raw job |
| `GetAlert(alertId)` | `alertId: integer` | `table\|nil` | One alert with responder list |
| `RespondToAlert(alertId)` | `alertId: integer` | `boolean, string?` | Attach self as responder |
| `StopResponding(alertId)` | `alertId: integer` | `boolean` | Detach self as responder |
| `UpdateResponderStatus(alertId, status)` | `alertId: integer, status: 'responding'\|'on_scene'\|'cleared'` | `boolean` | Transition responder status |
| `CloseAlert(alertId, reason?)` | `alertId: integer, reason?: string` | `boolean, string?` | Close an alert |

### Server

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `CreateAlert(data)` | `data: table` | `table\|nil` | Server-authored alert (911, panic, manual) — same shape as `SendAlert`. Implemented by `oxide-dispatch` and the `_default` fallback (notify + blip at `data.coords` for each job member, returns `{ recipients }`); `nil` on every other backend, so relay through a client `SendAlert` on a falsy return |
| `CivilianCall(src, payload)` | `src: number, payload: { channel: '911'\|'311', category?, message?, anonymous?, number?, jobs? }` | `table\|false\|nil, string?` | A 911/311 call from a player's phone at the player's position. `oxide-dispatch` runs it through its civilian call pipeline (categories, zone blacklist, replies to the caller) and returns `{ alertId }`, or `false, reason` when it turns the call down (`'unavailable'` while it is not running); `_default` alerts `payload.jobs` (default police) and returns `{ recipients }`. Every other backend returns `nil`: fall back to `CreateAlert`, then a client `SendAlert` |
| `GetActiveAlerts(jobFilter?)` | `jobFilter?: string\|string[]` | `table[]` | |
| `GetAlert(alertId)` | `alertId: integer` | `table\|nil` | |
| `RespondToAlert(alertId, src)` | `alertId: integer, src: number` | `boolean, string?` | |
| `StopResponding(alertId, src)` | `alertId: integer, src: number` | `boolean` | |
| `UpdateResponderStatus(alertId, src, status)` | `alertId: integer, src: number, status: string` | `boolean` | |
| `CloseAlert(alertId, src?, reason?)` | `alertId: integer, src?: number, reason?: string` | `boolean, string?` | |

### Client-side events (subscribe to these to react to live alert changes)

| Event | Args | Description |
|-------|------|-------------|
| `olink:client:dispatch:alertCreated` | `(alert)` | New alert dispatched to your job |
| `olink:client:dispatch:alertUpdated` | `(alert)` | Responder attached / status change |
| `olink:client:dispatch:alertClosed` | `(alertId, reason)` | Alert closed (`'closed'` or `'expired'`) |

## Module: weather (server + client, API v2)

Oxide resources must use `olink.weather` for weather access. Provider exports, native weather lookup fallbacks, and provider-specific events belong in the bridge. `oxide-weather` also retains its direct exports for developers who do not use o-link.

The full v2 implementation is `oxide-weather`. Other providers keep their existing client methods, plus engine-backed `IsRainingAt`, `IsCovered` and `GetExposureAt` on the client; the remaining v2 calls return nil/false through the stubs. Check `IsReady()` and returned data, not the existence of a callable stub. A missing provider gives neutral gameplay rather than fabricated temperature/exposure data. Server `GetTime()` returns nil when unavailable so consumers may retain their own documented clock fallback.

| Method | Side | Contract |
| --- | --- | --- |
| `GetResourceName()`, `GetApiVersion()`, `IsReady()` | Both | Selected provider (`none` if unavailable), API version (`2` for this implementation, `0` for a stub), readiness |
| `GetConditionsAt(coords)` | Both | `{ weather, weights, zone, rain, snow, raining, temperature?, wind, snowLevel, season?, blackout }`; temperature is Celsius, wind speed m/s, direction degrees, precipitation/snow level normalized 0–1 |
| `IsRainingAt(coords)`, `GetWindAt(coords)`, `GetTemperatureAt(coords)` | Both | Spatial values including regional blending/fronts; nil when unavailable. Under every other provider the client `IsRainingAt` falls back to the engine's current weather type (`RAIN`, `THUNDER`, `CLEARING`) and ignores `coords` |
| `IsSnowOnGround(coords?)` | Both | Accumulation above the ground threshold; client defaults to local position, server defaults to global accumulation |
| `GetExposureAt(coords, bucket?)` | Server | `{ known, covered?, bucket?, age? }`. Requests a bounded nearby collision probe when needed. Unknown/stale cover is neutral. Bucket defaults to 0 |
| `GetExposureAt(coords?)`, `IsCovered(coords?)` | Client | Local streamed collision probe; may yield briefly. Missing collision returns unknown/nil. Under every other provider the same upward collision probe runs through the fallback, so cover never depends on a weather resource |
| `RegisterExposureEntity(entity)`, `UnregisterExposureEntity(entity)` | Client | Register a crop prop to exclude its own collider from nearby roof tests. Ownership and dead handles are cleaned up. Re-register streamed props on weather ready |
| `GetPlayerExposure(src)` | Server | Server weather + fresh body cover, wetness, configured clothing insulation, and temperature; the consumer computes its own thermal effects |
| `GetRoadConditionsAt(coords)` | Both | `{ wetness, ice, cellSize }`; nil outside the configured grid or when unavailable. Client getter may yield and uses a short cache |
| `GetSetting(key)` | Server | Copy of saved configuration; restart-only edits may differ from current simulation settings |
| `SetSetting(key, value, actor?)` | Server | Validates and persists an editable setting; uses the standard original-resource allowlist and optional admin actor gate. Settings marked for restart remain staged |
| `GetWeatherData()` | Client | Current player's server-resolved weather/forecast data; yields through the bridge callback |
| `HoldLocalWeather(weather?)`, `ReleaseLocalWeather()` | Client | Shows `weather` (a weather type name, `EXTRASUNNY` by default) to this player only, and keeps it until released: for a walk-in space that is not a real interior. Under every provider and none: the provider's sync is paused and the clock and its minute length are put back, so time of day keeps running (every provider's own `ToggleSync(false)` moves the clock). A dry weather type also stops the rain. Holds belong to the calling resource, are released when it stops, and the newest hold's weather shows. `false` for an unknown weather type |
| `GetWeatherData(zone?)` | Server | Existing global or regional data contract |
| `GetWeatherAlerts(zone?)`, `GenerateWeazelReport(zone?, options?)` | Server | Phase 6 alert/report read APIs through the bridge |

Existing server getters and setters are also exposed: time/freeze/timescale, global and regional weather/forecast, seasons/holidays, fronts, blackout schedules, clock controls and scene locks. Signatures match oxide-weather's direct exports, including the optional final admin actor argument. Existing client getters and `ToggleSync(enabled, owner?)` remain available.

Mutations capture the invoking resource in o-link and forward it over a weather-side guarded call. `Config.SetterResources` applies to the **original resource**, not a blanket o-link permission; any supplied actor is still admin-checked. Scene locks retain that original owner. `WeatherBridge` and `WeatherReadBridge` are reserved adapter transports, not consumer APIs.

```lua
local weather = exports['o-link']:olink().weather
local conditions = weather.GetConditionsAt(coords)
local exposure = weather.GetExposureAt(coords, bucket)
-- Apply this resource's growth policy only when exposure is known and uncovered.
local roads = weather.GetRoadConditionsAt(coords)
-- Server automation must be allowlisted in oxide-weather/shared/config.lua:
local ok, reason = weather.SetWeather('RAIN', adminSource)
local report = weather.GenerateWeazelReport('paleto', { unit = 'F' })
```

Normalized server events: `olink:server:weather:timeChanged`, `clockProgress`, `weatherChanged`, `zoneWeatherChanged`, `seasonChanged`, `blackoutChanged`, `alertsChanged`, `ready`, and `stopped` (all use the same prefix). `clockProgress` is `{ minutes, frozen }`, where minutes is cumulative simulated time since the provider boot; it does not increase on manual SetTime. Client lifecycle events are `olink:client:weather:ready` and `stopped`.

Client cover observations cannot be treated as a server collision oracle. The weather service binds leases to the selected nearby source, registered coordinates and routing bucket, validates freshness, and derives modifiers itself. Server-configured covered areas override probe reports.

## Module: tablet (server + client)

Optional UI host. `oxide-tablet` draws a tablet shell (bezel, launcher, hold animation, focus, ESC) and hosts other resources' existing NUI bundles as apps: each app is an `<iframe>` of the owning resource's own `web/dist` at `https://cfx-nui-<resource>/<url>?tabletHost=oxide-tablet&tabletApp=<id>`. Consumers never depend on the tablet. The stubs return `false` / `'none'`, so gate on the return value (or `GetResourceState('oxide-tablet') == 'started'` plus `olink.tablet.GetResourceName() == 'oxide-tablet'`), never on `olink.supports('tablet')`, and fall back to your own UI.

Reference adapter: [`../modules/tablet/oxide-tablet/client.lua`](../modules/tablet/oxide-tablet/client.lua) (circular provider: registers at o-link load and gates per call on `GetResourceState`). Reference consumer: `oxide-police` (`client/modules/mdt.lua` `PoliceMDT.SyncTabletApp`, `client/modules/nui.lua` `PoliceNUI.PushMdt`). Web-side shim for hosted apps: `tools/templates/web_tablet_host.js`.

### Client

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `RegisterApp(def)` | `def: table` | `boolean` | Make an app available. `def = { id, label, icon, resource (required), url? = 'web/dist/index.html', query?, requires? = { jobs?, gangs?, duty? }, order?, color?, readyTimeoutMs?, description?, tagline?, category?, publisher?, version? }`. `id` is 1 to 64 characters of `A-Z a-z 0-9 _ -`. `requires` hides the app from the launcher and the store, and its widgets and notifications with it; when the player stops qualifying, an app on screen is closed (re-checked on `olink:client:jobChanged` and `olink:client:gangChanged`). `Open(appId)` bypasses it. `query` may not carry `tabletHost`, `tabletApp`, `tabletWidget`, `tabletSize` or `tabletImei`: the tablet sets those and drops them from `query`. Players install apps on each tablet from the built-in App Store (see below); `description` (280 bytes), `publisher` (60) and `version` (24) fall back to the resource's own `fxmanifest.lua` `description`, `author` and `version`, `tagline` (80) is the one-line subtitle (longer text is cut at the byte limit, so keep non-ASCII text well under it), `category` is one of `business`, `finance`, `law`, `medical`, `social`, `utilities` (default), `other`. `system`, `native` and `always` are the tablet's own and are ignored from consumers. `false` when the id is invalid, `label` or `resource` is missing, the resource does not exist, or the id is already registered by another resource |
| `UnregisterApp(id)` | `id: string` | `boolean` | Remove an app and drop its notifications. If it is on screen the player goes back to the launcher first (`appClosed` with reason `unregistered`). The tablet's own App Store and Settings are refused |
| `Open(appId?)` | `appId?: string` | `boolean` | Open the tablet, optionally straight into an app. Idempotent for the app already on screen. `false` when disabled, the app is unknown, the player has the tablet's admin settings editor open, or (only when the tablet is not already open) the player is dead or downed. Opening by id is the resource acting on its own behalf, so it works even when the player has not installed the app (it shows until they go Home; nothing is installed for them) |
| `Close()` | | `boolean` | Put the tablet away |
| `CloseApp(appId)` | `appId: string` | `boolean` | Back to the launcher if `appId` is on screen. `false` when `appId` is not a string or another app is on screen |
| `IsOpen()` | | `boolean` | |
| `GetCurrentApp()` | | `string\|nil` | |
| `Send(appId, message)` | `appId: string, message: { action, data }` | `boolean` | Relay a SendNUIMessage-shaped message into the app on screen; queued until the iframe posts `ready` (the queue holds 100 messages, then drops the oldest). `message.action` must be a string. Only the current app can be targeted, and the tablet's own native apps (App Store, Settings, Maps) are refused |
| `SetBadge(appId, count)` | `appId: string, count: number` | `boolean` | Launcher badge |
| `GetDevice()` | | `table\|nil` | `{ imei, name, battery }` of the device the open tablet was started on. `nil` when closed, when the open session was started by a resource rather than an item, when the tablet's `RequireItem` is off, or when the inventory cannot keep item metadata. An `Open` call while the player already has a tablet out from an item leaves that device session in place. `battery` is the charge as a whole percent (0 to 100): it goes down while the tablet is out, recharges while it is put away, and is kept up to date while the tablet is open. It stays at its stored value when the owner has battery drain turned off |
| `RegisterWidget(def)` | `def: table` | `boolean` | Add a home-screen widget. `def = { id, label, resource (required), type = 'stat' \| 'list' \| 'progress' \| 'text' \| 'frame', sizes? = { 'small', 'medium', 'large' } (first entry is the default; default `{ 'small' }`), icon?, color?, app? (app id opened on tap; the widget is only shown while that app is), requires?, order?, data? (same 8 KB cap as `SetWidgetData`; oversized data is dropped and the widget still registers), url?/query?/readyTimeoutMs? (frame only) }`. Ids follow the `RegisterApp` rules and fail the same way; `query` has the same reserved names. Widget ids are a separate namespace from app ids. Players place widgets from the gallery; nothing is added to their screens automatically |
| `UnregisterWidget(id)` | `id: string` | `boolean` | Remove a widget. A placed instance disappears from the screen; the player's saved slot is kept for when it registers again |
| `SetWidgetData(id, data)` | `id: string, data: table\|nil` | `boolean` | Push the widget's data (see the shapes below). Cached whether or not the tablet is open, so the last value shows as soon as the home screen does. Template widgets re-render; frame widgets receive `{ action: 'tablet:widgetData', data }`. `nil` or an empty table shows the loading state. `false` when unregistered or above 8 KB encoded |
| `Notify(def)` | `def: table` | `string\|false` | Post a push notification for a registered app. `def = { app (required), message (required), title?, icon? (default: the app's icon), id? (caller id, namespaced per app: the same id replaces the record and shows the banner again), data? (table, at most 8 KB encoded, relayed on tap), sound? = true, toast? }`. Kept in memory whether or not the tablet is open; while open a banner drops in under the status bar (skipped when the app is already on screen unless `toast = true`, never when `toast = false`, which also keeps the bubble away while the tablet is closed) and the entry lands in the tray. `title` is cut at 80 characters and `message` at 280. A caller `id` is 1 to 64 characters and may not start with `#`. Returns the id `app:id`; `false` when the app is not registered, notifications are disabled, the player muted the app in the tablet's Settings, `message` is empty, `data` is not a table or is over 8 KB, or `id` is invalid |
| `DismissNotification(id)` | `id: string` | `boolean` | Drop one notification by the id `Notify` returned |
| `ClearNotifications(appId?)` | `appId?: string` | `boolean` | Drop every notification of an app, or all of them when omitted |

### Server

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Open(src, appId?)` | `src: number, appId?: string` | `boolean` | Relay to the client `Open` |
| `Close(src)` | `src: number` | `boolean` | Relay to the client `Close` |
| `Send(src, appId, message)` | `src: number, appId: string, message: table` | `boolean` | Relay to the client `Send` |
| `GetDevice(src)` | `src: number` | `table\|nil` | `{ imei, name, item, slot }` the player's tablet session was started on, resolved from the inventory server-side. `nil` for device-less sessions (started by `Open`, `RequireItem` off, or an inventory that cannot keep item metadata). Key per-device state on this, never on an IMEI a client sent |
| `SetWidgetData(src, id, data)` | `src: number, id: string, data: table\|nil` | `boolean` | Relay to the client `SetWidgetData` |
| `Notify(src, def)` | `src: number, def: table` | `string\|false` | Relay to the client `Notify`. The id is fixed server-side (`def.id`, or generated as `s<n>`, so do not use ids of that form yourself) so it comes back synchronously; a result means relayed, not shown: it comes back even when the player muted the app |
| `DismissNotification(src, id)` | `src: number, id: string` | `boolean` | Relay to the client `DismissNotification` |
| `ClearNotifications(src, appId?)` | `src: number, appId?: string` | `boolean` | Relay to the client `ClearNotifications` |

### Client-side events (local `TriggerEvent`; subscribe with `AddEventHandler`)

| Event | Args | Description |
|-------|------|-------------|
| `olink:client:tablet:ready` | | Tablet client started or restarted: (re)register your apps and widgets, then push widget data |
| `olink:client:tablet:appOpened` | `(appId)` | App put on screen by a launcher tap, a widget tap, a notification tap or `Open`; may fire synchronously inside `Open` |
| `olink:client:tablet:appReady` | `(appId)` | The app's iframe posted `ready`; queued `Send`s were flushed |
| `olink:client:tablet:appClosed` | `(appId, reason)` | `reason` is `home`, `closed`, `switch` or `unregistered` |
| `olink:client:tablet:closed` | | Tablet put away |
| `olink:client:tablet:widgetReady` | `(widgetId)` | A frame widget's iframe posted `ready`; queued `SetWidgetData` was flushed |
| `olink:client:tablet:deviceRenamed` | `(device)` | The player renamed the device the open tablet runs on; `device = { imei, name, battery }` |
| `olink:client:tablet:notificationTapped` | `(id, appId, data)` | The player tapped a notification (banner or tray entry). The app was opened and, when `data` was set, received `{ action = 'tablet:notification', data }` through the relay queue |

### App Store

Registering an app does not put it on anyone's home screen. Every tablet has a built-in App Store (the tablet's own native `app_store` app) listing the apps the player qualifies for (`requires`, plus the item's allowlist); the player installs the ones they want on that device, and the installed set is saved with the device (or the character when the session has no device) next to the home layout. Installed apps then behave exactly as before: they take a home-screen cell, can be hidden into the App Library, carry widgets and notifications. An uninstalled app hides its widgets and notifications too. Server owners control this with `Config.Store` in oxide-tablet (`enabled = false` installs every app automatically, `preinstalled` lists apps installed on every tablet that cannot be uninstalled), and an item in `Config.Items` with an `apps` list is a curated device: what it lists is installed as-is and the store is not offered on it.

### Hosted-app contract (web)

Parent to iframe: `postMessage({ action, data }, '*')`, the SendNUIMessage shape, so existing message listeners work unchanged. Iframe to parent: `postMessage({ type: 'oxide-tablet', event: 'ready' | 'escape' | 'home' | 'close' | 'openApp', app, widget }, '*')`. `home` and `close` both return to the launcher (`appClosed` reason `home` / `closed`); neither puts the tablet away. `escape` applies the owner's ESC setting. Inside the iframe `GetParentResourceName()` is unreliable: derive the resource from `location.hostname` (`cfx-nui-<name>`), never call `SetNuiFocus` while hosted, forward Escape to the host, and post `ready` only after your message listeners exist. Copy `tools/templates/web_tablet_host.js` into the resource as `web/src/utils/host.js`; resources without a bundler (plain `<script>` tags) copy `tools/templates/web_tablet_host_classic.js` as `html/js/host.js` instead, which exposes the same API on `window.OxideTabletHost` (reference: `oxide-vending`). When the tablet was opened from an item the iframe URL also carries `&tabletImei=<imei>`; it is informational only, confirm it server-side with `olink.tablet.GetDevice(src)`.

### Widgets

Widgets sit on the player's home screen next to app tiles. Players decide which widgets they place, at which size, on which page; a resource only registers what is available and pushes data. Four **template** types are rendered by the tablet from the data you push, and `frame` hosts your own page like an app does. Sizes: `small` 2x2 cells, `medium` 4x2, `large` 4x4 (the grid is 8x5 per page).

| Type | `data` shape |
|------|--------------|
| `stat` | `{ value, label, sub?, icon?, trend? = 'up' \| 'down' \| 'flat' \| number }` |
| `list` | `{ title?, summary? = { value, label?, sub?, trend? }, items = { { text, value?, sub?, icon?, color?, trend? }, ... }, empty? }`. `summary` is a headline number drawn above the rows (its own column on `medium`); `trend` on it and on a row is `'up' \| 'down' \| 'flat'`, a number (shown as a signed percentage) or `{ dir, text }` for a pill with its own label such as `+$980`. Rows show `icon` (or the first letter of `text`) on a tile tinted with `color`; `small` cells draw one line per row |
| `progress` | `{ label, value, max? = 100, sub?, color? }` |
| `text` | `{ title?, body }` |
| `frame` | Anything: relayed into the iframe as `{ action: 'tablet:widgetData', data }` |

Register from `olink:client:tablet:ready` exactly as for apps, then `SetWidgetData` whenever the value changes (it is cheap: the tablet only re-renders when open). `data = nil` shows the widget's loading state.

### Hosted-widget contract (web)

A `frame` widget is an iframe of the owning resource's bundle at `https://cfx-nui-<resource>/<url>?tabletHost=oxide-tablet&tabletWidget=<id>&tabletSize=<small|medium|large>[&tabletImei=<imei>]` (no `tabletApp`). The shim exposes `hostedWidget` and `hostedSize`; `isHosted` is true for apps and widgets alike. Post `ready` the same way; data arrives as `{ action: 'tablet:widgetData', data }`. A size change re-mounts the iframe with a new `tabletSize`. `home` and `close` are ignored for widgets, `escape` is forwarded and handled like ESC on the tablet itself; post `openApp` (shim `requestOpenApp(app?)`) to open the widget's app. Never call `SetNuiFocus` from a widget. The frame is destroyed whenever its page is not on screen, so keep startup cheap and expect to receive the last data again after `ready`. Refresh your copy of `web_tablet_host.js` (or the classic port) before shipping a widget: copies made before widgets existed treat a widget frame as a top-level page.

### Notifications

Apps post notifications with `Notify`; the tablet draws them, the app never does. While the tablet is open a banner drops in under the status bar, and tapping the status bar opens the tray: every notification grouped by app, newest first, with per-item dismiss, per-app clear and clear all. Tapping a banner or a tray entry opens the app under the same job and item rules as a launcher tap, relays `{ action = 'tablet:notification', data }` into it once it reports ready, and drops the notification. While the tablet is away a small bubble springs in at the bottom right of the screen (newest on top of a short stack, gone after the configured duration; the tablet's `showWhenClosed` setting turns it off), and the notification waits in memory for the next open. Bubbles only show for apps installed on the tablet the player carries: its install list and its owner's notification preferences are fetched when the character loads. A curated item's `apps` list is not consulted while the tablet is away, so an app that is only on such a list does not bubble. Players can mute an app, silence everything with Do Not Disturb or turn banners off in the tablet's Settings app. They are gone after a character switch, when the app is unregistered or its resource stops, and beyond the server's cap (oldest first).

The tile badge is the larger of `SetBadge` and the app's pending notifications, so `SetBadge(app, 0)` does not hide them: call `ClearNotifications(app)` once the app has handled them itself. Register the app on `olink:client:tablet:ready` before notifying; a notification for an app the tablet does not know is dropped. Only `message`, `title` and the icon reach the screen; `data` stays in Lua until the tap.

## Module: hud (client only)

Lets a resource place its on-screen panels around the server's HUD, hide with it, and stay out of its way, with one set of calls that works whether or not a HUD is installed. A **panel** is any part of your own NUI drawn over the game: a notification area, a stage header, a timer card.

**Start with [HUD.md](HUD.md)**: one call, `AddPanel`, and a complete example of the Lua and the page. The rest of this section is the reference.

Every size and offset is in **vh**, percent of the screen height, so a panel keeps its place at every resolution (the screen is `100 * width / height` vh wide and 100 vh tall; `3` is 32 px at 1080p and 43 px at 1440p). A panel is pinned at one of nine **anchors**: `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right`. Offsets are measured inward from that edge, and from the centre line on a centred axis (positive is right / down), so a `top-right` panel at `{ x = 3, y = 4 }` is drawn with CSS `right: 3vh; top: 4vh`.

Providers:

- `oxide-hud`: the HUD measures its own widgets and places every panel clear of them, of its minimap and logo, of the zones the server reserves in its `Config.ReservedAreas`, and of panels placed before it, in the same order every session; when a column is full, a panel covers the least of other panels instead of the HUD ([HUD.md](HUD.md#where-the-hud-puts-your-panel)). Players can drag panels in the HUD editor (`/hud`), separately on foot and in a vehicle, hide them while editing, and switch them off in game. Circular adapter: while oxide-hud is installed but not running, every call answers as `_default`.
- `_default`: no HUD. A panel registered with an `offset` sits there (kept on screen); one without is placed inside the GTA safe zone, clear of estimated top-corner HUD stacks (45 x 28 vh in each top corner) and the minimap. `essential` and `shareSpot` are accepted and ignored. There is nothing to hide: `SetVisible` returns `false`, `IsVisible` is always `true`, and positions never carry `hidden`. There is no server accent: `GetTheme` returns `nil`.

### Client

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetResourceName()` | | `string` | `'oxide-hud'`, `'_default'`, or `'none'` from the stubs |
| `AddPanel(def, onChange)` | `def: table`, `onChange: function` | `boolean` | Register a panel and call `onChange(panel)` in your resource now and whenever it changes, with `{ id, hosted, show, preview, style, theme, position }`: whether a HUD places it, whether to draw it, whether the HUD editor previews it, CSS for its root element, the server accent (`nil` without one), and the raw position. `def` takes every `RegisterWidget` field plus `hideWith` (the hide reasons it follows, default `{ 'unloaded', 'external', 'pause', 'dead' }`, `false` for none) and `accent` (`false` never sends a theme). o-link follows the HUD's events and registers the panel again when the HUD (re)starts. `false` when `def` is invalid or `onChange` is missing. See [HUD.md](HUD.md) |
| `RemovePanel(id)` | `id: string` | `boolean` | Remove a panel added with `AddPanel` |
| `RegisterWidget(def)` | `def: table` | `position\|false` | Register a panel. `def = { id, label, anchor? = 'top-left', size? = { w, h } (vh, default 20 x 10), offset? = { x, y } (vh), overlay? = false, essential? = false, shareSpot? }`. `id` is 1 to 64 characters of `A-Z a-z 0-9 _ - . :`; prefix it with your resource name. `label` is shown on the panel's placeholder in the HUD editor. `offset` is where you draw the panel today: with no HUD it is used as given, and the HUD starts there and moves the panel only as far as it must; leave it out to be placed clear of everything. `overlay = true` marks a short-lived panel (a prompt, a progress bar, a downed card): it keeps clear of the HUD but not of other panels, and other panels do not move for it. `essential = true` marks a panel the player needs (notifications, a progress bar, a downed card): it can be hidden while the HUD editor is open but never switched off in game. `shareSpot` is a name, in the same characters as `id`, for panels that never show at the same time (one job's stage card and another's): panels with the same `shareSpot` and anchor share one spot instead of stacking, and the editor shows one of them at a time ([the names in use](HUD.md#shared-spots)). Registering the same `id` again updates it. The panel is removed when your resource stops. `false` when `def` is invalid (including a `shareSpot` that is not a name) |
| `UnregisterWidget(id)` | `id: string` | `boolean` | |
| `GetWidgetPosition(id)` | `id: string` | `position\|nil` | |
| `SetVisible(visible)` | `visible: boolean` | `boolean` | Hide (`false`) or show the HUD for your resource, for a full-screen view that runs without NUI focus (a bodycam, CCTV, a camera scene) or a cinematic: call `SetVisible(true)` on every path that closes it. Menus with NUI focus need nothing: the HUD hides for focus already ([HUD.md](HUD.md#menus-inputs-and-full-screen-views)). The HUD stays hidden while any resource holds it hidden, and a hold ends when its resource stops. o-link remembers the hold and applies it again as soon as the HUD (re)starts. `false` with no HUD |
| `KeepVisible(keep)` | `keep: boolean` | `boolean` | Keep the HUD up (`true`) while your resource holds NUI focus that is not a menu, such as a chat input or a remote used while driving; `false` when that focus ends. While any resource keeps it up, NUI focus does not hide the HUD; the pause menu, death and `SetVisible(false)` still do. A keep ends when its resource stops. o-link remembers it and applies it again as soon as the HUD (re)starts. `false` with no HUD |
| `IsVisible()` | | `boolean, string\|nil` | Whether the HUD is shown, and the hide reason (below) while it is not |
| `GetReservedAreas()` | | `table` | `{ measured, screen = { w, h, pixelWidth, pixelHeight }, safeZone = { x, y, w, h }, areas = { { id, kind, x, y, w, h, resource? }, ... } }`, all in vh from the screen's top-left corner. `measured` is `true` when a HUD knows its own layout (oxide-hud) and `false` for `_default`'s estimates. `kind` is `widget`, `minimap` or `logo` (the HUD's own), `reserved` (`Config.ReservedAreas`), `estimate` (`_default`), or `panel` / `overlay` (registered panels, with their `resource`; skip your own ids) |
| `GetTheme()` | | `table\|nil` | The server's accent colour, for panels that want to match the server's branding: `{ accent, light, dark, contrast, locked }`, the colours as lowercase `'#rrggbb'` strings and `locked` a boolean. `nil` when the HUD has no accent set, and always from `_default` (keep your own colours then). See [Theme](#theme) |

A **position** is `{ id, anchor, x, y, w, h, left, top, moved, hidden, hiddenBy }`: the anchor and offsets to draw the panel at, its size, its top-left corner (vh), `moved = true` when the player placed it, and `hidden = true` when your panel must not be drawn. `hiddenBy` says why while it is hidden: `'player'` (the player switched it off in game; never for an `essential` panel) or `'editor'` (only while the HUD editor is open: its eye, another resource soloed, or another panel of its shared spot shown). While the editor is open, `'editor'` comes first, so a panel the editor leaves out says `'editor'` even when it is also switched off in game. Draw the panel only while `hidden` is not `true`, and its edit preview only while `hiddenBy` is not `'editor'` (faded for `'player'`); `_default` and older HUDs leave both fields out. A panel switched off in game stops taking space, so others may move into it; one hidden only in the editor keeps its space. The anchor is always the one you registered. The first position `RegisterWidget` returns can be refined a moment later by `layoutChanged`, once oxide-hud has measured its layout.

### Client-side events (local `TriggerEvent`; subscribe with `AddEventHandler`)

Fired by the HUD resource, never by `_default`.

| Event | Args | Description |
|-------|------|-------------|
| `olink:client:hud:ready` | | The HUD is up for the character (it fires once a character loads, not when the HUD resource starts): register (again) here as well as at your own start, which covers the HUD starting after you and restarting. `SetVisible` and `KeepVisible` holds need no call here: o-link applies them again when the HUD starts |
| `olink:client:hud:layoutChanged` | `(positions)` | Something moved or a panel was hidden or shown: a drag in the editor (while the panel moves, about ten times a second), an on-foot/in-vehicle switch, a HUD widget change, a resolution change, another panel, the player hiding a panel in game or in the editor, the editor opening or closing. `positions` maps every registered `id` to its position; read your own ids. Call `GetReservedAreas()` again if you use it |
| `olink:client:hud:visibilityChanged` | `(visible, reason)` | The HUD was hidden or shown. `reason` while hidden, the first that applies: `unloaded` (character select, not loaded yet), `external` (a resource called `SetVisible(false)` for a full-screen view or a cinematic), `pause` (pause menu), `dead` (dead or downed), `phone` (phone open), `focus` (a NUI page has focus and no resource holds `KeepVisible`). `nil` when visible. Follow only the reasons that suit your panel: a downed card must not hide for `dead`, and a stage HUD whose own menus take focus must not hide for `focus` |
| `olink:client:hud:editMode` | `(enabled)` | The HUD editor opened or closed: while it is open, draw your panel with sample content (or the real panel, if it is up) where your position puts it, so the player can see what they are placing. Draw it while `hiddenBy` is not `'editor'`, which is exactly when the editor draws its placeholder, and faded for `'player'`. The editor relays positions just before this event as it opens and just after it as it closes, so a panel the editor leaves out never flashes a preview |
| `olink:client:hud:themeChanged` | `(theme)` | The server accent appeared or went away: fired with the theme when the HUD starts and with `nil` when it stops, only when the HUD has an accent set. `theme` is shaped like `GetTheme()` |

### Pattern

Use `AddPanel`. [HUD.md](HUD.md) starts with a complete example of the Lua and the page, then covers the options, shared spots, previews in `/hud`, hiding with the HUD, the accent, full-screen views and testing without a HUD.

With the lower-level calls instead: register at your own start and on `olink:client:hud:ready`; apply positions from `RegisterWidget` and `layoutChanged` only while `GetReservedAreas().measured` is true, so the panel stays where it is without a HUD; read `IsVisible()` when you register, because events only report changes; and pin your page's element at the anchor (`right: <x>vh; top: <y>vh` for `top-right`, `left: calc(50% + <x>vh)` with `translateX(-50%)` on a centred axis). Functions reach your resource as callable tables, so check the member and `pcall` it. On an o-link without the hud namespace `olink.hud` is `nil`, so guard every call. Resources that start before o-link (UI providers such as a notification or progress bar resource) look the namespace up at call time: `GetResourceState('o-link') == 'started'`, then `exports['o-link']:olink().hud`.

### Theme

A server sets one accent colour in its HUD (oxide-hud: `Config.Theme.accent`); `GetTheme()` returns it with the shades derived from it, so panels can match the server's branding. `AddPanel` sends the same table as `panel.theme`, unless the panel was added with `accent = false`.

| Field | Use |
|-------|-----|
| `accent` | Where your panel uses its own accent today: bars, fills, borders, icons, glows. A colour too dark to read on a dark panel is already lightened just enough (3:1 against `#0f1113`) |
| `light` | `accent` toward white, at least 4.5:1 against `#0f1113`: accent-coloured text and highlights |
| `dark` | `accent` toward black: gradient ends, deep fills, pressed states |
| `contrast` | `'#ffffff'` or `'#0f1113'`: text and icons drawn on a solid `accent` fill |
| `locked` | `true` when the server does not let players replace the accent with colours of their own (oxide-hud: `Config.Theme.lockAccent`). If your panel offers player colours, ignore them where the accent would show |

Only replace your accent. Colours that carry meaning (good, warning and bad states; notification types) keep their colours. Give server owners a config switch to keep your own colours. With the lower-level calls, read the theme where you register and on `themeChanged`, and treat anything other than four `'#rrggbb'` strings as no theme.

Reference consumers: `oxide-postaljob` (`AddPanel`: `client/modules/hud.lua`, `web/src/stores/hud.js`), `oxide-chat` (a size that follows the player's settings, and `KeepVisible` around its input: `client/hud.lua`), `oxide-dispatch` (a stack that grows inside its box: `web/src/stores/hud.js`), `oxide-gangs` (a panel drawn with natives: `client/modules/hud.lua`), `oxide-helptext` and `oxide-notify` (`AddPanel` from a resource that starts before o-link: `client/hud.lua`). oxide-hud also has its own exports (`RegisterWidget`, `UnregisterWidget` and `GetWidgetPosition`, in pixels from the top-left corner, and `SetVisible`) and events (`oxide:hud:ready`, `oxide:hud:widgetUpdate`, `oxide:hud:editMode`). They only work while oxide-hud is running; use `olink.hud`, which works with or without it.

## Module: phone (server + client)

Talks to whichever phone the server runs: `gksphone`, `lb-phone`, `okokPhone`, `oxide-phone`, `qb-phone`, `qs-smartphone` (Quasar V3, with the older Lite build as a fallback), `qs-smartphone-pro` or `yseries`. With no phone installed the `_default` adapter answers every call with its default and warns once per function. Not every phone supports every function; see the phone row in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md).

### Is a real phone installed?

Call `IsAvailable()`. It is `true` only while a real phone provider is running; `_default` and the stubs return `false` and never warn. Do not compare `GetResourceName()` with `'none'`: `_default` returns `'_default'`, like every `_default` adapter in o-link. Do not gate on `olink.supports('phone.SendEmail')` either, which is also true for the stubs.

`IsAvailable` is new in this version. A released resource that may run against an older o-link must not call it unguarded:

```lua
local function phoneAvailable()
    local fn = olink.phone and olink.phone.IsAvailable
    if fn then
        local ok, result = pcall(fn)
        if ok then return result and true or false end
    end
    local name = olink.phone and olink.phone.GetResourceName and olink.phone.GetResourceName()
    return name ~= nil and name ~= 'none' and name ~= '_default'
end
```

Functions reached through `exports['o-link']:olink()` cross the resource boundary as callable tables, so `type(fn) == 'function'` is false in your resource: nil-check the member and call it through `pcall`. Apply the same guard to any other function added in this version (`SendMessage`, `SendNotification`, `SendEmailOffline`, `GetSourceByNumber`, `GetNumbersByIdentifier`, `IsOpen`).

### Server

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `IsAvailable()` | | `boolean` | A real phone is running |
| `GetResourceName()` / `GetPhoneName()` | | `string` | Provider name; `'_default'` with no phone |
| `GetPlayerPhone(src)` | `src: number` | `string\|false` | The player's current number |
| `GetSourceByNumber(number)` | `number: string` | `number\|nil` | The online player using that number |
| `GetNumbersByIdentifier(identifier)` | `identifier: string` | `string[]` | Numbers registered to a character, online or offline. `{}` where the phone cannot answer |
| `SendEmail(src, sender, subject, message)` | `src: number, sender: string, subject: string, message: string` | `boolean` | Mail to an online player. `sender` is a display name ("Pizza This - Vespucci"); phones whose sender field is an address get a slug (`pizza-this-vespucci@service.com`) and keep the name where they have a name field. A real address passes through unchanged |
| `SendEmailOffline(identifier, sender, subject, message)` | `identifier: string, ...` | `boolean` | Mail to a character who may be offline. `false` on phones that cannot deliver it |
| `SendMessage(src, sender, message)` | `src: number, sender: string, message: string` | `boolean` | A text from a named service. Phones that cannot text from a name deliver it as mail (`subject` = `sender`) |
| `SendNotification(src, data)` | `src: number, data: { title, message, icon?, app? }` | `boolean` | A push notification on the phone |
| `Open(src, appId?)`, `Close(src)`, `Send(src, appId, message)`, `SetWidgetData(src, id, data)`, `Notify(src, def)`, `DismissNotification(src, id)`, `ClearNotifications(src, appId?)` | as `olink.tablet` | as `olink.tablet` | App host, shaped like the tablet's. Implemented by `oxide-phone` only; `false` on every other provider |
| `AppService(appId, method, params?)` | `appId: string, method: string, params?: table` | `boolean, any` | A phone service for a hosted app's own server (accounts, media the app got, location, the phone's id, evidence): `true, result` or `false, reason`. The phone checks that the calling resource declares `appId` in its manifest (o-link passes the caller on). Implemented by `oxide-phone` only; `false, 'unsupported'` elsewhere. Methods: oxide-phone's `docs/BUILDING-APPS.md` §10 |

### Client

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `IsAvailable()` | | `boolean` | A real phone is running |
| `GetResourceName()` / `GetPhoneName()` | | `string` | Provider name |
| `SendEmail(sender, subject, message)` | `sender: string, subject: string, message: string` | `boolean` | Mail to the local player. Most phones relay it through the server, which checks types, caps the lengths (100 / 100 / 2000) and allows one mail per player every 5 seconds |
| `IsOpen()` | | `boolean` | The phone is on screen |
| `RegisterApp`, `UnregisterApp`, `Open`, `Close`, `CloseApp`, `GetCurrentApp`, `Send`, `SetBadge`, `RegisterWidget`, `UnregisterWidget`, `SetWidgetData`, `Notify`, `DismissNotification`, `ClearNotifications` | as `olink.tablet` | as `olink.tablet` | App host. Implemented by `oxide-phone` only; `false` (`GetCurrentApp`: `nil`) elsewhere. Check the return value of `RegisterApp` |

### Provider precedence

When several phones are installed, o-link uses the first one that is started, and `qb-phone` steps aside for any other phone. `oxide-phone` starts after o-link, so it is chosen when it is installed: it wins over `qb-phone`, and it steps aside for any other phone that is already running (`gksphone`, `lb-phone`, `okokPhone`, `qs-smartphone`, `qs-smartphone-pro`, `yseries`). While `oxide-phone` is installed but stopped, its functions return their defaults and `IsAvailable()` is `false`. To pick a phone yourself, set `Config.Overrides.Phone` in o-link's `config.lua` to its folder name (for example `'qb-phone'`).

## Additional verified namespaces

These namespaces are present in the current implementation and load through the same self-registration pattern, but this file does not attempt to fully document every function signature in every implementation:

| Namespace | Side | Verified implementation folders |
|-----------|------|---------------------------------|
| `fuel` | client | 14 |
| `weather` | client + server (oxide-weather v2) | 5 client providers; full gameplay API on oxide-weather |
| `input` | client | 3 |
| `menu` | client | 5 |
| `radial` | client | 2 |
| `zones` | client | 2 |
| `banking` | server | 9 |
| `clothing` | shared + server + client | 7 |
| `dispatch` | server + client | 16 |
| `doorlock` | server + client | 4 |
| `housing` | server + client | 5 |
| `bossmenu` | server + client | 3 |
| `skills` | server + client | 4 |
| `vehicleOwnership` | server | 4 |
| `death` | server + client | 4 |
| `medical` | server + client | 1 |
| `gang` | server + client | 12 |

**Gang helpers (server)**

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Get(src)` | `src: number` | `table\|nil` | Normalized gang data `{ name, label, grade, gradeLabel, rank }` |
| `Set(src, name, label?, gradeName?, gradeLabel?, gradeRank?)` | | `boolean` | Assign gang (or `nil`/`'none'` to clear) |
| `DoesPlayerHaveGang(src, gangName, minGrade?)` | `src: number, gangName: string, minGrade: number\|nil` | `boolean` | True if player belongs to gang (optionally at or above the given grade) |
| `GetAll()` | | `table[]` | All gangs `{ id, name, label, color, motto, memberCount }` (oxide-gangs only; `{}` elsewhere) |
| `GetMembers(gangName)` | `gangName: string` | `table[]` | Members `{ charId, name, rank, gradeLabel, online }` (oxide-gangs only) |
| `GetGrades(gangName)` | `gangName: string` | `table[]` | Grades `{ rank, name, label, isBoss, permissions }` (oxide-gangs only) |
| `HasPermission(src, perm)` | `src: number, perm: string` | `boolean` | Whether the player's gang grade holds a permission flag (oxide-gangs only) |
| `AddToTreasury(gangName, amount, description?)` | | `boolean` | Credit a gang treasury (oxide-gangs only) |
| `RemoveFromTreasury(gangName, amount, description?)` | | `boolean` | Debit a gang treasury; fails on insufficient funds (oxide-gangs only) |
| `GetTreasury(gangName)` | `gangName: string` | `number` | Current treasury balance (oxide-gangs only; `0` elsewhere) |
| `GetTerritories()` | | `table[]` | Enabled territories `{ id, name, label, color, center, owner = {name,label,color}\|nil, contested, contestEndsAt (epoch sec)\|nil, modifiers\|nil, standings }` (oxide-gangs only; `{}` elsewhere) |
| `GetTerritoryAt(coords)` / `GetTerritoryAt(x, y, z)` | | `table\|nil` | Territory containing the point, same shape as above (`nil` outside every zone or without oxide-gangs). `modifiers` keys `yield`/`growth`/`price`/`buyerDensity` each default to `1.0` when absent |
| `GetTerritoryOwner(territoryId)` | `territoryId: number` | `string\|nil` | Owning gang name (oxide-gangs only) |
| `ReportDrugSale(src, coords, value)` | `src: number, coords: table, value: number` | `number` | Report a completed NPC drug sale; the seller's gang earns territory influence where it happened. Returns influence applied (`0` when capped, gangless, outside zones, or without oxide-gangs). Fire-and-forget |

The extended functions are provided by the `oxide-gangs` registry when installed; on other backends the stubs return the defaults noted above. Because stubs are callable, gate on the return value (or `olink.gang.GetResourceName() == 'oxide-gangs'`), not on `olink.supports('gang')`.

Client side additionally exposes `Get()` (reads the server-written `oxide:gang` statebag), `GetAll()`, `GetGrades(gangName)`, and `HasPermission(perm)`.

**Gang lifecycle events (oxide-gangs)**

| Event | Side | Payload | Description |
|-------|------|---------|-------------|
| `olink:server:gangChanged` | server | `(src, gangName\|nil)` | Player joined, left, or changed rank in a gang (`nil` = now gangless). Treat handlers as idempotent. |
| `olink:client:gangChanged` | client | `(gangData\|nil)` | Local player's gang changed; full statebag payload |

**Medical exposure (server, oxide-medical)**

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `ReportExposure(src, hazard, amount, data?)` | `src: number, hazard: string, amount: number, data: table\|nil` | `boolean` | Tell the medical resource a player breathed an environmental hazard it knows (`'smoke'`: `amount` is smoke density 0 to 1 times the seconds breathed). The medical resource decides the condition, symptoms and harm. `data = { source? }` names the reporter. `true` when it took the exposure (including a downed or exempt player it leaves alone); `false` for an unknown hazard, a bad amount, a player with no medical record, or no medical resource, so the caller deals the harm itself |

Report about once a second while the player breathes the hazard. The stub returns `false`, so gate on the return value rather than `olink.supports('medical')`.

**Clothing helpers (server, adapter-dependent)**

Functions common across `esx_skin`, `qb-clothing`, `fivem-appearance`, `illenium-appearance`, `rcore_clothing`, `oxide-clothing`:

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetAppearance(src, fullData?)` | `src: number, fullData?: boolean` | `table\|nil` | Converted skin data, or full data when `fullData` is true |
| `GetOfflineAppearance(charId)` | `charId: number\|string` | `table\|nil` | Appearance snapshot keyed by character id, shaped for `SetAppearance(ped, data)` — used to dress multichar preview peds |
| `SetAppearance(src, data, updateBackup?, save?)` | | `table\|nil` | Apply appearance and (optionally) persist to DB |
| `SaveCreatorAppearance(src, data, save?)` | `src: number, data: table` | `boolean` | Persist a full look from a built-in creator (face + clothing + tattoos). `data` is the native-indexed canonical shape (features 0-19, overlays 0-12 with 1-based style, components/props maps). Implemented by `illenium-appearance`, `qb-clothing`, `fivem-appearance`; returns `false` on backends that can't store it (e.g. `esx_skin`) so callers can fall back |
| `SetAppearanceExt(src, data)` | | `nil` | Apply gender-specific data (`{ male = ..., female = ... }`) |
| `Revert(src)` | `src: number` | `table\|nil` | Restore previous backup appearance |
| `OpenMenu(src)` | `src: number` | `nil` | Open the adapter's clothing menu for the player |
| `IsMale(src)` | `src: number` | `boolean` | True when the player ped uses the male freemode model |
| `SaveOutfit(src, name, data)` | | `number\|nil` | Persist a named outfit, returns its id |
| `GetOutfits(src)` | | `table[]` | Saved outfits for the player |
| `UpdateOutfit(src, outfitId, name, data)` | | `boolean` | Update a stored outfit |
| `DeleteOutfit(src, outfitId)` | | `boolean` | Delete a stored outfit |
| `Save(src)` | `src: number` | `boolean` | Flush cached skin to DB (esx_skin) |

Adapter-specific: `esx_skin` and `qb-clothing` use the framework's native table (`users.skin` / `playerskins`); `fivem-appearance` mirrors QB-style storage. The shared helpers (`EsxSkinConvertTo/FromDefault`, `QbClothingConvertTo/FromDefault`) live in each adapter's `shared.lua`.

**Clothing creator flow (client)**

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `StartCreation(gender, onDone)` | `gender: 0\|1, onDone: fun(success: boolean)` | `nil` | Open the framework's appearance editor for a new character and persist the result to the active character; `onDone(success)` fires when finished |
| `ApplyPlayerAppearance()` | | `nil` | Apply the loaded character's stored appearance to the player ped (no-op on frameworks that auto-apply on load) |
| `SetAppearance(ped, data)` | `ped: number, data: table` | `boolean` | Apply an appearance snapshot to a specific ped (used for preview peds) |

**Housing helpers (server, adapter-dependent)**

For the unified multichar spawn flow. `GetOwnedProperties` lists for a selector; `SpawnInside` delegates placement to the property resource (which owns the interior coords / routing bucket); `CreateStartingApartment` grants + enters a free apartment on creation. Implemented by `qb-apartments` (also bridges `qb-houses`), `qbx_properties`, and `esx_property`. o-link only processes the data — the caller (oxide-multichar) owns the apartment definition.

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetOwnedProperties(src, identifier?)` | `src: number, identifier?: string` | `{ id, kind, label, coords? }[]` | Properties the character owns; `kind` is `'apartment'`/`'house'`/`'property'`. `id` is the resource's own property identifier, passed back to `SpawnInside`. `coords` is the property's exterior `{ x, y, z }` when the backend can resolve it (used to place spawn-selector map markers; absent if unknown). Pass `identifier` (citizenid on QB/QBX, ESX identifier) to query a character that isn't loaded yet — used by the spawn selector before login |
| `CreateStartingApartment(src, def)` | `src: number, def: table` | `{ id, label }\|false` | Grant + enter a free starter apartment. `def` is the caller-supplied definition the active backend reads — qb-apartments expects `{ type, label }`; qbx_properties expects `{ label, interior, enter, interact[], stash }` (the qbx_properties apartmentOptions shape). Returns `false` where unsupported (e.g. `esx_property`, which has no free-property concept, or when `def` is missing) so callers spawn at a preset instead |
| `SpawnInside(src, id)` | `src: number, id: any` | `boolean` | Place the player inside an owned property (verifies ownership). Delegates the interior load to the property resource |

**Vehicles helpers (server)**

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `SearchByPlate(plate, limit?)` | | `table[]` | Search by plate |
| `GetByPlate(plate)` | | `table\|nil` | Vehicle record with owner data |
| `GetByOwner(identifier)` | | `table[]` | Vehicles for an owner |
| `IsOwnedBy(src, plate)` | | `boolean` | True if the vehicle with that plate belongs to the player |
| `GetOwnedPlates(src)` | | `string[]` | Plates owned by the player |

## Module: logger (server + client)

Provided by `oxide-logger` when installed, otherwise routed through `ox_lib`. The ox_lib adapter prints structured `[LEVEL][resource][category]` lines to the server/client console for INFO+ events and forwards through `lib.logger` to Datadog / Fivemanage / Loki when the `ox:logger` convar is set. `oxide-logger` adds rotating file logs, dedicated Discord/Fivemanage sinks, and ring-buffered error capture on top. The `/oxide:diag` support snapshot is owned by o-link itself (`core/diag_server.lua`) so every server can produce one; when `oxide-logger` is running, o-link pulls its captured error history into that snapshot via `GetRecentErrors`.

### Server
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Trace(resource, category, message, data?)` | | `boolean` | Trace-level log |
| `Debug(resource, category, message, data?)` | | `boolean` | Debug-level log |
| `Info(resource, category, message, data?)` | | `boolean` | Info-level log |
| `Warn(resource, category, message, data?)` | | `boolean` | Warn-level log |
| `Error(resource, category, message, data?)` | | `boolean` | Error-level log |
| `Fatal(resource, category, message, data?)` | | `boolean` | Fatal-level log |
| `Event(resource, category, eventName, data?)` | | `boolean` | Structured Info-level event log |
| `CaptureError(resource, errorMessage, traceback?, source?)` | | `boolean` | Push an error into the diag ring buffer |
| `SafeCall(fn, resource, category?)` | | `any` | xpcall wrapper that captures errors |
| `SetLevel(resource, level)` | `level: 'trace'\|'debug'\|'info'\|'warn'\|'error'\|'fatal'` | `boolean` | Override the per-resource level at runtime |
| `GetLevel(resource)` | | `string` | Current level for the resource |
| `GetRecentErrors(limit?)` | `limit: number` (default 50) | `table[]\|nil` | Recent captured errors from the ring buffer; `nil` when no provider supplies one. Used by `/oxide:diag` |

### Client
Same surface as server minus `SetLevel`/`GetLevel`/`GetRecentErrors` (level control is server-only — the server owns the sink configuration). Client log calls forward to the server for sink dispatch; only `SafeCall` and the local error ring buffer run client-side.

Categories are free-form strings; the Discord sink uses them to choose a webhook URL via `Config.Discord.Webhooks[category]` with fallback to `default`.

## Lifecycle events

| Event | Side | Args | Description |
|-------|------|------|-------------|
| `olink:server:playerReady` | server | `(source)` | Player is ready |
| `olink:server:playerUnload` | server | `(source)` | Player unload or logout |
| `olink:server:playerDropped` | server | `(source)` | Disconnect |
| `olink:server:jobChanged` | server | `(source, jobName)` | Server-side job change relay |
| `olink:server:dutyChanged` | server | `(source, onDuty, jobName?)` | Server-side duty toggle relay |
| `olink:client:playerReady` | client | none | Local player ready |
| `olink:client:playerUnload` | client | none | Local player unloaded |
| `olink:client:jobChanged` | client | `(jobData)` | Local job update |

`olink:server:dutyChanged` may fire more than once for a single change on some frameworks (qb-compat event echoes), and on ESX a duty flip also fires `olink:server:jobChanged` (duty is emulated via `setJob`). Treat handlers as idempotent. `jobName` can be `nil` if the job could not be resolved at fire time.

## Death helpers (client)

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `IsPlayerDowned()` | | `boolean` | Local player is in the downed/laststand state |
| `IsPlayerDead()` | | `boolean` | Local player is fully dead |
| `GetDeathState()` | | `table\|nil` | Provider-shaped death state snapshot |
| `SetSuppressed(value)` | `value: boolean` | `boolean` | Suspend/resume the provider's local death detection while a tool manipulates the player ped (e.g. the scene director possessing an actor swaps the player model mid-session). Returns `true` only when the death provider honoured it. The QBCore, Qbox and ESX providers return `false`, so callers must keep their own backstop (invincibility) regardless |

## Death lifecycle events

Normalized death events emitted by the death adapters. Granular events fire alongside the canonical `playerDeathStateChanged` so consumers can subscribe to whichever fits.

| Event | Side | Args |
|-------|------|------|
| `olink:server:playerDied` | server | `(source, data)` |
| `olink:server:playerDowned` | server | `(source, data)` |
| `olink:server:playerRevived` | server | `(source, data)` |
| `olink:server:playerRespawned` | server | `(source, data)` |
| `olink:server:playerDeathStateChanged` | server | `(source, newState, oldState, data)` |
| `olink:client:playerDied` | client | `(data)` |
| `olink:client:playerDowned` | client | `(data)` |
| `olink:client:playerRevived` | client | `(data)` |
| `olink:client:playerRespawned` | client | `(data)` |
| `olink:client:playerDeathStateChanged` | client | `(newState, oldState, data)` |

`state` is `'alive' | 'dead' | 'downed'`.

`data` is a best-effort table — all fields optional. Adapters fill what their framework provides:

```lua
data = {
    attacker = nil, -- number | nil  (server id of killer / reviver)
    weapon   = nil, -- string | number | nil
    cause    = nil, -- string | nil
    coords   = nil, -- vector3 | nil
}
```

### Per-framework caveats

- **ESX (`es_extended`)** — no native downed/laststand concept; `playerDowned` never fires. Death payload includes `attacker`, `weapon`, `cause`, `coords` from `esx:onPlayerDeath`. `playerRespawned` is not emitted (ESX does not distinguish revive from respawn).
- **QB-Core (`qb-core`)** — payloads are empty `{}` on death/downed/revive transitions because `hospital:server:SetDeathStatus` and `hospital:server:SetLaststandStatus` carry no killer info. Source-of-truth is metadata `isdead` / `inlaststand` (no statebag); the client relay reads it from `QBCore:Player:UpdatePlayerDataField` (current qb-core) and `QBCore:Player:SetPlayerData` (older builds). The server relay hears `hospital:server:SetDeathStatus` / `SetLaststandStatus` only as a cue: it never trusts their argument, reads the sender's own metadata once the event's handlers have run, and accepts at most 20 of them per player in 10 seconds. On both sides, `alive` after `downed` is relayed half a second late, so a bleed-out (last stand cleared, then `isdead` set) goes straight from `downed` to `dead`. `playerRespawned` is not emitted.
- **QBX (`qbx_core`)** — death/downed payloads include `attacker` and `weapon`. `playerRespawned` is not emitted (qbx_medical reports respawn as a revive).
- **`_default` fallback** — when no supported framework or medical resource is detected, a 500ms client poll on `IsPedDeadOrDying` emits `playerDied` / `playerRevived` only (no downed, no payload).
