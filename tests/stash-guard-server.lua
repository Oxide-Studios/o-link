-- The ox_inventory stash guard (modules/inventory/ox_inventory/server.lua): a guarded stash opens
-- through OpenStash only, once per open; a client asking ox_inventory for it by id is refused; other
-- stashes are untouched.
-- Run from the [oxide] folder: bash oxide-phone/tests/lua.sh o-link tests/stash-guard-server.lua
local passed, failed = 0, 0
local function check(name, ok)
    if ok then passed = passed + 1 else failed = failed + 1; print('FAIL ' .. name) end
end

local now = 0
GetGameTimer = function() return now end
GetResourceState = function(name) return name == 'ox_inventory' and 'started' or 'missing' end

local hooks, opened = {}, {}
local ox = {}
-- ox_inventory runs its openInventory hooks for every open, forced or asked for by a client.
local function open(src, id, forced)
    for _, h in ipairs(hooks) do
        if h.typeFilter and not h.typeFilter.stash then goto skip end
        if h.cb({ source = src, inventoryId = id, inventoryType = 'stash' }) == false then return false end
        ::skip::
    end
    opened[#opened + 1] = { src = src, id = id, forced = forced }
    return true
end
function ox:registerHook(event, cb, options)
    hooks[#hooks + 1] = { event = event, cb = cb, typeFilter = options and options.typeFilter }
end
function ox:RegisterStash() end
function ox:forceOpenInventory(src, kind, id) return open(src, id, true) end
exports = { ox_inventory = ox }

local registered
olink = {
    _guardImpl = function() return true end,
    _hasOverride = function() return false end,
    _register = function(namespace, impl) if namespace == 'inventory' then registered = impl end end,
}
dofile('modules/inventory/ox_inventory/server.lua')
local inv = registered
check('the adapter registered', inv ~= nil)

inv.RegisterStash('oxc_b_1_abcdefgh', 'Crate', 10, 1000)
inv.RegisterStash('other_stash', 'Other', 10, 1000)
check('GuardStash is supported on ox_inventory', inv.GuardStash('oxc_b_1_abcdefgh') == true)

check('the server opens a guarded stash', inv.OpenStash(1, 'oxc_b_1_abcdefgh') == nil and opened[#opened].id == 'oxc_b_1_abcdefgh')
check('a client asking for it by id afterwards is refused', open(1, 'oxc_b_1_abcdefgh', false) == false)
check('so is another player who saw the id', open(2, 'oxc_b_1_abcdefgh', false) == false)
check('a stash that is not guarded still opens for a client', open(1, 'other_stash', false) == true)
now = 10000
inv.OpenStash(3, 'oxc_b_1_abcdefgh')
check('each server open is allowed', opened[#opened].src == 3)

print(('[stash-guard] %d passed, %d failed'):format(passed, failed))
if failed > 0 then error('stash-guard failed') end
