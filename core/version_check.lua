-- Startup update lifecycle. Compares this resource's version against the
-- version field in fxmanifest.lua on the public repo's main branch and, when
-- Config.AutoDownloadUpdates is set, downloads the newer files over o-link's
-- own folder. The owner's config.lua is never overwritten. o-link never
-- restarts anything itself: a resource restart would desync every consumer
-- that snapshotted o-link's exports at boot, so the new files apply only on
-- the next full server restart.

-- Absent, not false, is the common case: the updater never overwrites config.lua,
-- so a customer who installed before this key existed keeps a config without it.
-- Treating absent as off would silence the update notice on exactly the installs
-- that are furthest behind, so only an explicit `false` disables the check.
if Config.CheckForUpdates == false then return end

local RESOURCE = GetCurrentResourceName()
local REPO_OWNER = 'WHEREISDAN'
local REPO_NAME = 'o-link'
local BRANCH = 'main'

local RAW_BASE = ('https://raw.githubusercontent.com/%s/%s/%s/'):format(REPO_OWNER, REPO_NAME, BRANCH)
local MANIFEST_URL = RAW_BASE .. 'fxmanifest.lua'
local TREE_URL = ('https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1'):format(REPO_OWNER, REPO_NAME, BRANCH)
local REPO_URL = ('https://github.com/%s/%s'):format(REPO_OWNER, REPO_NAME)

