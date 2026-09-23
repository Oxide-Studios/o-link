-- Isolated tests for the catalogue update notice: which resources are reported,
-- which are skipped, and silence on every failure path.
local rawprint = print
local installed, states, published, httpCode, output, thread = {}, {}, {}, 200, {}, nil

Config = { CheckForUpdates = true, Debug = false }
olink = {}

GetCurrentResourceName = function() return 'o-link' end
AddEventHandler = function() end
CreateThread = function(fn) thread = fn end
Wait = function() end

-- The settle loop spins on os.time; hold it still so one Wait is enough to leave.
local clock = 0
os = { time = function() clock = clock + 60 return clock end }

local names = {}
GetNumResources = function() return #names end
GetResourceByFindIndex = function(i) return names[i + 1] end
GetResourceState = function(name) return states[name] or 'missing' end
GetResourceMetadata = function(name) return installed[name] end

promise = { new = function() return { resolve = function(self, value) self.value = value end } end }
Citizen = { Await = function(p) return p.value end }
json = { decode = function(body) if type(body) == 'table' then return body end error('Invalid JSON') end }
print = function(...) output[#output + 1] = table.concat({ ... }, ' ') end
PerformHttpRequest = function(_, cb) cb(httpCode, published) end

local function Run(scenario)
    installed = scenario.installed
    states = {}
    names = {}
    for name in pairs(installed) do
        names[#names + 1] = name
        states[name] = scenario.stopped and scenario.stopped[name] and 'stopped' or 'started'
    end
    table.sort(names)

    published = scenario.published
    httpCode = scenario.code or 200
    output, thread, clock = {}, nil, 0

    dofile('core/update_lib.lua')
    dofile('core/catalogue_check.lua')
    thread()
end

local function Printed(needle)
    for _, line in ipairs(output) do
        if line:find(needle, 1, true) then return true end
    end
    return false
end

local function Lines()
    return table.concat(output, '\n')
end

-- Outdated resources are listed; current, ahead, stopped and uninstalled are not.
Run({
    installed = {
        ['oxide-police'] = '1.8.0',     -- outdated
        ['oxide-banking'] = '2.0.1',    -- outdated
        ['oxide-weed'] = '1.5.0',       -- current
        ['oxide-shops'] = '1.3.0',      -- ahead of published (dev build)
        ['oxide-meth'] = '1.5.0',       -- installed but stopped
    },
    stopped = { ['oxide-meth'] = true },
    published = {
        resources = {
            ['oxide-police'] = '1.9.0',
            ['oxide-banking'] = '2.1.0',
            ['oxide-weed'] = '1.5.0',
            ['oxide-shops'] = '1.2.0',
            ['oxide-meth'] = '1.6.0',
            ['oxide-tablet'] = '1.0.0', -- published but not installed here
        },
    },
})
assert(Printed('Updates available for 2 resource(s)'), Lines())
assert(Printed('oxide-banking') and Printed('2.0.1') and Printed('2.1.0'), Lines())
assert(Printed('oxide-police') and Printed('1.8.0') and Printed('1.9.0'), Lines())
assert(not Printed('oxide-weed') and not Printed('oxide-shops'), 'current and ahead are not reported')
assert(not Printed('oxide-meth'), 'a stopped resource is not reported')
assert(not Printed('oxide-tablet'), 'a resource that is not installed is not reported')

-- Alphabetical, so the block reads the same on every server.
local order = Lines():find('oxide%-banking') < Lines():find('oxide%-police')
assert(order, 'resources are listed alphabetically')

-- o-link excludes itself: core/version_check.lua reports it, with a download path.
Run({
    installed = { ['o-link'] = '1.7.0' },
    published = { resources = { ['o-link'] = '1.8.1' } },
})
assert(#output == 0, 'o-link is left to its own updater')

-- A resource with no version metadata cannot be compared, and says nothing.
Run({
    installed = { ['oxide-police'] = nil },
    published = { resources = { ['oxide-police'] = '1.9.0' } },
})
assert(#output == 0, 'a resource with no version metadata is skipped')

-- Every failure path is silent outside debug: an update notice is not worth a
-- scary console block when the check itself is what broke.
Run({
    installed = { ['oxide-police'] = '1.8.0' },
    published = { resources = { ['oxide-police'] = '1.9.0' } },
    code = 404,
})
assert(#output == 0, 'an HTTP failure prints nothing')

Run({
    installed = { ['oxide-police'] = '1.8.0' },
    published = 'not json',
})
assert(#output == 0, 'malformed json prints nothing')

Run({
    installed = { ['oxide-police'] = '1.8.0' },
    published = { notResources = true },
})
assert(#output == 0, 'a version list with no resources table prints nothing')

print = rawprint
print('Catalogue notice passed: outdated only, self and stopped excluded, silent on every failure path.')
