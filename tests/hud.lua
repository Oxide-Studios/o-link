-- Isolated tests for the hud namespace: the screen maths, the `_default` provider (panels
-- placed clear of the estimated corner HUDs and the minimap, inside the safe zone, never hidden,
-- no theme),
-- the oxide-hud adapter at call time (running, installed but stopped, failing exports) and
-- provider selection with overrides, and AddPanel: the panel table a resource's page draws from,
-- following the HUD's events.
local rawprint = print
local output, states, stopHandlers, calls, handlers = {}, {}, {}, {}, {}
local resolution, safeSize, minimap, invoker = { 1920, 1080 }, 1.0, false, 'consumer'
local hudExports = {}

Config = { Debug = false, Overrides = {} }
IsDuplicityVersion = function() return false end
SetTimeout = function() end
GetResourceState = function(name) return states[name] or 'missing' end
GetInvokingResource = function() return invoker end
GetCurrentResourceName = function() return 'o-link' end
GetActiveScreenResolution = function() return resolution[1], resolution[2] end
GetSafeZoneSize = function() return safeSize end
IsMinimapRendering = function() return minimap and 1 or false end
SetScriptGfxAlign = function() end
ResetScriptGfxAlign = function() end
-- Bottom-left aligned like the game: x from the safe edge, y up from the bottom safe edge.
GetScriptGfxPosition = function(x, y)
    local margin = (1 - safeSize) / 2
    return margin + x, 1 - margin + y
