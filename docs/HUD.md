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
| `offset` | none | `{ x, y }` in vh: where your page draws the panel today, measured in from the anchor's edges. The HUD starts there and moves the panel only as far as it must. Without it, the HUD finds a free spot |
| `shareSpot` | none | A [shared spot](#shared-spots) name |
| `overlay` | `false` | `true` for a panel that only shows briefly (a prompt, a tutorial card): it keeps clear of the HUD, but other panels do not move for it |
| `essential` | `false` | `true` for a panel the player must not miss (a downed card, alerts): it can be hidden in the editor but never switched off in game |
| `hideWith` | `{ 'unloaded', 'external', 'pause', 'dead' }` | The HUD hide reasons this panel follows. `false` never hides with the HUD |
| `accent` | `true` | `false` never sends `theme`. Give server owners a config switch for it |

**Units.** Every size and offset is in **vh**, percent of the screen height, so a panel keeps its place at every resolution. 3 vh is 32 px at 1080p. If your panel is sized in pixels, convert at registration: `local _, height = GetActiveScreenResolution()`, then `w = 300 * 100 / height`.

**Anchors.** The anchor you register never changes, wherever the player drags the panel; only the distances change. On a centred anchor (`top`, `bottom`, `left`, `right`, `center`) the distance is measured from the centre line to the middle of the panel, so centre your element on it, for example with `transform: translateX(-50%)` for `top` and `bottom`. `style` never sets `transform`, so your own transforms and transitions keep working.

Calling `AddPanel` again with the same `id` replaces the panel and sends its state again. `olink.hud.RemovePanel(id)` removes it. Panels are removed when your resource stops.

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
| `external` | A resource hides the HUD for a full-screen view or a cutscene ([Full-screen views](#full-screen-views)) |
| `pause` | The pause menu is open |
| `dead` | The player is dead or downed |
| `phone` | The phone is open |

The default follows the first four. A downed card leaves out `dead` (`hideWith = { 'external', 'pause' }`); a panel that must always show uses `hideWith = false`. NUI focus on its own (the chat input, a remote held while driving) never hides the HUD.

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

## Full-screen views

A menu or camera view that covers the game (a shop, a computer, a character creator, a job menu) hides the HUD while it is open:

```lua
local function openMenu()
    SetNuiFocus(true, true)
    if olink.hud then olink.hud.SetVisible(false) end
end

-- Every way the view closes ends here: the close button, Escape, death, logout.
local function closeMenu()
    SetNuiFocus(false, false)
    if olink.hud then olink.hud.SetVisible(true) end
end
```

- The HUD stays hidden while any resource holds it hidden, and comes back when the last one lets go.
- Your hold ends by itself if your resource stops.
- One hold per resource: if two of your views can be open at once, call `SetVisible(true)` only when the last one closes.
- Other resources' panels hide with it (the `external` reason).

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

- `oxide-postaljob`: `client/modules/hud.lua` (two panels, a shared spot, full-screen views) and `web/src/stores/hud.js` (the page side, previews, the accent).
