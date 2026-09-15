-- Isolated tests for the updater's write order: new files first, existing
-- files next, fxmanifest.lua last, and a clean abort when a folder is missing.
local rawprint = print
local remote, disk, folders, deny, writes, output, thread = {}, {}, {}, {}, {}, {}, nil

Config = { CheckForUpdates = true, AutoDownloadUpdates = true }
GetCurrentResourceName = function() return 'o-link' end
GetResourceMetadata = function() return '1.7.2' end
CreateThread = function(fn) thread = fn end
promise = { new = function() return { resolve = function(self, value) self.value = value end } end }
Citizen = { Await = function(p) return p.value end }
json = { decode = function(body) if type(body) == 'table' then return body end error('Invalid JSON') end }
print = function(...) output[#output + 1] = table.concat({ ... }, ' ') end
PerformHttpRequest = function(url, cb)
    if url:find('api.github.com', 1, true) then
        local tree = {}
        for path in pairs(remote) do tree[#tree + 1] = { type = 'blob', path = path } end
        return cb(200, { tree = tree })
    end
    local path = url:match('/main/(.+)$')
    if path and remote[path] then return cb(200, remote[path]) end
    cb(404, nil)
end
LoadResourceFile = function(_, path) return disk[path] end
SaveResourceFile = function(_, path, content)
    local folder = path:match('^(.+)/[^/]+$') or '.'
    if not folders[folder] or deny[path] then return false end
    writes[#writes + 1] = path
    disk[path] = content
    return true
end

local function Run(scenario)
    remote = {
        ['fxmanifest.lua'] = "fx_version 'cerulean'\nversion '1.8.0'\n",
        ['config.lua'] = 'new config',
        ['core/shared.lua'] = 'new shared',
        ['core/extra.lua'] = 'new file in an existing folder',
        ['modules/map/server.lua'] = 'new file in a new folder',
    }
    disk = { ['fxmanifest.lua'] = "version '1.7.2'", ['config.lua'] = 'my config', ['core/shared.lua'] = 'old shared' }
    folders, deny, writes, output, thread = scenario.folders, scenario.deny or {}, {}, {}, nil
    dofile('core/version_check.lua')
    thread()
end

local function Printed(needle)
    for _, line in ipairs(output) do
        if line:find(needle, 1, true) then return true end
    end
    return false
end

-- A new folder the updater cannot create: nothing in use changes.
Run({ folders = { ['.'] = true, core = true } })
assert(#writes == 1 and writes[1] == 'core/extra.lua', 'only the new file in an existing folder is written')
assert(disk['core/shared.lua'] == 'old shared' and disk['fxmanifest.lua'] == "version '1.7.2'", 'existing files untouched')
assert(Printed('installed manually') and Printed('modules/map/server.lua'), 'manual-install message names the file')

-- Every folder exists: new files, then existing files, manifest last; config.lua never written.
Run({ folders = { ['.'] = true, core = true, ['modules/map'] = true } })
assert(table.concat(writes, ',') == 'core/extra.lua,modules/map/server.lua,core/shared.lua,fxmanifest.lua', table.concat(writes, ','))
assert(disk['config.lua'] == 'my config', 'config.lua is protected')
assert(Printed('4 files written'), 'success summary')

-- An existing file fails: the manifest is not advanced so the update retries next start.
Run({ folders = { ['.'] = true, core = true, ['modules/map'] = true }, deny = { ['core/shared.lua'] = true } })
assert(disk['fxmanifest.lua'] == "version '1.7.2'", 'manifest untouched after a failed existing write')
assert(Printed('retried on the next start'), 'retry message')

print = rawprint
print('Updater passed: new files first, manifest last, clean abort on a missing folder, protected config.')
