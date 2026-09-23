-- Update notice for the rest of the catalogue. core/version_check.lua only knows
-- o-link, which leaves every paid resource silent: those ship through the Cfx.re
-- Portal, so there is no repository for a server to compare itself against. The
-- published version list fills that gap, and one request covers every installed
-- resource at once rather than each one polling on its own.
--
-- Notice only. Escrowed assets cannot be self-updated the way o-link can, so
-- there is nothing to download here.

if Config.CheckForUpdates == false then return end

local VERSIONS_URL = 'https://raw.githubusercontent.com/Oxide-Studios/oxide-versions/main/versions.json'
local PORTAL_URL = 'https://portal.cfx.re'
local SELF = GetCurrentResourceName()

-- Seconds of quiet after the last resource start before the catalogue is read.
-- o-link boots early by design, so most resources are still 'starting' when this
-- file runs; checking immediately would report versions for a half-booted server.
local SETTLE_SECONDS = 10

local lastStart = os.time()

AddEventHandler('onServerResourceStart', function()
    lastStart = os.time()
end)

local function startedResources()
    local started = {}
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name and GetResourceState(name) == 'started' then
            started[name] = true
        end
    end
    return started
end

local function fetchPublished()
    local code, body = olink._update.httpGet(VERSIONS_URL)
    if code ~= 200 or not body then
        if Config.Debug then
            print(('^3[o-link] Catalogue update check failed (HTTP %s). Will retry next restart.^0'):format(tostring(code)))
        end
        return nil
    end

    local ok, data = pcall(json.decode, body)
    if not ok or type(data) ~= 'table' or type(data.resources) ~= 'table' then
        if Config.Debug then
            print('^3[o-link] Catalogue update check failed: malformed version list.^0')
        end
        return nil
    end

    return data.resources
end

local function report(outdated)
    table.sort(outdated, function(a, b) return a.resource < b.resource end)

    local width = 0
    for i = 1, #outdated do
        if #outdated[i].resource > width then width = #outdated[i].resource end
    end

    print('^1========================================================^0')
    print(('^1[Oxide] Updates available for %d resource(s):^0'):format(#outdated))
    for i = 1, #outdated do
        local entry = outdated[i]
        local padding = string.rep(' ', width - #entry.resource)
        print(('^1  %s%s  ^3%s^1  ->  ^2%s^0'):format(entry.resource, padding, entry.installed, entry.published))
    end
    print(('^1[Oxide] Download from your Cfx.re account: ^4%s^0'):format(PORTAL_URL))
    print('^1========================================================^0')
end

CreateThread(function()
    while os.time() - lastStart < SETTLE_SECONDS do
        Wait(1000)
    end

    local published = fetchPublished()
    if not published then return end

    local started = startedResources()
    local outdated, checked, ahead = {}, 0, 0

    for resource, version in pairs(published) do
        -- o-link checks itself, with a download path this notice does not have.
        if resource ~= SELF and started[resource] then
            local installedStr = GetResourceMetadata(resource, 'version', 0)
            local installed = olink._update.parse(installedStr)
            local remote = olink._update.parse(version)

            if installed and remote then
                checked = checked + 1
                local result = olink._update.compare(remote, installed)
                if result > 0 then
                    outdated[#outdated + 1] = {
                        resource = resource,
                        installed = installedStr,
                        published = version,
                    }
                elseif result < 0 then
                    ahead = ahead + 1
                end
            end
        end
    end

    if #outdated > 0 then
        report(outdated)
    elseif Config.Debug then
        print(('^2[o-link] Catalogue up to date (%d resource(s) checked, %d ahead of published).^0'):format(checked, ahead))
    end
end)
