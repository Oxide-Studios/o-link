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
| `GetName()` | | `string` | Framework name: `'oxide-core'`, `'qb-core'`, `'qbx_core'`, or `'es_extended'` |
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

Character lifecycle (list/create/select/delete) for a framework-agnostic multicharacter resource. The provider is the framework core (`oxide-core`, `qbx_core`, `qb-core`, or `es_extended`). When no provider is installed the defaults return empty results.

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

The client adapter bridges the framework's native "show character selection" trigger to a unified `olink:client:startCharacterSelect` event (fired on boot and after `Logout`).

`OnboardNewCharacter` is the single onboarding seam — it folds together apartment selection (QBX `apartments:client:setupSpawnUI`, QB `qb-spawn:client:setupSpawns`), default-spawn selection, and first-character clothing (`qb-clothes:client:CreateFirstCharacter`) per framework. The oxide-core adapter currently just calls `olink.clothing.StartCreation` since Oxide has no housing/spawn resources yet; when those land, slot them in ahead of the clothing call and the multichar resource itself stays untouched.

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

## Module: money (server only)

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Add(src, accountType, amount, reason?)` | `src: number, accountType: string, amount: number, reason?: string` | `boolean` | Add money to an online player |
| `Remove(src, accountType, amount, reason?)` | `src: number, accountType: string, amount: number, reason?: string` | `boolean` | Remove money from an online player |
| `GetBalance(src, accountType)` | `src: number, accountType: string` | `number` | Online balance |
| `AddOffline(identifier, accountType, amount)` | `identifier: string, accountType: string, amount: number` | `boolean` | Add money offline |
| `RemoveOffline(identifier, accountType, amount)` | `identifier: string, accountType: string, amount: number` | `boolean` | Remove money offline |
| `GetBalanceOffline(identifier, accountType)` | `identifier: string, accountType: string` | `number` | Offline balance |

## Module: license (server only)

Licenses are bool flags keyed by license type (`'driver'`, `'weapon'`, `'business'`, etc.). The bridge does not validate type names — the consumer (e.g. oxide-police) owns the type catalogue. On QB/QBX/Oxide, types are arbitrary strings stored in player metadata. On ESX, types must exist in the `licenses` table (`esx_license`) for ESX-aware UIs to label them; the bridge will still write rows for unknown types but server owners should seed the table for consistency.

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

`identifier` matches `character.GetIdentifier(src)` — citizenid on QB/QBX, ESX identifier on es_extended, state_id (or numeric char_id) on oxide-core.

Storage:
- **qb-core / qbx_core** — `players.metadata.licences` (British spelling) as `{ [type]=bool }`.
- **es_extended** — rows in `user_licenses` keyed by player identifier.
- **oxide-core** — `characters.metadata.licenses` as `{ [type]=bool }`.

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
| `AddStashItem(id, item, count, metadata?)` | | `boolean` | Add one item to a stash |
| `AddStashItems(id, items)` | `items: { item, count\|amount, metadata\|info }[]` | `boolean` | Add several |
| `RemoveStashItem(id, item, count)` | | `boolean` | Remove from a stash |
| `ClearStash(id, type?, netId?)` | `type?: 'stash'\|'trunk'\|'glovebox'` | `boolean` | Empty a container. With `'trunk'`/`'glovebox'`, `id` is the **plate** and the adapter derives the container id. |
| `AddTrunkItems(plate, items, netId?)` | `items: { item, count\|amount, metadata\|info }[]` | `boolean` | Put items in a vehicle's trunk |
| `GetTrunkItems(plate, netId?)` | `plate: string, netId?: number` | `table[]\|nil` | Read a trunk's contents. **`nil` when the inventory cannot read one** -- never `{}`, which would be indistinguishable from an empty trunk. |
| `UpdatePlate(oldPlate, newPlate)` | | `boolean` | Move vehicle storage to a new plate |
| `OpenShop(src, shopId)` / `RegisterShop(...)` | | `boolean` | Shop passthrough |

**Trunk support is not universal.** `AddTrunkItems` / `GetTrunkItems` are real on
`ox_inventory`, `oxide-inventory`, `qb-inventory`, `ak47_qb_inventory` and (add only)
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

Provided by `oxide-vehicles` adapter at [`../modules/vehicles/oxide-vehicles/server.lua`](../modules/vehicles/oxide-vehicles/server.lua) (registered immediately at o-link load; wrappers gate on resource state at call time). Generic helpers `IsOwnedBy` / `GetOwnedPlates` come from [`../modules/vehicles/server.lua`](../modules/vehicles/server.lua).

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetResourceName()` |  | `string` | Active provider, e.g. `'oxide-vehicles'` |
| `SearchByPlate(plate, limit?)` | `plate: string, limit?: number` | `table[]` | Fuzzy plate search joined with owner record |
| `GetByPlate(plate)` | `plate: string` | `table\|nil` | Vehicle record + owner fields (`charId`, `ownerFirst`, `ownerStateId`, etc.) |
| `GetByOwner(identifier)` | `identifier: string` (stateId or charId) | `table[]` | Vehicles for an owner |
| `IsOwnedBy(src, plate)` | `src: number, plate: string` | `boolean` | Whether the plate belongs to the calling player |
| `GetOwnedPlates(src)` | `src: number` | `string[]` | Plates owned by the calling player |
| `GeneratePlate()` |  | `string` | Generate a unique plate per resource conventions |
| `RegisterVehicle(charId, model, plate, props?, type?)` | | `boolean` | Insert an owned vehicle row |
| `UnregisterVehicle(plate)` | `plate: string` | `boolean` | Delete an owned vehicle row |
| `GetVehicleOwner(plate)` | `plate: string` | `number\|nil` | Owner charId for a plate |
| `GetOwnedVehicles(charId)` | `charId: number` | `table[]` | All owned vehicles for a charId |
| `GetVehicleByPlate(plate)` | `plate: string` | `table\|nil` | Raw vehicle row (does NOT join characters) |
| `TransferOwnership(plate, newCharId)` | | `boolean` | Reassign owned vehicle to a new charId |
| `GiveKey(charId, plate, model?)` | | `boolean` | Grant key (item or session) for plate |
| `RemoveKey(charId, plate)` | | `boolean` | Revoke key for plate |
| `HasKey(charId, plate)` | | `boolean` | Whether the player has a key |
| `GetKeysForPlayer(charId)` | | `table[]` | All keys held by the player |
| `IsVehicleLocked(plate)` | | `boolean` | Vehicle locked state |
| `SetVehicleLocked(plate, locked)` | | `boolean` | Lock/unlock and sync to entity |
| `ImpoundVehicle(plate, fee?, lot?)` | | `boolean` | Impound the vehicle |
| `ReleaseImpound(plate)` | | `boolean` | Release from impound (admin/no-fee) |
| `GetImpoundedVehicles(charId, lot?)` | `charId: string\|number, lot?: string` | `table[]` | List vehicles in impound owned by `charId`, optionally filtered to `lot`. Each row: `{ id, plate, model, vehicleType, fee, props, lot }`. `fee = nil` means the framework has no fee column — caller must apply its own fee policy. |
| `RetrieveImpounded(src, vehicleId, lot?)` | `src: number, vehicleId: number\|string, lot?: string` | `boolean, errorReason?` | Validate ownership, deduct any framework-native fee, flip state out of impound. Caller spawns the vehicle from `props` returned by the prior `GetImpoundedVehicles` call. When the framework has no fee column (ESX), the bridge skips fee deduction and the caller is responsible. |
| `GetVehicleState(plate)` | | `any` | Internal state snapshot |
| `SaveVehicleProps(plate, propsJson)` | | `boolean` | Persist serialized properties |
| `RepairVehicle(plate)` | | `boolean` | Mark vehicle fully repaired |
| `AddSharedVehicle(groupType, groupName, model, plate, type?, garage?)` | | `boolean` | Add a job/gang shared vehicle |
| `RemoveSharedVehicle(plate)` | | `boolean` | Remove a shared vehicle |
| `GetSharedVehicles(groupType, groupName)` | | `table[]` | List shared vehicles for a group |

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