-- Files that must survive an update untouched (owner-customized, escrow_ignore'd).
local PROTECTED = {
    ['config.lua'] = true,
}

local HEADERS = { ['User-Agent'] = 'o-link-update-check' }

-- "X.Y.Z" -> { X, Y, Z }; missing parts default to 0.
local function parse(version)
    if type(version) ~= 'string' then return nil end
    local parts = {}
    for n in version:gmatch('%d+') do
        parts[#parts + 1] = tonumber(n)
    end
    if #parts == 0 then return nil end
    return parts
end

-- Returns 1 if a > b, -1 if a < b, 0 if equal.
local function compare(a, b)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y and 1 or -1 end
    end
    return 0
end

-- Blocking GET. Returns code, body.
local function httpGet(url)
    local p = promise.new()
    PerformHttpRequest(url, function(code, body)
        p:resolve({ code = code, body = body })
    end, 'GET', '', HEADERS)
    local res = Citizen.Await(p)
    return res.code, res.body
end

-- Enumerate every file on the branch via the git-tree API (one request).
-- Returns a list of repo-relative paths, or nil on failure.
local function listRemoteFiles()
    local code, body = httpGet(TREE_URL)
    if code ~= 200 or not body then
        print(('^1[o-link] Update download aborted: could not list repository files (HTTP %s).^0'):format(tostring(code)))
        return nil
    end

    local ok, tree = pcall(json.decode, body)
    if not ok or type(tree) ~= 'table' or type(tree.tree) ~= 'table' then
        print('^1[o-link] Update download aborted: malformed repository file list.^0')
        return nil
    end

    if tree.truncated then
        print('^1[o-link] Update download aborted: repository file list was truncated by GitHub.^0')
        return nil
    end

    local paths = {}
    for _, node in ipairs(tree.tree) do
        if node.type == 'blob' and node.path and not PROTECTED[node.path] then
            paths[#paths + 1] = node.path
        end
    end
    return paths
end

-- Fetch every path into memory first. Returns a path->content map, or nil if
-- any single file fails (so we never write a partial update over the resource).
local function stageFiles(paths)
    local staged = {}
    for i = 1, #paths do
        local path = paths[i]
        local code, body = httpGet(RAW_BASE .. path)
        if code ~= 200 or not body then
            print(('^1[o-link] Update download aborted at %s (HTTP %s). No files were changed.^0'):format(path, tostring(code)))
            return nil
        end
        staged[path] = body
    end
    return staged
end

-- Order the staged paths so a failed write cannot leave a half-applied install.
-- Brand-new files go first: the running manifest never references them, so if
-- one cannot be written (the updater cannot create folders) nothing in use has
-- changed. Existing files follow, and fxmanifest.lua goes last so the version
-- only advances once every other file is in place.
local function orderPaths(paths)
    local fresh, existing, manifest = {}, {}, nil
    for i = 1, #paths do
        local path = paths[i]
        if path == 'fxmanifest.lua' then
            manifest = path
        elseif LoadResourceFile(RESOURCE, path) then
            existing[#existing + 1] = path
        else
            fresh[#fresh + 1] = path
        end
    end
    table.sort(fresh)
    table.sort(existing)
    if manifest then existing[#existing + 1] = manifest end
    return fresh, existing
end

-- Returns true, or false plus the path that could not be written.
local function writeFiles(staged, paths)
    for i = 1, #paths do
        local path = paths[i]
        local content = staged[path]
        if not SaveResourceFile(RESOURCE, path, content, #content) then
            return false, path
        end
    end
    return true
end

local function applyUpdate(fromVer, toVer)
    print(('^3[o-link] Downloading update %s -> %s ...^0'):format(fromVer, toVer))

    local paths = listRemoteFiles()
    if not paths then return false end

    local staged = stageFiles(paths)
    if not staged then return false end

    local fresh, existing = orderPaths(paths)

    local ok, failed = writeFiles(staged, fresh)
    if not ok then
        print(('^1[o-link] Update %s could not write %s. The updater cannot create new folders, so this release must be installed manually. No file in use was changed.^0'):format(toVer, failed))
        print(('^1[o-link] Download: ^4%s^0'):format(REPO_URL))
        return false
    end

    ok, failed = writeFiles(staged, existing)
    if not ok then
        print(('^1[o-link] Failed writing %s. Update may be incomplete. The version was not advanced, so the update is retried on the next start.^0'):format(failed))
        print(('^1[o-link] If it keeps failing, install it manually: ^4%s^0'):format(REPO_URL))
        return false
    end

    print('^2========================================================^0')
    print(('^2[o-link] Update %s downloaded (%d files written).^0'):format(toVer, #fresh + #existing))
    print('^2[o-link] Restart your server to apply. Do NOT restart o-link alone --^0')
    print('^2[o-link] dependent resources cache its exports and would desync.^0')
    print('^2========================================================^0')

    return true
end

CreateThread(function()
    local localStr = GetResourceMetadata(RESOURCE, 'version', 0)
    local localVer = parse(localStr)
    if not localVer then
        if Config.Debug then
            print('^3[o-link] Update check skipped: local version metadata is missing or malformed.^0')
        end
        return
    end

    local code, body = httpGet(MANIFEST_URL)
    if code ~= 200 or not body then
        if Config.Debug then
            print(('^3[o-link] Update check failed (HTTP %s). Will retry next restart.^0'):format(tostring(code)))
        end
        return
    end

    -- Anchor to the start of a line so this matches the manifest's own `version`
    -- field and not `fx_version`. The leading newline lets it also match when
    -- `version` is the first line.
    local manifest = '\n' .. body
    local remoteStr = manifest:match("\nversion%s+'([^']+)'") or manifest:match('\nversion%s+"([^"]+)"')
    local remoteVer = parse(remoteStr)
    if not remoteVer then
        if Config.Debug then
            print('^3[o-link] Update check failed: could not read remote version.^0')
        end
        return
    end

    local result = compare(remoteVer, localVer)
    if result > 0 then
        if Config.AutoDownloadUpdates then
            applyUpdate(localStr, remoteStr)
        else
            print('^1========================================================^0')
            print(('^1[o-link] An update is available: ^3%s^1 -> ^2%s^0'):format(localStr, remoteStr))
            print(('^1[o-link] Download: ^4%s^0'):format(REPO_URL))
            print('^1========================================================^0')
        end
    elseif result < 0 then
        print(('^3[o-link] Running version %s is ahead of published %s (development build).^0'):format(localStr, remoteStr))
    elseif Config.Debug then
        print(('^2[o-link] Up to date (%s).^0'):format(localStr))
    end
end)
