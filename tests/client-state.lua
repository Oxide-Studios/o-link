-- Isolated tests for the client state namespaces (needs, money, seatbelt, voice) and the qb-core
-- death relay: provider precedence, normalization, change events and the no-provider defaults.
local rawprint = print
local output, states, netHandlers, handlers, bagHandlers, threads, emitted = {}, {}, {}, {}, {}, {}, {}
local playerData, esxData, exportsByResource = {}, {}, {}
local natives = {}

Config = { Debug = false, Overrides = {} }
IsDuplicityVersion = function() return false end
GetResourceState = function(name) return states[name] or 'missing' end
PlayerId = function() return 0 end
GetConvarInt = function(_, default) return default end
MumbleIsConnected = function() return natives.connected end
MumbleIsPlayerTalking = function() return natives.talking end
NetworkIsPlayerTalking = function() return natives.talking end
MumbleGetTalkerProximity = function() return natives.proximity end
print = function(...) output[#output + 1] = table.concat({ ... }, ' ') end

cache = { serverId = 7, vehicle = false }
LocalPlayer = { state = {} }

exports = setmetatable({}, {
    __call = function() end,
    __index = function(_, resource)
        local res = exportsByResource[resource]
        if not res then error(('No such export resource %s'):format(resource)) end
        return res
    end,
})

local function On(store, name, fn)
    store[name] = store[name] or {}
    table.insert(store[name], fn)
end
RegisterNetEvent = function(name, fn) if fn then On(netHandlers, name, fn) end end
AddEventHandler = function(name, fn) On(handlers, name, fn) end
AddStateBagChangeHandler = function(key, bagName, fn)
    assert(bagName == 'player:7', 'bag handlers are scoped to the local player')
    On(bagHandlers, key, fn)
end
TriggerEvent = function(name, ...)
    emitted[#emitted + 1] = { name = name, args = { ... } }
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
    for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end
end
CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
Wait = function(ms) coroutine.yield(ms) end

local function Net(name, ...) for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end end
local function Local(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end
local function SetBag(key, value)
    for _, fn in ipairs(bagHandlers[key] or {}) do fn('player:7', key, value) end
    LocalPlayer.state[key] = value
end
local function Tick()
    for _, thread in ipairs(threads) do
        if coroutine.status(thread) ~= 'dead' then assert(coroutine.resume(thread)) end
    end
end
local function Emitted(name)
    local out = {}
    for _, e in ipairs(emitted) do if e.name == name then out[#out + 1] = e.args end end
    return out
end

exportsByResource['qb-core'] = {
    GetCoreObject = function()
        return { Functions = { GetPlayerData = function() return playerData end } }
    end,
}
exportsByResource.qbx_core = { GetPlayerData = function() return playerData end }
exportsByResource.es_extended = {
    getSharedObject = function()
        return { GetPlayerData = function() return esxData end }
    end,
}

---@param scenario table<string, string> resource states
---@param files string[] adapter files, in the manifest's sorted glob order
local function Load(scenario, files)
    states, netHandlers, handlers, bagHandlers, threads, emitted, output = scenario, {}, {}, {}, {}, {}, {}
    LocalPlayer.state, playerData, esxData = {}, {}, {}
    cache.vehicle = false
    dofile('core/shared.lua')
    dofile('core/defaults_client.lua')
    for _, file in ipairs(files) do dofile(file) end
end

local function Needs(...)
    local files = {}
    for _, impl in ipairs({ '_default', 'es_extended', 'oxide-needs', 'qb-core', 'qbx_core' }) do
        files[#files + 1] = ('modules/needs/%s/client.lua'):format(impl)
    end
    Load(..., files)
end

local function Money(...)
    local files = {}
    for _, impl in ipairs({ '_default', 'es_extended', 'oxide-accounts', 'qb-core', 'qbx_core' }) do
        files[#files + 1] = ('modules/money/%s/client.lua'):format(impl)
    end
    Load(..., files)
end

local function Seatbelt(...)
    local files = {}
    for _, impl in ipairs({ '_default', 'oxide-vehicles', 'qb-smallresources', 'qbx_seatbelt' }) do
        files[#files + 1] = ('modules/seatbelt/%s/client.lua'):format(impl)
    end
    Load(..., files)
end

local function Voice(...)
    local files = {}
    for _, impl in ipairs({ '_default', 'pma-voice', 'saltychat' }) do
        files[#files + 1] = ('modules/voice/%s/client.lua'):format(impl)
    end
    Load(..., files)
end

-- needs: no provider ---------------------------------------------------------------------------
Needs({})
assert(olink.needs.GetResourceName() == '_default', 'clean server falls back to _default')
assert(olink.needs.Get('hunger') == nil and next(olink.needs.GetAll()) == nil, '_default knows no needs')
assert(#output == 0, '_default never warns')

-- needs: qb-core ----------------------------------------------------------------------------------
Needs({ ['qb-core'] = 'started' })
assert(olink.needs.GetResourceName() == 'qb-core', 'qb-core owns needs')
playerData = { metadata = { hunger = 64, thirst = 32, stress = 5 } }
local all = olink.needs.GetAll()
assert(all.hunger == 64 and all.thirst == 32 and all.stress == 5, 'GetAll reads PlayerData.metadata')
assert(olink.needs.Get('thirst') == 32 and olink.needs.Get('isdead') == nil, 'Get only answers needs')
Net('hud:client:UpdateNeeds', 50, 40)
local changes = Emitted('olink:client:needsChanged')
assert(#changes == 1 and changes[1][1].hunger == 50 and changes[1][1].thirst == 40, 'UpdateNeeds relays hunger and thirst')
Net('hud:client:UpdateStress', 12)
changes = Emitted('olink:client:needsChanged')
assert(#changes == 2 and changes[2][1].stress == 12 and changes[2][1].hunger == 50, 'UpdateStress keeps the other needs')
Net('QBCore:Player:UpdatePlayerDataField', 'metadata', { hunger = 50, thirst = 40, stress = 12 })
assert(#Emitted('olink:client:needsChanged') == 2, 'an unchanged metadata push is not re-emitted')
Net('QBCore:Player:UpdatePlayerDataField', 'metadata', { hunger = 49, thirst = 40, stress = 12 })
assert(#Emitted('olink:client:needsChanged') == 3, 'a metadata field push relays a change')
Net('QBCore:Player:UpdatePlayerDataField', 'money', { cash = 1 })
Net('QBCore:Player:SetPlayerData', { metadata = { hunger = 10, thirst = 40, stress = 12 } })
changes = Emitted('olink:client:needsChanged')
assert(#changes == 4 and changes[4][1].hunger == 10, 'older cores relay through SetPlayerData')

Needs({ ['qb-core'] = 'started', qbx_core = 'started' })
assert(olink.needs.GetResourceName() == 'qbx_core', 'qb-core steps aside for qbx_core')
Needs({ ['qb-core'] = 'started', ['oxide-core'] = 'started', ['oxide-needs'] = 'started' })
assert(olink.needs.GetResourceName() == 'oxide-needs', 'qb-core steps aside for oxide-needs')
Config.Overrides = { Needs = 'qb-core' }
Needs({ ['qb-core'] = 'started', ['oxide-core'] = 'started', ['oxide-needs'] = 'started' })
assert(olink.needs.GetResourceName() == 'qb-core', 'an override keeps qb-core')
Config.Overrides = {}

-- needs: qbx_core state bags --------------------------------------------------------------------
Needs({ qbx_core = 'started' })
assert(olink.needs.GetResourceName() == 'qbx_core', 'qbx_core owns needs')
LocalPlayer.state.hunger, LocalPlayer.state.thirst, LocalPlayer.state.stress = 80, 70, 0
assert(olink.needs.Get('hunger') == 80 and olink.needs.GetAll().thirst == 70, 'reads the player bags')
assert(olink.needs.Get('isLoggedIn') == nil, 'Get never reads unrelated bags')
SetBag('thirst', 65)
changes = Emitted('olink:client:needsChanged')
assert(#changes == 1 and changes[1][1].thirst == 65 and changes[1][1].hunger == 80, 'a bag change relays the new value before it lands')
SetBag('thirst', 65)
assert(#Emitted('olink:client:needsChanged') == 1, 'an unchanged bag is not re-emitted')

-- needs: es_extended (esx_status) ---------------------------------------------------------------
Needs({ es_extended = 'started' })
assert(olink.needs.GetResourceName() == 'es_extended', 'es_extended owns needs')
assert(olink.needs.Get('hunger') == nil, 'nothing is known before the first esx_status tick')
Local('esx_status:onTick', {
    { name = 'hunger', val = 500000, percent = 50 },
    { name = 'thirst', val = 254000 },
    { name = 'drunk', val = 1000000, percent = 100 },
})
all = olink.needs.GetAll()
assert(all.hunger == 50 and all.thirst == 25 and all.stress == nil, 'normalized to 0-100, stress untracked')
changes = Emitted('olink:client:needsChanged')
assert(#changes == 1 and changes[1][1].hunger == 50, 'the first tick relays')
Local('esx_status:onTick', { { name = 'hunger', val = 500000, percent = 50 }, { name = 'thirst', val = 254000 } })
assert(#Emitted('olink:client:needsChanged') == 1, 'an unchanged tick is not re-emitted')
TriggerEvent('olink:client:playerUnload')
assert(olink.needs.Get('hunger') == nil, 'unload forgets the last character')
Needs({ es_extended = 'started', ['oxide-core'] = 'started', ['oxide-needs'] = 'started' })
assert(olink.needs.GetResourceName() == 'oxide-needs', 'es_extended steps aside for oxide-needs')

-- needs: oxide-needs ----------------------------------------------------------------------------
Needs({ ['oxide-core'] = 'started' })
assert(olink.needs.GetResourceName() == '_default', 'oxide-core without oxide-needs has no needs')
Needs({ ['oxide-core'] = 'started', ['oxide-needs'] = 'stopped' })
assert(olink.needs.GetResourceName() == 'oxide-needs', 'oxide-needs owns needs although it starts after o-link')
assert(olink.needs.Get('hunger') == nil, 'no metadata bag yet')
SetBag('oxide:metadata', { hunger = 90, thirst = 85, stress = 3, dead = false })
assert(olink.needs.Get('stress') == 3 and olink.needs.GetAll().thirst == 85, 'reads the oxide:metadata bag')
changes = Emitted('olink:client:needsChanged')
assert(#changes == 1 and changes[1][1].hunger == 90, 'a metadata bag change relays')
SetBag('oxide:metadata', { hunger = 90, thirst = 85, stress = 3, dead = true })
assert(#Emitted('olink:client:needsChanged') == 1, 'a non-needs metadata change is not a needs change')
SetBag('oxide:metadata', nil)
assert(olink.needs.Get('hunger') == nil, 'a cleared bag reads empty')

-- money ---------------------------------------------------------------------------------------
Money({})
assert(olink.money.GetResourceName() == '_default' and olink.money.GetBalance('cash') == 0, '_default reads 0')
assert(#output == 0, '_default never warns')

Money({ ['qb-core'] = 'started' })
playerData = { money = { cash = 120, bank = 5000, crypto = 0 } }
assert(olink.money.GetBalance('cash') == 120 and olink.money.GetBalance('money') == 120, 'qb cash, money alias')
assert(olink.money.GetBalance('bank') == 5000 and olink.money.GetBalance('gold') == 0, 'qb bank, unknown account')
Net('QBCore:Player:UpdatePlayerDataField', 'money', { cash = 100, bank = 5000, crypto = 0 })
local moved = Emitted('olink:client:moneyChanged')
assert(#moved == 3, 'the first push reports every account')
Net('QBCore:Player:UpdatePlayerDataField', 'money', { cash = 90, bank = 5000, crypto = 0 })
moved = Emitted('olink:client:moneyChanged')
assert(#moved == 4 and moved[4][1] == 'cash' and moved[4][2] == 90, 'only the account that moved is reported')
Net('QBCore:Player:SetPlayerData', { money = { cash = 90, bank = 4000, crypto = 0 } })
moved = Emitted('olink:client:moneyChanged')
assert(#moved == 5 and moved[5][1] == 'bank' and moved[5][2] == 4000, 'older cores relay through SetPlayerData')
Money({ ['qb-core'] = 'started', qbx_core = 'started' })
assert(olink.money.GetResourceName() == 'qbx_core', 'qb-core steps aside for qbx_core')

Money({ qbx_core = 'started' })
assert(olink.money.GetBalance('cash') == 0, 'qbx PlayerData is empty before a character loads')
playerData = { money = { cash = 15, bank = 30 } }
assert(olink.money.GetBalance('bank') == 30, 'qbx bank')
Net('QBCore:Player:SetPlayerData', { money = { cash = 15, bank = 30 } })
Net('QBCore:Player:SetPlayerData', { money = { cash = 15, bank = 31 } })
moved = Emitted('olink:client:moneyChanged')
assert(#moved == 3 and moved[3][1] == 'bank' and moved[3][2] == 31, 'qbx relays changed accounts')

Money({ es_extended = 'started' })
esxData = { accounts = { { name = 'bank', money = 900 }, { name = 'money', money = 45 }, { name = 'black_money', money = 7 } } }
assert(olink.money.GetBalance('cash') == 45 and olink.money.GetBalance('bank') == 900, 'ESX cash is the money account')
Net('esx:setAccountMoney', { name = 'money', money = 40, label = 'Cash' })
moved = Emitted('olink:client:moneyChanged')
assert(#moved == 1 and moved[1][1] == 'cash' and moved[1][2] == 40, 'ESX money account is reported as cash')
Net('esx:playerLoaded', { accounts = { { name = 'money', money = 40 }, { name = 'bank', money = 950 } } })
moved = Emitted('olink:client:moneyChanged')
assert(#moved == 2 and moved[2][1] == 'bank', 'playerLoaded reports the accounts that differ')

Money({ ['oxide-core'] = 'started', ['oxide-accounts'] = 'started' })
assert(olink.money.GetResourceName() == 'oxide-accounts', 'oxide-accounts owns money')
SetBag('oxide:cash', 250)
SetBag('oxide:bank', 10000)
assert(olink.money.GetBalance('cash') == 250 and olink.money.GetBalance('money') == 250, 'oxide cash bag')
assert(olink.money.GetBalance('bank') == 10000 and olink.money.GetBalance(nil) == 0, 'oxide bank bag')
moved = Emitted('olink:client:moneyChanged')
assert(#moved == 2 and moved[1][1] == 'cash' and moved[2][1] == 'bank', 'oxide bag changes are reported')
SetBag('oxide:cash', 250)
assert(#Emitted('olink:client:moneyChanged') == 2, 'an unchanged bag is not re-emitted')
Money({ ['oxide-core'] = 'started' })
assert(olink.money.GetResourceName() ~= 'oxide-accounts', 'no oxide-accounts, no oxide adapter')

-- seatbelt ------------------------------------------------------------------------------------
Seatbelt({})
assert(olink.seatbelt.GetResourceName() == '_default' and olink.seatbelt.IsOn() == false, '_default belt is off')
assert(#output == 0, '_default never warns')

local belted = false
exportsByResource['oxide-vehicles'] = { IsSeatbeltOn = function() return belted end }
Seatbelt({ ['oxide-vehicles'] = 'stopped', ['qb-smallresources'] = 'started' })
assert(olink.seatbelt.GetResourceName() == 'oxide-vehicles', 'an installed oxide-vehicles owns the seatbelt')
assert(olink.seatbelt.IsOn() == false, 'a stopped oxide-vehicles answers false')
states['oxide-vehicles'] = 'started'
belted = true
assert(olink.seatbelt.IsOn() == true, 'oxide-vehicles reports the belt once started')
Tick()
assert(#Emitted('olink:client:seatbeltChanged') == 0, 'no poll on foot')
cache.vehicle = 42
Tick()
local belts = Emitted('olink:client:seatbeltChanged')
assert(#belts == 1 and belts[1][1] == true, 'the poll reports buckling up')
cache.vehicle, belted = false, false
Tick()
belts = Emitted('olink:client:seatbeltChanged')
assert(#belts == 2 and belts[2][1] == false, 'the poll reports the belt coming off after exit')

Config.Overrides = { Seatbelt = 'qb-smallresources' }
local smallBelt = false
exportsByResource['qb-smallresources'] = { HasSeatbeltOn = function() return smallBelt end }
Seatbelt({ ['oxide-vehicles'] = 'stopped', ['qb-smallresources'] = 'started' })
Config.Overrides = {}
assert(olink.seatbelt.GetResourceName() == 'qb-smallresources', 'an override picks qb-smallresources')
assert(#threads == 0, 'the overridden oxide-vehicles adapter never polls')
smallBelt = true
assert(olink.seatbelt.IsOn() == true, 'qb-smallresources export')
Local('seatbelt:client:ToggleSeatbelt', true)
Local('seatbelt:client:ToggleSeatbelt', true)
Local('seatbelt:client:ToggleSeatbelt', false)
belts = Emitted('olink:client:seatbeltChanged')
assert(#belts == 2 and belts[1][1] == true and belts[2][1] == false, 'qb-smallresources toggles relay once each')

Seatbelt({ qbx_seatbelt = 'started', ['qb-smallresources'] = 'stopped' })
assert(olink.seatbelt.GetResourceName() == 'qbx_seatbelt', 'qbx_seatbelt owns the seatbelt')
Local('seatbelt:client:ToggleSeatbelt')
assert(#Emitted('olink:client:seatbeltChanged') == 0, 'the stepped-aside qb-smallresources relay stays silent')
SetBag('seatbelt', true)
assert(olink.seatbelt.IsOn() == true, 'qbx reads the seatbelt bag')
SetBag('seatbelt', false)
SetBag('seatbelt', false)
belts = Emitted('olink:client:seatbeltChanged')
assert(#belts == 2 and belts[1][1] == true and belts[2][1] == false, 'qbx bag changes relay once each')

-- voice ---------------------------------------------------------------------------------------
natives = { connected = 1, talking = false, proximity = 12.5 }
Voice({})
assert(olink.voice.GetResourceName() == '_default', 'native voice by default')
local voice = olink.voice.GetState()
assert(voice.connected == true and voice.talking == false, 'native state normalizes BOOL natives')
assert(voice.range.index == 1 and voice.range.distance == 12.5 and voice.radio.active == false, 'native range, no radio')
natives.talking = 1
assert(olink.voice.GetState().talking == true, 'native talking')
assert(#output == 0, '_default never warns')

Voice({ ['pma-voice'] = 'stopped' })
assert(olink.voice.GetResourceName() == 'pma-voice', 'an installed pma-voice owns voice before it starts')
voice = olink.voice.GetState()
assert(voice.connected == false and voice.talking == false and voice.range.index == 2, 'not started yet: defaults')
states['pma-voice'] = 'started'
LocalPlayer.state.proximity = { index = 3, distance = 15.0, mode = 'Shouting' }
LocalPlayer.state.radioChannel = 0
voice = olink.voice.GetState()
assert(voice.connected == true and voice.talking == true, 'pma-voice started later is picked up')
assert(voice.range.index == 3 and voice.range.label == 'Shouting' and voice.range.distance == 15.0, 'pma range from the proximity bag')
assert(voice.radio.channel == nil and voice.radio.active == false, 'channel 0 means no radio')
LocalPlayer.state.radioChannel, LocalPlayer.state.radioActive = 4, true
voice = olink.voice.GetState()
assert(voice.radio.channel == 4 and voice.radio.active == true, 'pma radio channel and transmit')

local salty = { range = 3.5, channel = '' }
exportsByResource.saltychat = {
    GetVoiceRange = function() return salty.range end,
    GetRadioChannel = function(_, primary) assert(primary == true) return salty.channel end,
}
Voice({ saltychat = 'started' })
assert(olink.voice.GetResourceName() == 'saltychat', 'saltychat owns voice')
voice = olink.voice.GetState()
assert(voice.connected == true and voice.range.distance == 3.5 and voice.radio.channel == nil, 'saltychat before its events')
Local('SaltyChat_PluginStateChanged', 3)
assert(olink.voice.GetState().connected == false, 'the swiss channel is not connected')
Local('SaltyChat_PluginStateChanged', 2)
Local('SaltyChat_TalkStateChanged', true)
Local('SaltyChat_VoiceRangeChanged', 8.0, 1, 4)
Local('SaltyChat_RadioTrafficStateChanged', false, true, false, false)
salty.range, salty.channel = 8.0, 'lspd'
voice = olink.voice.GetState()
assert(voice.connected == true and voice.talking == true, 'saltychat talk state')
assert(voice.range.index == 2 and voice.range.count == 4 and voice.range.distance == 8.0, 'saltychat 0-based index becomes 1-based')
assert(voice.radio.active == true and voice.radio.channel == 'lspd', 'saltychat radio')
Local('onClientResourceStop', 'saltychat')
states.saltychat = 'stopped'
voice = olink.voice.GetState()
assert(voice.connected == false and voice.talking == false and voice.radio.active == false, 'a stopped saltychat reads idle')

Config.Overrides = { Voice = 'pma-voice' }
Voice({ ['pma-voice'] = 'started', saltychat = 'started' })
Config.Overrides = {}
assert(olink.voice.GetResourceName() == 'pma-voice', 'an override picks pma-voice over saltychat')

-- qb-core death relay -------------------------------------------------------------------------
Load({ ['qb-core'] = 'started' }, { 'modules/death/qb-core/client.lua' })
Net('QBCore:Player:UpdatePlayerDataField', 'metadata', { inlaststand = true, isdead = false })
Net('QBCore:Player:UpdatePlayerDataField', 'metadata', { inlaststand = false, isdead = true })
Net('QBCore:Player:SetPlayerData', { metadata = { inlaststand = false, isdead = false } })
local deaths = Emitted('olink:client:playerDeathStateChanged')
assert(#deaths == 3 and deaths[1][1] == 'downed' and deaths[2][1] == 'dead' and deaths[3][1] == 'alive', 'field pushes and full pushes both relay')

print = rawprint
print('Client state passed: needs, money, seatbelt, voice providers and the qb-core death relay.')