Controls — aim phase: mouse to aim, scroll wheel to rotate heading (LSHIFT = fine 1°), LMB confirm, RMB / ESC / Backspace cancel. **Enter opens the fine-tune gizmo**: mouse-drag the colored axes (X red / Y green / Z blue) to slide the preview, scroll to rotate (Shift fine), arrow keys nudge (Ctrl+Up/Down = height, Space cycles the step 0.01/0.05/0.25/1.0m), Enter confirms, Backspace re-aims, ESC cancels. **RMB during fine-tune enters look mode** — NUI focus is released so the admin can move/look freely without losing the session; RMB or Enter resumes the gizmo. `Coord` gets a translate-only gizmo (no rotation). Screen placements additionally support **tilt** (Ctrl+Scroll pitches the panel ±90° in both phases) and show **gold edge handles** on the quad — drag them (or Shift+arrows) to resize width/height during fine-tune, on top of the aim-phase arrow-key resize. MLO interior props are unreliable ray targets — aim near the spot and use the gizmo to land exactly. Polygon builder is a freecam authoring tool (Enter place, arrows nudge, Space save).

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Coord(opts?)` | `opts?: { initialCoords? }` | `{x,y,z}\|nil` | Raycast point picker (no preview entity). Aim marker is a translucent sphere + center dot on the hit point |
| `Entity()` | | `{x,y,z,w}\|nil` | Raycast entity picker — the entity under the crosshair highlights with an outline; LMB snaps to its center (returns the entity origin + heading). For points that belong to a prop/ped/vehicle already in the world (stashes, doors, machines). No fine-tune gizmo — LMB select, RMB/ESC cancel |
| `GhostPed(opts)` | `opts: { model, initialHeading?, anim?, zOffset? }` | `{x,y,z,w}\|nil` | Place a translucent ghost ped; `w` = heading. `anim = { dict, clip }` previews a looped pose with **per-frame pelvis compensation** — the visible body (not the ped origin) stays centered on the aim point, and the RETURNED coords are the compensated entity transform (replay via `TaskPlayAnim` + `SetEntityCoordsNoOffset` at those coords to reproduce the preview). Without `anim`, coords are the raw surface hit (preview lifted `zOffset`, default 1.0) |
| `GhostVehicle(opts)` | `opts: { model, initialHeading? }` | `{x,y,z,w}\|nil` | Place a translucent ghost vehicle; `w` = heading |
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

### Server
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Show(src, message, position?)` | `src: number, message: string, position?: string` | `nil` | Relay helptext to a client |
| `Hide(src)` | `src: number` | `nil` | Hide helptext for a client |

