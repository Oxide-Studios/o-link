-- Isolated tests for the updater's write order (new files first, existing files
-- next, fxmanifest.lua last), a clean abort when a folder is missing, and the
-- version notice every abort must fall back to.
local rawprint = print
local remote, disk, folders, deny, writes, output, thread = {}, {}, {}, {}, {}, {}, nil
local denyTree = false

Config = { CheckForUpdates = true, AutoDownloadUpdates = true }
olink = {}
GetCurrentResourceName = function() return 'o-link' end
GetResourceMetadata = function() return '1.7.2' end
CreateThread = function(fn) thread = fn end
promise = { new = function() return { resolve = function(self, value) self.value = value end } end }
Citizen = { Await = function(p) return p.value end }
json = { decode = function(body) if type(body) == 'table' then return body end error('Invalid JSON') end }
print = function(...) output[#output + 1] = table.concat({ ... }, ' ') end
PerformHttpRequest = function(url, cb)
    if url:find('api.github.com', 1, true) then
        if denyTree then return cb(500, nil) end
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
    denyTree = scenario.denyTree or false
    dofile('core/update_lib.lua')
    dofile('core/version_check.lua')
    thread()
end

local function Printed(needle)
    for _, line in ipairs(output) do
        if line:find(needle, 1, true) then return true end
    end
    return false
end

local function PrintedNotice()
    return Printed('An update is available') and Printed('1.7.2') and Printed('1.8.0')
        and Printed('https://github.com/Oxide-Studios/o-link')
end

-- A new folder the updater cannot create: nothing in use changes.
Run({ folders = { ['.'] = true, core = true } })
assert(#writes == 1 and writes[1] == 'core/extra.lua', 'only the new file in an existing folder is written')
assert(disk['core/shared.lua'] == 'old shared' and disk['fxmanifest.lua'] == "version '1.7.2'", 'existing files untouched')
assert(Printed('installed manually') and Printed('modules/map/server.lua'), 'manual-install message names the file')
assert(PrintedNotice(), 'a failed write still tells the owner which version to get, and where')

-- Every folder exists: new files, then existing files, manifest last; config.lua never written.
Run({ folders = { ['.'] = true, core = true, ['modules/map'] = true } })
assert(table.concat(writes, ',') == 'core/extra.lua,modules/map/server.lua,core/shared.lua,fxmanifest.lua', table.concat(writes, ','))
assert(disk['config.lua'] == 'my config', 'config.lua is protected')
assert(Printed('4 files written'), 'success summary')
assert(not Printed('An update is available'), 'a completed download does not also nag to download')

-- An existing file fails: the manifest is not advanced so the update retries next start.
Run({ folders = { ['.'] = true, core = true, ['modules/map'] = true }, deny = { ['core/shared.lua'] = true } })
assert(disk['fxmanifest.lua'] == "version '1.7.2'", 'manifest untouched after a failed existing write')
assert(Printed('retried on the next start'), 'retry message')
assert(PrintedNotice(), 'a partial write still tells the owner which version to get, and where')

-- The file list cannot be fetched at all: nothing is written, and the owner is
-- still told an update exists. This is the path a repository transfer would hit
-- if the HTTP client did not follow redirects.
Run({ folders = { ['.'] = true, core = true, ['modules/map'] = true }, denyTree = true })
assert(#writes == 0, 'nothing is written when the file list cannot be read')
assert(Printed('could not list repository files'), 'names the failure')
assert(PrintedNotice(), 'a failed listing still tells the owner which version to get, and where')

print = rawprint
print('Updater passed: new files first, manifest last, clean abort on a missing folder, protected config, every abort falls back to the download notice.')
