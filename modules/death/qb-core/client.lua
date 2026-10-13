if not olink._guardImpl('Death', 'qb-core', 'qb-core') then return end
if not olink._hasOverride('Death') and GetResourceState('qbx_core') == 'started' then return end
if not olink._hasOverride('Death') and GetResourceState('oxide-death') == 'started' then return end

local QBCore = exports['qb-core']:GetCoreObject()

olink._register('death', {
    ---@return boolean
    IsPlayerDowned = function()
        local data = QBCore.Functions.GetPlayerData()
        if not data or not data.metadata then return false end
        return data.metadata.inlaststand == true
    end,

    ---@return boolean
    IsPlayerDead = function()
        local data = QBCore.Functions.GetPlayerData()
        if not data or not data.metadata then return false end
        return data.metadata.isdead == true
    end,

    ---@return table|nil
    GetDeathState = function()
        local data = QBCore.Functions.GetPlayerData()
        if not data or not data.metadata then return nil end
        local state = 'alive'
        if data.metadata.isdead then state = 'dead'
        elseif data.metadata.inlaststand then state = 'downed' end
        return { state = state }
    end,
})

local function deriveState(meta)
    if not meta then return 'alive' end
    if meta.isdead then return 'dead' end
    if meta.inlaststand then return 'downed' end
    return 'alive'
end

local lastState = deriveState((QBCore.Functions.GetPlayerData() or {}).metadata)

local function transitionTo(newState)
    if newState == lastState then return end
    local oldState = lastState
    lastState = newState

    if newState == 'dead' then
        TriggerEvent('olink:client:playerDied', {})
    elseif newState == 'downed' then
        TriggerEvent('olink:client:playerDowned', {})
    elseif newState == 'alive' then
        TriggerEvent('olink:client:playerRevived', {})
    end
    TriggerEvent('olink:client:playerDeathStateChanged', newState, oldState, {})
end

-- Current qb-core pushes metadata edits as a single field; older builds resend the whole PlayerData.
RegisterNetEvent('QBCore:Player:UpdatePlayerDataField', function(key, value)
    if key == 'metadata' then transitionTo(deriveState(value)) end
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(playerData)
    transitionTo(deriveState(playerData and playerData.metadata))
end)
