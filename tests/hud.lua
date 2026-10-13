-- Isolated tests for the hud namespace: the screen maths, the `_default` provider (panels
-- placed clear of the estimated corner HUDs and the minimap, inside the safe zone, never hidden,
-- no theme),
-- the oxide-hud adapter at call time (running, installed but stopped, failing exports) and
-- provider selection with overrides.
local rawprint = print
local output, states, stopHandlers, calls = {}, {}, {}, {}
local resolution, safeSize, minimap, invoker = { 1920, 1080 }, 1.0, false, 'consumer'
local hudExports = {}

Config = { Debug = false, Overrides = {} }
IsDuplicityVersion = function() return false end
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
    states, stopHandlers, calls, output = scenario or {}, {}, {}, {}
    Config.Overrides = overrides or {}
    dofile('core/shared.lua')
    dofile('core/defaults_client.lua')
    dofile('modules/hud/shared.lua')
    dofile('modules/hud/_default/client.lua')
    dofile('modules/hud/oxide-hud/client.lua')
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
-- A full column keeps the panel on screen.
local _, fy = Hud.Place('top-left', 20, 10, 2, 2, { { x = 0, y = 0, w = 40, h = 99 } }, screen)
Near(fy, 90, 'a full column clamps to the bottom edge')
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
assert(olink.hud.GetTheme() == nil, 'fallback theme')
assert(#calls == 0, 'no export is called while oxide-hud is stopped')

-- oxide-hud running.
Load({ ['oxide-hud'] = 'started' })
local registered, hidden
hudExports = {
    RegisterPanel = function(def) registered = def return { id = def.id, anchor = def.anchor, x = 1, y = 2 } end,
    UnregisterPanel = function() return true end,
    GetPanelPosition = function(id) return id == 'known' and { id = id } or nil end,
    SetHiddenBy = function(owner, value) hidden = { owner, value } return true end,
    GetVisibility = function() return { visible = false, reason = 'pause' } end,
    GetReservedAreas = function() return { measured = true, areas = { { id = 'hud:w_1' } } } end,
    GetTheme = function() return { accent = '#724cab', light = '#9c82c4', dark = '#4a316f', contrast = '#ffffff' } end,
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
local v, r = olink.hud.IsVisible()
assert(v == false and r == 'pause', 'visibility and reason')
assert(olink.hud.GetReservedAreas().measured == true, 'areas from the HUD')
local theme = olink.hud.GetTheme()
assert(theme and theme.accent == '#724cab' and theme.contrast == '#ffffff', 'theme from the HUD')
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

-- Overrides.
Load({ ['oxide-hud'] = 'started' }, { Hud = '_default' })
provider = Provider()
assert(provider == '_default' and olink.hud.GetResourceName() == '_default', 'forced _default with oxide-hud installed')
Load({}, { Hud = 'oxide-hud' })
assert(Provider() == nil and olink.hud.GetResourceName() == 'none', 'forced oxide-hud while missing leaves the stubs')
assert(olink.hud.RegisterWidget({ id = 'x', label = 'x' }) == false and olink.hud.IsVisible() == true, 'stub defaults')
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
