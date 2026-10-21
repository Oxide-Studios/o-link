local RESOURCE = 'qbx_core'

if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Multichar', RESOURCE, RESOURCE) then return end

local function isStarted()
    return GetResourceState(RESOURCE) == 'started'
end

-- Server -> client -> qbx_core bridges. The server adapter dispatches Create
-- and Select through these because qbx_core's lifecycle is registered as
-- server-side lib.callbacks not reachable from another server VM.

lib.callback.register('o-link:multichar:qbx:create', function(payload)
    if not isStarted() then return { __err = 'qbx_core not started on client' } end
    local ok, result = pcall(function()
        return lib.callback.await('qbx_core:server:createCharacter', false, payload)
    end)
    -- Surface the real failure instead of a bare nil: the caught error text
    -- (e.g. ox_lib's "callback does not exist"), or qbx's silent nil-return
    -- (its createCharacter rejects slot-limit/sanitize failures with no output).
    if not ok then return { __err = tostring(result) } end
    if result == nil then return { __err = 'qbx_core createCharacter returned nil (slot limit, rejected charinfo, or login failure)' } end
    return result
end)

lib.callback.register('o-link:multichar:qbx:select', function(citizenId)
    if not isStarted() then return false end
    local ok, success = pcall(function()
        return lib.callback.await('qbx_core:server:loadCharacter', false, citizenId)
    end)
    return ok and success ~= false
end)

-- Delete is bridged here too. The qbx_core DeleteCharacter export is
-- ForceDeleteCharacter, which runs the delete in a detached thread and returns
-- before the transaction commits — so the deleting player's character lingers
-- in the selection menu until relog. qbx_core:server:deleteCharacter awaits the
-- transaction synchronously, so routing through it makes Delete actually
-- complete before we report success.
lib.callback.register('o-link:multichar:qbx:delete', function(citizenId)
    if not isStarted() then return false end
    local ok, success = pcall(function()
        return lib.callback.await('qbx_core:server:deleteCharacter', false, citizenId)
    end)
    return ok and success ~= false
end)

olink._register('multichar', {
    GetResourceName = function() return RESOURCE end,

    -- Post-creation onboarding. If qbx_apartments is installed, hand off to it
    -- (it natively triggers qb-clothes:client:CreateFirstCharacter when the
    -- apartment is confirmed, AND fires OnPlayerLoaded). Otherwise we fire the
    -- OnPlayerLoaded pair (server + client) then open the appearance creator —
    -- mirroring native spawnDefault(), which sends both. Only ever send the pair
    -- from our own spawn paths, never from a Client:OnPlayerLoaded listener
    -- (qb-style cores echo Server:OnPlayerLoaded back down — a listener-based
    -- re-emit feeds that echo and ping-pongs forever).
    OnboardNewCharacter = function(charId, opts, onDone)
        local gender = opts and opts.gender or 0

        if GetResourceState('qbx_apartments') == 'started' then
            TriggerEvent('apartments:client:setupSpawnUI', charId)
            if onDone then onDone(true) end
            return
        end

        TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
        TriggerEvent('QBCore:Client:OnPlayerLoaded')

        if olink.clothing and olink.clothing.StartCreation then
            olink.clothing.StartCreation(gender, onDone)
        elseif onDone then
            onDone(true)
        end
    end,

    -- Existing-character spawn. With the selector enabled and a spawn/apartments
    -- resource present, hand off to the framework's native spawn UI (it owns the
    -- teleport, screen, and OnPlayerLoaded). Returning true tells oxide-multichar
    -- to stop. Otherwise we fire the OnPlayerLoaded pair and return false so
    -- oxide does its default teleport + appearance apply.
    ---@return boolean handled
    SpawnCharacter = function(charId, position, useSelector)
        if useSelector and GetResourceState('qbx_apartments') == 'started' then
            TriggerEvent('apartments:client:setupSpawnUI', charId)
            return true
        end
        if useSelector and GetResourceState('qbx_spawn') == 'started' then
            TriggerEvent('qb-spawn:client:setupSpawns', charId)
            TriggerEvent('qb-spawn:client:openUI', true)
            return true
        end

        TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
        TriggerEvent('QBCore:Client:OnPlayerLoaded')
        return false
    end,
})

-- Bridge QBX's "return to selection" client event to the unified start event
-- the multichar resource listens on. Fires after Logout() or a kicked session.
RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    TriggerEvent('olink:client:startCharacterSelect')
end)

RegisterNetEvent('o-link:multichar:startSelect', function()
    TriggerEvent('olink:client:startCharacterSelect')
end)

-- Replaces qbx_core's native boot trigger (we comment out the chooseCharacter()
-- call in qbx_core/client/character.lua to disable the native selection menu).
-- Same wait pattern QBX used: hold until the session is live, disable auto-spawn,
-- dismiss the loadscreen, then hand off to oxide-multichar.
--
-- QBX ships the [standalone]/loadscreen resource with `loadscreen:externalShutdown
-- true` set in server.cfg, which keeps the screen up indefinitely until an
-- explicit Shutdown* call. Native chooseCharacter() did this after the tutorial
-- session started; we do it here so the player isn't stranded on "You will be
-- loaded in any moment now..." while oxide-multichar's Selection.Open streams
-- IPLs (a stream that won't progress until the loadscreen is dismissed).
--
-- Only with oxide-multichar on the server. Any other character screen (qbx_core's
-- own, or an external one with useExternalCharacters) boots itself and owns the
-- loadscreen and spawnmanager.
CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(0) end
    if GetResourceState('oxide-multichar') == 'missing' then return end
    pcall(function() exports.spawnmanager:setAutoSpawn(false) end)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    Wait(250)
    TriggerEvent('olink:client:startCharacterSelect')
end)