### Client
| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Show(message, position?)` | `message: string, position?: string` | `nil` | Show helptext locally |
| `Hide()` | | `nil` | Hide helptext locally |

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
| `CreateAlert(data)` | `data: table` | `table\|nil` | Server-authored alert (911, panic, manual) — same shape as `SendAlert` |
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
| `RegisterApp(def)` | `def: table` | `boolean` | Make an app available. `def = { id, label, icon, resource (required), url? = 'web/dist/index.html', query?, requires? = { jobs?, gangs?, duty? }, order?, color?, readyTimeoutMs?, description?, tagline?, category?, publisher? }`. `requires` filters the launcher and the store only. Players install apps on each tablet from the built-in App Store (see below); `description` (280 chars), `publisher` (60) and the version shown there fall back to the resource's own `fxmanifest.lua` `description`, `author` and `version`, `tagline` (80) is the one-line subtitle, `category` is one of `business`, `finance`, `law`, `medical`, `social`, `utilities` (default), `other`. `system` and `native` are the tablet's own and are ignored from consumers |
| `UnregisterApp(id)` | `id: string` | `boolean` | Remove an app (leaves it if on screen) |
| `Open(appId?)` | `appId?: string` | `boolean` | Open the tablet, optionally straight into an app. Idempotent for the app already on screen. `false` when disabled, dead/downed, or the app is unknown. Opening by id is the resource acting on its own behalf, so it works even when the player has not installed the app (it shows until they go Home; nothing is installed for them) |
| `Close()` | | `boolean` | Put the tablet away |
| `CloseApp(appId)` | `appId: string` | `boolean` | Back to the launcher if `appId` is on screen |
| `IsOpen()` | | `boolean` | |
| `GetCurrentApp()` | | `string\|nil` | |
| `Send(appId, message)` | `appId: string, message: { action, data }` | `boolean` | Relay a SendNUIMessage-shaped message into the app on screen; queued until the iframe posts `ready`. Only the current app can be targeted |
| `SetBadge(appId, count)` | `appId: string, count: number` | `boolean` | Launcher badge |
| `GetDevice()` | | `table\|nil` | `{ imei, name, battery }` of the device the open tablet was started on. `nil` when closed, opened by a resource rather than an item, or the inventory cannot keep item metadata |
| `RegisterWidget(def)` | `def: table` | `boolean` | Add a home-screen widget. `def = { id, label, resource (required), type = 'stat' \| 'list' \| 'progress' \| 'text' \| 'frame', sizes? = { 'small', 'medium', 'large' } (first entry is the default; default `{ 'small' }`), icon?, color?, app? (app id opened on tap; the widget is only shown while that app is), requires?, order?, data?, url?/query?/readyTimeoutMs? (frame only) }`. Widget ids are a separate namespace from app ids. Players place widgets from the gallery; nothing is added to their screens automatically |
| `UnregisterWidget(id)` | `id: string` | `boolean` | Remove a widget. A placed instance disappears from the screen; the player's saved slot is kept for when it registers again |
| `SetWidgetData(id, data)` | `id: string, data: table\|nil` | `boolean` | Push the widget's data (see the shapes below). Cached whether or not the tablet is open, so the last value shows as soon as the home screen does. Template widgets re-render; frame widgets receive `{ action: 'tablet:widgetData', data }`. `false` when unregistered or above 8 KB encoded |
| `Notify(def)` | `def: table` | `string\|false` | Post a push notification for a registered app. `def = { app (required), message (required), title?, icon? (default: the app's icon), id? (caller id, namespaced per app: the same id replaces the record and shows the banner again), data? (table, at most 8 KB encoded, relayed on tap), sound? = true, toast? }`. Kept in memory whether or not the tablet is open; while open a banner drops in under the status bar (skipped when the app is already on screen unless `toast = true`, never when `toast = false`) and the entry lands in the tray. Returns the id `app:id`; `false` when the app is not registered or notifications are disabled |
| `DismissNotification(id)` | `id: string` | `boolean` | Drop one notification by the id `Notify` returned |
| `ClearNotifications(appId?)` | `appId?: string` | `boolean` | Drop every notification of an app, or all of them when omitted |

### Server

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `Open(src, appId?)` | `src: number, appId?: string` | `boolean` | Relay to the client `Open` |
| `Close(src)` | `src: number` | `boolean` | Relay to the client `Close` |
| `Send(src, appId, message)` | `src: number, appId: string, message: table` | `boolean` | Relay to the client `Send` |
| `GetDevice(src)` | `src: number` | `table\|nil` | `{ imei, name, item, slot }` the player's open tablet was started on, resolved from the inventory server-side. `nil` for device-less sessions. Key per-device state on this, never on an IMEI a client sent |
| `SetWidgetData(src, id, data)` | `src: number, id: string, data: table\|nil` | `boolean` | Relay to the client `SetWidgetData` |
| `Notify(src, def)` | `src: number, def: table` | `string\|false` | Relay to the client `Notify`. The id is fixed server-side (`def.id` or generated) so it comes back synchronously; a result means relayed, not shown |
| `DismissNotification(src, id)` | `src: number, id: string` | `boolean` | Relay to the client `DismissNotification` |
| `ClearNotifications(src, appId?)` | `src: number, appId?: string` | `boolean` | Relay to the client `ClearNotifications` |

### Client-side events (local `TriggerEvent`; subscribe with `AddEventHandler`)

| Event | Args | Description |
|-------|------|-------------|
| `olink:client:tablet:ready` | | Tablet client started or restarted: (re)register your apps and widgets, then push widget data |
| `olink:client:tablet:appOpened` | `(appId)` | App put on screen by a launcher tap or `Open`; may fire synchronously inside `Open` |
| `olink:client:tablet:appReady` | `(appId)` | The app's iframe posted `ready`; queued `Send`s were flushed |
| `olink:client:tablet:appClosed` | `(appId, reason)` | `reason` is `home`, `closed`, `switch` or `unregistered` |
| `olink:client:tablet:closed` | | Tablet put away |
| `olink:client:tablet:widgetReady` | `(widgetId)` | A frame widget's iframe posted `ready`; queued `SetWidgetData` was flushed |
| `olink:client:tablet:deviceRenamed` | `(device)` | The player renamed the device the open tablet runs on; `device = { imei, name, battery }` |
| `olink:client:tablet:notificationTapped` | `(id, appId, data)` | The player tapped a notification (banner or tray entry). The app was opened and, when `data` was set, received `{ action = 'tablet:notification', data }` through the relay queue |

### App Store

Registering an app does not put it on anyone's home screen. Every tablet has a built-in App Store (the tablet's own native `app_store` app) listing the apps the player qualifies for (`requires`, plus the item's allowlist); the player installs the ones they want on that device, and the installed set is saved with the device (or the character when the session has no device) next to the home layout. Installed apps then behave exactly as before: they take a home-screen cell, can be hidden into the App Library, carry widgets and notifications. An uninstalled app hides its widgets and notifications too. Server owners control this with `Config.Store` in oxide-tablet (`enabled = false` installs every app automatically, `preinstalled` lists apps installed on every tablet that cannot be uninstalled), and an item in `Config.Items` with an `apps` list is a curated device: what it lists is installed as-is and the store is not offered on it.

### Hosted-app contract (web)

Parent to iframe: `postMessage({ action, data }, '*')`, the SendNUIMessage shape, so existing message listeners work unchanged. Iframe to parent: `postMessage({ type: 'oxide-tablet', event: 'ready' | 'escape' | 'home' | 'close', app }, '*')`. Inside the iframe `GetParentResourceName()` is unreliable: derive the resource from `location.hostname` (`cfx-nui-<name>`), never call `SetNuiFocus` while hosted, forward Escape to the host, and post `ready` only after your message listeners exist. Copy `tools/templates/web_tablet_host.js` into the resource as `web/src/utils/host.js`; resources without a bundler (plain `<script>` tags) copy `tools/templates/web_tablet_host_classic.js` as `html/js/host.js` instead, which exposes the same API on `window.OxideTabletHost` (reference: `oxide-vending`). When the tablet was opened from an item the iframe URL also carries `&tabletImei=<imei>`; it is informational only, confirm it server-side with `olink.tablet.GetDevice(src)`.

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

A `frame` widget is an iframe of the owning resource's bundle at `https://cfx-nui-<resource>/<url>?tabletHost=oxide-tablet&tabletWidget=<id>&tabletSize=<small|medium|large>[&tabletImei=<imei>]` (no `tabletApp`). The shim exposes `hostedWidget` and `hostedSize`; `isHosted` is true for apps and widgets alike. Post `ready` the same way; data arrives as `{ action: 'tablet:widgetData', data }`. A size change re-mounts the iframe with a new `tabletSize`. `escape`, `home` and `close` are ignored for widgets; post `openApp` (shim `requestOpenApp(app?)`) to open the widget's app. Never call `SetNuiFocus` from a widget. The frame is destroyed whenever its page is not on screen, so keep startup cheap and expect to receive the last data again after `ready`. Refresh your copy of `web_tablet_host.js` (or the classic port) before shipping a widget: copies made before widgets existed treat a widget frame as a top-level page.

### Notifications

Apps post notifications with `Notify`; the tablet draws them, the app never does. While the tablet is open a banner drops in under the status bar, and tapping the status bar opens the tray: every notification grouped by app, newest first, with per-item dismiss, per-app clear and clear all. Tapping a banner or a tray entry opens the app under the same job and item rules as a launcher tap, relays `{ action = 'tablet:notification', data }` into it once it reports ready, and drops the notification. While the tablet is away a small bubble springs in at the bottom right of the screen (newest on top of a short stack, gone after the configured duration; the tablet's `showWhenClosed` setting turns it off), and the notification waits in memory for the next open. They are gone after a character switch, when the app is unregistered or its resource stops, and beyond the server's cap (oldest first).

The tile badge is the larger of `SetBadge` and the app's pending notifications, so `SetBadge(app, 0)` does not hide them: call `ClearNotifications(app)` once the app has handled them itself. Register the app on `olink:client:tablet:ready` before notifying; a notification for an app the tablet does not know is dropped. Only `message`, `title` and the icon reach the screen; `data` stays in Lua until the tap.

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
| `phone` | server + client | 7 |
| `clothing` | shared + server + client | 7 |
| `dispatch` | server + client | 16 |
| `doorlock` | server + client | 4 |
| `housing` | server + client | 5 |
| `bossmenu` | server + client | 3 |
| `skills` | server + client | 4 |
| `vehicleOwnership` | server | 4 |
| `death` | server + client | 4 |
| `medical` | server + client | 1 |
| `needs` | server | 4 |
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

**Clothing helpers (server, adapter-dependent)**

Functions common across `esx_skin`, `qb-clothing`, `fivem-appearance`, `illenium-appearance`, `rcore_clothing`, `oxide-clothing`, `oxide-identity`:

| Function | Args | Returns | Description |
|----------|------|---------|-------------|
| `GetAppearance(src, fullData?)` | `src: number, fullData?: boolean` | `table\|nil` | Converted skin data, or full data when `fullData` is true |
| `GetOfflineAppearance(charId)` | `charId: number\|string` | `table\|nil` | Appearance snapshot keyed by character id, shaped for `SetAppearance(ped, data)` — used to dress multichar preview peds |
| `SetAppearance(src, data, updateBackup?, save?)` | | `table\|nil` | Apply appearance and (optionally) persist to DB |
| `SaveCreatorAppearance(src, data, save?)` | `src: number, data: table` | `boolean` | Persist a full look from a built-in creator (face + clothing + tattoos). `data` is the native-indexed canonical shape (features 0-19, overlays 0-12 with 1-based style, components/props maps). Implemented by `oxide-identity`, `illenium-appearance`, `qb-clothing`, `fivem-appearance`; returns `false` on backends that can't store it (e.g. `esx_skin`) so callers can fall back |
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
| `SetSuppressed(value)` | `value: boolean` | `boolean` | Suspend/resume the provider's local death detection while a tool manipulates the player ped (e.g. the scene director possessing an actor swaps the player model mid-session). Returns `true` only when the provider honoured it — currently oxide-death only; every other provider returns `false`, so callers must keep their own backstop (invincibility) regardless |

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
- **QB-Core (`qb-core`)** — payloads are empty `{}` on death/downed/revive transitions because `hospital:server:SetDeathStatus` and `hospital:server:SetLaststandStatus` carry no killer info. Source-of-truth is metadata `isdead` / `inlaststand` (no statebag).
- **QBX (`qbx_core`)** — death/downed payloads include `attacker` and `weapon`. `playerRespawned` is not emitted (qbx_medical reports respawn as a revive).
- **oxide-death** — emits all five events including `playerRespawned`. Payloads include `cause` (causeOfDeath) and `coords`.
- **`_default` fallback** — when no supported framework or medical resource is detected, a 500ms client poll on `IsPedDeadOrDying` emits `playerDied` / `playerRevived` only (no downed, no payload).
