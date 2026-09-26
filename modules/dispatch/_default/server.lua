-- Default dispatch fallback.
-- Only loads when no dedicated dispatch resource is running.
-- Relays alerts to job members via notifications.

local DEDICATED = {
    'oxide-dispatch', 'ps-dispatch', 'cd_dispatch', 'lb-tablet', 'bub-mdt', 'emergencydispatch',
    'qs_dispatch', 'tk_dispatch', 'fd_dispatch', 'kartik-mdt', 'linden_outlawalert', 'origen_police',
    'piotreq_gpt', 'redutzu-mdt', 'wasabi_mdt',
}

local function dedicatedRunning()
    if olink._hasOverride('Dispatch') then return false end
    for _, name in ipairs(DEDICATED) do
        if GetResourceState(name) == 'started' then return true end
    end
    return false
end

if not olink._guardImpl('Dispatch', '_default', false) then return end
if dedicatedRunning() then return end

---@return number recipients
local function broadcast(data)
    local recipients = 0
    local jobs = type(data.jobs) == 'table' and data.jobs or { data.jobs or 'police' }
    for i = 1, math.min(#jobs, 5) do
        local jobName = jobs[i]
        if type(jobName) == 'string' and olink.job then
            local members = olink.job.GetPlayersWithJob(jobName)
            for _, target in ipairs(members or {}) do
                TriggerClientEvent('o-link:dispatch:default:alert', target, data)
                recipients = recipients + 1
            end
        end
    end
    return recipients
end

olink._register('dispatch', {
    GetResourceName = function() return '_default' end,

    ---Server-authored alert. The caller's coords are trusted here, unlike the client event, which
    ---pins every alert to the sender's ped. A dispatch resource that started after o-link owns the
    ---client side, so this returns nil and the caller relays through its SendAlert instead.
    ---@param data table same shape as the client SendAlert
    ---@return table|nil { recipients = number }
    CreateAlert = function(data)
        if dedicatedRunning() then return nil end
        local c = type(data) == 'table' and data.coords
        if not (c and tonumber(c.x) and tonumber(c.y) and tonumber(c.z)) then return nil end
        local blip = type(data.blipData) == 'table' and data.blipData or {}
        return { recipients = broadcast({
            sprite    = blip.sprite or 161,
            color     = blip.color or 84,
            scale     = blip.scale or 1.0,
            coords    = vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0),
            message   = data.message or 'Alert',
            code      = data.code or '10-80',
            icon      = data.icon or 'fas fa-question',
            jobs      = data.jobs or { 'police' },
            time      = data.time or 30000,
            blipData  = data.blipData,
        }) }
    end,
})

local lastAlert = {}

RegisterNetEvent('o-link:dispatch:default:sendAlert', function(data)
    local src = source
    if not src or not GetPlayerPing(src) then return end

    local now = GetGameTimer()
    if lastAlert[src] and (now - lastAlert[src]) < 5000 then return end
    lastAlert[src] = now

    -- Inject server-authoritative coords
    local ped = GetPlayerPed(src)
    if ped and ped > 0 then
        data.coords = GetEntityCoords(ped)
    end

    broadcast(data)
end)

AddEventHandler('playerDropped', function()
    lastAlert[source] = nil
end)
