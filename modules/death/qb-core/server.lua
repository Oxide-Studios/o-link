if not olink._guardImpl('Death', 'qb-core', 'qb-core') then return end
if not olink._hasOverride('Death') and GetResourceState('qbx_core') == 'started' then return end
if not olink._hasOverride('Death') and GetResourceState('oxide-death') == 'started' then return end

local QBCore = exports['qb-core']:GetCoreObject()

olink._register('death', {
    ---@param src number
    ---@return boolean
    IsPlayerDowned = function(src)
        local p = QBCore.Functions.GetPlayer(src)
        if not p then return false end
        return p.PlayerData.metadata.inlaststand == true
    end,

    ---@param src number
    ---@return boolean
    IsPlayerDead = function(src)
        local p = QBCore.Functions.GetPlayer(src)
        if not p then return false end
        return p.PlayerData.metadata.isdead == true
    end,

    ---@param src number
    ---@return table|nil
    GetDeathState = function(src)
        local p = QBCore.Functions.GetPlayer(src)
        if not p then return nil end
        local meta = p.PlayerData.metadata
        local state = 'alive'
        if meta.isdead then state = 'dead'
        elseif meta.inlaststand then state = 'downed' end
        return { state = state }
    end,

    ---@param src number
    ---@param reviverSrc number|nil
    ---@return boolean
    RevivePlayer = function(src, reviverSrc)
        local p = QBCore.Functions.GetPlayer(src)
        if not p then return false end
        p.Functions.SetMetaData('isdead', false)
        p.Functions.SetMetaData('inlaststand', false)
        TriggerClientEvent('hospital:client:Revive', src)
        return true
    end,

    ---@param src number
    ---@param cause string|nil
    ---@return boolean
    KillPlayer = function(src, cause)
        local p = QBCore.Functions.GetPlayer(src)
        if not p then return false end
        p.Functions.SetMetaData('isdead', true)
        p.Functions.SetMetaData('inlaststand', false)
        TriggerClientEvent('hospital:client:KillPlayer', src)
        return true
    end,

    ---@param src number
    ---@param coords vector4|nil
    ---@return boolean
    RespawnPlayer = function(src, coords)
        local p = QBCore.Functions.GetPlayer(src)
        if not p then return false end
        p.Functions.SetMetaData('isdead', false)
        p.Functions.SetMetaData('inlaststand', false)
        if coords then
            SetEntityCoords(GetPlayerPed(src), coords.x, coords.y, coords.z)
            if coords.w then SetEntityHeading(GetPlayerPed(src), coords.w) end
        end
        TriggerClientEvent('hospital:client:Revive', src)
        return true
    end,

    ---@param src number
    ---@param cause string|nil
    ---@param coords vector3|nil
    ---@param heading number|nil
    ---@return boolean
    DownPlayer = function(src, cause, coords, heading)
        local p = QBCore.Functions.GetPlayer(src)
        if not p then return false end
        p.Functions.SetMetaData('inlaststand', true)
        TriggerClientEvent('hospital:client:SetLaststand', src)
        return true
    end,
})

local function deriveState(meta)
    if meta.isdead then return 'dead' end
    if meta.inlaststand then return 'downed' end
    return 'alive'
end

local lastState = {}
local pushes = {}   -- src -> count of metadata reads, so a later read cancels a waiting 'alive'
local reading = {}  -- src -> true while a read is queued for the next tick
local reports = {}  -- src -> { count, windowStart } for the rate limit

-- When a downed player bleeds out, qb-ambulancejob clears last stand and then sets isdead in two
-- separate events, so the 'alive' between them is not real. An 'alive' straight after 'downed'
-- waits briefly, and any read that comes meanwhile replaces it.
local SETTLE_MS = 500

-- qb-ambulancejob's normal flow sends two of these per state change.
local REPORT_WINDOW_MS = 10000
local REPORT_LIMIT = 20

local function emitTransition(src, newState)
    local oldState = lastState[src] or 'alive'
    if newState == oldState then return end
    lastState[src] = newState

    if newState == 'dead' then
        TriggerEvent('olink:server:playerDied', src, {})
    elseif newState == 'downed' then
        TriggerEvent('olink:server:playerDowned', src, {})
    elseif newState == 'alive' then
        TriggerEvent('olink:server:playerRevived', src, {})
    end
    TriggerEvent('olink:server:playerDeathStateChanged', src, newState, oldState, {})
end

local function metadataOf(src)
    local p = QBCore.Functions.GetPlayer(src)
    local meta = p and p.PlayerData and p.PlayerData.metadata
    return type(meta) == 'table' and meta or nil
end

local function observe(src)
    local meta = metadataOf(src)
    if not meta then return end
    pushes[src] = (pushes[src] or 0) + 1
    local newState = deriveState(meta)
    if newState == 'alive' and (lastState[src] or 'alive') == 'downed' then
        local push = pushes[src]
        SetTimeout(SETTLE_MS, function()
            if pushes[src] ~= push then return end
            local now = metadataOf(src)
            if now then emitTransition(src, deriveState(now)) end
        end)
        return
    end
    emitTransition(src, newState)
end

local function withinLimit(src)
    local now = GetGameTimer()
    local entry = reports[src]
    if not entry or now - entry.windowStart >= REPORT_WINDOW_MS then
        reports[src] = { count = 1, windowStart = now }
        return true
    end
    entry.count = entry.count + 1
    return entry.count <= REPORT_LIMIT
end

-- The two hospital events come from the player's own client, so they can only ever be about the
-- sender, and their argument is never trusted. Once every handler of the event has run (the
-- ambulance resource writes isdead / inlaststand from it), the relay reads the sender's metadata,
-- the same data IsPlayerDead and IsPlayerDowned read, and reports what actually changed. Reads
-- are queued once per player per tick and capped per player.
local function onHospitalReport()
    local src = tonumber(source)
    if not src or src <= 0 or reading[src] then return end
    if not QBCore.Functions.GetPlayer(src) then return end
    if not withinLimit(src) then return end
    reading[src] = true
    SetTimeout(0, function()
        reading[src] = nil
        observe(src)
    end)
end

RegisterNetEvent('hospital:server:SetDeathStatus', onHospitalReport)
RegisterNetEvent('hospital:server:SetLaststandStatus', onHospitalReport)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    lastState[src], pushes[src], reading[src], reports[src] = nil, nil, nil, nil
end)
