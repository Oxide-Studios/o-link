-- Isolated tests for the phone namespace: the sender-address slug, the `_default`
-- fallback with no phone installed, the client email relay's validation, and
-- qb-phone stepping aside for an installed oxide-phone.
local rawprint = print
local output, states, handlers, events, clock, isServer = {}, {}, {}, {}, 0, true

Config = { Debug = false, Overrides = {} }
IsDuplicityVersion = function() return isServer end
GetResourceState = function(name) return states[name] or 'missing' end
GetGameTimer = function() return clock end
GetPlayers = function() return {} end
exports = setmetatable({}, { __call = function() end })
RegisterNetEvent = function(name, fn) handlers[name] = fn end
AddEventHandler = function(name, fn) events[name] = fn end
print = function(...) output[#output + 1] = table.concat({ ... }, ' ') end

local function Load(side, scenario)
    isServer = side == 'server'
    states, handlers, events, output = scenario or {}, {}, {}, {}
    dofile('core/shared.lua')
    dofile(('core/defaults_%s.lua'):format(side))
    if isServer then dofile('modules/phone/_util/server.lua') end
    dofile(('modules/phone/_default/%s.lua'):format(side))
end

local function Warned(fn)
    for _, line in ipairs(output) do
        if line:find('olink.phone.' .. fn .. '()', 1, true) then return true end
    end
    return false
end

-- Sender address slug.
Load('server')
local slug = olink._phone.SenderAddress
assert(slug('Pizza This - Vespucci') == 'pizza-this-vespucci@service.com', slug('Pizza This - Vespucci'))
assert(slug('LSPD  Records & Fines!') == 'lspd-records-fines@service.com', slug('LSPD  Records & Fines!'))
assert(slug('Police@LSPD.gov') == 'police@lspd.gov', 'a real address passes through lowercased')
assert(slug('') == 'noreply@service.com' and slug(nil) == 'noreply@service.com', 'empty sender')
assert(slug('!!! ???') == 'noreply@service.com', 'sender with no usable characters')
local long = slug(('Very Long Company Name '):rep(6))
assert(#long:match('^(.-)@') <= 48 and not long:find('%-@'), 'length cap without a trailing dash: ' .. long)
for _, name in ipairs({ 'Pizza This - Vespucci', 'a b', ' x ', 'Los Santos Customs\t', 'ümlaut Café' }) do
    assert(not slug(name):find('%s'), 'no whitespace in ' .. slug(name))
end

-- `_default` with no phone installed: every call returns its default, nothing errors.
Load('server')
assert(olink.phone.IsAvailable() == false, 'IsAvailable is false with no phone')
assert(not Warned('IsAvailable'), 'IsAvailable is a capability check and never warns')
assert(olink.phone.GetResourceName() == '_default' and olink.phone.GetPhoneName() == '_default', 'names')
assert(olink.phone.GetPlayerPhone(1) == false, 'GetPlayerPhone')
assert(olink.phone.GetSourceByNumber('555-123-4567') == nil, 'GetSourceByNumber')
local numbers = olink.phone.GetNumbersByIdentifier('ABC123')
assert(type(numbers) == 'table' and next(numbers) == nil, 'GetNumbersByIdentifier returns an empty table')
assert(olink.phone.SendEmail(1, 'LSPD', 'Fine', 'Body') == false, 'SendEmail')
assert(olink.phone.SendEmailOffline('ABC123', 'LSPD', 'Fine', 'Body') == false, 'SendEmailOffline')
assert(olink.phone.SendMessage(1, 'Pizza This', 'Hi') == false, 'SendMessage')
assert(olink.phone.SendNotification(1, { title = 'T', message = 'M' }) == false, 'SendNotification')
for _, fn in ipairs({ 'Open', 'Close', 'Send', 'SetWidgetData', 'Notify', 'DismissNotification', 'ClearNotifications' }) do
    assert(olink.phone[fn](1, 'app', {}) == false, 'server ' .. fn)
end
assert(Warned('SendEmail'), 'a real call on the fallback warns once')

Load('client')
assert(olink.phone.IsAvailable() == false and olink.phone.IsOpen() == false, 'client capability checks')
assert(not Warned('IsAvailable') and not Warned('IsOpen'), 'client capability checks never warn')
assert(olink.phone.SendEmail('LSPD', 'Fine', 'Body') == false, 'client SendEmail')
assert(olink.phone.GetCurrentApp() == nil, 'client GetCurrentApp')
for _, fn in ipairs({ 'RegisterApp', 'UnregisterApp', 'Open', 'Close', 'CloseApp', 'Send', 'SetBadge',
    'RegisterWidget', 'UnregisterWidget', 'SetWidgetData', 'Notify', 'DismissNotification', 'ClearNotifications' }) do
    assert(olink.phone[fn]({}) == false, 'client ' .. fn)
end

-- Client email relay: untrusted payloads are type-checked, capped and rate limited.
Load('server')
local sent = {}
olink.phone.SendEmail = function(src, sender, title, message)
    sent[#sent + 1] = { src = src, sender = sender, title = title, message = message }
    return true
end
olink._phone.RegisterEmailRelay('test-phone')
local relay = handlers['o-link:phone:test-phone:sendEmail']
assert(relay, 'relay registered under the provider name')
local function Relay(src, data) source = src; relay(data) end

Relay(1, 'not a table')
Relay(1, { email = 5, title = 'T', message = 'M' })
Relay(0, { email = 'E', title = 'T', message = 'M' })
assert(#sent == 0, 'bad payloads and console source are dropped')

Relay(1, { email = ('e'):rep(300), title = ('t'):rep(300), message = ('m'):rep(5000) })
assert(#sent == 1 and #sent[1].sender == 100 and #sent[1].title == 100 and #sent[1].message == 2000, 'length caps')
Relay(1, { email = 'E', title = 'T', message = 'M' })
assert(#sent == 1, 'second relay inside the cooldown is dropped')
Relay(2, { email = 'E', title = 'T', message = 'M' })
assert(#sent == 2, 'the cooldown is per source')
clock = 5000
Relay(1, { email = 'E', title = 'T', message = 'M' })
assert(#sent == 3, 'the cooldown expires')
source = 1
events.playerDropped()
Relay(1, { email = 'E', title = 'T', message = 'M' })
assert(#sent == 4, 'a dropped player starts clean')

-- qb-phone steps aside for an installed oxide-phone (it registers later in folder order).
Load('server', { ['qb-phone'] = 'started', ['oxide-phone'] = 'stopped' })
dofile('modules/phone/qb-phone/server.lua')
assert(olink.phone.GetResourceName() ~= 'qb-phone', 'qb-phone steps aside for an installed oxide-phone')

Load('server', { ['qb-phone'] = 'started' })
dofile('modules/phone/qb-phone/server.lua')
assert(olink.phone.GetResourceName() == 'qb-phone' and olink.phone.IsAvailable() == true, 'qb-phone owns the namespace')

Load('server', { ['qb-phone'] = 'started', ['qs-smartphone-pro'] = 'started' })
dofile('modules/phone/qb-phone/server.lua')
assert(olink.phone.GetResourceName() ~= 'qb-phone', 'qb-phone steps aside for qs-smartphone-pro')

-- oxide-phone (circular provider) registers while installed, gates every call on its state,
-- and steps aside for another phone that is already running.
Load('server', { ['oxide-phone'] = 'stopped', ['qb-phone'] = 'started' })
dofile('modules/phone/oxide-phone/server.lua')
dofile('modules/phone/qb-phone/server.lua')
assert(olink.phone.GetResourceName() == 'oxide-phone', 'installed oxide-phone owns the namespace over qb-phone')
assert(olink.phone.IsAvailable() == false and olink.phone.GetPlayerPhone(1) == false, 'stopped oxide-phone answers defaults')
assert(olink.phone.SendEmail(1, 'A', 'B', 'C') == false and olink.phone.Notify(1, { app = 'x', message = 'y' }) == false, 'stopped: no delivery')
local none = olink.phone.GetNumbersByIdentifier('ABC')
assert(type(none) == 'table' and next(none) == nil, 'stopped: empty numbers')
assert(handlers['o-link:phone:oxide-phone:sendEmail'], 'oxide-phone registers its validated relay')

Load('server', { ['oxide-phone'] = 'stopped', ['lb-phone'] = 'started' })
dofile('modules/phone/lb-phone/server.lua')
dofile('modules/phone/oxide-phone/server.lua')
assert(olink.phone.GetResourceName() == 'lb-phone', 'a running lb-phone keeps the namespace over an installed oxide-phone')

Config.Overrides = { Phone = 'oxide-phone' }
Load('server', { ['oxide-phone'] = 'stopped', ['lb-phone'] = 'started' })
dofile('modules/phone/lb-phone/server.lua')
dofile('modules/phone/oxide-phone/server.lua')
assert(olink.phone.GetResourceName() == 'oxide-phone', 'an override picks oxide-phone')
Config.Overrides = {}

Load('server', { ['oxide-phone'] = 'missing' })
dofile('modules/phone/oxide-phone/server.lua')
assert(olink.phone.GetResourceName() == '_default', 'a missing oxide-phone leaves _default in place')

Config.Overrides = { Phone = 'qb-phone' }
Load('server', { ['qb-phone'] = 'started', ['oxide-phone'] = 'stopped' })
dofile('modules/phone/qb-phone/server.lua')
assert(olink.phone.GetResourceName() == 'qb-phone', 'an explicit override keeps qb-phone')
Config.Overrides = {}

print = rawprint
print('Phone passed: slug addresses, no-phone defaults, relay validation, qb-phone precedence.')
