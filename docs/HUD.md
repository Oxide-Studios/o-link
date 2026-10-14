# HUD panels

A **panel** is any part of your resource's page that stays on screen while the player plays: a job timer, a stage card, a row of control hints. With one call, `olink.hud.AddPanel`, a server HUD (Oxide HUD today) can do four things for that panel:

- place it clear of the HUD's own parts and of other resources' panels;
- let the player move it, hide it, or switch it off in the HUD editor (`/hud`);
- hide it while the HUD is hidden (pause menu, death, character select, a cutscene);
- give it the server's accent colour.

Your page keeps drawing the panel. It only applies the placement o-link sends it. On a server without a HUD, or with an o-link older than 1.12.0, nothing changes: the panel stays where your page has always drawn it.

`olink.hud` is client-only. Full function list: [API.md, Module: hud](API.md#module-hud-client-only). How Oxide HUD places panels and what its editor does with them: Oxide HUD's `docs/API.md`.

## Your first panel

**`client.lua`**

```lua
olink = exports['o-link']:olink()

-- The page calls this once it is listening, so it never misses the first message.
RegisterNUICallback('pageReady', function(_, cb)
    cb('ok')
    if not (olink.hud and olink.hud.AddPanel) then return end -- an o-link without HUD support

    olink.hud.AddPanel({
        id = 'my-job:timer',      -- unique: start it with your resource name
        label = 'My job: timer',  -- shown on the panel in the /hud editor
        anchor = 'top-right',     -- the corner or edge the panel is pinned to
        size = { w = 24, h = 8 }, -- in vh: percent of the screen height
    }, function(panel)
        SendNUIMessage({ action = 'hudPanel', panel = panel })
    end)
end)
```

**`web/index.html`**

```html
<style>
  /* Where the panel sits without a HUD. Keep it in a stylesheet: the HUD's placement is set
     inline, and when it is cleared your own position comes back. */
  #timer { position: fixed; right: 3vh; top: 4vh; width: 24vh; height: 8vh; }
</style>

<div id="timer">4:32</div>

<script>
  const timer = document.getElementById('timer')

  window.addEventListener('message', (event) => {
    if (event.data.action !== 'hudPanel') return
    const panel = event.data.panel
    Object.assign(timer.style, panel.style)          // where the HUD put it
    timer.style.display = panel.show ? '' : 'none'   // switched off, or hidden with the HUD
  })

  fetch(`https://${GetParentResourceName()}/pageReady`, { method: 'POST', body: '{}' })
</script>
```

That is the whole integration. What happens:

1. The page loads and calls `pageReady`. Lua adds the panel.
2. o-link calls your function straight away, and again every time something about the panel changes: the player drags it, switches it off, opens the editor, the HUD hides or comes back, the HUD restarts. Your function runs in your resource, so `SendNUIMessage` reaches your page.
3. The page applies `panel.style` and `panel.show`. That is all it needs to do.

Without a HUD, `panel.style` holds empty values, so your stylesheet's position stays, and `panel.show` is always `true`.

In a Vue page the same two fields bind directly: `<div v-if="active && panel.show" :style="panel.style">`.

## What your function receives

| Field | Type | Meaning |
|-------|------|---------|
| `id` | string | The panel's id, so one function can serve several panels |
| `hosted` | boolean | `true` while a HUD places the panel. `false` without one: draw it where you always do |
| `show` | boolean | `false` while the panel must not be drawn: the player switched it off, the editor leaves it out, or the HUD is hidden for a reason the panel follows ([Hiding with the HUD](#hiding-with-the-hud)). Draw your panel only while it is `true` |
| `preview` | boolean | `true` while the HUD editor is open and shows this panel. Draw sample content if nothing real is up ([Previews in /hud](#previews-in-hud)) |
| `style` | table | CSS for the panel's root element: `left`, `right`, `top`, `bottom` and `opacity`, as strings. Apply all of them every time. Empty strings hand the position back to your stylesheet |
| `theme` | table or nil | The server's accent colours ([The server accent](#the-server-accent)). `nil` keeps your own colours |
| `position` | table or nil | The raw placement in vh (`anchor`, `x`, `y`, `left`, `top`, `w`, `h`), for panels drawn from Lua instead of a page. `nil` while not hosted |

## The options

Only `id` and `label` are required.

| Option | Default | What it does |
|--------|---------|--------------|
| `id` | required | 1 to 64 characters of `A-Z a-z 0-9 _ - . :`. Start it with your resource name |
| `label` | required | The panel's name in the HUD editor. Pass translated text |
| `anchor` | `'top-left'` | The point the panel is pinned to: `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right` |
| `size` | `{ w = 20, h = 10 }` | The panel's size in vh. The HUD keeps this much space free for it, and the editor draws its box this size |
| `offset` | none | `{ x, y }` in vh: where your page draws the panel today, measured in from the anchor's edges. The HUD starts there and moves the panel only as far as it must ([Where the HUD puts your panel](#where-the-hud-puts-your-panel)). Without it, the HUD finds a free spot |
| `shareSpot` | none | A [shared spot](#shared-spots) name |
| `overlay` | `false` | `true` for a panel that only shows briefly (a prompt, a tutorial card): it keeps clear of the HUD, but other panels do not move for it |
| `essential` | `false` | `true` for a panel the player must not miss (a downed card, alerts): it can be hidden in the editor but never switched off in game |
| `hideWith` | `{ 'unloaded', 'external', 'pause', 'dead' }` | The HUD hide reasons this panel follows. `false` never hides with the HUD |
| `accent` | `true` | `false` never sends `theme`. Give server owners a config switch for it |

**Units.** Every size and offset is in **vh**, percent of the screen height, so a panel keeps its place at every resolution. 3 vh is 32 px at 1080p. If your panel is sized in pixels, convert at registration: `local _, height = GetActiveScreenResolution()`, then `w = 300 * 100 / height`.

**Anchors.** The anchor you register never changes, wherever the player drags the panel; only the distances change. On a centred anchor (`top`, `bottom`, `left`, `right`, `center`) the distance is measured from the centre line to the middle of the panel, so centre your element on it, for example with `transform: translateX(-50%)` for `top` and `bottom`. `style` never sets `transform`, so your own transforms and transitions keep working.

Calling `AddPanel` again with the same `id` replaces the panel and sends its state again. `olink.hud.RemovePanel(id)` removes it. Panels are removed when your resource stops.

## Where the HUD puts your panel

Oxide HUD starts your panel at its `offset` and moves it away from its anchor's edge (down for the top and middle rows, up for the bottom row) to the first spot clear of the HUD's own parts and of the panels placed before it. A panel on the `top` or `bottom` anchor only looks on its own half of the screen, so it never ends up in the middle of the player's view.

When the column is full, it never lands on the vehicle cluster, the minimap or the compass, and it is never pushed to the far edge of the screen. It takes the spot on its own half of the screen, clear of the HUD, that covers the least of the other panels, and it covers essential panels only when every spot would. If not even the HUD leaves room there (a panel taller than the space above the vehicle cluster), it stays at its `offset`.

Panels claim their spots in the same order every session: essential panels first, then the one whose `offset` is nearest its anchor's edge, then by `id`. A panel the player dragged stays exactly where they put it.

What this means for your panel:

- Give the `offset` you want, nearest the edge first: a panel asking to sit 2 vh from the edge is placed before one asking for 12.
- Mark `essential` only for what the player must not miss. Essential panels get their spots first and are covered last.
- Mark anything that shows briefly as `overlay`. Overlays take no space, so they never push your other panels or anyone else's.
- Register the size your panel draws at. A box larger than the panel takes room other panels could use.

### Default spots at the bottom centre

Many resources draw near the bottom centre. Start a short-lived panel in the lane for its kind, so the default layout does not stack them on each other (vh up from the bottom, at 1080p):

| Lane | From | Height | Used by |
|------|------|--------|---------|
| Control hints | 3 to 3.5 | up to 5.5 | the `controls-hint` shared spot |
| Progress bar | 10.4 | 3 | the progress bar (112 px up, 32 px tall) |
| Downed card | 8 | 11.1 | the EMS downed card (120 px tall) |
| Prompt | 20.5 | 4.3 | `oxide-helptext`'s bottom-centre box |

`offset` is where the HUD starts your panel. It is usually where your page draws it without a HUD; a panel whose own spot is in another lane can start in its lane with a HUD and keep its own spot without one, as `oxide-helptext` does.

## Shared spots

A shared spot is one place on screen for panels that never show at the same time, so they take turns instead of stacking down the screen. Panels with the same `shareSpot` and the same anchor share it, and the editor moves them together.

| Spot | Anchor | For |
|------|--------|-----|
| `job-timer` | `top` | The gig jobs' timer cards |
| `drug-stage` | `bottom` | The Meth and Cocaine stage cards |
| `controls-hint` | `bottom` | Control hint rows ("LMB Place, RMB Cancel") |
| `activity:left` | `top-left` | Stage headers (Fire, Weed, Pills) |
| `activity:right` | `top-right` | Tallies and career cards (Fire, Pills) |

Use one of these when your panel fits, so it shares with the others. A new name works too; it only shares with panels that use the same name.

## Previews in /hud

While the player edits their HUD, each panel is a box they drag around. When `preview` is `true`, draw your panel inside that box so they see what they are placing:

- If the real panel is up, it is the preview: draw nothing extra.
- Otherwise draw it with sample content, and stop when `preview` turns `false`.
- Keep it display only: no NUI focus, no input, no sounds, nothing sent to the server.
- A panel the player switched off in game still previews, dimmed: `style.opacity` does that for you.

```js
const drawReal = jobRunning && panel.show
const drawSample = !jobRunning && panel.preview
```

## Hiding with the HUD

`show` turns `false` while the HUD is hidden for one of the reasons in `hideWith`:

| Reason | When |
|--------|------|
| `unloaded` | No character: character select, after logout |
| `external` | A resource hides the HUD for a full-screen view or a cutscene ([Menus, inputs and full-screen views](#menus-inputs-and-full-screen-views)) |
| `pause` | The pause menu is open |
| `dead` | The player is dead or downed |
| `phone` | The phone is open |
| `focus` | A menu or another NUI page has focus (a shop, an inventory) |

The default follows the first four, so your panel stays up while a menu is open over it. A downed card leaves out `dead` (`hideWith = { 'external', 'pause' }`); a panel that should also hide behind menus adds `'focus'`; a panel that must always show uses `hideWith = false`.

## The server accent

`theme` carries the server's accent colours as `'#rrggbb'` strings:

| Field | Use |
|-------|-----|
| `accent` | Where your panel uses its own accent: bars, fills, borders, icons |
| `light` | Accent-coloured text and highlights |
| `dark` | Gradient ends, deep fills |
| `contrast` | Text and icons drawn on a solid `accent` fill |

Replace only your accent. Colours that mean something (green for done, red for late) keep their colours. Put the colours in CSS variables with your own colours as the fallback, so `nil` brings yours back:

```js
const accent = panel.theme ? panel.theme.accent : ''
timer.style.setProperty('--my-accent', accent)   // CSS: background: var(--my-accent, #9b2c2c)
```

Give server owners a switch, on by default, and pass it on: `accent = Config.UseHudAccent ~= false`.

## Menus, inputs and full-screen views

The HUD hides while any NUI page has focus, so most resources need nothing here:

| What your resource shows | What to do |
|--------------------------|------------|
| A menu that takes NUI focus (a shop, a computer, a job menu) | Nothing. The HUD hides while it has focus |
| An input that takes NUI focus while the player keeps playing (a chat input, a remote used while driving) | `KeepVisible(true)` when it takes focus, `KeepVisible(false)` when it lets go |
| A full-screen view without NUI focus (a bodycam, CCTV, a dashcam, a camera scene) | `SetVisible(false)` when it opens, `SetVisible(true)` on every path that closes it |

```lua
-- A chat input: focus, but not a menu.
local function openInput()
    SetNuiFocus(true, false)
    if olink.hud then olink.hud.KeepVisible(true) end
end

local function closeInput()
    SetNuiFocus(false, false)
    if olink.hud then olink.hud.KeepVisible(false) end
end

-- A camera view without focus. Every way it closes ends here: the key, death, logout.
local function startBodycam()
    if olink.hud then olink.hud.SetVisible(false) end
end

local function stopBodycam()
    if olink.hud then olink.hud.SetVisible(true) end
end
```

- While any resource keeps the HUD up, NUI focus does not hide it. The pause menu, death and full-screen views still do.
- While any resource holds the HUD hidden, it stays hidden; other resources' panels hide with it (the `external` reason).
- Both end by themselves if your resource stops.
- Both outlast a HUD restart. o-link remembers every resource's current `SetVisible(false)` and `KeepVisible(true)`, also while the HUD is stopped, and applies them again the moment Oxide HUD starts (`onClientResourceStart`), before any character has loaded, so a hold made at character select is back straight away. You do not need to call either again on `olink:client:hud:ready`; doing so is harmless.
- One of each per resource: if two of your views can be open at once, call `KeepVisible(false)` or `SetVisible(true)` only when the last one closes.

## Without a HUD, and on older o-link

Guard every call. On o-link 1.11.0 and older `olink.hud` is `nil`:

```lua
if olink.hud and olink.hud.AddPanel then ... end   -- adding panels
if olink.hud then olink.hud.SetVisible(false) end  -- any other olink.hud call
```

| Situation | What your panel gets |
|-----------|----------------------|
| No HUD installed, or Oxide HUD stopped | One call with `hosted = false`, empty `style`, `show = true`. No more calls until a HUD starts |
| Oxide HUD starts or restarts later | o-link adds your panel to it and calls your function again. Nothing to do on your side |
| Oxide HUD stops | One call with `hosted = false`: the panel goes back to its own spot and colours |
| o-link 1.11.0 or older | Nothing. Your guard skips the call |

To test your resource, check each of these:

1. With Oxide HUD running: `/hud` shows your panel's box with your preview in it. Drag it, switch it off with **Show in game**, open the pause menu.
2. Stop the HUD (`stop oxide-hud` in the server console). The panel goes back to its own spot straight away.
3. Without a HUD at all: set `Config.Overrides.Hud = '_default'` in o-link's `config.lua` and restart. The panel draws exactly as before you added it.
4. As on o-link 1.11.0: add `olink.hud = nil` after `exports['o-link']:olink()` in a test copy. The resource must start and work unchanged.

## Resources that start before o-link

A resource that o-link itself depends on (a notification or progress bar provider) cannot keep `olink` from load time. Look the namespace up when you need it and add the panel again on `olink:client:hud:ready`:

```lua
local function hud()
    if GetResourceState('o-link') ~= 'started' then return nil end
    local ok, bridge = pcall(function() return exports['o-link']:olink() end)
    return ok and bridge and bridge.hud or nil
end
```

## Lower-level calls

`AddPanel` is built on `RegisterWidget`, `IsVisible`, `GetTheme` and the `olink:client:hud:*` events, all listed in [API.md](API.md#module-hud-client-only). Use those only if `AddPanel` does not fit, for example to read `GetReservedAreas()` and lay out several panels yourself.

## Reference

- `oxide-postaljob`: `client/modules/hud.lua` (two panels, a shared spot) and `web/src/stores/hud.js` (the page side, previews, the accent). Its shift menu takes NUI focus, so it needs no HUD call.
- `oxide-chat`: `client/hud.lua` (a size that follows the player's chat settings, `KeepVisible` around its input).
- `oxide-dispatch`: `web/src/stores/hud.js` (a stack that grows inside its box, up or down from where the HUD puts it).
- `oxide-gangs`: `client/modules/hud.lua` (a bar drawn with natives from `panel.position`).
- `oxide-helptext`: `client/hud.lua` (a resource that starts before o-link, and a box that starts in its lane with a HUD).
