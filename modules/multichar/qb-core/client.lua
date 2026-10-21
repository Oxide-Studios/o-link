local RESOURCE = 'qb-core'

if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Multichar', RESOURCE, RESOURCE) then return end

olink._register('multichar', {
    GetResourceName = function() return RESOURCE end,

    -- Post-creation onboarding. If qb-apartments is installed, hand off to it
    -- (it natively triggers qb-clothes:client:CreateFirstCharacter on submit,
    -- AND fires OnPlayerLoaded). Otherwise we fire the OnPlayerLoaded pair
    -- (server + client, like native qb-multicharacter) then open the appearance
    -- creator. The pair must only ever be sent from our own spawn paths — qb-core
    -- answers Server:OnPlayerLoaded with a net Client:OnPlayerLoaded, so emitting
    -- it from a Client:OnPlayerLoaded listener feeds back into that echo and
    -- ping-pongs forever.
    OnboardNewCharacter = function(charId, opts, onDone)
        local gender = opts and opts.gender or 0

        if GetResourceState('qb-apartments') == 'started' then
            TriggerEvent('apartments:client:setupSpawnUI', { citizenid = charId })
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
        if useSelector and GetResourceState('qb-apartments') == 'started' then
            TriggerEvent('apartments:client:setupSpawnUI', { citizenid = charId })
            return true
        end
        if useSelector and GetResourceState('qb-spawn') == 'started' then
            TriggerEvent('qb-spawn:client:setupSpawns', { citizenid = charId }, false, nil)
            TriggerEvent('qb-spawn:client:openUI', true)
            return true
        end

        TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
        TriggerEvent('QBCore:Client:OnPlayerLoaded')
        return false
    end,
})

-- Bridge qb-multicharacter's "return to selection" client event (only fires if
-- the customer kept that resource installed; harmless when it's disabled) and
-- o-link's generic start event to the unified event the multichar resource
-- listens on.
RegisterNetEvent('qb-multicharacter:client:chooseChar', function()
    TriggerEvent('olink:client:startCharacterSelect')
end)

RegisterNetEvent('o-link:multichar:startSelect', function()
    TriggerEvent('olink:client:startCharacterSelect')
end)

-- Replaces qb-multicharacter's boot trigger (its server-side playerConnecting
-- handler natively fires qb-multicharacter:client:chooseChar, which we no
-- longer get because customers disable that resource). Mirrors QBX's pattern:
-- wait for session, disable auto-spawn, dismiss the loadscreen explicitly
-- (qb-loadingscreen and most QB-era loadscreens also wait for external
-- shutdown), then hand off to oxide-multichar. Only with oxide-multichar on the
-- server: qb-multicharacter or any other character screen boots itself and owns
-- the loadscreen and spawnmanager.
CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(0) end
    if GetResourceState('oxide-multichar') == 'missing' then return end
    pcall(function() exports.spawnmanager:setAutoSpawn(false) end)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    Wait(250)
    TriggerEvent('olink:client:startCharacterSelect')
end)