end
AddEventHandler = function(name, fn)
    if name == 'onClientResourceStop' then stopHandlers[#stopHandlers + 1] = fn end
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], fn)
end
local function Fire(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end
exports = setmetatable({}, {
    __index = function(_, resource)
        return setmetatable({}, {
            __index = function(_, method)
                return function(_, ...)
                    calls[#calls + 1] = { resource = resource, method = method, args = { ... } }
                    local impl = hudExports[method]
                    if not impl then error('no export ' .. method) end
                    return impl(...)
                end
            end,
        })
    end,
    __call = function() end,
})
print = function(...) output[#output + 1] = table.concat({ ... }, ' ') end

local function Load(scenario, overrides)
    states, stopHandlers, calls, output, handlers = scenario or {}, {}, {}, {}, {}
    Config.Overrides = overrides or {}
    dofile('core/shared.lua')
    dofile('core/defaults_client.lua')
    dofile('modules/hud/shared.lua')
    dofile('modules/hud/_default/client.lua')
    dofile('modules/hud/oxide-hud/client.lua')
    dofile('modules/hud/panels.lua')
end

local function Near(a, b, what)
    assert(type(a) == 'number' and math.abs(a - b) < 0.02, ('%s: %s, expected %s'):format(what, tostring(a), tostring(b)))
end

local function Provider()
    local caps = olink._getCapabilities().hud
    return caps and caps.provider, caps and caps.kind
end

-- Screen maths.
dofile('core/shared.lua')
dofile('modules/hud/shared.lua')
local Hud = olink._hud
local screen = Hud.Screen(1920, 1080)
Near(screen.w, 177.78, '16:9 width in vh')
assert(screen.h == 100, 'the screen is 100 vh tall')
for _, anchor in ipairs({ 'top-left', 'top', 'top-right', 'left', 'center', 'right', 'bottom-left', 'bottom', 'bottom-right' }) do
    local rect = Hud.Rect(anchor, 4, 7, 20, 10, screen)
    local x, y = Hud.Offset(anchor, rect, screen)
    Near(x, 4, anchor .. ' x round trip')
    Near(y, 7, anchor .. ' y round trip')
end
local tr = Hud.Rect('top-right', 3, 4, 20, 10, screen)
Near(tr.x, 177.78 - 3 - 20, 'top-right is measured in from the right edge')
local c = Hud.Rect('center', 0, 0, 20, 10, screen)
Near(c.x, 177.78 / 2 - 10, 'centre x')
Near(c.y, 45, 'centre y')
local br = Hud.Rect('bottom-right', 2, 5, 10, 10, screen)
Near(br.y, 85, 'bottom is measured up from the bottom edge')
assert(not Hud.IsAnchor('middle') and Hud.IsAnchor('bottom'), 'anchor names')
local clamped = Hud.Clamp({ x = 300, y = -5, w = 20, h = 10 }, screen)
Near(clamped.x, 157.78, 'clamped to the right edge')
assert(clamped.y == 0, 'clamped to the top edge')
local safe = Hud.SafeZone(0.9, screen)
Near(safe.x, 8.89, 'safe zone x margin')
Near(safe.y, 5, 'safe zone y margin')
Near(safe.w, 160, 'safe zone width')
local sx, sy = Hud.SafeOffset('top-right', safe)
Near(sx, 9.89, 'safe corner x plus the gap')
Near(sy, 6, 'safe corner y plus the gap')
-- Pushed down past every rect it overlaps, in one column.
local px, py = Hud.Place('top-left', 20, 10, 2, 2, {
    { x = 0, y = 0, w = 30, h = 20 },
    { x = 10, y = 15, w = 10, h = 10 },
    { x = 100, y = 0, w = 10, h = 90 },
}, screen)
Near(px, 2, 'placement keeps x')
Near(py, 26, 'placement moves below the lowest overlapping rect')
-- The bottom row moves up.
local _, by = Hud.Place('bottom-left', 20, 10, 2, 2, { { x = 0, y = 70, w = 40, h = 30 } }, screen)
Near(by, 31, 'bottom panels move up past the rect')
-- A full column: clear of the fixed rects over the others, else where it asked to be, never
-- clamped onto the far edge.
local _, fy = Hud.Place('top-left', 20, 10, 2, 2, { { x = 0, y = 0, w = 40, h = 99 } }, screen)
Near(fy, 2, 'a full column keeps the start')
local corner = { x = 0, y = 0, w = 45, h = 28 }
local _, oy = Hud.Place('top-left', 20, 10, 2, 2, { corner, { x = 0, y = 29, w = 40, h = 70 } }, screen, { corner })
Near(oy, 28, 'no room: clear of the fixed rect, covering the least of the panel below it')
local cluster = { x = 140, y = 70, w = 35, h = 28 }
local _, ty = Hud.Place('top-right', 30, 16.5, 3, 1, { { x = 140, y = 0, w = 40, h = 20 }, { x = 140, y = 36, w = 40, h = 34 }, cluster }, screen, { cluster })
Near(ty, 18.5, 'squeezed in: a sliver over a panel instead of a whole one')
local alerts = { x = 140, y = 0, w = 40, h = 5, essential = true }
local _, ay = Hud.Place('top-right', 30, 20, 3, 1, { alerts, { x = 140, y = 15, w = 40, h = 54 }, cluster }, screen, { cluster })
Near(ay, 5, 'essential rects are covered last')
local _, ly = Hud.Place('bottom-right', 30, 10, 3, 2, { cluster, { x = 140, y = 5, w = 35, h = 65 } }, screen, { cluster })
Near(ly, 30, 'a bottom-row panel stays on the bottom half')
local good = Hud.Normalize({ id = 'res:panel', label = 'Panel' }, 'res')
assert(good and good.anchor == 'top-left' and good.w == 20 and good.h == 10 and good.resource == 'res' and good.x == nil, 'defaults')
for what, def in pairs({
    nothing = nil,
    noId = { label = 'x' },
    badId = { id = 'a b', label = 'x' },
    longId = { id = ('x'):rep(65), label = 'x' },
    noLabel = { id = 'x' },
    badAnchor = { id = 'x', label = 'x', anchor = 'middle' },
    badShareSpot = { id = 'x', label = 'x', shareSpot = 'a b' },
    numberShareSpot = { id = 'x', label = 'x', shareSpot = 3 },
    longShareSpot = { id = 'x', label = 'x', shareSpot = ('x'):rep(65) },
}) do
    assert(Hud.Normalize(def) == false, 'rejects ' .. what)
end
assert(good.essential == false and good.shareSpot == nil, 'not essential, no shared spot by default')
local flagged = Hud.Normalize({ id = 'res:stage', label = 'Stage', essential = true, shareSpot = 'activity:left' }, 'res')
assert(flagged.essential == true and flagged.shareSpot == 'activity:left', 'essential and shareSpot kept')
assert(Hud.Normalize({ id = 'x', label = 'x', essential = 'yes' }).essential == false, 'essential only when true')

-- `_default` with no oxide-hud installed.
resolution, safeSize, minimap = { 1920, 1080 }, 1.0, false
Load()
local provider, kind = Provider()
assert(provider == '_default' and kind == 'fallback', ('provider %s %s'):format(tostring(provider), tostring(kind)))
assert(olink.hud.GetResourceName() == '_default', 'name')
assert(olink.hud.RegisterWidget(nil) == false and olink.hud.RegisterWidget({ id = 'x' }) == false, 'invalid defs are refused')

local fixed = olink.hud.RegisterWidget({ id = 'fire:right', label = 'Fire', anchor = 'top-right', size = { w = 22, h = 34 }, offset = { x = 3, y = 30 } })
assert(fixed and fixed.anchor == 'top-right' and fixed.x == 3 and fixed.y == 30 and fixed.moved == false, 'an offset is used as given')
Near(fixed.left, 177.78 - 3 - 22, 'left of the given offset')
assert(fixed.top == 30 and fixed.w == 22 and fixed.h == 34, 'top and size')

local auto = olink.hud.RegisterWidget({ id = 'notify', label = 'Notify', anchor = 'top-left', size = { w = 30, h = 12 } })
Near(auto.x, 1, 'auto placement starts in the safe zone corner')
Near(auto.y, 29, 'auto placement clears the top-left corner estimate')
local second = olink.hud.RegisterWidget({ id = 'second', label = 'Second', anchor = 'top-left', size = { w = 30, h = 5 } })
Near(second.y, 42, 'the next panel stacks under the first')
local right = olink.hud.RegisterWidget({ id = 'auto:right', label = 'Right', anchor = 'top-right', size = { w = 20, h = 5 } })
Near(right.y, 65, 'the top-right estimate and the fixed fire panel are both cleared')

assert(olink.hud.SetVisible(false) == false, 'nothing to hide')
assert(olink.hud.KeepVisible(true) == false, 'nothing to keep up')
local visible, reason = olink.hud.IsVisible()
assert(visible == true and reason == nil, 'always visible')
assert(olink.hud.GetTheme() == nil, 'no server accent without a HUD')

local areas = olink.hud.GetReservedAreas()
assert(areas.measured == false, 'estimates are not measured')
Near(areas.screen.w, 177.78, 'screen width')
assert(areas.safeZone.x == 0 and areas.safeZone.w == areas.screen.w, 'full safe zone at size 1.0')
local seen = {}
for _, area in ipairs(areas.areas) do seen[area.id] = area end
assert(seen['estimate:top-left'] and seen['estimate:top-right'] and not seen.minimap, 'corner estimates, no minimap while hidden')
assert(seen['fire:right'].kind == 'panel' and seen['fire:right'].resource == 'consumer', 'panels are listed with their resource')

-- The minimap and a smaller safe zone.
minimap, safeSize = true, 0.9
local bl = olink.hud.RegisterWidget({ id = 'bottom', label = 'Bottom', anchor = 'bottom-left', size = { w = 20, h = 8 } })
local mm
for _, area in ipairs(olink.hud.GetReservedAreas().areas) do if area.id == 'minimap' then mm = area end end
assert(mm, 'the minimap is reserved while it renders')
Near(mm.x, 177.78 * 0.0455, 'minimap x follows the safe zone')
Near(mm.y, 95 - 18.89, 'minimap top')
Near(bl.y, 100 - mm.y + 1, 'a bottom-left panel sits above the minimap')

-- The same offsets at other resolutions.
for _, res in ipairs({ { 2560, 1440 }, { 1366, 768 } }) do
    resolution = res
    local pos = olink.hud.GetWidgetPosition('fire:right')
    assert(pos.x == 3 and pos.y == 30, ('vh offsets hold at %dx%d'):format(res[1], res[2]))
end
resolution = { 1280, 1024 }
local narrow = olink.hud.GetWidgetPosition('fire:right')
Near(narrow.left, 125 - 3 - 22, '5:4 keeps the right offset')

local wide = olink.hud.RegisterWidget({ id = 'wide', label = 'Wide', offset = { x = 500, y = 2 }, size = { w = 20, h = 5 } })
Near(wide.left, 105, 'an off-screen offset is clamped on screen')
Near(wide.x, 105, 'and its offset with it')

-- `essential` and `shareSpot` are accepted and ignored: panels sharing a spot stack like any
-- others, and `_default` never hides a panel.
resolution = { 1920, 1080 }
local s1 = olink.hud.RegisterWidget({ id = 's1', label = 'S1', anchor = 'bottom-right', size = { w = 20, h = 6 }, shareSpot = 'activity:right' })
local s2 = olink.hud.RegisterWidget({ id = 's2', label = 'S2', anchor = 'bottom-right', size = { w = 20, h = 6 }, shareSpot = 'activity:right', essential = true })
Near(s2.y, s1.y + 6 + 1, 'no shared spot without a HUD')
assert(olink.hud.RegisterWidget({ id = 'bad', label = 'B', shareSpot = 'a b' }) == false, 'a bad shareSpot is refused')
local ess = olink.hud.RegisterWidget({ id = 'ess', label = 'E', anchor = 'bottom', essential = true, offset = { x = 0, y = 3 } })
assert(ess.y == 3 and ess.hidden == nil and ess.hiddenBy == nil and s1.hidden == nil and s2.hidden == nil, '_default never sets hidden')
for _, id in ipairs({ 's1', 's2', 'ess' }) do olink.hud.UnregisterWidget(id) end
resolution = { 1280, 1024 }

local o1 = olink.hud.RegisterWidget({ id = 'o1', label = 'O1', anchor = 'bottom', size = { w = 30, h = 12 }, offset = { x = 0, y = 8 }, overlay = true })
local o2 = olink.hud.RegisterWidget({ id = 'o2', label = 'O2', anchor = 'bottom', size = { w = 26, h = 5 }, overlay = true })
assert(o1.y == 8, 'an overlay with an offset sits as asked')
Near(o2.y, 6, 'an overlay without an offset ignores other panels: the safe zone corner, over o1')
local kinds = {}
for _, area in ipairs(olink.hud.GetReservedAreas().areas) do kinds[area.id] = area.kind end
assert(kinds.o1 == 'overlay' and kinds['fire:right'] == 'panel', 'overlays are listed as overlays')
olink.hud.UnregisterWidget('o1')
olink.hud.UnregisterWidget('o2')
assert(olink.hud.UnregisterWidget('wide') == true and olink.hud.UnregisterWidget('wide') == false, 'unregister once')
assert(olink.hud.GetWidgetPosition('wide') == nil, 'gone')
for _, fn in ipairs(stopHandlers) do fn('consumer') end
assert(olink.hud.GetWidgetPosition('notify') == nil and olink.hud.GetWidgetPosition('fire:right') == nil, 'panels go with their resource')

-- oxide-hud installed but not running: the adapter owns the namespace and answers like `_default`.
resolution, safeSize, minimap = { 1920, 1080 }, 1.0, false
Load({ ['oxide-hud'] = 'stopped' })
provider, kind = Provider()
assert(provider == 'oxide-hud' and kind == 'real', 'the adapter is registered while oxide-hud is installed')
assert(olink.hud.GetResourceName() == '_default', 'stopped oxide-hud answers as _default')
local fb = olink.hud.RegisterWidget({ id = 'p', label = 'P', anchor = 'top-right', offset = { x = 3, y = 4 } })
assert(fb and fb.x == 3 and fb.y == 4, 'fallback registration')
assert(olink.hud.GetReservedAreas().measured == false, 'fallback areas')
assert(olink.hud.SetVisible(false) == false and olink.hud.IsVisible() == true, 'fallback visibility')
assert(olink.hud.KeepVisible(true) == false, 'fallback keep')
assert(olink.hud.GetTheme() == nil, 'fallback theme')
assert(#calls == 0, 'no export is called while oxide-hud is stopped')

-- oxide-hud running.
Load({ ['oxide-hud'] = 'started' })
local registered, hidden, kept
hudExports = {
    SetKeepVisible = function(owner, value) kept = { owner, value } return true end,
    RegisterPanel = function(def) registered = def return { id = def.id, anchor = def.anchor, x = 1, y = 2 } end,
    UnregisterPanel = function() return true end,
    GetPanelPosition = function(id) return id == 'known' and { id = id } or nil end,
    SetHiddenBy = function(owner, value) hidden = { owner, value } return true end,
    GetVisibility = function() return { visible = false, reason = 'pause' } end,
    GetReservedAreas = function() return { measured = true, areas = { { id = 'hud:w_1' } } } end,
    GetTheme = function() return { accent = '#724cab', light = '#9c82c4', dark = '#4a316f', contrast = '#ffffff', locked = true } end,
}
assert(olink.hud.GetResourceName() == 'oxide-hud', 'name while running')
invoker = 'oxide-fire'
local def = { id = 'fire:left', label = 'Fire', anchor = 'top-left', offset = { x = 3, y = 4 }, essential = false, shareSpot = 'activity:left' }
local pos = olink.hud.RegisterWidget(def)
assert(pos.x == 1 and registered.resource == 'oxide-fire' and def.resource == nil, 'the caller is passed on a copy')
assert(registered.shareSpot == 'activity:left' and registered.essential == false, 'essential and shareSpot reach the HUD')
hudExports.GetPanelPosition = function(id) return { id = id, hidden = true, hiddenBy = 'player' } end
local hiddenPos = olink.hud.GetWidgetPosition('fire:left')
assert(hiddenPos.hidden == true and hiddenPos.hiddenBy == 'player', 'hidden and hiddenBy come back from the HUD')
hudExports.GetPanelPosition = function(id) return id == 'known' and { id = id } or nil end
assert(olink.hud.UnregisterWidget('fire:left') == true, 'unregister')
assert(olink.hud.GetWidgetPosition('known').id == 'known' and olink.hud.GetWidgetPosition('unknown') == nil, 'positions')
assert(olink.hud.SetVisible(false) == true and hidden[1] == 'oxide-fire' and hidden[2] == true, 'SetVisible(false) holds the HUD hidden for the caller')
olink.hud.SetVisible(true)
assert(hidden[2] == false, 'SetVisible(true) releases it')
assert(olink.hud.KeepVisible(true) == true and kept[1] == 'oxide-fire' and kept[2] == true, 'KeepVisible(true) keeps the HUD up for the caller')
olink.hud.KeepVisible(false)
assert(kept[2] == false, 'KeepVisible(false) lets focus hide it again')

-- Holds outlast a HUD restart: o-link applies them again as soon as the HUD starts, before any
-- character loads, and forgets a resource's holds when that resource stops.
local applied = {}
local function Applied()
    local list = {}
    for _, a in ipairs(applied) do list[#list + 1] = table.concat(a, ':') end
    table.sort(list)
    applied = {}
    return table.concat(list, ' ')
end
local setHiddenBy, setKeepVisible = hudExports.SetHiddenBy, hudExports.SetKeepVisible
olink.hud.SetVisible(false)
olink.hud.KeepVisible(true)
invoker = 'oxide-chat'
olink.hud.KeepVisible(true)
olink.hud.KeepVisible(false)
states['oxide-hud'] = 'stopped'
Fire('onClientResourceStop', 'oxide-hud')
invoker = 'oxide-police'
local callsBefore = #calls
assert(olink.hud.SetVisible(false) == false and #calls == callsBefore, 'a hold asked for while the HUD is stopped is only remembered')
hudExports.SetHiddenBy = function(owner, value) applied[#applied + 1] = { 'hide', owner, tostring(value) } return true end
hudExports.SetKeepVisible = function(owner, value) applied[#applied + 1] = { 'keep', owner, tostring(value) } return true end
states['oxide-hud'] = 'started'
Fire('onClientResourceStart', 'oxide-hud')
assert(Applied() == 'hide:oxide-fire:true hide:oxide-police:true keep:oxide-fire:true', 'every current hold is applied again when the HUD starts')
Fire('onClientResourceStart', 'oxide-chat')
assert(Applied() == '', 'another resource starting applies nothing')
Fire('onClientResourceStop', 'oxide-police')
Fire('onClientResourceStart', 'oxide-hud')
assert(Applied() == 'hide:oxide-fire:true keep:oxide-fire:true', 'a stopped resource holds nothing')
invoker = 'oxide-fire'
olink.hud.SetVisible(true)
olink.hud.KeepVisible(false)
applied = {}
Fire('onClientResourceStart', 'oxide-hud')
assert(Applied() == '', 'released holds are not applied again')
hudExports.SetHiddenBy, hudExports.SetKeepVisible = setHiddenBy, setKeepVisible

local v, r = olink.hud.IsVisible()
assert(v == false and r == 'pause', 'visibility and reason')
assert(olink.hud.GetReservedAreas().measured == true, 'areas from the HUD')
local theme = olink.hud.GetTheme()
assert(theme and theme.accent == '#724cab' and theme.contrast == '#ffffff' and theme.locked == true, 'theme from the HUD, with its lock')
hudExports.GetTheme = function() return nil end
assert(olink.hud.GetTheme() == nil, 'no theme when the HUD has none')

hudExports.RegisterPanel = function() error('boom') end
hudExports.GetReservedAreas = function() return 'nope' end
hudExports.GetVisibility = function() error('boom') end
hudExports.GetTheme = function() error('boom') end
assert(olink.hud.RegisterWidget(def) == false, 'a failing export registers nothing')
assert(olink.hud.GetReservedAreas().measured == false, 'a bad answer falls back to the estimates')
assert(olink.hud.IsVisible() == true, 'a failing export reads as visible')
assert(olink.hud.GetTheme() == nil, 'a failing export has no theme')
hudExports.GetTheme = function() return '#724cab' end
assert(olink.hud.GetTheme() == nil, 'a theme that is not a table is ignored')
invoker = 'consumer'

-- AddPanel without a HUD: one call straight away, nothing hosted, the page keeps its own spot.
resolution, safeSize, minimap = { 1920, 1080 }, 1.0, false
Load()
local got = {}
local function Collect(state) got[#got + 1] = state end
assert(olink.hud.AddPanel(nil, Collect) == false, 'no def')
assert(olink.hud.AddPanel({ id = 'consumer:timer', label = 'Timer' }) == false, 'no function')
assert(olink.hud.AddPanel({ id = 'bad id', label = 'Timer' }, Collect) == false, 'a bad def is refused')
assert(#got == 0, 'nothing is called for a refused panel')
assert(olink.hud.AddPanel({ id = 'consumer:timer', label = 'Timer', anchor = 'top', offset = { x = 0, y = 3.5 } }, Collect) == true, 'added')
assert(#got == 1, 'called once straight away')
local s = got[1]
assert(s.id == 'consumer:timer' and s.hosted == false and s.show == true and s.preview == false, 'not hosted, shown, no preview')
assert(s.style.left == '' and s.style.right == '' and s.style.top == '' and s.style.bottom == '' and s.style.opacity == '', 'an empty style keeps the page position')
assert(s.theme == nil and s.position == nil, 'no theme, no position')
assert(olink.hud.GetWidgetPosition('consumer:timer'), 'registered with the provider too')
-- A function from another resource arrives as a callable table.
local fromOtherVm = setmetatable({}, { __call = function(_, state) got[#got + 1] = state end })
assert(olink.hud.AddPanel({ id = 'consumer:card', label = 'Card' }, fromOtherVm) == true and #got == 2, 'a callable table works')
assert(olink.hud.AddPanel({ id = 'consumer:timer', label = 'Timer', anchor = 'top' }, Collect) == true and #got == 3, 'adding again sends again')
assert(olink.hud.RemovePanel('consumer:card') == true and olink.hud.RemovePanel('consumer:card') == false, 'removed once')
assert(olink.hud.GetWidgetPosition('consumer:card') == nil, 'unregistered from the provider')
Fire('olink:client:hud:visibilityChanged', false, 'pause')
assert(#got == 4 and got[4].show == false, 'hidden with a HUD that says so')
for _, fn in ipairs(stopHandlers) do fn('consumer') end
Fire('olink:client:hud:visibilityChanged', true, nil)
assert(#got == 4, 'nothing reaches a stopped resource')

-- AddPanel with oxide-hud running.
Load({ ['oxide-hud'] = 'started' })
local registeredDefs = {}
local nextPos = { anchor = 'top-right', x = 3, y = 4, w = 30, h = 18, left = 144.78, top = 4 }
local visibility = { visible = true }
local hudTheme = { accent = '#724CAB', light = '#9c82c4', dark = '#4a316f', contrast = '#ffffff', locked = false }
hudExports = {
    RegisterPanel = function(def)
        registeredDefs[#registeredDefs + 1] = def
        local pos = {}
        for k, v in pairs(nextPos) do pos[k] = v end
        pos.id = def.id
        return pos
    end,
    UnregisterPanel = function() return true end,
    GetPanelPosition = function() return nil end,
    SetHiddenBy = function() return true end,
    GetVisibility = function() return visibility end,
    GetReservedAreas = function() return { measured = true, areas = {} } end,
    GetTheme = function() return hudTheme end,
}
invoker = 'oxide-postaljob'
got = {}
local tutorial = {}
assert(olink.hud.AddPanel({
    id = 'oxide-postaljob:tutorial', label = 'Tutorial', anchor = 'top-right', size = { w = 30, h = 18 },
    offset = { x = 4, y = 12 }, overlay = true, hideWith = { 'phone' }, accent = false,
}, function(state) tutorial[#tutorial + 1] = state end), 'added on the HUD')
local def = registeredDefs[1]
assert(def.resource == 'oxide-postaljob' and def.overlay == true and def.offset.x == 4 and def.size.w == 30, 'registered for the caller with its own fields')
assert(def.hideWith == nil and def.accent == nil, 'AddPanel options stay in o-link')
s = tutorial[1]
assert(s.hosted == true and s.show == true and s.preview == false, 'hosted')
assert(s.style.right == '3vh' and s.style.top == '4vh' and s.style.left == 'auto' and s.style.bottom == 'auto', 'top-right CSS')
assert(s.position.anchor == 'top-right' and s.position.x == 3, 'the position for panels drawn from Lua')
assert(s.theme == nil, 'accent = false keeps the panel colours')

nextPos = { anchor = 'top', x = 0, y = 3.5, w = 26, h = 6, left = 75.89, top = 3.5 }
assert(olink.hud.AddPanel({ id = 'oxide-postaljob:timer', label = 'Timer', anchor = 'top', shareSpot = 'job-timer' }, Collect))
s = got[1]
assert(s.style.left == 'calc(50% + 0vh)' and s.style.right == 'auto' and s.style.top == '3.5vh', 'a centred axis is measured from the centre line')
assert(s.theme and s.theme.accent == '#724cab' and s.theme.locked == false, 'the server accent, lower case')
assert(registeredDefs[2].shareSpot == 'job-timer', 'shareSpot reaches the HUD')

-- Positions from the HUD's layout reports, sent only when something changed.
local function Layout(timer, extra)
    local list = { ['oxide-postaljob:timer'] = timer, ['oxide-postaljob:tutorial'] = { id = 'oxide-postaljob:tutorial', anchor = 'top-right', x = 3, y = 4, w = 30, h = 18, left = 144.78, top = 4 } }
    for k, v in pairs(extra or {}) do list[k] = v end
    Fire('olink:client:hud:layoutChanged', list)
end
local count = #got
Layout({ id = 'oxide-postaljob:timer', anchor = 'top', x = -2.25, y = 10, w = 26, h = 6, left = 73.64, top = 10 })
assert(#got == count + 1 and got[#got].style.left == 'calc(50% - 2.25vh)' and got[#got].style.top == '10vh', 'moved left of centre')
assert(#tutorial == 1, 'an unchanged panel is not sent again')
Layout({ id = 'oxide-postaljob:timer', anchor = 'top', x = -2.25, y = 10, w = 26, h = 6, left = 73.64, top = 10 }, { other = { id = 'other' } })
assert(#got == count + 1, 'the same layout sends nothing')
Layout({ id = 'oxide-postaljob:timer', anchor = 'bottom-left', x = 1.5, y = 2, w = 26, h = 6, left = 1.5, top = 92 })
s = got[#got]
assert(s.style.left == '1.5vh' and s.style.bottom == '2vh' and s.style.right == 'auto' and s.style.top == 'auto', 'bottom-left CSS')
Layout({ id = 'oxide-postaljob:timer', anchor = 'right', x = 10, y = -4, w = 26, h = 6, left = 141.78, top = 43 })
s = got[#got]
assert(s.style.right == '10vh' and s.style.top == 'calc(50% - 4vh)' and s.style.bottom == 'auto', 'right-middle CSS')
Layout({ id = 'oxide-postaljob:timer', anchor = 'top', x = 0, y = 3.5, w = 26, h = 6, left = 75.89, top = 3.5 })

-- Following the HUD: the default reasons, a panel's own list.
Fire('olink:client:hud:visibilityChanged', false, 'pause')
assert(got[#got].show == false and tutorial[#tutorial].show == true, 'the default follows pause; the tutorial follows only the phone')
Fire('olink:client:hud:visibilityChanged', false, 'phone')
assert(got[#got].show == true and tutorial[#tutorial].show == false, 'the default does not follow the phone')
Fire('olink:client:hud:visibilityChanged', false, 'focus')
assert(got[#got].show == true and tutorial[#tutorial].show == true, 'an unknown reason hides nothing')
for _, reason in ipairs({ 'unloaded', 'external', 'dead' }) do
    Fire('olink:client:hud:visibilityChanged', false, reason)
    assert(got[#got].show == false, 'the default follows ' .. reason)
end
Fire('olink:client:hud:visibilityChanged', true, nil)
assert(got[#got].show == true and tutorial[#tutorial].show == true, 'shown again')
local never = {}
assert(olink.hud.AddPanel({ id = 'oxide-postaljob:never', label = 'Never', hideWith = false }, function(state) never[#never + 1] = state end))
Fire('olink:client:hud:visibilityChanged', false, 'external')
assert(never[#never].show == true, 'hideWith = false never hides with the HUD')
Fire('olink:client:hud:visibilityChanged', true, nil)
olink.hud.RemovePanel('oxide-postaljob:never')

-- The HUD editor: preview while it shows the panel, nothing while it leaves it out, faded
-- while the player has it switched off in game.
Fire('olink:client:hud:editMode', true)
s = got[#got]
assert(s.preview == true and s.show == true and s.style.opacity == '', 'previewing')
Layout({ id = 'oxide-postaljob:timer', anchor = 'top', x = 0, y = 3.5, w = 26, h = 6, left = 75.89, top = 3.5, hidden = true, hiddenBy = 'editor' })
s = got[#got]
assert(s.show == false and s.preview == false, 'left out by the editor')
Layout({ id = 'oxide-postaljob:timer', anchor = 'top', x = 0, y = 3.5, w = 26, h = 6, left = 75.89, top = 3.5, hidden = true, hiddenBy = 'player' })
s = got[#got]
assert(s.show == true and s.preview == true and s.style.opacity == '0.45', 'switched off in game: a faded preview')
Fire('olink:client:hud:editMode', false)
s = got[#got]
assert(s.show == false and s.preview == false and s.style.opacity == '', 'switched off in game once the editor closes')
Layout({ id = 'oxide-postaljob:timer', anchor = 'top', x = 0, y = 3.5, w = 26, h = 6, left = 75.89, top = 3.5 })
assert(got[#got].show == true, 'switched on again')

-- The accent coming and going. The tutorial never had one, so it is not sent again.
local tutorialCount = #tutorial
Fire('olink:client:hud:themeChanged', nil)
assert(got[#got].theme == nil and #tutorial == tutorialCount, 'no accent')
Fire('olink:client:hud:themeChanged', { accent = '#123456', light = '#abcdef', dark = '#000000', contrast = '#ffffff' })
assert(got[#got].theme.accent == '#123456', 'a new accent')
Fire('olink:client:hud:themeChanged', { accent = 'red', light = '#abcdef', dark = '#000000', contrast = '#ffffff' })
assert(got[#got].theme == nil, 'an accent that is not #rrggbb is ignored')
Fire('olink:client:hud:themeChanged', hudTheme)
assert(#tutorial == tutorialCount, 'the tutorial was never sent an accent')

-- The HUD (re)starting registers every panel again.
local before = #registeredDefs
Fire('olink:client:hud:ready')
assert(#registeredDefs == before + 2, 'both panels registered again')
for i = before + 1, #registeredDefs do
    assert(registeredDefs[i].resource == 'oxide-postaljob', 'still registered for their resource')
end

-- A function that fails warns once and the rest carry on.
local failing = 0
assert(olink.hud.AddPanel({ id = 'oxide-postaljob:broken', label = 'Broken' }, function() failing = failing + 1 error('boom') end))
Fire('olink:client:hud:editMode', true)
Fire('olink:client:hud:editMode', false)
assert(failing == 3, 'still called')
local warnings = 0
for _, line in ipairs(output) do if line:find('oxide-postaljob:broken', 1, true) then warnings = warnings + 1 end end
assert(warnings == 1, 'warned once')
olink.hud.RemovePanel('oxide-postaljob:broken')

-- The HUD still answering while it stops: o-link reads it again once the stop has finished.
local later = {}
SetTimeout = function(_, fn) later[#later + 1] = fn end
count = #got
for _, fn in ipairs(stopHandlers) do fn('oxide-hud') end
assert(#got == count and #later == 1, 'still hosted while the HUD answers, so read again after the stop')
states['oxide-hud'] = 'stopped'
later[1]()
assert(#got == count + 1 and got[#got].hosted == false, 'unhosted once the stop has finished')
SetTimeout = function() end
states['oxide-hud'] = 'started'
Fire('olink:client:hud:ready')
assert(got[#got].hosted == true, 'hosted again when the HUD is back')

-- The HUD stopping: every panel goes back to its page's own spot, with its own colours.
states['oxide-hud'] = 'stopping'
count = #got
for _, fn in ipairs(stopHandlers) do fn('oxide-hud') end
s = got[#got]
assert(#got == count + 1 and s.hosted == false and s.style.top == '' and s.style.left == '' and s.theme == nil and s.position == nil, 'unhosted when the HUD stops')
assert(tutorial[#tutorial].hosted == false, 'every panel')
-- And the resource stopping: nothing more is sent to it.
states['oxide-hud'] = 'started'
count = #got
for _, fn in ipairs(stopHandlers) do fn('oxide-postaljob') end
Fire('olink:client:hud:ready')
Fire('olink:client:hud:editMode', true)
assert(#got == count, 'a stopped resource is forgotten')
invoker = 'consumer'

-- Overrides.
Load({ ['oxide-hud'] = 'started' }, { Hud = '_default' })
provider = Provider()
assert(provider == '_default' and olink.hud.GetResourceName() == '_default', 'forced _default with oxide-hud installed')
Load({}, { Hud = 'oxide-hud' })
assert(Provider() == nil and olink.hud.GetResourceName() == 'none', 'forced oxide-hud while missing leaves the stubs')
assert(olink.hud.RegisterWidget({ id = 'x', label = 'x' }) == false and olink.hud.IsVisible() == true, 'stub defaults')
assert(olink.hud.KeepVisible(true) == false, 'stub keep')
assert(type(olink.hud.GetReservedAreas().areas) == 'table', 'stub areas')
assert(olink.hud.GetTheme() == nil, 'stub theme')
local stubbed = {}
for name in pairs(olink.hud) do stubbed[name] = true end

-- Every function either provider registers has a stub.
for name in pairs(olink._hudDefault) do assert(stubbed[name], 'stub for _default ' .. name) end
Load({ ['oxide-hud'] = 'started' })
for name in pairs(olink.hud) do assert(stubbed[name], 'stub for oxide-hud ' .. name) end

print = rawprint
print('hud: all tests passed')
